import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'BackupConstants';

/**
 * Domain constants for FlowDiary data backup (Zip v1).
 */
export class BackupConstants {
  static readonly BACKUP_VERSION_V1: number = 1;

  static readonly BACKUP_FILE_PREFIX: string = 'FlowDiaryBackup_';
  static readonly BACKUP_FILE_SUFFIX: string = '.zip';

  // Locked by implementation-plan.md
  static readonly DEFAULT_RETENTION: number = 10;
  static readonly MIN_RETENTION: number = 1;
  static readonly MAX_RETENTION: number = 10;

  static readonly DB_NAME: string = 'Objective.db';
  static readonly DB_BACKUP_FILE_NAME: string = 'Objective.db.bak';

  static readonly MANIFEST_FILE_NAME: string = 'manifest.json';

  static readonly ZIP_DIR_DB: string = 'db';
  static readonly ZIP_DIR_FILES: string = 'files';
  static readonly ZIP_DIR_DIARY_IMAGES: string = 'diary_images';

  static readonly ZIP_PATH_DB_BACKUP: string = 'db/Objective.db.bak';
  static readonly ZIP_PATH_FILES_DIARY_IMAGES: string = 'files/diary_images';

  // Timestamp format decision: local time for user readability.
  // File name: FlowDiaryBackup_YYYYMMDD_HHmmss.zip (local time)
  static readonly FILENAME_TIMESTAMP_IS_LOCAL_TIME: boolean = true;
}

function pad2(value: number): string {
  hilog.info(0x0000, TAG, 'databackup.BackupConstants.pad2');
  const text: string = value.toString();
  return text.length >= 2 ? text : `0${text}`;
}

/**
 * Formats a filename timestamp in local time: YYYYMMDD_HHmmss.
 */
export function formatBackupFilenameTimestamp(createdAtMs: number): string {
  hilog.info(0x0000, TAG, 'databackup.BackupConstants.formatBackupFilenameTimestamp');
  const date: Date = new Date(createdAtMs);
  const yyyy: string = date.getFullYear().toString();
  const mm: string = pad2(date.getMonth() + 1);
  const dd: string = pad2(date.getDate());
  const hh: string = pad2(date.getHours());
  const min: string = pad2(date.getMinutes());
  const ss: string = pad2(date.getSeconds());
  return `${yyyy}${mm}${dd}_${hh}${min}${ss}`;
}

/**
 * Builds a FlowDiary backup zip filename from `createdAt` (ms since epoch).
 */
export function buildBackupZipFileName(createdAtMs: number): string {
  hilog.info(0x0000, TAG, 'databackup.BackupConstants.buildBackupZipFileName');
  return `${BackupConstants.BACKUP_FILE_PREFIX}${formatBackupFilenameTimestamp(createdAtMs)}${BackupConstants.BACKUP_FILE_SUFFIX}`;
}
