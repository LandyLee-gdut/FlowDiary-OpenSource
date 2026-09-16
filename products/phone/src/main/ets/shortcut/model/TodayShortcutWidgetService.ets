import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys, preferencesUtil } from 'base';

const TAG: string = 'TodayShortcutWidgetService';
const DOMAIN: number = 0x0000;
const FORM_DIMENSION_1X2: string = '1*2';
const FORM_DIMENSION_2X2: string = '2*2';

export class TodayShortcutBindingData {
  activityName: string = '';
  tagId: string = '';
  tagName: string = '';
  tagColor: string = '';
  tagLightColor: string = '';
  autoStart: boolean = false;
}

export class TodayShortcutWidgetData {
  formDimension: string = FORM_DIMENSION_2X2;
  binding: TodayShortcutBindingData | null = null;
}

interface TodayShortcutWidgetFormData {
  formDimension: string;
  todayShortcutBinding: string;
}

interface TodayShortcutWidgetFormEntry {
  formId: string;
  dimension: string;
}

interface TodayShortcutBindingEntry {
  formId: string;
  binding: TodayShortcutBindingData;
}

class TodayShortcutWidgetServiceImpl {
  async registerForm(context: Context, formId: string, dimension: string): Promise<void> {
    hilog.info(DOMAIN, TAG, `today shortcut registerForm start, formId=${formId}, dimension=${dimension}`);
    if (!formId || formId.length === 0) {
      hilog.info(DOMAIN, TAG, 'today shortcut registerForm skipped: formId is empty');
      return;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      hilog.error(DOMAIN, TAG, `today shortcut registerForm failed: preferences not ready, formId=${formId}`);
      return;
    }

    const ids = this.loadFormIds();
    if (!ids.includes(formId)) {
      ids.push(formId);
      preferencesUtil.putSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_IDS, JSON.stringify(ids));
    }

    const entries = this.loadFormEntries();
    const normalizedDimension = this.normalizeDimension(dimension);
    const existing = entries.find((entry: TodayShortcutWidgetFormEntry) => entry.formId === formId);
    if (existing) {
      existing.dimension = normalizedDimension;
    } else {
      entries.push({
        formId: formId,
        dimension: normalizedDimension
      });
    }
    preferencesUtil.putSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
    hilog.info(DOMAIN, TAG,
      `today shortcut registerForm done, formId=${formId}, idsCount=${ids.length}, entriesCount=${entries.length}`);
  }

  async unregisterForm(context: Context, formId: string): Promise<void> {
    hilog.info(DOMAIN, TAG, `today shortcut unregisterForm start, formId=${formId}`);
    if (!formId || formId.length === 0) {
      hilog.info(DOMAIN, TAG, 'today shortcut unregisterForm skipped: formId is empty');
      return;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      hilog.error(DOMAIN, TAG, `today shortcut unregisterForm failed: preferences not ready, formId=${formId}`);
      return;
    }

    const ids = this.loadFormIds().filter((id: string) => id !== formId);
    const entries = this.loadFormEntries().filter((entry: TodayShortcutWidgetFormEntry) => entry.formId !== formId);
    const bindings = this.loadBindingEntries().filter((entry: TodayShortcutBindingEntry) => entry.formId !== formId);
    preferencesUtil.putSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_IDS, JSON.stringify(ids));
    preferencesUtil.putSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));
    preferencesUtil.putSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_BINDINGS, JSON.stringify(bindings));
    hilog.info(DOMAIN, TAG,
      `today shortcut unregisterForm done, formId=${formId}, idsCount=${ids.length}, entriesCount=${entries.length}, bindingsCount=${bindings.length}`);
  }

  async saveBinding(
    context: Context,
    formId: string,
    binding: TodayShortcutBindingData | null,
    dimension?: string
  ): Promise<boolean> {
    hilog.info(DOMAIN, TAG,
      `today shortcut saveBinding start, formId=${formId}, dimension=${dimension ?? ''}, hasBinding=${binding !== null}`);
    if (!formId || formId.length === 0) {
      hilog.error(DOMAIN, TAG, 'today shortcut saveBinding failed: formId is empty');
      return false;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      hilog.error(DOMAIN, TAG, `today shortcut saveBinding failed: preferences not ready, formId=${formId}`);
      return false;
    }

    const ids = this.loadFormIds();
    if (!ids.includes(formId)) {
      ids.push(formId);
      preferencesUtil.putSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_IDS, JSON.stringify(ids));
    }

    const entries = this.loadFormEntries();
    const normalizedDimension = this.normalizeDimension(dimension);
    const existingEntry = entries.find((entry: TodayShortcutWidgetFormEntry) => entry.formId === formId);
    if (existingEntry) {
      existingEntry.dimension = normalizedDimension;
    } else {
      entries.push({
        formId: formId,
        dimension: normalizedDimension
      });
    }
    preferencesUtil.putSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_DIMENSIONS, JSON.stringify(entries));

    const normalizedBinding = this.normalizeBinding(binding);
    hilog.info(DOMAIN, TAG,
      `today shortcut saveBinding normalized binding, formId=${formId}, hasNormalizedBinding=${normalizedBinding !== null}`);
    const bindings = this.loadBindingEntries().filter((entry: TodayShortcutBindingEntry) => entry.formId !== formId);
    if (normalizedBinding) {
      bindings.push({
        formId: formId,
        binding: normalizedBinding
      });
      hilog.info(DOMAIN, TAG,
        `today shortcut saveBinding prepared binding payload, formId=${formId}, activityNameLength=${normalizedBinding.activityName.length}, tagId=${normalizedBinding.tagId}, autoStart=${normalizedBinding.autoStart}`);
    }
    preferencesUtil.putSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_BINDINGS, JSON.stringify(bindings));
    const persistedBinding = this.loadBindingEntries().find((entry: TodayShortcutBindingEntry) => entry.formId === formId);
    hilog.info(DOMAIN, TAG,
      `today shortcut saveBinding done, formId=${formId}, idsCount=${ids.length}, entriesCount=${entries.length}, bindingsCount=${bindings.length}, persisted=${persistedBinding !== undefined}`);
    return true;
  }

  async getBinding(context: Context, formId: string): Promise<TodayShortcutBindingData | null> {
    hilog.info(DOMAIN, TAG, `today shortcut getBinding start, formId=${formId}`);
    if (!formId || formId.length === 0) {
      hilog.info(DOMAIN, TAG, 'today shortcut getBinding skipped: formId is empty');
      return null;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      hilog.error(DOMAIN, TAG, `today shortcut getBinding failed: preferences not ready, formId=${formId}`);
      return null;
    }
    const entries = this.loadBindingEntries();
    const existing = entries.find((entry: TodayShortcutBindingEntry) => entry.formId === formId);
    if (!existing) {
      hilog.info(DOMAIN, TAG, `today shortcut getBinding not found, formId=${formId}`);
      return null;
    }
    hilog.info(DOMAIN, TAG,
      `today shortcut getBinding success, formId=${formId}, activityNameLength=${existing.binding.activityName.length}, tagId=${existing.binding.tagId}, autoStart=${existing.binding.autoStart}`);
    return existing.binding;
  }

  async getWidgetData(
    context: Context,
    formId: string,
    dimension?: string
  ): Promise<TodayShortcutWidgetData> {
    const data = new TodayShortcutWidgetData();
    hilog.info(DOMAIN, TAG,
      `today shortcut getWidgetData start, formId=${formId}, inputDimension=${dimension ?? ''}`);
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      hilog.error(DOMAIN, TAG, `today shortcut getWidgetData failed: preferences not ready, formId=${formId}`);
      return data;
    }
    data.formDimension = this.resolveDimensionByFormId(formId, dimension);
    data.binding = await this.getBinding(context, formId);
    hilog.info(DOMAIN, TAG,
      `today shortcut getWidgetData done, formId=${formId}, resolvedDimension=${data.formDimension}, hasBinding=${data.binding !== null}`);
    return data;
  }

  async refreshRegisteredForms(context: Context): Promise<void> {
    hilog.info(DOMAIN, TAG, 'today shortcut refreshRegisteredForms start');
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      hilog.error(DOMAIN, TAG, 'today shortcut refreshRegisteredForms aborted: preferences not ready');
      return;
    }
    const ids = this.loadFormIds();
    if (ids.length === 0) {
      hilog.info(DOMAIN, TAG, 'today shortcut refreshRegisteredForms skipped: no registered form ids');
      return;
    }
    const dimensionMap = this.buildDimensionMap(this.loadFormEntries());
    const bindingMap = this.buildBindingMap(this.loadBindingEntries());
    for (const formId of ids) {
      try {
        const dimension = dimensionMap.get(formId) ?? FORM_DIMENSION_2X2;
        const binding = bindingMap.get(formId) ?? null;
        const formData = this.buildFormData(dimension, binding);
        const providerData = formBindingData.createFormBindingData(formData);
        await formProvider.updateForm(formId, providerData);
        hilog.info(DOMAIN, TAG,
          `today shortcut refreshRegisteredForms updated form, formId=${formId}, dimension=${dimension}, hasBinding=${binding !== null}`);
      } catch (error) {
        hilog.error(DOMAIN, TAG, `today shortcut refreshRegisteredForms failed for ${formId}: ${JSON.stringify(error)}`);
      }
    }
  }

  async refreshFormById(context: Context, formId: string, dimension?: string): Promise<boolean> {
    hilog.info(DOMAIN, TAG,
      `today shortcut refreshFormById start, formId=${formId}, inputDimension=${dimension ?? ''}`);
    if (!formId || formId.length === 0) {
      hilog.error(DOMAIN, TAG, 'today shortcut refreshFormById failed: formId is empty');
      return false;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      hilog.error(DOMAIN, TAG, `today shortcut refreshFormById failed: preferences not ready, formId=${formId}`);
      return false;
    }
    const ids = this.loadFormIds();
    if (!ids.includes(formId)) {
      hilog.error(DOMAIN, TAG,
        `today shortcut refreshFormById failed: formId not registered, formId=${formId}, registeredCount=${ids.length}`);
      return false;
    }
    try {
      const resolvedDimension = this.resolveDimensionByFormId(formId, dimension);
      const binding = await this.getBinding(context, formId);
      const formData = this.buildFormData(resolvedDimension, binding);
      const providerData = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, providerData);
      hilog.info(DOMAIN, TAG,
        `today shortcut refreshFormById success, formId=${formId}, resolvedDimension=${resolvedDimension}, hasBinding=${binding !== null}`);
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `today shortcut refreshFormById failed for ${formId}: ${JSON.stringify(error)}`);
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

  private buildFormData(
    dimension: string,
    binding: TodayShortcutBindingData | null
  ): TodayShortcutWidgetFormData {
    return {
      formDimension: this.normalizeDimension(dimension),
      todayShortcutBinding: binding ? JSON.stringify(binding) : ''
    };
  }

  private resolveDimensionByFormId(formId: string, dimension?: string): string {
    if (dimension && dimension.length > 0) {
      return this.normalizeDimension(dimension);
    }
    const entries = this.loadFormEntries();
    const existing = entries.find((entry: TodayShortcutWidgetFormEntry) => entry.formId === formId);
    if (!existing) {
      return FORM_DIMENSION_2X2;
    }
    return this.normalizeDimension(existing.dimension);
  }

  private normalizeDimension(dimension?: string): string {
    if (dimension === FORM_DIMENSION_1X2) {
      return FORM_DIMENSION_1X2;
    }
    return FORM_DIMENSION_2X2;
  }

  private normalizeBinding(rawBinding: TodayShortcutBindingData | null): TodayShortcutBindingData | null {
    if (!rawBinding) {
      hilog.info(DOMAIN, TAG, 'today shortcut normalizeBinding returns null: raw binding is null');
      return null;
    }
    const activityName = rawBinding.activityName ? rawBinding.activityName.trim() : '';
    if (activityName.length === 0) {
      hilog.info(DOMAIN, TAG, 'today shortcut normalizeBinding returns null: activityName empty after trim');
      return null;
    }
    const binding = new TodayShortcutBindingData();
    binding.activityName = activityName;
    binding.tagId = rawBinding.tagId ? rawBinding.tagId : '';
    binding.tagName = rawBinding.tagName ? rawBinding.tagName : '';
    binding.tagColor = rawBinding.tagColor ? rawBinding.tagColor : '';
    binding.tagLightColor = rawBinding.tagLightColor ? rawBinding.tagLightColor : '';
    binding.autoStart = !!rawBinding.autoStart;
    return binding;
  }

  private async ensurePreferencesReady(context: Context): Promise<boolean> {
    if (preferencesUtil.isInitialized()) {
      hilog.info(DOMAIN, TAG, 'today shortcut ensurePreferencesReady: preferences already initialized');
      return true;
    }
    try {
      hilog.info(DOMAIN, TAG, 'today shortcut ensurePreferencesReady: initializing preferences');
      await preferencesUtil.init(context, 'todayStore', true);
      const initialized = preferencesUtil.isInitialized();
      hilog.info(DOMAIN, TAG, `today shortcut ensurePreferencesReady result=${initialized}`);
      return initialized;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `today shortcut ensurePreferencesReady failed: ${JSON.stringify(error)}`);
      return false;
    }
  }

  private loadFormIds(): string[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_IDS, '') as string;
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
      hilog.error(DOMAIN, TAG, `today shortcut loadFormIds parse failed: ${JSON.stringify(error)}`);
      return [];
    }
  }

  private loadFormEntries(): TodayShortcutWidgetFormEntry[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_DIMENSIONS, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as TodayShortcutWidgetFormEntry[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: TodayShortcutWidgetFormEntry[] = [];
      parsed.forEach((entry: TodayShortcutWidgetFormEntry) => {
        if (!entry || typeof entry.formId !== 'string' || entry.formId.length === 0) {
          return;
        }
        if (typeof entry.dimension !== 'string' || entry.dimension.length === 0) {
          return;
        }
        result.push({
          formId: entry.formId,
          dimension: this.normalizeDimension(entry.dimension)
        });
      });
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `today shortcut loadFormEntries parse failed: ${JSON.stringify(error)}`);
      return [];
    }
  }

  private loadBindingEntries(): TodayShortcutBindingEntry[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.SHORTCUT_WIDGET_FORM_BINDINGS, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as TodayShortcutBindingEntry[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: TodayShortcutBindingEntry[] = [];
      parsed.forEach((entry: TodayShortcutBindingEntry) => {
        if (!entry || typeof entry.formId !== 'string' || entry.formId.length === 0) {
          return;
        }
        const normalized = this.normalizeBinding(entry.binding);
        if (!normalized) {
          return;
        }
        result.push({
          formId: entry.formId,
          binding: normalized
        });
      });
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `today shortcut loadBindingEntries parse failed: ${JSON.stringify(error)}`);
      return [];
    }
  }

  private buildDimensionMap(entries: TodayShortcutWidgetFormEntry[]): Map<string, string> {
    const map = new Map<string, string>();
    entries.forEach((entry: TodayShortcutWidgetFormEntry) => {
      map.set(entry.formId, this.normalizeDimension(entry.dimension));
    });
    return map;
  }

  private buildBindingMap(entries: TodayShortcutBindingEntry[]): Map<string, TodayShortcutBindingData> {
    const map = new Map<string, TodayShortcutBindingData>();
    entries.forEach((entry: TodayShortcutBindingEntry) => {
      map.set(entry.formId, entry.binding);
    });
    return map;
  }
}

export const todayShortcutWidgetService = new TodayShortcutWidgetServiceImpl();
