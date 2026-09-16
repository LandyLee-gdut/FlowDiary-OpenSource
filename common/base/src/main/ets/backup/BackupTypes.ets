export enum BackupErrorCode {
  INVALID_ZIP = 1,
  MISSING_MANIFEST = 2,
  UNSUPPORTED_VERSION = 3,
  MISSING_DB_BACKUP = 4,
  CORRUPT_MANIFEST = 5,
  PERMISSION_DENIED = 6,
  IO_ERROR = 7,
  CANCELLED_BY_USER = 8,
  UNSUPPORTED = 9,
  BUSY = 10
}

export type BackupIncludeItem = 'rdb' | 'diary_images';

/**
 * Zip v1 manifest schema (domain type).
 */
export interface BackupManifestV1 {
  backupVersion: number;
  createdAt: number;
  appVersion: string;
  dbName: string;
  includes: BackupIncludeItem[];

  deviceType?: string;
  bundleName?: string;
  buildNumber?: string;
  notes?: string;
}

export interface BackupValidationIssue {
  code: BackupErrorCode;
  message: string;
}

export interface BackupValidationResult {
  ok: boolean;
  manifest?: BackupManifestV1;
  issue?: BackupValidationIssue;
  warnings?: string[];
}

export interface BackupResult {
  ok: boolean;
  code?: BackupErrorCode;
  message: string;
  detail?: string;
  createdAt?: number;
  zipUri?: string;
  outputUri?: string;
  autoDirUri?: string;
  deletedCount?: number;
  validation?: BackupValidationResult;
  manifest?: BackupManifestV1;
}

export interface AutoBackupDirState {
  enabled: boolean;
  dirUri?: string;
  issue?: BackupValidationIssue;
}

export interface BackupListItem {
  fileName: string;
  uri: string;
  createdAt: number;
  size: number;
}
