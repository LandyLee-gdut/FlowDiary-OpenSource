import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys, preferencesUtil, RDBStoreUtil, TimeRecordUtil, TimeRecordWithContext } from 'base';

const TAG: string = 'TodayRecordWidgetService';
const DAY_MS: number = 24 * 60 * 60 * 1000;
const FORM_DIMENSION_2X2: string = '2*2';

class ActivityAggregate {
  activityId: string = '';
  title: string = '';
  totalDurationMs: number = 0;
  latestStartTimeMs: number = 0;
  tagColorHex: string | null = null;
}

export class TodayRecordWidgetItem {
  id: string = '';
  name: string = '';
  durationMs: number = 0;
  tagColorHex: string | null = null;
}

export class TodayRecordWidgetData {
  items: TodayRecordWidgetItem[] = [];
  totalDurationMs: number = 0;
}

interface TodayRecordWidgetFormData {
  formDimension: string;
  todayRecordWidgetItems: string;
  todayRecordWidgetTotalDuration: string;
}

interface TodayRecordWidgetFormEntry {
  formId: string;
  dimension: string;
}

class TodayRecordWidgetServiceImpl {
  async getTodayRecordWidgetData(context: Context, dateMs?: number): Promise<TodayRecordWidgetData> {
    const data: TodayRecordWidgetData = new TodayRecordWidgetData();

    try {
      await this.ensureDbReady(context);
      const now = dateMs ?? Date.now();
      const dayStart = TimeRecordUtil.getDayStart(now);
      const dayEnd = dayStart + DAY_MS - 1;
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const records = await rdbStoreUtil.queryTimeRecordsWithActivityAndTag(dayStart, dayEnd);

      if (!records || records.length === 0) {
        return data;
      }

      const aggregates = this.aggregateRecords(records);
      if (aggregates.length === 0) {
        return data;
      }

      aggregates.sort((a: ActivityAggregate, b: ActivityAggregate) => {
        if (b.totalDurationMs !== a.totalDurationMs) {
          return b.totalDurationMs - a.totalDurationMs;
        }
        return b.latestStartTimeMs - a.latestStartTimeMs;
      });

      data.totalDurationMs = this.sumTotalDuration(aggregates);
      data.items = aggregates.map((aggregate: ActivityAggregate) => this.toWidgetItem(aggregate));
      return data;
    } catch (error) {
      hilog.error(0x0000, TAG, `getTodayRecordWidgetData failed: ${JSON.stringify(error)}`);
      return data;
    }
  }

  private async ensureDbReady(context: Context): Promise<void> {
    RDBStoreUtil.init(context);
    const rdbStoreUtil = RDBStoreUtil.getInstance();
    await rdbStoreUtil.initRDB();
  }

  private sumTotalDuration(aggregates: ActivityAggregate[]): number {
    let total: number = 0;
    aggregates.forEach((item: ActivityAggregate) => {
      total += item.totalDurationMs;
    });
    return total;
  }

  private aggregateRecords(records: TimeRecordWithContext[]): ActivityAggregate[] {
    const activityMap = new Map<string, ActivityAggregate>();

    records.forEach((record: TimeRecordWithContext) => {
      const duration = this.resolveDuration(record);
      if (duration <= 0) {
        return;
      }

      const activityId = record.activityId;
      if (!activityId || activityId.length === 0) {
        return;
      }

      const title = record.activityName && record.activityName.length > 0 ? record.activityName : '';
      let aggregate = activityMap.get(activityId);
      if (!aggregate) {
        aggregate = new ActivityAggregate();
        aggregate.activityId = activityId;
        aggregate.title = title;
        aggregate.totalDurationMs = 0;
        aggregate.latestStartTimeMs = record.startTimeMs;
        activityMap.set(activityId, aggregate);
      }

      aggregate.totalDurationMs += duration;
      if (record.startTimeMs > aggregate.latestStartTimeMs) {
        aggregate.latestStartTimeMs = record.startTimeMs;
      }
      if (record.tagColorHex && record.tagColorHex.length > 0) {
        aggregate.tagColorHex = record.tagColorHex;
      }
    });

    return Array.from(activityMap.values()).filter((item: ActivityAggregate) => item.totalDurationMs > 0);
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

  private toWidgetItem(aggregate: ActivityAggregate): TodayRecordWidgetItem {
    const item = new TodayRecordWidgetItem();
    item.id = aggregate.activityId;
    item.name = aggregate.title;
    item.durationMs = aggregate.totalDurationMs;
    item.tagColorHex = aggregate.tagColorHex;
    return item;
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
    }
    const entries = this.loadFormEntries();
    const existingIndex = entries.findIndex((entry: TodayRecordWidgetFormEntry) => entry.formId === formId);
    if (existingIndex >= 0) {
      entries[existingIndex] = { formId: formId, dimension: dimension };
    } else {
      entries.push({ formId: formId, dimension: dimension });
    }
    preferencesUtil.putSync(PreferenceKeys.TODAY_RECORD_WIDGET_FORM_IDS, JSON.stringify(ids));
    preferencesUtil.putSync(PreferenceKeys.TODAY_RECORD_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
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
    const entries = this.loadFormEntries().filter((entry: TodayRecordWidgetFormEntry) => entry.formId !== formId);
    preferencesUtil.putSync(PreferenceKeys.TODAY_RECORD_WIDGET_FORM_IDS, JSON.stringify(ids));
    preferencesUtil.putSync(PreferenceKeys.TODAY_RECORD_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
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
    const data = await this.getTodayRecordWidgetData(context);
    for (const formId of formIds) {
      const dimension = dimensionMap.get(formId) ?? FORM_DIMENSION_2X2;
      try {
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

    let resolvedDimension = dimension;
    if (!resolvedDimension || resolvedDimension.length === 0) {
      const ready = await this.ensurePreferencesReady(context);
      if (ready) {
        const entries = this.loadFormEntries();
        const match = entries.find((entry: TodayRecordWidgetFormEntry) => entry.formId === formId);
        if (match) {
          resolvedDimension = match.dimension;
        }
      }
    }

    if (!resolvedDimension || resolvedDimension.length === 0) {
      resolvedDimension = FORM_DIMENSION_2X2;
    }

    try {
      const data = await this.getTodayRecordWidgetData(context);
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

  private buildFormData(dimension: string, data: TodayRecordWidgetData): TodayRecordWidgetFormData {
    return {
      formDimension: dimension,
      todayRecordWidgetItems: JSON.stringify(data.items),
      todayRecordWidgetTotalDuration: data.totalDurationMs.toString()
    };
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
    const raw = preferencesUtil.getSync(PreferenceKeys.TODAY_RECORD_WIDGET_FORM_IDS, '') as string;
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

  private loadFormEntries(): TodayRecordWidgetFormEntry[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.TODAY_RECORD_WIDGET_FORM_DIMENSIONS, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as TodayRecordWidgetFormEntry[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed.filter((entry: TodayRecordWidgetFormEntry) =>
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

  private buildDimensionMap(entries: TodayRecordWidgetFormEntry[]): Map<string, string> {
    const result = new Map<string, string>();
    entries.forEach((entry: TodayRecordWidgetFormEntry) => {
      result.set(entry.formId, entry.dimension);
    });
    return result;
  }
}

export const todayRecordWidgetService = new TodayRecordWidgetServiceImpl();
