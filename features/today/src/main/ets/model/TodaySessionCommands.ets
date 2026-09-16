import { OpenRecordInfo, MatterItemModel, MatterItemModelInit, MatterStatus, RDBStoreUtil, TimeRecord, TimeRecordUtil } from 'base';
import type { SessionCommands } from 'base';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { todayActivityService, StopTimeRecordResult } from './TodayActivityService';
import { resolveDueAutoStopForcedEndTime, migrateAutoStopRunningSnapshotAfterSplit } from './AutoStopSettings';

const TAG: string = 'TodaySessionCommands';

/**
 * SessionCommands 的 today 侧实现（Phase 2）：
 * 适配 TodayActivityService 的 start/stop/查询能力，注册进 base 的 recordingSessionStore。
 */
export class TodaySessionCommands implements SessionCommands {
  async startSession(itemId: string): Promise<OpenRecordInfo> {
    const recordId = await todayActivityService.startTimeRecord(itemId);
    if (!recordId || recordId.trim() === '') {
      throw new Error(`startTimeRecord failed for ${itemId}`);
    }

    const record = await todayActivityService.getTimeRecordById(recordId);
    if (!record || record.activityId !== itemId || record.endTime) {
      throw new Error(`startTimeRecord verification failed for ${itemId}, recordId=${recordId}`);
    }

    const item = await this.findMatterItem(itemId);
    return this.buildOpenRecord(record as TimeRecord, item);
  }

  /**
   * 结束会话（Phase 2c-2）。store 传入快照 recordId，本命令按序负责：
   * 1) 自动停止到点 → 以持久化快照限时的 forced endTime 落库（承接旧 stop() 预检语义）；
   * 2) 跨天记录 → 先拆分并迁移自动停止快照，再停止当日尾记录；
   * 3) 其余 → stopTimeRecordDetailed 幂等停止。
   */
  async stopSession(itemId: string, recordId: string): Promise<void> {
    const record = await todayActivityService.getTimeRecordById(recordId);
    if (!record || record.activityId !== itemId || record.endTime) {
      // 记录缺失/易主/已结束：交由幂等停止路径给出终态判定
      const settledResult = await todayActivityService.stopTimeRecordDetailed(itemId, recordId);
      this.assertStopSucceeded(itemId, recordId, settledResult);
      return;
    }

    const activeRecord = record as TimeRecord;

    const forcedEndTimeMs = resolveDueAutoStopForcedEndTime(itemId, activeRecord.id, activeRecord.startTime);
    if (forcedEndTimeMs !== null) {
      const forcedResult = await todayActivityService.stopTimeRecordAtDetailed(itemId, activeRecord.id, forcedEndTimeMs);
      this.assertStopSucceeded(itemId, activeRecord.id, forcedResult);
      return;
    }

    let effectiveRecordId: string = activeRecord.id;
    if (activeRecord.startTime < TimeRecordUtil.getDayStart(Date.now())) {
      hilog.info(0x0000, TAG, `stopSession 检测到跨日记录，准备拆分: ${activeRecord.id}`);
      const splitRecord = await todayActivityService.splitTimeRecordAtBoundaries(activeRecord.id, Date.now());
      if (splitRecord) {
        migrateAutoStopRunningSnapshotAfterSplit(activeRecord, splitRecord, 'TodaySessionCommands.stopSession');
        effectiveRecordId = splitRecord.id;
      } else {
        hilog.warn(0x0000, TAG, `跨日拆分失败，继续停止原记录: ${activeRecord.id}`);
      }
    }

    const result = await todayActivityService.stopTimeRecordDetailed(itemId, effectiveRecordId);
    this.assertStopSucceeded(itemId, effectiveRecordId, result);
  }

  private assertStopSucceeded(itemId: string, recordId: string, result: StopTimeRecordResult): void {
    if (result === StopTimeRecordResult.FAILED || result === StopTimeRecordResult.RECORD_MISMATCH) {
      throw new Error(`stopTimeRecord failed for ${itemId}, recordId=${recordId}, result=${result}`);
    }
    // STOPPED_NOW / ALREADY_STOPPED / NO_OPEN_RECORD 均视为已达终态（幂等成功）
  }

  async queryOpenRecord(itemId: string): Promise<OpenRecordInfo | null> {
    const record = await todayActivityService.queryLatestTimeRecord(itemId);
    if (!record || record.endTime) {
      return null;
    }
    const item = await this.findMatterItem(itemId);
    return this.buildOpenRecord(record as TimeRecord, item);
  }

  /**
   * 全局查询最新未结束记录（store.restoreFromDb 唯一恢复数据源）。
   * 顺带对账 activity 状态：有活跃记录的置 RECORDING，无记录却 RECORDING 的回落 PAUSED
   * （语义承接原 TimerStateManager.restoreStateFromDatabase）。
   */
  async queryNewestOpenRecord(): Promise<OpenRecordInfo | null> {
    const allMatters = await todayActivityService.getTodayMatterItems();
    const rdbStoreUtil = RDBStoreUtil.getInstance();

    let candidate: OpenRecordInfo | null = null;
    let activeRecordCount = 0;

    for (const matter of allMatters) {
      const latestRecord = await todayActivityService.queryLatestTimeRecord(matter.id);
      const hasActiveRecord = latestRecord !== null && !latestRecord.endTime;

      if (hasActiveRecord && latestRecord) {
        activeRecordCount += 1;
        if (matter.status !== MatterStatus.RECORDING) {
          hilog.info(0x0000, TAG, `queryNewest: activity ${matter.id} -> RECORDING to match open record`);
          await rdbStoreUtil.updateActivityStatus(matter.id, MatterStatus.RECORDING);
        }
        if (candidate === null || latestRecord.startTime > candidate.startTime) {
          candidate = this.buildOpenRecord(latestRecord as TimeRecord, matter);
        }
      } else if (!hasActiveRecord && matter.status === MatterStatus.RECORDING) {
        hilog.warn(0x0000, TAG, `queryNewest: activity ${matter.id} RECORDING without open record, fallback PAUSED`);
        await rdbStoreUtil.updateActivityStatus(matter.id, MatterStatus.PAUSED);
      }
    }

    if (activeRecordCount > 1) {
      hilog.warn(0x0000, TAG, `queryNewest: multiple (${activeRecordCount}) open records, picking the newest`);
    }
    return candidate;
  }

  private buildOpenRecord(record: TimeRecord, item: MatterItemModel | null): OpenRecordInfo {
    const info = new OpenRecordInfo();
    info.itemId = record.activityId;
    info.recordId = record.id;
    info.startTime = record.startTime;
    info.title = item ? item.title : '';
    const rawColor: ResourceColor | undefined = item ? item.labelColor : undefined;
    info.color = typeof rawColor === 'string' ? rawColor : '';
    return info;
  }

  /**
   * 解析事项的展示元数据（title/color）。
   * 先查 AppStorage 集合（常规路径，同步可得）；
   * FanItem 快速开录等场景下事项尚未进集合，回退 DB（tagId 已落库，join 带出 tagColorHex），
   * 避免快照 color 为空导致 TextTimer/投影丢失 tag 颜色。
   */
  private async findMatterItem(itemId: string): Promise<MatterItemModel | null> {
    const todoRaw = AppStorage.get('unDoMatterData') as (MatterItemModel | MatterItemModelInit)[] | undefined;
    const doneRaw = AppStorage.get('doneMatterData') as (MatterItemModel | MatterItemModelInit)[] | undefined;
    const todoList = todoRaw ? MatterItemModel.ensureList(todoRaw) : [];
    const doneList = doneRaw ? MatterItemModel.ensureList(doneRaw) : [];

    for (const matter of todoList) {
      if (matter.id === itemId) {
        return matter;
      }
    }
    for (const matter of doneList) {
      if (matter.id === itemId) {
        return matter;
      }
    }
    return todayActivityService.getTodayMatterItemById(itemId);
  }
}
