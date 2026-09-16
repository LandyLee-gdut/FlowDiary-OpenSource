import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupConstants, buildBackupZipFileName } from './BackupConstants';
import { clearAndRestoreDiaryImages, copyDiaryImagesToStaging } from './BackupMediaAdapter';
import { BackupErrorCode, BackupIncludeItem, BackupManifestV1, BackupResult, BackupValidationResult } from './BackupTypes';
import { backupToFile, restoreFromFile } from './BackupRdbAdapter';
import { purgeOldBackups } from './BackupRepository';
import { BackupStagingOptions, withBackupStagingDir } from './BackupStagingBuilder';
import { quickValidateZipInput, validateExtractedDir } from './BackupPackageValidator';
import { ensureAutoBackupDir } from './BackupLocationManager';
import { compressDirectory, decompressToDir, withRestoreExtractDir } from './BackupZipAdapter';

const TAG: string = 'BackupService';

interface ErrorLike {
  code?: number;
  message?: string;
}

interface BackupTaskResult {
  createdAt: number;
  zipUri: string;
  outputUri?: string;
}

interface BackupResultExtras {
  autoDirUri?: string;
  deletedCount?: number;
  validation?: BackupValidationResult;
  manifest?: BackupManifestV1;
}

export interface ManualBackupOptions {
  context: common.UIAbilityContext;
  appVersion: string;
  exportUri: string;
  includes?: BackupIncludeItem[];
  deviceType?: string;
  bundleName?: string;
  buildNumber?: string;
  notes?: string;
}

export interface ManualBackupPrepareOptions {
  context: common.UIAbilityContext;
  appVersion: string;
  includes?: BackupIncludeItem[];
  deviceType?: string;
  bundleName?: string;
  buildNumber?: string;
  notes?: string;
}

export interface AutoBackupOptions {
  context: common.UIAbilityContext;
  appVersion: string;
  retentionCount?: number;
  includes?: BackupIncludeItem[];
  deviceType?: string;
  bundleName?: string;
  buildNumber?: string;
  notes?: string;
}

export interface RestoreBackupOptions {
  context: common.UIAbilityContext;
  zipPathOrUri: string;
}

let activeOperation: string | null = null;

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
  hilog.info(0x0000, TAG, 'databackup.BackupService.formatError');
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
  hilog.info(0x0000, TAG, 'databackup.BackupService.formatErrorCode');
  const maybeError = err as ErrorLike;
  if (maybeError && typeof maybeError.code === 'number') {
    return maybeError.code.toString();
  }
  return '-1';
}

function normalizePath(path: string, label: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupService.normalizePath');
  if (!path) {
    throw new Error(`BackupService invalid ${label}: empty`);
  }
  const trimmed = path.trim();
  if (trimmed.length === 0) {
    throw new Error(`BackupService invalid ${label}: empty`);
  }
  return trimmed;
}

function normalizeDir(path: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupService.normalizeDir');
  return path.endsWith('/') ? path.slice(0, -1) : path;
}

function resolveTempDir(ctx?: common.UIAbilityContext): string {
  hilog.info(0x0000, TAG, 'databackup.BackupService.resolveTempDir');
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

  throw new Error('BackupService invalid context: tempDir is missing');
}

function resolveFilesDir(ctx?: common.UIAbilityContext): string {
  hilog.info(0x0000, TAG, 'databackup.BackupService.resolveFilesDir');
  if (ctx && typeof ctx.filesDir === 'string' && ctx.filesDir.trim().length > 0) {
    return ctx.filesDir;
  }

  try {
    const appCtx = AppStorage.get('context') as common.UIAbilityContext;
    if (appCtx && typeof appCtx.filesDir === 'string' && appCtx.filesDir.trim().length > 0) {
      hilog.warn(0x0000, TAG, 'resolveFilesDir fallback to AppStorage context filesDir');
      return appCtx.filesDir;
    }
  } catch (_err) {
    // ignore and throw below
  }

  throw new Error('BackupService invalid context: filesDir is missing');
}

function buildTempZipPath(ctx: common.UIAbilityContext, createdAt: number): string {
  hilog.info(0x0000, TAG, 'databackup.BackupService.buildTempZipPath');
  const tempDir = normalizeDir(resolveTempDir(ctx));
  const fileName = buildBackupZipFileName(createdAt);
  return `${tempDir}/${fileName}`;
}

function buildPath(base: string, child: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupService.buildPath');
  const cleanChild = child.startsWith('/') ? child.slice(1) : child;
  return `${base}/${cleanChild}`;
}

function copyFileByPath(srcPath: string, dstPath: string): number {
  hilog.info(0x0000, TAG, 'databackup.BackupService.copyFileByPath');
  let srcFd: number | null = null;
  let dstFd: number | null = null;
  try {
    srcFd = fs.openSync(srcPath, fs.OpenMode.READ_ONLY).fd;
    dstFd = fs.openSync(dstPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC).fd;
    const buffer = new ArrayBuffer(1024 * 1024);
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

function cleanupFileBestEffort(path: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupService.cleanupFileBestEffort');
  try {
    fs.unlinkSync(path);
  } catch (_err) {
    // ignore cleanup failure
  }
}

function buildBusyResult(operation: string): BackupResult {
  hilog.info(0x0000, TAG, 'databackup.BackupService.buildBusyResult');
  return {
    ok: false,
    code: BackupErrorCode.BUSY,
    message: 'Backup is busy',
    detail: `busy: ${operation}`
  };
}

function buildFailureResult(code: BackupErrorCode, message: string, detail?: string, validation?: BackupValidationResult): BackupResult {
  hilog.info(0x0000, TAG, 'databackup.BackupService.buildFailureResult');
  return {
    ok: false,
    code,
    message,
    detail,
    validation
  };
}

function buildSuccessResult(message: string, task: BackupTaskResult, extra?: BackupResultExtras): BackupResult {
  hilog.info(0x0000, TAG, 'databackup.BackupService.buildSuccessResult');
  const result: BackupResult = {
    ok: true,
    message,
    createdAt: task.createdAt,
    zipUri: task.zipUri,
    outputUri: task.outputUri
  };
  if (extra) {
    if (extra.autoDirUri) {
      result.autoDirUri = extra.autoDirUri;
    }
    if (typeof extra.deletedCount === 'number') {
      result.deletedCount = extra.deletedCount;
    }
    if (extra.validation) {
      result.validation = extra.validation;
    }
    if (extra.manifest) {
      result.manifest = extra.manifest;
    }
  }
  return result;
}

function acquireOperation(operation: string): boolean {
  hilog.info(0x0000, TAG, 'databackup.BackupService.acquireOperation');
  if (activeOperation) {
    return false;
  }
  activeOperation = operation;
  return true;
}

function releaseOperation(operation: string): void {
  hilog.info(0x0000, TAG, 'databackup.BackupService.releaseOperation');
  if (activeOperation === operation) {
    activeOperation = null;
    return;
  }
  activeOperation = null;
}

function resolveAutoDirPath(dirUri: string): string {
  hilog.info(0x0000, TAG, 'databackup.BackupService.resolveAutoDirPath');
  const trimmed = normalizeDir(dirUri.trim());
  if (trimmed.startsWith('file://')) {
    try {
      return normalizeDir(new fileUri.FileUri(trimmed).path);
    } catch (_err) {
      return trimmed;
    }
  }
  return trimmed;
}

type OutputPathBuilder = (createdAt: number) => string;

async function runBackupPipeline(
  options: BackupStagingOptions,
  context: common.UIAbilityContext,
  buildOutputPath: OutputPathBuilder,
  exportUri?: string
): Promise<BackupTaskResult> {
  hilog.info(0x0000, TAG, 'databackup.BackupService.runBackupPipeline');
  const filesDir = resolveFilesDir(context);
  return withBackupStagingDir(options, async (staging) => {
    hilog.info(0x0000, TAG, `databackup.stage=staging_ready dir=${safePath(staging.stagingDir)}`);
    const outputZipUri = buildOutputPath(staging.createdAt);
    const dbBackupPath = buildPath(staging.dbDir, BackupConstants.DB_BACKUP_FILE_NAME);
    hilog.info(0x0000, TAG, `databackup.stage=db_backup path=${safePath(dbBackupPath)}`);
    await backupToFile(dbBackupPath);
    hilog.info(0x0000, TAG, `databackup.stage=media_backup filesDir=${safePath(filesDir)}`);
    await copyDiaryImagesToStaging(filesDir, staging.stagingDir);
    hilog.info(0x0000, TAG, `databackup.stage=zip_compress out=${safePath(outputZipUri)}`);
    await compressDirectory(staging.stagingDir, outputZipUri);

    if (exportUri) {
      if (exportUri !== outputZipUri) {
        hilog.info(0x0000, TAG, `databackup.stage=export_copy from=${safePath(outputZipUri)} to=${safePath(exportUri)}`);
        copyFileByPath(outputZipUri, exportUri);
      }
      const result: BackupTaskResult = {
        createdAt: staging.createdAt,
        zipUri: outputZipUri,
        outputUri: exportUri
      };
      return result;
    }

    const result: BackupTaskResult = {
      createdAt: staging.createdAt,
      zipUri: outputZipUri
    };
    return result;
  });
}

export async function createManualBackupAndExport(options: ManualBackupOptions): Promise<BackupResult> {
  hilog.info(0x0000, TAG, 'databackup.BackupService.createManualBackupAndExport');
  const operation = 'manual_export';
  if (!acquireOperation(operation)) {
    return buildBusyResult(operation);
  }
  hilog.info(0x0000, TAG, `databackup.stage=manual_export_start op=${operation}`);

  try {
    if (!options) {
      return buildFailureResult(BackupErrorCode.IO_ERROR, 'Backup options missing');
    }

    const exportUri = normalizePath(options.exportUri, 'exportUri');
    const stagingOptions: BackupStagingOptions = {
      context: options.context,
      appVersion: options.appVersion,
      includes: options.includes,
      deviceType: options.deviceType,
      bundleName: options.bundleName,
      buildNumber: options.buildNumber,
      notes: options.notes
    };

    const task = await runBackupPipeline(stagingOptions, options.context, (createdAt) => {
      return buildTempZipPath(options.context, createdAt);
    }, exportUri);

    if (task.outputUri && task.outputUri !== task.zipUri) {
      cleanupFileBestEffort(task.zipUri);
    }

    return buildSuccessResult('Backup exported', task);
  } catch (err) {
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG,
      `createManualBackupAndExport failed code=${formatErrorCode(err as object)} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error op=${operation} stage=manual_export msg=${errMessage}`);
    return buildFailureResult(BackupErrorCode.IO_ERROR, 'Backup export failed', errMessage);
  } finally {
    releaseOperation(operation);
    hilog.info(0x0000, TAG, `databackup.stage=manual_export_end op=${operation}`);
  }
}

export async function createManualBackup(options: ManualBackupPrepareOptions): Promise<BackupResult> {
  hilog.info(0x0000, TAG, 'databackup.BackupService.createManualBackup');
  const operation = 'manual_prepare';
  if (!acquireOperation(operation)) {
    return buildBusyResult(operation);
  }
  hilog.info(0x0000, TAG, `databackup.stage=manual_prepare_start op=${operation}`);

  try {
    if (!options) {
      return buildFailureResult(BackupErrorCode.IO_ERROR, 'Backup options missing');
    }

    const stagingOptions: BackupStagingOptions = {
      context: options.context,
      appVersion: options.appVersion,
      includes: options.includes,
      deviceType: options.deviceType,
      bundleName: options.bundleName,
      buildNumber: options.buildNumber,
      notes: options.notes
    };

    const task = await runBackupPipeline(stagingOptions, options.context, (createdAt) => {
      return buildTempZipPath(options.context, createdAt);
    });

    return buildSuccessResult('Backup ready', task);
  } catch (err) {
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG,
      `createManualBackup failed code=${formatErrorCode(err as object)} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error op=${operation} stage=manual_prepare msg=${errMessage}`);
    return buildFailureResult(BackupErrorCode.IO_ERROR, 'Backup prepare failed', errMessage);
  } finally {
    releaseOperation(operation);
    hilog.info(0x0000, TAG, `databackup.stage=manual_prepare_end op=${operation}`);
  }
}

export async function createAutoBackup(options: AutoBackupOptions): Promise<BackupResult> {
  hilog.info(0x0000, TAG, 'databackup.BackupService.createAutoBackup');
  const operation = 'auto_backup';
  if (!acquireOperation(operation)) {
    return buildBusyResult(operation);
  }
  hilog.info(0x0000, TAG, `databackup.stage=auto_backup_start op=${operation}`);

  try {
    if (!options) {
      return buildFailureResult(BackupErrorCode.IO_ERROR, 'Backup options missing');
    }

    const dirState = await ensureAutoBackupDir(options.context);
    if (!dirState.enabled || !dirState.dirUri) {
      const code = dirState.issue?.code ?? BackupErrorCode.PERMISSION_DENIED;
      const message = dirState.issue?.message ?? 'Auto backup directory unavailable';
      return buildFailureResult(code, 'Auto backup unavailable', message);
    }

    const autoDirPath = resolveAutoDirPath(dirState.dirUri);
    const stagingOptions: BackupStagingOptions = {
      context: options.context,
      appVersion: options.appVersion,
      includes: options.includes,
      deviceType: options.deviceType,
      bundleName: options.bundleName,
      buildNumber: options.buildNumber,
      notes: options.notes
    };

    const task = await runBackupPipeline(stagingOptions, options.context, (createdAt) => {
      return buildPath(autoDirPath, buildBackupZipFileName(createdAt));
    });

    let deletedCount = 0;
    try {
      hilog.info(0x0000, TAG, `databackup.stage=retention_cleanup dir=${safePath(autoDirPath)}`);
      deletedCount = await purgeOldBackups(autoDirPath, options.retentionCount);
    } catch (err) {
      hilog.warn(0x0000, TAG, `createAutoBackup retention cleanup failed: ${formatError(err as object)}`);
      hilog.warn(0x0000, TAG, `databackup.error op=${operation} stage=retention_cleanup msg=${formatError(err as object)}`);
    }

    return buildSuccessResult('Auto backup created', task, {
      autoDirUri: dirState.dirUri,
      deletedCount
    });
  } catch (err) {
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG,
      `createAutoBackup failed code=${formatErrorCode(err as object)} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error op=${operation} stage=auto_backup msg=${errMessage}`);
    return buildFailureResult(BackupErrorCode.IO_ERROR, 'Auto backup failed', errMessage);
  } finally {
    releaseOperation(operation);
    hilog.info(0x0000, TAG, `databackup.stage=auto_backup_end op=${operation}`);
  }
}

export async function validateBackupZip(options: RestoreBackupOptions): Promise<BackupResult> {
  hilog.info(0x0000, TAG, 'databackup.BackupService.validateBackupZip');
  const operation = 'import_validate';
  if (!acquireOperation(operation)) {
    return buildBusyResult(operation);
  }
  hilog.info(0x0000, TAG, `databackup.stage=import_validate_start op=${operation}`);

  try {
    if (!options) {
      return buildFailureResult(BackupErrorCode.IO_ERROR, 'Validate options missing');
    }

    const zipPath = normalizePath(options.zipPathOrUri, 'zipPathOrUri');
    hilog.info(0x0000, TAG, `databackup.stage=zip_validate path=${safePath(zipPath)}`);
    const quickValidation = quickValidateZipInput(zipPath);
    if (!quickValidation.ok) {
      const issue = quickValidation.issue;
      return buildFailureResult(issue?.code ?? BackupErrorCode.INVALID_ZIP,
        'Backup file is not recognized', issue?.message, quickValidation);
    }

    const validation = await withRestoreExtractDir(options.context, async (extractDir) => {
      hilog.info(0x0000, TAG, `databackup.stage=zip_decompress outDir=${safePath(extractDir)}`);
      await decompressToDir(zipPath, extractDir);
      hilog.info(0x0000, TAG, `databackup.stage=dir_validate dir=${safePath(extractDir)}`);
      return await validateExtractedDir(extractDir);
    });

    if (!validation.ok) {
      return buildFailureResult(
        validation.issue?.code ?? BackupErrorCode.INVALID_ZIP,
        'Backup file is not recognized',
        validation.issue?.message,
        validation
      );
    }

    return buildSuccessResult('Backup validated', {
      createdAt: validation.manifest?.createdAt ?? Date.now(),
      zipUri: zipPath
    }, {
      validation,
      manifest: validation.manifest
    });
  } catch (err) {
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG,
      `validateBackupZip failed code=${formatErrorCode(err as object)} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error op=${operation} stage=import_validate msg=${errMessage}`);
    return buildFailureResult(BackupErrorCode.IO_ERROR, 'Backup validate failed', errMessage);
  } finally {
    releaseOperation(operation);
    hilog.info(0x0000, TAG, `databackup.stage=import_validate_end op=${operation}`);
  }
}

export async function importAndRestore(options: RestoreBackupOptions): Promise<BackupResult> {
  hilog.info(0x0000, TAG, 'databackup.BackupService.importAndRestore');
  const operation = 'import_restore';
  if (!acquireOperation(operation)) {
    return buildBusyResult(operation);
  }
  hilog.info(0x0000, TAG, `databackup.stage=import_restore_start op=${operation}`);

  try {
    if (!options) {
      return buildFailureResult(BackupErrorCode.IO_ERROR, 'Restore options missing');
    }

    const zipPath = normalizePath(options.zipPathOrUri, 'zipPathOrUri');
    hilog.info(0x0000, TAG, `databackup.stage=zip_validate path=${safePath(zipPath)}`);
    const quickValidation = quickValidateZipInput(zipPath);
    if (!quickValidation.ok) {
      const issue = quickValidation.issue;
      return buildFailureResult(issue?.code ?? BackupErrorCode.INVALID_ZIP,
        'Backup file is not recognized', issue?.message, quickValidation);
    }

    const filesDir = resolveFilesDir(options.context);
    const restoreResult = await withRestoreExtractDir(options.context, async (extractDir) => {
      hilog.info(0x0000, TAG, `databackup.stage=zip_decompress outDir=${safePath(extractDir)}`);
      await decompressToDir(zipPath, extractDir);
      hilog.info(0x0000, TAG, `databackup.stage=dir_validate dir=${safePath(extractDir)}`);
      const validation = await validateExtractedDir(extractDir);
      if (!validation.ok) {
        return buildFailureResult(
          validation.issue?.code ?? BackupErrorCode.INVALID_ZIP,
          'Backup file is not recognized',
          validation.issue?.message,
          validation
        );
      }

      const dbBackupPath = buildPath(extractDir, BackupConstants.ZIP_PATH_DB_BACKUP);
      hilog.info(0x0000, TAG, `databackup.stage=db_restore path=${safePath(dbBackupPath)}`);
      await restoreFromFile(dbBackupPath);
      hilog.info(0x0000, TAG, `databackup.stage=media_restore dir=${safePath(extractDir)}`);
      await clearAndRestoreDiaryImages(filesDir, extractDir);
      return buildSuccessResult('Data restored', {
        createdAt: validation.manifest?.createdAt ?? Date.now(),
        zipUri: zipPath
      }, {
        validation,
        manifest: validation.manifest
      });
    });

    return restoreResult;
  } catch (err) {
    const errMessage = formatError(err as object);
    hilog.error(0x0000, TAG,
      `importAndRestore failed code=${formatErrorCode(err as object)} message=${errMessage}`);
    hilog.error(0x0000, TAG, `databackup.error op=${operation} stage=import_restore msg=${errMessage}`);
    return buildFailureResult(BackupErrorCode.IO_ERROR, 'Restore failed', errMessage);
  } finally {
    releaseOperation(operation);
    hilog.info(0x0000, TAG, `databackup.stage=import_restore_end op=${operation}`);
  }
}
