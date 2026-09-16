import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { BackupConstants } from './BackupConstants';
import { BackupIncludeItem, BackupManifestV1 } from './BackupTypes';

const TAG = 'BackupStaging';
const DEFAULT_INCLUDES: BackupIncludeItem[] = ['rdb', 'diary_images'];

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

export interface BackupStagingOptions {
  context?: common.UIAbilityContext;
  appVersion: string;
  includes?: BackupIncludeItem[];
  deviceType?: string;
  bundleName?: string;
  buildNumber?: string;
  notes?: string;
}

export interface BackupStagingInfo {
  stagingDir: string;
  dbDir: string;
  filesDir: string;
  diaryImagesDir: string;
  manifestPath: string;
  createdAt: number;
  manifest: BackupManifestV1;
}

function resolveTempDir(ctx?: common.UIAbilityContext): string {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.resolveTempDir');
  if (ctx && typeof ctx.tempDir === 'string' && ctx.tempDir.trim().length > 0) {
    return ctx.tempDir;
  }

  try {
    const appCtx = AppStorage.get('context') as common.UIAbilityContext;
    if (appCtx && typeof appCtx.tempDir === 'string' && appCtx.tempDir.trim().length > 0) {
      hilog.warn(0x0000, TAG, 'resolveTempDir fallback to AppStorage context tempDir');
      return appCtx.tempDir;
    }
  } catch (_err) {
    // ignore and throw below
  }

  throw new Error('BackupStaging invalid context: tempDir is missing');
}

function normalizeBaseDir(path: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.normalizeBaseDir');
  return path.endsWith('/') ? path.slice(0, -1) : path;
}

function normalizeAppVersion(appVersion: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.normalizeAppVersion');
  const trimmed = appVersion.trim();
  if (trimmed.length === 0) {
    throw new Error('BackupStaging invalid appVersion: empty');
  }
  return trimmed;
}

function normalizeIncludes(includes?: BackupIncludeItem[]): BackupIncludeItem[] {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.normalizeIncludes');
  if (includes && includes.length > 0) {
    return [...includes];
  }
  return [...DEFAULT_INCLUDES];
}

function buildStagingDirName(createdAt: number): string {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.buildStagingDirName');
  return `backup_stage_${createdAt}`;
}

function pathExists(path: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.pathExists');
  try {
    return fs.accessSync(path);
  } catch (_err) {
    return false;
  }
}

function buildUniqueStagingDir(tempDir: string, createdAt: number): string {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.buildUniqueStagingDir');
  const baseDir = normalizeBaseDir(tempDir);
  const baseName = buildStagingDirName(createdAt);
  const candidate = `${baseDir}/${baseName}`;
  if (!pathExists(candidate)) {
    return candidate;
  }
  const fallbackName = `${baseName}_${Math.floor(Math.random() * 1000000)}`;
  return `${baseDir}/${fallbackName}`;
}

function ensureDir(path: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.ensureDir');
  fs.mkdirSync(path, true);
}

function writeTextFile(path: string, content: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.writeTextFile');
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(file.fd, content);
  } finally {
    fs.closeSync(file.fd);
  }
}

function deleteDirContentsBestEffort(dirPath: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.deleteDirContentsBestEffort');
  let entries: string[] = [];
  try {
    entries = fs.listFileSync(dirPath);
  } catch (_err) {
    return;
  }

  entries.forEach((entry: string) => {
    const childPath = `${dirPath}/${entry}`;
    try {
      const stat = fs.statSync(childPath);
      if (stat.isDirectory()) {
        deleteDirContentsBestEffort(childPath);
        try {
          fs.rmdirSync(childPath);
        } catch (_err) {
          // best-effort cleanup
        }
      } else {
        try {
          fs.unlinkSync(childPath);
        } catch (_err) {
          // best-effort cleanup
        }
      }
    } catch (_err) {
      // best-effort cleanup
    }
  });
}

export async function cleanupBackupStagingDirBestEffort(stagingDir: string): Promise<void> {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.cleanupBackupStagingDirBestEffort');
  if (!stagingDir || stagingDir.trim().length === 0) {
    return;
  }
  if (!pathExists(stagingDir)) {
    return;
  }

  try {
    deleteDirContentsBestEffort(stagingDir);
    fs.rmdirSync(stagingDir);
  } catch (err) {
    hilog.warn(0x0000, TAG, `cleanupBackupStagingDirBestEffort failed: ${JSON.stringify(err)}`);
    hilog.warn(0x0000, TAG, `databackup.error stage=cleanup_staging dir=${safePath(stagingDir)}`);
  }
}

function buildManifest(options: BackupStagingOptions, includes: BackupIncludeItem[], createdAt: number): BackupManifestV1 {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.buildManifest');
  return {
    backupVersion: BackupConstants.BACKUP_VERSION_V1,
    createdAt: createdAt,
    appVersion: normalizeAppVersion(options.appVersion),
    dbName: BackupConstants.DB_NAME,
    includes: includes,
    deviceType: options.deviceType,
    bundleName: options.bundleName,
    buildNumber: options.buildNumber,
    notes: options.notes
  };
}

export async function createBackupStagingDir(options: BackupStagingOptions): Promise<BackupStagingInfo> {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.createBackupStagingDir');
  if (!options) {
    throw new Error('BackupStaging invalid options');
  }
  const createdAt = Date.now();
  const tempDir = resolveTempDir(options.context);
  const stagingDir = buildUniqueStagingDir(tempDir, createdAt);
  const includes = normalizeIncludes(options.includes);

  try {
    hilog.info(0x0000, TAG, `databackup.stage=staging_create dir=${safePath(stagingDir)}`);
    ensureDir(stagingDir);

    const dbDir = `${stagingDir}/${BackupConstants.ZIP_DIR_DB}`;
    const filesDir = `${stagingDir}/${BackupConstants.ZIP_DIR_FILES}`;
    const diaryImagesDir = `${filesDir}/${BackupConstants.ZIP_DIR_DIARY_IMAGES}`;
    ensureDir(dbDir);
    ensureDir(filesDir);
    ensureDir(diaryImagesDir);

    const manifest = buildManifest(options, includes, createdAt);
    const manifestPath = `${stagingDir}/${BackupConstants.MANIFEST_FILE_NAME}`;
    writeTextFile(manifestPath, JSON.stringify(manifest));
    hilog.info(0x0000, TAG, `databackup.stage=staging_manifest path=${safePath(manifestPath)}`);

    return {
      stagingDir: stagingDir,
      dbDir: dbDir,
      filesDir: filesDir,
      diaryImagesDir: diaryImagesDir,
      manifestPath: manifestPath,
      createdAt: createdAt,
      manifest: manifest
    };
  } catch (err) {
    await cleanupBackupStagingDirBestEffort(stagingDir);
    const errMessage = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(0x0000, TAG, `createBackupStagingDir failed: ${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=staging_create dir=${safePath(stagingDir)} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }
}

export async function withBackupStagingDir<T>(
  options: BackupStagingOptions,
  task: (staging: BackupStagingInfo) => Promise<T>
): Promise<T> {
  hilog.info(0x0000, TAG, 'databackup.BackupStaging.withBackupStagingDir');
  const staging = await createBackupStagingDir(options);
  try {
    return await task(staging);
  } finally {
    await cleanupBackupStagingDirBestEffort(staging.stagingDir);
  }
}
