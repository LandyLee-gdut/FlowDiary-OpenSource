import { ItemRestriction, LengthMetrics, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem } from '@kit.ArkUI';
import { HdsListItemCard, IconSize, PrefixIcon } from '@kit.UIDesignKit';
import { AppShadows, BreakpointConstants, VibratorUtil } from 'base';
import { REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION } from '../ReflectChartSettingsMotionTokens';
import { SettingsToggleRow } from './SettingsControlRows';
import { SettingsPageHeader } from './SettingsPageHeader';

@Component
export struct AppearanceSettingsPage {
  @Prop floatingActionBarEnabled: boolean = false;
  @Prop isDarkTheme: boolean = false;
  @Prop holdingHandEnabled: boolean = false;
  @Prop holdingHandOffsetPercent: number = 0;
  @Prop currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @Link tabSelectedIndexes: number[];
  onBack?: () => void;
  onFloatingActionBarToggle?: (isOn: boolean) => void;
  onHoldingHandToggle?: (isOn: boolean) => void;
  onHoldingHandOffsetChange?: (nextValue: number) => void;
  @State private themeTabOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [
      { text: $r('app.string.settings_theme_system') },
      { text: $r('app.string.settings_theme_light') },
      { text: $r('app.string.settings_theme_dark') }
    ] as ItemRestriction<SegmentButtonTextItem>,
    backgroundColor: $r('app.color.segment_background'),
    selectedFontSize: $r('app.float.settings_segment_font_size'),
    selectedBackgroundColor: $r('app.color.segment_selected_background'),
    selectedFontColor: $r('app.color.primary'),
    selectedFontWeight: FontWeight.Bold,
    fontSize: $r('app.float.settings_segment_font_size'),
    fontWeight: FontWeight.Medium,
    fontColor: $r('app.color.text_secondary'),
    localizedButtonPadding: {
      end: LengthMetrics.resource($r('app.float.settings_segment_button_padding')),
      start: LengthMetrics.resource($r('app.float.settings_segment_button_padding'))
    }
  });
  private pageInfos: NavPathStack = new NavPathStack();
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  private handleBack(): void {
    if (this.onBack) {
      this.onBack();
      return;
    }
    this.pageInfos.pop(1);
  }

  private adjustHoldingHandOffset(deltaPercent: number): void {
    const nextValue: number = Math.min(50, Math.max(0, this.holdingHandOffsetPercent + deltaPercent));
    if (nextValue === this.holdingHandOffsetPercent) {
      return;
    }
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    this.onHoldingHandOffsetChange?.(nextValue);
  }

  build() {
    NavDestination() {
      Column() {
        SettingsPageHeader({
          title: $r('app.string.settings_entry_appearance'),
          onAction: () => {
            this.handleBack();
          }
        })

        List() {
          ListItemGroup() {
            ListItem() {
              Stack({ alignContent: Alignment.End }) {
                HdsListItemCard({
                  cardBackgroundColor: $r('app.color.transparent'),
                  cardPrefixMargin: $r('app.string.card_margin'),
                  cardSuffixMargin: $r('app.string.card_margin'),
                  prefixItem: new PrefixIcon({
                    iconSize: IconSize.SYSTEM_ICON,
                    iconValue: {
                      symbol: $r('sys.symbol.dark_mode')
                    }
                  }),
                  textItem: {
                    primaryText: {
                      text: $r('app.string.dark_mode')
                    }
                  }
                })

                SegmentButton({ options: this.themeTabOptions, selectedIndexes: this.tabSelectedIndexes })
                  .width($r('app.float.settings_segment_width'))
                  .height($r('app.float.settings_segment_height'))
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => {
                    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                  })
                  .borderRadius($r('app.float.settings_segment_radius'))
                  .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE)
                  .offset({ x: $r('app.float.settings_segment_offset_x') })
              }
            }
            .borderRadius({
              topLeft: $r('app.float.settings_card_radius'),
              topRight: $r('app.float.settings_card_radius')
            })
            .backgroundColor($r('app.color.bg_card'))

            ListItem() {
              SettingsToggleRow({
                title: $r('app.string.settings_floating_action_bar'),
                detail: $r('app.string.settings_floating_action_bar_detail'),
                icon: $r('sys.symbol.rays'),
                checked: this.floatingActionBarEnabled,
                onChange: (isOn: boolean) => {
                  this.onFloatingActionBarToggle?.(isOn);
                }
              })
            }
            .borderRadius({
              bottomLeft: $r('app.float.settings_card_radius'),
              bottomRight: $r('app.float.settings_card_radius')
            })
            .backgroundColor($r('app.color.bg_card'))
          }
          .borderRadius($r('app.float.settings_card_radius'))

          if (this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_LG) {
            ListItemGroup() {
              ListItem() {
                SettingsToggleRow({
                  title: $r('app.string.settings_holding_hand'),
                  detail: $r('app.string.settings_holding_hand_detail'),
                  icon: $r('sys.symbol.hand_raised_hexagon'),
                  checked: this.holdingHandEnabled,
                  onChange: (isOn: boolean) => {
                    this.onHoldingHandToggle?.(isOn);
                  }
                })
              }
              .borderRadius(this.holdingHandEnabled ? {
                topLeft: $r('app.float.settings_card_radius'),
                topRight: $r('app.float.settings_card_radius')
              } : $r('app.float.settings_card_radius'))
              .backgroundColor($r('app.color.bg_card'))

              if (this.holdingHandEnabled) {
                ListItem() {
                  Stack({ alignContent: Alignment.End }) {
                    HdsListItemCard({
                      cardBackgroundColor: $r('app.color.transparent'),
                      cardPrefixMargin: $r('app.string.card_margin'),
                      cardSuffixMargin: $r('app.string.card_margin'),
                      prefixItem: new PrefixIcon({
                        iconSize: IconSize.SYSTEM_ICON,
                        iconValue: {
                          symbol: $r('sys.symbol.arrow_up')
                        }
                      }),
                      textItem: {
                        primaryText: {
                          text: $r('app.string.settings_holding_hand_offset')
                        }
                      }
                    })

                    Row() {
                      Button({ type: ButtonType.Circle }) {
                        SymbolGlyph($r('sys.symbol.minus'))
                          .fontSize($r('app.float.settings_control_icon_size'))
                          .fontWeight(FontWeight.Bold)
                          .fontColor([$r('app.color.text_primary')])
                      }
                      .enabled(this.holdingHandOffsetPercent > 0)
                      .onClick(() => {
                        this.adjustHoldingHandOffset(-10);
                      })
                      .padding($r('app.float.settings_control_button_padding'))
                      .backgroundColor($r('app.color.neutral_100'))
                      .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)

                      Text(`${this.holdingHandOffsetPercent}%`)
                        .fontSize($r('app.float.settings_control_text_font_size'))
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                        .padding({
                          left: $r('app.float.settings_control_text_padding_horizontal'),
                          right: $r('app.float.settings_control_text_padding_horizontal')
                        })

                      Button({ type: ButtonType.Circle }) {
                        SymbolGlyph($r('sys.symbol.plus'))
                          .fontSize($r('app.float.settings_control_icon_size'))
                          .fontWeight(FontWeight.Bold)
                          .fontColor([$r('app.color.text_primary')])
                      }
                      .enabled(this.holdingHandOffsetPercent < 50)
                      .onClick(() => {
                        this.adjustHoldingHandOffset(10);
                      })
                      .padding($r('app.float.settings_control_button_padding'))
                      .backgroundColor($r('app.color.neutral_100'))
                      .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)
                    }
                    .offset({ x: $r('app.float.settings_control_offset_x') })
                  }
                }
                .borderRadius({
                  bottomLeft: $r('app.float.settings_card_radius'),
                  bottomRight: $r('app.float.settings_card_radius')
                })
                .backgroundColor($r('app.color.bg_card'))
              }
            }
            .borderRadius($r('app.float.settings_card_radius'))
            .margin({ top: $r('app.float.settings_section_spacing') })
          }
        }
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: $r('app.float.settings_page_padding_horizontal'),
        right: $r('app.float.settings_page_padding_horizontal'),
        bottom: $r('app.float.settings_page_padding_bottom')
      })
      .backgroundColor($r('app.color.bg_main'))
    }
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
    })
    .onBackPressed((): boolean => {
      this.handleBack();
      return true;
    })
    .hideTitleBar(true)
    .systemTransition(REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
  }
}
