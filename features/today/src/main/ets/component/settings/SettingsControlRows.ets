import { HdsListItemCard, IconSize, PrefixIcon, SuffixArrow, SuffixSwitch } from '@kit.UIDesignKit';
import { VibratorUtil } from 'base';

@Component
export struct SettingsToggleRow {
  @Prop title: Resource = $r('app.string.settings_title');
  @Prop detail: Resource = $r('app.string.settings_title');
  @Prop icon: Resource = $r('sys.symbol.gearshape');
  @Prop checked: boolean = false;
  onChange?: (checked: boolean) => void;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  build() {
    HdsListItemCard({
      cardBackgroundColor: $r('app.color.transparent'),
      cardPrefixMargin: $r('app.string.card_margin'),
      cardSuffixMargin: $r('app.string.card_margin'),
      prefixItem: new PrefixIcon({
        iconSize: IconSize.SYSTEM_ICON,
        iconValue: {
          symbol: this.icon
        }
      }),
      textItem: {
        primaryText: {
          text: this.title
        },
        secondaryText: {
          text: this.detail
        }
      },
      suffixItem: new SuffixSwitch({
        isCheck: this.checked,
        selectColor: $r('app.color.primary'),
        onChange: (checked: boolean) => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
          this.onChange?.(checked);
        }
      })
    })
  }
}

@Component
export struct SettingsSelectRow {
  @Prop title: Resource = $r('app.string.settings_title');
  @Prop icon: Resource = $r('sys.symbol.gearshape');
  @Prop options: SelectOption[] = [];
  @Prop selectedIndex: number = 0;
  onSelect?: (index: number) => void;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  private getSelectedValue(): ResourceStr {
    if (this.selectedIndex >= 0 && this.selectedIndex < this.options.length) {
      return this.options[this.selectedIndex].value;
    }
    return '';
  }

  build() {
    Stack({ alignContent: Alignment.End }) {
      HdsListItemCard({
        cardBackgroundColor: $r('app.color.transparent'),
        cardPrefixMargin: $r('app.string.card_margin'),
        cardSuffixMargin: $r('app.string.card_margin'),
        prefixItem: new PrefixIcon({
          iconSize: IconSize.SYSTEM_ICON,
          iconValue: {
            symbol: this.icon
          }
        }),
        textItem: {
          primaryText: {
            text: this.title
          }
        }
      })

      Select(this.options)
        .selected(this.selectedIndex)
        .value(this.getSelectedValue())
        .font({ size: $r('app.float.settings_control_text_font_size'), weight: FontWeight.Bold })
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.transparent'))
        .offset({ x: $r('app.float.settings_control_offset_x') })
        .onSelect((index: number) => {
          if (index === this.selectedIndex) {
            return;
          }
          this.selectedIndex = index;
          void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
          this.onSelect?.(index);
        })
    }
  }
}

@Component
export struct SettingsActionRow {
  @Prop title: Resource = $r('app.string.settings_title');
  @Prop detail: Resource = $r('app.string.settings_title');
  @Prop statusText: string = '';
  @Prop icon: Resource = $r('sys.symbol.gearshape');
  @Prop showArrow: boolean = true;
  onAction?: () => void;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  build() {
    HdsListItemCard({
      cardBackgroundColor: $r('app.color.transparent'),
      cardPrefixMargin: $r('app.string.card_margin'),
      cardSuffixMargin: $r('app.string.card_margin'),
      prefixItem: new PrefixIcon({
        iconSize: IconSize.SYSTEM_ICON,
        iconValue: {
          symbol: this.icon
        }
      }),
      textItem: {
        primaryText: {
          text: this.title
        },
        secondaryText: {
          text: this.statusText.length > 0 ? this.statusText : this.detail
        }
      },
      suffixItem: this.showArrow ? new SuffixArrow({
        color: $r('app.color.neutral_800')
      }) : undefined
    })
    .onClick(() => {
      void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
      this.onAction?.();
    })
  }
}
