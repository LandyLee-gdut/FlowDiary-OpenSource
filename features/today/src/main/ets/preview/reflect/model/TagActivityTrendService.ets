import { hilog } from '@kit.PerformanceAnalysisKit';
import { RDBStoreUtil, TimeRecordUtil, TimeRecordWithContext } from 'base';
import { AppColors } from 'base';

const TAG = 'TagActivityTrendService';
const DAY_MS: number = 24 * 60 * 60 * 1000;
const UNTAGGED_KEY = '__untagged__';

/**
 * Service helper feeding the upcoming Reflect line chart.
 * Example usage:
 *   const trends = await tagActivityTrendService.getActivityTrends({
 *     dimension: 'week',
 *     focusDateMs: Date.now(),
 *     tagIds: ['tag-1', 'tag-2'] // optional
 *   });
 * Use `series.color` / `series.lightColor` for line styling and
 * `series.points` as the y-values per day bucket.
 */
export type TagTrendDimension = 'week' | 'month' | 'year';

export interface TagTrendRequest {
  dimension: TagTrendDimension;
  focusDateMs?: number;
  tagIds?: string[];
}

export interface TagTrendPoint {
  dateMs: number;
  activityCount: number;
}

export interface TagTrendSeries {
  tagId: string | null;
  tagName: string;
  color: string;
  lightColor: string;
  points: TagTrendPoint[];
}

export interface TagTrendResponse {
  dimension: TagTrendDimension;
  startMs: number;
  endMs: number;
  series: TagTrendSeries[];
}

interface TagSeriesMeta {
  tagId: string | null;
  tagName: string;
  color: string;
  lightColor: string;
}

interface TagSeriesAccumulator {
  meta: TagSeriesMeta;
  dailyActivities: Map<number, Set<string>>;
}

type BucketGranularity = 'day' | 'month';

export interface TagTrendRange {
  startMs: number;
  endMs: number;
  bucketType: BucketGranularity;
  bucketStarts: number[];
}

class TagActivityTrendService {
  private static instance: TagActivityTrendService;

  static getInstance(): TagActivityTrendService {
    if (!TagActivityTrendService.instance) {
      TagActivityTrendService.instance = new TagActivityTrendService();
    }
    return TagActivityTrendService.instance;
  }

  /**
   * Returns per-tag activity counts per day for the requested dimension.
   * The count is based on distinct activities that have at least one completed
   * time record touching the day (multiple records for the same activity are
   * counted once per day).
   */
  async getActivityTrends(request: TagTrendRequest): Promise<TagTrendResponse> {
    const focusDateMs = request.focusDateMs ?? Date.now();
    const range = resolveTagTrendRange(request.dimension, focusDateMs);
    const rdbStoreUtil = RDBStoreUtil.getInstance();

    try {
      const records = await rdbStoreUtil.queryTimeRecordsWithActivityAndTag(range.startMs, range.endMs);
      const filtered = this.filterByTagIds(records, request.tagIds);
      const series = await this.buildSeries(filtered, range, request.tagIds);

      return {
        dimension: request.dimension,
        startMs: range.startMs,
        endMs: range.endMs,
        series
      };
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to build tag activity trends: ${JSON.stringify(error)}`);
      return {
        dimension: request.dimension,
        startMs: range.startMs,
        endMs: range.endMs,
        series: []
      };
    }
  }

  async buildActivityTrendsFromRecords(request: TagTrendRequest, records: TimeRecordWithContext[]): Promise<TagTrendResponse> {
    const focusDateMs = request.focusDateMs ?? Date.now();
    const range = resolveTagTrendRange(request.dimension, focusDateMs);
    try {
      const filtered = this.filterByTagIds(records, request.tagIds);
      const series = await this.buildSeries(filtered, range, request.tagIds);
      return {
        dimension: request.dimension,
        startMs: range.startMs,
        endMs: range.endMs,
        series
      };
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to build tag activity trends from records: ${JSON.stringify(error)}`);
      return {
        dimension: request.dimension,
        startMs: range.startMs,
        endMs: range.endMs,
        series: []
      };
    }
  }

  private async buildSeries(
    records: TimeRecordWithContext[],
    range: TagTrendRange,
    requestedTagIds?: string[]
  ): Promise<TagTrendSeries[]> {
    const seriesMap: Map<string, TagSeriesAccumulator> = new Map();

    // Seed requested tags so the chart can render empty lines when no data exists.
    await this.seedRequestedTags(seriesMap, requestedTagIds);

    for (const record of records) {
      // Skip active/open-ended records to avoid over-counting.
      if (!record.endTimeMs && !record.durationMs) {
        continue;
      }

      const recordEnd = record.endTimeMs ?? (record.durationMs ? record.startTimeMs + record.durationMs : record.startTimeMs);
      const clampedStart = Math.max(record.startTimeMs, range.startMs);
      const clampedEnd = Math.min(recordEnd, range.endMs);
      if (clampedEnd < range.startMs || clampedEnd < clampedStart) {
        continue;
      }

      const tagKey = record.tagId ?? UNTAGGED_KEY;
      const accumulator = this.getOrCreateAccumulator(seriesMap, tagKey, record);

      const segments = TimeRecordUtil.splitIntoDaySegments(clampedStart, clampedEnd);
      for (const segment of segments) {
        const dayStart = TimeRecordUtil.getDayStart(segment.start);
        if (dayStart < range.startMs || dayStart > range.endMs) {
          continue;
        }
        const activitiesForDay = accumulator.dailyActivities.get(dayStart) ?? new Set<string>();
        activitiesForDay.add(record.activityId);
        accumulator.dailyActivities.set(dayStart, activitiesForDay);
      }
    }

    const series: TagTrendSeries[] = [];
    seriesMap.forEach((accumulator: TagSeriesAccumulator) => {
      const points: TagTrendPoint[] = this.buildPointsForRange(range, accumulator.dailyActivities);

      series.push({
        tagId: accumulator.meta.tagId,
        tagName: accumulator.meta.tagName,
        color: accumulator.meta.color,
        lightColor: accumulator.meta.lightColor,
        points
      });
    });

    return series;
  }

  private buildPointsForRange(
    range: TagTrendRange,
    dailyActivities: Map<number, Set<string>>
  ): TagTrendPoint[] {
    if (range.bucketType === 'month') {
      return this.buildMonthlyPoints(range.bucketStarts, dailyActivities);
    }
    return this.buildDailyPoints(range.bucketStarts, dailyActivities);
  }

  private buildDailyPoints(
    bucketStarts: number[],
    dailyActivities: Map<number, Set<string>>
  ): TagTrendPoint[] {
    return bucketStarts.map((dayStart: number): TagTrendPoint => {
      const activities = dailyActivities.get(dayStart);
      return {
        dateMs: dayStart,
        activityCount: activities ? activities.size : 0
      };
    });
  }

  private buildMonthlyPoints(
    bucketStarts: number[],
    dailyActivities: Map<number, Set<string>>
  ): TagTrendPoint[] {
    const points: TagTrendPoint[] = [];
    for (let index = 0; index < bucketStarts.length; index++) {
      const monthStart = bucketStarts[index];
      const nextMonthStart = index < bucketStarts.length - 1
        ? bucketStarts[index + 1]
        : this.getNextMonthStart(monthStart);
      let monthlyTotal = 0;
      for (let dayMs = monthStart; dayMs < nextMonthStart; dayMs += DAY_MS) {
        const activities = dailyActivities.get(dayMs);
        if (activities) {
          monthlyTotal += activities.size;
        }
      }
      points.push({
        dateMs: monthStart,
        activityCount: monthlyTotal
      });
    }
    return points;
  }

  private getNextMonthStart(monthStart: number): number {
    const date = new Date(monthStart);
    return new Date(date.getFullYear(), date.getMonth() + 1, 1).getTime();
  }

  private async seedRequestedTags(
    seriesMap: Map<string, TagSeriesAccumulator>,
    requestedTagIds?: string[]
  ): Promise<void> {
    if (!requestedTagIds || requestedTagIds.length === 0) {
      return;
    }

    const uniqueIds = Array.from(new Set(requestedTagIds));
    try {
      const allTags = await RDBStoreUtil.getInstance().queryAllTags();
      uniqueIds.forEach((tagId: string) => {
        if (seriesMap.has(tagId)) {
          return;
        }
        const tagMeta = allTags.find(tag => tag.id === tagId);
        const meta: TagSeriesMeta = tagMeta
          ? {
              tagId: tagMeta.id,
              tagName: tagMeta.name,
              color: tagMeta.color,
              lightColor: tagMeta.lightColor
            }
          : {
              tagId,
              tagName: 'Unknown Tag',
              color: AppColors.DATA_VIZ_1,
              lightColor: AppColors.DATA_VIZ_1_LIGHT
            };

        seriesMap.set(tagId, {
          meta,
          dailyActivities: new Map()
        });
      });
    } catch (error) {
      hilog.error(0x0000, TAG, `Unable to seed requested tags: ${JSON.stringify(error)}`);
    }
  }

  private getOrCreateAccumulator(
    seriesMap: Map<string, TagSeriesAccumulator>,
    tagKey: string,
    record: TimeRecordWithContext
  ): TagSeriesAccumulator {
    const existing = seriesMap.get(tagKey);
    if (existing) {
      return existing;
    }

    const meta: TagSeriesMeta = {
      tagId: record.tagId,
      tagName: record.tagName ?? 'Untagged',
      color: record.tagColorHex ?? AppColors.NEUTRAL_700,
      lightColor: record.tagLightColorHex ?? AppColors.NEUTRAL_200
    };

    const accumulator: TagSeriesAccumulator = {
      meta,
      dailyActivities: new Map()
    };
    seriesMap.set(tagKey, accumulator);
    return accumulator;
  }

  private filterByTagIds(records: TimeRecordWithContext[], tagIds?: string[]): TimeRecordWithContext[] {
    if (!tagIds || tagIds.length === 0) {
      return records;
    }
    const tagIdSet = new Set(tagIds);
    return records.filter((record: TimeRecordWithContext) => record.tagId !== null && tagIdSet.has(record.tagId));
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

function buildWeekRange(focusDayStart: number): TagTrendRange {
  const startMs = getWeekStart(focusDayStart);
  const bucketStarts: number[] = [];
  for (let offset = 0; offset < 7; offset++) {
    bucketStarts.push(startMs + offset * DAY_MS);
  }
  return {
    startMs,
    endMs: startMs + DAY_MS * 7 - 1,
    bucketType: 'day',
    bucketStarts
  };
}

function buildMonthRange(focusDayStart: number): TagTrendRange {
  const focusDate = new Date(focusDayStart);
  const startMs = new Date(focusDate.getFullYear(), focusDate.getMonth(), 1).getTime();
  const nextMonthStart = new Date(focusDate.getFullYear(), focusDate.getMonth() + 1, 1).getTime();
  const bucketStarts: number[] = [];
  for (let dayMs = startMs; dayMs < nextMonthStart; dayMs += DAY_MS) {
    bucketStarts.push(dayMs);
  }
  return {
    startMs,
    endMs: nextMonthStart - 1,
    bucketType: 'day',
    bucketStarts
  };
}

function buildYearRange(focusDayStart: number): TagTrendRange {
  const focusDate = new Date(focusDayStart);
  const startMs = new Date(focusDate.getFullYear(), 0, 1).getTime();
  const nextYearStart = new Date(focusDate.getFullYear() + 1, 0, 1).getTime();
  const bucketStarts: number[] = [];
  for (let month = 0; month < 12; month++) {
    bucketStarts.push(new Date(focusDate.getFullYear(), month, 1).getTime());
  }
  return {
    startMs,
    endMs: nextYearStart - 1,
    bucketType: 'month',
    bucketStarts
  };
}

export function resolveTagTrendRange(dimension: TagTrendDimension, focusDateMs: number): TagTrendRange {
  const focusDayStart = TimeRecordUtil.getDayStart(focusDateMs);
  switch (dimension) {
    case 'week':
      return buildWeekRange(focusDayStart);
    case 'month':
      return buildMonthRange(focusDayStart);
    case 'year':
    default:
      return buildYearRange(focusDayStart);
  }
}

export const tagActivityTrendService = TagActivityTrendService.getInstance();
