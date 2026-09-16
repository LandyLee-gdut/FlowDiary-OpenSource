// /common/theme/AppColors.ts
import { ColorUtil } from '../common/ColorUtil';

/**
 * Defines the standard color palette for the application UI, designed for a premium and cohesive visual experience.
 * This system is built around a primary Blue and an accent Gold, supported by a comprehensive neutral scale.
 */
export class AppColors {

  // --- 1. Primary Color: Blue (品牌主色 - 稳定、专业) ---
  // 用于主要操作按钮、关键链接、选中状态等。
  static readonly PRIMARY_LIGHTER: string = '#E6F0FF';  // 非常浅的背景或悬浮色
  static readonly PRIMARY_LIGHT: string = '#B3D1FF';   // 较浅的背景或辅助元素
  static readonly PRIMARY: string = '#4D94FF';         // 核心品牌色，用于按钮和交互
  static readonly PRIMARY_DARK: string = '#0063E6';    // 更深的主色，用于悬浮或按下状态
  static readonly PRIMARY_DARKER: string = '#004AAA';  // 最深的主色，用于特殊强调

  // --- 2. Accent Color: Gold (强调/辅助色 - 高级、温暖) ---
  // 用于特别需要突出的元素，如VIP标识、奖励、重要数据点。应谨慎使用。
  static readonly ACCENT_LIGHTER: string = '#FFF7E6';  // 金色系浅背景
  static readonly ACCENT_LIGHT: string = '#FFDCA8';   // 浅金色
  static readonly ACCENT: string = '#cbffc166';         // 核心辅助色
  static readonly ACCENT_DARK: string = '#E6A23A';    // 深金色
  static readonly ACCENT_DARKER: string = '#CC851A';  // 最深金色

  // --- 3. Neutral Colors: Gray (中性色 - 界面的骨架) ---
  // 用于文本、背景、边框、分割线，是高级感的基础。
  static readonly NEUTRAL_0_WHITE: string = '#FFFFFF';
  static readonly NEUTRAL_100: string = '#F4F6F8';     // 页面/卡片浅背景
  static readonly NEUTRAL_200: string = '#E8EBED';     // 描边、分割线、图表背景轨道
  static readonly NEUTRAL_300: string = '#D1D9E0';     // 禁用状态元素
  static readonly NEUTRAL_500: string = '#8A9BA8';     // 辅助/次要文本
  static readonly NEUTRAL_700: string = '#4E5D66';     // 次要标题/常规文本
  static readonly NEUTRAL_800: string = '#ff202628';
  static readonly NEUTRAL_900: string = '#1F2326';     // 主要标题/核心文本
  static readonly NEUTRAL_1000_BLACK: string = '#000000';

  // --- 4. Semantic Colors (语义色 - 反馈用户状态) ---
  static readonly SUCCESS: string = '#26C281';
  static readonly SUCCESS_LIGHT: string = '#A9E7D3';
  static readonly WARNING: string = '#F5BF3B';
  static readonly WARNING_LIGHT: string = '#FFE8A0';
  static readonly ERROR: string = '#E35C4D';
  static readonly ERROR_LIGHT: string = '#FFB3B3';

  // --- 5. Data Visualization Palette (数据可视化色板) ---
  // 一套和谐的多色组合，专为图表设计，避免与UI主色冲突。
  // 顺序：主蓝 -> 辅金 -> 宁静青 -> 优雅紫 -> 活力珊瑚
  static readonly DATA_VIZ_1: string = AppColors.PRIMARY;      // #4D94FF
  static readonly DATA_VIZ_2: string = AppColors.WARNING;       // #FFC166
  static readonly DATA_VIZ_3: string = '#4AC9C2';              // 薄荷青 (Mint)
  static readonly DATA_VIZ_4: string = '#ccb380ff';              // 紫罗兰 (Violet)
  static readonly DATA_VIZ_5: string = '#ccff8a78';              // 珊瑚色 (Coral)
  static readonly DATA_VIZ_6: string = '#66D9A8';              // 春绿色
  // 【新增颜色】 inspired by your predefinedColors, making them more lively
  static readonly DATA_VIZ_7: string = '#EF4444'; // 活力红 (Vibrant Red)
  static readonly DATA_VIZ_8: string = '#8B5CF6'; // 紫水晶 (Amethyst)
  static readonly DATA_VIZ_9: string = '#06B6D4'; // 青色 (Teal/Cyan)
  static readonly DATA_VIZ_10: string = '#F97316'; // 橘色 (Tangerine)
  static readonly DATA_VIZ_11: string = '#EC4899'; // 品红 (Magenta)
  static readonly DATA_VIZ_12: string = '#84CC16'; // 酸橙绿 (Lime Green)



  // --- 5a. Data Visualization Palette - Light Tints (新增部分，用于标签背景) ---
  // 与上方 DATA_VIZ 色板一一对应，提供柔和的背景色。
  static readonly DATA_VIZ_1_LIGHT: string = AppColors.PRIMARY_LIGHTER; // #E6F0FF (复用)
  static readonly DATA_VIZ_2_LIGHT: string = AppColors.WARNING_LIGHT;   // #FEF5E1 (复用)
  static readonly DATA_VIZ_3_LIGHT: string = '#E0F8F7';                 // Light Mint
  static readonly DATA_VIZ_4_LIGHT: string = '#F2EBFF';                 // Light Violet
  static readonly DATA_VIZ_5_LIGHT: string = '#FFEAE7';                 // Light Coral
  static readonly DATA_VIZ_6_LIGHT: string = '#E3F7EF';                 // Light Spring

  // 【新增浅色】
  static readonly DATA_VIZ_7_LIGHT: string = '#FEE2E2'; // Light Vibrant Red
  static readonly DATA_VIZ_8_LIGHT: string = '#F5F3FF'; // Light Amethyst
  static readonly DATA_VIZ_9_LIGHT: string = '#E0F9FA'; // Light Teal/Cyan
  static readonly DATA_VIZ_10_LIGHT: string = '#FFF7ED';// Light Tangerine
  static readonly DATA_VIZ_11_LIGHT: string = '#FDF2F8';// Light Magenta
  static readonly DATA_VIZ_12_LIGHT: string = '#F7FEE7';// Light Lime Green

  // --- 6. Standard UI Element Colors (标准UI元素颜色定义) ---
  // 将基础色板映射到具体UI角色，便于维护和主题切换。
  static readonly TEXT_PRIMARY: string = AppColors.NEUTRAL_900;
  static readonly TEXT_SECONDARY: string = AppColors.NEUTRAL_700;
  static readonly TEXT_TERTIARY: string = AppColors.NEUTRAL_500;
  static readonly TEXT_DISABLED: string = AppColors.NEUTRAL_300;
  static readonly TEXT_ON_PRIMARY: string = AppColors.NEUTRAL_0_WHITE; // 主色按钮上的文字

  static readonly BG_PAGE: string = AppColors.NEUTRAL_100;
  static readonly BG_CARD: string = AppColors.NEUTRAL_0_WHITE;
  static readonly BG_MAIN: string = '#fff8f7f8'

  static readonly BORDER_PRIMARY: string = AppColors.NEUTRAL_200;
  static readonly BORDER_SECONDARY: string = AppColors.NEUTRAL_100;

  static readonly SHADOW_THICK: string = '#ffaeadad';

  // 初晨天空的金色，温柔明亮
  static readonly SKY_MORNING_GOLD: string = '#FFF4D6';  // 柔和的淡金，带一点奶白感

  // 落日黄昏的金色，温暖浓烈
  static readonly SKY_SUNSET_GOLD: string = '#FFD580';  // 浓郁的橙金色，温暖饱满
  static readonly SKY_SUNSET_GOLD_LIGHT: string = '#ffffe78e';  // 浓郁的橙金色，温暖饱满

  static readonly SKY_LIGHTER: string = '#DFF6FF';  // 晴空般的浅蓝色，清澈明亮

  static readonly SKY_MORNING: string = '#E0F7FA';  // 带一点点青色的浅蓝，轻盈通透

  static readonly SKY_CLEAR: string = '#CCE7FF';  // 明快的淡蓝色，清爽透亮

  static readonly PANEL_BG: string = '#F1F5F9'
}

export class AppGradients {

  /**
   * 主要品牌渐变，用于关键Banner或卡片背景。
   */
  static readonly PRIMARY_GRADIENT = new LinearGradient([
    { color: AppColors.PRIMARY, offset: 0 },
    { color: AppColors.PRIMARY_DARK, offset: 1 }
  ]);

  /**
   * 强调/高光渐变，用于需要特别突出的区域。
   */
  static readonly ACCENT_GRADIENT = new LinearGradient([
    { color: AppColors.ACCENT_LIGHT, offset: 0 },
    { color: AppColors.ACCENT, offset: 1 }
  ]);

  /**
   * 优雅的、轻微的背景渐变，增加界面呼吸感。
   */
  static readonly SUBTLE_BACKGROUND = new LinearGradient([
    { color: '#F8F9FB', offset: 0 }, // 略带蓝调的白
    { color: AppColors.NEUTRAL_100, offset: 1 }
  ]);

  /**
   * 数据面板专属的渐变色数组。
   * 每个渐变都使用同色系的深浅变化，显得更加精致和专业。
   */

  static readonly DATA_PANEL_COLORS: ResourceColor[] = [
  // 原始颜色
    AppColors.DATA_VIZ_1,
    AppColors.DATA_VIZ_2,
    AppColors.DATA_VIZ_3,
    AppColors.DATA_VIZ_4,
    AppColors.DATA_VIZ_5,
    AppColors.DATA_VIZ_6,
    // 【新增颜色】
    AppColors.DATA_VIZ_7,
    AppColors.DATA_VIZ_8,
    AppColors.DATA_VIZ_9,
    AppColors.DATA_VIZ_10,
    AppColors.DATA_VIZ_11,
    AppColors.DATA_VIZ_12,
  ];

  static readonly DATA_PANEL_GRADIENTS: LinearGradient[] = [
  // 原始渐变
  // 1. Blue
    new LinearGradient([{ color: '#B3D1FF', offset: 0 }, { color: AppColors.DATA_VIZ_1, offset: 1 }]),
    // 2. Gold
    new LinearGradient([{ color: '#FFEBCC', offset: 0 }, { color: AppColors.DATA_VIZ_2, offset: 1 }]),
    // 3. Mint
    new LinearGradient([{ color: '#A0F0EB', offset: 0 }, { color: AppColors.DATA_VIZ_3, offset: 1 }]),
    // 4. Violet
    new LinearGradient([{ color: '#E0CCFF', offset: 0 }, { color: AppColors.DATA_VIZ_4, offset: 1 }]),
    // 5. Coral
    new LinearGradient([{ color: '#FFD1CA', offset: 0 }, { color: AppColors.DATA_VIZ_5, offset: 1 }]),
    // 6. Spring Green
    new LinearGradient([{ color: '#B3EBD5', offset: 0 }, { color: AppColors.DATA_VIZ_6, offset: 1 }]),

    // 【新增渐变】
    // 7. Vibrant Red
    new LinearGradient([{ color: AppColors.DATA_VIZ_7_LIGHT, offset: 0 }, { color: AppColors.DATA_VIZ_7, offset: 1 }]),
    // 8. Amethyst
    new LinearGradient([{ color: AppColors.DATA_VIZ_8_LIGHT, offset: 0 }, { color: AppColors.DATA_VIZ_8, offset: 1 }]),
    // 9. Teal/Cyan
    new LinearGradient([{ color: AppColors.DATA_VIZ_9_LIGHT, offset: 0 }, { color: AppColors.DATA_VIZ_9, offset: 1 }]),
    // 10. Tangerine
    new LinearGradient([{ color: AppColors.DATA_VIZ_10_LIGHT, offset: 0 }, { color: AppColors.DATA_VIZ_10, offset: 1 }]),
    // 11. Magenta
    new LinearGradient([{ color: AppColors.DATA_VIZ_11_LIGHT, offset: 0 }, { color: AppColors.DATA_VIZ_11, offset: 1 }]),
    // 12. Lime Green
    new LinearGradient([{ color: AppColors.DATA_VIZ_12_LIGHT, offset: 0 }, { color: AppColors.DATA_VIZ_12, offset: 1 }]),
  ];


  /**
   * 【新增辅助函数】
   * 根据给定的纯色，查找并返回其对应的渐变色。
   * 如果找不到，返回一个默认的灰色渐变，防止应用崩溃。
   * @param solidColor - The solid color to find the corresponding gradient for.
   * @returns The corresponding LinearGradient or a default one.
   */
  static getGradientForColor(solidColor: ResourceColor): LinearGradient {
    const palette = AppGradients.DATA_PANEL_COLORS;
    if (typeof solidColor === 'string') {
      const normalizedInput = ColorUtil.normalizeHexColor(solidColor);
      const normalizedPalette = palette.map(item => typeof item === 'string' ? ColorUtil.normalizeHexColor(item) : '');
      const index = normalizedPalette.indexOf(normalizedInput);
      if (index !== -1) {
        return AppGradients.DATA_PANEL_GRADIENTS[index];
      }
      return AppGradients.buildGradient(normalizedInput);
    }

    const index = palette.indexOf(solidColor);
    if (index !== -1) {
      return AppGradients.DATA_PANEL_GRADIENTS[index];
    }
    console.error(`Color ${solidColor} not found in DATA_PANEL_COLORS. Using default gradient.`);
    return new LinearGradient([{ color: AppColors.NEUTRAL_300, offset: 0 }, { color: AppColors.NEUTRAL_500, offset: 1 }]);
  }

  private static buildGradient(hexColor: string): LinearGradient {
    const lightColor = ColorUtil.generateLighterColor(hexColor, 0.92);
    return new LinearGradient([
      { color: lightColor, offset: 0 },
      { color: hexColor, offset: 1 }
    ]);
  }
}
