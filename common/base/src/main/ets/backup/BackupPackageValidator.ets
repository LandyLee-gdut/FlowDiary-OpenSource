import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupConstants } from './BackupConstants';
import {
  BackupErrorCode,
  BackupIncludeItem,
  BackupManifestV1,
  BackupValidationIssue,
  BackupValidationResult
} from './BackupTypes';

const TAG: string = 'BackupValidator';
const MIN_ZIP_BYTES: number = 128;

interface ErrorLike {
  code?: number;
  message?: string;
}

interface ManifestValidationResult {
  manifest?: BackupManifestV1;
  issue?: BackupValidationIssue;
}

type JsonPrimitive = string | number | boolean | null;
type JsonArray = JsonPrimitive[];

interface ManifestJson {
  backupVersion?: number;
  createdAt?: number;
  appVersion?: string;
  dbName?: string;
  includes?: JsonArray;
  deviceType?: string;
  bundleName?: string;
  buildNumber?: string;
  notes?: string;
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
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.formatError');
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

function createIssue(code: BackupErrorCode, message: string): BackupValidationIssue {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.createIssue');
  return { code, message };
}

function normalizePath(path: string, label: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.normalizePath');
  if (!path) {
    throw new Error(`BackupValidator invalid ${label}: empty`);
  }
  const trimmed = path.trim();
  if (trimmed.length === 0) {
    throw new Error(`BackupValidator invalid ${label}: empty`);
  }
  return trimmed;
}

function normalizeDir(path: string, label: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.normalizeDir');
  const trimmed = normalizePath(path, label);
  return trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;
}

function buildPath(base: string, child: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.buildPath');
  const cleanChild = child.startsWith('/') ? child.slice(1) : child;
  return `${base}/${cleanChild}`;
}

function pathExists(path: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.pathExists');
  try {
    return fs.accessSync(path);
  } catch (_err) {
    return false;
  }
}

function statFileSize(path: string): number {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.statFileSize');
  const stat = fs.statSync(path);
  if (!stat.isFile()) {
    throw new Error('not a file');
  }
  return Number(stat.size) || 0;
}

function statIsDirectory(path: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.statIsDirectory');
  const stat = fs.statSync(path);
  return stat.isDirectory();
}

function readTextFile(path: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.readTextFile');
  return fs.readTextSync(path, { encoding: 'utf-8' });
}

function isZipSuffix(path: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.isZipSuffix');
  return path.toLowerCase().endsWith(BackupConstants.BACKUP_FILE_SUFFIX);
}

function parseIncludes(raw: JsonArray | undefined): BackupIncludeItem[] | null {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.parseIncludes');
  if (!Array.isArray(raw)) {
    return null;
  }
  const includes: BackupIncludeItem[] = [];
  for (const item of raw) {
    if (item === 'rdb' || item === 'diary_images') {
      includes.push(item);
      continue;
    }
    return null;
  }
  return includes;
}

function hasRequiredIncludes(includes: BackupIncludeItem[]): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.hasRequiredIncludes');
  return includes.includes('rdb') && includes.includes('diary_images');
}

function validateManifest(raw: object): ManifestValidationResult {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.validateManifest');
  if (Array.isArray(raw)) {
    const result: ManifestValidationResult = {
      issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, 'manifest.json is not an object')
    };
    return result;
  }

  const data = raw as ManifestJson;
  const version = data.backupVersion;
  if (typeof version !== 'number') {
    const result: ManifestValidationResult = {
      issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, 'backupVersion missing')
    };
    return result;
  }
  if (version !== BackupConstants.BACKUP_VERSION_V1) {
    const result: ManifestValidationResult = {
      issue: createIssue(BackupErrorCode.UNSUPPORTED_VERSION, 'backupVersion unsupported')
    };
    return result;
  }

  const createdAt = data.createdAt;
  if (typeof createdAt !== 'number' || !Number.isFinite(createdAt)) {
    const result: ManifestValidationResult = {
      issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, 'createdAt invalid')
    };
    return result;
  }

  const appVersion = data.appVersion;
  if (typeof appVersion !== 'string' || appVersion.trim().length === 0) {
    const result: ManifestValidationResult = {
      issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, 'appVersion invalid')
    };
    return result;
  }

  const dbName = data.dbName;
  if (dbName !== BackupConstants.DB_NAME) {
    const result: ManifestValidationResult = {
      issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, 'dbName mismatch')
    };
    return result;
  }

  const includes = parseIncludes(data.includes);
  if (!includes || !hasRequiredIncludes(includes)) {
    const result: ManifestValidationResult = {
      issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, 'includes invalid')
    };
    return result;
  }

  const manifest: BackupManifestV1 = {
    backupVersion: version,
    createdAt: createdAt,
    appVersion: appVersion.trim(),
    dbName: BackupConstants.DB_NAME,
    includes: includes,
    deviceType: typeof data.deviceType === 'string' ? data.deviceType : undefined,
    bundleName: typeof data.bundleName === 'string' ? data.bundleName : undefined,
    buildNumber: typeof data.buildNumber === 'string' ? data.buildNumber : undefined,
    notes: typeof data.notes === 'string' ? data.notes : undefined
  };

  const result: ManifestValidationResult = { manifest };
  return result;
}

export function quickValidateZipInput(zipPathOrUri: string): BackupValidationResult {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.quickValidateZipInput');
  const warnings: string[] = [];
  let normalizedPath: string;
  try {
    normalizedPath = normalizePath(zipPathOrUri, 'zipPathOrUri');
  } catch (err) {
    const errMessage = err instanceof Error ? err.message : String(err);
    hilog.error(0x0000, TAG, `databackup.error stage=quick_validate path=${safePath(zipPathOrUri)} msg=${errMessage}`);
    return {
      ok: false,
      issue: createIssue(BackupErrorCode.INVALID_ZIP, errMessage)
    };
  }

  if (!isZipSuffix(normalizedPath)) {
    warnings.push('zip path does not end with .zip');
  }

  try {
    const size = statFileSize(normalizedPath);
    if (size < MIN_ZIP_BYTES) {
      hilog.warn(0x0000, TAG, `databackup.error stage=quick_validate path=${safePath(normalizedPath)} msg=zip too small`);
      return {
        ok: false,
        issue: createIssue(BackupErrorCode.INVALID_ZIP, 'zip file too small')
      };
    }
  } catch (err) {
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG, `databackup.error stage=quick_validate path=${safePath(normalizedPath)} msg=${errMessage}`);
    return {
      ok: false,
      issue: createIssue(BackupErrorCode.IO_ERROR, `zip access failed: ${errMessage}`)
    };
  }

  hilog.info(0x0000, TAG, `databackup.stage=quick_validate_ok path=${safePath(normalizedPath)}`);
  return {
    ok: true,
    warnings: warnings.length > 0 ? warnings : undefined
  };
}

export async function validateExtractedDir(extractedDir: string): Promise<BackupValidationResult> {
  hilog.info(0x0000, TAG, 'databackup.BackupValidator.validateExtractedDir');
  let normalizedDir: string;
  try {
    normalizedDir = normalizeDir(extractedDir, 'extractedDir');
  } catch (err) {
    const errMessage = err instanceof Error ? err.message : String(err);
    hilog.error(0x0000, TAG, `databackup.error stage=validate_dir dir=${safePath(extractedDir)} msg=${errMessage}`);
    return {
      ok: false,
      issue: createIssue(BackupErrorCode.INVALID_ZIP, errMessage)
    };
  }

  if (!pathExists(normalizedDir)) {
    hilog.error(0x0000, TAG, `databackup.error stage=validate_dir dir=${safePath(normalizedDir)} msg=missing`);
    return {
      ok: false,
      issue: createIssue(BackupErrorCode.INVALID_ZIP, 'extractedDir missing')
    };
  }

  const manifestPath = buildPath(normalizedDir, BackupConstants.MANIFEST_FILE_NAME);
  if (!pathExists(manifestPath)) {
    hilog.error(0x0000, TAG, `databackup.error stage=manifest_missing path=${safePath(manifestPath)}`);
    return {
      ok: false,
      issue: createIssue(BackupErrorCode.MISSING_MANIFEST, 'manifest.json missing')
    };
  }

  let manifestText: string;
  try {
    manifestText = readTextFile(manifestPath);
  } catch (err) {
    hilog.error(0x0000, TAG, `databackup.error stage=manifest_read path=${safePath(manifestPath)} msg=${formatError(err as object)}`);
    return {
      ok: false,
      issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, `manifest.json read failed: ${formatError(err as object)}`)
    };
  }

  let parsed: object;
  try {
    parsed = JSON.parse(manifestText) as object;
  } catch (err) {
    hilog.error(0x0000, TAG, `databackup.error stage=manifest_parse path=${safePath(manifestPath)} msg=${formatError(err as object)}`);
    return {
      ok: false,
      issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, `manifest.json parse failed: ${formatError(err as object)}`)
    };
  }

  const manifestResult = validateManifest(parsed);
  if (manifestResult.issue) {
    hilog.error(0x0000, TAG, `databackup.error stage=manifest_validate code=${manifestResult.issue.code} msg=${manifestResult.issue.message}`);
    return {
      ok: false,
      issue: manifestResult.issue
    };
  }

  const manifest = manifestResult.manifest as BackupManifestV1;
  const dbBackupPath = buildPath(normalizedDir, BackupConstants.ZIP_PATH_DB_BACKUP);
  if (!pathExists(dbBackupPath)) {
    hilog.error(0x0000, TAG, `databackup.error stage=db_backup_missing path=${safePath(dbBackupPath)}`);
    return {
      ok: false,
      issue: createIssue(BackupErrorCode.MISSING_DB_BACKUP, 'db backup file missing')
    };
  }

  try {
    const size = statFileSize(dbBackupPath);
    if (size <= 0) {
      hilog.error(0x0000, TAG, `databackup.error stage=db_backup_empty path=${safePath(dbBackupPath)}`);
      return {
        ok: false,
        issue: createIssue(BackupErrorCode.MISSING_DB_BACKUP, 'db backup file empty')
      };
    }
  } catch (err) {
    hilog.error(0x0000, TAG, `databackup.error stage=db_backup_invalid path=${safePath(dbBackupPath)} msg=${formatError(err as object)}`);
    return {
      ok: false,
      issue: createIssue(BackupErrorCode.MISSING_DB_BACKUP, `db backup file invalid: ${formatError(err as object)}`)
    };
  }

  if (manifest.includes.includes('diary_images')) {
    const diaryImagesDir = buildPath(normalizedDir, BackupConstants.ZIP_PATH_FILES_DIARY_IMAGES);
    if (!pathExists(diaryImagesDir)) {
      hilog.error(0x0000, TAG, `databackup.error stage=diary_images_missing path=${safePath(diaryImagesDir)}`);
      return {
        ok: false,
        issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, 'diary_images directory missing')
      };
    }
    try {
      if (!statIsDirectory(diaryImagesDir)) {
        hilog.error(0x0000, TAG, `databackup.error stage=diary_images_not_dir path=${safePath(diaryImagesDir)}`);
        return {
          ok: false,
          issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, 'diary_images path is not a directory')
        };
      }
    } catch (err) {
      hilog.error(0x0000, TAG, `databackup.error stage=diary_images_invalid path=${safePath(diaryImagesDir)} msg=${formatError(err as object)}`);
      return {
        ok: false,
        issue: createIssue(BackupErrorCode.CORRUPT_MANIFEST, `diary_images directory invalid: ${formatError(err as object)}`)
      };
    }
  }

  hilog.info(0x0000, TAG, `databackup.stage=validate_dir_ok dir=${safePath(normalizedDir)}`);
  return {
    ok: true,
    manifest: manifest
  };
}
