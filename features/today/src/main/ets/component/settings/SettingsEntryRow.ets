import { HdsListItemCard, IconSize, PrefixIcon, SuffixArrow } from '@kit.UIDesignKit';

@Component
export struct SettingsEntryRow {
  @Prop title: Resource = $r('app.string.settings_title');
  @Prop icon: Resource = $r('sys.symbol.gearshape');

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
        }
      },
      suffixItem: new SuffixArrow({
        color: $r('app.color.neutral_800')
      })
    })
  }
}

@Component
export struct SettingsSectionHeader {
  @Prop title: Resource = $r('app.string.settings_title');

  build() {
    Text(this.title)
      .fontSize($r('app.float.settings_section_title_font_size'))
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .padding({
        left: $r('app.float.settings_section_title_padding_start'),
        bottom: $r('app.float.settings_section_title_padding_bottom')
      })
  }
}
