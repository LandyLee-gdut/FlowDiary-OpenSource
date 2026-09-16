import { AppShadows, BreakpointConstants, BreakpointType, MatterItemModel, MatterStatus, TimeRecordUtil } from 'base';
import { hdsEffect } from '@kit.UIDesignKit';

const RECORDING_DEMO_REFERENCE_MS: number = 60 * 60 * 1000;

@Component
export struct MatterItemDemo {
  @Prop item: MatterItemModel = new MatterItemModel();
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @StorageProp(BreakpointConstants.CURRENT_BREAKPOINT) currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  build() {

    Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
      Column() {
        Text(this.item.title)
          .fontWeight(600)
          .fontSize(18)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Row() {
          Row()
            .width(7)
            .height(7)
            .borderRadius('50%')
            .margin({ right: 10 })
            .backgroundColor(this.item.labelColor);
          Text(this.item.label)
            .fontSize(12)
            .fontWeight(400)
            .fontColor($r('app.color.text_secondary'));
        }
        .alignItems(VerticalAlign.Center);
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Start)
      .flexGrow(1)
      .flexShrink(1)
      .height(45);

      Row({ space: this.getTextActionSpacing() }) {
        if (this.item.status === MatterStatus.TODO) {
          this.renderTodoAction();
        } else if (this.item.status === MatterStatus.RECORDING) {
          this.renderRecordingAction();
        } else {
          this.renderPausedAction();
        }
      }
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .height(this.getActionAreaHeight())
      .flexShrink(0);
    }
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER // 照亮区域
      })
      .buildEffect())
    .borderRadius(15)
    .backgroundColor(this.shouldApplyBackground() ? this.getCardFillColor() : null)
    .linearGradient(this.getGradientColors() ? {
      direction: GradientDirection.LeftBottom,
      colors: this.getGradientColors()
    } : null)
    .padding(this.getCardPadding())
    // .shadow(AppShadows.CARD_RESTING)
    .shadow({
      color: $r('app.color.neutral_300'),
      radius: 50,
    })
    .height('100%')
    .width('100%');
  }
  @Builder
  private renderTodoAction(): void {
    Button({ type: ButtonType.Capsule, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.play_fill'))
        .fontColor(['#2E86DE'])
        .fontWeight(700)
        .fontSize(20);
    }
    .width(this.getActionButtonWidth())
    .height(this.getActionButtonHeight())
    .backgroundColor(this.getSecondaryButtonBackground())
    .shadow(AppShadows.CARD_RESTING);
  }
  @Builder
  private renderRecordingAction(): void {
    Column() {
      Column() {
        Text('正在计时...')
          .fontColor($r('app.color.text_secondary'))
          .fontSize(14)
          .fontWeight(500);

        Text(this.formatDuration())
          .fontSize(18)
          .fontWeight(700)
          .fontColor($r('app.color.text_secondary'));
      }
      .height(45)
      .width(this.isSmallBreakpoint() ? '100%' : null)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween);
    }
    .alignItems(this.isSmallBreakpoint() ? HorizontalAlign.Start : HorizontalAlign.End)
    .justifyContent(FlexAlign.Center)
    .height(this.isSmallBreakpoint() ? 45 : null)
    .width(this.isSmallBreakpoint() ? 120 : null)
    .flexGrow(0)
    .flexShrink(1);

    Column() {
      Stack() {
        Progress({ value: this.getRecordingProgressValue(), total: 100, type: ProgressType.Ring })
          .color(Color.Orange)
          .width(60)
          .height(this.getRecordingProgressHeight())
          .style({ strokeWidth: 5, enableSmoothEffect: true })
          .backgroundColor(Color.Transparent);

        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          SymbolGlyph($r('sys.symbol.pause'))
            .fontColor([$r('app.color.neutral_100')])
            .fontWeight(700)
            .fontSize(20);
        }
        .width(this.getActionButtonWidth())
        .height(this.getActionButtonHeight())
        .backgroundColor($r('app.color.error'))
        .shadow({ color: $r('app.color.error'), radius: 20 });
      }
    }
  }
  @Builder
  private renderPausedAction(): void {
    Column() {
      Column() {
        Text('已记录:  ')
          .fontSize($r('app.float.item_recorded_font_size'))
          .fontColor($r('app.color.text_tertiary'))
          .fontWeight(500);
        Text(this.formatDuration())
          .fontSize(18)
          .fontWeight(700)
          .fontColor($r('app.color.text_secondary'));
      }
      .height(45)
      .width(this.isSmallBreakpoint() ? '100%' : null)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween);
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(this.isSmallBreakpoint() ? HorizontalAlign.Start : HorizontalAlign.End)
    .width(this.isSmallBreakpoint() ? 120 : null)
    .flexGrow(0)
    .flexShrink(1);

    Button({ type: ButtonType.Capsule, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontColor(['#2E86DE'])
        .fontWeight(700)
        .fontSize(20);
    }
    .width(this.getActionButtonWidth())
    .height(this.getActionButtonHeight())
    .backgroundColor(this.getSecondaryButtonBackground())
    .shadow(AppShadows.CARD_RESTING);
  }

  private formatDuration(): string {
    return TimeRecordUtil.formatTime(this.item.durationInMilliseconds);
  }

  private getRecordingProgressValue(): number {
    if (this.item.status !== MatterStatus.RECORDING) {
      return 0;
    }
    if (this.item.durationInMilliseconds <= 0) {
      return 0;
    }
    const progress = Math.round((this.item.durationInMilliseconds / RECORDING_DEMO_REFERENCE_MS) * 100);
    return Math.min(100, Math.max(0, progress));
  }

  private getActionButtonWidth(): number {
    return new BreakpointType<number>({ sm: 56, md: 56, lg: 60 }).getValue(this.currentBreakpoint);
  }

  private getActionButtonHeight(): number {
    return new BreakpointType<number>({ sm: 38, md: 38, lg: 40 }).getValue(this.currentBreakpoint);
  }

  private getActionAreaHeight(): number {
    if (this.item.status === MatterStatus.RECORDING) {
      return this.getRecordingProgressHeight();
    }
    return Math.max(this.getActionButtonHeight(), 45);
  }

  private getRecordingProgressHeight(): number {
    return new BreakpointType<number>({ sm: 90, md: 100, lg: 110 }).getValue(this.currentBreakpoint);
  }

  private getTextActionSpacing(): number {
    return new BreakpointType<number>({ sm: 6, md: 8, lg: 10 }).getValue(this.currentBreakpoint);
  }

  private isSmallBreakpoint(): boolean {
    return this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM;
  }

  private getCardPadding(): number {
    return new BreakpointType<number>({
      sm: 14,
      md: 16,
      lg: 20
    }).getValue(this.currentBreakpoint);
  }

  private shouldApplyBackground(): boolean {
    return this.isDarkTheme || (this.item.status === MatterStatus.RECORDING && !!this.item.labelColor);
  }

  private getGradientColors(): Array<[string | ResourceColor, number]> | null {
    if (this.isDarkTheme) {
      return null;
    }
    if (this.item.status === MatterStatus.RECORDING) {
      return [
        [$r('app.color.day_review_loading_gradient_start'), 0],
        [$r('app.color.neutral_100'), 0.4],
        [$r('app.color.day_review_loading_gradient_end'), 1],
      ];
    }
    return [
      [$r('app.color.matter_card_gradient_start'), 0],
      [$r('app.color.matter_card_gradient_end'), 1],
    ];
  }

  private getCardFillColor(): string | ResourceColor {
    if (this.isDarkTheme) {
      return $r('app.color.matter_card_fill');
    }
    if (this.item.status === MatterStatus.RECORDING && this.item?.labelColor) {
      return this.item.labelColor;
    }
    return $r('app.color.matter_card_fill');
  }

  private getSecondaryButtonBackground(): ResourceColor | string {
    return $r('app.color.matter_card_secondary_button_bg');
  }
}
