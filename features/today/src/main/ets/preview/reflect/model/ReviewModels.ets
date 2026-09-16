/**
 * Blueprint data contracts for the "Review" feature. These interfaces describe
 * the structures returned by the yet-to-be implemented ReviewService. They
 * encapsulate view-ready aggregations for month, week, and day scopes while
 * reusing shared primitives such as TimeRecord and TagItem.
 */
import type { TimeRecordWithContext, DayAggregation, TagPaletteMap } from 'base';

/**
 * Aggregated snapshot backing the review page. Encapsulates the current focus
 * date state as well as month/week/day overviews for UI modules.
 */
export interface ReviewSnapshot {
  focusDateMs: number;
  focusDateLabel: string;
  focusState: FocusDateState;
  monthOverview: MonthOverview;
  weekOverview: WeekOverview;
  dailyOverview: DailyOverview;
  totals: ReviewTotals;
  mixColor: ColorMixResult;
  interaction?: ReviewInteractionMetadata;
}

/**
 * Exposes navigation affordances associated with the focus date displayed in
 * the top date navigator. Mirrors RV-1 by disabling forward navigation when
 * reaching today or empty datasets.
 */
export interface FocusDateState {
  focusDateMs: number;
  isToday: boolean;
  prevDateEnabled: boolean;
  nextDateEnabled: boolean;
  calendarSheetConfig: CalendarSheetConfig;
}

/**
 * Configuration payload for the calendar sheet picker. Allows the UI layer to
 * render month boundaries and optionally highlight the first selectable day.
 */
export interface CalendarSheetConfig {
  minSelectableMs: number | null;
  maxSelectableMs: number;
  initialFocusedMonthMs: number;
}

/**
 * Consolidated metrics used to present key totals across the review modules.
 */
export interface ReviewTotals {
  totalMonthDurationMs: number;
  totalWeekDurationMs: number;
  totalDayDurationMs: number;
  dominantTagId?: string | null;
}

/**
 * Month-level overview feeding the calendar grid.
 */
export interface MonthOverview {
  monthStartMs: number;
  monthEndMsExclusive: number;
  calendarCells: CalendarCell[];
  activeWeeks: number;
  summaryStats: MonthSummaryStats;
}

export interface MonthSummaryStats {
  activeDays: number;
  emptyDays: number;
  totalDurationMs: number;
  averageDailyDurationMs: number;
}

/**
 * Single cell within the review calendar grid.
 */
export interface CalendarCell {
  dateMs: number;
  inCurrentMonth: boolean;
  isToday: boolean;
  isSelected: boolean;
  hasRecord: boolean;
  totalDurationMs: number;
  tagSlices: TagSlice[];
  mixColor?: ColorMixResult;
}

/**
 * Weighted contribution for a given tag inside calendar pies, weekly bars, and
 * daily swiper cards.
 */
export interface TagSlice {
  tagId: string | null;
  tagName: string;
  tagColor: string;
  durationMs: number;
  percent: number;
  sortOrder: number;
}

/**
 * Week-level overview powering the weekly stacked bar chart.
 */
export interface WeekOverview {
  weekStartMs: number;
  weekEndMsExclusive: number;
  dayBars: WeekDayBar[];
  totalWeekDurationMs: number;
  maxDailyDurationMs: number;
}

export interface WeekDayBar {
  dateMs: number;
  weekdayLabel: string;
  totalDurationMs: number;
  mixColor?: ColorMixResult;
  tagSlices: TagSlice[];
  interactionHint?: string;
}

/**
 * Daily-level overview exposed to the swiper module.
 */
export interface DailyOverview {
  dateMs: number;
  dayLabel: string;
  backgroundColor: ColorMixResult;
  tagReports: DailyTagReport[];
  totalDayDurationMs: number;
  unassignedDurationMs: number;
  notes?: string | null;
  initialSwiperIndex?: number;
}

export interface DailyTagReport {
  tagId: string | null;
  tagName: string;
  tagColor: string;
  totalDurationMs: number;
  percentOfDay: number;
  activities: ActivitySlice[];
}

export interface ActivitySlice {
  recordId: string;
  activityId: string;
  activityName: string;
  startTimeMs: number;
  endTimeMs: number;
  durationMs: number;
  isSplitSegment: boolean;
  sourceRecordId?: string;
}

/**
 * Common representation for blended colors derived from tag contributions. The
 * hex string is used by UI components, while the raw RGB values allow charts to
 * interpolate gradients if required.
 */
export interface ColorMixResult {
  hex: string;
  rgb: RGBColorComponents;
  dominantTagId?: string | null;
}

export interface RGBColorComponents {
  r: number;
  g: number;
  b: number;
}

/**
 * Optional interaction metadata returned alongside snapshots so the view layer
 * can orchestrate scroll or focus behavior after cross-module interactions.
 */
export interface ReviewInteractionMetadata {
  scrollAnchors?: ScrollAnchors;
  analyticsTag?: string;
}

export interface ScrollAnchors {
  calendarModuleAnchor?: string;
  weeklyModuleAnchor?: string;
  dailyModuleAnchor?: string;
}

/**
 * Extension contracts describing data needed from the persistence layer. The
 * actual implementations will live in RDBStoreUtil but are documented here to
 * make ReviewService dependencies explicit.
 */
export interface ReviewAggregationPrimitives {
  recordsWithContext: TimeRecordWithContext[];
  dayAggregations: DayAggregation[];
  tagPalette: TagPaletteMap;
}
