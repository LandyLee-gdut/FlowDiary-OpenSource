import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys } from '../../constants/PreferenceKeys';
import { PreferencesUtil, preferencesUtil } from '../PreferencesUtil';
import {
  EmojiCategory,
  EmojiItem,
  EmojiPreference,
  cloneEmojiItem,
  cloneEmojiPresets,
  cloneEmojiPreference,
  DEFAULT_EMOJI_PREFERENCE,
  EMOJI_PRESETS,
  isEmojiCategory
} from '../EmojiPreference';

const TAG: string = 'EmojiPreferenceService';

export interface EmojiItemPayload {
  char: string;
  name: string;
  category: EmojiCategory;
}

export interface EmojiItemUpdate {
  char?: string;
  name?: string;
  category?: EmojiCategory;
}

/**
 * Stores user level preferences such as emoji presets through Ark Preferences.
 * Inspired by FanItemService to provide consistent CRUD style helpers.
 */
export class EmojiPreferenceService {
  private readonly preferencesUtil: PreferencesUtil = preferencesUtil;

  getEmojiPreference(): EmojiPreference {
    return cloneEmojiPreference(this.readPreference());
  }

  getEmojiPresets(): EmojiItem[] {
    const preference: EmojiPreference = this.readPreference();
    return cloneEmojiPresets(preference.emojiPresets);
  }

  getEmojiPresetByChar(char: string): EmojiItem | undefined {
    const normalizedChar: string | undefined = this.normalizeEmojiChar(char);
    if (!normalizedChar) {
      return undefined;
    }
    const preference: EmojiPreference = this.readPreference();
    const matched: EmojiItem | undefined = preference.emojiPresets.find(
      (item: EmojiItem) => item.char === normalizedChar
    );
    return matched ? cloneEmojiItem(matched) : undefined;
  }

  insertEmojiPreset(payload: EmojiItemPayload): EmojiItem[] {
    const preference: EmojiPreference = this.readPreference();
    const nextPresets: EmojiItem[] = cloneEmojiPresets(preference.emojiPresets);

    const normalized: EmojiItem | undefined = this.normalizeEmojiPayload(payload);
    if (!normalized) {
      hilog.warn(0x0000, TAG, `[EmojiPreferenceService] Insert skipped due to invalid payload: ${JSON.stringify(payload)}`);
      return nextPresets;
    }

    const exists: boolean = nextPresets.some((item: EmojiItem) => item.char === normalized.char);
    if (exists) {
      hilog.warn(0x0000, TAG, `[EmojiPreferenceService] Insert skipped because emoji already exists: ${normalized.char}`);
      return nextPresets;
    }

    nextPresets.push(normalized);
    this.persistPreference({ emojiPresets: nextPresets });
    return cloneEmojiPresets(nextPresets);
  }

  saveEmojiPresets(payloads: Array<EmojiItemPayload | EmojiItem>): EmojiItem[] {
    const sanitized: EmojiItem[] = [];
    const seenChars: Set<string> = new Set();

    payloads.forEach((payload: EmojiItemPayload | EmojiItem) => {
      const normalized: EmojiItem | undefined = this.normalizeEmojiPayload(payload);
      if (!normalized) {
        return;
      }
      if (seenChars.has(normalized.char)) {
        return;
      }
      sanitized.push(normalized);
      seenChars.add(normalized.char);
    });

    if (sanitized.length === 0) {
      hilog.warn(0x0000, TAG, '[EmojiPreferenceService] Save skipped because sanitized preset list is empty');
      return this.getEmojiPresets();
    }

    this.persistPreference({ emojiPresets: sanitized });
    return cloneEmojiPresets(sanitized);
  }

  updateEmojiPreset(targetChar: string, patch: EmojiItemUpdate): EmojiItem | undefined {
    const normalizedTarget: string | undefined = this.normalizeEmojiChar(targetChar);
    if (!normalizedTarget) {
      return undefined;
    }

    const preference: EmojiPreference = this.readPreference();
    const nextPresets: EmojiItem[] = cloneEmojiPresets(preference.emojiPresets);
    const index: number = nextPresets.findIndex((item: EmojiItem) => item.char === normalizedTarget);
    if (index < 0) {
      hilog.warn(0x0000, TAG, `[EmojiPreferenceService] Update skipped, emoji not found: ${targetChar}`);
      return undefined;
    }

    const existing: EmojiItem = nextPresets[index];

    const updatedChar: string | undefined = this.normalizeEmojiChar(patch.char ?? existing.char);
    const updatedName: string | undefined = this.normalizeEmojiName(patch.name ?? existing.name);
    const updatedCategory: EmojiCategory | undefined = this.normalizeEmojiCategory(patch.category ?? existing.category);

    if (!updatedChar || !updatedName || !updatedCategory) {
      hilog.warn(0x0000, TAG, `[EmojiPreferenceService] Update skipped, invalid patch: ${JSON.stringify(patch)}`);
      return undefined;
    }

    if (updatedChar !== existing.char) {
      const hasConflict: boolean = nextPresets.some((item: EmojiItem, idx: number) => {
        return idx !== index && item.char === updatedChar;
      });
      if (hasConflict) {
        hilog.warn(0x0000, TAG, `[EmojiPreferenceService] Update skipped, target char conflicts with another emoji: ${updatedChar}`);
        return undefined;
      }
    }

    const updated: EmojiItem = {
      char: updatedChar,
      name: updatedName,
      category: updatedCategory
    };

    nextPresets[index] = updated;
    this.persistPreference({ emojiPresets: nextPresets });
    return cloneEmojiItem(updated);
  }

  removeEmojiPreset(targetChar: string): EmojiItem[] {
    const normalizedChar: string | undefined = this.normalizeEmojiChar(targetChar);
    if (!normalizedChar) {
      return this.getEmojiPresets();
    }

    const preference: EmojiPreference = this.readPreference();
    const nextPresets: EmojiItem[] = cloneEmojiPresets(preference.emojiPresets);
    const filtered: EmojiItem[] = nextPresets.filter((item: EmojiItem) => item.char !== normalizedChar);

    if (filtered.length === nextPresets.length) {
      hilog.warn(0x0000, TAG, `[EmojiPreferenceService] Remove skipped, emoji not found: ${targetChar}`);
      return nextPresets;
    }

    this.persistPreference({ emojiPresets: filtered });
    return cloneEmojiPresets(filtered);
  }

  private readPreference(): EmojiPreference {
    const store = this.preferencesUtil.getPreferences();
    if (!store) {
      hilog.warn(0x0000, TAG, '[EmojiPreferenceService] Preferences not initialized, returning default preference');
      return cloneEmojiPreference(DEFAULT_EMOJI_PREFERENCE);
    }

    try {
      if (!store.hasSync(PreferenceKeys.EMOJI_PREFERENCE)) {
        const defaults: EmojiPreference = cloneEmojiPreference(DEFAULT_EMOJI_PREFERENCE);
        this.persistPreference(defaults, store);
        return defaults;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[EmojiPreferenceService] Failed when checking preference existence: ${JSON.stringify(error)}`);
      return cloneEmojiPreference(DEFAULT_EMOJI_PREFERENCE);
    }

    const rawValue = store.getSync(PreferenceKeys.EMOJI_PREFERENCE, '') as string;
    const parsed: EmojiPreference | undefined = this.deserializePreference(rawValue);
    if (!parsed) {
      hilog.warn(0x0000, TAG, '[EmojiPreferenceService] Stored preference invalid, resetting to defaults');
      const defaults: EmojiPreference = cloneEmojiPreference(DEFAULT_EMOJI_PREFERENCE);
      this.persistPreference(defaults, store);
      return defaults;
    }

    return parsed;
  }

  private persistPreference(preference: EmojiPreference, preferenceStore?: preferences.Preferences): void {
    const store = preferenceStore ?? this.preferencesUtil.getPreferences();
    if (!store) {
      hilog.warn(0x0000, TAG, '[EmojiPreferenceService] Preferences not initialized, skip persisting preference');
      return;
    }

    const sanitized: EmojiPreference = {
      emojiPresets: this.sanitizeEmojiList(preference.emojiPresets, false)
    };
    const serialized: string = JSON.stringify(sanitized);

    try {
      store.putSync(PreferenceKeys.EMOJI_PREFERENCE, serialized);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[EmojiPreferenceService] Failed to persist preference: ${JSON.stringify(error)}`);
    }
  }

  private deserializePreference(rawValue: string): EmojiPreference | undefined {
    try {
      const parsed = JSON.parse(rawValue) as EmojiPreference;
      const emojiPresets: EmojiItem[] = this.sanitizeEmojiList(parsed?.emojiPresets, true);
      return { emojiPresets };
    } catch (error) {
      hilog.error(0x0000, TAG, `[EmojiPreferenceService] Failed to deserialize preference: ${JSON.stringify(error)}`);
      return undefined;
    }
  }

  private sanitizeEmojiList(candidates: EmojiItem[] | undefined, fallbackOnInvalid: boolean = false): EmojiItem[] {
    if (!Array.isArray(candidates)) {
      return fallbackOnInvalid ? cloneEmojiPresets(EMOJI_PRESETS) : [];
    }

    const sanitized: EmojiItem[] = [];
    const seenChars: Set<string> = new Set();

    candidates.forEach((candidate: EmojiItem) => {
      const normalized: EmojiItem | undefined = this.normalizeEmojiPayload(candidate);
      if (!normalized) {
        return;
      }
      if (seenChars.has(normalized.char)) {
        return;
      }
      sanitized.push(normalized);
      seenChars.add(normalized.char);
    });

    if (fallbackOnInvalid && sanitized.length === 0 && candidates.length > 0) {
      return cloneEmojiPresets(EMOJI_PRESETS);
    }

    return sanitized;
  }

  private normalizeEmojiPayload(payload: EmojiItemPayload | EmojiItem): EmojiItem | undefined {
    if (!payload) {
      return undefined;
    }

    const normalizedChar: string | undefined = this.normalizeEmojiChar(payload.char);
    const normalizedName: string | undefined = this.normalizeEmojiName(payload.name);
    const normalizedCategory: EmojiCategory | undefined = this.normalizeEmojiCategory(payload.category);

    if (!normalizedChar || !normalizedName || !normalizedCategory) {
      return undefined;
    }

    return {
      char: normalizedChar,
      name: normalizedName,
      category: normalizedCategory
    };
  }

  private normalizeEmojiChar(char?: string): string | undefined {
    if (typeof char !== 'string') {
      return undefined;
    }
    const value: string = char.trim();
    if (!value) {
      return undefined;
    }
    return value;
  }

  private normalizeEmojiName(name?: string): string | undefined {
    if (typeof name !== 'string') {
      return undefined;
    }
    const value: string = name.trim();
    if (!value) {
      return undefined;
    }
    return value;
  }

  private normalizeEmojiCategory(category?: string | EmojiCategory): EmojiCategory | undefined {
    if (typeof category !== 'string') {
      return undefined;
    }
    const trimmed: string = category.trim();
    if (!trimmed) {
      return undefined;
    }
    if (!isEmojiCategory(trimmed)) {
      return undefined;
    }
    return trimmed as EmojiCategory;
  }
}

export const emojiPreferenceService: EmojiPreferenceService = new EmojiPreferenceService();
