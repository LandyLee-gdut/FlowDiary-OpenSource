import fs from '@ohos.file.fs';
import relationalStore from '@ohos.data.relationalStore';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RDBStoreUtil } from '../database/RDBStoreUtil';

const TAG: string = 'BackupRdbAdapter';

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

function normalizePath(path: string, label: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupRdbAdapter.normalizePath');
  if (!path) {
    throw new Error(`BackupRdbAdapter invalid ${label}: empty`);
  }
  const trimmed = path.trim();
  if (trimmed.length === 0) {
    throw new Error(`BackupRdbAdapter invalid ${label}: empty`);
  }
  return trimmed;
}

function formatError(err: object): string {
  hilog.info(0x0000, TAG, 'databackup.BackupRdbAdapter.formatError');
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
  hilog.info(0x0000, TAG, 'databackup.BackupRdbAdapter.formatErrorCode');
  const maybeError = err as ErrorLike;
  if (maybeError && typeof maybeError.code === 'number') {
    return maybeError.code.toString();
  }
  return '-1';
}

function getRdbStoreOrThrow(): relationalStore.RdbStore {
  hilog.info(0x0000, TAG, 'databackup.BackupRdbAdapter.getRdbStoreOrThrow');
  let rdbStoreUtil: RDBStoreUtil;
  try {
    rdbStoreUtil = RDBStoreUtil.getInstance();
  } catch (err) {
    const errMessage = formatError(err as object);
    throw new Error(`BackupRdbAdapter RDBStoreUtil not initialized: ${errMessage}`);
  }

  const rdbStore = rdbStoreUtil.getRdbStore();
  if (!rdbStore) {
    throw new Error('BackupRdbAdapter RdbStore not ready. Call RDBStoreUtil.init(context) + initRDB() before backup/restore.');
  }
  return rdbStore;
}

function assertBackupFileReady(path: string): number {
  hilog.info(0x0000, TAG, 'databackup.BackupRdbAdapter.assertBackupFileReady');
  try {
    const stat = fs.statSync(path);
    if (!stat.isFile()) {
      throw new Error('BackupRdbAdapter backup path is not a file');
    }
    const size = Number(stat.size) || 0;
    if (size <= 0) {
      throw new Error('BackupRdbAdapter backup file is empty');
    }
    return size;
  } catch (err) {
    const errMessage = formatError(err as object);
    throw new Error(`BackupRdbAdapter backup file missing: ${errMessage}`);
  }
}

function assertRestoreFileReady(path: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupRdbAdapter.assertRestoreFileReady');
  try {
    const stat = fs.statSync(path);
    if (!stat.isFile()) {
      throw new Error('BackupRdbAdapter restore path is not a file');
    }
    const size = Number(stat.size) || 0;
    if (size <= 0) {
      throw new Error('BackupRdbAdapter restore file is empty');
    }
  } catch (err) {
    const errMessage = formatError(err as object);
    throw new Error(`BackupRdbAdapter restore file missing: ${errMessage}`);
  }
}

/**
 * Backup RDB to a specified file path.
 * Caller must ensure RDBStoreUtil.init(context) + initRDB() have completed.
 */
export async function backupToFile(outPath: string): Promise<void> {
  hilog.info(0x0000, TAG, 'databackup.BackupRdbAdapter.backupToFile');
  const normalizedPath = normalizePath(outPath, 'outPath');
  const rdbStore = getRdbStoreOrThrow();
  hilog.info(0x0000, TAG, `databackup.stage=rdb_backup_start path=${safePath(normalizedPath)}`);

  try {
    await rdbStore.backup(normalizedPath);
  } catch (err) {
    const errCode = formatErrorCode(err as object);
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG, `backupToFile failed code=${errCode} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=rdb_backup code=${errCode} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }

  const size = assertBackupFileReady(normalizedPath);
  hilog.info(0x0000, TAG, `databackup.stage=rdb_backup_done path=${safePath(normalizedPath)} size=${size}`);
}

/**
 * Restore RDB from a specified backup file path.
 * Caller must ensure RDBStoreUtil.init(context) + initRDB() have completed.
 */
export async function restoreFromFile(inPath: string): Promise<void> {
  hilog.info(0x0000, TAG, 'databackup.BackupRdbAdapter.restoreFromFile');
  const normalizedPath = normalizePath(inPath, 'inPath');
  const rdbStore = getRdbStoreOrThrow();
  hilog.info(0x0000, TAG, `databackup.stage=rdb_restore_start path=${safePath(normalizedPath)}`);

  assertRestoreFileReady(normalizedPath);

  try {
    await rdbStore.restore(normalizedPath);
    hilog.info(0x0000, TAG, `databackup.stage=rdb_restore_done path=${safePath(normalizedPath)}`);
  } catch (err) {
    const errCode = formatErrorCode(err as object);
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG, `restoreFromFile failed code=${errCode} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=rdb_restore code=${errCode} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }
}
