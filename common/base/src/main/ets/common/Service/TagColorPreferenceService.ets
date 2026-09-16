import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys } from '../../constants/PreferenceKeys';
import { ColorUtil } from '../ColorUtil';
import { PreferencesUtil, preferencesUtil } from '../PreferencesUtil';

const TAG: string = 'TagColorPreferenceService';
const DEFAULT_TAG_COLORS: string[] = [
  // 预设标签颜色（与 TodayModel.getMockTagData 对齐）
  '#4D94FF', // 数据可视化蓝 / 默认“工作”
  '#F5BF3B', // 数据可视化金 / 默认“休闲”
  '#4AC9C2', // 数据可视化薄荷青 / 默认“学习”
  '#CCB380', // 数据可视化紫罗兰 / 默认“生活”
  '#CCFF8A', // 数据可视化珊瑚 / 默认“运动”
  '#66D9A8', // 春绿色 / 默认“副业”
  // 其他基础预设颜色
  '#EF4444', // 活力红
  '#8B5CF6', // 紫水晶
  '#06B6D4', // 青色
  '#F97316', // 橘色
  '#EC4899', // 品红
  '#84CC16'  // 酸橙绿
];

/**
 * 管理标签颜色调色盘的轻量级偏好存储。
 * 依赖 PreferencesUtil，提供基础的增删改查接口，便于后续接入 ColorPicker 等自定义入口。
 */
export class TagColorPreferenceService {
  private readonly preferencesUtil: PreferencesUtil = preferencesUtil;

  getColors(): string[] {
    return this.readColors();
  }

  saveColors(colors: string[]): string[] {
    const sanitized = this.sanitizeColors(colors);
    this.persistColors(sanitized);
    return [...sanitized];
  }

  addColor(color: string): string[] {
    const normalized = this.normalizeColor(color);
    if (!normalized) {
      hilog.warn(0x0000, TAG, `[TagColorPreferenceService] addColor skipped: invalid color=${JSON.stringify(color)}`);
      return this.getColors();
    }

    const current = this.readColors();
    if (current.some(item => item === normalized)) {
      return current;
    }

    const next = [...current, normalized];
    this.persistColors(next);
    return [...next];
  }

  removeColor(color: string): string[] {
    const normalized = this.normalizeColor(color);
    if (!normalized) {
      hilog.warn(0x0000, TAG, `[TagColorPreferenceService] removeColor skipped: invalid color=${JSON.stringify(color)}`);
      return this.getColors();
    }

    const current = this.readColors();
    const filtered = current.filter(item => item !== normalized);
    if (filtered.length === current.length) {
      hilog.warn(0x0000, TAG, `[TagColorPreferenceService] removeColor skipped: color not found=${normalized}`);
      return current;
    }

    this.persistColors(filtered);
    return [...filtered];
  }

  resetToDefaults(): string[] {
    this.persistColors(DEFAULT_TAG_COLORS);
    return [...DEFAULT_TAG_COLORS];
  }

  private readColors(): string[] {
    const store = this.preferencesUtil.getPreferences();
    if (!store) {
      hilog.warn(0x0000, TAG, '[TagColorPreferenceService] Preferences not initialized, fallback to defaults');
      return [...DEFAULT_TAG_COLORS];
    }

    try {
      if (!store.hasSync(PreferenceKeys.TAG_COLORS)) {
        this.persistColors(DEFAULT_TAG_COLORS, store);
        return [...DEFAULT_TAG_COLORS];
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[TagColorPreferenceService] hasSync failed: ${JSON.stringify(error)}`);
      return [...DEFAULT_TAG_COLORS];
    }

    try {
      const raw = store.getSync(PreferenceKeys.TAG_COLORS, '') as string;
      const parsed = this.deserialize(raw);
      if (!parsed || parsed.length === 0) {
        hilog.warn(0x0000, TAG, '[TagColorPreferenceService] Stored colors invalid, reset to defaults');
        this.persistColors(DEFAULT_TAG_COLORS, store);
        return [...DEFAULT_TAG_COLORS];
      }
      return parsed;
    } catch (error) {
      hilog.error(0x0000, TAG, `[TagColorPreferenceService] getSync failed: ${JSON.stringify(error)}`);
      return [...DEFAULT_TAG_COLORS];
    }
  }

  private persistColors(colors: string[], preferenceStore?: preferences.Preferences): void {
    const store = preferenceStore ?? this.preferencesUtil.getPreferences();
    if (!store) {
      hilog.warn(0x0000, TAG, '[TagColorPreferenceService] Preferences not initialized, skip persist');
      return;
    }
    const sanitized = this.sanitizeColors(colors);
    const serialized = JSON.stringify(sanitized);
    try {
      store.putSync(PreferenceKeys.TAG_COLORS, serialized);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[TagColorPreferenceService] persist failed: ${JSON.stringify(error)}`);
    }
  }

  private deserialize(raw: string): string[] | undefined {
    try {
      const parsed = JSON.parse(raw) as string[];
      return this.sanitizeColors(parsed);
    } catch (error) {
      hilog.error(0x0000, TAG, `[TagColorPreferenceService] deserialize failed: ${JSON.stringify(error)}`);
      return undefined;
    }
  }

  private sanitizeColors(colors: string[] | undefined): string[] {
    if (!Array.isArray(colors)) {
      return [...DEFAULT_TAG_COLORS];
    }
    const result: string[] = [];
    const seen: Set<string> = new Set();
    colors.forEach(item => {
      const normalized = this.normalizeColor(item);
      if (!normalized) {
        return;
      }
      if (seen.has(normalized)) {
        return;
      }
      seen.add(normalized);
      result.push(normalized);
    });
    return result.length > 0 ? result : [...DEFAULT_TAG_COLORS];
  }

  private normalizeColor(color?: string): string | undefined {
    if (typeof color !== 'string') {
      return undefined;
    }
    const normalized = ColorUtil.normalizeHexColor(color);
    if (!/^#[0-9A-F]{6}$/i.test(normalized)) {
      return undefined;
    }
    return normalized.toUpperCase();
  }
}

export const tagColorPreferenceService: TagColorPreferenceService = new TagColorPreferenceService();
