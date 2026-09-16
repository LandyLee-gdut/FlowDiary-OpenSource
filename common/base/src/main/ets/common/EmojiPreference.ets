/**
 * Canonical user preference shape shared across features.
 * Emoji presets are persisted via preferences and exposed through EmojiUtil helpers.
 */
export type EmojiCategory =
  | 'mood_status'
  | 'health_routine'
  | 'clothing_style'
  | 'food_drink'
  | 'home_household'
  | 'transport_travel'
  | 'work_study'
  | 'sports_hobbies'
  | 'shopping_money'
  | 'time_holidays'
  | 'nature_weather'
  | 'tools_tech';

export interface EmojiItem {
  char: string;
  name: string;
  category: EmojiCategory;
}

export interface EmojiPreference {
  emojiPresets: EmojiItem[];
}

export const EMOJI_CATEGORIES: readonly EmojiCategory[] = [
  'mood_status',
  'health_routine',
  'clothing_style',
  'food_drink',
  'home_household',
  'transport_travel',
  'work_study',
  'sports_hobbies',
  'shopping_money',
  'time_holidays',
  'nature_weather',
  'tools_tech'
];

// Default data migrated from the legacy EmojiUtil constant.
export const EMOJI_PRESETS: EmojiItem[] = [
  // === 心情与状态 ===
  { char: '\u{1F600}', name: 'Grinning Face', category: 'mood_status' },
  { char: '\u{1F60D}', name: 'Heart Eyes', category: 'mood_status' },
  { char: '\u{1F60E}', name: 'Cool', category: 'mood_status' },
  { char: '\u{1F622}', name: 'Crying Face', category: 'mood_status' },
  { char: '\u{1F914}', name: 'Thinking Face', category: 'mood_status' },
  { char: '\u{1F973}', name: 'Party Face', category: 'mood_status' },

  // === 健康与作息 ===
  { char: '\u{1F4AA}', name: 'Flexed Biceps', category: 'health_routine' },
  { char: '\u{1F48A}', name: 'Pill', category: 'health_routine' },
  { char: '\u{1FA7A}', name: 'Stethoscope', category: 'health_routine' },
  { char: '\u{1F6CC}', name: 'Person in Bed', category: 'health_routine' },
  { char: '\u{1F9D8}', name: 'Lotus Position', category: 'health_routine' },
  { char: '\u{1F9D7}', name: 'Person Climbing', category: 'health_routine' },

  // === 穿着与风格（衣） ===
  { char: '\u{1F455}', name: 'T-Shirt', category: 'clothing_style' },
  { char: '\u{1F457}', name: 'Dress', category: 'clothing_style' },
  { char: '\u{1F9E2}', name: 'Billed Cap', category: 'clothing_style' },
  { char: '\u{1F45F}', name: 'Running Shoe', category: 'clothing_style' },
  { char: '\u{1F458}', name: 'Kimono', category: 'clothing_style' },
  { char: '\u{1F451}', name: 'Crown', category: 'clothing_style' },

  // === 饮食（食） ===
  { char: '\u{1F354}', name: 'Hamburger', category: 'food_drink' },
  { char: '\u{1F35C}', name: 'Noodles', category: 'food_drink' },
  { char: '\u{1F363}', name: 'Sushi', category: 'food_drink' },
  { char: '\u{1F370}', name: 'Cake', category: 'food_drink' },
  { char: '\u{2615}', name: 'Hot Beverage', category: 'food_drink' },
  { char: '\u{1F37A}', name: 'Beer Mug', category: 'food_drink' },

  // === 居家与家务（住） ===
  { char: '\u{1F3E0}', name: 'House', category: 'home_household' },
  { char: '\u{1F6CF}', name: 'Bed', category: 'home_household' },
  { char: '\u{1F9F9}', name: 'Broom', category: 'home_household' },
  { char: '\u{1F9FA}', name: 'Basket', category: 'home_household' },
  { char: '\u{1F9FC}', name: 'Soap', category: 'home_household' },
  { char: '\u{1F37D}', name: 'Fork and Knife with Plate', category: 'home_household' },

  // === 出行与旅行（行） ===
  { char: '\u{1F697}', name: 'Car', category: 'transport_travel' },
  { char: '\u{1F6B2}', name: 'Bicycle', category: 'transport_travel' },
  { char: '\u{1F6A2}', name: 'Ship', category: 'transport_travel' },
  { char: '\u{2708}', name: 'Airplane', category: 'transport_travel' },
  { char: '\u{1F5FA}', name: 'World Map', category: 'transport_travel' },
  { char: '\u{1F9F3}', name: 'Luggage', category: 'transport_travel' },

  // === 学习与工作 ===
  { char: '\u{1F4DA}', name: 'Books', category: 'work_study' },
  { char: '\u{1F4DD}', name: 'Memo', category: 'work_study' },
  { char: '\u{1F4BC}', name: 'Briefcase', category: 'work_study' },
  { char: '\u{1F58A}', name: 'Pen', category: 'work_study' },
  { char: '\u{1F5D3}', name: 'Calendar', category: 'work_study' },
  { char: '\u{1F4C8}', name: 'Chart Increasing', category: 'work_study' },

  // === 运动与兴趣（含健身） ===
  { char: '\u{1F3CB}', name: 'Lifting Weights', category: 'sports_hobbies' },
  { char: '\u{1F3C3}', name: 'Running', category: 'sports_hobbies' },
  { char: '\u{1F6B4}', name: 'Cycling', category: 'sports_hobbies' },
  { char: '\u{1F3CA}', name: 'Swimming', category: 'sports_hobbies' },
  { char: '\u{1F94A}', name: 'Boxing Glove', category: 'sports_hobbies' },
  { char: '\u{1F3F8}', name: 'Badminton', category: 'sports_hobbies' },

  // === 购物与财务 ===
  { char: '\u{1F6CD}', name: 'Shopping Bags', category: 'shopping_money' },
  { char: '\u{1F4B0}', name: 'Money Bag', category: 'shopping_money' },
  { char: '\u{1F4B3}', name: 'Credit Card', category: 'shopping_money' },
  { char: '\u{1F4E6}', name: 'Package', category: 'shopping_money' },
  { char: '\u{1F9FE}', name: 'Receipt', category: 'shopping_money' },
  { char: '\u{1F4B8}', name: 'Money with Wings', category: 'shopping_money' },

  // === 时间与节日 ===
  { char: '\u{23F0}', name: 'Alarm Clock', category: 'time_holidays' },
  { char: '\u{1F4C5}', name: 'Calendar', category: 'time_holidays' },
  { char: '\u{1F389}', name: 'Party Popper', category: 'time_holidays' },
  { char: '\u{1F382}', name: 'Birthday Cake', category: 'time_holidays' },
  { char: '\u{1F9E7}', name: 'Red Envelope', category: 'time_holidays' },
  { char: '\u{1F38A}', name: 'Confetti Ball', category: 'time_holidays' },

  // === 自然与天气 ===
  { char: '\u{2600}', name: 'Sun', category: 'nature_weather' },
  { char: '\u{26C5}', name: 'Sun Behind Cloud', category: 'nature_weather' },
  { char: '\u{1F327}', name: 'Cloud with Rain', category: 'nature_weather' },
  { char: '\u{1F308}', name: 'Rainbow', category: 'nature_weather' },
  { char: '\u{1F338}', name: 'Cherry Blossom', category: 'nature_weather' },
  { char: '\u{1F33F}', name: 'Herb', category: 'nature_weather' },

  // === 工具与数码 ===
  { char: '\u{1F4A1}', name: 'Light Bulb', category: 'tools_tech' },
  { char: '\u{1F527}', name: 'Wrench', category: 'tools_tech' },
  { char: '\u{1F50B}', name: 'Battery', category: 'tools_tech' },
  { char: '\u{1F50C}', name: 'Electric Plug', category: 'tools_tech' },
  { char: '\u{1F4F1}', name: 'Mobile Phone', category: 'tools_tech' },
  { char: '\u{1F5A5}', name: 'Desktop Computer', category: 'tools_tech' }
];

export const DEFAULT_EMOJI_PREFERENCE: EmojiPreference = {
  emojiPresets: cloneEmojiPresets()
};

export function cloneEmojiItem(item: EmojiItem): EmojiItem {
  return {
    char: item.char,
    name: item.name,
    category: item.category
  };
}

export function cloneEmojiPresets(source: ReadonlyArray<EmojiItem> = EMOJI_PRESETS): EmojiItem[] {
  return source.map((item: EmojiItem) => cloneEmojiItem(item));
}

export function cloneEmojiPreference(source: EmojiPreference = DEFAULT_EMOJI_PREFERENCE): EmojiPreference {
  return {
    emojiPresets: cloneEmojiPresets(source.emojiPresets)
  };
}

export function isEmojiCategory(candidate: string): boolean {
  return (EMOJI_CATEGORIES as readonly string[]).indexOf(candidate) >= 0;
}
