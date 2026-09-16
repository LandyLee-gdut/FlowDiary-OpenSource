export class ReflectChartIds {
  // Fixed section item: always visible, excluded from sortable/toggleable chart settings.
  static readonly MINI_CALENDAR: string = 'MINI_CALENDAR';

  // Configurable chart ids (V2 baseline order).
  static readonly TIMELINE: string = 'TIMELINE';
  static readonly DAY_REVIEW: string = 'DAY_REVIEW';
  static readonly TAG_TREND: string = 'TAG_TREND';
  static readonly TAG_TIME_BAR: string = 'TAG_TIME_BAR';
  static readonly WEEKLY_REVIEW: string = 'WEEKLY_REVIEW';
}

@Observed
export class ReflectChartSettingItem {
  chartId: string;
  visible: boolean;
  order: number;

  constructor(chartId: string, visible: boolean, order: number) {
    this.chartId = chartId;
    this.visible = visible;
    this.order = order;
  }
}

export class ReflectChartSettings {
  version: number;
  items: ReflectChartSettingItem[];

  constructor(version: number, items: ReflectChartSettingItem[]) {
    this.version = version;
    this.items = items;
  }
}

export const REFLECT_CHART_SETTINGS_VERSION: number = 2;

const MANAGED_CHART_IDS: string[] = [
  ReflectChartIds.TIMELINE,
  ReflectChartIds.DAY_REVIEW,
  ReflectChartIds.TAG_TREND,
  ReflectChartIds.TAG_TIME_BAR,
  ReflectChartIds.WEEKLY_REVIEW
];

const DEFAULT_CHART_ITEMS: ReflectChartSettingItem[] = [
  new ReflectChartSettingItem(ReflectChartIds.TIMELINE, true, 0),
  new ReflectChartSettingItem(ReflectChartIds.DAY_REVIEW, true, 1),
  new ReflectChartSettingItem(ReflectChartIds.TAG_TREND, true, 2),
  new ReflectChartSettingItem(ReflectChartIds.TAG_TIME_BAR, true, 3),
  new ReflectChartSettingItem(ReflectChartIds.WEEKLY_REVIEW, true, 4)
];

function cloneItem(item: ReflectChartSettingItem): ReflectChartSettingItem {
  return new ReflectChartSettingItem(item.chartId, item.visible, item.order);
}

function defaultOrderOf(chartId: string): number {
  const index: number = MANAGED_CHART_IDS.findIndex((id: string) => id === chartId);
  return index >= 0 ? index : Number.MAX_SAFE_INTEGER;
}

function defaultVisibilityOf(chartId: string): boolean {
  const matched: ReflectChartSettingItem | undefined = DEFAULT_CHART_ITEMS.find(
    (item: ReflectChartSettingItem) => item.chartId === chartId
  );
  return matched ? matched.visible : true;
}

function normalizeOrder(order: number, fallbackOrder: number): number {
  if (!Number.isFinite(order)) {
    return fallbackOrder;
  }
  if (order < 0) {
    return fallbackOrder;
  }
  return Math.floor(order);
}

export function getManagedReflectChartIds(): string[] {
  return [...MANAGED_CHART_IDS];
}

export function isManagedReflectChartId(chartId: string): boolean {
  return MANAGED_CHART_IDS.some((id: string) => id === chartId);
}

export function buildDefaultReflectChartSettings(): ReflectChartSettings {
  return new ReflectChartSettings(
    REFLECT_CHART_SETTINGS_VERSION,
    DEFAULT_CHART_ITEMS.map((item: ReflectChartSettingItem) => cloneItem(item))
  );
}

export function sanitizeReflectChartSettings(settings?: ReflectChartSettings): ReflectChartSettings {
  if (!settings || !Array.isArray(settings.items)) {
    return buildDefaultReflectChartSettings();
  }

  const seen: Set<string> = new Set();
  const sanitized: ReflectChartSettingItem[] = [];

  settings.items.forEach((item: ReflectChartSettingItem, index: number) => {
    if (!item || typeof item.chartId !== 'string') {
      return;
    }
    if (!isManagedReflectChartId(item.chartId)) {
      return;
    }
    if (seen.has(item.chartId)) {
      return;
    }
    seen.add(item.chartId);

    sanitized.push(
      new ReflectChartSettingItem(
        item.chartId,
        typeof item.visible === 'boolean' ? item.visible : defaultVisibilityOf(item.chartId),
        normalizeOrder(item.order, index)
      )
    );
  });

  MANAGED_CHART_IDS.forEach((chartId: string) => {
    if (!seen.has(chartId)) {
      sanitized.push(
        new ReflectChartSettingItem(
          chartId,
          defaultVisibilityOf(chartId),
          defaultOrderOf(chartId)
        )
      );
    }
  });

  sanitized.sort((left: ReflectChartSettingItem, right: ReflectChartSettingItem) => {
    if (left.order !== right.order) {
      return left.order - right.order;
    }
    return defaultOrderOf(left.chartId) - defaultOrderOf(right.chartId);
  });

  const normalizedItems: ReflectChartSettingItem[] = sanitized.map((item: ReflectChartSettingItem, index: number) => {
    return new ReflectChartSettingItem(item.chartId, item.visible, index);
  });

  return new ReflectChartSettings(REFLECT_CHART_SETTINGS_VERSION, normalizedItems);
}
