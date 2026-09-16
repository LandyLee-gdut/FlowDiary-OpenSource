import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ColorConversion';

/**
 * HSB 颜色接口
 */
interface HSBColor {
  h: number;
  s: number;
  b: number;
}

/**
 * RGB 颜色接口
 */
interface RGBColor {
  r: number;
  g: number;
  b: number;
}

/**
 * 颜色转换工具类
 * 用于将 RGB 转换为 HSB，对亮度和饱和度进行调整，再转换回 RGB
 * 适用于从图片提取主色后生成适合大面积背景的颜色
 */
export class ColorConversion {
  /**
   * 处理颜色：将 RGB 转换为 HSB，调整亮度和饱和度，再转换回 RGB
   * 
   * @param rRGB 红色分量 (0-1)
   * @param gRGB 绿色分量 (0-1)
   * @param bRGB 蓝色分量 (0-1)
   * @returns RGB 数组 [r, g, b]，每个值在 0-255 范围内
   */
  public static dealColor(rRGB: number, gRGB: number, bRGB: number): number[] {
    // 1. 将 RGB 转换为 HSB
    const hsb = ColorConversion.rgbToHsb(rRGB, gRGB, bRGB);
    
    // 2. 对亮度 bHSB 做阈值与偏移处理（防止过亮/过暗）
    let adjustedBrightness = hsb.b;
    let adjustedSaturation = hsb.s;
    
    // 亮度调整：限制在 0.15-0.85 之间，避免过亮或过暗
    if (adjustedBrightness < 0.15) {
      adjustedBrightness = 0.15;
    } else if (adjustedBrightness > 0.85) {
      adjustedBrightness = 0.85;
    }
    
    // 饱和度调整：适当降低饱和度，使背景色更柔和
    if (adjustedSaturation > 0.7) {
      adjustedSaturation = 0.7;
    } else if (adjustedSaturation < 0.3) {
      adjustedSaturation = 0.3;
    }
    
    // 3. 从 HSB 转换回 RGB
    const rgb = ColorConversion.hsbToRgb(hsb.h, adjustedSaturation, adjustedBrightness);
    
    return [
      Math.floor(rgb.r * 255.0),
      Math.floor(rgb.g * 255.0),
      Math.floor(rgb.b * 255.0)
    ];
  }
  
  /**
   * 将 RGB 转换为 HSB (Hue, Saturation, Brightness)
   * 
   * @param r 红色分量 (0-1)
   * @param g 绿色分量 (0-1)
   * @param b 蓝色分量 (0-1)
   * @returns HSB 对象，h/s/b 都在 0-1 范围内
   */
  private static rgbToHsb(r: number, g: number, b: number): HSBColor {
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const delta = max - min;
    
    let h = 0;
    let s = 0;
    const bVal = max;
    
    // 计算饱和度
    if (max !== 0) {
      s = delta / max;
    }
    
    // 计算色相
    if (delta !== 0) {
      if (max === r) {
        h = ((g - b) / delta) % 6;
      } else if (max === g) {
        h = (b - r) / delta + 2;
      } else {
        h = (r - g) / delta + 4;
      }
      h = h / 6;
      if (h < 0) {
        h += 1;
      }
    }
    
    return { h, s, b: bVal };
  }
  
  /**
   * 将 HSB 转换为 RGB
   * 
   * @param h 色相 (0-1)
   * @param s 饱和度 (0-1)
   * @param b 亮度 (0-1)
   * @returns RGB 对象，r/g/b 都在 0-1 范围内
   */
  private static hsbToRgb(h: number, s: number, b: number): RGBColor {
    let r = 0;
    let g = 0;
    let blue = 0;
    
    if (s === 0) {
      // 灰度
      r = g = blue = b;
    } else {
      const i = Math.floor(h * 6);
      const f = (h * 6) - i;
      const p = b * (1 - s);
      const q = b * (1 - f * s);
      const t = b * (1 - (1 - f) * s);
      
      switch (i % 6) {
        case 0:
          r = b;
          g = t;
          blue = p;
          break;
        case 1:
          r = q;
          g = b;
          blue = p;
          break;
        case 2:
          r = p;
          g = b;
          blue = t;
          break;
        case 3:
          r = p;
          g = q;
          blue = b;
          break;
        case 4:
          r = t;
          g = p;
          blue = b;
          break;
        case 5:
          r = b;
          g = p;
          blue = q;
          break;
      }
    }
    
    return { r, g, b: blue };
  }
}