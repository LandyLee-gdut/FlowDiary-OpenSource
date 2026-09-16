import { hilog } from '@kit.PerformanceAnalysisKit';
import { JSON } from '@kit.ArkTS';
import { PreferenceKeys, PreferencesUtil, preferencesUtil, TimeRecord } from 'base';

const DOMAIN: number = 0x0000;
const TAG: string = 'AutoStopSettings';
const HALF_HOUR_SECONDS: number = 30 * 60;
const MIN_AUTO_STOP_LIMIT_HALF_HOURS: number = 1;
const MAX_AUTO_STOP_LIMIT_HALF_HOURS: number = 16;
const MAX_LIVE_VIEW_DURATION_SECONDS: number = MAX_AUTO_STOP_LIMIT_HALF_HOURS * HALF_HOUR_SECONDS;

export const AUTO_STOP_ENABLED_DEFAULT: boolean = false;
export const AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT: number = 12;
export const AUTO_STOP_EMPTY_SNAPSHOT: string = '';
export const AUTO_STOP_ENABLED_APP_STORAGE_KEY: string = PreferenceKeys.AUTO_STOP_ENABLED;
export const AUTO_STOP_LIMIT_HALF_HOURS_APP_STORAGE_KEY: string = PreferenceKeys.AUTO_STOP_LIMIT_HALF_HOURS;
export const AUTO_STOP_RUNNING_SNAPSHOT_APP_STORAGE_KEY: string = PreferenceKeys.AUTO_STOP_RUNNING_SNAPSHOT;

export enum AutoStopRunningSnapshotState {
  EMPTY = 'empty',
  VALID = 'valid',
  DIRTY = 'dirty'
}

interface AutoStopRunningSnapshotShape {
  recordId?: string;
  activityId?: string;
  startTime?: number;
  limitSeconds?: number;
  enabledAtStart?: boolean;
}

export class AutoStopRunningSnapshot {
  recordId: string;
  activityId: string;
  startTime: number;
  limitSeconds: number;
  enabledAtStart: boolean;

  constructor(
    recordId: string,
    activityId: string,
    startTime: number,
    limitSeconds: number,
    enabledAtStart: boolean
  ) {
    this.recordId = recordId;
    this.activityId = activityId;
    this.startTime = startTime;
    this.limitSeconds = limitSeconds;
    this.enabledAtStart = enabledAtStart;
  }
}

export class AutoStopSettingsState {
  enabled: boolean;
  limitHalfHours: number;
  serializedSnapshot: string;
  snapshot?: AutoStopRunningSnapshot;
  snapshotState: AutoStopRunningSnapshotState;

  constructor(
    enabled: boolean,
    limitHalfHours: number,
    serializedSnapshot: string,
    snapshotState: AutoStopRunningSnapshotState,
    snapshot?: AutoStopRunningSnapshot
  ) {
    this.enabled = enabled;
    this.limitHalfHours = limitHalfHours;
    this.serializedSnapshot = serializedSnapshot;
    this.snapshotState = snapshotState;
    this.snapshot = snapshot;
  }
}

function normalizePositiveInteger(value: number): number {
  return Math.floor(value);
}

export function clampAutoStopLimitHalfHours(value: number): number {
  if (!Number.isFinite(value)) {
    return AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT;
  }
  const normalized: number = normalizePositiveInteger(value);
  if (normalized < MIN_AUTO_STOP_LIMIT_HALF_HOURS) {
    return MIN_AUTO_STOP_LIMIT_HALF_HOURS;
  }
  if (normalized > MAX_AUTO_STOP_LIMIT_HALF_HOURS) {
    return MAX_AUTO_STOP_LIMIT_HALF_HOURS;
  }
  return normalized;
}

export function autoStopLimitHalfHoursToSeconds(limitHalfHours: number): number {
  return clampAutoStopLimitHalfHours(limitHalfHours) * HALF_HOUR_SECONDS;
}

export function autoStopLimitSecondsToHalfHours(limitSeconds: number): number {
  if (!Number.isFinite(limitSeconds)) {
    return AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT;
  }
  return clampAutoStopLimitHalfHours(Math.floor(limitSeconds / HALF_HOUR_SECONDS));
}

export function isAutoStopEnabledInAppStorage(): boolean {
  const storedValue = AppStorage.get(AUTO_STOP_ENABLED_APP_STORAGE_KEY) as boolean | undefined;
  return typeof storedValue === 'boolean' ? storedValue : AUTO_STOP_ENABLED_DEFAULT;
}

export function getAutoStopLimitHalfHoursFromAppStorage(): number {
  const storedValue = AppStorage.get(AUTO_STOP_LIMIT_HALF_HOURS_APP_STORAGE_KEY) as number | undefined;
  if (typeof storedValue !== 'number') {
    return AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT;
  }
  return clampAutoStopLimitHalfHours(storedValue);
}

export function getAutoStopLimitSecondsFromAppStorage(): number {
  return autoStopLimitHalfHoursToSeconds(getAutoStopLimitHalfHoursFromAppStorage());
}

export function formatAutoStopLimitLabel(limitHalfHours: number): string {
  const normalizedLimit: number = clampAutoStopLimitHalfHours(limitHalfHours);
  if (normalizedLimit === MIN_AUTO_STOP_LIMIT_HALF_HOURS) {
    return '0.5小时';
  }
  if (normalizedLimit % 2 === 0) {
    return `${normalizedLimit / 2}小时`;
  }
  return `${Math.floor(normalizedLimit / 2)}.5小时`;
}

function validateAutoStopRunningSnapshot(
  candidate?: AutoStopRunningSnapshotShape
): AutoStopRunningSnapshot | undefined {
  if (!candidate) {
    return undefined;
  }
  const recordId: string = typeof candidate.recordId === 'string' ? candidate.recordId.trim() : '';
  const activityId: string = typeof candidate.activityId === 'string' ? candidate.activityId.trim() : '';
  const startTime: number = typeof candidate.startTime === 'number' ? candidate.startTime : Number.NaN;
  const limitSeconds: number = typeof candidate.limitSeconds === 'number' ? candidate.limitSeconds : Number.NaN;
  const enabledAtStart: boolean = typeof candidate.enabledAtStart === 'boolean' ? candidate.enabledAtStart : false;

  if (recordId.length === 0 || activityId.length === 0) {
    return undefined;
  }
  if (!Number.isFinite(startTime) || startTime <= 0) {
    return undefined;
  }
  if (!Number.isFinite(limitSeconds) || limitSeconds < 0) {
    return undefined;
  }
  if (enabledAtStart && limitSeconds <= 0) {
    return undefined;
  }
  const normalizedLimitSeconds: number = enabledAtStart
    ? Math.min(Math.floor(limitSeconds), MAX_AUTO_STOP_LIMIT_HALF_HOURS * HALF_HOUR_SECONDS)
    : 0;
  return new AutoStopRunningSnapshot(
    recordId,
    activityId,
    Math.floor(startTime),
    normalizedLimitSeconds,
    enabledAtStart
  );
}

export function parseAutoStopRunningSnapshot(
  rawValue: string
): AutoStopSettingsState {
  const normalizedRawValue: string = typeof rawValue === 'string' ? rawValue.trim() : '';
  if (normalizedRawValue.length === 0) {
    return new AutoStopSettingsState(
      AUTO_STOP_ENABLED_DEFAULT,
      AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT,
      AUTO_STOP_EMPTY_SNAPSHOT,
      AutoStopRunningSnapshotState.EMPTY
    );
  }

  try {
    const parsed = JSON.parse(normalizedRawValue) as AutoStopRunningSnapshotShape;
    const snapshot: AutoStopRunningSnapshot | undefined = validateAutoStopRunningSnapshot(parsed);
    if (!snapshot) {
      return new AutoStopSettingsState(
        AUTO_STOP_ENABLED_DEFAULT,
        AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT,
        AUTO_STOP_EMPTY_SNAPSHOT,
        AutoStopRunningSnapshotState.DIRTY
      );
    }
    return new AutoStopSettingsState(
      AUTO_STOP_ENABLED_DEFAULT,
      AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT,
      serializeAutoStopRunningSnapshot(snapshot),
      AutoStopRunningSnapshotState.VALID,
      snapshot
    );
  } catch (error) {
    hilog.warn(DOMAIN, TAG, `Failed to parse auto stop snapshot: ${JSON.stringify(error)}`);
    return new AutoStopSettingsState(
      AUTO_STOP_ENABLED_DEFAULT,
      AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT,
      AUTO_STOP_EMPTY_SNAPSHOT,
      AutoStopRunningSnapshotState.DIRTY
    );
  }
}

export function serializeAutoStopRunningSnapshot(snapshot?: AutoStopRunningSnapshot | null): string {
  if (!snapshot) {
    return AUTO_STOP_EMPTY_SNAPSHOT;
  }
  return JSON.stringify({
    recordId: snapshot.recordId,
    activityId: snapshot.activityId,
    startTime: Math.floor(snapshot.startTime),
    limitSeconds: Math.floor(snapshot.limitSeconds),
    enabledAtStart: snapshot.enabledAtStart
  });
}

export function getAutoStopRunningSnapshotFromAppStorage(): AutoStopRunningSnapshot | undefined {
  const rawValue = AppStorage.get(AUTO_STOP_RUNNING_SNAPSHOT_APP_STORAGE_KEY) as string | undefined;
  const serializedValue: string = typeof rawValue === 'string' ? rawValue : AUTO_STOP_EMPTY_SNAPSHOT;
  const parsedState = parseAutoStopRunningSnapshot(serializedValue);
  return parsedState.snapshotState === AutoStopRunningSnapshotState.VALID ? parsedState.snapshot : undefined;
}

export function doesAutoStopRunningSnapshotMatch(
  snapshot: AutoStopRunningSnapshot | undefined,
  activityId: string,
  recordId: string,
  startTime: number
): boolean {
  if (!snapshot) {
    return false;
  }
  const normalizedActivityId: string = activityId.trim();
  const normalizedRecordId: string = recordId.trim();
  if (normalizedActivityId.length === 0 || normalizedRecordId.length === 0) {
    return false;
  }
  const normalizedStartTime: number = Number.isFinite(startTime) && startTime > 0 ? Math.floor(startTime) : 0;
  return snapshot.activityId === normalizedActivityId
    && snapshot.recordId === normalizedRecordId
    && (normalizedStartTime === 0 || snapshot.startTime <= normalizedStartTime);
}

export function buildAutoStopRunningSnapshotForCurrentSettings(
  activityId: string,
  recordId: string,
  startTime: number
): AutoStopRunningSnapshot {
  const normalizedActivityId: string = activityId.trim();
  const normalizedRecordId: string = recordId.trim();
  const normalizedStartTime: number = Number.isFinite(startTime) && startTime > 0
    ? Math.floor(startTime)
    : Date.now();
  const autoStopEnabled: boolean = isAutoStopEnabledInAppStorage();
  const limitSeconds: number = autoStopEnabled
    ? getAutoStopLimitSecondsFromAppStorage()
    : MAX_LIVE_VIEW_DURATION_SECONDS;
  return new AutoStopRunningSnapshot(
    normalizedRecordId,
    normalizedActivityId,
    normalizedStartTime,
    limitSeconds,
    true
  );
}

/**
 * 到点自动停止的强制结束时间（Phase 2c-2）：持久化运行快照与
 * (activityId, recordId, startTime) 匹配且已到限时 → 返回 forced end 毫秒；否则 null。
 * TodaySessionCommands.stopSession 与 MatterItemStateManager.enforceAutoStopIfNeeded
 * 共用本函数，保证到点停止（无论经 store 还是直落库兜底）写出的 endTime 一致。
 */
export function resolveDueAutoStopForcedEndTime(
  activityId: string,
  recordId: string,
  startTime: number
): number | null {
  const snapshot = getAutoStopRunningSnapshotFromAppStorage();
  if (!snapshot) {
    return null;
  }
  if (!doesAutoStopRunningSnapshotMatch(snapshot, activityId, recordId, startTime)) {
    return null;
  }
  if (!snapshot.enabledAtStart || snapshot.limitSeconds <= 0) {
    return null;
  }
  const forcedEndTimeMs: number = snapshot.startTime + snapshot.limitSeconds * 1000;
  if (Date.now() < forcedEndTimeMs) {
    return null;
  }
  return forcedEndTimeMs;
}

/**
 * 跨天拆分后把持久化运行快照迁移到新尾记录（Phase 2c-2，从 manager 私有方法下沉）。
 * 仅当快照仍指向原记录时迁移；limit 计时基点保持原 startTime 不变。
 */
export function migrateAutoStopRunningSnapshotAfterSplit(
  originalRecord: TimeRecord,
  splitRecord: TimeRecord,
  source: string
): void {
  const snapshot = getAutoStopRunningSnapshotFromAppStorage();
  if (!snapshot) {
    return;
  }
  if (!doesAutoStopRunningSnapshotMatch(snapshot, originalRecord.activityId, originalRecord.id, originalRecord.startTime)) {
    return;
  }

  const migratedSnapshot = new AutoStopRunningSnapshot(
    splitRecord.id,
    splitRecord.activityId,
    snapshot.startTime,
    snapshot.limitSeconds,
    snapshot.enabledAtStart
  );
  persistAutoStopRunningSnapshot(preferencesUtil, migratedSnapshot);
  hilog.info(
    DOMAIN,
    TAG,
    `AutoStop snapshot migrated after record split, source=${source}, activityId=${splitRecord.activityId}, fromRecordId=${originalRecord.id}, toRecordId=${splitRecord.id}, originalStartTime=${snapshot.startTime}`
  );
}

export function persistAutoStopRunningSnapshot(
  preferencesUtil: PreferencesUtil,
  snapshot?: AutoStopRunningSnapshot | null
): string {
  ensureAutoStopAppStorageDefaults();

  const serializedSnapshot: string = serializeAutoStopRunningSnapshot(snapshot);
  AppStorage.setOrCreate(
    AUTO_STOP_RUNNING_SNAPSHOT_APP_STORAGE_KEY,
    serializedSnapshot.length > 0 ? serializedSnapshot : AUTO_STOP_EMPTY_SNAPSHOT
  );

  const preferenceStore = preferencesUtil.getPreferences();
  if (!preferenceStore) {
    hilog.warn(DOMAIN, TAG, 'Preferences unavailable when persisting running snapshot, AppStorage only.');
    return serializedSnapshot;
  }

  try {
    preferenceStore.putSync(
      PreferenceKeys.AUTO_STOP_RUNNING_SNAPSHOT,
      serializedSnapshot.length > 0 ? serializedSnapshot : AUTO_STOP_EMPTY_SNAPSHOT
    );
    if (preferencesUtil.requiresManualFlush()) {
      preferencesUtil.flush();
    }
  } catch (error) {
    hilog.error(
      DOMAIN,
      TAG,
      `Failed to persist running snapshot to preferences, keeping AppStorage value only: ${JSON.stringify(error)}`
    );
  }
  return serializedSnapshot;
}

export function ensureAutoStopAppStorageDefaults(): void {
  if (AppStorage.get(AUTO_STOP_ENABLED_APP_STORAGE_KEY) === undefined) {
    AppStorage.setOrCreate(AUTO_STOP_ENABLED_APP_STORAGE_KEY, AUTO_STOP_ENABLED_DEFAULT);
  }
  if (AppStorage.get(AUTO_STOP_LIMIT_HALF_HOURS_APP_STORAGE_KEY) === undefined) {
    AppStorage.setOrCreate(AUTO_STOP_LIMIT_HALF_HOURS_APP_STORAGE_KEY, AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT);
  }
  if (AppStorage.get(AUTO_STOP_RUNNING_SNAPSHOT_APP_STORAGE_KEY) === undefined) {
    AppStorage.setOrCreate(AUTO_STOP_RUNNING_SNAPSHOT_APP_STORAGE_KEY, AUTO_STOP_EMPTY_SNAPSHOT);
  }
}

export function syncAutoStopUserSettingsToAppStorage(
  enabled: boolean,
  limitHalfHours: number
): void {
  AppStorage.setOrCreate(AUTO_STOP_ENABLED_APP_STORAGE_KEY, enabled);
  AppStorage.setOrCreate(
    AUTO_STOP_LIMIT_HALF_HOURS_APP_STORAGE_KEY,
    clampAutoStopLimitHalfHours(limitHalfHours)
  );
}

export function syncAutoStopSettingsToAppStorage(
  enabled: boolean,
  limitHalfHours: number,
  serializedSnapshot: string
): void {
  syncAutoStopUserSettingsToAppStorage(enabled, limitHalfHours);
  AppStorage.setOrCreate(
    AUTO_STOP_RUNNING_SNAPSHOT_APP_STORAGE_KEY,
    serializedSnapshot.length > 0 ? serializedSnapshot : AUTO_STOP_EMPTY_SNAPSHOT
  );
}

export function hydrateAutoStopSettings(preferencesUtil: PreferencesUtil): AutoStopSettingsState {
  ensureAutoStopAppStorageDefaults();

  const preferenceStore = preferencesUtil.getPreferences();
  if (!preferenceStore) {
    const fallbackState = new AutoStopSettingsState(
      AUTO_STOP_ENABLED_DEFAULT,
      AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT,
      AUTO_STOP_EMPTY_SNAPSHOT,
      AutoStopRunningSnapshotState.EMPTY
    );
    syncAutoStopSettingsToAppStorage(
      fallbackState.enabled,
      fallbackState.limitHalfHours,
      fallbackState.serializedSnapshot
    );
    return fallbackState;
  }

  let shouldFlush: boolean = false;

  let enabled: boolean = AUTO_STOP_ENABLED_DEFAULT;
  if (!preferenceStore.hasSync(PreferenceKeys.AUTO_STOP_ENABLED)) {
    preferenceStore.putSync(PreferenceKeys.AUTO_STOP_ENABLED, AUTO_STOP_ENABLED_DEFAULT);
    shouldFlush = true;
  } else {
    enabled = !!preferenceStore.getSync(PreferenceKeys.AUTO_STOP_ENABLED, AUTO_STOP_ENABLED_DEFAULT);
  }

  let limitHalfHours: number = AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT;
  if (!preferenceStore.hasSync(PreferenceKeys.AUTO_STOP_LIMIT_HALF_HOURS)) {
    preferenceStore.putSync(PreferenceKeys.AUTO_STOP_LIMIT_HALF_HOURS, AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT);
    shouldFlush = true;
  } else {
    const storedLimit = preferenceStore.getSync(
      PreferenceKeys.AUTO_STOP_LIMIT_HALF_HOURS,
      AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT
    ) as number;
    const normalizedLimit = clampAutoStopLimitHalfHours(storedLimit);
    limitHalfHours = normalizedLimit;
    if (!Number.isFinite(storedLimit) || storedLimit !== normalizedLimit) {
      preferenceStore.putSync(PreferenceKeys.AUTO_STOP_LIMIT_HALF_HOURS, normalizedLimit);
      shouldFlush = true;
    }
  }

  let snapshotRaw: string = AUTO_STOP_EMPTY_SNAPSHOT;
  if (!preferenceStore.hasSync(PreferenceKeys.AUTO_STOP_RUNNING_SNAPSHOT)) {
    preferenceStore.putSync(PreferenceKeys.AUTO_STOP_RUNNING_SNAPSHOT, AUTO_STOP_EMPTY_SNAPSHOT);
    shouldFlush = true;
  } else {
    const storedSnapshotValue = preferenceStore.getSync(
      PreferenceKeys.AUTO_STOP_RUNNING_SNAPSHOT,
      AUTO_STOP_EMPTY_SNAPSHOT
    );
    snapshotRaw = typeof storedSnapshotValue === 'string' ? storedSnapshotValue : AUTO_STOP_EMPTY_SNAPSHOT;
    if (typeof storedSnapshotValue !== 'string') {
      shouldFlush = true;
      preferenceStore.putSync(PreferenceKeys.AUTO_STOP_RUNNING_SNAPSHOT, AUTO_STOP_EMPTY_SNAPSHOT);
    }
  }

  const parsedSnapshot = parseAutoStopRunningSnapshot(snapshotRaw);
  if (parsedSnapshot.snapshotState === AutoStopRunningSnapshotState.DIRTY) {
    hilog.warn(DOMAIN, TAG, 'Detected dirty auto stop snapshot, clearing to empty baseline.');
    preferenceStore.putSync(PreferenceKeys.AUTO_STOP_RUNNING_SNAPSHOT, AUTO_STOP_EMPTY_SNAPSHOT);
    shouldFlush = true;
  }

  if (shouldFlush && preferencesUtil.requiresManualFlush()) {
    preferencesUtil.flush();
  }

  const resolvedState = new AutoStopSettingsState(
    enabled,
    limitHalfHours,
    parsedSnapshot.snapshotState === AutoStopRunningSnapshotState.VALID
      ? parsedSnapshot.serializedSnapshot
      : AUTO_STOP_EMPTY_SNAPSHOT,
    parsedSnapshot.snapshotState,
    parsedSnapshot.snapshot
  );

  syncAutoStopSettingsToAppStorage(
    resolvedState.enabled,
    resolvedState.limitHalfHours,
    resolvedState.serializedSnapshot
  );
  return resolvedState;
}
