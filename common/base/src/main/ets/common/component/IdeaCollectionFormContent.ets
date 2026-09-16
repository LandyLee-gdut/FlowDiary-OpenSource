import { TagModel } from '../model/TagItem';
import { EmojiItem } from '../EmojiUtil';
import { AppShadows } from '../../constants/Shadow';
import { VibratorUtil } from '../VibratorUtil';
import { curves } from '@kit.ArkUI';

@Component
export struct IdeaCollectionFormContent {
  @Link name: string;
  @Link summaryText: string;
  @Link selectedTagIndex: number;
  @Link selectedEmojiChar: string;
  @Prop tagData: TagModel[] = [];
  @Prop emojis: EmojiItem[] = [];
  @Prop isDarkTheme: boolean = false;

  @Prop headerLabel: ResourceStr = '';
  @Prop namePlaceholder: ResourceStr = '';
  @Prop descLabel: ResourceStr = '';
  @Prop descPlaceholder: ResourceStr = '';
  @Prop tagLabel: ResourceStr = '';
  @Prop emojiLabel: ResourceStr = '';
  @Prop defaultEmoji: ResourceStr = '';
  @Prop enableTagSelectionScale: boolean = true;
  @Prop confirmText: ResourceStr = $r('app.string.common_confirm');
  @Prop confirmDisabled: boolean = false;
  @Prop confirmDisabledText: ResourceStr = '';
  onClose?: () => void;
  onConfirm?: () => void | Promise<void>;

  @State isDescriptionFocused: boolean = false;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        this.DecorationGlowLayer();
        Column() {
          Scroll() {
            Column() {
              this.HeaderLabelSection();
              this.PreviewSection();
              this.NameSection();
              this.DescriptionSection();
              this.TagSelectorSection();
              this.EmojiSelectorSection();
              this.ConfirmButtonSection();
            }
            .padding({
              left: $r('app.float.ideapool_collection_upsert_card_padding_horizontal'),
              right: $r('app.float.ideapool_collection_upsert_card_padding_horizontal'),
              top: $r('app.float.ideapool_collection_upsert_card_padding_top'),
              bottom: $r('app.float.ideapool_collection_upsert_card_padding_bottom')
            })
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .layoutWeight(1)
          .height('100%')
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Off)
          .nestedScroll({
            scrollForward: NestedScrollMode.PARENT_FIRST,
            scrollBackward: NestedScrollMode.SELF_FIRST
          })
        }
        .width('100%')
        .height('100%')
        this.CloseButtonSection();
      }
      // .clip(true)
      .backgroundColor($r('app.color.bg_card'))
      // .borderRadius($r('app.float.ideapool_collection_upsert_card_radius'))
      // .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)
      // .constraintSize({ maxWidth: $r('app.float.ideapool_collection_upsert_card_max_width') })
      .width('100%')
      .height('100%')
    }
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [
        [$r('app.color.bg_card'), 0],
        [$r('app.color.bg_card'), 0.5],
        [$r('app.color.accent_lighter'), 1],
      ]
    })
    // .padding({
    //   left: $r('app.float.ideapool_collection_upsert_sheet_padding_horizontal'),
    //   right: $r('app.float.ideapool_collection_upsert_sheet_padding_horizontal'),
    //   bottom: $r('app.float.ideapool_collection_upsert_sheet_padding_bottom')
    // })
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.KEYBOARD, SafeAreaType.SYSTEM])
  }

  @Builder
  private DecorationGlowLayer(): void {
    Column() {
    }
    .width('100%')
    .height('100%')

    Column() {
    }
    .width($r('app.float.ideapool_collection_upsert_glow_size'))
    .height($r('app.float.ideapool_collection_upsert_glow_size'))
    .borderRadius($r('app.float.ideapool_collection_upsert_glow_radius'))
    .backgroundColor($r('app.color.primary_light'))
    .opacity($r('app.float.ideapool_collection_upsert_glow_opacity'))
    .shadow({
      radius: $r('app.float.ideapool_collection_upsert_glow_shadow_radius'),
      color: $r('app.color.primary_light'),
      offsetY: 0
    })
    .position({
      x: $r('app.float.ideapool_collection_upsert_glow_left_x'),
      y: $r('app.float.ideapool_collection_upsert_glow_y')
    })

    Column() {
    }
    .width($r('app.float.ideapool_collection_upsert_glow_size'))
    .height($r('app.float.ideapool_collection_upsert_glow_size'))
    .borderRadius($r('app.float.ideapool_collection_upsert_glow_radius'))
    .backgroundColor($r('app.color.accent_light'))
    .opacity($r('app.float.ideapool_collection_upsert_glow_opacity'))
    .shadow({
      radius: $r('app.float.ideapool_collection_upsert_glow_shadow_radius'),
      color: $r('app.color.accent_light'),
      offsetY: 0
    })
    .position({
      x: $r('app.float.ideapool_collection_upsert_glow_right_x'),
      y: $r('app.float.ideapool_collection_upsert_glow_y')
    })
  }

  private resolvePreviewColor(): ResourceColor {
    if (this.selectedTagIndex >= 0 && this.selectedTagIndex < this.tagData.length) {
      return this.tagData[this.selectedTagIndex].lightColor;
    }
    return $r('app.color.neutral_100');
  }

  private resolvePreviewEmoji(): ResourceStr {
    if (this.selectedEmojiChar && this.selectedEmojiChar.length > 0) {
      return this.selectedEmojiChar;
    }
    return this.defaultEmoji;
  }

  private resolveDescriptionBackground(): ResourceColor {
    // if (this.isDescriptionFocused) {
    //   return $r('app.color.bg_card');
    // }
    return $r('app.color.bg_main');
  }

  private resolveDescriptionBorder(): ResourceColor {
    // if (this.isDescriptionFocused) {
    //   return $r('app.color.primary');
    // }
    return $r('app.color.neutral_200');
  }

  private resolveEmojiBorder(emojiChar: string): ResourceColor {
    if (this.selectedEmojiChar === emojiChar) {
      return $r('app.color.primary');
    }
    return $r('app.color.neutral_200');
  }

  private resolveEmojiBackground(emojiChar: string): ResourceColor {
    if (this.selectedEmojiChar === emojiChar) {
      return $r('app.color.bg_card');
    }
    return $r('app.color.neutral_100');
  }

  private resolveEmojiShadow(emojiChar: string): ShadowOptions {
    if (this.selectedEmojiChar === emojiChar) {
      return {
        color: $r('app.color.primary_light'),
        radius: $r('app.float.ideapool_collection_upsert_emoji_selected_shadow_radius'),
        offsetX: 0,
        offsetY: 0
      };
    }
    return AppShadows.NONE;
  }

  private resolveConfirmText(): ResourceStr {
    if (this.confirmDisabled && this.confirmDisabledText) {
      return this.confirmDisabledText;
    }
    return this.confirmText;
  }

  @Builder
  private CloseButtonSection(): void {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontColor([$r('app.color.text_primary')])
          .fontSize($r('app.float.form_sheet_close_icon_size'))
          .fontWeight(700)
      }
      .width($r('app.float.form_sheet_close_button_size'))
      .height($r('app.float.form_sheet_close_button_size'))
      .backgroundColor($r('app.color.neutral_100'))
      .onClick(() => {
        this.onClose?.();
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .padding({
      left: $r('app.float.form_sheet_close_button_margin_start'),
      top: $r('app.float.form_sheet_close_button_margin_top')
    })
  }

  @Builder
  private HeaderLabelSection(): void {
    Row() {
      Text(this.headerLabel)
        .fontSize($r('app.float.ideapool_collection_upsert_header_text_size'))
        .fontWeight(700)
        .fontColor($r('app.color.text_secondary'))
        .letterSpacing($r('app.float.ideapool_collection_upsert_header_letter_spacing'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({
      top: $r('app.float.ideapool_collection_upsert_header_margin_top'),
      bottom: $r('app.float.ideapool_collection_upsert_header_margin_bottom')
    })
  }

  @Builder
  private PreviewSection(): void {
    Column() {
      Column() {
        Text(this.resolvePreviewEmoji())
          .fontSize($r('app.float.ideapool_collection_upsert_preview_emoji_size'))
      }
      .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)
      .width($r('app.float.ideapool_collection_upsert_preview_size'))
      .height($r('app.float.ideapool_collection_upsert_preview_size'))
      .borderRadius($r('app.float.ideapool_collection_upsert_preview_radius'))
      .backgroundColor(this.resolvePreviewColor())
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: $r('app.float.ideapool_collection_upsert_preview_margin_top') })
  }

  @Builder
  private NameSection(): void {
    Column() {
      TextInput({
        text: this.name,
        placeholder: this.namePlaceholder
      })
        .fontSize($r('app.float.ideapool_collection_upsert_name_font_size'))
        .fontWeight(600)
        .textAlign(TextAlign.Center)
        .placeholderFont({
          size: 22,
          weight: 600
        })
        .caretColor($r('app.color.primary'))
        .backgroundColor($r('app.color.transparent'))
        .placeholderColor($r('app.color.text_disabled'))
        .borderRadius($r('app.float.ideapool_collection_upsert_name_input_radius'))
        .height($r('app.float.ideapool_collection_upsert_name_input_height'))
        .width('100%')
        .onChange((value: string) => {
          this.name = value;
        })

      Divider()
        .strokeWidth(2)
        .width($r('app.float.ideapool_collection_upsert_name_underline_width'))
        .borderRadius($r('app.float.ideapool_collection_upsert_name_underline_radius'))
        .backgroundColor($r('app.color.neutral_100'))
    }
    .alignItems(HorizontalAlign.Center)
    .margin({
      top: $r('app.float.ideapool_collection_upsert_name_section_margin_top'),
      bottom: $r('app.float.ideapool_collection_upsert_name_section_margin_bottom')
    })
    .width('100%')
  }

  @Builder
  private DescriptionSection(): void {
    Column() {
      Row() {
        Text(this.descLabel)
          .fontSize($r('app.float.ideapool_collection_upsert_label_text_size'))
          .fontWeight(500)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: $r('app.float.ideapool_collection_upsert_label_margin_bottom') })

      TextArea({
        text: this.summaryText,
        placeholder: this.descPlaceholder
      })
        .padding({top: 12, bottom:12, left: 15, right: 15})
        .caretColor($r('app.color.primary'))
        .backgroundColor(this.resolveDescriptionBackground())
        .placeholderColor($r('app.color.text_disabled'))
        .border({ width: $r('app.float.ideapool_collection_upsert_input_border_width'), color: this.resolveDescriptionBorder() })
        .borderRadius($r('app.float.ideapool_collection_upsert_textarea_radius'))
        .height($r('app.float.ideapool_collection_upsert_textarea_height'))
        .width('100%')
        .onFocus(() => {
          this.isDescriptionFocused = true;
        })
        .onBlur(() => {
          this.isDescriptionFocused = false;
        })
        .onChange((value: string) => {
          this.summaryText = value;
        })
    }
    .margin({ top: $r('app.float.ideapool_collection_upsert_section_gap') })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private TagSelectorSection(): void {
    Column() {
      Row() {
        Text(this.tagLabel)
          .fontSize($r('app.float.ideapool_collection_upsert_label_text_size'))
          .fontWeight(500)
      }
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: $r('app.float.ideapool_collection_upsert_label_margin_bottom') })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach(this.tagData, (tag: TagModel, index: number) => {
          Stack({ alignContent: Alignment.TopEnd }) {
            Row() {
              Text(tag.name)
                .fontColor(tag.color)
                .fontWeight(FontWeight.Medium)
                .fontSize($r('app.float.ideapool_collection_upsert_tag_text_size'))
            }
            .height($r('app.float.ideapool_collection_upsert_tag_height'))
            .alignItems(VerticalAlign.Center)
            .padding({
              left: $r('app.float.ideapool_collection_upsert_tag_padding_horizontal'),
              right: $r('app.float.ideapool_collection_upsert_tag_padding_horizontal'),
              top: $r('app.float.ideapool_collection_upsert_tag_padding_vertical'),
              bottom: $r('app.float.ideapool_collection_upsert_tag_padding_vertical')
            })
            .margin({
              right: $r('app.float.ideapool_collection_upsert_tag_margin_right'),
              bottom: $r('app.float.ideapool_collection_upsert_tag_margin_bottom')
            })
            .backgroundColor(tag.lightColor)
            .opacity(this.isDarkTheme ? $r('app.float.ideapool_collection_upsert_tag_dark_opacity') : 1)
            .translate({ z: this.selectedTagIndex === index ? -30 : 0 })
            .scale(this.selectedTagIndex === index && this.enableTagSelectionScale ? { x: 1.1, y: 1.1 } : {})
            .animation({ curve: curves.springMotion(0.35, 0.6), duration: 50 })
            .shadow(this.selectedTagIndex === index
              ? AppShadows.getTagPillShadow(tag.color, this.isDarkTheme)
              : AppShadows.NONE)
            .justifyContent(FlexAlign.Center)
            .borderRadius($r('app.float.ideapool_collection_upsert_tag_radius'))
            .onClick(() => {
              if (this.selectedTagIndex !== index) {
                this.selectedTagIndex = index;
                void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
              }
            })

            if (this.selectedTagIndex === index) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontColor([$r('app.color.neutral_100')])
                  .fontSize($r('app.float.ideapool_collection_upsert_tag_check_icon_size'))
                  .fontWeight(700)
              }
              .backgroundColor($r('app.color.primary'))
              .translate({ x: -3, y: -5 })
              .transition(TransitionEffect.scale({ x: 0, y: 0 })
                .animation({ curve: curves.springMotion(0.35, 0.7), duration: 10 }))
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
              .width($r('app.float.ideapool_collection_upsert_tag_check_size'))
              .height($r('app.float.ideapool_collection_upsert_tag_check_size'))
            }
          }
        }, (tag: TagModel) => tag.id)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .margin({ top: $r('app.float.ideapool_collection_upsert_section_gap') })
    .width('100%')
  }

  @Builder
  private EmojiSelectorSection(): void {
    Column() {
      Row() {
        Text(this.emojiLabel)
          .fontSize($r('app.float.ideapool_collection_upsert_label_text_size'))
          .fontWeight(500)
      }
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: $r('app.float.ideapool_collection_upsert_emoji_label_margin_bottom') })

      Grid() {
        ForEach(this.emojis, (emoji: EmojiItem) => {
          GridItem() {
            Column() {
              Text(emoji.char)
                .fontSize($r('app.float.ideapool_collection_upsert_emoji_text_size'))
            }
            .width($r('app.float.ideapool_collection_upsert_emoji_cell_size'))
            .height($r('app.float.ideapool_collection_upsert_emoji_cell_size'))
            .borderRadius('50%')
            .backgroundColor(this.resolveEmojiBackground(emoji.char))
            .border({
              width: $r('app.float.ideapool_collection_upsert_emoji_cell_border_width'),
              color: this.resolveEmojiBorder(emoji.char)
            })
            // .shadow(this.resolveEmojiShadow(emoji.char))
            .scale(this.selectedEmojiChar === emoji.char ? { x: 1.08, y: 1.08 } : {})
            .animation({ curve: curves.springMotion(0.35, 0.6), duration: 60 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .onClick(() => {
            if (this.selectedEmojiChar !== emoji.char) {
              this.selectedEmojiChar = emoji.char;
              void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            }
          })
        }, (emoji: EmojiItem) => emoji.char)
      }
      .scrollBar(BarState.Off)
      .columnsGap($r('app.float.ideapool_collection_upsert_emoji_grid_gap'))
      .rowsGap($r('app.float.ideapool_collection_upsert_emoji_grid_gap'))
      .rowsTemplate('1fr 1fr')
      .height($r('app.float.ideapool_collection_upsert_emoji_grid_height'))
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .margin({ top: $r('app.float.ideapool_collection_upsert_section_gap'), bottom: $r('app.float.ideapool_collection_upsert_emoji_section_margin_bottom') })
    .width('100%')
  }

  @Builder
  private ConfirmButtonSection(): void {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Text(this.resolveConfirmText())
        .fontWeight(700)
        .fontSize($r('app.float.form_sheet_confirm_button_font_size'))
        .fontColor(this.confirmDisabled ? $r('app.color.text_disabled') : $r('app.color.primary'))
    }
    .enabled(!this.confirmDisabled)
    .height($r('app.float.form_sheet_confirm_button_height'))
    .width('100%')
    .border({ width: $r('app.float.form_sheet_confirm_button_border_width'), color: $r('app.color.primary_light') })
    .backgroundColor($r('app.color.primary_lighter'))
    .borderRadius($r('app.float.form_sheet_confirm_button_radius'))
    .margin({
      top: $r('app.float.form_sheet_confirm_button_margin_top'),
      bottom: $r('app.float.form_sheet_confirm_button_margin_bottom')
    })
    .onClick(() => {
      this.onConfirm?.();
    })
  }
}
