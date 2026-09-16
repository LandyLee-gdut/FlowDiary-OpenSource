import fs from '@ohos.file.fs';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys } from '../constants/PreferenceKeys';
import { preferencesUtil } from '../common/PreferencesUtil';
import { AutoBackupDirState, BackupErrorCode, BackupValidationIssue } from './BackupTypes';

const TAG: string = 'BackupLocation';
const TODAY_STORE_NAME: string = 'todayStore';
const PROBE_PREFIX: string = 'auto_backup_probe_';

interface ErrorLike {
  code?: number;
  message?: string;
}

type PickerResult = string | string[];

interface BackupDirValidationResult {
  ok: boolean;
  issue?: BackupValidationIssue;
}

function safePath(path: string): string {
  if (!path) {
    return '';
  }
  let cleaned = path.trim();
  if (cleaned.startsWith('file://')) {
    cleaned = cleaned.slice('file://'.length);
  }
  const parts = cleaned.split('/').filter((part: string) => part.length > 0);
  if (parts.length === 0) {
    return cleaned;
  }
  const tail = parts.slice(Math.max(0, parts.length - 2));
  return tail.join('/');
}

function formatError(err: object): string {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.formatError');
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
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.formatErrorCode');
  const maybeError = err as ErrorLike;
  if (maybeError && typeof maybeError.code === 'number') {
    return maybeError.code.toString();
  }
  return '-1';
}

function createIssue(code: BackupErrorCode, message: string): BackupValidationIssue {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.createIssue');
  return { code, message };
}

async function ensurePreferenceStore(context?: common.UIAbilityContext): Promise<preferences.Preferences | null> {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.ensurePreferenceStore');
  if (context) {
    try {
      await preferencesUtil.init(context, TODAY_STORE_NAME, true);
    } catch (err) {
      hilog.error(0x0000, TAG,
        `ensurePreferenceStore init failed code=${formatErrorCode(err as object)} message=${formatError(err as object)}`);
    }
  }
  const store = preferencesUtil.getPreferences();
  return store ?? null;
}

function normalizeDirUri(dirUri: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.normalizeDirUri');
  const trimmed = dirUri.trim();
  return trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;
}

function resolveDirPath(dirUri: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.resolveDirPath');
  const normalized = normalizeDirUri(dirUri);
  if (normalized.startsWith('file://')) {
    try {
      return new fileUri.FileUri(normalized).path;
    } catch (_err) {
      return normalized;
    }
  }
  return normalized;
}

function buildPath(base: string, child: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.buildPath');
  const cleanChild = child.startsWith('/') ? child.slice(1) : child;
  return `${base}/${cleanChild}`;
}

function persistIssue(store: preferences.Preferences | null, issue?: BackupValidationIssue): void {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.persistIssue');
  if (!store) {
    return;
  }
  try {
    if (!issue) {
      store.deleteSync(PreferenceKeys.AUTO_BACKUP_DIR_LAST_ERROR);
    } else {
      store.putSync(PreferenceKeys.AUTO_BACKUP_DIR_LAST_ERROR, JSON.stringify(issue));
    }
    if (preferencesUtil.requiresManualFlush()) {
      preferencesUtil.flush();
    }
  } catch (err) {
    hilog.warn(0x0000, TAG, `persistIssue failed: ${formatError(err as object)}`);
  }
}

function readIssue(store: preferences.Preferences | null): BackupValidationIssue | undefined {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.readIssue');
  if (!store) {
    return undefined;
  }
  try {
    const raw = store.getSync(PreferenceKeys.AUTO_BACKUP_DIR_LAST_ERROR, '') as string;
    if (!raw || raw.trim().length === 0) {
      return undefined;
    }
    const parsed = JSON.parse(raw) as BackupValidationIssue;
    if (!parsed || typeof parsed.code !== 'number' || typeof parsed.message !== 'string') {
      return undefined;
    }
    return parsed;
  } catch (_err) {
    return undefined;
  }
}

function readStoredDirUri(store: preferences.Preferences | null): string | null {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.readStoredDirUri');
  if (!store) {
    return null;
  }
  try {
    const raw = store.getSync(PreferenceKeys.AUTO_BACKUP_DIR_URI, '') as string;
    if (!raw || raw.trim().length === 0) {
      return null;
    }
    return normalizeDirUri(raw);
  } catch (_err) {
    return null;
  }
}

function persistDirUri(store: preferences.Preferences | null, dirUri: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.persistDirUri');
  if (!store) {
    return;
  }
  try {
    store.putSync(PreferenceKeys.AUTO_BACKUP_DIR_URI, normalizeDirUri(dirUri));
    if (preferencesUtil.requiresManualFlush()) {
      preferencesUtil.flush();
    }
  } catch (err) {
    hilog.warn(0x0000, TAG, `persistDirUri failed: ${formatError(err as object)}`);
  }
}

function validateWritableDir(dirUri: string): BackupDirValidationResult {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.validateWritableDir');
  const normalized = normalizeDirUri(dirUri);
  if (!normalized) {
    const result: BackupDirValidationResult = {
      ok: false,
      issue: createIssue(BackupErrorCode.IO_ERROR, 'auto backup dir uri empty')
    };
    return result;
  }
  const dirPath = resolveDirPath(normalized);
  hilog.info(0x0000, TAG, `databackup.stage=validate_auto_dir path=${safePath(dirPath)}`);
  try {
    const stat = fs.statSync(dirPath);
    if (!stat.isDirectory()) {
      const result: BackupDirValidationResult = {
        ok: false,
        issue: createIssue(BackupErrorCode.IO_ERROR, 'auto backup dir is not a directory')
      };
      return result;
    }
  } catch (err) {
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG, `databackup.error stage=validate_auto_dir path=${safePath(dirPath)} msg=${errMessage}`);
    const result: BackupDirValidationResult = {
      ok: false,
      issue: createIssue(BackupErrorCode.IO_ERROR, `auto backup dir missing: ${errMessage}`)
    };
    return result;
  }

  const probeName = `${PROBE_PREFIX}${Date.now()}`;
  const probePath = buildPath(dirPath, probeName);
  let fd: number | null = null;
  try {
    fd = fs.openSync(probePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC).fd;
  } catch (err) {
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG, `databackup.error stage=probe_write path=${safePath(probePath)} msg=${errMessage}`);
    const result: BackupDirValidationResult = {
      ok: false,
      issue: createIssue(BackupErrorCode.PERMISSION_DENIED, `auto backup dir not writable: ${errMessage}`)
    };
    return result;
  } finally {
    if (fd !== null) {
      try {
        fs.closeSync(fd);
      } catch (_err) {
        // ignore close failure
      }
    }
  }
  try {
    fs.unlinkSync(probePath);
  } catch (_err) {
    // ignore cleanup failure
  }
  const result: BackupDirValidationResult = { ok: true };
  return result;
}

function resolvePickerUri(result: PickerResult | undefined): string | null {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.resolvePickerUri');
  if (!result) {
    return null;
  }
  if (Array.isArray(result)) {
    return result.length > 0 ? result[0] : null;
  }
  if (typeof result === 'string' && result.trim().length > 0) {
    return result;
  }
  return null;
}

function mapPickerError(err: object): BackupValidationIssue {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.mapPickerError');
  const errMessage = formatError(err as object);
  const lower = errMessage.toLowerCase();
  if (lower.includes('cancel')) {
    return createIssue(BackupErrorCode.CANCELLED_BY_USER, 'user cancelled');
  }
  if (lower.includes('unsupported') || lower.includes('not support')) {
    return createIssue(BackupErrorCode.UNSUPPORTED, errMessage);
  }
  return createIssue(BackupErrorCode.PERMISSION_DENIED, errMessage);
}

async function requestDownloadDirUri(): Promise<string> {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.requestDownloadDirUri');
  const viewPicker = new picker.DocumentViewPicker();
  const options = new picker.DocumentSaveOptions();
  options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;

  const result = await viewPicker.save(options) as PickerResult;
  const uri = resolvePickerUri(result);
  if (!uri) {
    throw new Error('download dir picker returned empty uri');
  }
  return normalizeDirUri(uri);
}

export async function getAutoBackupDirState(context?: common.UIAbilityContext): Promise<AutoBackupDirState> {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.getAutoBackupDirState');
  const store = await ensurePreferenceStore(context);
  const storedDirUri = readStoredDirUri(store);
  if (!storedDirUri) {
    const issue = readIssue(store);
    hilog.info(0x0000, TAG, 'databackup.stage=auto_dir_missing');
    return { enabled: false, issue };
  }

  const validation = validateWritableDir(storedDirUri);
  if (!validation.ok) {
    persistIssue(store, validation.issue);
    hilog.warn(0x0000, TAG, `databackup.error stage=auto_dir_invalid dir=${safePath(storedDirUri)} code=${validation.issue?.code}`);
    return { enabled: false, dirUri: storedDirUri, issue: validation.issue };
  }

  persistIssue(store, undefined);
  hilog.info(0x0000, TAG, `databackup.stage=auto_dir_ok dir=${safePath(storedDirUri)}`);
  return { enabled: true, dirUri: storedDirUri };
}

export async function ensureAutoBackupDir(context: common.UIAbilityContext): Promise<AutoBackupDirState> {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.ensureAutoBackupDir');
  const store = await ensurePreferenceStore(context);
  if (!store) {
    return {
      enabled: false,
      issue: createIssue(BackupErrorCode.IO_ERROR, 'preferences not initialized')
    };
  }

  const storedDirUri = readStoredDirUri(store);
  if (storedDirUri) {
    const validation = validateWritableDir(storedDirUri);
    if (!validation.ok) {
      persistIssue(store, validation.issue);
      hilog.warn(0x0000, TAG, `databackup.error stage=auto_dir_invalid dir=${safePath(storedDirUri)} code=${validation.issue?.code}`);
      return { enabled: false, dirUri: storedDirUri, issue: validation.issue };
    }
    persistIssue(store, undefined);
    hilog.info(0x0000, TAG, `databackup.stage=auto_dir_cached dir=${safePath(storedDirUri)}`);
    return { enabled: true, dirUri: storedDirUri };
  }

  try {
    const dirUri = await requestDownloadDirUri();
    persistDirUri(store, dirUri);
    const validation = validateWritableDir(dirUri);
    if (!validation.ok) {
      persistIssue(store, validation.issue);
      hilog.warn(0x0000, TAG, `databackup.error stage=auto_dir_new_invalid dir=${safePath(dirUri)} code=${validation.issue?.code}`);
      return { enabled: false, dirUri, issue: validation.issue };
    }
    persistIssue(store, undefined);
    hilog.info(0x0000, TAG, `databackup.stage=auto_dir_new_ok dir=${safePath(dirUri)}`);
    return { enabled: true, dirUri };
  } catch (err) {
    const issue = mapPickerError(err as object);
    persistIssue(store, issue);
    hilog.warn(0x0000, TAG,
      `ensureAutoBackupDir failed code=${issue.code} message=${issue.message}`);
    hilog.warn(0x0000, TAG, `databackup.error stage=auto_dir_picker code=${issue.code} msg=${issue.message}`);
    return { enabled: false, issue };
  }
}

export async function clearAutoBackupDir(context?: common.UIAbilityContext): Promise<void> {
  hilog.info(0x0000, TAG, 'databackup.BackupLocation.clearAutoBackupDir');
  const store = await ensurePreferenceStore(context);
  if (!store) {
    return;
  }
  try {
    store.deleteSync(PreferenceKeys.AUTO_BACKUP_DIR_URI);
    store.deleteSync(PreferenceKeys.AUTO_BACKUP_DIR_LAST_ERROR);
    if (preferencesUtil.requiresManualFlush()) {
      preferencesUtil.flush();
    }
  } catch (err) {
    hilog.warn(0x0000, TAG, `clearAutoBackupDir failed: ${formatError(err as object)}`);
  }
}
