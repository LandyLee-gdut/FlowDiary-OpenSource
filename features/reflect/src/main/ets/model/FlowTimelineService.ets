import { hilog } from '@kit.PerformanceAnalysisKit';
import { RDBStoreUtil, TimeRecordUtil, TimeRecordWithContext, AppColors } from 'base';
import type { FlowTimelineItem } from './FlowEventModel';

const TAG: string = 'FlowTimelineService';
const DAY_MS: number = 24 * 60 * 60 * 1000;
const UNTITLED_ACTIVITY: string = '未命名活动';

class FlowTimelineServiceImpl {
  private static instance: FlowTimelineServiceImpl;

  static getInstance(): FlowTimelineServiceImpl {
    if (!FlowTimelineServiceImpl.instance) {
      FlowTimelineServiceImpl.instance = new FlowTimelineServiceImpl();
    }
    return FlowTimelineServiceImpl.instance;
  }

  async getDayTimeline(focusDateMs?: number, preferDarkColor?: boolean): Promise<FlowTimelineItem[]> {
    const dayStartMs = TimeRecordUtil.getDayStart(focusDateMs ?? Date.now());
    const dayEndMs = dayStartMs + DAY_MS - 1;
    const rdbStoreUtil = RDBStoreUtil.getInstance();

    try {
      const records = await rdbStoreUtil.queryTimeRecordsWithActivityAndTag(dayStartMs, dayEndMs);
      const items = this.buildTimelineItems(records, dayStartMs, dayEndMs, preferDarkColor ?? false);
      return items;
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to load day timeline: ${JSON.stringify(error)}`);
      return [];
    }
  }

  getDayTimelineFromRecords(records: TimeRecordWithContext[], focusDateMs: number, preferDarkColor: boolean): FlowTimelineItem[] {
    const dayStartMs = TimeRecordUtil.getDayStart(focusDateMs);
    const dayEndMs = dayStartMs + DAY_MS - 1;
    return this.buildTimelineItems(records, dayStartMs, dayEndMs, preferDarkColor);
  }

  private buildTimelineItems(
    records: TimeRecordWithContext[],
    dayStartMs: number,
    dayEndMs: number,
    preferDarkColor: boolean
  ): FlowTimelineItem[] {
    const items: FlowTimelineItem[] = [];

    records.forEach((record: TimeRecordWithContext) => {
      const durationMs = this.computeDuration(record, dayStartMs, dayEndMs);
      if (durationMs <= 0) {
        return;
      }

      const endMs = this.resolveEndMs(record, durationMs, dayEndMs);

      const item: FlowTimelineItem = {
        id: 0,
        time: TimeRecordUtil.formatToHHmm(record.startTimeMs),
        duration: TimeRecordUtil.formatDuration(durationMs),
        title: record.activityName || UNTITLED_ACTIVITY,
        color: preferDarkColor
          ? (record.tagColorHex ?? record.tagLightColorHex ?? AppColors.NEUTRAL_200)
          : (record.tagLightColorHex ?? record.tagColorHex ?? AppColors.NEUTRAL_200),
        startMs: record.startTimeMs,
        endMs,
        durationMs,
        durationMinutes: Math.max(1, Math.round(durationMs / 60000)),
        endLabel: TimeRecordUtil.formatToHHmm(endMs)
      };
      items.push(item);
    });

    items.sort((a: FlowTimelineItem, b: FlowTimelineItem) => a.startMs - b.startMs);

    const normalized: FlowTimelineItem[] = [];
    for (let index = 0; index < items.length; index++) {
      const source = items[index];
      const normalizedItem: FlowTimelineItem = {
        id: index + 1,
        time: source.time,
        duration: source.duration,
        title: source.title,
        color: source.color,
        startMs: source.startMs,
        endMs: source.endMs,
        durationMs: source.durationMs,
        durationMinutes: source.durationMinutes,
        endLabel: source.endLabel
      };
      normalized.push(normalizedItem);
    }
    return normalized;
  }

  private computeDuration(record: TimeRecordWithContext, dayStartMs: number, dayEndMs: number): number {
    const declaredDuration = record.durationMs ?? undefined;
    
    // 如果没有 endTimeMs 且没有 durationMs，直接忽略该记录
    if (record.endTimeMs == null && declaredDuration === undefined) {
      return 0;
    }
    
    const rawEnd = record.endTimeMs ?? (declaredDuration !== undefined ? record.startTimeMs + declaredDuration : 0);
    if (rawEnd === 0) {
      return 0;
    }
    
    const clampedStart = Math.max(record.startTimeMs, dayStartMs);
    const clampedEnd = Math.min(rawEnd, dayEndMs);
    if (clampedEnd <= clampedStart) {
      return 0;
    }
    const span = clampedEnd - clampedStart;
    if (declaredDuration !== undefined && declaredDuration > 0) {
      return Math.min(span, declaredDuration);
    }
    return span;
  }

  private resolveEndMs(record: TimeRecordWithContext, durationMs: number, dayEndMs: number): number {
    const declaredEnd = record.endTimeMs ?? (record.durationMs ? record.startTimeMs + record.durationMs : null);
    const computedEnd = record.startTimeMs + durationMs;
    if (declaredEnd === null) {
      return Math.min(computedEnd, dayEndMs);
    }
    return Math.min(declaredEnd, dayEndMs);
  }
}

export const flowTimelineService: FlowTimelineServiceImpl = FlowTimelineServiceImpl.getInstance();
