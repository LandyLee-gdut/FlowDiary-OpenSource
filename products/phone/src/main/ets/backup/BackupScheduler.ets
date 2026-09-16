import { bundleManager, common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BackupErrorCode,
  createAutoBackup,
  getAutoBackupDirState,
  PreferenceKeys,
  preferencesUtil,
  StorageKeys
} from 'base';

const TAG: string = 'BackupScheduler';
const TODAY_STORE_NAME: string = 'todayStore';
const AUTO_BACKUP_INTERVAL_MS: number = 60 * 60 * 1000;
const AUTO_BACKUP_MIN_INTERVAL_MS: number = 6 * 60 * 60 * 1000;
const DEFAULT_LAST_DAY: string = '';
const DEFAULT_LAST_RUN_AT: number = 0;
const DEFAULT_LAST_ERROR_CODE: number = 0;
const FALLBACK_APP_VERSION: string = '0.0.0';

interface ErrorLike {
  code?: number;
  message?: string;
}

interface AppInfoLike {
  versionName?: string;
}

interface BundleInfoLike {
  versionName?: string;
  appInfo?: AppInfoLike;
}

function formatError(err: object): string {
  hilog.info(0x0000, TAG, 'databackup.BackupScheduler.formatError');
  const maybeError = err as ErrorLike;
  if (maybeError && typeof maybeError.message === 'string' && maybeError.message.length > 0) {
    return maybeError.message;
  }
  try {
    return JSON.stringify(err);
  } catch (_error) {
    return String(err);
  }
}

function formatErrorCode(err: object): string {
  hilog.info(0x0000, TAG, 'databackup.BackupScheduler.formatErrorCode');
  const maybeError = err as ErrorLike;
  if (maybeError && typeof maybeError.code === 'number') {
    return maybeError.code.toString();
  }
  return '-1';
}

function buildDayKey(timestamp: number): string {
  hilog.info(0x0000, TAG, 'databackup.BackupScheduler.buildDayKey');
  const date = new Date(timestamp);
  const year = date.getFullYear().toString();
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}${month}${day}`;
}

async function ensurePreferenceStore(context: common.UIAbilityContext): Promise<preferences.Preferences | null> {
  hilog.info(0x0000, TAG, 'databackup.BackupScheduler.ensurePreferenceStore');
  try {
    await preferencesUtil.init(context, TODAY_STORE_NAME, true);
  } catch (err) {
    hilog.error(0x0000, TAG,
      `ensurePreferenceStore init failed code=${formatErrorCode(err as object)} message=${formatError(err as object)}`);
  }
  const store = preferencesUtil.getPreferences();
  return store ?? null;
}

function readLastDay(store: preferences.Preferences | null): string {
  hilog.info(0x0000, TAG, 'databackup.BackupScheduler.readLastDay');
  if (!store) {
    return DEFAULT_LAST_DAY;
  }
  try {
    return store.getSync(PreferenceKeys.AUTO_BACKUP_LAST_DAY, DEFAULT_LAST_DAY) as string;
  } catch (_err) {
    return DEFAULT_LAST_DAY;
  }
}

function readLastRunAt(store: preferences.Preferences | null): number {
  hilog.info(0x0000, TAG, 'databackup.BackupScheduler.readLastRunAt');
  if (!store) {
    return DEFAULT_LAST_RUN_AT;
  }
  try {
    const raw = store.getSync(PreferenceKeys.AUTO_BACKUP_LAST_RUN_AT, DEFAULT_LAST_RUN_AT);
    return typeof raw === 'number' ? raw : Number(raw) || DEFAULT_LAST_RUN_AT;
  } catch (_err) {
    return DEFAULT_LAST_RUN_AT;
  }
}

function readLastErrorCode(store: preferences.Preferences | null): number {
  hilog.info(0x0000, TAG, 'databackup.BackupScheduler.readLastErrorCode');
  if (!store) {
    return DEFAULT_LAST_ERROR_CODE;
  }
  try {
    const raw = store.getSync(PreferenceKeys.AUTO_BACKUP_LAST_ERROR_CODE, DEFAULT_LAST_ERROR_CODE);
    return typeof raw === 'number' ? raw : Number(raw) || DEFAULT_LAST_ERROR_CODE;
  } catch (_err) {
    return DEFAULT_LAST_ERROR_CODE;
  }
}

function persistAutoBackupState(
  store: preferences.Preferences | null,
  lastDay: string,
  lastRunAt: number,
  lastErrorCode: number
): void {
  hilog.info(0x0000, TAG, 'databackup.BackupScheduler.persistAutoBackupState');
  if (!store) {
    return;
  }
  try {
    store.putSync(PreferenceKeys.AUTO_BACKUP_LAST_DAY, lastDay);
    store.putSync(PreferenceKeys.AUTO_BACKUP_LAST_RUN_AT, lastRunAt);
    store.putSync(PreferenceKeys.AUTO_BACKUP_LAST_ERROR_CODE, lastErrorCode);
    if (preferencesUtil.requiresManualFlush()) {
      preferencesUtil.flush();
    }
  } catch (err) {
    hilog.warn(0x0000, TAG, `persistAutoBackupState failed: ${formatError(err as object)}`);
  }
}

export class BackupScheduler {
  private intervalId: number | null = null;
  private running: boolean = false;
  private inFlight: boolean = false;
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    hilog.info(0x0000, TAG, 'databackup.BackupScheduler.constructor');
    this.context = context;
  }

  start(): void {
    hilog.info(0x0000, TAG, 'databackup.BackupScheduler.start');
    if (this.running) {
      return;
    }
    this.running = true;
    void this.syncStatusFromPreferences();
    void this.maybeRunDailyAutoBackup('foreground');
    this.startInterval();
  }

  stop(): void {
    hilog.info(0x0000, TAG, 'databackup.BackupScheduler.stop');
    this.running = false;
    if (this.intervalId !== null) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  private startInterval(): void {
    hilog.info(0x0000, TAG, 'databackup.BackupScheduler.startInterval');
    if (this.intervalId !== null) {
      return;
    }
    this.intervalId = setInterval(() => {
      void this.maybeRunDailyAutoBackup('interval');
    }, AUTO_BACKUP_INTERVAL_MS);
  }

  private async syncStatusFromPreferences(): Promise<void> {
    hilog.info(0x0000, TAG, 'databackup.BackupScheduler.syncStatusFromPreferences');
    const store = await ensurePreferenceStore(this.context);
    const lastRunAt = readLastRunAt(store);
    const lastErrorCode = readLastErrorCode(store);
    AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_RUN_AT, lastRunAt);
    AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_ERROR_CODE, lastErrorCode);

    const dirState = await getAutoBackupDirState(this.context);
    AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_ENABLED, dirState.enabled);
    if (dirState.issue?.code) {
      AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_ERROR_CODE, dirState.issue.code);
    }
  }

  private async resolveAppVersion(): Promise<string> {
    hilog.info(0x0000, TAG, 'databackup.BackupScheduler.resolveAppVersion');
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const info = bundleInfo as BundleInfoLike;
      const versionName = info.versionName;
      if (typeof versionName === 'string' && versionName.trim().length > 0) {
        return versionName.trim();
      }
      const appInfo = info.appInfo;
      if (appInfo && typeof appInfo.versionName === 'string' && appInfo.versionName.trim().length > 0) {
        return appInfo.versionName.trim();
      }
    } catch (err) {
      const errMessage = formatError(err as object);
      hilog.warn(0x0000, TAG, `resolveAppVersion failed: ${errMessage}`);
    }
    return FALLBACK_APP_VERSION;
  }

  private async maybeRunDailyAutoBackup(source: string): Promise<void> {
    hilog.info(0x0000, TAG, 'databackup.BackupScheduler.maybeRunDailyAutoBackup');
    if (!this.running || this.inFlight) {
      return;
    }

    const now = Date.now();

    const store = await ensurePreferenceStore(this.context);
    const lastDay = readLastDay(store);
    const lastRunAt = readLastRunAt(store);
    const lastErrorCode = readLastErrorCode(store);
    AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_RUN_AT, lastRunAt);
    AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_ERROR_CODE, lastErrorCode);

    const dirState = await getAutoBackupDirState(this.context);
    AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_ENABLED, dirState.enabled);
    if (!dirState.enabled) {
      const issueCode = dirState.issue?.code ?? BackupErrorCode.PERMISSION_DENIED;
      hilog.warn(0x0000, TAG, `databackup.error stage=auto_backup_disabled source=${source} code=${issueCode}`);
      AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_ERROR_CODE, issueCode);
      persistAutoBackupState(store, lastDay, lastRunAt, issueCode);
      return;
    }

    if (lastRunAt > 0 && now - lastRunAt < AUTO_BACKUP_MIN_INTERVAL_MS) {
      return;
    }

    this.inFlight = true;
    try {
      hilog.info(0x0000, TAG, `databackup.stage=auto_backup_trigger source=${source}`);
      const appVersion = await this.resolveAppVersion();
      const result = await createAutoBackup({
        context: this.context,
        appVersion
      });
      if (result.ok) {
        const createdAt = result.createdAt ?? Date.now();
        const createdDayKey = buildDayKey(createdAt);
        persistAutoBackupState(store, createdDayKey, createdAt, DEFAULT_LAST_ERROR_CODE);
        AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_RUN_AT, createdAt);
        AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_ERROR_CODE, DEFAULT_LAST_ERROR_CODE);
        AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_ENABLED, true);
        hilog.info(0x0000, TAG, `databackup.stage=auto_backup_ok source=${source}`);
      } else {
        const errorCode = result.code ?? BackupErrorCode.IO_ERROR;
        persistAutoBackupState(store, lastDay, lastRunAt, errorCode);
        AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_ERROR_CODE, errorCode);
        hilog.warn(0x0000, TAG, `databackup.error stage=auto_backup_fail source=${source} code=${errorCode}`);
      }
    } catch (err) {
      const errMessage = formatError(err as object);
      hilog.error(0x0000, TAG, `maybeRunDailyAutoBackup failed: ${errMessage}`);
      hilog.error(0x0000, TAG, `databackup.error stage=auto_backup_exception source=${source} msg=${errMessage}`);
    } finally {
      this.inFlight = false;
    }
  }
}
