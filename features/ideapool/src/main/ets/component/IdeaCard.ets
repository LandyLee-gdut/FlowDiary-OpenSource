import {
  IdeaActivity,
  IdeaLightState,
  TimeRecordUtil,
  AppShadows,
  buildPointLightEffect
} from 'base';
import { curves } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';

@Component
export struct IdeaCard {
  private static readonly CARD_TOUCH_LIGHT_HEIGHT = 200;
  private static readonly BUTTON_TOUCH_LIGHT_HEIGHT = 240;
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @State isCardPressed: boolean = false;
  @State isEditButtonPressed: boolean = false;
  @State isMoveButtonPressed: boolean = false;
  @ObjectLink idea: IdeaActivity;
  @Prop relativeTimeBaseline: number = Date.now();
  @Prop isInteractionEnabled: boolean = true;
  onMoveToToday?: () => void;
  onEdit?: () => void;
  onExpand?: () => void;
  onLongPress?: () => void;

  private isIdeaLit(): boolean {
    return this.idea.ideaLightState === IdeaLightState.LIT;
  }

  private setEditButtonGlowActive(active: boolean): void {
    this.isEditButtonPressed = active;
  }

  private setMoveButtonGlowActive(active: boolean): void {
    this.isMoveButtonPressed = active;
  }

  build() {
    Column() {
      // 上方名称和按钮选秀
      Row() {
        Text(this.idea.name)
          .fontSize(16)
          .fontWeight(700)
          .fontColor(this.isIdeaLit() ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .width('75%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(16)
            .fontWeight(400)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.5 })
        .visualEffect(buildPointLightEffect({
          preset: 'buttonTouch',
          color: $r('app.color.immersive_glow_primary'),
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
          isActive: this.isEditButtonPressed,
          isDarkTheme: this.isDarkTheme,
          overrides: {
            height: IdeaCard.BUTTON_TOUCH_LIGHT_HEIGHT
          }
        }))
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.setEditButtonGlowActive(true);
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.setEditButtonGlowActive(false);
          }
        })
        .shadow({ color: $r('app.color.accent_lighter'), radius: 10})
        .padding(5)
        .backgroundColor(this.isIdeaLit() ? $r('app.color.bg_main') : $r('app.color.neutral_100'))
        .border({
          width: this.isIdeaLit() ? 0 : 1,
          color: this.isIdeaLit() ? Color.Transparent : $r('app.color.neutral_300')
        })
        .onClick(() => {
          if (this.onEdit) {
            this.onEdit();
          }
        })
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .animation({ curve: curves.springMotion(), duration: 120 })

      Column() {
        Row() {
          Row()
            .width(8)
            .height(8)
            .borderRadius('50%')
            .margin({right: 5})
            .backgroundColor(this.isIdeaLit() ? this.idea.tagColorHex ?? $r('app.color.tag_placeholder_gray') : this.idea.tagLightColorHex)
          Text(this.idea.tagName ?? '无标签')
            .fontSize(11)
            .fontWeight(400)
            .fontColor($r('app.color.text_tertiary'))
        }
        .offset({ y: 10 })
        .width('100%')
        .justifyContent(FlexAlign.Start)

        Row() {
          Text(`创建:${TimeRecordUtil.formatRelativeTime(this.idea.createdAt, this.relativeTimeBaseline)}`)
            .fontSize(11)
            .fontWeight(500)
            .fontColor($r('app.color.text_disabled'))

          Button() {
            Row() {
              SymbolGlyph($r('sys.symbol.sun_max'))
                .fontSize(16)
                .fontWeight(700)
                .fontColor([this.isIdeaLit() ? $r('app.color.neutral_100') : $r('app.color.text_tertiary')])
            }
          }
          .visualEffect(buildPointLightEffect({
            preset: 'buttonTouch',
            color: $r('app.color.immersive_glow_warning'),
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
            isActive: this.isMoveButtonPressed,
            isDarkTheme: this.isDarkTheme,
            overrides: {
              height: IdeaCard.BUTTON_TOUCH_LIGHT_HEIGHT
            }
          }))
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.setMoveButtonGlowActive(true);
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.setMoveButtonGlowActive(false);
            }
          })
          .onClick(() => {
            if (this.onMoveToToday) {
              this.onMoveToToday();
            }
          })
          .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.5 })
          .shadow({ color: this.isIdeaLit() ? $r('app.color.warning') : Color.Transparent, radius: this.isIdeaLit() ? 15 : 0 })
          .padding(5)
          .backgroundColor(this.isIdeaLit() ? $r('app.color.accent') : $r('app.color.bg_main'))
          .border({
            width: this.isIdeaLit() ? 0 : 1,
            color: this.isIdeaLit() ? Color.Transparent : $r('app.color.neutral_300')
          })
        }
        .alignItems(VerticalAlign.Bottom)
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .borderRadius(15)
    .padding({ left: 15, right: 15, top: 15, bottom: 15 })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor(this.isIdeaLit() ? $r('app.color.bg_card') : $r('app.color.bg_main'))
    .visualEffect(buildPointLightEffect({
      preset: 'cardTouch',
      color: $r('app.color.immersive_glow_warning'),
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      isActive: this.isCardPressed,
      isDarkTheme: this.isDarkTheme,
      overrides: {
        height: IdeaCard.CARD_TOUCH_LIGHT_HEIGHT
      }
    }))
    .shadow({
      radius: this.isIdeaLit() ? 35 : 20,
      color: this.isIdeaLit()
        ? $r('app.color.ideapool_card_shadow_lit')
        : $r('app.color.ideapool_card_shadow_default'),
      offsetY: 4
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isCardPressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isCardPressed = false;
      }
    })
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.isInteractionEnabled ? HitTestMode.Default : HitTestMode.None)
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((): void => {
          if (this.isInteractionEnabled && this.onLongPress) {
            this.onLongPress();
          }
        })
    )
    .onClick(() => {
      // 点击卡片展开
      if (this.onExpand) {
        this.onExpand();
      }
    })
  }
}
