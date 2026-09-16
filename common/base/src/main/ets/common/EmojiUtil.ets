import { emojiPreferenceService, EmojiItemPayload, EmojiItemUpdate } from './Service/EmojiPreferenceService';
import { EmojiCategory, EmojiItem, EMOJI_PRESETS, cloneEmojiPresets } from './EmojiPreference';

export { EmojiCategory, EmojiItem, EMOJI_PRESETS } from './EmojiPreference';
export { EmojiItemPayload, EmojiItemUpdate } from './Service/EmojiPreferenceService';

export class EmojiUtil {
  static getAll(): EmojiItem[] {
    return emojiPreferenceService.getEmojiPresets();
  }

  static getByChar(char: string): EmojiItem | undefined {
    return emojiPreferenceService.getEmojiPresetByChar(char);
  }

  static byCategory(category: EmojiCategory): EmojiItem[] {
    const all = emojiPreferenceService.getEmojiPresets();
    return all.filter((item: EmojiItem) => item.category === category);
  }

  static addEmoji(payload: EmojiItemPayload): EmojiItem[] {
    return emojiPreferenceService.insertEmojiPreset(payload);
  }

  static saveEmojis(payloads: Array<EmojiItemPayload | EmojiItem>): EmojiItem[] {
    return emojiPreferenceService.saveEmojiPresets(payloads);
  }

  static updateEmoji(targetChar: string, patch: EmojiItemUpdate): EmojiItem | undefined {
    return emojiPreferenceService.updateEmojiPreset(targetChar, patch);
  }

  static removeEmoji(targetChar: string): EmojiItem[] {
    return emojiPreferenceService.removeEmojiPreset(targetChar);
  }

  static resetToDefaults(): EmojiItem[] {
    return emojiPreferenceService.saveEmojiPresets(cloneEmojiPresets());
  }
}
