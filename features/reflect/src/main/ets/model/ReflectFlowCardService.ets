import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  RDBStoreUtil,
  TimeRecordUtil,
  TimeRecordWithContext,
  FilesDirCarrier,
  computeFileHashFromUri,
  relPathToImageUri,
  resolveStoredPath,
  savePickerUriToSandboxFiles,
  guessMimeTypeFromUri,
  deleteStoredFileBestEffort
} from 'base';
import fs from '@ohos.file.fs';

const TAG: string = 'ReflectFlowCardService';
const DAY_MS: number = 24 * 60 * 60 * 1000;

interface ErrorLike {
  code?: number;
  message?: string;
}

export interface ReflectFlowCardItem {
  activityId: string;
  title: string;
  label: string;
  labelColor: string | ResourceColor;
  durationInMilliseconds: number;
  latestStartTimeMs: number;
  timeRangeLabel: string;
}

export interface FlowCardCoverImageResult {
  relPath: string;
  imageUri: string;
}

interface ActivityAggregateData {
  activityId: string;
  title: string;
  label: string;
  labelColor: string | ResourceColor;
  totalDurationMs: number;
  latestStartTimeMs: number;
  timeRanges: ActivityTimeRange[];
}

interface ActivityTimeRange {
  startMs: number;
  endMs: number;
}

class ReflectFlowCardServiceImpl {
  async getDayFlowCardItems(dateMs: number): Promise<ReflectFlowCardItem[]> {
    const dayStart = TimeRecordUtil.getDayStart(dateMs);
    const dayEnd = dayStart + DAY_MS - 1;
    const rdbStoreUtil = RDBStoreUtil.getInstance();

    try {
      const records = await rdbStoreUtil.queryTimeRecordsWithActivityAndTag(dayStart, dayEnd);
      if (!records || records.length === 0) {
        return [];
      }

      const aggregates = this.aggregateRecords(records);
      return aggregates
        .sort((a, b) => a.latestStartTimeMs - b.latestStartTimeMs)
        .map((data): ReflectFlowCardItem => {
          return {
            activityId: data.activityId,
            title: data.title,
            label: data.label,
            labelColor: data.labelColor,
            durationInMilliseconds: data.totalDurationMs,
            latestStartTimeMs: data.latestStartTimeMs,
            timeRangeLabel: this.formatTimeRanges(data.timeRanges)
          };
        });
    } catch (error) {
      hilog.error(0x0000, TAG, `getDayFlowCardItems failed: ${JSON.stringify(error)}`);
      return [];
    }
  }

  private aggregateRecords(records: TimeRecordWithContext[]): ActivityAggregateData[] {
    const activityMap = new Map<string, ActivityAggregateData>();

    records.forEach((record: TimeRecordWithContext) => {
      if (record.endTimeMs === null && record.durationMs == null) {
        return;
      }

      const duration = record.durationMs
        ? record.durationMs
        : (record.endTimeMs ? (record.endTimeMs - record.startTimeMs) : 0);

      if (duration <= 0) {
        return;
      }

      const recordEnd = record.endTimeMs ?? (record.durationMs ? record.startTimeMs + record.durationMs : null);
      if (!recordEnd || recordEnd <= record.startTimeMs) {
        return;
      }

      const title = record.activityName || '未命名活动';
      const label = record.tagName || '未分配';
      const labelColor = record.tagColorHex || '#808080';
      const timeRange: ActivityTimeRange = { startMs: record.startTimeMs, endMs: recordEnd };

      const existing = activityMap.get(record.activityId);
      if (existing) {
        existing.totalDurationMs += duration;
        if (record.startTimeMs > existing.latestStartTimeMs) {
          existing.latestStartTimeMs = record.startTimeMs;
        }
        existing.timeRanges.push(timeRange);
      } else {
        activityMap.set(record.activityId, {
          activityId: record.activityId,
          title,
          label,
          labelColor,
          totalDurationMs: duration,
          latestStartTimeMs: record.startTimeMs,
          timeRanges: [timeRange]
        });
      }
    });

    return Array.from(activityMap.values())
      .filter((item) => item.totalDurationMs > 0);
  }

  private formatTimeRanges(ranges: ActivityTimeRange[]): string {
    if (!ranges || ranges.length === 0) {
      return '';
    }
    const sortedRanges = ranges.slice().sort((a, b) => a.startMs - b.startMs);
    const labels = sortedRanges.map((range) => {
      const start = TimeRecordUtil.formatToHHmm(range.startMs);
      const end = TimeRecordUtil.formatToHHmm(range.endMs);
      return `${start} - ${end}`;
    });
    return labels.join(' / ');
  }

  async saveActivityDiary(activityId: string, text: string): Promise<boolean> {
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'saveActivityDiary failed: activityId is empty');
      return false;
    }

    const rdbStoreUtil = RDBStoreUtil.getInstance();
    const now = Date.now();

    try {
      await rdbStoreUtil.beginTransaction();

      const diaryId = `${activityId}_diary`;
      const sql = 'INSERT OR REPLACE INTO activity_diary (id, activity_id, text, created_at, updated_at) VALUES (?, ?, ?, ?, ?)';
      await rdbStoreUtil.executeSql(sql, [diaryId, activityId, text, now, now]);

      await rdbStoreUtil.commit();
      hilog.info(0x0000, TAG, `saveActivityDiary success: activityId=${activityId}, textLength=${text.length}`);
      return true;
    } catch (error) {
      await rdbStoreUtil.rollBack();
      hilog.error(0x0000, TAG, `saveActivityDiary failed: message=${JSON.stringify(error)}`);
      return false;
    }
  }

  async queryActivityDiary(activityId: string): Promise<string> {
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'queryActivityDiary failed: activityId is empty');
      return '';
    }

    const rdbStoreUtil = RDBStoreUtil.getInstance();

    try {
      const text = await rdbStoreUtil.queryActivityDiary(activityId);
      const result = text ?? '';
      hilog.info(0x0000, TAG, `queryActivityDiary success: activityId=${activityId}, textLength=${result.length}`);
      return result;
    } catch (error) {
      hilog.error(0x0000, TAG, `queryActivityDiary failed: message=${JSON.stringify(error)}`);
      return '';
    }
  }

  async replaceActivityCoverImage(
    activityId: string,
    pickerUri: string,
    ctx: FilesDirCarrier
  ): Promise<FlowCardCoverImageResult | null> {
    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'replaceActivityCoverImage failed: activityId is empty');
      return null;
    }
    if (!pickerUri || pickerUri.trim().length === 0) {
      hilog.error(0x0000, TAG, 'replaceActivityCoverImage failed: pickerUri is empty');
      return null;
    }

    let savedRelPath: string | null = null;
    let savedImageUri: string | null = null;
    let savedAbsPath: string | null = null;
    let contentHash: string | null = null;
    let didCopyNewFile = false;

    try {
      hilog.info(0x0000, TAG, `replaceActivityCoverImage start activityId=${activityId} pickerUri=${pickerUri}`);
      const rdbStoreUtil = RDBStoreUtil.getInstance();

      try {
        contentHash = await computeFileHashFromUri(pickerUri);
      } catch (err) {
        hilog.warn(0x0000, TAG, `replaceActivityCoverImage hash failed activityId=${activityId} err=${JSON.stringify(err)}`);
        contentHash = null;
      }

      if (contentHash) {
        const existingPath = await rdbStoreUtil.queryMediaLocalPathByHash(contentHash);
        if (existingPath) {
          const existingUri = relPathToImageUri(ctx, existingPath);
          if (existingUri) {
            savedRelPath = existingPath;
            savedImageUri = existingUri;
            savedAbsPath = resolveStoredPath(ctx, existingPath);
            hilog.info(0x0000, TAG,
              `replaceActivityCoverImage reuse existing file relPath=${existingPath} hash=${contentHash}`);
          }
        }
      }

      if (!savedRelPath) {
        const saved = await savePickerUriToSandboxFiles(ctx, pickerUri, 'diary_images');
        didCopyNewFile = true;
        savedRelPath = saved.relPath;
        savedImageUri = saved.imageUri;
        savedAbsPath = saved.absPath;
        hilog.info(0x0000, TAG,
          `replaceActivityCoverImage saved relPath=${saved.relPath} absPath=${saved.absPath} imageUri=${saved.imageUri}`);
      }

      if (!savedRelPath || !savedImageUri) {
        hilog.error(0x0000, TAG,
          `replaceActivityCoverImage failed: resolved path/uri missing activityId=${activityId}`);
        if (didCopyNewFile && savedRelPath) {
          deleteStoredFileBestEffort(ctx, savedRelPath);
        }
        return null;
      }

      if (!savedAbsPath) {
        savedAbsPath = resolveStoredPath(ctx, savedRelPath);
      }

      const mimeType = guessMimeTypeFromUri(pickerUri);
      let byteSize = 0;
      try {
        if (savedAbsPath) {
          const stat = fs.statSync(savedAbsPath);
          byteSize = Number(stat.size) || 0;
        }
      } catch (_err) {
        byteSize = 0;
      }

      hilog.info(0x0000, TAG,
        `replaceActivityCoverImage file stat mimeType=${mimeType} byteSize=${byteSize} absPath=${savedAbsPath ?? ''}`);

      const result = await rdbStoreUtil.replaceActivityCoverMedia(
        activityId,
        savedRelPath,
        mimeType,
        byteSize,
        0,
        0,
        contentHash
      );
      if (!result.ok) {
        hilog.error(0x0000, TAG,
          `replaceActivityCoverImage failed: replaceActivityCoverMedia not ok activityId=${activityId} relPath=${savedRelPath}`);
        if (didCopyNewFile && savedRelPath) {
          deleteStoredFileBestEffort(ctx, savedRelPath);
        }
        return null;
      }

      const oldPaths = Array.from(new Set(result.oldPaths))
        .filter(path => path && path !== savedRelPath);
      hilog.info(0x0000, TAG,
        `replaceActivityCoverImage db ok oldPathsCount=${oldPaths.length} activityId=${activityId}`);

      for (const oldPath of oldPaths) {
        const remainingCount = await rdbStoreUtil.queryMediaPathReferenceCount(oldPath);
        if (remainingCount === 0) {
          deleteStoredFileBestEffort(ctx, oldPath);
        }
      }

      hilog.info(0x0000, TAG, `replaceActivityCoverImage success activityId=${activityId} relPath=${savedRelPath}`);
      return { relPath: savedRelPath, imageUri: savedImageUri };
    } catch (error) {
      if (didCopyNewFile && savedRelPath) {
        deleteStoredFileBestEffort(ctx, savedRelPath);
      }
      const maybeError = error as ErrorLike;
      const errMessage = maybeError?.message ? maybeError.message : JSON.stringify(error);
      const errCode = typeof maybeError?.code === 'number' ? maybeError.code : -1;
      hilog.error(0x0000, TAG,
        `replaceActivityCoverImage exception activityId=${activityId} pickerUri=${pickerUri} code=${errCode} message=${errMessage}`);
      return null;
    }
  }
}

export const reflectFlowCardService = new ReflectFlowCardServiceImpl();
