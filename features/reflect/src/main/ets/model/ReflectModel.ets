import { hilog } from '@kit.PerformanceAnalysisKit';
import { RDBStoreUtil, StorageKeys, TimeRecordUtil } from 'base';
import type { LabelSummaryModel, TimeRecordWithContext } from 'base';
import type { DayReviewPanelData } from './DayReviewModel';
import { buildDayReviewPanelData } from './DayReviewModel';
import type { TagTimeDistributionPanelData } from './TagTimeDistributionModel';
import { buildTagTimeDistributionPanelData, resolveTagTimeDistributionRange } from './TagTimeDistributionModel';
import type { FlowTimelineItem } from './FlowEventModel';
import { flowTimelineService } from './FlowTimelineService';
import type { TagTrendDimension, TagTrendRequest, TagTrendResponse } from './TagActivityTrendService';
import { tagActivityTrendService, resolveTagTrendRange } from './TagActivityTrendService';
import type { TagTimeDimension, TagTimeSummaryRequest, TagTimeSummaryResponse } from './TagTimeRangeService';
import { tagTimeRangeService, resolveTagTimeRange } from './TagTimeRangeService';
import { reflectService } from './ReflectService';

const TAG: string = 'ReflectModel';
const DAY_MS: number = 24 * 60 * 60 * 1000;
const MIN_SEGMENT_SECONDS: number = 1;

export interface ReflectTimelineSegment {
  id: string;
  startMs: number;
  endMs: number;
  durationMs: number;
  weight: number;
  color: ResourceColor;
  label: string;
  activityTitle: string;
  tagName: string;
  isGap: boolean;
}

export interface CalendarDaySummary {
  dayStartMs: number;
  totalDurationMs: number;
}

interface ClampedSegmentRange {
  start: number;
  end: number;
}

function clampToDay(startMs: number, endMs: number, dayStartMs: number): ClampedSegmentRange | null {
  const dayEndMs = dayStartMs + DAY_MS;
  const clampedStart = Math.max(startMs, dayStartMs);
  const clampedEnd = Math.min(endMs, dayEndMs);
  if (clampedEnd <= clampedStart) {
    return null;
  }
  return { start: clampedStart, end: clampedEnd };
}

@Observed
export class ReflectModel {
  public focusDateMs: number = TimeRecordUtil.getDayStart(Date.now());

  public dayReviewData: DayReviewPanelData | null = null;
  public dayDistributionData: TagTimeDistributionPanelData | null = null;
  public dayTimelineSegments: ReflectTimelineSegment[] = [];
  public dayTimelineDateLabel: string = '';
  public dayTimelineHasRecords: boolean = false;
  public dayTimelineLoading: boolean = false;
  public dayTimelineError: boolean = false;
  public dayDistributionLoading: boolean = false;
  public dayDistributionError: boolean = false;

  public streamTimelineItems: FlowTimelineItem[] = [];
  public streamTimelineLoading: boolean = false;
  public streamTimelineError: boolean = false;

  public tagTrendWeek: TagTrendResponse | null = null;
  public tagTrendMonth: TagTrendResponse | null = null;
  public tagTrendYear: TagTrendResponse | null = null;
  public tagTrendLoadingWeek: boolean = false;
  public tagTrendLoadingMonth: boolean = false;
  public tagTrendLoadingYear: boolean = false;
  public tagTrendErrorWeek: boolean = false;
  public tagTrendErrorMonth: boolean = false;
  public tagTrendErrorYear: boolean = false;

  public tagTimeWeek: TagTimeSummaryResponse | null = null;
  public tagTimeMonth: TagTimeSummaryResponse | null = null;
  public tagTimeYear: TagTimeSummaryResponse | null = null;
  public tagTimeLoadingWeek: boolean = false;
  public tagTimeLoadingMonth: boolean = false;
  public tagTimeLoadingYear: boolean = false;
  public tagTimeErrorWeek: boolean = false;
  public tagTimeErrorMonth: boolean = false;
  public tagTimeErrorYear: boolean = false;

  private refreshRunning: boolean = false;
  private refreshQueued: boolean = false;
  private refreshQueuedForce: boolean = false;
  private focusKey: string = '';

  private recordCache: Map<string, TimeRecordWithContext[]> = new Map();
  private recordInflight: Map<string, Promise<TimeRecordWithContext[]>> = new Map();

  private calendarCache: Map<string, CalendarDaySummary[]> = new Map();
  private calendarInflight: Map<string, Promise<CalendarDaySummary[]>> = new Map();
  private dayLabelSummaryCache: Map<number, LabelSummaryModel[]> = new Map();
  private dayLabelSummaryInflight: Map<number, Promise<LabelSummaryModel[]>> = new Map();

  private dayRequestToken: number = 0;
  private streamRequestToken: number = 0;
  private tagTrendWeekToken: number = 0;
  private tagTrendMonthToken: number = 0;
  private tagTrendYearToken: number = 0;
  private tagTimeWeekToken: number = 0;
  private tagTimeMonthToken: number = 0;
  private tagTimeYearToken: number = 0;

  private streamPreferDarkColor: boolean = false;

  public invalidateCaches(): void {
    this.recordCache.clear();
    this.recordInflight.clear();
    this.calendarCache.clear();
    this.calendarInflight.clear();
    this.dayLabelSummaryCache.clear();
    this.dayLabelSummaryInflight.clear();
  }

  public async refreshAll(forceReload: boolean = false): Promise<void> {
    if (this.refreshRunning) {
      this.refreshQueued = true;
      this.refreshQueuedForce = this.refreshQueuedForce || forceReload;
      return;
    }
    this.refreshRunning = true;
    try {
      const focusDateMs = this.updateFocusDate();
      await Promise.all([
        this.refreshDayBundle(focusDateMs, forceReload),
        this.refreshTagTrend('week', forceReload),
        this.refreshTagTimeSummary('week', forceReload),
      ]);
    } finally {
      this.refreshRunning = false;
      if (this.refreshQueued) {
        const queuedForce = this.refreshQueuedForce;
        this.refreshQueued = false;
        this.refreshQueuedForce = false;
        await this.refreshAll(queuedForce);
      }
    }
  }

  public async refreshDayBundle(focusDateMs?: number, forceReload: boolean = false): Promise<void> {
    const previousFocusKey = this.focusKey;
    const resolvedFocus = focusDateMs ?? this.updateFocusDate();
    const nextFocusKey = this.formatFocusKey(TimeRecordUtil.getDayStart(resolvedFocus));
    const dayStart = TimeRecordUtil.getDayStart(resolvedFocus);
    const dayEnd = dayStart + DAY_MS - 1;
    const requestToken = this.nextDayRequestToken();
    this.dayTimelineLoading = true;
    this.dayDistributionLoading = true;
    this.dayTimelineError = false;
    this.dayDistributionError = false;
    try {
      const records = await this.loadRecords(dayStart, dayEnd, forceReload);
      if (!this.isLatestDayRequest(requestToken)) {
        return;
      }
      const dayPanel = buildDayReviewPanelData(dayStart, records);
      this.dayReviewData = dayPanel;
      this.dayTimelineSegments = this.buildTimelineSegments(dayPanel);
      this.dayTimelineHasRecords = dayPanel.groups.some(group => group.records.length > 0);
      this.dayTimelineDateLabel = dayPanel.dateLabel;

      const range = resolveTagTimeDistributionRange('day', dayStart);
      this.dayDistributionData = buildTagTimeDistributionPanelData('day', range, records);

      if (this.streamPreferDarkColor !== undefined) {
        await this.refreshStreamTimeline(this.streamPreferDarkColor, forceReload);
      }
      if (previousFocusKey === nextFocusKey) {
        this.bumpCalendarRefreshRevision();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh day bundle: ${JSON.stringify(error)}`);
      this.dayReviewData = null;
      this.dayDistributionData = null;
      this.dayTimelineSegments = [];
      this.dayTimelineHasRecords = false;
      this.dayTimelineDateLabel = '';
      this.dayTimelineError = true;
      this.dayDistributionError = true;
    } finally {
      if (this.isLatestDayRequest(requestToken)) {
        this.dayTimelineLoading = false;
        this.dayDistributionLoading = false;
      }
    }
  }

  private bumpCalendarRefreshRevision(): void {
    const current = AppStorage.get(StorageKeys.REFLECT_CALENDAR_REVISION) as number | undefined;
    if (typeof current === 'number') {
      AppStorage.set(StorageKeys.REFLECT_CALENDAR_REVISION, current + 1);
    } else {
      AppStorage.setOrCreate(StorageKeys.REFLECT_CALENDAR_REVISION, 1);
    }
  }

  public async refreshStreamTimeline(preferDarkColor: boolean, forceReload: boolean = false): Promise<FlowTimelineItem[]> {
    this.streamPreferDarkColor = preferDarkColor;
    const focusDateMs = this.updateFocusDate();
    const dayStart = TimeRecordUtil.getDayStart(focusDateMs);
    const dayEnd = dayStart + DAY_MS - 1;
    const requestToken = this.nextStreamRequestToken();
    this.streamTimelineLoading = true;
    this.streamTimelineError = false;
    try {
      const records = await this.loadRecords(dayStart, dayEnd, forceReload);
      const items = flowTimelineService.getDayTimelineFromRecords(records, dayStart, preferDarkColor);
      if (this.isLatestStreamRequest(requestToken)) {
        this.streamTimelineItems = items;
      }
      return items;
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh stream timeline: ${JSON.stringify(error)}`);
      if (this.isLatestStreamRequest(requestToken)) {
        this.streamTimelineItems = [];
        this.streamTimelineError = true;
      }
      return [];
    } finally {
      if (this.isLatestStreamRequest(requestToken)) {
        this.streamTimelineLoading = false;
      }
    }
  }

  public async refreshTagTrend(dimension: TagTrendDimension, forceReload: boolean = false): Promise<TagTrendResponse | null> {
    const focusDateMs = this.updateFocusDate();
    const range = resolveTagTrendRange(dimension, focusDateMs);
    const cached = this.getTagTrendResponse(dimension);
    if (!forceReload && cached && cached.startMs === range.startMs && cached.endMs === range.endMs) {
      return cached;
    }
    const token = this.nextTagTrendToken(dimension);
    this.setTagTrendLoading(dimension, true);
    this.setTagTrendError(dimension, false);
    try {
      const records = await this.loadRecords(range.startMs, range.endMs, forceReload);
      const request: TagTrendRequest = {
        dimension,
        focusDateMs,
      };
      const response = await tagActivityTrendService.buildActivityTrendsFromRecords(request, records);
      if (this.isLatestTagTrendRequest(dimension, token)) {
        this.setTagTrendResponse(dimension, response);
      }
      return response;
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh tag trend ${dimension}: ${JSON.stringify(error)}`);
      if (this.isLatestTagTrendRequest(dimension, token)) {
        this.setTagTrendResponse(dimension, null);
        this.setTagTrendError(dimension, true);
      }
      return null;
    } finally {
      if (this.isLatestTagTrendRequest(dimension, token)) {
        this.setTagTrendLoading(dimension, false);
      }
    }
  }

  public async refreshTagTimeSummary(dimension: TagTimeDimension, forceReload: boolean = false): Promise<TagTimeSummaryResponse | null> {
    const focusDateMs = this.updateFocusDate();
    const range = resolveTagTimeRange(dimension, focusDateMs);
    const cached = this.getTagTimeResponse(dimension);
    if (!forceReload && cached && cached.startMs === range.startMs && cached.endMs === range.endMs) {
      return cached;
    }
    const token = this.nextTagTimeToken(dimension);
    this.setTagTimeLoading(dimension, true);
    this.setTagTimeError(dimension, false);
    try {
      const records = await this.loadRecords(range.startMs, range.endMs, forceReload);
      const request: TagTimeSummaryRequest = {
        dimension,
        focusDateMs,
      };
      const response = tagTimeRangeService.buildTagTimeSummaryFromRecords(request, records);
      if (this.isLatestTagTimeRequest(dimension, token)) {
        this.setTagTimeResponse(dimension, response);
      }
      return response;
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh tag time summary ${dimension}: ${JSON.stringify(error)}`);
      if (this.isLatestTagTimeRequest(dimension, token)) {
        this.setTagTimeResponse(dimension, null);
        this.setTagTimeError(dimension, true);
      }
      return null;
    } finally {
      if (this.isLatestTagTimeRequest(dimension, token)) {
        this.setTagTimeLoading(dimension, false);
      }
    }
  }

  public async getCalendarDaySummaries(startMs: number, endMs: number, forceReload: boolean = false): Promise<CalendarDaySummary[]> {
    const cacheKey = `${startMs}-${endMs}`;
    if (!forceReload) {
      const cached = this.calendarCache.get(cacheKey);
      if (cached) {
        return cached;
      }
    }
    const inflight = this.calendarInflight.get(cacheKey);
    if (inflight) {
      return await inflight;
    }
    const request = RDBStoreUtil.getInstance().queryCalendarDaySummaries(startMs, endMs) as Promise<CalendarDaySummary[]>;
    this.calendarInflight.set(cacheKey, request);
    try {
      const summaries = await request;
      this.calendarCache.set(cacheKey, summaries);
      return summaries;
    } finally {
      this.calendarInflight.delete(cacheKey);
    }
  }

  public async getDayLabelSummary(dateMs: number, forceReload: boolean = false): Promise<LabelSummaryModel[]> {
    const dayStart = TimeRecordUtil.getDayStart(dateMs);
    if (!forceReload) {
      const cached = this.dayLabelSummaryCache.get(dayStart);
      if (cached) {
        return cached;
      }
    }
    const inflight = this.dayLabelSummaryInflight.get(dayStart);
    if (inflight) {
      return await inflight;
    }
    const request = reflectService.getDayLabelSummary(dayStart);
    this.dayLabelSummaryInflight.set(dayStart, request);
    try {
      const summaries = await request;
      this.dayLabelSummaryCache.set(dayStart, summaries);
      return summaries;
    } finally {
      this.dayLabelSummaryInflight.delete(dayStart);
    }
  }

  public getTagTrendResponse(dimension: TagTrendDimension): TagTrendResponse | null {
    switch (dimension) {
      case 'month':
        return this.tagTrendMonth;
      case 'year':
        return this.tagTrendYear;
      default:
        return this.tagTrendWeek;
    }
  }

  public getTagTimeResponse(dimension: TagTimeDimension): TagTimeSummaryResponse | null {
    switch (dimension) {
      case 'month':
        return this.tagTimeMonth;
      case 'year':
        return this.tagTimeYear;
      case 'day':
        return null;
      default:
        return this.tagTimeWeek;
    }
  }

  private async loadRecords(startMs: number, endMs: number, forceReload: boolean): Promise<TimeRecordWithContext[]> {
    const cacheKey = `${startMs}-${endMs}`;
    if (!forceReload) {
      const cached = this.recordCache.get(cacheKey);
      if (cached) {
        return cached;
      }
    }
    const inflight = this.recordInflight.get(cacheKey);
    if (inflight) {
      return await inflight;
    }
    const request = RDBStoreUtil.getInstance().queryTimeRecordsWithActivityAndTag(startMs, endMs);
    this.recordInflight.set(cacheKey, request);
    try {
      const records = await request;
      this.recordCache.set(cacheKey, records);
      return records;
    } finally {
      this.recordInflight.delete(cacheKey);
    }
  }

  private updateFocusDate(): number {
    const resolved = this.resolveFocusDateMs();
    const key = this.formatFocusKey(resolved);
    if (key !== this.focusKey) {
      this.focusKey = key;
      this.resetFocusData();
    }
    this.focusDateMs = resolved;
    return resolved;
  }

  private resolveFocusDateMs(): number {
    const now = new Date();
    const storedYear = AppStorage.get(StorageKeys.SELECTED_YEAR) as number | undefined;
    const storedMonth = AppStorage.get(StorageKeys.SELECTED_MONTH) as number | undefined;
    const storedDate = AppStorage.get(StorageKeys.SELECTED_DATE) as number | undefined;
    const year = storedYear ?? now.getFullYear();
    const month = storedMonth ?? (now.getMonth() + 1);
    const date = storedDate ?? now.getDate();
    const focusDate = new Date(year, month - 1, date);
    if (focusDate.getFullYear() !== year || (focusDate.getMonth() + 1) !== month || focusDate.getDate() !== date) {
      return TimeRecordUtil.getDayStart(now.getTime());
    }
    return TimeRecordUtil.getDayStart(focusDate.getTime());
  }

  private formatFocusKey(focusDateMs: number): string {
    const date = new Date(focusDateMs);
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  private resetFocusData(): void {
    this.dayReviewData = null;
    this.dayDistributionData = null;
    this.dayTimelineSegments = [];
    this.dayTimelineDateLabel = '';
    this.dayTimelineHasRecords = false;
    this.streamTimelineItems = [];
    this.tagTrendWeek = null;
    this.tagTrendMonth = null;
    this.tagTrendYear = null;
    this.tagTimeWeek = null;
    this.tagTimeMonth = null;
    this.tagTimeYear = null;
  }

  private buildTimelineSegments(panelData: DayReviewPanelData): ReflectTimelineSegment[] {
    const dayStartMs = panelData.dateMs;
    const orderedRecords: ReflectTimelineSegment[] = [];
    panelData.groups.forEach(group => {
      group.records.forEach((record, index) => {
        const bounded = clampToDay(record.startTimeMs, record.endTimeMs ?? record.startTimeMs, dayStartMs);
        if (!bounded) {
          return;
        }
        const durationMs = bounded.end - bounded.start;
        const weight = this.resolveSegmentWeight(durationMs);
        const segment: ReflectTimelineSegment = {
          id: `${group.tagId ?? 'untagged'}-${record.recordId ?? index}`,
          startMs: bounded.start,
          endMs: bounded.end,
          durationMs,
          weight,
          color: group.tagColor as ResourceColor,
          label: `${record.startLabel} - ${record.endLabel}`,
          activityTitle: record.activityTitle,
          tagName: group.tagName,
          isGap: false,
        };
        orderedRecords.push(segment);
      });
    });
    orderedRecords.sort((a, b) => a.startMs - b.startMs);

    const segments: ReflectTimelineSegment[] = [];
    let cursor = dayStartMs;
    const dayEndMs = dayStartMs + DAY_MS;
    orderedRecords.forEach((recordSegment, idx) => {
      if (recordSegment.startMs > cursor) {
        segments.push(this.createGapSegment(cursor, recordSegment.startMs, dayStartMs, idx));
      }
      segments.push(recordSegment);
      cursor = Math.max(cursor, recordSegment.endMs);
    });
    if (cursor < dayEndMs) {
      segments.push(this.createGapSegment(cursor, dayEndMs, dayStartMs, orderedRecords.length));
    }
    return segments;
  }

  private createGapSegment(startMs: number, endMs: number, dayStartMs: number, index: number): ReflectTimelineSegment {
    const durationMs = Math.max(endMs - startMs, 0);
    const weight = this.resolveSegmentWeight(durationMs);
    return {
      id: `gap-${dayStartMs}-${index}-${startMs}`,
      startMs,
      endMs,
      durationMs,
      weight,
      color: Color.Transparent as ResourceColor,
      label: `${TimeRecordUtil.formatToHHmm(startMs)} - ${TimeRecordUtil.formatToHHmm(endMs)}`,
      activityTitle: '空闲时段',
      tagName: '空闲',
      isGap: true,
    };
  }

  private resolveSegmentWeight(durationMs: number): number {
    if (durationMs <= 0) {
      return MIN_SEGMENT_SECONDS;
    }
    const durationSeconds = Math.max(Math.floor(durationMs / 1000), MIN_SEGMENT_SECONDS);
    return durationSeconds;
  }

  private nextDayRequestToken(): number {
    this.dayRequestToken += 1;
    return this.dayRequestToken;
  }

  private isLatestDayRequest(token: number): boolean {
    return token === this.dayRequestToken;
  }

  private nextStreamRequestToken(): number {
    this.streamRequestToken += 1;
    return this.streamRequestToken;
  }

  private isLatestStreamRequest(token: number): boolean {
    return token === this.streamRequestToken;
  }

  private nextTagTrendToken(dimension: TagTrendDimension): number {
    switch (dimension) {
      case 'month':
        this.tagTrendMonthToken += 1;
        return this.tagTrendMonthToken;
      case 'year':
        this.tagTrendYearToken += 1;
        return this.tagTrendYearToken;
      default:
        this.tagTrendWeekToken += 1;
        return this.tagTrendWeekToken;
    }
  }

  private isLatestTagTrendRequest(dimension: TagTrendDimension, token: number): boolean {
    switch (dimension) {
      case 'month':
        return token === this.tagTrendMonthToken;
      case 'year':
        return token === this.tagTrendYearToken;
      default:
        return token === this.tagTrendWeekToken;
    }
  }

  private setTagTrendResponse(dimension: TagTrendDimension, response: TagTrendResponse | null): void {
    switch (dimension) {
      case 'month':
        this.tagTrendMonth = response;
        break;
      case 'year':
        this.tagTrendYear = response;
        break;
      default:
        this.tagTrendWeek = response;
        break;
    }
  }

  private setTagTrendLoading(dimension: TagTrendDimension, loading: boolean): void {
    switch (dimension) {
      case 'month':
        this.tagTrendLoadingMonth = loading;
        break;
      case 'year':
        this.tagTrendLoadingYear = loading;
        break;
      default:
        this.tagTrendLoadingWeek = loading;
        break;
    }
  }

  private setTagTrendError(dimension: TagTrendDimension, error: boolean): void {
    switch (dimension) {
      case 'month':
        this.tagTrendErrorMonth = error;
        break;
      case 'year':
        this.tagTrendErrorYear = error;
        break;
      default:
        this.tagTrendErrorWeek = error;
        break;
    }
  }

  private nextTagTimeToken(dimension: TagTimeDimension): number {
    switch (dimension) {
      case 'month':
        this.tagTimeMonthToken += 1;
        return this.tagTimeMonthToken;
      case 'year':
        this.tagTimeYearToken += 1;
        return this.tagTimeYearToken;
      default:
        this.tagTimeWeekToken += 1;
        return this.tagTimeWeekToken;
    }
  }

  private isLatestTagTimeRequest(dimension: TagTimeDimension, token: number): boolean {
    switch (dimension) {
      case 'month':
        return token === this.tagTimeMonthToken;
      case 'year':
        return token === this.tagTimeYearToken;
      default:
        return token === this.tagTimeWeekToken;
    }
  }

  private setTagTimeResponse(dimension: TagTimeDimension, response: TagTimeSummaryResponse | null): void {
    switch (dimension) {
      case 'month':
        this.tagTimeMonth = response;
        break;
      case 'year':
        this.tagTimeYear = response;
        break;
      case 'week':
        this.tagTimeWeek = response;
        break;
      default:
        break;
    }
  }

  private setTagTimeLoading(dimension: TagTimeDimension, loading: boolean): void {
    switch (dimension) {
      case 'month':
        this.tagTimeLoadingMonth = loading;
        break;
      case 'year':
        this.tagTimeLoadingYear = loading;
        break;
      case 'week':
        this.tagTimeLoadingWeek = loading;
        break;
      default:
        break;
    }
  }

  private setTagTimeError(dimension: TagTimeDimension, error: boolean): void {
    switch (dimension) {
      case 'month':
        this.tagTimeErrorMonth = error;
        break;
      case 'year':
        this.tagTimeErrorYear = error;
        break;
      case 'week':
        this.tagTimeErrorWeek = error;
        break;
      default:
        break;
    }
  }
}
