import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferencesUtil, preferencesUtil } from 'base';
import {
  FanItem,
  DirectRecordData,
  parseSwissKnifeItemsPreference,
  normalizeDirectRecordData as normalizeDirectRecordDataFromOverlay
} from './OverLayModel';

const TAG: string = 'FanItemService';

export interface FanItemPayload {
  icon: string;
  label: string;
  /**
   * 允许传入自定义ID；如果未提供或冲突，将由服务自动生成
   */
  id?: number;
  directRecordData?: DirectRecordData | null;
}

export interface FanItemUpdate {
  icon?: string;
  label?: string;
  directRecordData?: DirectRecordData | null;
}

export type FanItemComparator = (a: FanItem, b: FanItem) => number;

export const FAN_ITEM_PREFERENCE_KEY: string = 'mockFanItems';

/**
 * 集中管理 FanItem 的增删改查逻辑，并负责与 PreferencesUtil 之间的数据同步。
 * 所有返回的列表都会同步写回用户首选项，以确保 UI 和存储保持一致。
 */
export class FanItemService {
  private readonly preferencesUtil: PreferencesUtil = preferencesUtil;

  /**
   * 获取所有 FanItem。
   */
  getAllFanItems(): FanItem[] {
    const storedValue: string = this.readRawPreference();
    return parseSwissKnifeItemsPreference(storedValue);
  }

  /**
   * 根据ID获取 FanItem。
   * @param id FanItem唯一标识
   */
  getFanItemById(id: number): FanItem | null {
    const items = this.getAllFanItems();
    const matched = items.find(item => item.id === id);
    return matched ?? null;
  }

  /**
   * 新增一个 FanItem。
   * @param payload FanItem基础数据
   * @returns 更新后的列表
   */
  insertFanItem(payload: FanItemPayload): FanItem[] {
    const items = this.getAllFanItems();
    const nextItems = [...items];

    const newItem = this.buildFanItem(payload, nextItems);
    if (!newItem) {
      hilog.warn(0x0000, TAG, `[FanItemService] Failed to insert fan item, invalid payload: ${JSON.stringify(payload)}`);
      return items;
    }

    nextItems.push(newItem);
    this.persistFanItems(nextItems);
    return nextItems;
  }

  /**
   * 批量覆盖保存 FanItem 列表。
   * @param payloads 新的 FanItem 数据
   * @returns 更新后的列表
   */
  saveFanItems(payloads: FanItemPayload[] | FanItem[]): FanItem[] {
    const sanitized: FanItem[] = [];
    payloads.forEach((payload) => {
      let candidate: FanItem | null;
      if (payload instanceof FanItem) {
        candidate = this.cloneFanItem(payload, sanitized);
      } else {
        candidate = this.buildFanItem(payload as FanItemPayload, sanitized);
      }
      if (candidate) {
        sanitized.push(candidate);
      }
    });

    this.persistFanItems(sanitized);
    return sanitized;
  }

  /**
   * 更新指定 FanItem。
   * @param id FanItem唯一标识
   * @param patch 需要更新的字段
   * @returns 更新后的 FanItem 或 null（如果未找到）
   */
  updateFanItem(id: number, patch: FanItemUpdate): FanItem | null {
    const items = this.getAllFanItems();
    const index = items.findIndex(item => item.id === id);

    if (index < 0) {
      hilog.warn(0x0000, TAG, `[FanItemService] Attempted to update non-existing fan item: ${id}`);
      return null;
    }

    const existing = items[index];
    const updated = new FanItem(
      this.normalizeIcon(patch.icon ?? existing.icon),
      this.normalizeLabel(patch.label ?? existing.label),
      existing.id,
      patch.directRecordData !== undefined
        ? this.normalizeDirectRecordData(patch.directRecordData)
        : existing.directRecordData
    );

    items[index] = updated;
    this.persistFanItems(items);
    return updated;
  }

  /**
   * 删除指定 FanItem。
   * @param id FanItem唯一标识
   * @returns 是否删除成功
   */
  deleteFanItem(id: number): boolean {
    const items = this.getAllFanItems();
    const filtered = items.filter(item => item.id !== id);

    if (filtered.length === items.length) {
      hilog.warn(0x0000, TAG, `[FanItemService] Attempted to delete non-existing fan item: ${id}`);
      return false;
    }

    this.persistFanItems(filtered);
    return true;
  }

  /**
   * 使用自定义排序方法对 FanItem 进行排序，并写回首选项。
   * @param comparator 排序函数，默认按照label的拼音顺序排序
   * @returns 排序后的列表
   */
  sortFanItems(comparator?: FanItemComparator): FanItem[] {
    const items = this.getAllFanItems();
    const sorted = [...items].sort(comparator ?? this.defaultComparator);
    this.persistFanItems(sorted);
    return sorted;
  }

  /**
   * 重写首选项中的原始数据。
   */
  private persistFanItems(items: FanItem[]): void {
    const preferenceStore = this.preferencesUtil.getPreferences();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[FanItemService] Preferences not initialized, skip persisting fan items');
      return;
    }
    try {
      const serialized = JSON.stringify(items);
      preferenceStore.putSync(FAN_ITEM_PREFERENCE_KEY, serialized);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[FanItemService] Failed to persist fan items: ${JSON.stringify(error)}`);
    }
  }

  private readRawPreference(): string {
    const preferenceStore = this.preferencesUtil.getPreferences();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[FanItemService] Preferences not initialized, returning empty fan items');
      return '[]';
    }
    const storedValue = preferenceStore.getSync(FAN_ITEM_PREFERENCE_KEY, '[]');
    if (typeof storedValue === 'string') {
      return storedValue;
    }

    try {
      return JSON.stringify(storedValue ?? []);
    } catch (error) {
      hilog.error(0x0000, TAG, `[FanItemService] Failed to stringify preference value: ${JSON.stringify(error)}`);
      return '[]';
    }
  }

  private defaultComparator(a: FanItem, b: FanItem): number {
    return this.normalizeLabel(a.label).localeCompare(this.normalizeLabel(b.label), 'zh-CN');
  }

  private buildFanItem(payload: FanItemPayload, existing: FanItem[]): FanItem | null {
    const label = this.normalizeLabel(payload.label);
    if (!label) {
      return null;
    }

    const icon = this.normalizeIcon(payload.icon);
    const directRecordData = this.normalizeDirectRecordData(payload.directRecordData);

    const usedIds = new Set(existing.map(item => item.id));
    let id = this.normalizeId(payload.id);
    if (id === null || usedIds.has(id)) {
      id = this.generateNextId(usedIds);
    }

    return new FanItem(icon, label, id, directRecordData);
  }

  private cloneFanItem(source: FanItem, existing: FanItem[]): FanItem | null {
    if (!(source instanceof FanItem)) {
      return null;
    }

    const usedIds = new Set(existing.map(item => item.id));
    let id = this.normalizeId(source.id);
    if (id === null || usedIds.has(id)) {
      id = this.generateNextId(usedIds);
    }

    return new FanItem(
      this.normalizeIcon(source.icon),
      this.normalizeLabel(source.label),
      id,
      this.normalizeDirectRecordData(source.directRecordData)
    );
  }

  private normalizeLabel(label?: string): string {
    if (typeof label !== 'string') {
      return '';
    }
    return label.trim();
  }

  private normalizeIcon(icon?: string): string {
    if (typeof icon !== 'string' || icon.trim().length === 0) {
      return '⭐️';
    }
    return icon.trim();
  }

  private normalizeId(value?: number): number | null {
    if (typeof value !== 'number' || Number.isNaN(value)) {
      return null;
    }
    return value;
  }

  private generateNextId(usedIds: Set<number>): number {
    let nextId = usedIds.size > 0 ? Math.max(...Array.from(usedIds)) + 1 : 1;
    if (!Number.isFinite(nextId) || nextId < 1) {
      nextId = 1;
    }

    while (usedIds.has(nextId)) {
      nextId++;
    }
    return nextId;
  }

  private normalizeDirectRecordData(data?: DirectRecordData | null): DirectRecordData | undefined {
    if (!data) {
      return undefined;
    }

    const normalized = normalizeDirectRecordDataFromOverlay({
      tagId: data.tagId ?? null,
      autoStart: data.autoStart ?? false
    });

    return normalized;
  }
}

export const fanItemService = new FanItemService();
