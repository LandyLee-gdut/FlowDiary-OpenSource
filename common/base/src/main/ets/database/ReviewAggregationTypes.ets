/**
 * Shared data contracts for review-focused database aggregations.
 * These interfaces describe lightweight projections returned by RDBStoreUtil
 * when preparing review insights across month/week/day scopes.
 */
export interface TimeRecordWithContext {
  recordId: string;
  activityId: string;
  activityName: string;
  startTimeMs: number;
  endTimeMs: number | null;
  durationMs?: number | null;
  tagId: string | null;
  tagName: string | null;
  tagColorHex: string | null;
  tagLightColorHex: string | null;
}

/**
 * Aggregated time usage for a single calendar date grouped by tag.
 */
export interface DayAggregation {
  dateMs: number;
  tagId: string | null;
  totalDurationMs: number;
  activityCount: number;
}

/**
 * Palette lookup information for tags referenced in review analytics.
 */
export interface TagPaletteEntry {
  tagId: string;
  tagName: string;
  colorHex: string;
  lightColorHex: string;
}

export type TagPaletteMap = Record<string, TagPaletteEntry>;

export interface FocusDateBoundsRow {
  earliestRecordMs: number | null;
  latestRecordMs: number;
}
