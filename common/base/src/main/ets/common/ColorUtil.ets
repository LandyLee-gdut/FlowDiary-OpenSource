import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ColorUtil'

export class ColorUtil {
  /**
   * 将HEX颜色转换为HSL颜色 (高精度版本，防止色相偏移)。
   * @param hex The hex color string (e.g., '#8B5CF6').
   * @returns HSL object, or null if invalid.
   */
  static hexToHsl(hex: string): MyHSLColor | null {
    const rgb = ColorUtil.hexToRgb(hex);
    if (!rgb) {
      hilog.error(0x0000, TAG, 'Invalid hex for HSL conversion: ' + hex);
      return null;
    }

    const r = rgb.r / 255;
    const g = rgb.g / 255;
    const b = rgb.b / 255;

    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);

    let h = 0, s = 0, l = (max + min) / 2;

    if (max === min) {
      h = s = 0; // 灰度
    } else {
      const d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      switch (max) {
        case r:
          h = (g - b) / d + (g < b ? 6 : 0);
          break;
        case g:
          h = (b - r) / d + 2;
          break;
        case b:
          h = (r - g) / d + 4;
          break;
      }
      h /= 6; // 转换为 0-1 范围
    }

    return { h, s, l };
  }

  /**
   * 将HSL颜色转换回HEX颜色 (高精度版本)。
   * @param hsl The HSL color object (h, s, l are all in the 0-1 range).
   * @returns Hex color string.
   */
  static hslToHex(hsl: MyHSLColor): string {
    const h = hsl.h;
    const s = hsl.s;
    const l = hsl.l;
    let r: number, g: number, b: number;

    if (s === 0) {
      r = g = b = l; // 灰度
    } else {
      const hue2rgb = (p: number, q: number, t: number): number => {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1 / 6) return p + (q - p) * 6 * t;
        if (t < 1 / 2) return q;
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
        return p;
      };

      const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      const p = 2 * l - q;
      r = hue2rgb(p, q, h + 1 / 3);
      g = hue2rgb(p, q, h);
      b = hue2rgb(p, q, h - 1 / 3);
    }

    const toHex = (x: number): string => {
      const hex = Math.round(x * 255).toString(16);
      return hex.length === 1 ? '0' + hex : hex;
    };

    return `#${toHex(r)}${toHex(g)}${toHex(b)}`.toUpperCase();
  }

  /**
   * [Vibrant Version] 生成一个更鲜艳、饱和度更高的浅色版本。
   *
   * @param hex 基础十六进制颜色字符串。
   * @param lightnessFactor 可选，用于强制指定目标亮度 (0-1)。
   * @param saturationFactor 可选，用于强制指定目标饱和度 (0-1)。
   * @returns 返回一个新的、更鲜艳的十六进制浅色字符串。
   */
  static generateLightColor(hex: string, lightnessFactor?: number, saturationFactor?: number): string {
    const hsl = ColorUtil.hexToHsl(hex);
    if (!hsl) {
      return '#F0F0F0';
    }

    // 保持色相完全不变,只调整亮度和饱和度
    let targetLightness: number;
    let targetSaturation: number;

    if (lightnessFactor !== undefined) {
      targetLightness = lightnessFactor;
    } else {
      // 根据原始亮度适度调整,避免过度变浅
      if (hsl.l < 0.3) {
        targetLightness = 0.70; // 深色 -> 中等浅色
      } else if (hsl.l < 0.5) {
        targetLightness = 0.75; // 中等深色 -> 浅色
      } else if (hsl.l < 0.7) {
        targetLightness = 0.80; // 中等色 -> 较浅色
      } else {
        targetLightness = Math.min(0.85, hsl.l + 0.10); // 已经浅的颜色只略微调整
      }
    }

    if (saturationFactor !== undefined) {
      targetSaturation = saturationFactor;
    } else {
      // 保持较高饱和度,避免颜色变灰
      if (hsl.s < 0.3) {
        targetSaturation = 0.50; // 低饱和度提升
      } else if (hsl.s < 0.6) {
        targetSaturation = Math.min(0.75, hsl.s + 0.15); // 中等饱和度适度提升
      } else {
        targetSaturation = Math.max(0.65, hsl.s - 0.05); // 高饱和度略微降低,保持鲜艳
      }
    }

    const newHsl: MyHSLColor = {
      h: hsl.h, // 色相完全保持不变
      s: Math.max(0.4, Math.min(0.9, targetSaturation)), // 饱和度范围 0.4-0.9
      l: Math.max(0.65, Math.min(0.85, targetLightness)), // 亮度范围 0.65-0.85
    };

    return ColorUtil.hslToHex(newHsl);
  }

  /**
   * [Soft Version] 生成一个柔和的浅色版本，饱和度调整策略更保守。
   * 对于高饱和度颜色会适当降低饱和度，以获得更柔和的观感。
   *
   * @param hex 基础十六进制颜色字符串。
   * @param lightnessFactor 可选，用于强制指定目标亮度 (0-1)。
   * @param saturationFactor 可选，用于强制指定目标饱和度 (0-1)。
   * @returns 返回一个新的、更柔和的十六进制浅色字符串。
   */
  static generateLighterColor(hex: string, lightnessFactor: number = 0.95, saturationFactor?: number): string {
    // 使用修复后的高精度转换函数，避免色相偏移
    const hsl = ColorUtil.hexToHsl(hex);
    if (!hsl) {
      hilog.error(0x0000, TAG, 'no hsl color!');
      return '#F0F0F0';
    }

    let targetLightness = hsl.l + 0.29;
    targetLightness = Math.max(0.85, Math.min(0.96, targetLightness));

    if (lightnessFactor !== undefined) {
      targetLightness = Math.max(0.85, Math.min(0.96, lightnessFactor));
    }

    let targetSaturation = hsl.s;
    if (saturationFactor !== undefined) {
      targetSaturation = saturationFactor;
    } else {
      if (hsl.s > 0.8) {
        targetSaturation = Math.max(0.7, hsl.s - 0.1); // 高饱和度颜色略微降低饱和度
      } else if (hsl.s < 0.4) {
        targetSaturation = Math.min(0.6, hsl.s + 0.1); // 低饱和度颜色略微提高饱和度
      }
    }

    const newHsl: MyHSLColor = {
      h: hsl.h,
      s: targetSaturation,
      l: targetLightness,
    };

    return ColorUtil.hslToHex(newHsl);
  }

  static generateVibrantVariant(hex: string, lightenStep: number = 0.1, saturateStep: number = 0.1): string {
    const hsl = ColorUtil.hexToHsl(hex);
    if (!hsl) {
      hilog.error(0x0000, TAG, 'Could not generate vibrant variant, invalid source hex: ' + hex);
      return hex;
    }
    const newLightness = Math.min(0.95, hsl.l + lightenStep);
    const newSaturation = Math.min(1.0, hsl.s + saturateStep);
    const vibrantHsl: MyHSLColor = {
      h: hsl.h,
      s: newSaturation,
      l: newLightness,
    };
    return ColorUtil.hslToHex(vibrantHsl);
  }

  static hexToRgb(hex: string): MyRGBColor | null {
    const cleanHex = hex.replace('#', '');
    if (cleanHex.length !== 6 && cleanHex.length !== 3) {
      return null;
    }
    const shorthandRegex = /^#?([a-f\d])([a-f\d])([a-f\d])$/i;
    const fullHex = cleanHex.replace(shorthandRegex, (m: string, r: string, g: string, b: string): string => r + r + g + g + b + b);
    const result = /^([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(fullHex);
    if (!result) return null;
    return {
      r: parseInt(result[1], 16),
      g: parseInt(result[2], 16),
      b: parseInt(result[3], 16)
    };
  }

  static lightenColor(hex: string, factor: number = 0.15): string {
    const rgb = ColorUtil.hexToRgb(hex);
    if (!rgb) {
      return '#F0F0F0';
    }
    const lightenedR = Math.round(rgb.r + (255 - rgb.r) * factor);
    const lightenedG = Math.round(rgb.g + (255 - rgb.g) * factor);
    const lightenedB = Math.round(rgb.b + (255 - rgb.b) * factor);
    const toHex = (value: number): string => value.toString(16).padStart(2, '0').toUpperCase();
    return `#${toHex(lightenedR)}${toHex(lightenedG)}${toHex(lightenedB)}`;
  }

  static getRandomDataVizColor(): string {
    const colors: string[] = [
      '#4D94FF', '#FFC166', '#4AC9C2', '#CCB380',
      '#CCFF8A', '#66D9A8', '#EF4444', '#8B5CF6',
      '#06B6D4', '#F97316', '#EC4899', '#84CC16'
    ];
    const randomIndex = Math.floor(Math.random() * colors.length);
    return colors[randomIndex];
  }

  /**
   * 规范化十六进制颜色字符串为 #RRGGBB 格式。
   * 兼容 #RGB, #RRGGBB, #AARRGGBB (取后6位)。
   * @param hex 原始颜色字符串
   * @returns 规范化后的六位十六进制颜色字符串
   */
  static normalizeHexColor(hex: string): string {
    if (!hex) return '#000000';
    // 移除非十六进制字符
    let clean = hex.replace(/[^0-9A-Fa-f]/g, '');

    if (clean.length === 3) {
      // RGB -> RRGGBB
      clean = clean.split('').map(c => c + c).join('');
    } else if (clean.length === 8) {
      // AARRGGBB -> RRGGBB (HarmonyOS通常是AARRGGBB)
      clean = clean.substring(2);
    } else if (clean.length > 6) {
      // 取最后6位
      clean = clean.substring(clean.length - 6);
    } else if (clean.length < 6) {
      // 长度不足6位，补零或返回默认黑色
      return '#000000';
    }

    return `#${clean.toUpperCase()}`;
  }
}

export interface MyRGBColor {
  r: number,
  g: number,
  b: number
}

export interface MyHSLColor {
  h: number; // 色相, 0-1
  s: number; // 饱和度, 0-1
  l: number; // 亮度, 0-1
}