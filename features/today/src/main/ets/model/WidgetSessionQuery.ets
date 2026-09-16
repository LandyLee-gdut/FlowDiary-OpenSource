import { hilog } from '@kit.PerformanceAnalysisKit';
import { MatterItemModel, OpenRecordInfo, RDBStoreUtil, SessionSnapshot, TimeRecord } from 'base';
import { todayActivityService } from './TodayActivityService';

const TAG: string = 'WidgetSessionQuery';

/**
 * 桌面计时卡片会话数据源（Phase 4-1）。
 * 双态兼容主进程与 Form 独立进程：
 * - 同进程快路径：投影 runningSessionView 命中（recordId 非空，排除 STARTING 瞬态）直接使用，免 rdb 查询；
 * - 跨进程兜底：Form 进程不共享 AppStorage 时以 rdb 最新未结束记录为准（只读，无对账副作用）。
 */
export async function queryWidgetSessionData(context: Context): Promise<OpenRecordInfo | null> {
  const view = AppStorage.get('runningSessionView') as SessionSnapshot | null;
  if (view && view.recordId !== '') {
    const info = new OpenRecordInfo();
    info.itemId = view.itemId;
    info.recordId = view.recordId;
    info.startTime = view.startTime;
    info.title = view.title;
    info.color = view.color;
    return info;
  }
  if (!await ensureRdbReady(context)) {
    return null;
  }
  return queryNewestOpenRecordReadOnly();
}

/** Form 进程可能未经 PhoneAbility.onCreate 初始化 RDB，兜底路径先补齐（initRDB 幂等）。 */
async function ensureRdbReady(context: Context): Promise<boolean> {
  try {
    let dbUtil: RDBStoreUtil;
    try {
      dbUtil = RDBStoreUtil.getInstance();
    } catch (_error) {
      RDBStoreUtil.init(context);
      dbUtil = RDBStoreUtil.getInstance();
    }
    await dbUtil.initRDB();
    return true;
  } catch (error) {
    hilog.error(0x0000, TAG, `ensureRdbReady failed: ${JSON.stringify(error)}`);
    return false;
  }
}

async function queryNewestOpenRecordReadOnly(): Promise<OpenRecordInfo | null> {
  const matters = await todayActivityService.getTodayMatterItems();
  let candidate: OpenRecordInfo | null = null;
  for (const matter of matters) {
    const latest = await todayActivityService.queryLatestTimeRecord(matter.id);
    if (latest === null || latest.endTime) {
      continue;
    }
    if (candidate === null || latest.startTime > candidate.startTime) {
      candidate = buildWidgetSession(latest, matter);
    }
  }
  return candidate;
}

function buildWidgetSession(record: TimeRecord, item: MatterItemModel): OpenRecordInfo {
  const info = new OpenRecordInfo();
  info.itemId = record.activityId;
  info.recordId = record.id;
  info.startTime = record.startTime;
  info.title = item.title;
  const rawColor: ResourceColor | undefined = item.labelColor;
  info.color = typeof rawColor === 'string' ? rawColor : '';
  return info;
}
