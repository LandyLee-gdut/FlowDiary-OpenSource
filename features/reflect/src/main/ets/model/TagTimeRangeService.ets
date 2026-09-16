import { hilog } from '@kit.PerformanceAnalysisKit';
import { RDBStoreUtil, TimeRecordUtil, TimeRecordWithContext, AppColors } from 'base';

const TAG = 'TagTimeRangeService';
const DAY_MS: number = 24 * 60 * 60 * 1000;
const UNTAGGED_KEY = '__untagged__';

export type TagTimeDimension = 'day' | 'week' | 'month' | 'year';

export interface TagTimeSummaryRequest {
  dimension: TagTimeDimension;
  focusDateMs?: number;
  tagIds?: string[];
  /**
   * Optional limit to cap how many tags are returned.
   * Defaults to 8 to keep the chart readable.
   */
  limit?: number;
}

export interface TagTimeSummaryEntry {
  tagId: string | null;
  tagName: string;
  color: string;
  lightColor: string;
  totalMinutes: number;
}

export interface TagTimeSummaryResponse {
  dimension: TagTimeDimension;
  startMs: number;
  endMs: number;
  entries: TagTimeSummaryEntry[];
}

export interface TagTimeRange {
  startMs: number;
  endMs: number;
}

interface TagTimeMeta {
  tagId: string | null;
  tagName: string;
  color: string;
  lightColor: string;
}

interface TagTimeAccumulator {
  meta: TagTimeMeta;
  totalDurationMs: number;
}

class TagTimeRangeServiceImpl {
  private static instance: TagTimeRangeServiceImpl;

  static getInstance(): TagTimeRangeServiceImpl {
    if (!TagTimeRangeServiceImpl.instance) {
      TagTimeRangeServiceImpl.instance = new TagTimeRangeServiceImpl();
    }
    return TagTimeRangeServiceImpl.instance;
  }

  async getTagTimeSummary(request: TagTimeSummaryRequest): Promise<TagTimeSummaryResponse> {
    const focusDateMs = request.focusDateMs ?? Date.now();
    const range = resolveTagTimeRange(request.dimension, focusDateMs);
    const limit = request.limit ?? 8;

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const records = await rdbStoreUtil.queryTimeRecordsWithActivityAndTag(range.startMs, range.endMs);
      const filtered = this.filterRecords(records, request.tagIds);
      const accumulatorMap = this.buildAccumulatorMap(filtered, range);

      let entries: TagTimeSummaryEntry[] = Array.from(accumulatorMap.values())
        .map((accumulator: TagTimeAccumulator): TagTimeSummaryEntry => ({
          tagId: accumulator.meta.tagId,
          tagName: accumulator.meta.tagName,
          color: accumulator.meta.color,
          lightColor: accumulator.meta.lightColor,
          totalMinutes: Math.round(accumulator.totalDurationMs / 60000)
        }))
        .filter((entry: TagTimeSummaryEntry): boolean => entry.totalMinutes > 0)
        .sort((a: TagTimeSummaryEntry, b: TagTimeSummaryEntry): number => b.totalMinutes - a.totalMinutes);

      if (entries.length > limit) {
        entries = entries.slice(0, limit);
      }

      return {
        dimension: request.dimension,
        startMs: range.startMs,
        endMs: range.endMs,
        entries
      };
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to build tag time summary: ${JSON.stringify(error)}`);
      return {
        dimension: request.dimension,
        startMs: range.startMs,
        endMs: range.endMs,
        entries: []
      };
    }
  }

  buildTagTimeSummaryFromRecords(request: TagTimeSummaryRequest, records: TimeRecordWithContext[]): TagTimeSummaryResponse {
    const focusDateMs = request.focusDateMs ?? Date.now();
    const range = resolveTagTimeRange(request.dimension, focusDateMs);
    const limit = request.limit ?? 8;
    try {
      const filtered = this.filterRecords(records, request.tagIds);
      const accumulatorMap = this.buildAccumulatorMap(filtered, range);

      let entries: TagTimeSummaryEntry[] = Array.from(accumulatorMap.values())
        .map((accumulator: TagTimeAccumulator): TagTimeSummaryEntry => ({
          tagId: accumulator.meta.tagId,
          tagName: accumulator.meta.tagName,
          color: accumulator.meta.color,
          lightColor: accumulator.meta.lightColor,
          totalMinutes: Math.round(accumulator.totalDurationMs / 60000)
        }))
        .filter((entry: TagTimeSummaryEntry): boolean => entry.totalMinutes > 0)
        .sort((a: TagTimeSummaryEntry, b: TagTimeSummaryEntry): number => b.totalMinutes - a.totalMinutes);

      if (entries.length > limit) {
        entries = entries.slice(0, limit);
      }

      return {
        dimension: request.dimension,
        startMs: range.startMs,
        endMs: range.endMs,
        entries
      };
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to build tag time summary from records: ${JSON.stringify(error)}`);
      return {
        dimension: request.dimension,
        startMs: range.startMs,
        endMs: range.endMs,
        entries: []
      };
    }
  }

  private filterRecords(records: TimeRecordWithContext[], tagIds?: string[]): TimeRecordWithContext[] {
    if (!tagIds || tagIds.length === 0) {
      return records;
    }
    const tagIdSet = new Set(tagIds);
    return records.filter((record: TimeRecordWithContext) => record.tagId !== null && tagIdSet.has(record.tagId));
  }

  private buildAccumulatorMap(records: TimeRecordWithContext[], range: TagTimeRange): Map<string, TagTimeAccumulator> {
    const map: Map<string, TagTimeAccumulator> = new Map();

    for (const record of records) {
      if (!record.endTimeMs && !record.durationMs) {
        continue;
      }

      const recordEnd = record.endTimeMs ?? (record.durationMs ? record.startTimeMs + record.durationMs : record.startTimeMs);
      const clampedStart = Math.max(record.startTimeMs, range.startMs);
      const clampedEnd = Math.min(recordEnd, range.endMs);
      const durationMs = Math.max(0, clampedEnd - clampedStart);
      if (durationMs <= 0) {
        continue;
      }

      const tagKey = record.tagId ?? UNTAGGED_KEY;
      const accumulator = this.getOrCreateAccumulator(map, tagKey, record);
      accumulator.totalDurationMs += durationMs;
    }

    return map;
  }

  private getOrCreateAccumulator(
    map: Map<string, TagTimeAccumulator>,
    tagKey: string,
    record: TimeRecordWithContext
  ): TagTimeAccumulator {
    const existing = map.get(tagKey);
    if (existing) {
      return existing;
    }

    const meta: TagTimeMeta = {
      tagId: record.tagId,
      tagName: record.tagName ?? '无标签',
      color: record.tagColorHex ?? AppColors.NEUTRAL_700,
      lightColor: record.tagLightColorHex ?? AppColors.NEUTRAL_200
    };
    const accumulator: TagTimeAccumulator = {
      meta,
      totalDurationMs: 0
    };

    map.set(tagKey, accumulator);
    return accumulator;
  }

}

function getWeekStart(timestamp: number): number {
  const dayStart = TimeRecordUtil.getDayStart(timestamp);
  const date = new Date(dayStart);
  const dayOfWeek = date.getDay();
  const offsetToMonday = (dayOfWeek + 6) % 7;
  date.setHours(0, 0, 0, 0);
  date.setDate(date.getDate() - offsetToMonday);
  return date.getTime();
}

function buildDayRange(focusDayStart: number): TagTimeRange {
  return {
    startMs: focusDayStart,
    endMs: focusDayStart + DAY_MS - 1
  };
}

function buildWeekRange(focusDayStart: number): TagTimeRange {
  const weekStart = getWeekStart(focusDayStart);
  return {
    startMs: weekStart,
    endMs: weekStart + DAY_MS * 7 - 1
  };
}

function buildMonthRange(focusDayStart: number): TagTimeRange {
  const focusDate = new Date(focusDayStart);
  const startMs = new Date(focusDate.getFullYear(), focusDate.getMonth(), 1).getTime();
  const nextMonthStart = new Date(focusDate.getFullYear(), focusDate.getMonth() + 1, 1).getTime();
  return {
    startMs,
    endMs: nextMonthStart - 1
  };
}

function buildYearRange(focusDayStart: number): TagTimeRange {
  const focusDate = new Date(focusDayStart);
  const startMs = new Date(focusDate.getFullYear(), 0, 1).getTime();
  const nextYearStart = new Date(focusDate.getFullYear() + 1, 0, 1).getTime();
  return {
    startMs,
    endMs: nextYearStart - 1
  };
}

export function resolveTagTimeRange(dimension: TagTimeDimension, focusDateMs: number): TagTimeRange {
  const focusDayStart = TimeRecordUtil.getDayStart(focusDateMs);
  switch (dimension) {
    case 'day':
      return buildDayRange(focusDayStart);
    case 'week':
      return buildWeekRange(focusDayStart);
    case 'month':
      return buildMonthRange(focusDayStart);
    case 'year':
    default:
      return buildYearRange(focusDayStart);
  }
}

export const tagTimeRangeService = TagTimeRangeServiceImpl.getInstance();
