import { VibratorUtil } from 'base';

@Component
export struct SettingsPageHeader {
  @Prop title: Resource = $r('app.string.settings_title');
  @Prop showCloseButton: boolean = false;
  onAction?: () => void;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  build() {
    Row() {
      if (!this.showCloseButton) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize($r('app.float.settings_header_icon_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor([$r('app.color.text_primary')])
        }
        .onClick(() => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
          this.onAction?.();
        })
        .margin({ right: $r('app.float.settings_header_action_margin_end') })
        .padding($r('app.float.settings_header_action_padding'))
        .backgroundColor($r('app.color.neutral_100'))
        .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)
      }

      Text(this.title)
        .fontWeight(FontWeight.Bold)
        .fontSize($r('app.float.settings_header_title_font_size'))
        .fontColor($r('app.color.text_primary'))

      if (this.showCloseButton) {
        Blank()

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize($r('app.float.settings_header_icon_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor([$r('app.color.text_primary')])
        }
        .onClick(() => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
          this.onAction?.();
        })
        .padding($r('app.float.settings_header_action_padding'))
        .backgroundColor($r('app.color.neutral_100'))
        .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)
      }
    }
    .width('100%')
    .height($r('app.float.settings_header_height'))
    .alignItems(VerticalAlign.Center)
  }
}
