import dayjs from 'dayjs';
import { RDBStoreUtil, TimeRecordUtil } from 'base';
import type { FocusDateBoundsRow } from 'base';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReflectFlowCardItem, reflectFlowCardService } from './ReflectFlowCardService';

const TAG = 'ReflectFlowCardGallery';
const DAY_MS: number = 24 * 60 * 60 * 1000;

const INITIAL_DAYS_BEFORE: number = 3;
const INITIAL_DAYS_AFTER: number = 3;
const PREFETCH_EDGE_THRESHOLD: number = 3;
const MAX_SCAN_DAYS_PER_REQUEST: number = 14;

export interface FlowCardGallerySelection {
  year: number;
  month: number;
  day: number;
}

export interface FlowCardGalleryTimelinePayload {
  items: ReflectFlowCardItem[];
  itemCount: number;
  currentIndex: number;
}

class FlowCardGalleryTimelinePayloadImpl implements FlowCardGalleryTimelinePayload {
  items: ReflectFlowCardItem[];
  itemCount: number;
  currentIndex: number;

  constructor(items: ReflectFlowCardItem[], currentIndex: number) {
    this.items = items;
    this.itemCount = items.length;
    this.currentIndex = currentIndex;
  }
}

export interface FlowCardGalleryCallbacks {
  setLoading: (loading: boolean) => void;
  applyTimeline: (payload: FlowCardGalleryTimelinePayload) => void;
  onNoMoreData?: (direction: number) => void;
}

class LoadMoreRequest {
  showNoMoreToast: boolean;
  sessionId: number;

  constructor(showNoMoreToast: boolean, sessionId: number) {
    this.showNoMoreToast = showNoMoreToast;
    this.sessionId = sessionId;
  }
}

interface InitializeOptions {
  showLoading?: boolean;
}

export class FlowCardGalleryController {
  private currentIndex: number = 0;
  private timelineItems: ReflectFlowCardItem[] = [];
  private bounds: FocusDateBoundsRow | null = null;
  private currentDayStartMs: number = TimeRecordUtil.getDayStart(Date.now());

  private isLoading: boolean = false;
  private isLoadingPrev: boolean = false;
  private isLoadingNext: boolean = false;
  private noMorePrev: boolean = false;
  private noMoreNext: boolean = false;

  private sessionId: number = 0;
  private pendingTimer: number = -1;

  private cachedDayItems: Map<number, ReflectFlowCardItem[]> = new Map();
  private knownEmptyDays: Set<number> = new Set();
  private insertedDays: Set<number> = new Set();
  private readonly maxCachedDays: number = 30;

  private prevSearchCursorDayStart: number | null = null;
  private nextSearchCursorDayStart: number | null = null;

  private readonly callbacks: FlowCardGalleryCallbacks;

  constructor(callbacks: FlowCardGalleryCallbacks) {
    this.callbacks = callbacks;
  }

  public dispose(): void {
    if (this.pendingTimer !== -1) {
      clearTimeout(this.pendingTimer);
      this.pendingTimer = -1;
    }
  }

  public setCurrentIndex(index: number): void {
    this.currentIndex = index;
    this.maybePrefetchAroundIndex(index);
  }

  public getDateLabelForIndex(index: number): string {
    const item = this.timelineItems[index];
    if (!item) {
      return '';
    }
    const dayStart = TimeRecordUtil.getDayStart(item.latestStartTimeMs);
    return FlowCardGalleryController.formatDateLabel(dayStart);
  }

  public getSelectionForIndex(index: number): FlowCardGallerySelection | null {
    const item = this.timelineItems[index];
    if (!item) {
      return null;
    }
    return this.msToSelection(item.latestStartTimeMs);
  }

  public scheduleJump(selection: FlowCardGallerySelection, options?: InitializeOptions): void {
    if (this.pendingTimer !== -1) {
      clearTimeout(this.pendingTimer);
      this.pendingTimer = -1;
    }

    this.pendingTimer = setTimeout(() => {
      this.pendingTimer = -1;
      void this.jumpToSelection(selection, options);
    }, 0);
  }

  public async initialize(selection: FlowCardGallerySelection, options?: InitializeOptions): Promise<void> {
    const sessionId = this.resetTimeline('initialize');
    const showLoading = options?.showLoading ?? true;

    if (showLoading) {
      this.setLoading(true);
    }

    try {
      await this.ensureBounds(sessionId);
      if (sessionId !== this.sessionId) {
        return;
      }

      const anchorDayStart = TimeRecordUtil.getDayStart(this.selectionToMs(selection));
      this.currentDayStartMs = anchorDayStart;

      const anchorItems = await this.loadDayItems(anchorDayStart, sessionId);
      if (sessionId !== this.sessionId) {
        return;
      }

      if (anchorItems.length === 0) {
        this.knownEmptyDays.add(anchorDayStart);
        this.prevSearchCursorDayStart = anchorDayStart;
        this.nextSearchCursorDayStart = anchorDayStart;
        this.applyTimeline();
        return;
      }

      await this.loadAndInsertDay(anchorDayStart, 0, sessionId);
      if (sessionId !== this.sessionId) {
        return;
      }

      this.prevSearchCursorDayStart = anchorDayStart;
      this.nextSearchCursorDayStart = anchorDayStart;

      for (let i = 0; i < INITIAL_DAYS_BEFORE; i++) {
        await this.loadMore(-1, new LoadMoreRequest(false, sessionId));
        if (sessionId !== this.sessionId) {
          return;
        }
      }

      for (let i = 0; i < INITIAL_DAYS_AFTER; i++) {
        await this.loadMore(1, new LoadMoreRequest(false, sessionId));
        if (sessionId !== this.sessionId) {
          return;
        }
      }

      this.applyTimeline();
    } catch (error) {
      if (sessionId !== this.sessionId) {
        return;
      }
      hilog.error(0x0000, TAG, `galleryTimeline initialize failed: ${JSON.stringify(error)}`);
      this.applyTimeline();
    } finally {
      if (sessionId === this.sessionId) {
        this.setLoading(false);
      }
    }
  }

  public async jumpToSelection(selection: FlowCardGallerySelection, options?: InitializeOptions): Promise<void> {
    const targetDayStart = TimeRecordUtil.getDayStart(this.selectionToMs(selection));
    const existingIndex = this.findFirstIndexForDayStart(targetDayStart);
    if (existingIndex !== -1) {
      this.currentIndex = existingIndex;
      this.currentDayStartMs = targetDayStart;
      this.applyTimeline();
      return;
    }
    await this.initialize(selection, options);
  }

  public async requestLoadMore(direction: number): Promise<void> {
    if (this.timelineItems.length === 0) {
      return;
    }
    await this.loadMore(direction, new LoadMoreRequest(true, this.sessionId));
  }

  public async jumpToAdjacentDay(direction: number): Promise<void> {
    if (this.timelineItems.length === 0) {
      this.maybeNotifyNoMoreData(direction);
      return;
    }

    const currentItem = this.timelineItems[this.currentIndex];
    if (!currentItem) {
      return;
    }

    const currentDayStart = TimeRecordUtil.getDayStart(currentItem.latestStartTimeMs);
    const found = this.findAdjacentDayIndex(currentDayStart, direction);
    if (found !== -1) {
      this.currentIndex = found;
      this.applyTimeline();
      return;
    }

    await this.loadMore(direction, new LoadMoreRequest(true, this.sessionId));
    const foundAfterLoad = this.findAdjacentDayIndex(currentDayStart, direction);
    if (foundAfterLoad !== -1) {
      this.currentIndex = foundAfterLoad;
      this.applyTimeline();
    }
  }

  public selectionToMs(selection: FlowCardGallerySelection): number {
    const dayString = `${selection.year}-${selection.month.toString().padStart(2, '0')}-${selection.day.toString().padStart(2, '0')}`;
    return dayjs(dayString).valueOf();
  }

  public msToSelection(dateMs: number): FlowCardGallerySelection {
    const target = dayjs(dateMs);
    return {
      year: target.year(),
      month: target.month() + 1,
      day: target.date()
    };
  }

  public static formatDateLabel(dayStartMs: number): string {
    const date = new Date(dayStartMs);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    const weekdayLabels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    const weekday = weekdayLabels[date.getDay()] ?? '';
    return `${month}月${day}日 · ${weekday}`;
  }

  private resetTimeline(reason: string): number {
    this.sessionId += 1;
    const sessionId = this.sessionId;

    this.timelineItems = [];
    this.currentIndex = 0;
    this.bounds = null;
    this.noMorePrev = false;
    this.noMoreNext = false;
    this.isLoadingPrev = false;
    this.isLoadingNext = false;

    this.prevSearchCursorDayStart = null;
    this.nextSearchCursorDayStart = null;
    this.cachedDayItems.clear();
    this.knownEmptyDays.clear();
    this.insertedDays.clear();

    if (this.pendingTimer !== -1) {
      clearTimeout(this.pendingTimer);
      this.pendingTimer = -1;
    }

    hilog.info(0x0000, TAG, `galleryTimeline reset reason=${reason} sessionId=${sessionId}`);
    return sessionId;
  }

  private setLoading(loading: boolean): void {
    if (this.isLoading === loading) {
      return;
    }
    this.isLoading = loading;
    this.callbacks.setLoading(loading);
  }

  private applyTimeline(): void {
    const items = this.timelineItems.slice();
    const itemCount = items.length;
    if (this.currentIndex < 0) {
      this.currentIndex = 0;
    }
    if (itemCount > 0 && this.currentIndex >= itemCount) {
      this.currentIndex = itemCount - 1;
    }
    if (itemCount > 0) {
      const item = items[this.currentIndex];
      if (item) {
        this.currentDayStartMs = TimeRecordUtil.getDayStart(item.latestStartTimeMs);
      }
    }
    const payload = new FlowCardGalleryTimelinePayloadImpl(items, this.currentIndex);
    this.callbacks.applyTimeline(payload);
  }

  private async ensureBounds(sessionId: number): Promise<void> {
    if (this.bounds) {
      return;
    }
    const rdbStoreUtil = RDBStoreUtil.getInstance();
    const bounds = await rdbStoreUtil.queryFocusDateBounds();
    if (sessionId !== this.sessionId) {
      return;
    }
    this.bounds = bounds;
    hilog.info(0x0000, TAG,
      `galleryTimeline bounds earliest=${bounds.earliestRecordMs ?? -1} latest=${bounds.latestRecordMs}`);
  }

  private getEarliestAllowedDayStart(): number | null {
    const earliest = this.bounds?.earliestRecordMs ?? null;
    if (earliest === null) {
      return null;
    }
    return TimeRecordUtil.getDayStart(earliest);
  }

  private getLatestAllowedDayStart(): number {
    const latest = this.bounds?.latestRecordMs ?? Date.now();
    return TimeRecordUtil.getDayStart(latest);
  }

  // NOTE: Anchor-day resolution intentionally does not fallback to the nearest
  // non-empty day. When a user selects a day with no data, the gallery should
  // show an empty state for that exact date (see V1.2 immersive flow card plan).

  private findFirstIndexForDayStart(dayStartMs: number): number {
    for (let i = 0; i < this.timelineItems.length; i++) {
      const item = this.timelineItems[i];
      if (!item) {
        continue;
      }
      const itemDayStart = TimeRecordUtil.getDayStart(item.latestStartTimeMs);
      if (itemDayStart === dayStartMs) {
        return i;
      }
    }
    return -1;
  }

  private findAdjacentDayIndex(currentDayStart: number, direction: number): number {
    if (direction < 0) {
      for (let i = this.currentIndex - 1; i >= 0; i--) {
        const item = this.timelineItems[i];
        if (!item) {
          continue;
        }
        const dayStart = TimeRecordUtil.getDayStart(item.latestStartTimeMs);
        if (dayStart < currentDayStart) {
          const targetDayStart = dayStart;
          for (let j = i; j + 1 < this.timelineItems.length; j++) {
            const nextItem = this.timelineItems[j + 1];
            if (!nextItem) {
              break;
            }
            const nextDayStart = TimeRecordUtil.getDayStart(nextItem.latestStartTimeMs);
            if (nextDayStart !== targetDayStart) {
              return j;
            }
          }
          return i;
        }
      }
      return -1;
    }

    for (let i = this.currentIndex + 1; i < this.timelineItems.length; i++) {
      const item = this.timelineItems[i];
      if (!item) {
        continue;
      }
      const dayStart = TimeRecordUtil.getDayStart(item.latestStartTimeMs);
      if (dayStart > currentDayStart) {
        return i;
      }
    }
    return -1;
  }

  private maybePrefetchAroundIndex(index: number): void {
    if (this.isLoading) {
      return;
    }
    const itemCount = this.timelineItems.length;
    if (itemCount <= 0) {
      return;
    }

    if (!this.noMorePrev && index <= PREFETCH_EDGE_THRESHOLD) {
      void this.loadMore(-1, new LoadMoreRequest(false, this.sessionId));
    }
    if (!this.noMoreNext && index >= itemCount - 1 - PREFETCH_EDGE_THRESHOLD) {
      void this.loadMore(1, new LoadMoreRequest(false, this.sessionId));
    }
  }

  private maybeNotifyNoMoreData(direction: number): void {
    if (direction < 0) {
      if (!this.noMorePrev) {
        return;
      }
    } else {
      if (!this.noMoreNext) {
        return;
      }
    }
    this.callbacks.onNoMoreData?.(direction);
  }

  private async loadMore(
    direction: number,
    params: LoadMoreRequest
  ): Promise<void> {
    const sessionId = params.sessionId;
    if (sessionId !== this.sessionId) {
      return;
    }
    if (this.timelineItems.length === 0) {
      return;
    }

    if (direction < 0) {
      if (this.noMorePrev) {
        if (params.showNoMoreToast) {
          this.callbacks.onNoMoreData?.(-1);
        }
        return;
      }
      if (this.isLoadingPrev) {
        return;
      }
      this.isLoadingPrev = true;
    } else {
      if (this.noMoreNext) {
        if (params.showNoMoreToast) {
          this.callbacks.onNoMoreData?.(1);
        }
        return;
      }
      if (this.isLoadingNext) {
        return;
      }
      this.isLoadingNext = true;
    }

    try {
      await this.ensureBounds(sessionId);
      if (sessionId !== this.sessionId) {
        return;
      }

      const earliestAllowed = this.getEarliestAllowedDayStart();
      const latestAllowed = this.getLatestAllowedDayStart();

      let scanCursorDayStart: number | null = direction < 0 ? this.prevSearchCursorDayStart : this.nextSearchCursorDayStart;
      if (scanCursorDayStart === null) {
        const currentItem = this.timelineItems[this.currentIndex];
        if (!currentItem) {
          return;
        }
        scanCursorDayStart = TimeRecordUtil.getDayStart(currentItem.latestStartTimeMs);
      }

      if (scanCursorDayStart === null) {
        return;
      }

      for (let scanned = 0; scanned < MAX_SCAN_DAYS_PER_REQUEST; scanned++) {
        if (sessionId !== this.sessionId) {
          return;
        }

        const candidateDayStart: number = scanCursorDayStart + direction * DAY_MS;
        scanCursorDayStart = candidateDayStart;

        if (direction < 0) {
          this.prevSearchCursorDayStart = scanCursorDayStart;
        } else {
          this.nextSearchCursorDayStart = scanCursorDayStart;
        }

        if (earliestAllowed !== null && candidateDayStart < earliestAllowed) {
          this.noMorePrev = true;
          if (params.showNoMoreToast) {
            this.callbacks.onNoMoreData?.(-1);
          }
          return;
        }
        if (candidateDayStart > latestAllowed) {
          this.noMoreNext = true;
          if (params.showNoMoreToast) {
            this.callbacks.onNoMoreData?.(1);
          }
          return;
        }
        if (this.insertedDays.has(candidateDayStart) || this.knownEmptyDays.has(candidateDayStart)) {
          continue;
        }

        const items = await this.loadDayItems(candidateDayStart, sessionId);
        if (sessionId !== this.sessionId) {
          return;
        }
        if (items.length === 0) {
          this.knownEmptyDays.add(candidateDayStart);
          continue;
        }

        const insertDirection: -1 | 1 = direction < 0 ? -1 : 1;
        await this.loadAndInsertDay(candidateDayStart, insertDirection, sessionId);
        if (sessionId !== this.sessionId) {
          return;
        }
        this.applyTimeline();
        return;
      }

      const rdbStoreUtil = RDBStoreUtil.getInstance();
      let fallbackTs: number | null = null;
      if (direction < 0) {
        fallbackTs = await rdbStoreUtil.queryLatestTimeRecordStartBefore(scanCursorDayStart);
      } else {
        const cutoff = scanCursorDayStart + DAY_MS - 1;
        fallbackTs = await rdbStoreUtil.queryEarliestTimeRecordStartAfter(cutoff);
      }
      if (sessionId !== this.sessionId) {
        return;
      }
      if (fallbackTs === null) {
        if (direction < 0) {
          this.noMorePrev = true;
          if (params.showNoMoreToast) {
            this.callbacks.onNoMoreData?.(-1);
          }
        } else {
          this.noMoreNext = true;
          if (params.showNoMoreToast) {
            this.callbacks.onNoMoreData?.(1);
          }
        }
        return;
      }

      const fallbackDayStart = TimeRecordUtil.getDayStart(fallbackTs);
      if (direction < 0) {
        if (earliestAllowed !== null && fallbackDayStart < earliestAllowed) {
          this.noMorePrev = true;
          if (params.showNoMoreToast) {
            this.callbacks.onNoMoreData?.(-1);
          }
          return;
        }
        this.prevSearchCursorDayStart = fallbackDayStart;
      } else {
        if (fallbackDayStart > latestAllowed) {
          this.noMoreNext = true;
          if (params.showNoMoreToast) {
            this.callbacks.onNoMoreData?.(1);
          }
          return;
        }
        this.nextSearchCursorDayStart = fallbackDayStart;
      }

      const insertDirection: -1 | 1 = direction < 0 ? -1 : 1;
      await this.loadAndInsertDay(fallbackDayStart, insertDirection, sessionId);
      if (sessionId !== this.sessionId) {
        return;
      }
      this.applyTimeline();
    } catch (error) {
      if (sessionId !== this.sessionId) {
        return;
      }
      hilog.warn(0x0000, TAG, `galleryTimeline loadMore failed dir=${direction}: ${JSON.stringify(error)}`);
    } finally {
      if (direction < 0) {
        this.isLoadingPrev = false;
      } else {
        this.isLoadingNext = false;
      }
    }
  }

  private async loadAndInsertDay(dayStartMs: number, direction: -1 | 0 | 1, sessionId: number): Promise<void> {
    if (sessionId !== this.sessionId) {
      return;
    }
    if (this.insertedDays.has(dayStartMs)) {
      return;
    }
    const items = await this.loadDayItems(dayStartMs, sessionId);
    if (sessionId !== this.sessionId) {
      return;
    }
    if (items.length === 0) {
      this.knownEmptyDays.add(dayStartMs);
      return;
    }

    this.insertedDays.add(dayStartMs);
    if (direction < 0) {
      this.timelineItems = items.concat(this.timelineItems);
      this.currentIndex += items.length;
    } else if (direction > 0) {
      this.timelineItems = this.timelineItems.concat(items);
    } else {
      this.timelineItems = items.slice();
      this.currentIndex = 0;
    }
  }

  private async loadDayItems(dayStartMs: number, sessionId: number): Promise<ReflectFlowCardItem[]> {
    const cached = this.cachedDayItems.get(dayStartMs);
    if (cached) {
      return cached.slice();
    }
    if (sessionId !== this.sessionId) {
      return [];
    }

    const items = await reflectFlowCardService.getDayFlowCardItems(dayStartMs);
    if (sessionId !== this.sessionId) {
      return [];
    }

    this.cacheDayItems(dayStartMs, items);
    return items.slice();
  }

  private cacheDayItems(dayStartMs: number, items: ReflectFlowCardItem[]): void {
    this.cachedDayItems.set(dayStartMs, items.slice());

    const existing = this.cachedDayItems.get(dayStartMs);
    if (existing) {
      this.cachedDayItems.delete(dayStartMs);
      this.cachedDayItems.set(dayStartMs, existing);
    }

    while (this.cachedDayItems.size > this.maxCachedDays) {
      const oldestKey = this.cachedDayItems.keys().next().value as number | undefined;
      if (oldestKey === undefined) {
        break;
      }
      this.cachedDayItems.delete(oldestKey);
    }
  }
}
