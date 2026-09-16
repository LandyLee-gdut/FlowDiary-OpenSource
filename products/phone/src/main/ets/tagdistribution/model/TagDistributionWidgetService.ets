import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys, preferencesUtil, RDBStoreUtil, TimeRecordUtil, TimeRecordWithContext } from 'base';

const TAG: string = 'TagDistributionWidgetService';
const DAY_MS: number = 24 * 60 * 60 * 1000;
const FORM_DIMENSION_2X2: string = '2*2';
const UNTAGGED_ID: string = '__untagged__';

class TagAggregate {
  tagId: string = '';
  tagName: string = '';
  totalDurationMs: number = 0;
  latestStartTimeMs: number = 0;
  tagColorHex: string | null = null;
}

export class TagDistributionWidgetItem {
  id: string = '';
  name: string = '';
  durationMs: number = 0;
  tagColorHex: string | null = null;
}

export class TagDistributionWidgetData {
  items: TagDistributionWidgetItem[] = [];
}

interface TagDistributionWidgetFormData {
  formDimension: string;
  tagDistributionWidgetItems: string;
}

interface TagDistributionWidgetFormEntry {
  formId: string;
  dimension: string;
}

class TagDistributionWidgetServiceImpl {
  async getTagDistributionWidgetData(context: Context, dateMs?: number): Promise<TagDistributionWidgetData> {
    const data = new TagDistributionWidgetData();
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

      aggregates.sort((a: TagAggregate, b: TagAggregate) => {
        if (b.totalDurationMs !== a.totalDurationMs) {
          return b.totalDurationMs - a.totalDurationMs;
        }
        return b.latestStartTimeMs - a.latestStartTimeMs;
      });

      data.items = aggregates.map((aggregate: TagAggregate) => this.toWidgetItem(aggregate));
      return data;
    } catch (error) {
      hilog.error(0x0000, TAG, `getTagDistributionWidgetData failed: ${JSON.stringify(error)}`);
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
      preferencesUtil.putSync(PreferenceKeys.TAG_DISTRIBUTION_WIDGET_FORM_IDS, JSON.stringify(ids));
    }
    const entries = this.loadFormEntries();
    const existing = entries.find((entry: TagDistributionWidgetFormEntry) => entry.formId === formId);
    if (existing) {
      existing.dimension = dimension;
    } else {
      entries.push({ formId: formId, dimension: dimension });
    }
    preferencesUtil.putSync(PreferenceKeys.TAG_DISTRIBUTION_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
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
    const entries = this.loadFormEntries().filter((entry: TagDistributionWidgetFormEntry) => entry.formId !== formId);
    preferencesUtil.putSync(PreferenceKeys.TAG_DISTRIBUTION_WIDGET_FORM_IDS, JSON.stringify(ids));
    preferencesUtil.putSync(PreferenceKeys.TAG_DISTRIBUTION_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
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
    const data = await this.getTagDistributionWidgetData(context);
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
        const match = entries.find((entry: TagDistributionWidgetFormEntry) => entry.formId === formId);
        if (match) {
          resolvedDimension = match.dimension;
        }
      }
      if (!resolvedDimension || resolvedDimension.length === 0) {
        resolvedDimension = FORM_DIMENSION_2X2;
      }
      const data = await this.getTagDistributionWidgetData(context);
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

  private buildFormData(dimension: string, data: TagDistributionWidgetData): TagDistributionWidgetFormData {
    return {
      formDimension: dimension,
      tagDistributionWidgetItems: JSON.stringify(data.items)
    };
  }

  private aggregateRecords(records: TimeRecordWithContext[]): TagAggregate[] {
    const tagMap = new Map<string, TagAggregate>();
    records.forEach((record: TimeRecordWithContext) => {
      const duration = this.resolveDuration(record);
      if (duration <= 0) {
        return;
      }
      const tagKey = record.tagId ?? UNTAGGED_ID;
      let aggregate = tagMap.get(tagKey);
      if (!aggregate) {
        aggregate = new TagAggregate();
        aggregate.tagId = record.tagId ?? '';
        aggregate.tagName = record.tagName ?? '';
        aggregate.totalDurationMs = 0;
        aggregate.latestStartTimeMs = record.startTimeMs;
        tagMap.set(tagKey, aggregate);
      }

      aggregate.totalDurationMs += duration;
      if (record.startTimeMs > aggregate.latestStartTimeMs) {
        aggregate.latestStartTimeMs = record.startTimeMs;
      }
      if (record.tagColorHex && record.tagColorHex.length > 0) {
        aggregate.tagColorHex = record.tagColorHex;
      }
    });

    return Array.from(tagMap.values()).filter((item: TagAggregate) => item.totalDurationMs > 0);
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

  private toWidgetItem(aggregate: TagAggregate): TagDistributionWidgetItem {
    const item = new TagDistributionWidgetItem();
    item.id = aggregate.tagId && aggregate.tagId.length > 0 ? aggregate.tagId : (aggregate.tagName || UNTAGGED_ID);
    item.name = aggregate.tagName;
    item.durationMs = aggregate.totalDurationMs;
    item.tagColorHex = aggregate.tagColorHex;
    return item;
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
    const raw = preferencesUtil.getSync(PreferenceKeys.TAG_DISTRIBUTION_WIDGET_FORM_IDS, '') as string;
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

  private loadFormEntries(): TagDistributionWidgetFormEntry[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.TAG_DISTRIBUTION_WIDGET_FORM_DIMENSIONS, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as TagDistributionWidgetFormEntry[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed.filter((entry: TagDistributionWidgetFormEntry) =>
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

  private buildDimensionMap(entries: TagDistributionWidgetFormEntry[]): Map<string, string> {
    const result = new Map<string, string>();
    entries.forEach((entry: TagDistributionWidgetFormEntry) => {
      result.set(entry.formId, entry.dimension);
    });
    return result;
  }
}

export const tagDistributionWidgetService = new TagDistributionWidgetServiceImpl();
