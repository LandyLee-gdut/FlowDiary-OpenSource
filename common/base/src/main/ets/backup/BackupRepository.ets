import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupConstants } from './BackupConstants';
import { BackupListItem } from './BackupTypes';

const TAG: string = 'BackupRepository';

interface ErrorLike {
  code?: number;
  message?: string;
}

interface StatWithTimes {
  mtimeMs?: number;
  mtime?: number | string | Date;
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
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.formatError');
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

function normalizeDir(path: string, label: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.normalizeDir');
  if (!path) {
    throw new Error(`BackupRepository invalid ${label}: empty`);
  }
  const trimmed = path.trim();
  if (trimmed.length === 0) {
    throw new Error(`BackupRepository invalid ${label}: empty`);
  }
  return trimmed.endsWith('/') ? trimmed.slice(0, -1) : trimmed;
}

function buildPath(base: string, child: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.buildPath');
  const cleanChild = child.startsWith('/') ? child.slice(1) : child;
  return `${base}/${cleanChild}`;
}

function isSafeEntryName(entry: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.isSafeEntryName');
  if (!entry || entry.trim().length === 0) {
    return false;
  }
  if (entry.includes('/') || entry.includes('\\')) {
    return false;
  }
  return !entry.includes('..');
}

function isBackupZipName(fileName: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.isBackupZipName');
  return fileName.startsWith(BackupConstants.BACKUP_FILE_PREFIX) && fileName.endsWith(BackupConstants.BACKUP_FILE_SUFFIX);
}

function parseFilenameTimestamp(fileName: string): number | null {
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.parseFilenameTimestamp');
  const prefix = BackupConstants.BACKUP_FILE_PREFIX;
  const suffix = BackupConstants.BACKUP_FILE_SUFFIX;
  if (!fileName.startsWith(prefix) || !fileName.endsWith(suffix)) {
    return null;
  }

  const body = fileName.slice(prefix.length, fileName.length - suffix.length);
  const match = body.match(/^(\d{8})_(\d{6})$/);
  if (!match) {
    return null;
  }

  const datePart = match[1];
  const timePart = match[2];
  const year = Number(datePart.slice(0, 4));
  const month = Number(datePart.slice(4, 6));
  const day = Number(datePart.slice(6, 8));
  const hour = Number(timePart.slice(0, 2));
  const min = Number(timePart.slice(2, 4));
  const sec = Number(timePart.slice(4, 6));

  if (
    !Number.isFinite(year) ||
    !Number.isFinite(month) ||
    !Number.isFinite(day) ||
    !Number.isFinite(hour) ||
    !Number.isFinite(min) ||
    !Number.isFinite(sec)
  ) {
    return null;
  }

  const date = new Date(year, month - 1, day, hour, min, sec, 0);
  if (
    date.getFullYear() !== year ||
    date.getMonth() + 1 !== month ||
    date.getDate() !== day ||
    date.getHours() !== hour ||
    date.getMinutes() !== min ||
    date.getSeconds() !== sec
  ) {
    return null;
  }

  return date.getTime();
}

function extractMtimeMs(stat: fs.Stat): number | null {
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.extractMtimeMs');
  const record: StatWithTimes = stat as StatWithTimes;
  const mtimeMs = record.mtimeMs;
  if (typeof mtimeMs === 'number' && Number.isFinite(mtimeMs)) {
    return mtimeMs;
  }

  const mtime = record.mtime;
  if (mtime && typeof mtime === 'object') {
    const dateValue = mtime as Date;
    if (typeof dateValue.getTime === 'function') {
      const timeValue = dateValue.getTime();
      if (Number.isFinite(timeValue)) {
        return timeValue;
      }
    }
  }
  if (typeof mtime === 'number' && Number.isFinite(mtime)) {
    return mtime < 100000000000 ? mtime * 1000 : mtime;
  }
  if (typeof mtime === 'string') {
    const parsed = Date.parse(mtime);
    if (!Number.isNaN(parsed)) {
      return parsed;
    }
  }
  return null;
}

function normalizeRetentionCount(retentionCount: number | undefined): number {
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.normalizeRetentionCount');
  const fallback = BackupConstants.DEFAULT_RETENTION;
  if (typeof retentionCount !== 'number' || !Number.isFinite(retentionCount)) {
    return fallback;
  }
  const floor = Math.floor(retentionCount);
  if (floor < BackupConstants.MIN_RETENTION) {
    return BackupConstants.MIN_RETENTION;
  }
  if (floor > BackupConstants.MAX_RETENTION) {
    return BackupConstants.MAX_RETENTION;
  }
  return floor;
}

export async function listAutoBackups(autoDirUri: string): Promise<BackupListItem[]> {
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.listAutoBackups');
  const normalizedDir = normalizeDir(autoDirUri, 'autoDirUri');
  let entries: string[] = [];

  hilog.info(0x0000, TAG, `databackup.stage=list_auto_start dir=${safePath(normalizedDir)}`);
  try {
    entries = fs.listFileSync(normalizedDir);
  } catch (err) {
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG, `listAutoBackups list failed: ${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error stage=list_auto dir=${safePath(normalizedDir)} msg=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }

  const items: BackupListItem[] = [];
  entries.forEach((entry: string) => {
    if (!isSafeEntryName(entry)) {
      hilog.warn(0x0000, TAG, `listAutoBackups skip unsafe entry=${entry}`);
      return;
    }
    if (!isBackupZipName(entry)) {
      return;
    }

    const fullPath = buildPath(normalizedDir, entry);
    let stat: fs.Stat;
    try {
      stat = fs.statSync(fullPath);
    } catch (err) {
      hilog.warn(0x0000, TAG, `listAutoBackups stat failed entry=${entry} err=${formatError(err as object)}`);
      return;
    }

    if (!stat.isFile()) {
      return;
    }

    const size = Number(stat.size) || 0;
    let createdAt = parseFilenameTimestamp(entry);
    if (createdAt === null) {
      const fallbackTime = extractMtimeMs(stat);
      createdAt = fallbackTime !== null ? fallbackTime : Date.now();
    }

    items.push({
      fileName: entry,
      uri: fullPath,
      createdAt: createdAt,
      size: size
    });
  });

  items.sort((a, b) => {
    if (a.createdAt !== b.createdAt) {
      return b.createdAt - a.createdAt;
    }
    return a.fileName.localeCompare(b.fileName);
  });

  hilog.info(0x0000, TAG, `databackup.stage=list_auto_done dir=${safePath(normalizedDir)} count=${items.length}`);
  return items;
}

export async function purgeOldBackups(autoDirUri: string, retentionCount?: number): Promise<number> {
  hilog.info(0x0000, TAG, 'databackup.BackupRepository.purgeOldBackups');
  const normalizedDir = normalizeDir(autoDirUri, 'autoDirUri');
  const keep = normalizeRetentionCount(retentionCount);
  const items = await listAutoBackups(normalizedDir);

  if (items.length <= keep) {
    hilog.info(0x0000, TAG, `databackup.stage=purge_skip dir=${safePath(normalizedDir)} keep=${keep} count=${items.length}`);
    return 0;
  }

  let deleted = 0;
  const toDelete = items.slice(keep);
  hilog.info(0x0000, TAG, `databackup.stage=purge_start dir=${safePath(normalizedDir)} keep=${keep} delete=${toDelete.length}`);
  toDelete.forEach((item: BackupListItem) => {
    if (!isSafeEntryName(item.fileName) || !isBackupZipName(item.fileName)) {
      hilog.warn(0x0000, TAG, `purgeOldBackups skip unsafe item=${item.fileName}`);
      return;
    }
    if (!item.uri.startsWith(`${normalizedDir}/`)) {
      hilog.warn(0x0000, TAG, `purgeOldBackups skip out-of-scope uri=${item.fileName}`);
      return;
    }

    try {
      fs.unlinkSync(item.uri);
      deleted += 1;
      hilog.info(0x0000, TAG, `purgeOldBackups deleted ${item.fileName}`);
    } catch (err) {
      hilog.warn(0x0000, TAG, `purgeOldBackups delete failed ${item.fileName} err=${formatError(err as object)}`);
    }
  });

  hilog.info(0x0000, TAG, `databackup.stage=purge_done dir=${safePath(normalizedDir)} deleted=${deleted}`);
  return deleted;
}
