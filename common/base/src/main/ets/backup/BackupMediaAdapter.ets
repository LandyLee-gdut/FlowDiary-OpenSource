import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupConstants } from './BackupConstants';

const TAG: string = 'BackupMediaAdapter';
const COPY_BUFFER_BYTES: number = 1024 * 1024;

interface ErrorLike {
  code?: number;
  message?: string;
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

function normalizeBaseDir(path: string, label: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.normalizeBaseDir');
  if (!path) {
    throw new Error(`BackupMediaAdapter invalid ${label}: empty`);
  }
  const trimmed = path.trim();
  if (trimmed.length === 0) {
    throw new Error(`BackupMediaAdapter invalid ${label}: empty`);
  }
  return trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;
}

function formatError(err: object): string {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.formatError');
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
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.formatErrorCode');
  const maybeError = err as ErrorLike;
  if (maybeError && typeof maybeError.code === 'number') {
    return maybeError.code.toString();
  }
  return '-1';
}

function buildPath(base: string, child: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.buildPath');
  const cleanChild = child.startsWith('/') ? child.slice(1) : child;
  return `${base}/${cleanChild}`;
}

function pathExists(path: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.pathExists');
  try {
    return fs.accessSync(path);
  } catch (_err) {
    return false;
  }
}

function ensureDir(path: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.ensureDir');
  fs.mkdirSync(path, true);
}

function ensureEmptyDir(path: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.ensureEmptyDir');
  if (!pathExists(path)) {
    ensureDir(path);
    return;
  }
  let stat: fs.Stat;
  try {
    stat = fs.statSync(path);
  } catch (err) {
    throw err instanceof Error ? err : new Error(formatError(err as object));
  }
  if (stat.isDirectory()) {
    deleteDirContents(path);
    return;
  }
  fs.unlinkSync(path);
  ensureDir(path);
}

function isSafeEntryName(entry: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.isSafeEntryName');
  if (!entry || entry.trim().length === 0) {
    return false;
  }
  if (entry.includes('/') || entry.includes('\\')) {
    return false;
  }
  return !entry.includes('..');
}

function openReadFile(path: string): number {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.openReadFile');
  try {
    return fs.openSync(path, fs.OpenMode.READ_ONLY).fd;
  } catch (err) {
    const errMessage = formatError(err as object);
    const errCode = formatErrorCode(err as object);
    hilog.error(0x0000, TAG, `openReadFile failed path=${path} code=${errCode} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=open_read path=${safePath(path)} code=${errCode} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }
}

function openWriteFile(path: string): number {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.openWriteFile');
  try {
    return fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC).fd;
  } catch (err) {
    const errMessage = formatError(err as object);
    const errCode = formatErrorCode(err as object);
    hilog.error(0x0000, TAG, `openWriteFile failed path=${path} code=${errCode} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=open_write path=${safePath(path)} code=${errCode} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }
}

function copyFileByPath(srcPath: string, dstPath: string): number {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.copyFileByPath');
  let srcFd: number | null = null;
  let dstFd: number | null = null;
  try {
    srcFd = openReadFile(srcPath);
    dstFd = openWriteFile(dstPath);
    const buffer = new ArrayBuffer(COPY_BUFFER_BYTES);
    let totalWritten = 0;
    while (true) {
      const bytesRead = fs.readSync(srcFd, buffer);
      if (bytesRead <= 0) {
        break;
      }
      fs.writeSync(dstFd, buffer, { length: bytesRead });
      totalWritten += bytesRead;
    }
    return totalWritten;
  } finally {
    if (srcFd !== null) {
      try {
        fs.closeSync(srcFd);
      } catch (_err) {
        // ignore close failure
      }
    }
    if (dstFd !== null) {
      try {
        fs.closeSync(dstFd);
      } catch (_err) {
        // ignore close failure
      }
    }
  }
}

function listEntriesOrEmpty(path: string): string[] {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.listEntriesOrEmpty');
  try {
    return fs.listFileSync(path);
  } catch (_err) {
    return [];
  }
}

function deleteDirContents(path: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.deleteDirContents');
  const entries = fs.listFileSync(path);
  entries.forEach((entry: string) => {
    if (!isSafeEntryName(entry)) {
      hilog.warn(0x0000, TAG, `deleteDirContents skip unsafe entry=${entry}`);
      return;
    }
    const childPath = buildPath(path, entry);
    const stat = fs.statSync(childPath);
    if (stat.isDirectory()) {
      deleteDirContents(childPath);
      fs.rmdirSync(childPath);
    } else {
      fs.unlinkSync(childPath);
    }
  });
}

function copyDirectoryFiles(sourceDir: string, targetDir: string): number {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.copyDirectoryFiles');
  let copied = 0;
  const entries = listEntriesOrEmpty(sourceDir);
  entries.forEach((entry: string) => {
    if (!isSafeEntryName(entry)) {
      hilog.warn(0x0000, TAG, `copyDirectoryFiles skip unsafe entry=${entry}`);
      return;
    }
    const srcPath = buildPath(sourceDir, entry);
    let stat: fs.Stat;
    try {
      stat = fs.statSync(srcPath);
    } catch (err) {
      const errMessage = formatError(err as object);
      hilog.warn(0x0000, TAG, `copyDirectoryFiles stat failed entry=${entry} message=${errMessage}`);
      return;
    }
    if (!stat.isFile()) {
      hilog.warn(0x0000, TAG, `copyDirectoryFiles skip non-file entry=${entry}`);
      return;
    }
    const dstPath = buildPath(targetDir, entry);
    copyFileByPath(srcPath, dstPath);
    copied += 1;
  });
  return copied;
}

/**
 * Copy `${filesDir}/diary_images/` into staging `files/diary_images/`.
 * Missing source dir is treated as empty.
 */
export async function copyDiaryImagesToStaging(filesDir: string, stagingDir: string): Promise<void> {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.copyDiaryImagesToStaging');
  const normalizedFilesDir = normalizeBaseDir(filesDir, 'filesDir');
  const normalizedStagingDir = normalizeBaseDir(stagingDir, 'stagingDir');
  const sourceDir = buildPath(normalizedFilesDir, BackupConstants.ZIP_DIR_DIARY_IMAGES);
  const stagingFilesDir = buildPath(normalizedStagingDir, BackupConstants.ZIP_DIR_FILES);
  const targetDir = buildPath(stagingFilesDir, BackupConstants.ZIP_DIR_DIARY_IMAGES);

  hilog.info(0x0000, TAG, `databackup.stage=media_backup_start sourceDir=${safePath(sourceDir)} targetDir=${safePath(targetDir)}`);
  // Note: targetDir is already created by BackupStagingBuilder, no need to ensureDir again

  if (!pathExists(sourceDir)) {
    hilog.info(0x0000, TAG, 'copyDiaryImagesToStaging source dir missing, treat as empty');
    return;
  }

  const copied = copyDirectoryFiles(sourceDir, targetDir);
  hilog.info(0x0000, TAG, `databackup.stage=media_backup_done copied=${copied}`);
}

/**
 * Clear `${filesDir}/diary_images/` and overwrite from extracted `files/diary_images/`.
 */
export async function clearAndRestoreDiaryImages(filesDir: string, extractedDir: string): Promise<void> {
  hilog.info(0x0000, TAG, 'databackup.BackupMediaAdapter.clearAndRestoreDiaryImages');
  const normalizedFilesDir = normalizeBaseDir(filesDir, 'filesDir');
  const normalizedExtractedDir = normalizeBaseDir(extractedDir, 'extractedDir');
  const targetDir = buildPath(normalizedFilesDir, BackupConstants.ZIP_DIR_DIARY_IMAGES);
  const extractedFilesDir = buildPath(normalizedExtractedDir, BackupConstants.ZIP_DIR_FILES);
  const sourceDir = buildPath(extractedFilesDir, BackupConstants.ZIP_DIR_DIARY_IMAGES);

  hilog.info(0x0000, TAG, `databackup.stage=media_restore_start sourceDir=${safePath(sourceDir)} targetDir=${safePath(targetDir)}`);
  try {
    ensureEmptyDir(targetDir);
  } catch (err) {
    const errMessage = formatError(err as object);
    const errCode = formatErrorCode(err as object);
    hilog.error(0x0000, TAG, `clearAndRestoreDiaryImages clear failed code=${errCode} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=media_restore_clear code=${errCode} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }

  if (!pathExists(sourceDir)) {
    hilog.warn(0x0000, TAG, 'clearAndRestoreDiaryImages extracted dir missing, restore as empty');
    return;
  }

  const copied = copyDirectoryFiles(sourceDir, targetDir);
  hilog.info(0x0000, TAG, `databackup.stage=media_restore_done copied=${copied}`);
}
