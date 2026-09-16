import { ConfigurationConstant } from '@kit.AbilityKit';

export const COLOR_MODE_STORAGE_KEY: string = 'currentColorMode';
// 单调递增的版本号：每次确认的系统配色回调都会 +1，用于触发 shader/visualEffect 重建。
// 不能用 colorMode 值本身做触发源——应用内切换主题时 AppStorage 会被提前同步写入，
// 等系统真正切换资源后回调再写同样的值，@Watch 不会二次触发。
export const COLOR_MODE_VERSION_KEY: string = 'currentColorModeVersion';

export class ColorModeUtil {
  static isDarkMode(colorMode?: number): boolean {
    return colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  static normalize(colorMode?: number): number {
    return typeof colorMode === 'number'
      ? colorMode
      : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }

  static describe(colorMode?: number): string {
    return ColorModeUtil.isDarkMode(colorMode) ? 'dark' : 'light';
  }
}
