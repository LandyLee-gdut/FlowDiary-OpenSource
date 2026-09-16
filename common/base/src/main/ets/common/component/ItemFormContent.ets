/**
 * 通用表单内容组件
 * 用于添加/编辑灵感、事项、快捷项等场景的统一表单布局
 */
import { curves } from '@kit.ArkUI';
import { TagModel } from '../model/TagItem';
import { EmojiItem, EmojiUtil } from '../EmojiUtil';
import { VibratorUtil } from '../VibratorUtil';
import { AppShadows } from '../../constants/Shadow';
import { IdeaCollection } from '../model/IdeaPoolModels';
import { IdeaCollectionPicker } from './IdeaCollectionPicker';
import {
  ItemFormSheetConfig,
  NameInputConfig,
  TagSelectorConfig,
  EmojiSelectorConfig
} from './ItemFormSheetTypes';

@Component
export struct ItemFormContent {
  /** 表单配置 */
  @Require @Prop config: ItemFormSheetConfig;
  /** 标签数据 */
  @Link tagData: TagModel[];
  /** 名称输入值 */
  @Link inputName: string;
  /** 选中的标签索引 */
  @Link selectedTagIndex: number;
  /** 直接开始toggle状态 */
  @Link directStartEnabled: boolean;
  /** 是否处于标签编辑模式 */
  @Link isEditingTag: boolean;
  /** 标签抖动角度 */
  @Link tagShakeAngle: number;
  /** 选中的emoji（用于编辑模式高亮） */
  @Link selectedEmoji: string;
  /** 是否深色主题 */
  @Prop isDarkTheme: boolean = false;
  /** 是否显示集合选择区（灵感池专用） */
  @Prop showCollectionPicker: boolean = false;
  /** 集合选择区标题 */
  @Prop collectionPickerLabel: ResourceStr = '';
  /** 集合数据 */
  @Prop collections: IdeaCollection[] = [];
  /** 当前选中的集合ID */
  @Prop selectedCollectionId: string | null = null;
  /** 是否显示“散落灵感”选项 */
  @Prop showCollectionLooseOption: boolean = true;
  /** 是否展示关闭/确认按钮 */
  @Prop showActionButtons: boolean = false;
  /** 确认按钮文字 */
  @Prop confirmButtonText: ResourceStr = '';
  /** 确认按钮是否禁用 */
  @Prop confirmButtonDisabled: boolean = false;
  /** 确认按钮禁用时文字 */
  @Prop confirmButtonDisabledText: ResourceStr = '';
  /** 表情列表 */
  @State private emojis: EmojiItem[] = EmojiUtil.getAll();
  /** 新建标签回调 */
  onCreateTag?: () => void;
  /** 删除标签回调 */
  onDeleteTag?: (tag: TagModel, index: number) => void;
  /** 切换标签编辑模式回调 */
  onToggleTagEditing?: (isEditing: boolean) => void;
  /** 集合选择变化回调 */
  onCollectionSelectionChange?: (collectionId: string | null) => void;
  /** 关闭回调 */
  onClose?: () => void;
  /** 确认回调 */
  onConfirm?: () => void | Promise<void>;
  /** 触觉反馈工具 */
  private vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Scroll() {
          Column() {
            // 名称输入区
            if (this.config.nameInput) {
              this.NameInputSection(this.config.nameInput)
            }

            // 标签选择区
            if (this.config.tagSelector) {
              this.TagSelectorSection(this.config.tagSelector)
            }

            if (this.showCollectionPicker) {
              IdeaCollectionPicker({
                label: this.collectionPickerLabel,
                collections: this.collections,
                selectedCollectionId: this.selectedCollectionId,
                showLooseOption: this.showCollectionLooseOption,
                isDarkTheme: this.isDarkTheme,
                onSelectionChange: (collectionId: string | null) => {
                  this.onCollectionSelectionChange?.(collectionId);
                }
              })
            }

            // 表情选择区
            if (this.config.emojiSelector?.show !== false) {
              this.EmojiSelectorSection(this.config.emojiSelector)
            }
          }
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: 100 }))
            .animation({ curve: curves.springMotion(), duration: 50 }))
          .padding({
            left: $r('app.float.form_sheet_content_padding_horizontal'),
            right: $r('app.float.form_sheet_content_padding_horizontal'),
            bottom: $r('app.float.form_sheet_content_padding_bottom')
          })
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .onClick(() => {
            if (this.isEditingTag) {
              this.onToggleTagEditing?.(false);
            }
          })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)

        if (this.showActionButtons) {
          this.ConfirmButtonSection();
        }
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.KEYBOARD, SafeAreaType.SYSTEM])

      if (this.showActionButtons) {
        this.CloseButtonSection();
      }
    }
    .width('100%')
    .height('100%')
  }

  private resolveConfirmButtonText(): ResourceStr {
    if (this.confirmButtonDisabled && this.confirmButtonDisabledText) {
      return this.confirmButtonDisabledText;
    }
    if (this.confirmButtonText) {
      return this.confirmButtonText;
    }
    return this.config.titleBar.actionButtonText;
  }

  @Builder
  private CloseButtonSection(): void {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontColor([$r('app.color.text_primary')])
          .fontSize($r('app.float.form_sheet_close_icon_size'))
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
  private ConfirmButtonSection(): void {
    Row() {
      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Text(this.resolveConfirmButtonText())
          .fontWeight(700)
          .fontSize($r('app.float.form_sheet_confirm_button_font_size'))
          .fontColor(this.confirmButtonDisabled ? $r('app.color.text_disabled') : $r('app.color.primary'))
      }
      .enabled(!this.confirmButtonDisabled)
      .height($r('app.float.form_sheet_confirm_button_height'))
      .width('100%')
      .border({ width: $r('app.float.form_sheet_confirm_button_border_width'), color: $r('app.color.primary_light') })
      .backgroundColor($r('app.color.primary_lighter'))
      .borderRadius($r('app.float.form_sheet_confirm_button_radius'))
      .onClick(() => {
        this.onConfirm?.();
      })
    }
    .width('100%')
    .padding({
      left: $r('app.float.form_sheet_content_padding_horizontal'),
      right: $r('app.float.form_sheet_content_padding_horizontal'),
      top: $r('app.float.form_sheet_confirm_button_margin_top'),
      bottom: $r('app.float.form_sheet_confirm_button_margin_bottom')
    })
  }

  /**
   * 名称输入区
   */
  @Builder
  NameInputSection(inputConfig: NameInputConfig) {
    Row() {
      Text(inputConfig.label)
        .fontSize(15)
        .fontWeight(500)

      if (inputConfig.showDirectStartToggle) {
        Row() {
          Text(inputConfig.directStartLabel ?? $r('app.string.start_directly'))
            .fontSize(12)
            .fontWeight(700)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.End)
            .margin({ right: 3 })

          Toggle({ type: ToggleType.Switch, isOn: this.directStartEnabled })
            .selectedColor($r('app.color.primary'))
            .onChange((isOn: boolean) => {
              this.directStartEnabled = isOn;
            })
        }
      }
    }
    .justifyContent(inputConfig.showDirectStartToggle ? FlexAlign.SpaceBetween : FlexAlign.Start)
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: inputConfig.showDirectStartToggle ? 5 : 10, top: 12 })

    Row() {
      TextInput({ text: $$this.inputName, placeholder: inputConfig.placeholder as string })
        .caretColor($r('app.color.primary'))
        .backgroundColor(Color.Transparent)
        .border({ width: 2, color: $r('app.color.neutral_200') })
        .borderRadius(10)
        .width('100%')
    }
    .width('100%')
    .margin({ bottom: 10 })
  }

  /**
   * 标签选择区
   */
  @Builder
  TagSelectorSection(tagConfig: TagSelectorConfig) {
    Column() {
      Row() {
        if (tagConfig.label) {
          Text(tagConfig.label)
            .fontSize(15)
            .fontWeight(500)
            .margin({ right: 3 })
        }

        if (tagConfig.showEditHint && tagConfig.editHintText) {
          Text(tagConfig.editHintText)
            .fontSize(12)
            .fontColor($r('app.color.warning'))
            .fontWeight(700)
        }
      }
      .alignItems(VerticalAlign.Bottom)
      .margin({ bottom: 10 })

      if (tagConfig.enableLongPressEdit) {
        // 带长按编辑手势的标签区域
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.TagList(tagConfig)
        }
        .gesture(
          LongPressGesture({ repeat: true })
            .onAction(() => {
              if (!this.isEditingTag) {
                this.selectedTagIndex = -1;
              }
              this.onToggleTagEditing?.(!this.isEditingTag);
              void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            })
        )
        .width('100%')
      } else {
        // 无长按编辑手势的标签区域
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.TagList(tagConfig)
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  /**
   * 标签列表内容（抽取为独立Builder以复用）
   */
  @Builder
  TagList(tagConfig: TagSelectorConfig) {
    ForEach(
          this.tagData,
          (tag: TagModel, index: number) => {
            Stack({ alignContent: Alignment.TopEnd }) {
              Row() {
                Text(tag.name)
                  .fontColor(tag.color)
                  .fontWeight(FontWeight.Medium)
                  .fontSize(16)
              }
              .height(30)
              .alignItems(VerticalAlign.Center)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 10 })
              .backgroundColor(tag.lightColor)
              .opacity((this.isDarkTheme ? 0.95 : 1))
              .translate({ z: this.selectedTagIndex === index && !(this.isEditingTag && tagConfig.enableLongPressEdit) ? -30 : 0 })
              .scale(this.selectedTagIndex === index && !(this.isEditingTag && tagConfig.enableLongPressEdit) ? { x: 1.1 , y: 1.1 } : {})
              .animation({ curve: curves.springMotion(0.35, 0.6), duration: 50 })
              .shadow(this.selectedTagIndex === index && !(this.isEditingTag && tagConfig.enableLongPressEdit)
                ? AppShadows.getTagPillShadow(tag.color, this.isDarkTheme)
                : AppShadows.NONE)
              .justifyContent(FlexAlign.Center)
              .borderRadius(20)
              .onClick(() => {
                if (this.isEditingTag && tagConfig.enableLongPressEdit) {
                  return;
                }
                if (this.selectedTagIndex !== index) {
                  this.selectedTagIndex = index;
                  void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                }
              })
              .rotate({
                x: 0,
                y: 0,
                z: 1,
                angle: this.isEditingTag ? this.tagShakeAngle * this.getTagShakePhase(index) : 0,
                centerX: '50%',
                centerY: '50%'
              })
              .translate({ x: this.isEditingTag ? 1.5 * this.getTagShakePhase(index) : 0 })

              // 编辑模式下的删除按钮
              if (this.isEditingTag && tagConfig.enableLongPressEdit) {
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.xmark'))
                    .fontColor([$r('app.color.neutral_100')])
                    .fontSize(10)
                    .fontWeight(700)
                }
                .backgroundColor($r('app.color.error'))
                .translate({ x: -3, y: -5 })
                .shadow(this.getDestructiveActionShadow())
                .onClick(() => {
                  this.onDeleteTag?.(tag, index);
                })
                .transition(TransitionEffect.scale({ x: 0, y: 0 })
                  .animation({ curve: curves.springMotion(0.6, 0.5), duration: 10, delay: index * 10 }))
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
                .width(15)
                .height(15)
              }

              if (this.selectedTagIndex == index && !(this.isEditingTag && tagConfig.enableLongPressEdit)) {
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontColor([$r('app.color.neutral_100')])
                    .fontSize(10)
                    .fontWeight(700)
                }
                .backgroundColor($r('app.color.primary'))
                .translate({ x: -3, y: -5 })
                // .shadow(this.getDestructiveActionShadow())
                .transition(TransitionEffect.scale({ x: 0, y: 0 })
                  .animation({ curve: curves.springMotion(0.35, 0.7), duration: 10}))
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
                .width(15)
                .height(15)
              }
            }
          },
          (tag: TagModel) => tag.id
        )

        // 新建标签按钮
        if (tagConfig.showCreateButton) {
          Button() {
            Text('新建')
              .fontColor($r('app.color.neutral_500'))
              .fontWeight(FontWeight.Medium)
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .border({ width: 2, style: BorderStyle.Dashed, color: $r('app.color.neutral_300') })
          .backgroundColor($r('app.color.neutral_100'))
          .borderRadius(20)
          .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
          .margin({ bottom: 10 })
          .onClick(() => {
            this.onCreateTag?.();
            void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
          })
        }

        // 无标签提示
        if (this.tagData.length === 0 && !tagConfig.showCreateButton) {
          Row() {
            Text('暂无标签，请先创建')
              .fontColor($r('app.color.text_disabled'))
              .fontSize(14)
          }
          .height(30)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.neutral_100'))
          .borderRadius(20)
        }
  }

  /**
   * 表情/图标选择区
   */
  @Builder
  EmojiSelectorSection(emojiConfig?: EmojiSelectorConfig) {
    Column() {
      Row() {
        if (emojiConfig?.label) {
          Text(emojiConfig.label)
            .fontSize(15)
            .fontWeight(500)
            .margin({ right: 3 })
        }

        if (emojiConfig?.hint) {
          Text(emojiConfig.hint)
            .fontSize(12)
            .fontColor($r('app.color.primary'))
            .fontWeight(700)
        }
      }
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 5 })

      Grid() {
        ForEach(
          this.emojis,
          (emoji: EmojiItem) => {
            GridItem() {
              Text(emoji.char)
                .fontSize(16)
                .padding(8)
                .borderRadius('50%')
                .backgroundColor($r('app.color.bg_main'))
                .shadow(this.selectedEmoji === emoji.char && !(emojiConfig?.appendToInput ?? true)
                  ? { color: $r('app.color.primary'), radius: 12 }
                  : { radius: 0 })
            }
            .onClick(() => {
              if (emojiConfig?.appendToInput ?? true) {
                // 追加模式：将emoji添加到名称输入框
                this.inputName = `${this.inputName ?? ''}${emoji.char}`;
              } else {
                // 选择模式：设置选中的emoji
                this.selectedEmoji = emoji.char;
              }
              void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            })
          },
          (emoji: EmojiItem) => emoji.char
        )
      }
      .scrollBar(BarState.Off)
      .columnsGap(5)
      .rowsGap(5)
      .rowsTemplate('1fr 1fr')
      .height(90)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 10 })
  }

  /**
   * 获取标签抖动相位
   */
  private getTagShakePhase(index: number): number {
    return index % 2 === 0 ? 1 : -1;
  }

  /**
   * 获取删除操作的阴影样式
   */
  private getDestructiveActionShadow(): ShadowOptions {
    const base = this.isDarkTheme ? AppShadows.SUBTLE_DARK : AppShadows.SUBTLE;
    return {
      radius: base.radius,
      offsetX: base.offsetX,
      offsetY: base.offsetY,
      color: $r('app.color.error')
    };
  }
}
