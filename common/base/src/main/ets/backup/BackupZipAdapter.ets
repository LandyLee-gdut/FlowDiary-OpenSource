import fs from '@ohos.file.fs';
import { zlib } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

const TAG: string = 'BackupZipAdapter';
const DEFAULT_ZLIB_OPTIONS: zlib.Options = {
  level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
};

interface ErrorLike {
  code?: number;
  message?: string;
}

export interface RestoreExtractInfo {
  extractDir: string;
  createdAt: number;
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

function normalizePath(path: string, label: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.normalizePath');
  if (!path) {
    throw new Error(`BackupZipAdapter invalid ${label}: empty`);
  }
  const trimmed = path.trim();
  if (trimmed.length === 0) {
    throw new Error(`BackupZipAdapter invalid ${label}: empty`);
  }
  return trimmed;
}

function normalizeDir(path: string, label: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.normalizeDir');
  const trimmed = normalizePath(path, label);
  return trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;
}

function normalizeBaseDir(path: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.normalizeBaseDir');
  return path.endsWith('/') ? path.slice(0, -1) : path;
}

function formatError(err: object): string {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.formatError');
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
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.formatErrorCode');
  const maybeError = err as ErrorLike;
  if (maybeError && typeof maybeError.code === 'number') {
    return maybeError.code.toString();
  }
  return '-1';
}

function resolveTempDir(ctx?: common.UIAbilityContext): string {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.resolveTempDir');
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

  throw new Error('BackupZipAdapter invalid context: tempDir is missing');
}

function pathExists(path: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.pathExists');
  try {
    return fs.accessSync(path);
  } catch (_err) {
    return false;
  }
}

function ensureDir(path: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.ensureDir');
  try {
    fs.mkdirSync(path, true);
  } catch (_err) {
    // ignore if already exists
  }
}

function assertDirReady(path: string, label: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.assertDirReady');
  try {
    const stat = fs.statSync(path);
    if (!stat.isDirectory()) {
      throw new Error(`BackupZipAdapter ${label} is not a directory`);
    }
  } catch (err) {
    const errMessage = formatError(err as object);
    throw new Error(`BackupZipAdapter ${label} missing: ${errMessage}`);
  }
}

function assertFileReady(path: string, label: string): number {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.assertFileReady');
  try {
    const stat = fs.statSync(path);
    if (!stat.isFile()) {
      throw new Error(`BackupZipAdapter ${label} is not a file`);
    }
    const size = Number(stat.size) || 0;
    if (size <= 0) {
      throw new Error(`BackupZipAdapter ${label} file is empty`);
    }
    return size;
  } catch (err) {
    const errMessage = formatError(err as object);
    throw new Error(`BackupZipAdapter ${label} missing: ${errMessage}`);
  }
}

function getParentDir(path: string): string | null {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.getParentDir');
  const idx = path.lastIndexOf('/');
  if (idx < 0) {
    return null;
  }
  if (idx === 0) {
    return '/';
  }
  return path.slice(0, idx);
}

function ensureParentDir(path: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.ensureParentDir');
  const parent = getParentDir(path);
  if (!parent || parent.trim().length === 0) {
    return;
  }
  ensureDir(parent);
}

function deleteDirContentsBestEffort(dirPath: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.deleteDirContentsBestEffort');
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

function buildExtractDirName(createdAt: number): string {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.buildExtractDirName');
  return `restore_extract_${createdAt}`;
}

function buildUniqueExtractDir(tempDir: string, createdAt: number): string {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.buildUniqueExtractDir');
  const baseDir = normalizeBaseDir(tempDir);
  const baseName = buildExtractDirName(createdAt);
  const candidate = `${baseDir}/${baseName}`;
  if (!pathExists(candidate)) {
    return candidate;
  }
  const fallbackName = `${baseName}_${Math.floor(Math.random() * 1000000)}`;
  return `${baseDir}/${fallbackName}`;
}

export async function cleanupRestoreExtractDirBestEffort(extractDir: string): Promise<void> {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.cleanupRestoreExtractDirBestEffort');
  if (!extractDir || extractDir.trim().length === 0) {
    return;
  }
  if (!pathExists(extractDir)) {
    return;
  }

  try {
    deleteDirContentsBestEffort(extractDir);
    fs.rmdirSync(extractDir);
  } catch (err) {
    hilog.warn(0x0000, TAG, `cleanupRestoreExtractDirBestEffort failed: ${JSON.stringify(err)}`);
    hilog.warn(0x0000, TAG, `databackup.error stage=cleanup_extract dir=${safePath(extractDir)}`);
  }
}

export async function createRestoreExtractDir(context?: common.UIAbilityContext): Promise<RestoreExtractInfo> {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.createRestoreExtractDir');
  const createdAt = Date.now();
  const tempDir = resolveTempDir(context);
  const extractDir = buildUniqueExtractDir(tempDir, createdAt);

  try {
    ensureDir(extractDir);
    assertDirReady(extractDir, 'extractDir');
    hilog.info(0x0000, TAG, `databackup.stage=extract_dir_ready dir=${safePath(extractDir)}`);
    return {
      extractDir: extractDir,
      createdAt: createdAt
    };
  } catch (err) {
    await cleanupRestoreExtractDirBestEffort(extractDir);
    const errMessage = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(0x0000, TAG, `createRestoreExtractDir failed: ${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=create_extract_dir dir=${safePath(extractDir)} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }
}

export async function withRestoreExtractDir<T>(
  context: common.UIAbilityContext | undefined,
  task: (extractDir: string) => Promise<T>
): Promise<T> {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.withRestoreExtractDir');
  const extract = await createRestoreExtractDir(context);
  try {
    return await task(extract.extractDir);
  } finally {
    await cleanupRestoreExtractDirBestEffort(extract.extractDir);
  }
}

/**
 * Compress a staging directory into a zip file.
 */
export async function compressDirectory(stagingDir: string, outZipPathOrUri: string): Promise<void> {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.compressDirectory');
  const normalizedStagingDir = normalizeDir(stagingDir, 'stagingDir');
  const normalizedOutPath = normalizePath(outZipPathOrUri, 'outZipPathOrUri');
  assertDirReady(normalizedStagingDir, 'stagingDir');
  ensureParentDir(normalizedOutPath);

  hilog.info(0x0000, TAG, `databackup.stage=compress_start stagingDir=${safePath(normalizedStagingDir)} outZip=${safePath(normalizedOutPath)}`);
  try {
    await zlib.compressFile(normalizedStagingDir, normalizedOutPath, DEFAULT_ZLIB_OPTIONS);
  } catch (err) {
    const errCode = formatErrorCode(err as object);
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG, `compressDirectory failed code=${errCode} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=compress code=${errCode} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }

  const size = assertFileReady(normalizedOutPath, 'outZipPathOrUri');
  hilog.info(0x0000, TAG, `databackup.stage=compress_done outZip=${safePath(normalizedOutPath)} size=${size}`);
}

/**
 * Decompress a zip file into a directory (must exist).
 */
export async function decompressToDir(zipPathOrUri: string, outDir: string): Promise<void> {
  hilog.info(0x0000, TAG, 'databackup.BackupZipAdapter.decompressToDir');
  const normalizedZipPath = normalizePath(zipPathOrUri, 'zipPathOrUri');
  const normalizedOutDir = normalizeDir(outDir, 'outDir');
  assertFileReady(normalizedZipPath, 'zipPathOrUri');
  ensureDir(normalizedOutDir);
  assertDirReady(normalizedOutDir, 'outDir');

  hilog.info(0x0000, TAG, `databackup.stage=decompress_start zip=${safePath(normalizedZipPath)} outDir=${safePath(normalizedOutDir)}`);
  try {
    await zlib.decompressFile(normalizedZipPath, normalizedOutDir, DEFAULT_ZLIB_OPTIONS);
  } catch (err) {
    const errCode = formatErrorCode(err as object);
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG, `decompressToDir failed code=${errCode} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=decompress code=${errCode} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }
  hilog.info(0x0000, TAG, `databackup.stage=decompress_done outDir=${safePath(normalizedOutDir)}`);
}
