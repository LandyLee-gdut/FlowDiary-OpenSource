import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError, emitter } from '@kit.BasicServicesKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { todayActivityService, StopTimeRecordResult } from '../model/TodayActivityService';
import { liveViewController } from '../liveView/LiveViewManger';
import {
  MatterStatus,
  TimeRecord,
  TimeRecordUtil,
  MatterItemModel,
  MatterItemModelInit,
  preferencesUtil,
  recordingSessionStore,
  SessionSnapshot,
  StartResult,
  StopResult,
  RecordingPhase
} from 'base';
import {
  AutoStopRunningSnapshot,
  ensureAutoStopAppStorageDefaults,
  getAutoStopRunningSnapshotFromAppStorage,
  doesAutoStopRunningSnapshotMatch,
  buildAutoStopRunningSnapshotForCurrentSettings,
  persistAutoStopRunningSnapshot,
  migrateAutoStopRunningSnapshotAfterSplit
} from '../model/AutoStopSettings';

const TAG = 'MatterItemStateManager';
const BACKGROUND_TASK_LOG_PREFIX: string = 'background task';
const BACKGROUND_UPDATE_INTERVAL_MS: number = 60 * 1000;
const BACKGROUND_PROGRESS_CYCLE_MINUTES: number = 60;
const NOTIFICATION_LIVE_VIEW_TYPE_CODE: number = 8;
const NOTIFICATION_TEMPLATE_NAME: string = 'downloadTemplate';

function formatBackgroundElapsedDuration(elapsedMillis: number): string {
  const elapsedMinutes = Math.max(0, Math.floor(elapsedMillis / 60000));
  const hours = Math.floor(elapsedMinutes / 60);
  const minutes = elapsedMinutes % 60;

  if (hours <= 0) {
    return `${elapsedMinutes}分钟`;
  }
  if (minutes <= 0) {
    return `${hours}小时`;
  }
  return `${hours}小时${minutes}分钟`;
}

function calculateBackgroundCycleProgress(elapsedMillis: number): number {
  const cycleMillis = BACKGROUND_PROGRESS_CYCLE_MINUTES * 60 * 1000;
  if (cycleMillis <= 0) {
    return 0;
  }
  const cycleElapsedMillis = elapsedMillis % cycleMillis;
  return Math.min(100, Math.floor((cycleElapsedMillis / cycleMillis) * 100));
}

export interface MatterItemStateSnapshot {
  itemId: string;
  status: MatterStatus;
  durationInMilliseconds: number;
  isRunning: boolean;
  currentRecordId: string;
  record?: TimeRecord;
  restartBackgroundTask: boolean;
  lastKnownStartTime: number;
}

interface MatterItemInternalState {
  itemId: string;
  status: MatterStatus;
  durationInMilliseconds: number;
  isRunning: boolean;
  currentRecordId: string;
  record?: TimeRecord;
  lastKnownStartTime: number;
  pauseTime: number;
  elapsedTimeBeforeBackground: number;
  backgroundTaskId: number;
  continuousTaskNotificationId: number;
  updateIntervalId: number;
  restartBackgroundTask: boolean;
  lastForegroundTime: number;
}

interface BackgroundHandle {
  context?: Context;
}

interface AppStorageKeysDefinition {
  DONE: string;
  TODO: string;
  MATTER_REVISION: string;
}

const APP_STORAGE_KEYS: AppStorageKeysDefinition = {
  DONE: 'doneMatterData',
  TODO: 'unDoMatterData',
  MATTER_REVISION: 'matterDataRevision'
};

enum StopFinalizeDisposition {
  FINALIZED = 'finalized',
  ALREADY_SETTLED = 'already_settled',
  FAILED = 'failed'
}

export enum MatterItemActionResult {
  SUCCESS = 'success',
  BLOCKED_BY_OTHER = 'blocked_by_other',
  NO_ACTIVE_RECORD = 'no_active_record',
  INVALID_RECORD = 'invalid_record',
  INTERNAL_ERROR = 'internal_error'
}

interface GeneratedObjectLiteralInterface_1 {
  typeCode: number;
  title: string;
  text: string;
}

export class MatterItemStateManager {
  private static instance: MatterItemStateManager;
  private readonly stateMap: Map<string, MatterItemInternalState> = new Map<string, MatterItemInternalState>();
  private readonly backgroundHandles: Map<string, BackgroundHandle> = new Map<string, BackgroundHandle>();
  private readonly stateListeners: Array<() => void> = [];
  private readonly autoStopFlights: Map<string, Promise<MatterItemStateSnapshot | undefined>> =
    new Map<string, Promise<MatterItemStateSnapshot | undefined>>();
  private readonly restoreFlights: Map<string, Promise<MatterItemStateSnapshot>> =
    new Map<string, Promise<MatterItemStateSnapshot>>();
  private readonly backgroundRequestVersions: Map<string, number> = new Map<string, number>();
  private backgroundTaskQueue: Promise<void> = Promise.resolve();

  static getInstance(): MatterItemStateManager {
    if (!MatterItemStateManager.instance) {
      MatterItemStateManager.instance = new MatterItemStateManager();
    }
    return MatterItemStateManager.instance;
  }

  addStateListener(listener: () => void): void {
    if (this.stateListeners.includes(listener)) {
      return;
    }
    this.stateListeners.push(listener);
  }

  removeStateListener(listener: () => void): void {
    const index = this.stateListeners.indexOf(listener);
    if (index >= 0) {
      this.stateListeners.splice(index, 1);
    }
  }

  private constructor() {
    // Initialize AppStorage defaults when manager loads
    this.ensureAppStorageDefaults();
  }

  private ensureAppStorageDefaults(): void {
    ensureAutoStopAppStorageDefaults();
    // 运行态键（isRunning/currentRunningItemId 等）已由 RecordingSessionBoot 投影单写（Phase 4-6）
    if (AppStorage.get(APP_STORAGE_KEYS.MATTER_REVISION) === undefined) {
      AppStorage.setOrCreate(APP_STORAGE_KEYS.MATTER_REVISION, 0);
    }
  }

  private getOrCreateState(itemId: string): MatterItemInternalState {
    let state = this.stateMap.get(itemId);
    if (!state) {
      state = {
        itemId,
        status: MatterStatus.TODO,
        durationInMilliseconds: 0,
        isRunning: false,
        currentRecordId: '',
        record: undefined,
        lastKnownStartTime: 0,
        pauseTime: 0,
        elapsedTimeBeforeBackground: 0,
        backgroundTaskId: -1,
        continuousTaskNotificationId: -1,
        updateIntervalId: -1,
        restartBackgroundTask: false,
        lastForegroundTime: 0
      };
      this.stateMap.set(itemId, state);
    }
    return state;
  }

  private cloneMatterItem(source: MatterItemModel | MatterItemModelInit): MatterItemModel {
    if (source instanceof MatterItemModel) {
      return source.clone();
    }
    return new MatterItemModel(source);
  }

  private readMatterCollection(key: string): MatterItemModel[] {
    const data = AppStorage.get(key) as (MatterItemModel | MatterItemModelInit)[] | undefined;
    if (!data || !Array.isArray(data)) {
      return [];
    }
    return MatterItemModel.ensureList(data);
  }

  private replaceMatter(collection: MatterItemModel[], item: MatterItemModel): MatterItemModel[] {
    const candidate = MatterItemModel.from(item);
    const updated = collection.slice();
    const index = updated.findIndex(existing => existing.id === candidate.id);
    if (index >= 0) {
      updated[index] = candidate;
      return updated;
    }
    updated.push(candidate);
    return updated;
  }

  private removeMatter(collection: MatterItemModel[], itemId: string): MatterItemModel[] {
    if (!collection.length) {
      return [];
    }
    const index = collection.findIndex(existing => existing.id === itemId);
    if (index < 0) {
      return collection.slice();
    }
    const updated = collection.slice();
    updated.splice(index, 1);
    return updated;
  }

  private syncCollectionsWithItem(item: MatterItemModel): void {
    const sanitized = this.cloneMatterItem(item);
    const matterData = this.readMatterCollection('matterData');
    const doneCollection = this.readMatterCollection(APP_STORAGE_KEYS.DONE);
    const todoCollection = this.readMatterCollection(APP_STORAGE_KEYS.TODO);

    const updatedMatterData = this.replaceMatter(matterData, sanitized);

    const shouldBeInDone = sanitized.status === MatterStatus.PAUSED
      || sanitized.status === MatterStatus.RECORDING;

    const updatedDone = shouldBeInDone
      ? this.replaceMatter(doneCollection, sanitized)
      : this.removeMatter(doneCollection, sanitized.id);

    const updatedTodo = shouldBeInDone
      ? this.removeMatter(todoCollection, sanitized.id)
      : this.replaceMatter(todoCollection, sanitized);

    AppStorage.setOrCreate('matterData', updatedMatterData);
    AppStorage.setOrCreate(APP_STORAGE_KEYS.DONE, updatedDone);
    AppStorage.setOrCreate(APP_STORAGE_KEYS.TODO, updatedTodo);
  }

  private clearBackgroundUpdateInterval(state: MatterItemInternalState): void {
    if (state.updateIntervalId !== -1) {
      clearInterval(state.updateIntervalId);
      state.updateIntervalId = -1;
    }
  }

  private scheduleBackgroundUpdates(itemId: string): void {
    const state = this.getOrCreateState(itemId);
    this.clearBackgroundUpdateInterval(state);
    state.updateIntervalId = setInterval(() => {
      void this.updateBackgroundTask(itemId);
    }, BACKGROUND_UPDATE_INTERVAL_MS);
    void this.updateBackgroundTask(itemId);
  }

  private getBackgroundRequestVersion(itemId: string): number {
    return this.backgroundRequestVersions.get(itemId) ?? 0;
  }

  private invalidateBackgroundRequest(itemId: string): number {
    const nextVersion = this.getBackgroundRequestVersion(itemId) + 1;
    this.backgroundRequestVersions.set(itemId, nextVersion);
    return nextVersion;
  }

  private enqueueBackgroundTaskOperation(
    itemId: string,
    operationName: string,
    operation: () => Promise<void>
  ): Promise<void> {
    const queuedOperation = this.backgroundTaskQueue
      .then(operation)
      .catch((error: BusinessError): void => {
        hilog.error(
          0x0000,
          TAG,
          `${BACKGROUND_TASK_LOG_PREFIX}: ${operationName} queue failed itemId=${itemId} error=${JSON.stringify(error)}`
        );
      });
    this.backgroundTaskQueue = queuedOperation;
    return queuedOperation;
  }

  private publishBackgroundProgress(itemId: string): void {
    const state = this.getOrCreateState(itemId);
    if (state.continuousTaskNotificationId === -1) {
      return;
    }

    const handle = this.backgroundHandles.get(itemId);
    if (!handle || !handle.context) {
      return;
    }

    const now = Date.now();
    const referenceStart = state.record?.startTime || state.lastKnownStartTime;
    if (referenceStart <= 0) {
      return;
    }

    const elapsedMillis = Math.max(0, now - referenceStart);
    const elapsedMinutes = Math.floor(elapsedMillis / 60000);
    const formattedElapsed = formatBackgroundElapsedDuration(elapsedMillis);
    const pseudoProgress = calculateBackgroundCycleProgress(elapsedMillis);

    const liveViewContent: GeneratedObjectLiteralInterface_1 = {
      typeCode: NOTIFICATION_LIVE_VIEW_TYPE_CODE,
      title: '事项计时进行中',
      text: `已运行${elapsedMinutes}分钟`
    };

    const displayTitle = this.resolveItemTitle(itemId);
    const template: notificationManager.NotificationTemplate = {
      name: NOTIFICATION_TEMPLATE_NAME,
      data: {
        title: displayTitle ? `记录中：${displayTitle}` : '记录中',
        fileName: `已记录${formattedElapsed}`,
        progressValue: pseudoProgress
      }
    };

    const request: notificationManager.NotificationRequest = {
      id: state.continuousTaskNotificationId,
      notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
        systemLiveView: liveViewContent
      },
      template
    };

    notificationManager.publish(request).catch((error: BusinessError) => {
      hilog.error(0x0000, TAG, `更新后台通知失败: ${JSON.stringify(error)}`);
    });
  }

  private async alignRecordToCurrentDay(record?: TimeRecord): Promise<TimeRecord | undefined> {
    if (!record) {
      return undefined;
    }

    const now = Date.now();
    const todayStart = TimeRecordUtil.getDayStart(now);
    if (record.startTime >= todayStart) {
      return record;
    }

    hilog.info(0x0000, TAG, `检测到跨日记录，准备拆分: ${record.id}`);
    const normalizedEndTime = typeof record.endTime === 'number' && record.endTime > 0 ? record.endTime : undefined;
    const referenceTime = normalizedEndTime ?? now;
    const splitRecord = await todayActivityService.splitTimeRecordAtBoundaries(record.id, referenceTime);
    if (!splitRecord) {
      hilog.error(0x0000, TAG, `跨日拆分失败，继续使用原记录: ${record.id}`);
      return record;
    }

    if (!normalizedEndTime && splitRecord.id !== record.id) {
      this.migrateRunningSnapshotAfterSplit(record, splitRecord, 'alignRecordToCurrentDay');
    }

    if (!normalizedEndTime) {
      try {
        await liveViewController.updateLiveViewTimeCrossDay(splitRecord.startTime);
      } catch (error) {
        hilog.error(0x0000, TAG, `跨日实况窗更新失败: ${JSON.stringify(error)}`);
      }
    }

    return splitRecord;
  }

  snapshot(itemId: string): MatterItemStateSnapshot {
    const state = this.getOrCreateState(itemId);
    return {
      itemId,
      status: state.status,
      durationInMilliseconds: state.durationInMilliseconds,
      isRunning: state.isRunning,
      currentRecordId: state.currentRecordId,
      record: state.record,
      restartBackgroundTask: state.restartBackgroundTask,
      lastKnownStartTime: state.lastKnownStartTime
    };
  }

  canStart(item: MatterItemModel): boolean {
    const state = this.getOrCreateState(item.id);
    if (state.isRunning) {
      hilog.info(0x0000, TAG, `计时器已在运行: ${item.title}`);
      try {
        promptAction.openToast({ message: '事项已在进行', duration: 1000 });
      } catch (error) {
        hilog.error(0x0000, TAG, `展示Toast失败: ${JSON.stringify(error)}`);
      }
      return false;
    }

    const session = recordingSessionStore.snapshot();
    if (session !== null && session.itemId !== item.id) {
      hilog.info(0x0000, TAG, `已有其他计时器在运行，当前运行ID: ${session.itemId}`);
      try {
        promptAction.openToast({ message: '事项已在进行', duration: 1000 });
      } catch (error) {
        hilog.error(0x0000, TAG, `展示Toast失败: ${JSON.stringify(error)}`);
      }
      return false;
    }
    return true;
  }

  getCurrentRunningItemId(): string {
    return this.getGlobalRunningItemId();
  }

  /** store 快照中属于该 item 的会话；null = 该 item 无运行会话（快照即会话真值）。 */
  private sessionSnapshotFor(itemId: string): SessionSnapshot | null {
    const session = recordingSessionStore.snapshot();
    if (session === null || session.itemId !== itemId) {
      return null;
    }
    return session;
  }

  /** 全局运行信号：store 快照为唯一真值（Phase 4-5 起 legacy 键兜底删除）。 */
  private getGlobalRunningItemId(): string {
    const session = recordingSessionStore.snapshot();
    return session !== null ? session.itemId : '';
  }

  private getGlobalRunningRecordId(): string {
    const session = recordingSessionStore.snapshot();
    return session !== null ? session.recordId : '';
  }

  isItemRunning(itemId: string): boolean {
    if (!itemId) {
      return false;
    }
    return this.getCurrentRunningItemId() === itemId;
  }

  private async runAutoStopSingleFlight(
    itemId: string,
    source: string,
    task: () => Promise<MatterItemStateSnapshot | undefined>
  ): Promise<MatterItemStateSnapshot | undefined> {
    const existingFlight = this.autoStopFlights.get(itemId);
    if (existingFlight) {
      hilog.info(0x0000, TAG, `AutoStop single-flight reused, source=${source}, activityId=${itemId}`);
      return existingFlight;
    }

    const flight = (async (): Promise<MatterItemStateSnapshot | undefined> => {
      try {
        return await task();
      } finally {
        this.autoStopFlights.delete(itemId);
      }
    })();
    this.autoStopFlights.set(itemId, flight);
    return flight;
  }

  private async finalizeStopResult(
    item: MatterItemModel,
    activeRecord: TimeRecord,
    source: string,
    didSplitRecord: boolean,
    shouldStopLiveView: boolean,
    stopResult: StopTimeRecordResult
  ): Promise<StopFinalizeDisposition> {
    if (stopResult === StopTimeRecordResult.STOPPED_NOW) {
      await this.finalizeStoppedState(item, activeRecord, source, didSplitRecord, shouldStopLiveView);
      return StopFinalizeDisposition.FINALIZED;
    }

    if (stopResult === StopTimeRecordResult.ALREADY_STOPPED || stopResult === StopTimeRecordResult.NO_OPEN_RECORD) {
      hilog.warn(0x0000, TAG,
        `Stop finalize reusing settled record state, source=${source}, activityId=${item.id}, recordId=${activeRecord.id}, result=${stopResult}`);
      await this.finalizeStoppedState(item, activeRecord, source, didSplitRecord, shouldStopLiveView);
      return StopFinalizeDisposition.ALREADY_SETTLED;
    }

    hilog.error(0x0000, TAG,
      `Stop finalize failed, source=${source}, activityId=${item.id}, recordId=${activeRecord.id}, result=${stopResult}`);
    return StopFinalizeDisposition.FAILED;
  }

  private moveItemToRunningCollections(item: MatterItemModel): void {
    const unDoRaw = AppStorage.get(APP_STORAGE_KEYS.TODO) as (MatterItemModel | MatterItemModelInit)[] | undefined;
    const doneRaw = AppStorage.get(APP_STORAGE_KEYS.DONE) as (MatterItemModel | MatterItemModelInit)[] | undefined;
    const unDoMatterData = unDoRaw ? MatterItemModel.ensureList(unDoRaw) : [];
    const doneMatterData = doneRaw ? MatterItemModel.ensureList(doneRaw) : [];

    item.status = MatterStatus.RECORDING;
    const filteredTodo = unDoMatterData.filter(todo => todo.id !== item.id);

    let updatedDone: MatterItemModel[];

    const existingDoneIndex: number = doneMatterData.findIndex(doneItem => doneItem.id === item.id);
    if (existingDoneIndex >= 0) {
      // 组内恢复（PAUSED -> RECORDING）保持原位置，避免卡片在列表中跳动
      updatedDone = doneMatterData.slice();
      updatedDone[existingDoneIndex] = item;
    } else {
      // undo -> done 跨组开始：插入 done 头部
      updatedDone = [item, ...doneMatterData];
    }

    AppStorage.set(APP_STORAGE_KEYS.TODO, filteredTodo);
    AppStorage.set(APP_STORAGE_KEYS.DONE, updatedDone);
  }

  private notifyMatterDataRefresh(): void {
    try {
      const currentRevision = AppStorage.get(APP_STORAGE_KEYS.MATTER_REVISION) as number || 0;
      AppStorage.set(APP_STORAGE_KEYS.MATTER_REVISION, currentRevision + 1);
      emitter.emit('updateMatterItem');
      hilog.info(0x0000, TAG, 'updating matter item')
      this.notifyStateChanged();
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to emit matter refresh event: ${JSON.stringify(error)}`);
    }
  }

  private notifyStateChanged(): void {
    if (this.stateListeners.length === 0) {
      return;
    }
    this.stateListeners.forEach((listener: () => void) => {
      try {
        listener();
      } catch (error) {
        hilog.error(0x0000, TAG, `State listener failed: ${JSON.stringify(error)}`);
      }
    });
  }

  private getPersistedRunningSnapshot(): AutoStopRunningSnapshot | undefined {
    return getAutoStopRunningSnapshotFromAppStorage();
  }

  private persistRunningSnapshot(snapshot?: AutoStopRunningSnapshot | null): void {
    persistAutoStopRunningSnapshot(preferencesUtil, snapshot);
  }

  private migrateRunningSnapshotAfterSplit(originalRecord: TimeRecord, splitRecord: TimeRecord, source: string): void {
    migrateAutoStopRunningSnapshotAfterSplit(originalRecord, splitRecord, source);
  }

  private writeRunningSnapshot(activityId: string, recordId: string, startTime: number, source: string): void {
    const snapshot = buildAutoStopRunningSnapshotForCurrentSettings(activityId, recordId, startTime);
    this.persistRunningSnapshot(snapshot);
    hilog.info(
      0x0000,
      TAG,
      `AutoStop snapshot persisted, source=${source}, activityId=${snapshot.activityId}, recordId=${snapshot.recordId}, enabled=${snapshot.enabledAtStart}, limitSeconds=${snapshot.limitSeconds}`
    );
  }

  private clearRunningSnapshotForActivity(
    activityId: string,
    source: string,
    recordId?: string,
    startTime?: number
  ): void {
    const snapshot = this.getPersistedRunningSnapshot();
    if (!snapshot) {
      return;
    }

    const normalizedActivityId: string = activityId.trim();
    const matchesRecord = recordId !== undefined
      && startTime !== undefined
      && doesAutoStopRunningSnapshotMatch(snapshot, normalizedActivityId, recordId, startTime);
    const matchesActivity = normalizedActivityId.length === 0 || snapshot.activityId === normalizedActivityId;

    if (!matchesRecord && !matchesActivity) {
      hilog.warn(
        0x0000,
        TAG,
        `AutoStop snapshot cleanup skipped due to mismatch, source=${source}, targetActivityId=${normalizedActivityId}, snapshotActivityId=${snapshot.activityId}, snapshotRecordId=${snapshot.recordId}`
      );
      return;
    }

    this.persistRunningSnapshot(undefined);
    hilog.info(
      0x0000,
      TAG,
      `AutoStop snapshot cleared, source=${source}, activityId=${snapshot.activityId}, recordId=${snapshot.recordId}`
    );
  }

  private reconcileRunningSnapshot(record: TimeRecord, source: string): void {
    const snapshot = this.getPersistedRunningSnapshot();
    if (!snapshot) {
      hilog.info(
        0x0000,
        TAG,
        `AutoStop snapshot missing, source=${source}, activityId=${record.activityId}, recordId=${record.id}`
      );
      return;
    }

    if (doesAutoStopRunningSnapshotMatch(snapshot, record.activityId, record.id, record.startTime)) {
      hilog.info(
        0x0000,
        TAG,
        `AutoStop snapshot matched, source=${source}, activityId=${record.activityId}, recordId=${record.id}`
      );
      return;
    }

    hilog.warn(
      0x0000,
      TAG,
      `AutoStop snapshot mismatch, source=${source}, activityId=${record.activityId}, recordId=${record.id}, snapshotActivityId=${snapshot.activityId}, snapshotRecordId=${snapshot.recordId}`
    );
    this.persistRunningSnapshot(undefined);
  }

  private async finalizeStoppedState(
    item: MatterItemModel,
    activeRecord: TimeRecord,
    source: string,
    didSplitRecord: boolean,
    shouldStopLiveView: boolean
  ): Promise<MatterItemStateSnapshot> {
    const state = this.getOrCreateState(item.id);
    this.clearRunningSnapshotForActivity(item.id, source, activeRecord.id, activeRecord.startTime);

    state.isRunning = false;
    state.status = MatterStatus.PAUSED;
    state.record = undefined;
    state.currentRecordId = '';
    state.lastKnownStartTime = 0;
    state.restartBackgroundTask = false;

    // Phase 2c-2：旧停止链路的计时键直写已删除——会话清快照后由 store 投影单写 idle 键
    this.stopBackgroundTask(item.id);

    if (shouldStopLiveView) {
      try {
        await liveViewController.stopLiveView();
      } catch (error) {
        hilog.warn(0x0000, TAG, `AutoStop live view cleanup skipped, source=${source}, error=${JSON.stringify(error)}`);
      }
    }

    const updatedDuration = await todayActivityService.getTodayTotalDuration(item.id);
    state.durationInMilliseconds = updatedDuration;
    item.status = MatterStatus.PAUSED;
    item.durationInMilliseconds = updatedDuration;

    await this.syncPauseCollections(item, updatedDuration);

    if (didSplitRecord) {
      this.notifyMatterDataRefresh();
    } else {
      this.notifyStateChanged();
    }
    return this.snapshot(item.id);
  }

  /** onTick 跨天检查的分钟去重戳（Phase 3：分钟边界才做 DB 级检查）。 */
  private lastTickMinuteStamp: number = -1;

  /**
   * ticker 效应入口（Phase 3，boot 注册一次，承接原 MatterItem TextTimer.onTimer 职责）：
   * 1) 自动停止到点检查——先做廉价键预检，已到限时才触发（避免每秒查库）；
   * 2) 跨天拆分——分钟边界检查运行记录是否跨日，跨日则拆分并 adopt 刷新快照。
   */
  handleSessionTick(nowMs: number): void {
    const session = recordingSessionStore.snapshot();
    if (session === null || session.phase !== RecordingPhase.RUNNING) {
      this.lastTickMinuteStamp = -1;
      return;
    }

    const autoStopSnapshot = this.getPersistedRunningSnapshot();
    if (autoStopSnapshot && autoStopSnapshot.enabledAtStart && autoStopSnapshot.limitSeconds > 0
      && autoStopSnapshot.activityId === session.itemId
      && nowMs >= autoStopSnapshot.startTime + autoStopSnapshot.limitSeconds * 1000) {
      try {
        promptAction.openToast({ message: $r('app.string.dialog_message_2'), duration: 1000 });
      } catch (error) {
        hilog.warn(0x0000, TAG, `AutoStop toast failed: ${JSON.stringify(error)}`);
      }
      void this.enforceAutoStopIfNeeded(session.itemId, 'onTick');
      return;
    }

    const minuteStamp = Math.floor(nowMs / 60000);
    if (minuteStamp === this.lastTickMinuteStamp) {
      return;
    }
    this.lastTickMinuteStamp = minuteStamp;
    void this.alignRunningSessionAcrossDay(session, nowMs);
  }

  private async alignRunningSessionAcrossDay(session: SessionSnapshot, nowMs: number): Promise<void> {
    if (session.startTime >= TimeRecordUtil.getDayStart(nowMs)) {
      return;
    }
    try {
      const record = await todayActivityService.queryLatestTimeRecord(session.itemId);
      if (!record || record.endTime) {
        return;
      }
      const alignedRecord = await this.alignRecordToCurrentDay(record as TimeRecord);
      if (alignedRecord && alignedRecord.id !== record.id) {
        await recordingSessionStore.adoptOpenRecord(session.itemId);
      }
    } catch (error) {
      hilog.warn(0x0000, TAG, `onTick 跨天对齐失败: ${JSON.stringify(error)}`);
    }
  }

  async enforceAutoStopIfNeeded(itemId: string, source: string): Promise<MatterItemStateSnapshot | undefined> {
    const normalizedItemId: string = itemId.trim();
    if (normalizedItemId.length === 0) {
      return undefined;
    }
    return this.runAutoStopSingleFlight(normalizedItemId, source, async (): Promise<MatterItemStateSnapshot | undefined> => {
      const state = this.getOrCreateState(normalizedItemId);
      const activeRecord = await todayActivityService.queryLatestTimeRecord(normalizedItemId);
      if (!activeRecord || activeRecord.endTime) {
        return undefined;
      }

      state.record = activeRecord as TimeRecord;
      state.currentRecordId = activeRecord.id;
      state.lastKnownStartTime = activeRecord.startTime;

      const snapshot = this.getPersistedRunningSnapshot();
      if (!snapshot) {
        hilog.info(
          0x0000,
          TAG,
          `AutoStop skipped for legacy open record without snapshot, source=${source}, activityId=${normalizedItemId}, recordId=${activeRecord.id}`
        );
        return undefined;
      }

      if (!doesAutoStopRunningSnapshotMatch(snapshot, normalizedItemId, activeRecord.id, activeRecord.startTime)) {
        hilog.warn(
          0x0000,
          TAG,
          `AutoStop skipped due to snapshot mismatch, source=${source}, activityId=${normalizedItemId}, recordId=${activeRecord.id}, snapshotActivityId=${snapshot.activityId}, snapshotRecordId=${snapshot.recordId}`
        );
        this.persistRunningSnapshot(undefined);
        return undefined;
      }

      if (!snapshot.enabledAtStart || snapshot.limitSeconds <= 0) {
        hilog.info(
          0x0000,
          TAG,
          `AutoStop disabled in snapshot, source=${source}, activityId=${normalizedItemId}, recordId=${activeRecord.id}`
        );
        return undefined;
      }

      const forcedEndTimeMs: number = snapshot.startTime + snapshot.limitSeconds * 1000;
      const now: number = Date.now();
      if (now < forcedEndTimeMs) {
        return undefined;
      }

      const item = await todayActivityService.getTodayMatterItemById(normalizedItemId);
      if (!item) {
        hilog.error(
          0x0000,
          TAG,
          `AutoStop failed because item was not found, source=${source}, activityId=${normalizedItemId}, recordId=${activeRecord.id}`
        );
        return undefined;
      }

      // 到点：经 store 停止；commands 层依持久化快照写入 forced endTime。
      // store 未收编该会话（ideapool/legacy 直写键）时先以 DB 为准收编。
      if (this.sessionSnapshotFor(normalizedItemId) === null) {
        await recordingSessionStore.adoptOpenRecord(normalizedItemId);
      }
      const stopResult = await recordingSessionStore.stop(normalizedItemId);
      if (stopResult === StopResult.SUCCESS) {
        await this.finalizeStoppedState(item, activeRecord as TimeRecord, `auto-stop-${source}`, false, true);
        return this.snapshot(normalizedItemId);
      }
      if (stopResult === StopResult.NOT_RUNNING) {
        // 收编后仍无会话（收编失败/竞态）：保留直落库兜底（forced endTime 语义一致），再以 adopt 对账键
        const directResult =
          await todayActivityService.stopTimeRecordAtDetailed(normalizedItemId, activeRecord.id, forcedEndTimeMs);
        const disposition = await this.finalizeStopResult(
          item,
          activeRecord as TimeRecord,
          `auto-stop-${source}`,
          false,
          true,
          directResult
        );
        if (disposition === StopFinalizeDisposition.FAILED) {
          return undefined;
        }
        await recordingSessionStore.adoptOpenRecord(normalizedItemId);
        return this.snapshot(normalizedItemId);
      }
      hilog.error(
        0x0000,
        TAG,
        `AutoStop store stop failed, source=${source}, activityId=${normalizedItemId}, recordId=${activeRecord.id}, result=${stopResult}`
      );
      return undefined;
    });
  }

  private async syncPauseCollections(item: MatterItemModel, durationInMilliseconds: number): Promise<void> {
    item.status = MatterStatus.PAUSED;
    item.durationInMilliseconds = durationInMilliseconds;

    const existingDoneRaw = AppStorage.get(APP_STORAGE_KEYS.DONE) as (MatterItemModel | MatterItemModelInit)[] | undefined;
    const existingDone = existingDoneRaw ? MatterItemModel.ensureList(existingDoneRaw) : [];
    const updatedDone: MatterItemModel[] = [];

    for (let i = 0; i < existingDone.length; i++) {
      const matter = existingDone[i];
      if (matter.id === item.id) {
        const pausedMatter = new MatterItemModel({
          id: matter.id,
          title: matter.title,
          label: matter.label,
          labelColor: matter.labelColor,
          status: MatterStatus.PAUSED,
          durationInMilliseconds: durationInMilliseconds
        });
        updatedDone.push(pausedMatter);
      } else {
        updatedDone.push(MatterItemModel.from(matter));
      }
    }

    AppStorage.set(APP_STORAGE_KEYS.DONE, updatedDone);
  }

  async start(item: MatterItemModel): Promise<MatterItemStateSnapshot | undefined> {
    return this.startViaStore(item, 'start');
  }

  async continue(item: MatterItemModel): Promise<MatterItemStateSnapshot | undefined> {
    return this.startViaStore(item, 'continue');
  }

  /**
   * start/continue 共用链路（Phase 2c-1）：会话建立走 recordingSessionStore，
   * 建库与验证在 store 注入的命令内完成；运行键由 store 投影单写。
   */
  private async startViaStore(item: MatterItemModel, source: string): Promise<MatterItemStateSnapshot | undefined> {
    if (!this.canStart(item)) {
      return undefined;
    }

    const state = this.getOrCreateState(item.id);

    try {
      hilog.info(0x0000, TAG, `${source === 'start' ? '开始计时' : '继续计时'}: ${item.title}`);

      const result = await recordingSessionStore.start(item.id);
      if (result !== StartResult.SUCCESS) {
        hilog.error(0x0000, TAG, `${source} 计时失败: ${item.title}, result=${result}`);
        return undefined;
      }

      const session = recordingSessionStore.snapshot();
      if (!session || session.itemId !== item.id || session.recordId === '') {
        hilog.error(0x0000, TAG, `${source} 计时后快照校验失败: ${item.title}`);
        return undefined;
      }

      this.writeRunningSnapshot(session.itemId, session.recordId, session.startTime, source);
      state.currentRecordId = session.recordId;
      state.isRunning = true;
      state.status = MatterStatus.RECORDING;
      state.lastKnownStartTime = session.startTime;
      state.restartBackgroundTask = true;
      if (source === 'start') {
        state.durationInMilliseconds = item.durationInMilliseconds;
      }

      this.moveItemToRunningCollections(item);

      hilog.info(0x0000, TAG, `${source} 计时成功: ${item.title}, 记录ID: ${session.recordId}`);
      this.notifyStateChanged();
      return this.snapshot(item.id);
    } catch (error) {
      hilog.error(0x0000, TAG, `${source} 计时异常: ${item.title}, ${JSON.stringify(error)}`);
      // store 失败路径自身保证回 Idle 且不发事件，无需重置运行键
      state.isRunning = false;
      state.status = item.status;
      state.restartBackgroundTask = false;
      return undefined;
    }
  }

  /**
   * 停止链路（Phase 2c-2）：预检自动停止 → store.stop（forced endTime 与跨天拆分在
   * TodaySessionCommands.stopSession 内完成）→ finalizeStoppedState 承接效应。
   * store 未收编的会话（ideapool/legacy）先 adopt 以 DB 为准收编。
   */
  async stop(item: MatterItemModel): Promise<MatterItemStateSnapshot | undefined> {
    const state = this.getOrCreateState(item.id);

    if (!state.isRunning && state.status !== MatterStatus.PAUSED && this.sessionSnapshotFor(item.id) === null) {
      hilog.info(0x0000, TAG, `计时器未运行且未暂停，无需停止: ${item.title}`);
      return this.snapshot(item.id);
    }

    try {
      const existingRecord = await todayActivityService.queryLatestTimeRecord(item.id);
      if (!existingRecord) {
        hilog.error(0x0000, TAG, `停止计时失败: 找不到匹配的活跃记录, ${item.title}`);
        return undefined;
      }

      const preSplitAutoStoppedSnapshot = await this.enforceAutoStopIfNeeded(item.id, 'stop-before-cross-day-split');
      if (preSplitAutoStoppedSnapshot) {
        return preSplitAutoStoppedSnapshot;
      }

      if (existingRecord.endTime) {
        hilog.warn(0x0000, TAG, `停止计时时发现记录已结束，尝试使用现有数据: ${existingRecord.id}`);
      }

      // 拆分预测（决定刷新粒度）：startTime 早于今日 0 点即视为将拆分
      const didSplitRecord = existingRecord.startTime < TimeRecordUtil.getDayStart(Date.now());

      if (this.sessionSnapshotFor(item.id) === null) {
        await recordingSessionStore.adoptOpenRecord(item.id);
      }
      const stopResult = await recordingSessionStore.stop(item.id);
      if (stopResult === StopResult.DB_ERROR) {
        hilog.error(0x0000, TAG, `停止计时失败: ${item.title}, result=${stopResult}`);
        return undefined;
      }

      if (stopResult === StopResult.NOT_RUNNING) {
        // 收编后仍无会话（记录已结束/外部已停）：按已落定处理
        const settledResult = existingRecord.endTime
          ? StopTimeRecordResult.ALREADY_STOPPED
          : await todayActivityService.stopTimeRecordDetailed(item.id, existingRecord.id);
        const disposition =
          await this.finalizeStopResult(item, existingRecord as TimeRecord, 'stop', didSplitRecord, false, settledResult);
        if (disposition === StopFinalizeDisposition.FAILED) {
          return undefined;
        }
        await recordingSessionStore.adoptOpenRecord(item.id);
        return this.snapshot(item.id);
      }

      await this.finalizeStoppedState(item, existingRecord as TimeRecord, 'stop', didSplitRecord, false);
      return this.snapshot(item.id);
    } catch (error) {
      hilog.error(0x0000, TAG, `停止计时异常: ${item.title}, ${JSON.stringify(error)}`);
      return undefined;
    }
  }

  async initialize(item: MatterItemModel): Promise<MatterItemStateSnapshot> {
    const state = this.getOrCreateState(item.id);
    try {
      hilog.info(0x0000, TAG, `初始化事项状态: ${item.title}`);
      state.status = item.status;
      state.durationInMilliseconds = item.durationInMilliseconds;
      state.restartBackgroundTask = this.sessionSnapshotFor(item.id) !== null;

      let latestRecord = await todayActivityService.queryLatestTimeRecord(item.id);
      if (latestRecord && !latestRecord.endTime) {
        const autoStoppedSnapshot = await this.enforceAutoStopIfNeeded(item.id, 'initialize-before-cross-day-split');
        if (autoStoppedSnapshot) {
          return autoStoppedSnapshot;
        }
        const originalRecordId = latestRecord.id;
        const alignedRecord = await this.alignRecordToCurrentDay(latestRecord as TimeRecord);
        latestRecord = alignedRecord || latestRecord;
        state.record = latestRecord as TimeRecord;
        state.currentRecordId = latestRecord.id;
        state.lastKnownStartTime = latestRecord.startTime;
        this.reconcileRunningSnapshot(latestRecord as TimeRecord, 'initialize');
        if (alignedRecord && alignedRecord.id !== originalRecordId
          && this.sessionSnapshotFor(item.id) !== null) {
          // 拆分换了 recordId：以 DB 为准刷新 store 快照（投影随身份键更新）
          await recordingSessionStore.adoptOpenRecord(item.id);
        }
      } else {
        state.record = undefined;
        state.currentRecordId = '';
        state.lastKnownStartTime = 0;
        this.clearRunningSnapshotForActivity(item.id, 'initialize');
      }

      // 对账基准（Phase 4-5）：store 快照为唯一会话真值
      const hasActiveRecord = !!state.record && !state.record.endTime;
      const globalSession = recordingSessionStore.snapshot();
      let isRunningSignal = this.sessionSnapshotFor(item.id) !== null;
      const isItemRecording = state.status === MatterStatus.RECORDING;

      hilog.info(0x0000, TAG,
        `Sync Restart: initialize item=${item.id}, status=${state.status}, hasActiveRecord=${hasActiveRecord}, sessionRunning=${isRunningSignal}, globalItem=${globalSession ? globalSession.itemId : ''}`);

      if (hasActiveRecord && !isRunningSignal && (globalSession === null || globalSession.itemId === item.id)) {
        // store 未跟踪该活跃记录而全局槽空闲/指向本 item（恢复未跑）：以 DB 为准收编 store
        await recordingSessionStore.adoptOpenRecord(item.id);
        isRunningSignal = this.sessionSnapshotFor(item.id) !== null;
      }

      if (hasActiveRecord && !isRunningSignal) {
        hilog.warn(0x0000, TAG, `状态不一致: ${item.title} 有活跃记录但不是运行会话`);
        if (state.currentRecordId) {
          hilog.warn(0x0000, TAG,
            `Sync Restart: stopping stray active record ${state.currentRecordId} for item=${item.id} because global runningId=${this.getGlobalRunningItemId() || '<empty>'}`);
          await todayActivityService.stopTimeRecord(item.id, state.currentRecordId);
          this.clearRunningSnapshotForActivity(item.id, 'initialize-stray-record', state.currentRecordId, state.lastKnownStartTime);
        }
        state.isRunning = false;
        state.status = MatterStatus.PAUSED;
        state.currentRecordId = '';
        state.record = undefined;
        state.restartBackgroundTask = false;
        const updatedDuration = await todayActivityService.getTodayTotalDuration(item.id);
        state.durationInMilliseconds = updatedDuration;
        await this.syncPauseCollections(item, updatedDuration);
      } else if (isRunningSignal && !hasActiveRecord) {
        hilog.warn(0x0000, TAG, `状态不一致: ${item.title} 会话在运行但没有活跃记录`);
        state.isRunning = false;
        state.status = MatterStatus.PAUSED;
        state.currentRecordId = '';
        state.record = undefined;
        this.clearRunningSnapshotForActivity(item.id, 'initialize-session-without-record');
        state.restartBackgroundTask = false;
        // 键/会话对账：无未结束记录 → adopt 空结果清会话与键
        await recordingSessionStore.adoptOpenRecord(item.id);
        hilog.warn(0x0000, TAG,
          `Sync Restart: cleared running state for item=${item.id} due to missing active record, globalRunningId=${this.getGlobalRunningItemId()}`);
      } else if (isItemRecording && !isRunningSignal && !hasActiveRecord) {
        hilog.warn(0x0000, TAG, `状态不一致: ${item.title} 状态为RECORDING但没有活跃记录`);
        state.status = MatterStatus.PAUSED;
        state.isRunning = false;
        state.currentRecordId = '';
        this.clearRunningSnapshotForActivity(item.id, 'initialize-recording-without-record');
        await todayActivityService.updateActivityStatus(item.id, MatterStatus.PAUSED);
      } else if (isRunningSignal && hasActiveRecord && isItemRecording) {
        hilog.info(0x0000, TAG, `检测到正在运行的事项: ${item.title}`);
        const session = this.sessionSnapshotFor(item.id);
        state.isRunning = true;
        state.status = MatterStatus.RECORDING;
        state.currentRecordId = session ? session.recordId : (state.record?.id || '');
        const referenceStart = session ? session.startTime : (state.record?.startTime || 0);
        if (referenceStart > 0) {
          state.lastKnownStartTime = referenceStart;
          const elapsedSeconds = Math.floor((Date.now() - referenceStart) / 1000);
          state.restartBackgroundTask = true;
          hilog.info(0x0000, TAG,
            `Sync Restart: resumed running item=${item.id} record=${state.currentRecordId}, elapsed=${elapsedSeconds}s`);
        }
        // Phase 2c-3：旧恢复链路的计时键直写已删除——投影单写
      } else {
        state.isRunning = false;
        state.currentRecordId = '';
        state.restartBackgroundTask = false;
        hilog.info(0x0000, TAG,
          `Sync Restart: initialize fallback for item=${item.id}, globalRunningId=${this.getGlobalRunningItemId()}, hasActive=${hasActiveRecord}`);
      }

      hilog.info(0x0000, TAG, `初始化事项状态完成: ${item.title}, 运行状态=${state.isRunning}`);
      return this.snapshot(item.id);
    } catch (error) {
      hilog.error(0x0000, TAG, `初始化事项状态异常: ${JSON.stringify(error)}`);
      return this.snapshot(item.id);
    }
  }

  async refreshItemState(itemId: string): Promise<MatterItemStateSnapshot | undefined> {
    try {
      const state = this.getOrCreateState(itemId);
      hilog.info(0x0000, TAG,
        `Sync Matter Status: refresh start item=${itemId} stateStatus=${state.status} stateRunning=${state.isRunning} stateRecord=${state.currentRecordId} session=${this.sessionSnapshotFor(itemId)?.recordId ?? '<none>'}`);

      const latestItem = await todayActivityService.getTodayMatterItemById(itemId);
      if (!latestItem) {
        hilog.warn(0x0000, TAG, `refreshItemState: 未找到事项 ${itemId}`);
        return undefined;
      }

      state.status = latestItem.status;
      state.durationInMilliseconds = latestItem.durationInMilliseconds;

      const latestRecord = await todayActivityService.queryLatestTimeRecord(itemId);
      const hasActiveRecord = !!latestRecord && !latestRecord.endTime;

      if (hasActiveRecord && latestRecord) {
        const activeSession = this.sessionSnapshotFor(itemId);

        state.record = latestRecord as TimeRecord;
        state.lastKnownStartTime = latestRecord.startTime;
        this.reconcileRunningSnapshot(latestRecord as TimeRecord, 'refreshItemState');
        const autoStoppedSnapshot = await this.enforceAutoStopIfNeeded(itemId, 'refreshItemState');
        if (autoStoppedSnapshot) {
          return autoStoppedSnapshot;
        }

        if (activeSession !== null) {
          // 身份以 store 为准，明细以 DB 记录为准
          state.currentRecordId = activeSession.recordId;
          state.isRunning = true;
          state.status = MatterStatus.RECORDING;
          latestItem.status = MatterStatus.RECORDING;
          state.restartBackgroundTask = true;
        } else {
          // 全局槽被其他会话占据：仅同步明细，不伪造本 item 运行态、不写全局键
          state.isRunning = false;
          state.currentRecordId = latestRecord.id;
        }
        hilog.info(0x0000, TAG,
          `Sync Matter Status: refresh active record item=${itemId} record=${latestRecord.id} start=${latestRecord.startTime} sessionManaged=${activeSession !== null}`);
      } else {
        this.stopBackgroundTask(itemId);
        state.record = latestRecord ?? undefined;
        state.currentRecordId = '';
        state.lastKnownStartTime = 0;
        state.isRunning = false;
        state.restartBackgroundTask = false;
        this.clearRunningSnapshotForActivity(itemId, 'refreshItemState');

        if (this.sessionSnapshotFor(itemId) !== null) {
          // 会话对账：无未结束记录 → adopt 空结果清会话
          await recordingSessionStore.adoptOpenRecord(itemId);
        }
      }

      this.syncCollectionsWithItem(latestItem);
      this.notifyStateChanged();
      hilog.info(0x0000, TAG,
        `Sync Matter Status: refresh done item=${itemId} status=${state.status} isRunning=${state.isRunning} record=${state.currentRecordId} duration=${state.durationInMilliseconds} restartBackground=${state.restartBackgroundTask}`);
      return this.snapshot(itemId);
    } catch (error) {
      hilog.error(0x0000, TAG, `刷新事项状态失败: ${JSON.stringify(error)}`);
      return undefined;
    }
  }

  async reconcileGlobalRunningState(): Promise<boolean> {
    try {
      // Phase 2c-3：会话真值读 store 快照（legacy 键兜底 ideapool，Phase 4 收敛）
      const itemId = this.getGlobalRunningItemId();
      if (!itemId) {
        return false;
      }

      const recordId = this.getGlobalRunningRecordId();
      if (!recordId) {
        this.clearRunningState(itemId);
        return false;
      }

      const record = await todayActivityService.getTimeRecordById(recordId);
      if (!record || record.endTime || record.activityId !== itemId) {
        this.clearRunningState(itemId);
        return false;
      }

      const activity = await todayActivityService.getTodayMatterItemById(itemId);
      if (!activity) {
        this.clearRunningState(itemId);
        return false;
      }

      const autoStoppedSnapshot = await this.enforceAutoStopIfNeeded(itemId, 'reconcileGlobalRunningState');
      if (autoStoppedSnapshot) {
        return false;
      }

      return true;
    } catch (error) {
      hilog.error(0x0000, TAG, `全局运行状态校验失败: ${JSON.stringify(error)}`);
      return false;
    }
  }

  private clearRunningState(itemId: string): void {
    this.clearRunningSnapshotForActivity(itemId, 'clearRunningState');
    if (itemId) {
      this.stopBackgroundTask(itemId);
      const state = this.stateMap.get(itemId);
      if (state) {
        state.isRunning = false;
        state.currentRecordId = '';
        state.record = undefined;
        state.restartBackgroundTask = false;
      }
      // 键/会话对账：无未结束记录时 adopt 空结果清会话并由投影写 idle 键
      recordingSessionStore.adoptOpenRecord(itemId).catch((): void => {
        hilog.warn(0x0000, TAG, `clearRunningState adopt reconcile failed, item=${itemId}`);
      });
    }
  }

  async handleForegroundChange(item: MatterItemModel, appInForeground: boolean): Promise<MatterItemStateSnapshot> {
    const state = this.getOrCreateState(item.id);

    if (appInForeground) {
      state.lastForegroundTime = Date.now();
      // Phase 2c-3：全局运行信号读 store（legacy 键兜底）
      const globalRunningItemId = this.getGlobalRunningItemId();
      const globalRecordId = this.getGlobalRunningRecordId();
      const shouldRestoreFromGlobalState = globalRunningItemId === item.id && !!globalRecordId;
      if (shouldRestoreFromGlobalState) {
        state.isRunning = true;
        state.status = MatterStatus.RECORDING;
        state.currentRecordId = globalRecordId;
        return this.restoreOnForeground(item);
      }
      if (state.isRunning && state.currentRecordId) {
        return this.restoreOnForeground(item);
      }
      return this.snapshot(item.id);
    }

    if (state.isRunning && state.status === MatterStatus.RECORDING) {
      state.elapsedTimeBeforeBackground = Date.now() - (state.record?.startTime || Date.now());
      state.lastKnownStartTime = state.record?.startTime || 0;
    }
    return this.snapshot(item.id);
  }

  async restoreOnForeground(item: MatterItemModel): Promise<MatterItemStateSnapshot> {
    const existingFlight = this.restoreFlights.get(item.id);
    if (existingFlight) {
      hilog.info(0x0000, TAG, `Foreground restore reused, item=${item.id}`);
      return existingFlight;
    }

    const flight = (async (): Promise<MatterItemStateSnapshot> => {
      const state = this.getOrCreateState(item.id);
      try {
        let targetRecordId: string = state.currentRecordId.trim();
        const globalRunningItemId = this.getGlobalRunningItemId();
        const globalRecordId = this.getGlobalRunningRecordId();

        if (!targetRecordId && globalRunningItemId === item.id && globalRecordId) {
          targetRecordId = globalRecordId;
          state.currentRecordId = globalRecordId;
        }

        let record: TimeRecord | null = null;
        if (targetRecordId) {
          record = await todayActivityService.getTimeRecordById(targetRecordId);
        }

        if ((!record || record.endTime || record.activityId !== item.id) && globalRunningItemId === item.id) {
          const latestRecord = await todayActivityService.queryLatestTimeRecord(item.id);
          if (latestRecord && !latestRecord.endTime) {
            record = latestRecord as TimeRecord;
            state.currentRecordId = latestRecord.id;
          }
        }

        if (!record || record.endTime || record.activityId !== item.id) {
          hilog.error(0x0000, TAG, `恢复计时失败: 找不到有效的活跃记录`);
          state.isRunning = false;
          state.currentRecordId = '';
          this.clearRunningSnapshotForActivity(item.id, 'restoreOnForeground-invalid-record');
          state.restartBackgroundTask = false;
          // 键/会话对账：无有效记录 → adopt 空结果清会话与键
          await recordingSessionStore.adoptOpenRecord(item.id);
          return this.snapshot(item.id);
        }

        const preSplitAutoStoppedSnapshot =
          await this.enforceAutoStopIfNeeded(item.id, 'restoreOnForeground-before-cross-day-split');
        if (preSplitAutoStoppedSnapshot) {
          return preSplitAutoStoppedSnapshot;
        }

        const alignedRecord = await this.alignRecordToCurrentDay(record as TimeRecord);
        const activeRecord = alignedRecord || record;
        this.reconcileRunningSnapshot(activeRecord as TimeRecord, 'restoreOnForeground');

        const autoStoppedSnapshot = await this.enforceAutoStopIfNeeded(item.id, 'restoreOnForeground');
        if (autoStoppedSnapshot) {
          return autoStoppedSnapshot;
        }

        if (activeRecord.id !== state.currentRecordId) {
          hilog.info(0x0000, TAG, `恢复时检测到新的当日记录，更新记录ID: ${state.currentRecordId} -> ${activeRecord.id}`);
          state.currentRecordId = activeRecord.id;
        }

        const shouldRestartBackgroundTask =
          state.restartBackgroundTask || this.sessionSnapshotFor(item.id) !== null;
        state.record = activeRecord as TimeRecord;
        state.lastKnownStartTime = activeRecord.startTime;
        state.restartBackgroundTask = shouldRestartBackgroundTask;
        state.isRunning = true;
        state.status = MatterStatus.RECORDING;

        // store 快照对齐：拆分换了 recordId 时以 DB 为准刷新会话
        const currentSession = this.sessionSnapshotFor(item.id);
        if (currentSession !== null && currentSession.recordId !== activeRecord.id) {
          await recordingSessionStore.adoptOpenRecord(item.id);
        }

        return this.snapshot(item.id);
      } catch (error) {
        hilog.error(0x0000, TAG, `恢复计时异常: ${JSON.stringify(error)}`);
        state.isRunning = false;
        state.currentRecordId = '';
        this.clearRunningSnapshotForActivity(item.id, 'restoreOnForeground-error');
        state.restartBackgroundTask = false;
        await recordingSessionStore.adoptOpenRecord(item.id);
        return this.snapshot(item.id);
      } finally {
        this.restoreFlights.delete(item.id);
      }
    })();

    this.restoreFlights.set(item.id, flight);
    return flight;
  }

  consumeRestartBackgroundFlag(itemId: string): void {
    // Phase 4-5：协议收进 stateMap（原 AppStorage 键协议随投影瘦身移除）
    this.getOrCreateState(itemId).restartBackgroundTask = false;
  }

  async ensureBackgroundTask(itemId: string, context: Context, source: string): Promise<boolean> {
    hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ensure begin itemId=${itemId} source=${source}`);
    if (!itemId) {
      hilog.warn(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ensure skipped empty itemId source=${source}`);
      return false;
    }

    const snapshot = await this.refreshItemState(itemId);
    if (!snapshot?.isRunning) {
      hilog.warn(
        0x0000,
        TAG,
        `${BACKGROUND_TASK_LOG_PREFIX}: ensure skipped not running itemId=${itemId} source=${source} snapshotRunning=${snapshot?.isRunning ?? false}`
      );
      return false;
    }

    const item = await todayActivityService.getTodayMatterItemById(itemId);
    if (!item) {
      hilog.warn(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ensure item not found itemId=${itemId} source=${source}`);
      return false;
    }

    await this.requestBackgroundTaskStart(item, context, source);
    this.consumeRestartBackgroundFlag(itemId);
    return this.getOrCreateState(itemId).backgroundTaskId !== -1;
  }

  startBackgroundTask(item: MatterItemModel, context: Context): void {
    const state = this.getOrCreateState(item.id);
    hilog.info(
      0x0000,
      TAG,
      `${BACKGROUND_TASK_LOG_PREFIX}: start requested itemId=${item.id} running=${state.isRunning} taskId=${state.backgroundTaskId} recordId=${state.currentRecordId}`
    );

    if (!state.isRunning) {
      hilog.warn(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: start skipped because item is not running itemId=${item.id}`);
      return;
    }

    void this.requestBackgroundTaskStart(item, context, 'MatterItem');
  }

  private requestBackgroundTaskStart(item: MatterItemModel, context: Context, source: string): Promise<void> {
    const handle = this.backgroundHandles.get(item.id) || {};
    handle.context = context;
    this.backgroundHandles.set(item.id, handle);
    const requestVersion = this.getBackgroundRequestVersion(item.id);
    return this.enqueueBackgroundTaskOperation(item.id, 'start', async (): Promise<void> => {
      await this.startBackgroundTaskNow(item, context, source, requestVersion);
    });
  }

  private async startBackgroundTaskNow(
    item: MatterItemModel,
    context: Context,
    source: string,
    requestVersion: number
  ): Promise<void> {
    const state = this.getOrCreateState(item.id);
    if (requestVersion !== this.getBackgroundRequestVersion(item.id) || !state.isRunning) {
      hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: start invalidated itemId=${item.id} source=${source}`);
      return;
    }

    const handle = this.backgroundHandles.get(item.id) || {};
    handle.context = context;
    this.backgroundHandles.set(item.id, handle);

    if (state.backgroundTaskId !== -1) {
      hilog.info(
        0x0000,
        TAG,
        `${BACKGROUND_TASK_LOG_PREFIX}: start reused tracked task itemId=${item.id} source=${source} taskId=${state.backgroundTaskId}`
      );
      this.scheduleBackgroundUpdates(item.id);
      return;
    }

    try {
      const existingTasks = await backgroundTaskManager.getAllContinuousTasks(context);
      const existingTask = existingTasks.find((task: backgroundTaskManager.ContinuousTaskInfo): boolean => {
        return task.abilityName === 'PhoneAbility' && task.backgroundModes.includes('dataTransfer');
      });
      if (existingTask) {
        if (requestVersion !== this.getBackgroundRequestVersion(item.id) || !state.isRunning) {
          hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: adoption invalidated itemId=${item.id} source=${source}`);
          return;
        }
        state.backgroundTaskId = existingTask.continuousTaskId;
        state.continuousTaskNotificationId = existingTask.notificationId;
        hilog.info(
          0x0000,
          TAG,
          `${BACKGROUND_TASK_LOG_PREFIX}: adopted system task itemId=${item.id} source=${source} taskId=${existingTask.continuousTaskId}`
        );
        this.scheduleBackgroundUpdates(item.id);
        return;
      }
    } catch (error) {
      hilog.warn(
        0x0000,
        TAG,
        `${BACKGROUND_TASK_LOG_PREFIX}: query existing task failed itemId=${item.id} error=${JSON.stringify(error)}`
      );
    }

    if (requestVersion !== this.getBackgroundRequestVersion(item.id) || !state.isRunning) {
      hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: start invalidated after query itemId=${item.id} source=${source}`);
      return;
    }

    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{ bundleName: 'com.landylee.flowdiary', abilityName: 'PhoneAbility' }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    try {
      const wantAgentObj: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      if (requestVersion !== this.getBackgroundRequestVersion(item.id) || !state.isRunning) {
        hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: start invalidated after wantAgent itemId=${item.id}`);
        return;
      }

      const result = await backgroundTaskManager.startBackgroundRunning(context, ['dataTransfer'], wantAgentObj);
      const taskId = result.continuousTaskId ?? 0;
      if (requestVersion !== this.getBackgroundRequestVersion(item.id) || !state.isRunning) {
        hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: started task became stale, stopping itemId=${item.id} taskId=${taskId}`);
        await this.stopBackgroundRunningNow(context, taskId);
        return;
      }

      state.backgroundTaskId = taskId;
      state.continuousTaskNotificationId = result.notificationId ?? -1;
      hilog.info(
        0x0000,
        TAG,
        `${BACKGROUND_TASK_LOG_PREFIX}: start success itemId=${item.id} source=${source} taskId=${taskId} notificationId=${state.continuousTaskNotificationId}`
      );
      this.scheduleBackgroundUpdates(item.id);
    } catch (error) {
      state.backgroundTaskId = -1;
      state.continuousTaskNotificationId = -1;
      hilog.error(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: start failed itemId=${item.id} error=${JSON.stringify(error)}`);
    }
  }

  private async updateBackgroundTask(itemId: string): Promise<void> {
    const state = this.getOrCreateState(itemId);
    const handle = this.backgroundHandles.get(itemId);
    hilog.info(
      0x0000,
      TAG,
      `${BACKGROUND_TASK_LOG_PREFIX}: update tick itemId=${itemId} running=${state.isRunning} taskId=${state.backgroundTaskId} recordId=${state.currentRecordId} hasContext=${handle?.context !== undefined}`
    );
    if (!state.isRunning) {
      hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: update stopped because item is no longer running itemId=${itemId}`);
      this.clearBackgroundUpdateInterval(state);
      return;
    }

    const autoStoppedSnapshot = await this.enforceAutoStopIfNeeded(itemId, 'backgroundTask');
    if (autoStoppedSnapshot) {
      this.clearBackgroundUpdateInterval(state);
      return;
    }

    if (!handle || !handle.context) {
      hilog.warn(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: update missing context itemId=${itemId}`);
      this.clearBackgroundUpdateInterval(state);
      return;
    }

    if (state.backgroundTaskId === -1) {
      hilog.warn(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: update stopped because task is unavailable itemId=${itemId}`);
      this.clearBackgroundUpdateInterval(state);
      return;
    }

    const requestVersion = this.getBackgroundRequestVersion(itemId);
    await this.enqueueBackgroundTaskOperation(itemId, 'update', async (): Promise<void> => {
      if (
        requestVersion !== this.getBackgroundRequestVersion(itemId) ||
        !state.isRunning ||
        state.backgroundTaskId === -1
      ) {
        return;
      }
      try {
        await backgroundTaskManager.updateBackgroundRunning(handle.context as Context, ['dataTransfer']);
        hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: update success itemId=${itemId} taskId=${state.backgroundTaskId}`);
        this.publishBackgroundProgress(itemId);
      } catch (error) {
        hilog.error(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: update failed itemId=${itemId} error=${JSON.stringify(error)}`);
        state.backgroundTaskId = -1;
        state.continuousTaskNotificationId = -1;
        this.clearBackgroundUpdateInterval(state);
      }
    });
  }

  stopBackgroundTask(itemId: string): void {
    const state = this.getOrCreateState(itemId);
    const handle = this.backgroundHandles.get(itemId);
    const requestVersion = this.invalidateBackgroundRequest(itemId);
    hilog.info(
      0x0000,
      TAG,
      `${BACKGROUND_TASK_LOG_PREFIX}: stop requested itemId=${itemId} taskId=${state.backgroundTaskId} hasContext=${handle?.context !== undefined} version=${requestVersion}`
    );

    this.clearBackgroundUpdateInterval(state);
    void this.enqueueBackgroundTaskOperation(itemId, 'stop', async (): Promise<void> => {
      const currentHandle = this.backgroundHandles.get(itemId);
      const taskId = state.backgroundTaskId;
      if (currentHandle?.context && taskId !== -1) {
        try {
          await this.stopBackgroundRunningNow(currentHandle.context, taskId);
          hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: stop success itemId=${itemId} taskId=${taskId}`);
        } catch (error) {
          hilog.error(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: stop failed itemId=${itemId} error=${JSON.stringify(error)}`);
        }
      }

      state.backgroundTaskId = -1;
      state.continuousTaskNotificationId = -1;
      this.backgroundHandles.delete(itemId);
    });
  }

  private async stopBackgroundRunningNow(context: Context, continuousTaskId: number): Promise<void> {
    if (continuousTaskId > 0) {
      await backgroundTaskManager.stopBackgroundRunning(context, continuousTaskId);
      return;
    }
    await backgroundTaskManager.stopBackgroundRunning(context);
  }

  private resolveItemTitle(itemId: string): string {
    const session = this.sessionSnapshotFor(itemId);
    if (session !== null && session.title !== '') {
      return session.title;
    }

    const doneList = this.readMatterCollection(APP_STORAGE_KEYS.DONE);
    const todoList = this.readMatterCollection(APP_STORAGE_KEYS.TODO);
    const target = doneList.find(item => item.id === itemId) || todoList.find(item => item.id === itemId);
    return target?.title || itemId;
  }
}
