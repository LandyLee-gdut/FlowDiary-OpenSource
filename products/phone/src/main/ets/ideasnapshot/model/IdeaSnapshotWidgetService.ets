import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IdeaActivity, IdeaLightState, PreferenceKeys, preferencesUtil, RDBStoreUtil } from 'base';

const TAG: string = 'IdeaSnapshotWidgetService';
const FORM_DIMENSION_2X2: string = '2*2';

export class IdeaSnapshotWidgetData {
  unlitCount: number = 0;
  latestIdeaTitle: string = '';
}

interface IdeaSnapshotWidgetFormData {
  formDimension: string;
  ideaSnapshotUnlitCount: string;
  ideaSnapshotLatestTitle: string;
}

interface IdeaSnapshotWidgetFormEntry {
  formId: string;
  dimension: string;
}

interface IdeaSnapshotSummary {
  unlitCount: number;
  latestTitle: string;
}

class IdeaSnapshotWidgetServiceImpl {
  async getIdeaSnapshotWidgetData(context: Context): Promise<IdeaSnapshotWidgetData> {
    const data = new IdeaSnapshotWidgetData();
    try {
      await this.ensureDbReady(context);
      const store = RDBStoreUtil.getInstance();
      const activities = await store.queryIdeaPoolActivities();
      if (!activities || activities.length === 0) {
        return data;
      }
      const summary = this.buildSummary(activities);
      data.unlitCount = summary.unlitCount;
      data.latestIdeaTitle = summary.latestTitle;
      return data;
    } catch (error) {
      hilog.error(0x0000, TAG, `getIdeaSnapshotWidgetData failed: ${JSON.stringify(error)}`);
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
      preferencesUtil.putSync(PreferenceKeys.IDEA_SNAPSHOT_WIDGET_FORM_IDS, JSON.stringify(ids));
    }
    const entries = this.loadFormEntries();
    const existing = entries.find((entry: IdeaSnapshotWidgetFormEntry) => entry.formId === formId);
    if (existing) {
      existing.dimension = dimension;
    } else {
      entries.push({ formId: formId, dimension: dimension });
    }
    preferencesUtil.putSync(PreferenceKeys.IDEA_SNAPSHOT_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
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
    const entries = this.loadFormEntries().filter((entry: IdeaSnapshotWidgetFormEntry) => entry.formId !== formId);
    preferencesUtil.putSync(PreferenceKeys.IDEA_SNAPSHOT_WIDGET_FORM_IDS, JSON.stringify(ids));
    preferencesUtil.putSync(PreferenceKeys.IDEA_SNAPSHOT_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
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
    const data = await this.getIdeaSnapshotWidgetData(context);
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
        const match = entries.find((entry: IdeaSnapshotWidgetFormEntry) => entry.formId === formId);
        if (match) {
          resolvedDimension = match.dimension;
        }
      }
      if (!resolvedDimension || resolvedDimension.length === 0) {
        resolvedDimension = FORM_DIMENSION_2X2;
      }
      const data = await this.getIdeaSnapshotWidgetData(context);
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

  private buildSummary(activities: IdeaActivity[]): IdeaSnapshotSummary {
    let unlitCount: number = 0;
    let latestTitle: string = '';
    let latestTimestamp: number = -1;
    let latestUnlitTitle: string = '';
    let latestUnlitTimestamp: number = -1;

    activities.forEach((activity: IdeaActivity) => {
      const timestamp = activity.updatedAt > 0 ? activity.updatedAt : activity.createdAt;
      if (timestamp > latestTimestamp) {
        latestTimestamp = timestamp;
        latestTitle = activity.name || '';
      }
      if (activity.ideaLightState === IdeaLightState.UNLIT) {
        unlitCount += 1;
        if (timestamp > latestUnlitTimestamp) {
          latestUnlitTimestamp = timestamp;
          latestUnlitTitle = activity.name || '';
        }
      }
    });

    return {
      unlitCount: unlitCount,
      latestTitle: latestUnlitTimestamp >= 0 ? latestUnlitTitle : latestTitle
    };
  }

  private buildFormData(dimension: string, data: IdeaSnapshotWidgetData): IdeaSnapshotWidgetFormData {
    return {
      formDimension: dimension,
      ideaSnapshotUnlitCount: data.unlitCount.toString(),
      ideaSnapshotLatestTitle: data.latestIdeaTitle
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
    const raw = preferencesUtil.getSync(PreferenceKeys.IDEA_SNAPSHOT_WIDGET_FORM_IDS, '') as string;
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

  private loadFormEntries(): IdeaSnapshotWidgetFormEntry[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.IDEA_SNAPSHOT_WIDGET_FORM_DIMENSIONS, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as IdeaSnapshotWidgetFormEntry[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed.filter((entry: IdeaSnapshotWidgetFormEntry) =>
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

  private buildDimensionMap(entries: IdeaSnapshotWidgetFormEntry[]): Map<string, string> {
    const result = new Map<string, string>();
    entries.forEach((entry: IdeaSnapshotWidgetFormEntry) => {
      result.set(entry.formId, entry.dimension);
    });
    return result;
  }
}

export const ideaSnapshotWidgetService = new IdeaSnapshotWidgetServiceImpl();
