/**
 * Service for fetching historical day data including activities and label summaries.
 * Used by the MiniCalendar expanded day detail view.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RDBStoreUtil, TimeRecordUtil, TimeRecordWithContext, LabelSummaryModel } from 'base';

const TAG: string = 'HistoricalDayService';

/**
 * Represents a single activity record for display in the day detail view.
 */
export interface HistoricalActivityData {
  recordId: string;
  activityId: string;
  activityName: string;
  tagId: string | null;
  tagName: string | null;
  tagColorHex: string | null;
  startTimeMs: number;
  endTimeMs: number | null;
  totalDurationMinutes: number;
}

/**
 * Aggregated data for a historical day snapshot.
 */
export interface HistoricalDaySnapshot {
  dateMs: number;
  dateString: string;
  labelSummaries: LabelSummaryModel[];
  activities: HistoricalActivityData[];
  totalDurationMinutes: number;
}

/**
 * Interface for aggregating label data internally.
 */
interface LabelAggregateData {
  totalMilliseconds: number;
  color: string;
}

/**
 * Interface for aggregating activity data by activityId.
 */
interface ActivityAggregateData {
  activityId: string;
  activityName: string;
  tagId: string | null;
  tagName: string | null;
  tagColorHex: string | null;
  totalMilliseconds: number;
  latestStartTimeMs: number;  // For sorting - use the latest start time
}

/**
 * Service class for fetching historical day data.
 */
class HistoricalDayServiceImpl {
  private static instance: HistoricalDayServiceImpl;

  private constructor() {}

  static getInstance(): HistoricalDayServiceImpl {
    if (!HistoricalDayServiceImpl.instance) {
      HistoricalDayServiceImpl.instance = new HistoricalDayServiceImpl();
    }
    return HistoricalDayServiceImpl.instance;
  }

  /**
   * Gets the complete snapshot for a specific day.
   * @param dateMs The target date in milliseconds
   * @returns Promise<HistoricalDaySnapshot> Complete day data including label summaries and activities
   */
  async getDaySnapshot(dateMs: number): Promise<HistoricalDaySnapshot> {
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const dayStart = TimeRecordUtil.getDayStart(dateMs);
      const dayEnd = dayStart + 24 * 60 * 60 * 1000 - 1;

      hilog.debug(0x0000, TAG, `Getting day snapshot for date: ${dayStart} to ${dayEnd}`);

      // Get all time records for this day with activity and tag context
      const recordsWithContext = await rdbStoreUtil.queryTimeRecordsWithActivityAndTag(dayStart, dayEnd);

      if (!recordsWithContext || recordsWithContext.length === 0) {
        hilog.debug(0x0000, TAG, `No records found for date: ${dayStart}`);
        return this.buildEmptySnapshot(dayStart);
      }

      // Build label summaries
      const labelSummaries = this.buildLabelSummaries(recordsWithContext);

      // Build activity list
      const activities = this.buildActivityList(recordsWithContext);

      // Calculate total duration
      const totalDurationMinutes = activities.reduce(
        (sum: number, activity: HistoricalActivityData): number => sum + activity.totalDurationMinutes, 0
      );

      // Format date string
      const date = new Date(dayStart);
      const dateString = `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;

      hilog.debug(0x0000, TAG, `Built snapshot with ${labelSummaries.length} labels, ${activities.length} activities`);

      return {
        dateMs: dayStart,
        dateString,
        labelSummaries,
        activities,
        totalDurationMinutes
      };
    } catch (error) {
      hilog.error(0x0000, TAG, `Error getting day snapshot: ${JSON.stringify(error)}`);
      return this.buildEmptySnapshot(dateMs);
    }
  }

  /**
   * Builds label summaries from time records.
   */
  private buildLabelSummaries(records: TimeRecordWithContext[]): LabelSummaryModel[] {
    const labelMap = new Map<string, LabelAggregateData>();

    records.forEach((record: TimeRecordWithContext) => {
      const labelName = record.tagName || '无标签';
      const labelColor = record.tagColorHex || '#808080';

      // Skip records that are still recording
      if (!record.endTimeMs && !record.durationMs) {
        return;
      }

      // Calculate duration
      const duration = record.durationMs
        ? record.durationMs
        : (record.endTimeMs ? (record.endTimeMs - record.startTimeMs) : 0);

      if (duration > 0) {
        const existing = labelMap.get(labelName);
        if (existing) {
          existing.totalMilliseconds += duration;
        } else {
          const newData: LabelAggregateData = {
            totalMilliseconds: duration,
            color: labelColor
          };
          labelMap.set(labelName, newData);
        }
      }
    });

    // Convert to LabelSummaryModel array and sort by duration
    const labelSummaries: LabelSummaryModel[] = Array.from(labelMap.entries())
      .map((entry: [string, LabelAggregateData]): LabelSummaryModel => {
        const labelName = entry[0];
        const data = entry[1];
        const summaryItem: LabelSummaryModel = {
          labelName: labelName,
          totalMinutes: Math.round(data.totalMilliseconds / 60000),
          labelColor: data.color
        };
        return summaryItem;
      })
      .filter((summary: LabelSummaryModel): boolean => summary.totalMinutes > 0)
      .sort((a: LabelSummaryModel, b: LabelSummaryModel): number => b.totalMinutes - a.totalMinutes);

    return labelSummaries;
  }

  /**
   * Builds activity list from time records, aggregating by activityId.
   * Multiple time records for the same activity are combined into one entry.
   */
  private buildActivityList(records: TimeRecordWithContext[]): HistoricalActivityData[] {
    const activityMap = new Map<string, ActivityAggregateData>();

    records.forEach((record: TimeRecordWithContext) => {
      // Only include completed records
      if (record.endTimeMs === null && record.durationMs === null) {
        return;
      }

      const duration = record.durationMs
        ? record.durationMs
        : (record.endTimeMs ? (record.endTimeMs - record.startTimeMs) : 0);

      if (duration <= 0) {
        return;
      }

      const existing = activityMap.get(record.activityId);
      if (existing) {
        // Aggregate duration
        existing.totalMilliseconds += duration;
        // Keep the latest start time for sorting
        if (record.startTimeMs > existing.latestStartTimeMs) {
          existing.latestStartTimeMs = record.startTimeMs;
        }
      } else {
        // Create new aggregate entry
        const newData: ActivityAggregateData = {
          activityId: record.activityId,
          activityName: record.activityName,
          tagId: record.tagId,
          tagName: record.tagName,
          tagColorHex: record.tagColorHex,
          totalMilliseconds: duration,
          latestStartTimeMs: record.startTimeMs
        };
        activityMap.set(record.activityId, newData);
      }
    });

    // Convert to HistoricalActivityData array and sort by latest start time (descending)
    return Array.from(activityMap.values())
      .map((data: ActivityAggregateData): HistoricalActivityData => {
        return {
          recordId: data.activityId,  // Use activityId as recordId since we're aggregating
          activityId: data.activityId,
          activityName: data.activityName,
          tagId: data.tagId,
          tagName: data.tagName,
          tagColorHex: data.tagColorHex,
          startTimeMs: data.latestStartTimeMs,
          endTimeMs: null,  // Not meaningful for aggregated data
          totalDurationMinutes: Math.round(data.totalMilliseconds / 60000)
        };
      })
      .filter((activity: HistoricalActivityData): boolean => activity.totalDurationMinutes > 0)
      .sort((a: HistoricalActivityData, b: HistoricalActivityData): number => b.totalDurationMinutes - a.totalDurationMinutes);
  }

  /**
   * Builds an empty snapshot for days with no data.
   */
  private buildEmptySnapshot(dateMs: number): HistoricalDaySnapshot {
    const dayStart = TimeRecordUtil.getDayStart(dateMs);
    const date = new Date(dayStart);
    const dateString = `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;

    return {
      dateMs: dayStart,
      dateString,
      labelSummaries: [],
      activities: [],
      totalDurationMinutes: 0
    };
  }
}

export const historicalDayService = HistoricalDayServiceImpl.getInstance();
