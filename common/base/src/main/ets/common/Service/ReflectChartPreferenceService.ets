import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys } from '../../constants/PreferenceKeys';
import { StorageKeys } from '../../constants/StorageKeys';
import { PreferencesUtil, preferencesUtil } from '../PreferencesUtil';
import {
  ReflectChartSettingItem,
  ReflectChartSettings,
  buildDefaultReflectChartSettings,
  isManagedReflectChartId,
  sanitizeReflectChartSettings
} from '../model/ReflectChartSettings';

const TAG: string = 'ReflectChartPreferenceService';

export class ReflectChartPreferenceService {
  private readonly preferencesUtil: PreferencesUtil = preferencesUtil;

  loadSettings(): ReflectChartSettings {
    return this.readSettings();
  }

  saveSettings(settings: ReflectChartSettings): ReflectChartSettings {
    const current: ReflectChartSettings = this.readSettings();
    const sanitized: ReflectChartSettings = sanitizeReflectChartSettings(settings);
    if (this.areSettingsEqual(current, sanitized)) {
      return current;
    }
    this.persistSettings(sanitized);
    this.bumpRevision();
    return sanitized;
  }

  toggleVisible(chartId: string, visible?: boolean): ReflectChartSettings {
    if (!isManagedReflectChartId(chartId)) {
      return this.readSettings();
    }

    const current: ReflectChartSettings = this.readSettings();
    const sortedItems: ReflectChartSettingItem[] = this.sortItemsByOrder(current.items);
    const target: ReflectChartSettingItem | undefined = sortedItems.find(
      (item: ReflectChartSettingItem) => item.chartId === chartId
    );
    if (!target) {
      return current;
    }

    const targetVisible: boolean = typeof visible === 'boolean' ? visible : !target.visible;
    if (target.visible === targetVisible) {
      return current;
    }

    const nextItems: ReflectChartSettingItem[] = sortedItems.map((item: ReflectChartSettingItem) => {
      return new ReflectChartSettingItem(
        item.chartId,
        item.chartId === chartId ? targetVisible : item.visible,
        item.order
      );
    });

    const nextSettings: ReflectChartSettings = sanitizeReflectChartSettings(
      new ReflectChartSettings(current.version, nextItems)
    );

    this.persistSettings(nextSettings);
    this.bumpRevision();
    return nextSettings;
  }

  isFlowCardGalleryVisible(): boolean {
    return this.readFlowCardGalleryVisible();
  }

  setFlowCardGalleryVisible(visible: boolean): boolean {
    const currentVisible: boolean = this.readFlowCardGalleryVisible();
    if (currentVisible === visible) {
      return currentVisible;
    }
    this.persistFlowCardGalleryVisible(visible);
    this.bumpRevision();
    return visible;
  }

  reorderVisibleCharts(chartIds: string[]): ReflectChartSettings {
    const current: ReflectChartSettings = this.readSettings();
    const sortedItems: ReflectChartSettingItem[] = this.sortItemsByOrder(current.items);
    const visibleChartIds: string[] = sortedItems
      .filter((item: ReflectChartSettingItem) => item.visible)
      .map((item: ReflectChartSettingItem) => item.chartId);

    if (visibleChartIds.length <= 1) {
      return current;
    }

    const requestedVisibleChartIds: string[] = [];
    const seen: Set<string> = new Set();
    chartIds.forEach((chartId: string) => {
      if (!isManagedReflectChartId(chartId)) {
        return;
      }
      if (!visibleChartIds.some((id: string) => id === chartId)) {
        return;
      }
      if (seen.has(chartId)) {
        return;
      }
      requestedVisibleChartIds.push(chartId);
      seen.add(chartId);
    });

    visibleChartIds.forEach((chartId: string) => {
      if (seen.has(chartId)) {
        return;
      }
      requestedVisibleChartIds.push(chartId);
      seen.add(chartId);
    });

    const hiddenChartIds: string[] = sortedItems
      .filter((item: ReflectChartSettingItem) => !item.visible)
      .map((item: ReflectChartSettingItem) => item.chartId);
    const orderedChartIds: string[] = [...requestedVisibleChartIds, ...hiddenChartIds];
    const orderMap: Map<string, number> = new Map();
    orderedChartIds.forEach((chartId: string, index: number) => {
      orderMap.set(chartId, index);
    });

    const nextItems: ReflectChartSettingItem[] = sortedItems.map((item: ReflectChartSettingItem) => {
      const nextOrder: number | undefined = orderMap.get(item.chartId);
      return new ReflectChartSettingItem(
        item.chartId,
        item.visible,
        nextOrder === undefined ? item.order : nextOrder
      );
    });
    const nextSettings: ReflectChartSettings = sanitizeReflectChartSettings(
      new ReflectChartSettings(current.version, nextItems)
    );

    if (this.areSettingsEqual(current, nextSettings)) {
      return current;
    }

    this.persistSettings(nextSettings);
    this.bumpRevision();
    return nextSettings;
  }

  resetToDefault(): ReflectChartSettings {
    const defaults: ReflectChartSettings = buildDefaultReflectChartSettings();
    this.persistSettings(defaults);
    this.persistFlowCardGalleryVisible(true);
    this.bumpRevision();
    return defaults;
  }

  private readSettings(): ReflectChartSettings {
    const store = this.preferencesUtil.getPreferences();
    if (!store) {
      hilog.warn(0x0000, TAG, '[ReflectChartPreferenceService] Preferences not initialized, fallback to defaults');
      return buildDefaultReflectChartSettings();
    }

    try {
      if (!store.hasSync(PreferenceKeys.REFLECT_CHART_SETTINGS_V2)) {
        const defaults: ReflectChartSettings = buildDefaultReflectChartSettings();
        this.persistSettings(defaults, store);
        return defaults;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[ReflectChartPreferenceService] hasSync failed: ${JSON.stringify(error)}`);
      return buildDefaultReflectChartSettings();
    }

    const rawValue: string = store.getSync(PreferenceKeys.REFLECT_CHART_SETTINGS_V2, '') as string;
    const parsed: ReflectChartSettings | undefined = this.deserialize(rawValue);
    const sanitized: ReflectChartSettings = sanitizeReflectChartSettings(parsed);

    if (!parsed || !this.areSettingsEqual(parsed, sanitized)) {
      this.persistSettings(sanitized, store);
    }

    return sanitized;
  }

  private persistSettings(settings: ReflectChartSettings, preferenceStore?: preferences.Preferences): void {
    const store = preferenceStore ?? this.preferencesUtil.getPreferences();
    if (!store) {
      hilog.warn(0x0000, TAG, '[ReflectChartPreferenceService] Preferences not initialized, skip persist');
      return;
    }

    const sanitized: ReflectChartSettings = sanitizeReflectChartSettings(settings);
    const serialized: string = JSON.stringify(sanitized);
    try {
      store.putSync(PreferenceKeys.REFLECT_CHART_SETTINGS_V2, serialized);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[ReflectChartPreferenceService] persist failed: ${JSON.stringify(error)}`);
    }
  }

  private readFlowCardGalleryVisible(): boolean {
    const store = this.preferencesUtil.getPreferences();
    if (!store) {
      hilog.warn(0x0000, TAG, '[ReflectChartPreferenceService] Preferences not initialized, fallback flow card gallery visible=true');
      return true;
    }
    try {
      const rawValue: preferences.ValueType = store.getSync(PreferenceKeys.REFLECT_FLOW_CARD_GALLERY_VISIBLE, true);
      if (typeof rawValue === 'boolean') {
        return rawValue;
      }
      this.persistFlowCardGalleryVisible(true, store);
      return true;
    } catch (error) {
      hilog.error(0x0000, TAG, `[ReflectChartPreferenceService] flow card gallery visible read failed: ${JSON.stringify(error)}`);
      return true;
    }
  }

  private persistFlowCardGalleryVisible(visible: boolean, preferenceStore?: preferences.Preferences): void {
    const store = preferenceStore ?? this.preferencesUtil.getPreferences();
    if (!store) {
      hilog.warn(0x0000, TAG, '[ReflectChartPreferenceService] Preferences not initialized, skip flow card gallery visible persist');
      return;
    }
    try {
      store.putSync(PreferenceKeys.REFLECT_FLOW_CARD_GALLERY_VISIBLE, visible);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[ReflectChartPreferenceService] flow card gallery visible persist failed: ${JSON.stringify(error)}`);
    }
  }

  private deserialize(rawValue: string): ReflectChartSettings | undefined {
    if (!rawValue || rawValue.length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(rawValue) as ReflectChartSettings;
    } catch (error) {
      hilog.error(0x0000, TAG, `[ReflectChartPreferenceService] deserialize failed: ${JSON.stringify(error)}`);
      return undefined;
    }
  }

  private sortItemsByOrder(items: ReflectChartSettingItem[]): ReflectChartSettingItem[] {
    return items
      .map((item: ReflectChartSettingItem) => new ReflectChartSettingItem(item.chartId, item.visible, item.order))
      .sort((left: ReflectChartSettingItem, right: ReflectChartSettingItem) => {
        if (left.order !== right.order) {
          return left.order - right.order;
        }
        return left.chartId.localeCompare(right.chartId);
      });
  }

  private areSettingsEqual(left: ReflectChartSettings, right: ReflectChartSettings): boolean {
    if (left.version !== right.version) {
      return false;
    }
    if (left.items.length !== right.items.length) {
      return false;
    }
    for (let index = 0; index < left.items.length; index += 1) {
      const leftItem: ReflectChartSettingItem = left.items[index];
      const rightItem: ReflectChartSettingItem = right.items[index];
      if (leftItem.chartId !== rightItem.chartId) {
        return false;
      }
      if (leftItem.visible !== rightItem.visible) {
        return false;
      }
      if (leftItem.order !== rightItem.order) {
        return false;
      }
    }
    return true;
  }

  private bumpRevision(): void {
    const currentRevision: number | undefined = AppStorage.get(StorageKeys.REFLECT_CHART_SETTINGS_REVISION) as number | undefined;
    if (currentRevision !== undefined) {
      AppStorage.set(StorageKeys.REFLECT_CHART_SETTINGS_REVISION, currentRevision + 1);
      return;
    }
    AppStorage.setOrCreate(StorageKeys.REFLECT_CHART_SETTINGS_REVISION, 1);
  }
}

export const reflectChartPreferenceService: ReflectChartPreferenceService = new ReflectChartPreferenceService();
