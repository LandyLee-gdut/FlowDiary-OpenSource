import { AppShadows } from 'base';

const SUMMARY_CARD_HEIGHT: number = 78;
const SUMMARY_CARD_RADIUS: number = 22;
const SUMMARY_CARD_PADDING_H: number = 18;
const SUMMARY_CARD_PADDING_V: number = 14;
const SUMMARY_CARD_GAP: number = 12;
const SUMMARY_TITLE_FONT_SIZE: number = 14;
const SUMMARY_TITLE_FONT_WEIGHT: number = 400;
const SUMMARY_COUNT_FONT_SIZE: number = 25;
const SUMMARY_COUNT_FONT_WEIGHT: number = 800;
const SUMMARY_COUNT_MARGIN_TOP: number = 8;
const SUMMARY_CARD_BORDER_WIDTH: number = 1;

export enum SummaryCardVariant {
  UNLIT = 0,
  LIT = 1
}

@Component
export struct IdeaLightSummaryCard {
  @Prop title: ResourceStr = '';
  @Prop count: number = 0;
  @Prop valueText: ResourceStr | null = null;
  @Prop variant: SummaryCardVariant = SummaryCardVariant.UNLIT;
  @Prop isDarkTheme: boolean = false;
  @Prop titleFontSize: number | Resource = SUMMARY_TITLE_FONT_SIZE;
  @Prop valueFontSize: number | Resource = SUMMARY_COUNT_FONT_SIZE;
  @Prop alignCenter: boolean = false;
  @State numberTransition: NumericTextTransition =
    new NumericTextTransition({ flipDirection: FlipDirection.DOWN, enableBlur: false });

  private getValueText(): ResourceStr {
    if (this.valueText !== null) {
      return this.valueText;
    }
    return this.count.toString();
  }

  private getValueTransition(): NumericTextTransition | undefined {
    if (this.valueText !== null) {
      return undefined;
    }
    return this.numberTransition;
  }

  private getCardAlignment(): HorizontalAlign {
    return this.alignCenter ? HorizontalAlign.Center : HorizontalAlign.Start;
  }

  private getBackgroundColor(): ResourceColor {
    return this.variant === SummaryCardVariant.LIT
      ? $r('app.color.summary_lit_background')
      : $r('app.color.bg_card');
  }

  private getBorderColor(): ResourceColor {
    return this.variant === SummaryCardVariant.LIT
      ? $r('app.color.summary_lit_border')
      : $r('app.color.neutral_200');
  }

  private getTitleColor(): ResourceColor {
    return this.variant === SummaryCardVariant.LIT
      ? $r('app.color.accent_dark')
      : $r('app.color.text_tertiary');
  }

  private getCountColor(): ResourceColor {
    return this.variant === SummaryCardVariant.LIT
      ? $r('app.color.accent_darker')
      : $r('app.color.text_primary');
  }

  private getShadow(): ShadowOptions {
    return this.isDarkTheme ? AppShadows.LIGHT_SHADOW_DARK : AppShadows.LIGHT_SHADOW;
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(this.titleFontSize)
        .fontWeight(SUMMARY_TITLE_FONT_WEIGHT)
        .fontColor(this.getTitleColor())

      Text(this.getValueText())
        .fontSize(this.valueFontSize)
        .fontWeight(SUMMARY_COUNT_FONT_WEIGHT)
        .fontColor(this.getCountColor())
        .margin({ top: SUMMARY_COUNT_MARGIN_TOP })
        .contentTransition(this.getValueTransition())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(this.getCardAlignment())
    .padding({
      left: SUMMARY_CARD_PADDING_H,
      right: SUMMARY_CARD_PADDING_H,
      top: SUMMARY_CARD_PADDING_V,
      bottom: SUMMARY_CARD_PADDING_V
    })
    .backgroundColor(this.getBackgroundColor())
    .border({ width: SUMMARY_CARD_BORDER_WIDTH, color: this.getBorderColor() })
    .borderRadius(SUMMARY_CARD_RADIUS)
    .shadow(this.getShadow())
  }
}

@Component
export struct IdeaLightSummaryCards {
  @Prop unlitCount: number = 0;
  @Prop litCount: number = 0;
  @Prop isDarkTheme: boolean = false;

  build() {
    Row({ space: SUMMARY_CARD_GAP }) {
      IdeaLightSummaryCard({
        title: $r('app.string.ideapool_summary_unlit'),
        count: this.unlitCount,
        variant: SummaryCardVariant.UNLIT,
        isDarkTheme: this.isDarkTheme
      })
        .layoutWeight(1)

      IdeaLightSummaryCard({
        title: $r('app.string.ideapool_summary_lit'),
        count: this.litCount,
        variant: SummaryCardVariant.LIT,
        isDarkTheme: this.isDarkTheme
      })
        .layoutWeight(1)
    }
    .height('100%')
    .width('100%')
  }
}
