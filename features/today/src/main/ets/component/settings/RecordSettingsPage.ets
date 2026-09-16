import { promptAction } from '@kit.ArkUI';
import { HdsListItemCard, IconSize, PrefixIcon } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VibratorUtil } from 'base';
import {
  AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT,
  clampAutoStopLimitHalfHours
} from '../../model/AutoStopSettings';
import { REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION } from '../ReflectChartSettingsMotionTokens';
import { SettingsSelectRow, SettingsToggleRow } from './SettingsControlRows';
import { SettingsPageHeader } from './SettingsPageHeader';

const TAG: string = 'RecordSettingsPage';

@Component
export struct RecordSettingsPage {
  @Prop directStartEnabled: boolean = false;
  @Watch('onAutoStopEnabledPropChanged') @Prop autoStopEnabled: boolean = false;
  @Watch('onAutoStopLimitPropChanged') @Prop autoStopLimitHalfHours: number = AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT;
  @Prop defaultLinePanelEnabled: boolean = false;
  onBack?: () => void;
  onDirectStartToggle?: (isOn: boolean) => void;
  onAutoStopEnabledChange?: (enabled: boolean) => void;
  onAutoStopLimitHalfHoursChange?: (limitHalfHours: number) => void;
  onDefaultLinePanelToggle?: (isOn: boolean) => void;
  @State private localAutoStopEnabled: boolean = false;
  @State private localAutoStopLimitHalfHours: number = AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT;
  @State private limitInputText: string = '';
  private pageInfos: NavPathStack = new NavPathStack();
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  aboutToAppear(): void {
    this.syncAutoStopState();
  }

  private onAutoStopEnabledPropChanged(): void {
    this.syncAutoStopState();
  }

  private onAutoStopLimitPropChanged(): void {
    this.syncAutoStopState();
  }

  private syncAutoStopState(): void {
    this.localAutoStopEnabled = this.autoStopEnabled;
    this.localAutoStopLimitHalfHours = clampAutoStopLimitHalfHours(this.autoStopLimitHalfHours);
    this.limitInputText = this.resolveLimitInputText(this.localAutoStopLimitHalfHours);
  }

  private handleBack(): void {
    if (this.onBack) {
      this.onBack();
      return;
    }
    this.pageInfos.pop(1);
  }

  private handleAutoStopEnabledChange(enabled: boolean): void {
    if (enabled === this.localAutoStopEnabled) {
      return;
    }
    this.localAutoStopEnabled = enabled;
    this.onAutoStopEnabledChange?.(enabled);
  }

  private handleAutoStopLimitChange(limitHalfHours: number): void {
    const normalizedLimit: number = clampAutoStopLimitHalfHours(limitHalfHours);
    if (normalizedLimit === this.localAutoStopLimitHalfHours) {
      return;
    }
    this.localAutoStopLimitHalfHours = normalizedLimit;
    this.limitInputText = this.resolveLimitInputText(normalizedLimit);
    this.onAutoStopLimitHalfHoursChange?.(normalizedLimit);
  }

  private getChartPanelOptions(): SelectOption[] {
    return [
      { value: $r('app.string.data_panel_chart_pie') },
      { value: $r('app.string.data_panel_chart_line') }
    ];
  }

  private canDecreaseLimit(): boolean {
    return this.localAutoStopLimitHalfHours > 1;
  }

  private canIncreaseLimit(): boolean {
    return this.localAutoStopLimitHalfHours < 48;
  }

  private resolveLimitInputText(limitHalfHours: number): string {
    const normalizedLimit: number = clampAutoStopLimitHalfHours(limitHalfHours);
    if (normalizedLimit % 2 === 0) {
      return `${normalizedLimit / 2}`;
    }
    return `${Math.floor(normalizedLimit / 2)}.5`;
  }

  private normalizeLimitInputText(value: string): string {
    const sanitizedValue: string = value.replace(/[^0-9.]/g, '');
    const firstDotIndex: number = sanitizedValue.indexOf('.');
    if (firstDotIndex < 0) {
      return sanitizedValue;
    }
    const integerPart: string = firstDotIndex === 0 ? '0' : sanitizedValue.slice(0, firstDotIndex);
    const fractionPart: string = sanitizedValue.slice(firstDotIndex + 1).replace(/\./g, '').slice(0, 1);
    return `${integerPart}.${fractionPart}`;
  }

  private parseLimitInputHalfHours(inputValue: string): number | null {
    const trimmedValue: string = inputValue.trim();
    if (trimmedValue.length === 0 || !/^\d+(\.\d)?$/.test(trimmedValue)) {
      return null;
    }
    const parsedHours: number = Number(trimmedValue);
    if (!Number.isFinite(parsedHours) || parsedHours < 0.5 || parsedHours > 24) {
      return null;
    }
    const normalizedHalfHours: number = parsedHours * 2;
    if (!Number.isInteger(normalizedHalfHours)) {
      return null;
    }
    return clampAutoStopLimitHalfHours(normalizedHalfHours);
  }

  private commitLimitInputText(): void {
    const parsedHalfHours: number | null = this.parseLimitInputHalfHours(this.limitInputText);
    if (parsedHalfHours === null) {
      this.limitInputText = this.resolveLimitInputText(this.localAutoStopLimitHalfHours);
      promptAction.openToast({
        message: $r('app.string.auto_stop_settings_limit_invalid_toast'),
        duration: 1500
      }).catch(() => {
        hilog.error(0x0000, TAG, '[Settings] failed to show invalid auto-stop limit toast');
      });
      return;
    }
    this.limitInputText = this.resolveLimitInputText(parsedHalfHours);
    if (parsedHalfHours === this.localAutoStopLimitHalfHours) {
      return;
    }
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    this.handleAutoStopLimitChange(parsedHalfHours);
  }

  private adjustLimit(deltaHalfHours: number): void {
    const nextLimit: number = clampAutoStopLimitHalfHours(this.localAutoStopLimitHalfHours + deltaHalfHours);
    if (nextLimit === this.localAutoStopLimitHalfHours) {
      return;
    }
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    this.handleAutoStopLimitChange(nextLimit);
  }

  build() {
    NavDestination() {
      Column() {
        SettingsPageHeader({
          title: $r('app.string.settings_entry_record'),
          onAction: () => {
            this.handleBack();
          }
        })

        List({ space: 0 }) {
          ListItem() {
            SettingsToggleRow({
              title: $r('app.string.default_directly_record'),
              detail: $r('app.string.settings_direct_record_detail'),
              icon: $r('sys.symbol.collection_panel'),
              checked: this.directStartEnabled,
              onChange: (isOn: boolean) => {
                this.onDirectStartToggle?.(isOn);
              }
            })
          }
          .borderRadius({
            topLeft: $r('app.float.settings_card_radius'),
            topRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsToggleRow({
              title: $r('app.string.auto_stop_settings_entry'),
              detail: $r('app.string.auto_stop_settings_switch_detail'),
              icon: $r('sys.symbol.clock'),
              checked: this.localAutoStopEnabled,
              onChange: (isOn: boolean) => {
                this.handleAutoStopEnabledChange(isOn);
              }
            })
          }
          .backgroundColor($r('app.color.bg_card'))

          if (this.localAutoStopEnabled) {
            ListItem() {
              Stack({ alignContent: Alignment.End }) {
                HdsListItemCard({
                  cardBackgroundColor: $r('app.color.transparent'),
                  cardPrefixMargin: $r('app.string.card_margin'),
                  cardSuffixMargin: $r('app.string.card_margin'),
                  prefixItem: new PrefixIcon({
                    iconSize: IconSize.SYSTEM_ICON,
                    iconValue: {
                      symbol: $r('sys.symbol.clock')
                    }
                  }),
                  textItem: {
                    primaryText: {
                      text: $r('app.string.auto_stop_settings_limit_title')
                    }
                  }
                })

                Row({ space: $r('app.float.auto_stop_settings_control_gap') }) {
                  Button({ type: ButtonType.Circle, stateEffect: true }) {
                    SymbolGlyph($r('sys.symbol.minus'))
                      .fontSize($r('app.float.settings_control_icon_size'))
                      .fontWeight(FontWeight.Bold)
                      .fontColor([$r('app.color.text_primary')])
                  }
                  .enabled(this.canDecreaseLimit())
                  .onClick(() => {
                    this.adjustLimit(-1);
                  })
                  .padding($r('app.float.settings_control_button_padding'))
                  .backgroundColor($r('app.color.neutral_100'))
                  .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)

                  TextInput({
                    text: $$this.limitInputText,
                    placeholder: $r('app.string.auto_stop_settings_input_placeholder')
                  })
                    .maxLength(4)
                    .width($r('app.float.auto_stop_settings_control_input_width'))
                    .height($r('app.float.auto_stop_settings_control_input_height'))
                    .fontSize($r('app.float.auto_stop_settings_limit_value_font_size'))
                    .fontWeight(FontWeight.Bold)
                    .textAlign(TextAlign.Center)
                    .caretColor($r('app.color.primary'))
                    .backgroundColor($r('app.color.transparent'))
                    .placeholderColor($r('app.color.text_secondary'))
                    .placeholderFont({
                      size: $r('app.float.settings_control_text_font_size'),
                      weight: FontWeight.Bold
                    })
                    .padding($r('app.float.settings_control_input_padding'))
                    .onChange((value: string) => {
                      this.limitInputText = this.normalizeLimitInputText(value);
                    })
                    .onBlur(() => {
                      this.commitLimitInputText();
                    })

                  Text($r('app.string.auto_stop_settings_input_unit'))
                    .fontSize($r('app.float.auto_stop_settings_limit_value_font_size'))
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))

                  Button({ type: ButtonType.Circle, stateEffect: true }) {
                    SymbolGlyph($r('sys.symbol.plus'))
                      .fontSize($r('app.float.settings_control_icon_size'))
                      .fontWeight(FontWeight.Bold)
                      .fontColor([$r('app.color.text_primary')])
                  }
                  .enabled(this.canIncreaseLimit())
                  .onClick(() => {
                    this.adjustLimit(1);
                  })
                  .padding($r('app.float.settings_control_button_padding'))
                  .backgroundColor($r('app.color.neutral_100'))
                  .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)
                }
                .margin({ right: $r('app.float.settings_control_margin_end') })
              }
            }
            .backgroundColor($r('app.color.bg_card'))
          }

          ListItem() {
            SettingsSelectRow({
              title: $r('app.string.default_use_panel'),
              icon: $r('sys.symbol.rectangle_split_2x1'),
              options: this.getChartPanelOptions(),
              selectedIndex: this.defaultLinePanelEnabled ? 1 : 0,
              onSelect: (index: number) => {
                this.onDefaultLinePanelToggle?.(index === 1);
              }
            })
          }
          .borderRadius({
            bottomLeft: $r('app.float.settings_card_radius'),
            bottomRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))
        }
        .width('100%')
        .scrollBar(BarState.Off)

        Text($r('app.string.auto_stop_settings_future_only'))
          .width('100%')
          .fontSize($r('app.float.settings_detail_tip_font_size'))
          .lineHeight($r('app.float.settings_detail_tip_line_height'))
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: $r('app.float.settings_detail_tip_margin_top') })
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
