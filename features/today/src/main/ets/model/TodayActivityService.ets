import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  TodayActivityItem,
  RDBStoreUtil,
  MatterStatus,
  TimeRecord,
  TimeRecordUtil,
  calendarSyncService,
  FilesDirCarrier,
  computeFileHashFromUri,
  relPathToImageUri,
  resolveStoredPath,
  savePickerUriToSandboxFiles,
  guessMimeTypeFromUri,
  deleteStoredFileBestEffort
} from 'base';
import { TagItem } from 'base/src/main/ets/common/model/TagItem';
import { MatterItemModel } from 'base';
import fs from '@ohos.file.fs';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG: string = 'TodayActivityService';
const CALENDAR_SYNC_ENABLED_APP_STORAGE_KEY: string = 'calendarSyncEnabled';

export enum StopTimeRecordResult {
  STOPPED_NOW = 'stopped_now',
  ALREADY_STOPPED = 'already_stopped',
  NO_OPEN_RECORD = 'no_open_record',
  RECORD_MISMATCH = 'record_mismatch',
  FAILED = 'failed'
}

interface ErrorLike {
  code?: number;
  message?: string;
}

export interface ActivityCoverImageResult {
  relPath: string;
  imageUri: string;
}

interface PendingCalendarUpsertTask {
  recordId: string;
  source: string;
}

/**
 * 提供用于管理"今日活动"的业务逻辑。
 * 该服务层位于 UI/ViewModel 和数据访问层 (RDBStoreUtil) 之间。
 */
export class TodayActivityService {
  private pendingCalendarUpsertQueue: PendingCalendarUpsertTask[] = [];
  private pendingCalendarUpsertIds: Set<string> = new Set<string>();
  private isDrainingCalendarUpsertQueue: boolean = false;
  private activeCalendarUpsertRecordId: string = '';
  private deletePreferredRecordIds: Set<string> = new Set<string>();
  private activityOperationQueues: Map<string, Promise<void>> = new Map<string, Promise<void>>();

  /**
   * 创建一个新活动并将其添加到"今日清单"。
   * 它通过 RDBStoreUtil 处理与数据库的交互。
   *
   * @param name 新活动的名称 (例如, "阅读一本书")。
   * @param tagId 与此活动关联的现有标签的唯一标识符，如果没有标签则为 null。
   * @returns 一个 Promise，如果成功，则解析为新创建活动的 MatterItemModel；否则解析为 null。
   */
  async createNewTodayActivity(
    name: string,
    tagId: string | null,
    suppressSyncPush: boolean = false
  ): Promise<MatterItemModel | null> {
    // 基础校验：确保活动名称不为空
    if (!name || name.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法创建名称为空的活动。');
      return null;
    }

    hilog.info(0x0000, TAG, `尝试创建新的今日活动: '${name}'，标签ID为: ${tagId}`);

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();

      // 生成唯一ID
      const activityId = this.generateUniqueId();

      // 插入活动，状态为0表示TODO状态
      const rowId = await rdbStoreUtil.insertActivity(activityId, name.trim(), tagId, 0, suppressSyncPush);
      
      if (rowId > 0) {
        hilog.info(0x0000, TAG, `成功创建新的今日活动，ID为: ${activityId}`);
        
        // 获取刚创建的活动详情并转换为MatterItemModel
        const createdActivity = await this.getTodayMatterItemById(activityId);
        return createdActivity;
      } else {
        hilog.error(0x0000, TAG, '创建新的今日活动失败，返回的 rowId 无效。');
        return null;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `创建今日活动时发生意外错误: ${JSON.stringify(error)}`);
      return null;
    }
  }

  /**
   * 从数据库获取所有"今日活动"，并将其转换为UI所需的 MatterItemModel 列表。
   * 
   * CARRY-OVER BEHAVIOR:
   * - TODO (status=0) items will persist across days and always appear in the list
   *   until they are marked as completed (PAUSED/RECORDING) or archived
   * - This ensures undone tasks from previous days remain visible and actionable
   * - RECORDING (status=1) and PAUSED (status=2) items require either:
   *   a) Creation date is today OR
   *   b) Has time records associated with today
   * 
   * @returns 一个 Promise，解析为一个包含 MatterItemModel 对象的数组。
   */
  async getTodayMatterItems(): Promise<MatterItemModel[]> {
    hilog.info(0x0000, TAG, 'Fetching and preparing matter items for the UI (with carry-over for TODO items).');

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();

      // 步骤 1: 从数据库获取原始活动数据
      const todayActivities: TodayActivityItem[] = await rdbStoreUtil.queryAllTodayActivities();

      if (!todayActivities || todayActivities.length === 0) {
        hilog.info(0x0000, TAG, 'No activities found for today.');
        return [];
      }

      // 步骤 2: 将数据库模型 (TodayActivityItem) 映射到视图模型 (MatterItemModel)
      const matterItems: MatterItemModel[] = await Promise.all(todayActivities.map(async (activity) => {
        // 颜色处理：提供默认颜色
        const labelColor: string = activity.tagColorHex || '#808080';

        // 从 time_record 表计算今日总时长
        const totalDuration = await rdbStoreUtil.queryTodayTotalDuration(activity.id);
        
        // 查询活动的实际状态，基于 time_record 表
        const activityStatus: number = activity.status;
        
        // 检查状态一致性 - 查询最新的时间记录
        const latestRecord = await rdbStoreUtil.queryLatestTimeRecord(activity.id);
        const hasActiveRecord = latestRecord && !latestRecord.endTime;
        
        // 检查状态不一致情况
        if (activityStatus === MatterStatus.RECORDING && !hasActiveRecord) {
          hilog.warn(0x0000, TAG, `STATUS INCONSISTENCY: Activity ${activity.id} has status RECORDING but no active time record`);
        } else if (activityStatus !== MatterStatus.RECORDING && hasActiveRecord) {
          hilog.warn(0x0000, TAG, `STATUS INCONSISTENCY: Activity ${activity.id} has active time record but status is ${activityStatus}`);
        }
        
        // 将数据库状态转换为 MatterStatus 枚举
        let status: MatterStatus;
        switch (activityStatus) {
          case 0:
            status = MatterStatus.TODO;
            break;
          case 1:
            status = MatterStatus.RECORDING;
            break;
          case 2:
            status = MatterStatus.PAUSED;
            break;
          default:
            status = MatterStatus.TODO;
            break;
        }
        
        // 创建并返回 MatterItemModel 对象
        const matterItem = new MatterItemModel({
          id: activity.id,
          title: activity.name,
          label: activity.tagName || '无标签',
          labelColor: labelColor,
          status: status,
          durationInMilliseconds: totalDuration,
        });
        return matterItem;
      }));

      hilog.info(0x0000, TAG, `Successfully prepared ${matterItems.length} matter items.`);
      return matterItems;
    } catch (error) {
      hilog.error(0x0000, TAG, `获取今日活动时发生错误: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /**
   * 根据ID获取单个今日活动，并将其转换为 MatterItemModel。
   *
   * @param activityId 活动的唯一标识符
   * @returns 一个 Promise，如果成功，则解析为 MatterItemModel 对象；否则解析为 null。
   */
  async getTodayMatterItemById(activityId: string): Promise<MatterItemModel | null> {
      hilog.info(0x0000, TAG, `Fetching matter item by ID: ${activityId}`)
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();

      // 步骤 1: 从数据库查询单个活动
      const activity: TodayActivityItem | null = await rdbStoreUtil.queryActivityById(activityId);

      if (!activity) {
        hilog.warn(0x0000, TAG, `No activity found with ID: ${activityId}`);
        return null;
      }

      // 步骤 2: 将数据库模型 (TodayActivityItem) 映射到视图模型 (MatterItemModel)
      // 颜色处理：提供默认颜色
      const labelColor: string = activity.tagColorHex || '#808080';

      // 从 time_record 表计算今日总时长
      const totalDuration = await rdbStoreUtil.queryTodayTotalDuration(activity.id);

      // 查询活动的实际状态，基于 time_record 表
      const activityStatus: number = activity.status;

      // 检查状态一致性 - 查询最新的时间记录
      const latestRecord = await rdbStoreUtil.queryLatestTimeRecord(activity.id);
      const hasActiveRecord = latestRecord && !latestRecord.endTime;

      // 检查状态不一致情况
      if (activityStatus === MatterStatus.RECORDING && !hasActiveRecord) {
        hilog.warn(0x0000, TAG, `STATUS INCONSISTENCY: Activity ${activity.id} has status RECORDING but no active time record`);
      } else if (activityStatus !== MatterStatus.RECORDING && hasActiveRecord) {
        hilog.warn(0x0000, TAG, `STATUS INCONSISTENCY: Activity ${activity.id} has active time record but status is ${activityStatus}`);
      }

      // 将数据库状态转换为 MatterStatus 枚举
      let status: MatterStatus;
      switch (activityStatus) {
        case 0:
          status = MatterStatus.TODO;
          break;
        case 1:
          status = MatterStatus.RECORDING;
          break;
        case 2:
          status = MatterStatus.PAUSED;
          break;
        default:
          status = MatterStatus.TODO;
          break;
      }

      // 创建并返回 MatterItemModel 对象
      const matterItem = new MatterItemModel({
        id: activity.id,
        title: activity.name,
        label: activity.tagName || '无标签',
        labelColor: labelColor,
        status: status,
        durationInMilliseconds: totalDuration,
      });

      hilog.info(0x0000, TAG, `Successfully prepared matter item for ID: ${activityId}`);
      return matterItem;
    } catch (error) {
      hilog.error(0x0000, TAG, `根据ID获取今日活动时发生错误: ${JSON.stringify(error)}`);
      return null;
    }
  }

  /**
   * 获取所有活动（不限于今日清单）
   * @returns 所有活动的列表
   */
  async getAllActivities(): Promise<TodayActivityItem[]> {
    hilog.info(0x0000, TAG, 'Fetching all activities from database.');

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      // 这里需要在 RDBStoreUtil 中添加 queryAllActivities 方法
      const activities = await rdbStoreUtil.queryAllActivities();
      hilog.info(0x0000, TAG, `Successfully fetched ${activities.length} activities.`);
      return activities;
    } catch (error) {
      hilog.error(0x0000, TAG, `获取所有活动时发生错误: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /**
   * 生成唯一ID
   */
  private generateUniqueId(): string {
    return `activity_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  private async runWithActivityLock<T>(
    activityId: string,
    source: string,
    task: () => Promise<T>
  ): Promise<T> {
    const normalizedActivityId: string = activityId.trim();
    if (!normalizedActivityId) {
      return task();
    }

    const previousQueue: Promise<void> = this.activityOperationQueues.get(normalizedActivityId) ?? Promise.resolve();
    let releaseCurrent: (value?: void | PromiseLike<void>) => void = () => {
    };
    const currentQueue: Promise<void> = new Promise<void>((resolve: (value?: void | PromiseLike<void>) => void) => {
      releaseCurrent = resolve;
    });
    const nextQueue: Promise<void> = previousQueue
      .catch((error: Object) => {
        hilog.warn(0x0000, TAG, `activity lock recovered from queue error, source=${source}, error=${JSON.stringify(error)}`);
      })
      .then(() => currentQueue);
    this.activityOperationQueues.set(normalizedActivityId, nextQueue);

    await previousQueue.catch((error: Object) => {
      hilog.warn(0x0000, TAG, `activity lock previous queue failed, source=${source}, error=${JSON.stringify(error)}`);
    });

    try {
      return await task();
    } finally {
      releaseCurrent();
      if (this.activityOperationQueues.get(normalizedActivityId) === nextQueue) {
        this.activityOperationQueues.delete(normalizedActivityId);
      }
    }
  }

  private markDeletePreferred(recordId: string, enabled: boolean): void {
    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      return;
    }
    if (enabled) {
      this.deletePreferredRecordIds.add(normalizedRecordId);
      if (this.pendingCalendarUpsertIds.has(normalizedRecordId)) {
        void this.drainCalendarUpsertQueue();
      }
      return;
    }
    this.deletePreferredRecordIds.delete(normalizedRecordId);
  }

  private hasPendingCalendarUpsert(recordId: string): boolean {
    if (this.activeCalendarUpsertRecordId === recordId) {
      return true;
    }
    if (this.pendingCalendarUpsertIds.has(recordId)) {
      return true;
    }
    return this.pendingCalendarUpsertQueue.some((task: PendingCalendarUpsertTask) => task.recordId === recordId);
  }

  private async waitForCalendarUpsertSettled(recordId: string, source: string, timeoutMs: number = 1500): Promise<void> {
    if (!this.isCalendarSyncEnabled()) {
      return;
    }

    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      return;
    }

    const startAt: number = Date.now();
    while (this.hasPendingCalendarUpsert(normalizedRecordId)) {
      const elapsedMs: number = Date.now() - startAt;
      if (elapsedMs >= timeoutMs) {
        hilog.warn(0x0000, TAG, `calendar upsert wait timeout, source=${source}, recordId=${normalizedRecordId}, elapsedMs=${elapsedMs}`);
        return;
      }
      await this.sleep(40);
    }
  }

  private sleep(delayMs: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), delayMs);
    });
  }

  /**
   * 开始记录时间
   * @param activityId 活动ID
   * @returns 记录ID（如果成功）或null（如果失败）
   */
  async startTimeRecord(activityId: string): Promise<string | null> {
    const normalizedActivityId: string = activityId.trim();
    if (!normalizedActivityId) {
      hilog.error(0x0000, TAG, 'startTimeRecord failed: activityId is empty');
      return null;
    }

    return this.runWithActivityLock(normalizedActivityId, 'startTimeRecord', async () => {
      try {
        const rdbStoreUtil = RDBStoreUtil.getInstance();
        const openRecords: TimeRecord[] = await rdbStoreUtil.queryOpenTimeRecordsByActivityId(normalizedActivityId);
        if (openRecords.length > 0) {
          const latestOpenRecord: TimeRecord = openRecords[0];
          if (openRecords.length > 1) {
            hilog.warn(0x0000, TAG,
              `startTimeRecord idempotent hit with duplicate open records, activityId=${normalizedActivityId}, openCount=${openRecords.length}`);
          } else {
            hilog.warn(0x0000, TAG,
              `startTimeRecord idempotent hit, activityId=${normalizedActivityId}, existingRecordId=${latestOpenRecord.id}`);
          }
          const statusUpdateResult: boolean = await rdbStoreUtil.updateActivityStatus(normalizedActivityId, MatterStatus.RECORDING);
          if (!statusUpdateResult) {
            hilog.warn(0x0000, TAG, `startTimeRecord failed to align activity status for ${normalizedActivityId}`);
          }
          return latestOpenRecord.id;
        }

        // 创建新的时间记录
        const startTime = Date.now();

        // 开始事务
        await rdbStoreUtil.beginTransaction();

        try {
          // 插入时间记录
          const recordId = await rdbStoreUtil.insertTimeRecord(normalizedActivityId, startTime);

          if (!recordId) {
            hilog.error(0x0000, TAG, `Failed to insert time record for activity ${normalizedActivityId}`);
            await rdbStoreUtil.rollBack();
            return null;
          }

          hilog.info(0x0000, TAG, `Time record inserted successfully for activity ${normalizedActivityId}, recordId: ${recordId}`);

          // 更新活动状态为 RECORDING
          const statusUpdateResult = await rdbStoreUtil.updateActivityStatus(normalizedActivityId, MatterStatus.RECORDING);

          if (!statusUpdateResult) {
            hilog.error(0x0000, TAG, `CRITICAL: Time record created but status update failed for activity ${normalizedActivityId}`);
            await rdbStoreUtil.rollBack();
            return null;
          }

          // 提交事务
          await rdbStoreUtil.commit();

          hilog.info(0x0000, TAG, `Activity status updated successfully to RECORDING for activity ${normalizedActivityId}`);
          // Verify the final state by checking the latest record again
          const finalRecord = await this.queryLatestTimeRecord(normalizedActivityId);
          const hasActiveRecord = finalRecord && !finalRecord.endTime;
          hilog.info(0x0000, TAG, `Final state verification - Activity ${normalizedActivityId} has active record: ${hasActiveRecord}`);

          return recordId;
        } catch (error) {
          // 发生错误时回滚事务
          await rdbStoreUtil.rollBack();
          hilog.error(0x0000, TAG, `Transaction failed for startTimeRecord: ${JSON.stringify(error)}`);
          return null;
        }
      } catch (error) {
        hilog.error(0x0000, TAG, `Error starting time record: ${JSON.stringify(error)}`);
        return null;
      }
    });
  }

  async splitTimeRecordAtBoundaries(recordId: string, referenceTime: number): Promise<TimeRecord | null> {
    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      hilog.error(0x0000, TAG, 'splitTimeRecordAtBoundaries called with invalid recordId');
      return null;
    }

    const originalRecord = await this.getTimeRecordById(normalizedRecordId);
    if (!originalRecord) {
      hilog.error(0x0000, TAG, `splitTimeRecordAtBoundaries: record ${normalizedRecordId} not found`);
      return null;
    }

    return this.runWithActivityLock(originalRecord.activityId, 'splitTimeRecordAtBoundaries', async () => {
      const latestOriginalRecord = await this.getTimeRecordById(normalizedRecordId);
      if (!latestOriginalRecord) {
        hilog.error(0x0000, TAG, `splitTimeRecordAtBoundaries: record ${normalizedRecordId} disappeared during lock`);
        return null;
      }

      const normalizedEndTime = typeof latestOriginalRecord.endTime === 'number' && latestOriginalRecord.endTime > 0
        ? latestOriginalRecord.endTime
        : undefined;
      const safeReferenceTime = typeof referenceTime === 'number' && referenceTime > 0
        ? referenceTime
        : Date.now();
      const effectiveEnd = normalizedEndTime ?? Math.max(safeReferenceTime, latestOriginalRecord.startTime);
      if (effectiveEnd <= latestOriginalRecord.startTime) {
        return latestOriginalRecord;
      }

      const segments = TimeRecordUtil.splitIntoDaySegments(latestOriginalRecord.startTime, effectiveEnd);
      if (!segments || segments.length <= 1) {
        return latestOriginalRecord;
      }

      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const closedRecordIds: string[] = [];
      let transactionStarted = false;
      try {
        await rdbStoreUtil.beginTransaction();
        transactionStarted = true;
        const firstSegment = segments[0];
        const firstDuration = firstSegment.end - firstSegment.start;
        const firstUpdated = await rdbStoreUtil.updateTimeRecordStartEndTime(
          latestOriginalRecord.id,
          firstSegment.start,
          firstSegment.end,
          firstDuration
        );

        if (!firstUpdated) {
          throw new Error(`Failed to update original record ${latestOriginalRecord.id} during split`);
        }
        closedRecordIds.push(latestOriginalRecord.id);

        let lastRecordId = latestOriginalRecord.id;

        for (let i = 1; i < segments.length; i++) {
          const segment = segments[i];
          const isLast = i === segments.length - 1;
          const shouldRemainOpen = isLast && normalizedEndTime === undefined;
          const segmentEnd = shouldRemainOpen ? undefined : segment.end;
          const segmentDuration = segmentEnd !== undefined ? (segmentEnd - segment.start) : undefined;

          const newRecordId = await rdbStoreUtil.insertTimeRecord(
            latestOriginalRecord.activityId,
            segment.start,
            segmentEnd,
            segmentDuration
          );

          if (!newRecordId || newRecordId.trim() === '') {
            throw new Error('Failed to insert split time record');
          }

          if (segmentEnd !== undefined && segmentEnd > segment.start) {
            closedRecordIds.push(newRecordId);
          }
          lastRecordId = newRecordId;
        }

        await rdbStoreUtil.commit();
        transactionStarted = false;

        const finalRecord = await this.getTimeRecordById(lastRecordId);
        if (!finalRecord) {
          throw new Error('Failed to load final split record');
        }

        await this.syncRecordUpsertByIds(closedRecordIds, 'splitTimeRecordAtBoundaries');

        return finalRecord;
      } catch (error) {
        if (transactionStarted) {
          await rdbStoreUtil.rollBack();
        }
        hilog.error(0x0000, TAG, `splitTimeRecordAtBoundaries failed: ${JSON.stringify(error)}`);
        return null;
      }
    });
  }

  /**
   * 停止记录时间
   * @param activityId 活动ID
   * @param recordId 可选的时间记录ID，如果提供则直接更新该记录
   * @returns 是否成功停止记录
   */
  async stopTimeRecord(activityId: string, recordId?: string): Promise<boolean> {
    const result = await this.stopTimeRecordDetailed(activityId, recordId);
    return result === StopTimeRecordResult.STOPPED_NOW
      || result === StopTimeRecordResult.ALREADY_STOPPED
      || result === StopTimeRecordResult.NO_OPEN_RECORD;
  }

  async stopTimeRecordAt(activityId: string, recordId: string, forcedEndTimeMs: number): Promise<boolean> {
    const result = await this.stopTimeRecordAtDetailed(activityId, recordId, forcedEndTimeMs);
    return result === StopTimeRecordResult.STOPPED_NOW
      || result === StopTimeRecordResult.ALREADY_STOPPED
      || result === StopTimeRecordResult.NO_OPEN_RECORD;
  }

  async stopTimeRecordDetailed(activityId: string, recordId?: string): Promise<StopTimeRecordResult> {
    return this.stopTimeRecordInternal(activityId, recordId);
  }

  async stopTimeRecordAtDetailed(
    activityId: string,
    recordId: string,
    forcedEndTimeMs: number
  ): Promise<StopTimeRecordResult> {
    return this.stopTimeRecordInternal(activityId, recordId, forcedEndTimeMs);
  }

  private async stopTimeRecordInternal(
    activityId: string,
    recordId?: string,
    forcedEndTimeMs?: number
  ): Promise<StopTimeRecordResult> {
    const normalizedActivityId: string = activityId.trim();
    if (!normalizedActivityId) {
      hilog.error(0x0000, TAG, `Invalid activity ID provided: ${activityId}`);
      return StopTimeRecordResult.FAILED;
    }

    const normalizedRecordId: string = typeof recordId === 'string' ? recordId.trim() : '';
    const hasForcedEndTime: boolean = typeof forcedEndTimeMs === 'number';
    const lockSource: string = hasForcedEndTime ? 'stopTimeRecordAt' : 'stopTimeRecord';

    return this.runWithActivityLock(normalizedActivityId, lockSource, async () => {
      try {
        const rdbStoreUtil = RDBStoreUtil.getInstance();
        let latestRecord: TimeRecord | null = null;

        // 如果提供了记录ID，优先使用记录ID查询
        if (normalizedRecordId.length > 0) {
          latestRecord = await this.getTimeRecordById(normalizedRecordId);
          if (!latestRecord) {
            hilog.error(0x0000, TAG, `Time record with ID ${normalizedRecordId} not found for activity ${normalizedActivityId}`);
            return StopTimeRecordResult.RECORD_MISMATCH;
          }

          // 验证记录是否属于指定的活动
          if (latestRecord.activityId !== normalizedActivityId) {
            hilog.error(0x0000, TAG, `Record ID ${normalizedRecordId} does not belong to activity ${normalizedActivityId}`);
            return StopTimeRecordResult.RECORD_MISMATCH;
          }

          hilog.info(0x0000, TAG, `Using provided record ID ${normalizedRecordId} for activity ${normalizedActivityId}`);
        } else {
          // 回退到原有的基于活动ID的查询逻辑
          latestRecord = await this.queryLatestTimeRecord(normalizedActivityId);
          if (!latestRecord) {
            hilog.warn(0x0000, TAG, `No time record found for activity ${normalizedActivityId}, cannot accurately calculate duration`);

            // 如果没有找到时间记录，我们无法准确计算持续时间
            // 直接更新活动状态为PAUSED，不创建时间记录
            const statusUpdateResult = await rdbStoreUtil.updateActivityStatus(normalizedActivityId, MatterStatus.PAUSED);

            if (!statusUpdateResult) {
              hilog.error(0x0000, TAG, `Failed to update activity status for ${normalizedActivityId}`);
              return StopTimeRecordResult.FAILED;
            }

            hilog.info(0x0000, TAG, `Updated activity status to PAUSED for ${normalizedActivityId} without creating time record`);
            return StopTimeRecordResult.NO_OPEN_RECORD;
          }

          hilog.info(0x0000, TAG, `Using latest record found by activity ID for activity ${normalizedActivityId}`);
        }

        if (latestRecord.endTime) {
          const openRecordsAfterClosedInput: TimeRecord[] = await rdbStoreUtil.queryOpenTimeRecordsByActivityId(normalizedActivityId);
          if (openRecordsAfterClosedInput.length === 0) {
            hilog.warn(0x0000, TAG,
              `Time record for activity ${normalizedActivityId} already stopped (endTime: ${latestRecord.endTime}), no open records remained.`);
            return StopTimeRecordResult.ALREADY_STOPPED;
          }
          latestRecord = openRecordsAfterClosedInput[0];
          hilog.warn(0x0000, TAG,
            `Stop fallback switched to latest open record ${latestRecord.id} for activity ${normalizedActivityId}`);
        }

        // 验证开始时间：确保开始时间是有效的
        if (!latestRecord.startTime || latestRecord.startTime <= 0) {
          hilog.error(0x0000, TAG, `Invalid start time for activity ${normalizedActivityId}: ${latestRecord.startTime}`);
          return StopTimeRecordResult.FAILED;
        }

        // 验证时间一致性：确保开始时间不晚于当前时间
        const currentTime = Date.now();
        if (latestRecord.startTime > currentTime) {
          hilog.error(0x0000, TAG, `Start time is in the future for activity ${normalizedActivityId}: ${latestRecord.startTime} > ${currentTime}`);
          return StopTimeRecordResult.FAILED;
        }

        // 计算持续时间并更新记录
        let endTime: number = Math.floor(currentTime / 1000) * 1000; // align to seconds to avoid drift
        if (hasForcedEndTime) {
          const candidateEndTime: number = Math.floor(forcedEndTimeMs as number);
          if (!Number.isFinite(candidateEndTime)) {
            hilog.error(0x0000, TAG, `Invalid forced end time for activity ${normalizedActivityId}: ${forcedEndTimeMs}`);
            return StopTimeRecordResult.FAILED;
          }
          if (candidateEndTime < latestRecord.startTime) {
            hilog.error(
              0x0000,
              TAG,
              `Forced end time earlier than start time for activity ${normalizedActivityId}: ${candidateEndTime} < ${latestRecord.startTime}`
            );
            return StopTimeRecordResult.FAILED;
          }
          if (candidateEndTime > currentTime) {
            hilog.error(
              0x0000,
              TAG,
              `Forced end time is in the future for activity ${normalizedActivityId}: ${candidateEndTime} > ${currentTime}`
            );
            return StopTimeRecordResult.FAILED;
          }
          endTime = candidateEndTime;
        }
        const duration = endTime - latestRecord.startTime;

        // 验证持续时间：确保持续时间是合理的
        if (duration < 0) {
          hilog.error(0x0000, TAG, `Invalid duration calculated for activity ${normalizedActivityId}: ${duration}ms`);
          return StopTimeRecordResult.FAILED;
        }

        hilog.info(
          0x0000,
          TAG,
          `Stopping time record for activity ${normalizedActivityId}, duration: ${duration}ms, forced=${hasForcedEndTime}`
        );

        // 开始事务
        await rdbStoreUtil.beginTransaction();
        const closedRecordIds: string[] = [];

        try {
          // 使用新的 updateTimeRecordById 方法更新时间记录
          const updateSuccess = await this.updateTimeRecordById(latestRecord.id, endTime, duration);

          if (!updateSuccess) {
            hilog.error(0x0000, TAG, `Failed to stop time record for activity ${normalizedActivityId}`);
            await rdbStoreUtil.rollBack();
            return StopTimeRecordResult.FAILED;
          }
          closedRecordIds.push(latestRecord.id);

          const openRecords: TimeRecord[] = await rdbStoreUtil.queryOpenTimeRecordsByActivityId(normalizedActivityId);
          for (const openRecord of openRecords) {
            if (openRecord.id === latestRecord.id) {
              continue;
            }
            const residualEndTime: number = Math.max(endTime, openRecord.startTime);
            const residualDuration: number = residualEndTime - openRecord.startTime;
            const residualUpdatedRows: number = await rdbStoreUtil.updateTimeRecord(
              openRecord.id,
              residualEndTime,
              residualDuration
            );
            if (residualUpdatedRows > 0) {
              closedRecordIds.push(openRecord.id);
              hilog.warn(0x0000, TAG,
                `Stop cleanup closed residual open record ${openRecord.id} for activity ${normalizedActivityId}`);
            } else {
              hilog.warn(0x0000, TAG,
                `Stop cleanup skipped residual open record ${openRecord.id} for activity ${normalizedActivityId}`);
            }
          }

          // 更新活动状态为 PAUSED
          const statusUpdateResult = await rdbStoreUtil.updateActivityStatus(normalizedActivityId, MatterStatus.PAUSED);

          if (!statusUpdateResult) {
            hilog.error(0x0000, TAG, `Failed to update activity status for ${normalizedActivityId}`);
            await rdbStoreUtil.rollBack();
            return StopTimeRecordResult.FAILED;
          }

          // 提交事务
          await rdbStoreUtil.commit();
          // 验证最终状态：确保记录已正确停止
          const finalRecord = await this.getTimeRecordById(latestRecord.id);
          if (finalRecord && finalRecord.endTime === endTime) {
            const normalizedClosedRecordIds: string[] = this.normalizeRecordIds(closedRecordIds);
            normalizedClosedRecordIds.forEach((closedRecordId: string) => {
              this.enqueueCalendarUpsert(closedRecordId, 'stopTimeRecord');
            });
            const remainingOpenRecords: TimeRecord[] = await rdbStoreUtil.queryOpenTimeRecordsByActivityId(normalizedActivityId);
            if (remainingOpenRecords.length > 0) {
              hilog.warn(0x0000, TAG,
                `Residual open records still exist after stop, activityId=${normalizedActivityId}, count=${remainingOpenRecords.length}`);
            }
            hilog.info(0x0000, TAG,
              `Successfully stopped time record for activity ${normalizedActivityId}, duration: ${duration}ms, closedCount=${normalizedClosedRecordIds.length}`);
            return StopTimeRecordResult.STOPPED_NOW;
          } else {
            hilog.error(0x0000, TAG, `State verification failed for activity ${normalizedActivityId} after stopping time record`);
            return StopTimeRecordResult.FAILED;
          }
        } catch (error) {
          // 发生错误时回滚事务
          await rdbStoreUtil.rollBack();
          hilog.error(0x0000, TAG, `Transaction failed for ${lockSource}: ${JSON.stringify(error)}`);
          return StopTimeRecordResult.FAILED;
        }
      } catch (error) {
        hilog.error(0x0000, TAG, `Error in ${lockSource}: ${JSON.stringify(error)}`);
        return StopTimeRecordResult.FAILED;
      }
    });
  }

  /**
   * 获取活动的今日总时长（毫秒）
   * @param activityId 活动ID
   * @returns 今日总时长（毫秒）
   */
  async getTodayTotalDuration(activityId: string): Promise<number> {
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      return await rdbStoreUtil.queryTodayTotalDuration(activityId);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error getting today total duration: ${JSON.stringify(error)}`);
      return 0;
    }
  }

  /**
   * 获取所有活动的今日总时长（毫秒）
   * @returns 所有活动的今日总时长（毫秒）
   */
  async getAllTodayTotalDuration(): Promise<number> {
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      return await rdbStoreUtil.queryAllTodayTotalDuration();
    } catch (error) {
      hilog.error(0x0000, TAG, `Error getting all today total duration: ${JSON.stringify(error)}`);
      return 0;
    }
  }

  /**
   * 更新时间记录的结束时间和持续时间
   * @param recordId 时间记录ID
   * @param endTime 结束时间（时间戳，毫秒）
   * @param duration 持续时间（毫秒）
   * @returns 更新的行数
   */
  async updateTimeRecord(recordId: string, endTime: number, duration: number): Promise<number> {
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      return await rdbStoreUtil.updateTimeRecord(recordId, endTime, duration);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error updating time record: ${JSON.stringify(error)}`);
      return 0;
    }
  }

  /**
   * 更新时间记录的开始时间
   * @param recordId 时间记录ID
   * @param startTime 新的开始时间（时间戳，毫秒）
   * @returns 是否成功更新
   */
  async updateTimeRecordStartTime(recordId: string, startTime: number): Promise<boolean> {
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const updateResult: boolean = await rdbStoreUtil.updateTimeRecordStartTime(recordId, startTime);
      if (!updateResult) {
        return false;
      }
      await this.syncClosedRecordById(recordId, 'updateTimeRecordStartTime');
      return true;
    } catch (error) {
      hilog.error(0x0000, TAG, `Error updating time record start time: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 根据ID更新时间记录的结束时间和持续时间
   * @param recordId 时间记录ID
   * @param endTime 结束时间（时间戳，毫秒）
   * @param duration 持续时间（毫秒）
   * @returns 是否成功更新
   */
  async updateTimeRecordById(recordId: string, endTime: number, duration: number): Promise<boolean> {
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const updatedRows = await rdbStoreUtil.updateTimeRecord(recordId, endTime, duration);
      return updatedRows > 0;
    } catch (error) {
      hilog.error(0x0000, TAG, `Error updating time record by ID: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 更新时间记录的开始时间、结束时间和持续时间
   * @param recordId 时间记录ID
   * @param startTime 新的开始时间（时间戳，毫秒）
   * @param endTime 新的结束时间（时间戳，毫秒），可选
   * @param duration 新的持续时间（毫秒），可选
   * @returns 是否成功更新
   */
  async updateTimeRecordStartEndTime(recordId: string, startTime: number, endTime: number, duration?: number): Promise<boolean> {
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const updateResult: boolean = await rdbStoreUtil.updateTimeRecordStartEndTime(recordId, startTime, endTime, duration);
      if (!updateResult) {
        return false;
      }
      if (this.isClosedRange(startTime, endTime)) {
        await this.syncRecordUpsertById(recordId, 'updateTimeRecordStartEndTime');
      }
      return true;
    } catch (error) {
      hilog.error(0x0000, TAG, `Error updating time record start and end time: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 手动新增一条闭合时间记录（用于编辑页手动补录）
   * @param activityId 活动ID
   * @param startTime 开始时间（时间戳，毫秒）
   * @param endTime 结束时间（时间戳，毫秒）
   * @param duration 持续时长（毫秒），可选
   * @returns 新增记录ID，失败返回 null
   */
  async addManualTimeRecord(activityId: string, startTime: number, endTime: number, duration?: number): Promise<string | null> {
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'addManualTimeRecord failed: invalid activityId');
      return null;
    }
    if (!this.isClosedRange(startTime, endTime)) {
      hilog.error(0x0000, TAG, `addManualTimeRecord failed: invalid time range ${startTime} -> ${endTime}`);
      return null;
    }

    const resolvedDuration: number = typeof duration === 'number' && duration > 0
      ? duration
      : (endTime - startTime);
    if (resolvedDuration <= 0) {
      hilog.error(0x0000, TAG, `addManualTimeRecord failed: invalid duration ${resolvedDuration}`);
      return null;
    }

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const recordId = await rdbStoreUtil.insertTimeRecord(activityId, startTime, endTime, resolvedDuration);
      if (!recordId || recordId.trim() === '') {
        hilog.error(0x0000, TAG, `addManualTimeRecord failed: insert returned empty recordId, activityId=${activityId}`);
        return null;
      }
      await this.syncRecordUpsertById(recordId, 'addManualTimeRecord');
      return recordId;
    } catch (error) {
      hilog.error(0x0000, TAG, `addManualTimeRecord exception: ${JSON.stringify(error)}`);
      return null;
    }
  }

  private isCalendarSyncEnabled(): boolean {
    try {
      const enabledValue: boolean | undefined = AppStorage.get(CALENDAR_SYNC_ENABLED_APP_STORAGE_KEY) as boolean | undefined;
      return enabledValue === true;
    } catch (error) {
      hilog.warn(0x0000, TAG, `calendar sync gate check failed: ${JSON.stringify(error)}`);
      return false;
    }
  }

  private isClosedRange(startTime: number, endTime: number): boolean {
    return endTime > startTime;
  }

  private isClosedRecord(record: TimeRecord): boolean {
    return typeof record.endTime === 'number' && record.endTime > record.startTime;
  }

  private normalizeRecordIds(recordIds: string[]): string[] {
    const normalized: string[] = [];
    const seen: Set<string> = new Set<string>();
    recordIds.forEach((recordId: string) => {
      const normalizedRecordId: string = recordId.trim();
      if (!normalizedRecordId || seen.has(normalizedRecordId)) {
        return;
      }
      seen.add(normalizedRecordId);
      normalized.push(normalizedRecordId);
    });
    return normalized;
  }

  private enqueueCalendarUpsert(recordId: string, source: string): void {
    if (!this.isCalendarSyncEnabled()) {
      return;
    }

    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      return;
    }

    if (this.deletePreferredRecordIds.has(normalizedRecordId)) {
      hilog.info(0x0000, TAG, `calendar upsert skipped by delete priority, source=${source}, recordId=${normalizedRecordId}`);
      return;
    }

    if (this.pendingCalendarUpsertIds.has(normalizedRecordId)) {
      hilog.info(0x0000, TAG, `calendar upsert already queued, source=${source}, recordId=${normalizedRecordId}`);
      return;
    }

    this.pendingCalendarUpsertIds.add(normalizedRecordId);
    this.pendingCalendarUpsertQueue.push({
      recordId: normalizedRecordId,
      source: source
    });
    hilog.info(0x0000, TAG, `calendar upsert queued, source=${source}, recordId=${normalizedRecordId}`);
    void this.drainCalendarUpsertQueue();
  }

  private async drainCalendarUpsertQueue(): Promise<void> {
    if (this.isDrainingCalendarUpsertQueue) {
      return;
    }

    this.isDrainingCalendarUpsertQueue = true;
    try {
      while (this.pendingCalendarUpsertQueue.length > 0) {
        const task: PendingCalendarUpsertTask | undefined = this.pendingCalendarUpsertQueue.shift();
        if (!task) {
          continue;
        }
        this.pendingCalendarUpsertIds.delete(task.recordId);
        if (this.deletePreferredRecordIds.has(task.recordId)) {
          hilog.info(0x0000, TAG, `calendar upsert queue dropped by delete priority, source=${task.source}, recordId=${task.recordId}`);
          continue;
        }
        this.activeCalendarUpsertRecordId = task.recordId;
        try {
          await this.syncRecordUpsertById(task.recordId, `${task.source}_async_queue`);
        } finally {
          if (this.activeCalendarUpsertRecordId === task.recordId) {
            this.activeCalendarUpsertRecordId = '';
          }
        }
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar upsert queue drain exception: ${JSON.stringify(error)}`);
    } finally {
      this.activeCalendarUpsertRecordId = '';
      this.isDrainingCalendarUpsertQueue = false;
      if (this.pendingCalendarUpsertQueue.length > 0) {
        void this.drainCalendarUpsertQueue();
      }
    }
  }

  private async syncClosedRecordById(recordId: string, source: string): Promise<void> {
    if (!this.isCalendarSyncEnabled()) {
      return;
    }
    const record: TimeRecord | null = await this.getTimeRecordById(recordId);
    if (!record || !this.isClosedRecord(record)) {
      return;
    }
    await this.syncRecordUpsertById(record.id, source);
  }

  private async syncRecordUpsertByIds(recordIds: string[], source: string): Promise<void> {
    if (!this.isCalendarSyncEnabled()) {
      return;
    }
    const normalizedRecordIds: string[] = this.normalizeRecordIds(recordIds);
    for (const recordId of normalizedRecordIds) {
      await this.syncRecordUpsertById(recordId, source);
    }
  }

  private async syncRecordUpsertById(recordId: string, source: string): Promise<void> {
    if (!this.isCalendarSyncEnabled()) {
      return;
    }
    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      return;
    }
    if (this.deletePreferredRecordIds.has(normalizedRecordId)) {
      hilog.info(0x0000, TAG, `calendar upsert skipped by delete priority, source=${source}, recordId=${normalizedRecordId}`);
      return;
    }
    try {
      const syncResult: boolean = await calendarSyncService.upsertByTimeRecord(normalizedRecordId);
      if (!syncResult) {
        hilog.warn(0x0000, TAG, `calendar upsert not synced, source=${source}, recordId=${normalizedRecordId}`);
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar upsert exception, source=${source}, recordId=${normalizedRecordId}, error=${JSON.stringify(error)}`);
    }
  }

  private async deleteCalendarEventBeforeRecordDelete(recordId: string, source: string): Promise<boolean> {
    if (!this.isCalendarSyncEnabled()) {
      return true;
    }
    try {
      const syncResult: boolean = await calendarSyncService.deleteByTimeRecord(recordId);
      if (!syncResult) {
        hilog.error(0x0000, TAG, `calendar delete blocked local delete, source=${source}, recordId=${recordId}`);
        return false;
      }
      return true;
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar delete exception, source=${source}, recordId=${recordId}, error=${JSON.stringify(error)}`);
      return false;
    }
  }

  private async deleteCalendarEventsBeforeRecordDelete(recordIds: string[], source: string): Promise<boolean> {
    const normalizedRecordIds: string[] = this.normalizeRecordIds(recordIds);
    if (normalizedRecordIds.length === 0 || !this.isCalendarSyncEnabled()) {
      return true;
    }
    try {
      const syncResult: boolean = await calendarSyncService.deleteByTimeRecords(normalizedRecordIds);
      if (!syncResult) {
        hilog.error(0x0000, TAG,
          `calendar batch delete blocked local delete, source=${source}, recordCount=${normalizedRecordIds.length}`);
        return false;
      }
      return true;
    } catch (error) {
      hilog.error(0x0000, TAG,
        `calendar batch delete exception, source=${source}, recordCount=${normalizedRecordIds.length}, error=${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 查询指定活动的最新时间记录
   * @param activityId 活动ID
   * @returns 最新的时间记录对象，如果没有则返回null
   */
  async queryLatestTimeRecord(activityId: string): Promise<TimeRecord | null> {
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      return await rdbStoreUtil.queryLatestTimeRecord(activityId);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error querying latest time record: ${JSON.stringify(error)}`);
      return null;
    }
  }

  /**
   * 根据ID查询时间记录
   * @param recordId 时间记录ID
   * @returns 时间记录对象，如果没有则返回null
   */
  async getTimeRecordById(recordId: string): Promise<TimeRecord | null> {
    // 验证记录ID是否有效
    if (!recordId || recordId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid record ID provided: empty or null');
      return null;
    }

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const record = await rdbStoreUtil.queryTimeRecordById(recordId);
      
      if (!record) {
        hilog.warn(0x0000, TAG, `No time record found with ID: ${recordId}`);
        return null;
      }
      
      return record;
    } catch (error) {
      hilog.error(0x0000, TAG, `Error querying time record by ID ${recordId}: ${JSON.stringify(error)}`);
      return null;
    }
  }

  /**
   * 删除时间记录
   * @param recordId 时间记录ID
   * @returns 是否成功删除
   */
  async deleteTimeRecord(recordId: string): Promise<boolean> {
    // 验证记录ID是否有效
    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      hilog.error(0x0000, TAG, 'Invalid record ID provided for deletion: empty or null');
      return false;
    }

    const existingRecord: TimeRecord | null = await this.getTimeRecordById(normalizedRecordId);
    if (!existingRecord) {
      hilog.warn(0x0000, TAG, `deleteTimeRecord skipped, record already missing: ${normalizedRecordId}`);
      return true;
    }

    return this.runWithActivityLock(existingRecord.activityId, 'deleteTimeRecord', async () => {
      this.markDeletePreferred(normalizedRecordId, true);
      try {
        const latestRecord: TimeRecord | null = await this.getTimeRecordById(normalizedRecordId);
        if (!latestRecord) {
          hilog.warn(0x0000, TAG, `deleteTimeRecord lock stage skipped, record already removed: ${normalizedRecordId}`);
          return true;
        }
        await this.waitForCalendarUpsertSettled(normalizedRecordId, 'deleteTimeRecord');
        const rdbStoreUtil = RDBStoreUtil.getInstance();
        const calendarDeleteReady: boolean = await this.deleteCalendarEventBeforeRecordDelete(normalizedRecordId, 'deleteTimeRecord');
        if (!calendarDeleteReady) {
          return false;
        }
        const success = await rdbStoreUtil.deleteTimeRecord(normalizedRecordId);

        if (success) {
          hilog.info(0x0000, TAG, `Time record deleted successfully, record ID: ${normalizedRecordId}`);
        } else {
          hilog.error(0x0000, TAG, `Failed to delete time record, record ID: ${normalizedRecordId}`);
        }

        return success;
      } catch (error) {
        hilog.error(0x0000, TAG, `Error deleting time record by ID ${normalizedRecordId}: ${JSON.stringify(error)}`);
        return false;
      } finally {
        this.markDeletePreferred(normalizedRecordId, false);
      }
    });
  }

  private async waitForCalendarUpsertSettledByIds(recordIds: string[], source: string): Promise<void> {
    const normalizedRecordIds: string[] = this.normalizeRecordIds(recordIds);
    for (const recordId of normalizedRecordIds) {
      await this.waitForCalendarUpsertSettled(recordId, source);
    }
  }

  private markDeletePreferredByIds(recordIds: string[], enabled: boolean): void {
    const normalizedRecordIds: string[] = this.normalizeRecordIds(recordIds);
    normalizedRecordIds.forEach((recordId: string) => {
      this.markDeletePreferred(recordId, enabled);
    });
  }

  /**
   * 根据状态获取活动列表
   * @param status 活动状态 (MatterStatus 枚举)
   * @returns 符合指定状态的活动列表
   */
  async getActivitiesByStatus(status: MatterStatus): Promise<MatterItemModel[]> {
    hilog.info(0x0000, TAG, `Fetching activities by status: ${status}`);

    try {
      // 获取所有今日活动
      const allActivities = await this.getTodayMatterItems();
      
      if (!allActivities || allActivities.length === 0) {
        hilog.info(0x0000, TAG, 'No activities found for today.');
        return [];
      }
      
      // 根据状态过滤活动
      const filteredActivities = allActivities.filter(activity => activity.status === status);
      
      hilog.info(0x0000, TAG, `Successfully found ${filteredActivities.length} activities with status ${status}.`);
      return filteredActivities;
    } catch (error) {
      hilog.error(0x0000, TAG, `Error fetching activities by status ${status}: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /**
   * 更新活动状态
   * @param activityId 活动ID
   * @param newStatus 新的活动状态 (MatterStatus 枚举)
   * @returns 是否成功更新状态
   */
  async updateActivityStatus(activityId: string, newStatus: MatterStatus): Promise<boolean> {
    // 基础验证：确保活动ID有效
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法更新状态，活动ID为空。');
      return false;
    }

    hilog.info(0x0000, TAG, `尝试更新活动 ${activityId} 的状态为: ${newStatus}`);

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      
      // 验证活动是否存在
      const activity = await this.getTodayMatterItemById(activityId);
      if (!activity) {
        hilog.error(0x0000, TAG, `活动不存在，ID: ${activityId}`);
        return false;
      }
      
      // 检查状态是否实际发生了变化
      if (activity.status === newStatus) {
        hilog.info(0x0000, TAG, `活动 ${activityId} 的状态已经是 ${newStatus}，无需更新。`);
        return true;
      }
      
      // 特殊状态转换处理
      if (newStatus === MatterStatus.RECORDING) {
        // 如果要设置为录制状态，检查是否已有活动的时间记录
        const latestRecord = await rdbStoreUtil.queryLatestTimeRecord(activityId);
        const hasActiveRecord = latestRecord && !latestRecord.endTime;
        
        if (hasActiveRecord) {
          hilog.warn(0x0000, TAG, `活动 ${activityId} 已有活动的时间记录，状态可能不一致`);
        } else {
          // 如果没有活动的时间记录，需要创建一个
          const startTime = Date.now();
          const recordId = await rdbStoreUtil.insertTimeRecord(activityId, startTime);
          
          if (!recordId) {
            hilog.error(0x0000, TAG, `为活动 ${activityId} 创建时间记录失败`);
            return false;
          }
          
          hilog.info(0x0000, TAG, `为活动 ${activityId} 创建了新的时间记录，ID: ${recordId}`);
        }
      } else if (activity.status === MatterStatus.RECORDING) {
        // 如果从录制状态切换到其他状态，需要停止当前的时间记录
        const latestRecord = await rdbStoreUtil.queryLatestTimeRecord(activityId);
        
        if (latestRecord && !latestRecord.endTime) {
          const currentTime = Date.now();
          const duration = currentTime - latestRecord.startTime;
          
          const updateSuccess = await this.updateTimeRecordById(latestRecord.id, currentTime, duration);
          
          if (!updateSuccess) {
            hilog.error(0x0000, TAG, `停止活动 ${activityId} 的时间记录失败`);
            return false;
          }
          await this.syncRecordUpsertById(latestRecord.id, 'updateActivityStatus');
          
          hilog.info(0x0000, TAG, `已停止活动 ${activityId} 的时间记录，持续时间: ${duration}ms`);
        }
      }
      
      // 更新活动状态
      const updateResult = await rdbStoreUtil.updateActivityStatus(activityId, newStatus);
      
      if (updateResult) {
        hilog.info(0x0000, TAG, `成功更新活动 ${activityId} 的状态为: ${newStatus}`);
        return true;
      } else {
        hilog.error(0x0000, TAG, `更新活动 ${activityId} 的状态失败`);
        return false;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `更新活动 ${activityId} 状态时发生错误: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 删除活动及其相关记录
   * @param activityId 活动ID
   * @returns 是否成功删除
   */
  async deleteActivity(activityId: string): Promise<boolean> {
    // 基础验证：确保活动ID有效
    const normalizedActivityId: string = activityId.trim();
    if (!normalizedActivityId) {
      hilog.error(0x0000, TAG, '无法删除活动，活动ID为空。');
      return false;
    }

    hilog.info(0x0000, TAG, `尝试删除活动，ID: ${normalizedActivityId}`);

    return this.runWithActivityLock(normalizedActivityId, 'deleteActivity', async () => {
      try {
        const rdbStoreUtil = RDBStoreUtil.getInstance();

        // 验证活动是否存在
        const activity = await this.getTodayMatterItemById(normalizedActivityId);
        if (!activity) {
          hilog.error(0x0000, TAG, `活动不存在，无法删除，ID: ${normalizedActivityId}`);
          return false;
        }

        // 检查活动状态，如果正在录制需要先停止
        if (activity.status === MatterStatus.RECORDING) {
          hilog.warn(0x0000, TAG, `活动 ${normalizedActivityId} 正在录制中，尝试停止时间记录`);

          const latestRecord = await rdbStoreUtil.queryLatestTimeRecord(normalizedActivityId);
          if (latestRecord && !latestRecord.endTime) {
            const currentTime = Date.now();
            const duration = currentTime - latestRecord.startTime;

            const updateSuccess = await this.updateTimeRecordById(latestRecord.id, currentTime, duration);
            if (!updateSuccess) {
              hilog.error(0x0000, TAG, `停止活动 ${normalizedActivityId} 的时间记录失败`);
              return false;
            }

            hilog.info(0x0000, TAG, `已停止活动 ${normalizedActivityId} 的时间记录，持续时间: ${duration}ms`);
          }
        }

        const timeRecords: TimeRecord[] = await rdbStoreUtil.queryTimeRecordsByActivityId(normalizedActivityId);
        const recordIds: string[] = timeRecords.map((record: TimeRecord) => record.id);
        this.markDeletePreferredByIds(recordIds, true);
        try {
          await this.waitForCalendarUpsertSettledByIds(recordIds, 'deleteActivity');
          const calendarDeleteReady: boolean = await this.deleteCalendarEventsBeforeRecordDelete(recordIds, 'deleteActivity');
          if (!calendarDeleteReady) {
            return false;
          }

          // 调用RDBStoreUtil的deleteActivity方法删除活动
          const deleteResult = await rdbStoreUtil.deleteActivity(normalizedActivityId);

          if (deleteResult) {
            hilog.info(0x0000, TAG, `成功删除活动，ID: ${normalizedActivityId}`);
            return true;
          } else {
            hilog.error(0x0000, TAG, `删除活动失败，ID: ${normalizedActivityId}`);
            return false;
          }
        } finally {
          this.markDeletePreferredByIds(recordIds, false);
        }
      } catch (error) {
        hilog.error(0x0000, TAG, `删除活动 ${normalizedActivityId} 时发生错误: ${JSON.stringify(error)}`);
        return false;
      }
    });
  }

  /**
   * 获取指定活动对应的所有时间记录
   * @param activityId 活动ID
   * @returns 该活动对应的所有时间记录数组
   */
  async getTimeRecordsByActivityId(activityId: string): Promise<TimeRecord[]> {
    // 基础验证：确保活动ID有效
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法获取时间记录，活动ID为空。');
      return [];
    }

    hilog.info(0x0000, TAG, `获取活动 ${activityId} 的所有时间记录`);

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const timeRecords = await rdbStoreUtil.queryTimeRecordsByActivityId(activityId);
      
      hilog.info(0x0000, TAG, `成功获取活动 ${activityId} 的 ${timeRecords.length} 个时间记录`);
      return timeRecords;
    } catch (error) {
      hilog.error(0x0000, TAG, `获取活动 ${activityId} 的时间记录时发生错误: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /**
   * 根据活动ID获取对应的标签对象
   * @param activityId 活动ID
   * @returns 标签对象或null（如果活动没有标签或标签不存在）
   */
  async getTagByActivityId(activityId: string): Promise<TagItem | undefined> {
    // 基础验证：确保活动ID有效
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法获取标签，活动ID为空。');
      return undefined;
    }

    hilog.info(0x0000, TAG, `获取活动 ${activityId} 的标签信息`);

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      
      // 步骤1: 查询活动对应的标签ID
      const tagId = await rdbStoreUtil.queryTagIdByActivityId(activityId);
      
      if (!tagId) {
        hilog.info(0x0000, TAG, `活动 ${activityId} 没有关联的标签`);
        return undefined;
      }
      
      // 步骤2: 使用标签ID查询完整的标签对象
      const tag = await rdbStoreUtil.queryTagById(tagId);
      
      if (!tag) {
        hilog.warn(0x0000, TAG, `活动 ${activityId} 关联的标签 ${tagId} 不存在`);
        return undefined;
      }
      
      hilog.info(0x0000, TAG, `成功获取活动 ${activityId} 的标签: ${tag.name}`);
      return tag;
    } catch (error) {
      hilog.error(0x0000, TAG, `获取活动 ${activityId} 的标签时发生错误: ${JSON.stringify(error)}`);
      return undefined;
    }
  }

  /**
   * 更新活动的标签
   * @param activityId 活动ID
   * @param tagId 新的标签ID（可以为null表示移除标签）
   * @returns 是否成功更新
   */
  async updateActivityTag(activityId: string, tagId: string): Promise<boolean> {
    // 基础验证：确保活动ID有效
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法更新标签，活动ID为空。');
      return false;
    }

    hilog.info(0x0000, TAG, `尝试更新活动 ${activityId} 的标签为: ${tagId}`);

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();

      // 验证活动是否存在
      const activity = await this.getTodayMatterItemById(activityId);
      if (!activity) {
        hilog.error(0x0000, TAG, `活动不存在，无法更新标签，ID: ${activityId}`);
        return false;
      }

      // 如果提供了标签ID，验证标签是否存在
      if (tagId && tagId.trim().length > 0) {
        const tagExists = await rdbStoreUtil.queryTagById(tagId);
        if (!tagExists) {
          hilog.error(0x0000, TAG, `标签不存在，无法更新活动标签，标签ID: ${tagId}`);
          return false;
        }
      }

      // 更新活动标签
      const updateResult = await rdbStoreUtil.updateActivityTag(activityId, tagId);

      if (updateResult) {
        hilog.info(0x0000, TAG, `成功更新活动 ${activityId} 的标签为: ${tagId}`);
        return true;
      } else {
        hilog.error(0x0000, TAG, `更新活动 ${activityId} 的标签失败`);
        return false;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `更新活动 ${activityId} 标签时发生错误: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 更新活动的名称和标签
   * @param activityId 活动ID
   * @param name 新的活动名称
   * @param tagId 新的标签ID（可以为null表示移除标签）
   * @returns 是否成功更新
   */
  async updateActivityNameAndTag(activityId: string, name: string, tagId: string | null): Promise<boolean> {
    // 基础验证：确保活动ID有效
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法更新活动名称和标签，活动ID为空。');
      return false;
    }

    // 基础验证：确保活动名称有效
    if (!name || name.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法更新活动名称和标签，活动名称为空。');
      return false;
    }

    const normalizedName: string = name.trim();
    hilog.info(0x0000, TAG, `尝试更新活动 ${activityId} 的名称为: ${normalizedName}，标签为: ${tagId}`);

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();

      // 验证活动是否存在
      const activity = await this.getTodayMatterItemById(activityId);
      if (!activity) {
        hilog.error(0x0000, TAG, `活动不存在，无法更新名称和标签，ID: ${activityId}`);
        return false;
      }
      const shouldResyncCalendarCopy: boolean = activity.title.trim() !== normalizedName;

      // 如果提供了标签ID，验证标签是否存在
      if (tagId && tagId.trim().length > 0) {
        const tagExists = await rdbStoreUtil.queryTagById(tagId);
        if (!tagExists) {
          hilog.error(0x0000, TAG, `标签不存在，无法更新活动标签，标签ID: ${tagId}`);
          return false;
        }
      }

      // 更新活动名称和标签
      const updateResult = await rdbStoreUtil.updateActivityNameAndTag(activityId, normalizedName, tagId);

      if (updateResult) {
        if (shouldResyncCalendarCopy) {
          await this.syncClosedRecordsByActivityId(activityId, 'updateActivityNameAndTag');
        }
        hilog.info(0x0000, TAG, `成功更新活动 ${activityId} 的名称为: ${normalizedName}，标签为: ${tagId}`);
        return true;
      } else {
        hilog.error(0x0000, TAG, `更新活动 ${activityId} 的名称和标签失败`);
        return false;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `更新活动 ${activityId} 名称和标签时发生错误: ${JSON.stringify(error)}`);
      return false;
    }
  }

  private async syncClosedRecordsByActivityId(activityId: string, source: string): Promise<void> {
    if (!this.isCalendarSyncEnabled()) {
      return;
    }
    try {
      const records: TimeRecord[] = await RDBStoreUtil.getInstance().queryTimeRecordsByActivityId(activityId);
      const closedRecordIds: string[] = records
        .filter((record: TimeRecord) => this.isClosedRecord(record))
        .map((record: TimeRecord) => record.id);
      if (closedRecordIds.length === 0) {
        return;
      }
      await this.syncRecordUpsertByIds(closedRecordIds, source);
    } catch (error) {
      hilog.error(0x0000, TAG,
        `calendar upsert by activity failed, source=${source}, activityId=${activityId}, error=${JSON.stringify(error)}`);
    }
  }

  async replaceActivityCoverImage(
    activityId: string,
    pickerUri: string,
    ctx: FilesDirCarrier
  ): Promise<ActivityCoverImageResult | null> {
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'PhotoPick replaceActivityCoverImage failed: activityId is empty.');
      return null;
    }
    if (!pickerUri || pickerUri.trim().length === 0) {
      hilog.error(0x0000, TAG, 'PhotoPick replaceActivityCoverImage failed: pickerUri is empty.');
      return null;
    }

    let savedRelPath: string | null = null;
    let savedImageUri: string | null = null;
    let savedAbsPath: string | null = null;
    let contentHash: string | null = null;
    let didCopyNewFile = false;
    try {
      hilog.info(0x0000, TAG, `PhotoPick replaceActivityCoverImage start activityId=${activityId} pickerUri=${pickerUri}`);
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      try {
        contentHash = await computeFileHashFromUri(pickerUri);
      } catch (err) {
        hilog.warn(0x0000, TAG,
          `PhotoPick replaceActivityCoverImage hash failed activityId=${activityId} err=${JSON.stringify(err)}`);
        contentHash = null;
      }

      if (contentHash) {
        const existingPath = await rdbStoreUtil.queryMediaLocalPathByHash(contentHash);
        if (existingPath) {
          const existingUri = relPathToImageUri(ctx, existingPath);
          if (existingUri) {
            savedRelPath = existingPath;
            savedImageUri = existingUri;
            savedAbsPath = resolveStoredPath(ctx, existingPath);
            hilog.info(0x0000, TAG,
              `PhotoPick replaceActivityCoverImage reuse existing file relPath=${existingPath} hash=${contentHash}`);
          }
        }
      }

      if (!savedRelPath) {
        const saved = await savePickerUriToSandboxFiles(ctx, pickerUri, 'diary_images');
        didCopyNewFile = true;
        savedRelPath = saved.relPath;
        savedImageUri = saved.imageUri;
        savedAbsPath = saved.absPath;
        hilog.info(0x0000, TAG,
          `PhotoPick replaceActivityCoverImage saved relPath=${saved.relPath} absPath=${saved.absPath} imageUri=${saved.imageUri}`);
      }

      if (!savedRelPath || !savedImageUri) {
        hilog.error(0x0000, TAG,
          `PhotoPick replaceActivityCoverImage failed: resolved path/uri missing activityId=${activityId}`);
        if (didCopyNewFile && savedRelPath) {
          deleteStoredFileBestEffort(ctx, savedRelPath);
        }
        return null;
      }

      if (!savedAbsPath) {
        savedAbsPath = resolveStoredPath(ctx, savedRelPath);
      }
      const mimeType = guessMimeTypeFromUri(pickerUri);
      let byteSize = 0;
      try {
        if (savedAbsPath) {
          const stat = fs.statSync(savedAbsPath);
          byteSize = Number(stat.size) || 0;
        }
      } catch (_err) {
        byteSize = 0;
      }
      hilog.info(0x0000, TAG,
        `PhotoPick replaceActivityCoverImage file stat mimeType=${mimeType} byteSize=${byteSize} absPath=${savedAbsPath ?? ''}`);

      const result = await rdbStoreUtil.replaceActivityCoverMedia(
        activityId,
        savedRelPath,
        mimeType,
        byteSize,
        0,
        0,
        contentHash
      );
      if (!result.ok) {
        hilog.error(0x0000, TAG,
          `PhotoPick replaceActivityCoverImage failed: replaceActivityCoverMedia not ok activityId=${activityId} relPath=${savedRelPath}`);
        if (didCopyNewFile && savedRelPath) {
          deleteStoredFileBestEffort(ctx, savedRelPath);
        }
        return null;
      }

      const oldPaths = Array.from(new Set(result.oldPaths))
        .filter(path => path && path !== savedRelPath);
      hilog.info(0x0000, TAG,
        `PhotoPick replaceActivityCoverImage db ok oldPathsCount=${oldPaths.length} activityId=${activityId}`);
      for (const oldPath of oldPaths) {
        const remainingCount = await rdbStoreUtil.queryMediaPathReferenceCount(oldPath);
        if (remainingCount === 0) {
          deleteStoredFileBestEffort(ctx, oldPath);
        }
      }

      hilog.info(0x0000, TAG, `PhotoPick replaceActivityCoverImage success activityId=${activityId} relPath=${savedRelPath}`);
      return { relPath: savedRelPath, imageUri: savedImageUri };
    } catch (error) {
      if (didCopyNewFile && savedRelPath) {
        deleteStoredFileBestEffort(ctx, savedRelPath);
      }
      const maybeError = error as ErrorLike;
      const errMessage = maybeError?.message ? maybeError.message : JSON.stringify(error);
      const errCode = typeof maybeError?.code === 'number' ? maybeError.code : -1;
      hilog.error(0x0000, TAG,
        `PhotoPick replaceActivityCoverImage exception activityId=${activityId} pickerUri=${pickerUri} code=${errCode} message=${errMessage}`);
      return null;
    }
  }

  /**
   * Save activity diary text to database
   * @param activityId Activity ID
   * @param text Diary text content
   * @returns Whether save was successful
   */
  async saveActivityDiary(activityId: string, text: string): Promise<boolean> {
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'saveDiary failed: activityId is empty');
      return false;
    }

    const rdbStoreUtil = RDBStoreUtil.getInstance();
    const now = Date.now();

    try {
      await rdbStoreUtil.beginTransaction();

      // Use INSERT OR REPLACE to update or insert diary record
      // Use activity_id as unique key to ensure each activity has only one diary record
      const diaryId = `${activityId}_diary`;
      const sql = 'INSERT OR REPLACE INTO activity_diary (id, activity_id, text, created_at, updated_at) VALUES (?, ?, ?, ?, ?)';
      await rdbStoreUtil.executeSql(sql, [diaryId, activityId, text, now, now]);

      await rdbStoreUtil.commit();
      hilog.info(0x0000, TAG, `saveDiary success: activityId=${activityId}, textLength=${text.length}`);
      return true;
    } catch (error) {
      await rdbStoreUtil.rollBack();
      hilog.error(0x0000, TAG, `saveDiary failed: message: ${error}`);
      return false;
    }
  }

  /**
   * Query activity diary text
   * @param activityId Activity ID
   * @returns Diary text content, empty string if none
   */
  async queryActivityDiary(activityId: string): Promise<string> {
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'queryDiary failed: activityId is empty');
      return '';
    }

    const rdbStoreUtil = RDBStoreUtil.getInstance();

    try {
      const text = await rdbStoreUtil.queryActivityDiary(activityId);
      const result = text ?? '';
      hilog.info(0x0000, TAG, `queryDiary success: activityId=${activityId}, textLength=${result.length}`);
      return result;
    } catch (error) {
      hilog.error(0x0000, TAG, `queryDiary failed: message=${error}`);
      return '';
    }
  }
}

// 导出单例，方便在整个应用中统一调用
export const todayActivityService = new TodayActivityService();
