import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys, preferencesUtil, RDBStoreUtil, TimeRecordUtil, TimeRecordWithContext } from 'base';

const TAG: string = 'ReflectTodayWidgetService';
const DAY_MS: number = 24 * 60 * 60 * 1000;
const FORM_DIMENSION_2X2: string = '2*2';
const UNTAGGED_ID: string = '__untagged__';
const UNTAGGED_LABEL: string = '未分配';

class SegmentAggregate {
  tagId: string = '';
  label: string = '';
  totalDurationMs: number = 0;
  latestStartTimeMs: number = 0;
  colorHex: string | null = null;
}

export class ReflectTodayWidgetSegment {
  label: string = '';
  durationMs: number = 0;
  ratio: number = 0;
  colorHex: string = '';
}

export class ReflectTodayWidgetData {
  segments: ReflectTodayWidgetSegment[] = [];
  totalDurationMs: number = 0;
}

interface ReflectTodayWidgetFormData {
  formDimension: string;
  reflectTodayWidgetSegments: string;
  reflectTodayWidgetTotalDuration: string;
}

interface ReflectTodayWidgetFormEntry {
  formId: string;
  dimension: string;
}

class ReflectTodayWidgetServiceImpl {
  async getReflectTodayWidgetData(context: Context, dateMs?: number): Promise<ReflectTodayWidgetData> {
    const data = new ReflectTodayWidgetData();
    try {
      await this.ensureDbReady(context);
      const now = dateMs ?? Date.now();
      const dayStart = TimeRecordUtil.getDayStart(now);
      const dayEnd = dayStart + DAY_MS - 1;
      const store = RDBStoreUtil.getInstance();
      const records = await store.queryTimeRecordsWithActivityAndTag(dayStart, dayEnd);
      if (!records || records.length === 0) {
        return data;
      }

      const aggregates = this.aggregateRecords(records);
      if (aggregates.length === 0) {
        return data;
      }

      aggregates.sort((a: SegmentAggregate, b: SegmentAggregate) => {
        if (b.totalDurationMs !== a.totalDurationMs) {
          return b.totalDurationMs - a.totalDurationMs;
        }
        return b.latestStartTimeMs - a.latestStartTimeMs;
      });

      const totalDurationMs = aggregates.reduce((sum: number, item: SegmentAggregate) => sum + item.totalDurationMs, 0);
      data.totalDurationMs = totalDurationMs;
      data.segments = aggregates.map((aggregate: SegmentAggregate) => this.toSegment(aggregate, totalDurationMs));
      return data;
    } catch (error) {
      hilog.error(0x0000, TAG, `getReflectTodayWidgetData failed: ${JSON.stringify(error)}`);
      return data;
    }
  }

  async registerForm(context: Context, formId: string, dimension: string): Promise<void> {
    if (!formId || formId.length === 0) {
      return;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return;
    }
    const ids = this.loadFormIds();
    if (!ids.includes(formId)) {
      ids.push(formId);
      preferencesUtil.putSync(PreferenceKeys.REFLECT_TODAY_WIDGET_FORM_IDS, JSON.stringify(ids));
    }
    const entries = this.loadFormEntries();
    const existing = entries.find((entry: ReflectTodayWidgetFormEntry) => entry.formId === formId);
    if (existing) {
      existing.dimension = dimension;
    } else {
      entries.push({ formId: formId, dimension: dimension });
    }
    preferencesUtil.putSync(PreferenceKeys.REFLECT_TODAY_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
  }

  async unregisterForm(context: Context, formId: string): Promise<void> {
    if (!formId || formId.length === 0) {
      return;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return;
    }
    const ids = this.loadFormIds().filter((id: string) => id !== formId);
    const entries = this.loadFormEntries().filter((entry: ReflectTodayWidgetFormEntry) => entry.formId !== formId);
    preferencesUtil.putSync(PreferenceKeys.REFLECT_TODAY_WIDGET_FORM_IDS, JSON.stringify(ids));
    preferencesUtil.putSync(PreferenceKeys.REFLECT_TODAY_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
  }

  async refreshRegisteredForms(context: Context): Promise<void> {
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return;
    }
    const formIds = this.loadFormIds();
    if (formIds.length === 0) {
      return;
    }
    const entries = this.loadFormEntries();
    const dimensionMap = this.buildDimensionMap(entries);
    const data = await this.getReflectTodayWidgetData(context);
    for (const formId of formIds) {
      try {
        const dimension = dimensionMap.get(formId) ?? FORM_DIMENSION_2X2;
        const formData = this.buildFormData(dimension, data);
        const binding = formBindingData.createFormBindingData(formData);
        await formProvider.updateForm(formId, binding);
      } catch (error) {
        hilog.error(0x0000, TAG, `refreshRegisteredForms failed for ${formId}: ${JSON.stringify(error)}`);
      }
    }
  }

  async refreshFormById(context: Context, formId: string, dimension?: string): Promise<boolean> {
    if (!formId || formId.length === 0) {
      return false;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return false;
    }
    const ids = this.loadFormIds();
    if (!ids.includes(formId)) {
      return false;
    }
    try {
      let resolvedDimension = dimension;
      if (!resolvedDimension || resolvedDimension.length === 0) {
        const entries = this.loadFormEntries();
        const match = entries.find((entry: ReflectTodayWidgetFormEntry) => entry.formId === formId);
        if (match) {
          resolvedDimension = match.dimension;
        }
      }
      if (!resolvedDimension || resolvedDimension.length === 0) {
        resolvedDimension = FORM_DIMENSION_2X2;
      }
      const data = await this.getReflectTodayWidgetData(context);
      const formData = this.buildFormData(resolvedDimension, data);
      const binding = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, binding);
      return true;
    } catch (error) {
      hilog.error(0x0000, TAG, `refreshFormById failed for ${formId}: ${JSON.stringify(error)}`);
      return false;
    }
  }

  async isRegisteredForm(context: Context, formId: string): Promise<boolean> {
    if (!formId || formId.length === 0) {
      return false;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return false;
    }
    return this.loadFormIds().includes(formId);
  }

  private aggregateRecords(records: TimeRecordWithContext[]): SegmentAggregate[] {
    const tagMap = new Map<string, SegmentAggregate>();
    records.forEach((record: TimeRecordWithContext) => {
      const duration = this.resolveDuration(record);
      if (duration <= 0) {
        return;
      }
      const tagKey = record.tagId ?? record.tagName ?? UNTAGGED_ID;
      let aggregate = tagMap.get(tagKey);
      if (!aggregate) {
        aggregate = new SegmentAggregate();
        aggregate.tagId = record.tagId ?? '';
        aggregate.label = record.tagName ?? UNTAGGED_LABEL;
        aggregate.totalDurationMs = 0;
        aggregate.latestStartTimeMs = record.startTimeMs;
        aggregate.colorHex = record.tagColorHex;
        tagMap.set(tagKey, aggregate);
      }

      aggregate.totalDurationMs += duration;
      if (record.startTimeMs > aggregate.latestStartTimeMs) {
        aggregate.latestStartTimeMs = record.startTimeMs;
      }
      if (record.tagColorHex && record.tagColorHex.length > 0) {
        aggregate.colorHex = record.tagColorHex;
      }
    });

    return Array.from(tagMap.values()).filter((item: SegmentAggregate) => item.totalDurationMs > 0);
  }

  private resolveDuration(record: TimeRecordWithContext): number {
    if (record.durationMs !== null && record.durationMs !== undefined) {
      return record.durationMs;
    }
    if (record.endTimeMs !== null) {
      return record.endTimeMs - record.startTimeMs;
    }
    return 0;
  }

  private toSegment(aggregate: SegmentAggregate, totalDurationMs: number): ReflectTodayWidgetSegment {
    const segment = new ReflectTodayWidgetSegment();
    segment.label = aggregate.label;
    segment.durationMs = aggregate.totalDurationMs;
    segment.ratio = totalDurationMs > 0 ? aggregate.totalDurationMs / totalDurationMs : 0;
    segment.colorHex = aggregate.colorHex ?? '';
    return segment;
  }

  private buildFormData(dimension: string, data: ReflectTodayWidgetData): ReflectTodayWidgetFormData {
    return {
      formDimension: dimension,
      reflectTodayWidgetSegments: JSON.stringify(data.segments),
      reflectTodayWidgetTotalDuration: data.totalDurationMs.toString()
    };
  }

  private async ensureDbReady(context: Context): Promise<void> {
    RDBStoreUtil.init(context);
    const store = RDBStoreUtil.getInstance();
    await store.initRDB();
  }

  private async ensurePreferencesReady(context: Context): Promise<boolean> {
    if (preferencesUtil.isInitialized()) {
      return true;
    }
    try {
      await preferencesUtil.init(context, 'todayStore', true);
      return preferencesUtil.isInitialized();
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to initialize preferences for widget refresh: ${JSON.stringify(error)}`);
      return false;
    }
  }

  private loadFormIds(): string[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.REFLECT_TODAY_WIDGET_FORM_IDS, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as string[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed.filter((value: string) => typeof value === 'string' && value.length > 0);
    } catch (error) {
      return [];
    }
  }

  private loadFormEntries(): ReflectTodayWidgetFormEntry[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.REFLECT_TODAY_WIDGET_FORM_DIMENSIONS, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as ReflectTodayWidgetFormEntry[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed.filter((entry: ReflectTodayWidgetFormEntry) =>
        entry
        && typeof entry.formId === 'string'
        && entry.formId.length > 0
        && typeof entry.dimension === 'string'
        && entry.dimension.length > 0
      );
    } catch (error) {
      return [];
    }
  }

  private buildDimensionMap(entries: ReflectTodayWidgetFormEntry[]): Map<string, string> {
    const result = new Map<string, string>();
    entries.forEach((entry: ReflectTodayWidgetFormEntry) => {
      result.set(entry.formId, entry.dimension);
    });
    return result;
  }
}

export const reflectTodayWidgetService = new ReflectTodayWidgetServiceImpl();
