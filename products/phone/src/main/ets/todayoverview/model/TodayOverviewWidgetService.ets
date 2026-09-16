import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys, preferencesUtil } from 'base';
import { TodayRecordWidgetData, todayRecordWidgetService } from '../../todayrecordwidget/model/TodayRecordWidgetService';

const TAG: string = 'TodayOverviewWidgetService';
const FORM_DIMENSION_2X2: string = '2*2';

export class TodayOverviewWidgetData {
  totalDurationMs: number = 0;
  itemCount: number = 0;
}

interface TodayOverviewWidgetFormData {
  formDimension: string;
  todayOverviewTotalDuration: string;
  todayOverviewItemCount: string;
}

interface TodayOverviewWidgetFormEntry {
  formId: string;
  dimension: string;
}

class TodayOverviewWidgetServiceImpl {
  async getTodayOverviewWidgetData(context: Context, dateMs?: number): Promise<TodayOverviewWidgetData> {
    const overview: TodayOverviewWidgetData = new TodayOverviewWidgetData();
    try {
      const data: TodayRecordWidgetData = await todayRecordWidgetService.getTodayRecordWidgetData(context, dateMs);
      overview.totalDurationMs = data.totalDurationMs;
      overview.itemCount = data.items.length;
      return overview;
    } catch (error) {
      hilog.error(0x0000, TAG, `getTodayOverviewWidgetData failed: ${JSON.stringify(error)}`);
      return overview;
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
      preferencesUtil.putSync(PreferenceKeys.TODAY_OVERVIEW_WIDGET_FORM_IDS, JSON.stringify(ids));
    }
    const entries = this.loadFormEntries();
    const existing = entries.find((entry: TodayOverviewWidgetFormEntry) => entry.formId === formId);
    if (existing) {
      existing.dimension = dimension;
    } else {
      entries.push({ formId: formId, dimension: dimension });
    }
    preferencesUtil.putSync(PreferenceKeys.TODAY_OVERVIEW_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
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
    const entries = this.loadFormEntries().filter((entry: TodayOverviewWidgetFormEntry) => entry.formId !== formId);
    preferencesUtil.putSync(PreferenceKeys.TODAY_OVERVIEW_WIDGET_FORM_IDS, JSON.stringify(ids));
    preferencesUtil.putSync(PreferenceKeys.TODAY_OVERVIEW_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
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
    const data = await this.getTodayOverviewWidgetData(context);
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
        const match = entries.find((entry: TodayOverviewWidgetFormEntry) => entry.formId === formId);
        if (match) {
          resolvedDimension = match.dimension;
        }
      }
      if (!resolvedDimension || resolvedDimension.length === 0) {
        resolvedDimension = FORM_DIMENSION_2X2;
      }
      const data = await this.getTodayOverviewWidgetData(context);
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

  private buildFormData(dimension: string, data: TodayOverviewWidgetData): TodayOverviewWidgetFormData {
    return {
      formDimension: dimension,
      todayOverviewTotalDuration: data.totalDurationMs.toString(),
      todayOverviewItemCount: data.itemCount.toString()
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
    const raw = preferencesUtil.getSync(PreferenceKeys.TODAY_OVERVIEW_WIDGET_FORM_IDS, '') as string;
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

  private loadFormEntries(): TodayOverviewWidgetFormEntry[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.TODAY_OVERVIEW_WIDGET_FORM_DIMENSIONS, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as TodayOverviewWidgetFormEntry[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed.filter((entry: TodayOverviewWidgetFormEntry) =>
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

  private buildDimensionMap(entries: TodayOverviewWidgetFormEntry[]): Map<string, string> {
    const result = new Map<string, string>();
    entries.forEach((entry: TodayOverviewWidgetFormEntry) => {
      result.set(entry.formId, entry.dimension);
    });
    return result;
  }
}

export const todayOverviewWidgetService = new TodayOverviewWidgetServiceImpl();
