import { TagModel } from '../model/TagItem';
import { tagService, TagCreateResult, TagMutationResult } from '../Service/TagService';
import { calculateSheetHeight } from '../SheetHeightUtil';
import { MatterItemModel } from '../model/MatterItemModel';
import { VibratorUtil } from '../VibratorUtil';
import { BreakpointConstants } from '../../constants/BreakpointConstants';
import { BreakpointSystem, BreakpointType } from '../../utils/BreakpointSystem';
import {
  curves, LengthMetrics, promptAction
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HSBColorPicker } from '@keke/color-picker';
import { ColorUtil } from '../ColorUtil';
import { tagColorPreferenceService } from '../Service/TagColorPreferenceService';
import {
  DEFAULT_CUSTOMIZE_COLOR,
  resolveSelectedColor,
  resetCustomizeColor,
  showValidationToast,
  validateTagForm
} from '../utils/TagDialogUtils';

const TAG = 'AddNewTagDialog';
const TAG_NAME_MAX_LENGTH: number = 2;

export interface TagDialogDependencies {
  refreshTags?: () => Promise<TagModel[]>;
}

export type TagDialogMode = 'create' | 'edit';

@Component
export struct AddNewTagDialog {
  controller?: CustomDialogController;
  @Link inputActivityName?: string;
  @Link selectedTagIndex: number;
  @Link sheetHeight: number;
  @Link inputTagName: string;
  @Link selectedLabelIndex: number;
  @Link isShow: boolean;
  @Link showFlag: Visibility;
  @Prop mode: TagDialogMode = 'create';
  @Prop editingTag?: TagModel;
  onTagSaved?: (tagId: string, mode: TagDialogMode) => Promise<void> | void;
  dependencies?: TagDialogDependencies;

  // V1/V2混用：使用普通变量传递给V2组件HSBColorPicker，通过onChange回调更新
  // @State用于触发UI刷新，普通变量用于传递给V2组件
  @State customizeColorState: string = DEFAULT_CUSTOMIZE_COLOR;
  @State presetCustomizeColorState: string = DEFAULT_CUSTOMIZE_COLOR;
  @State isEditingTagColors: boolean = false;
  private customizeColor: string = DEFAULT_CUSTOMIZE_COLOR;
  private presetCustomizeColor: string = DEFAULT_CUSTOMIZE_COLOR;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  @StorageLink('tagData') tagData: TagModel[] = [];
  @StorageLink('newTagColor') newTagColor: string[] = [];
  @StorageLink('doneMatterData') doneMatterData: MatterItemModel[] = [];
  @StorageLink('unDoMatterData') unDoMatterData: MatterItemModel[] = [];
  @StorageLink('isCustomDialogShow') isCustomDialogShow: boolean = false;
  private breakPointSystem: BreakpointSystem = new BreakpointSystem();
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  aboutToAppear(): void {
    this.breakPointSystem.register();
    this.initializeDialogState();
  }

  aboutToDisappear(): void {
    this.selectedLabelIndex = -1;
    this.isEditingTagColors = false;
    this.breakPointSystem.unregister();
  }

  private effect: TransitionEffect =
    // 创建默认透明度转场效果,并指定了springMotion(0, 1)曲线
    TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0, 1) })
      // 添加平移转场效果，这里的动画参数使用指定的springMotion()
      .combine(TransitionEffect.translate({ y: 100 }).animation({ curve: curves.springMotion() }));

  private effect_2: TransitionEffect =
    // 创建默认透明度转场效果,并指定了springMotion(0, 1)曲线
    TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0, 1) })
      // 添加平移转场效果，这里的动画参数使用指定的springMotion()
      .combine(TransitionEffect.translate({ y: 250 }).animation({ curve: curves.springMotion() }));

  private computeSheetHeight(tagCount: number): number {
    return calculateSheetHeight(tagCount, this.currentBreakpoint);
  }

  private updateSheetHeight(tagCount?: number): void {
    const count = tagCount !== undefined ? tagCount : this.tagData.length;
    this.sheetHeight = this.computeSheetHeight(count);
  }

  private resetCustomizeColor(): void {
    const defaultColor = resetCustomizeColor();
    this.customizeColor = defaultColor;
    this.customizeColorState = defaultColor;
  }

  private resetPresetCustomizeColor(): void {
    const defaultColor = resetCustomizeColor();
    this.presetCustomizeColor = defaultColor;
    this.presetCustomizeColorState = defaultColor;
  }

  private isEditMode(): boolean {
    return this.mode === 'edit';
  }

  private initializeDialogState(): void {
    this.newTagColor = tagColorPreferenceService.getColors();
    this.exitTagColorEditMode();
    this.resetPresetCustomizeColor();

    if (!this.isEditMode()) {
      if (this.selectedLabelIndex === -200) {
        this.selectedLabelIndex = -1;
      }
      return;
    }

    const targetTag = this.editingTag;
    if (!targetTag) {
      hilog.warn(0x0000, TAG, 'Edit mode enabled but editingTag is undefined');
      this.selectedLabelIndex = -1;
      return;
    }

    this.inputTagName = targetTag.name;
    this.applyColorSelection(targetTag.color);
  }

  private applyColorSelection(targetColor: string): void {
    const normalizedColor = ColorUtil.normalizeHexColor(targetColor);
    const presetIndex = this.newTagColor.findIndex((item: string) =>
      ColorUtil.normalizeHexColor(item) === normalizedColor
    );

    if (presetIndex >= 0) {
      this.selectedLabelIndex = presetIndex;
      return;
    }

    this.customizeColor = normalizedColor;
    this.customizeColorState = normalizedColor;
    this.selectedLabelIndex = -100;
  }

  private getRefreshTags(): () => Promise<TagModel[]> {
    if (this.dependencies && this.dependencies.refreshTags) {
      return this.dependencies.refreshTags;
    }
    return () => tagService.getAllTagsForUI();
  }

  private enterTagColorEditMode(): void {
    if (this.isEditMode()) {
      return;
    }
    if (this.isEditingTagColors) {
      return;
    }
    this.isEditingTagColors = true;
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
  }

  private exitTagColorEditMode(): void {
    if (!this.isEditingTagColors) {
      return;
    }
    this.isEditingTagColors = false;
  }

  private showDeleteColorDialog(color: string, index: number): void {
    const uiContext = this.getUIContext();
    if (!uiContext) {
      hilog.warn(0x0000, TAG, 'UI context unavailable when showing delete color dialog');
      return;
    }

    uiContext.showAlertDialog({
      title: '删除预设颜色？',
      message: `删除后将移除颜色 ${color}`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      gridCount: 4,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: '取消',
        action: () => {
          hilog.info(0x0000, TAG, `Cancel delete preset color ${color}`);
        }
      },
      secondaryButton: {
        enabled: true,
        defaultFocus: true,
        style: DialogButtonStyle.HIGHLIGHT,
        value: '确认',
        action: () => {
          hilog.info(0x0000, TAG, `Confirm delete preset color ${color}`);
          void this.handleDeletePresetColor(color, index);
        }
      },
      cancel: () => {
        hilog.info(0x0000, TAG, 'Closed delete preset color dialog');
      },
      onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
        hilog.info(0x0000, TAG, `Delete preset color dialog onWillDismiss reason= ${dismissDialogAction.reason}`);
        if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
          dismissDialogAction.dismiss();
        }
        if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissDialogAction.dismiss();
        }
      }
    });
  }

  private updateSelectedLabelAfterDeletion(removedIndex: number): void {
    if (this.selectedLabelIndex === removedIndex) {
      this.selectedLabelIndex = -1;
      return;
    }

    if (this.selectedLabelIndex > removedIndex) {
      this.selectedLabelIndex = this.selectedLabelIndex - 1;
    }
  }

  private async handleDeletePresetColor(color: string, index: number): Promise<void> {
    try {
      const updatedColors = tagColorPreferenceService.removeColor(color);
      this.newTagColor = updatedColors;
      this.updateSelectedLabelAfterDeletion(index);
      this.exitTagColorEditMode();
      promptAction.openToast({
        message: '已删除预设颜色',
        duration: 800
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to delete preset color ${color}: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '删除颜色失败',
        duration: 1000
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    }
  }

  private async handleCreateNewTag(): Promise<void> {
    const validationMessage = validateTagForm(this.inputTagName, this.selectedLabelIndex);
    if (validationMessage) {
      await showValidationToast(validationMessage, TAG);
      return;
    }

    const selectedColor = resolveSelectedColor(this.selectedLabelIndex, this.customizeColorState, this.newTagColor);

    hilog.info(0x0000, TAG, `Creating new tag: ${this.inputTagName} with color: ${selectedColor}`);

    try {
      const createResult: TagCreateResult = await tagService.createNewTag(this.inputTagName.trim(), selectedColor);

      if (createResult.success && createResult.tagId) {
        const newTagId: string = createResult.tagId;
        hilog.info(0x0000, TAG, `New tag created successfully with ID: ${newTagId}`);

        const refreshTags = this.getRefreshTags();
        this.tagData = await refreshTags();

        const newTagIndex = this.tagData.findIndex(tag => tag.id === newTagId);
        if (newTagIndex >= 0) {
          this.selectedTagIndex = newTagIndex;
        }

        this.inputTagName = '';
        this.selectedLabelIndex = -1;
        this.resetCustomizeColor();
        // 使用统一的高度计算逻辑，防止底部内容被裁剪（结合断点自适应行列数）
        this.updateSheetHeight();
        await this.onTagSaved?.(newTagId, this.mode);

        if (this.controller) {
          this.controller.close();
        }
        hilog.info(0x0000, TAG, 'Tag creation completed and UI refreshed');
      } else {
        if (createResult.reason === 'DUPLICATE_NAME') {
          await showValidationToast('标签名称已存在', TAG);
        } else if (createResult.reason === 'INVALID_NAME') {
          await showValidationToast('标签名称不能为空', TAG);
        } else if (createResult.reason === 'INVALID_COLOR') {
          await showValidationToast('标签颜色无效', TAG);
        } else {
          hilog.error(0x0000, TAG, 'Failed to create new tag');
          await showValidationToast('创建标签失败，请稍后重试', TAG);
        }
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `handleCreateNewTag failed: ${JSON.stringify(error)}`);
      await showValidationToast('创建标签失败，请稍后重试', TAG);
    }
  }

  private async handleUpdateTag(): Promise<void> {
    const targetTag = this.editingTag;
    if (!targetTag) {
      await showValidationToast('未找到要编辑的标签', TAG);
      return;
    }

    const validationMessage = validateTagForm(this.inputTagName, this.selectedLabelIndex);
    if (validationMessage) {
      await showValidationToast(validationMessage, TAG);
      return;
    }

    const selectedColor = resolveSelectedColor(this.selectedLabelIndex, this.customizeColorState, this.newTagColor);
    const result: TagMutationResult = await tagService.updateTag(targetTag.id, this.inputTagName.trim(), selectedColor);
    if (!result.success) {
      if (result.reason === 'DUPLICATE_NAME') {
        await showValidationToast('标签名称已存在', TAG);
      } else if (result.reason === 'INVALID_NAME') {
        await showValidationToast('标签名称不能为空', TAG);
      } else if (result.reason === 'INVALID_COLOR') {
        await showValidationToast('标签颜色无效', TAG);
      } else if (result.reason === 'NOT_FOUND') {
        await showValidationToast('标签不存在', TAG);
      } else {
        await showValidationToast('保存失败，请稍后重试', TAG);
      }
      return;
    }

    const refreshTags = this.getRefreshTags();
    this.tagData = await refreshTags();
    const updatedTagIndex = this.tagData.findIndex((item: TagModel) => item.id === targetTag.id);
    if (updatedTagIndex >= 0) {
      this.selectedTagIndex = updatedTagIndex;
    }
    await this.onTagSaved?.(targetTag.id, this.mode);

    if (this.controller) {
      this.controller.close();
    }
  }

  private async handleTagSubmit(): Promise<void> {
    if (this.inputTagName.length > TAG_NAME_MAX_LENGTH) {
      await showValidationToast('字数超出限制！(最多2个)', TAG);
      return;
    }
    if (this.isEditMode()) {
      await this.handleUpdateTag();
      return;
    }
    await this.handleCreateNewTag();
  }

  build() {
    Column() {
      Row() {
        Text(this.isEditMode() ? ' 编辑标签名称' : ' 新建标签名称')
          .fontSize(20)
          .fontWeight(700);
        // Text(' (最多3个字)')
        //   .fontSize(14)
        //   .fontColor($r('app.color.accent'))
        //   .fontWeight(700);
      }
        .transition(this.effect)
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Bottom)
        .margin({ bottom: 10, top: 12 });

      Row() {
        TextInput({
          text: $$this.inputTagName,
          placeholder: this.isEditMode() ? '请输入标签名称' : '尽量保证在两个字哦～'
        })
          .caretColor($r('app.color.primary'))
          .width(275)
          .borderRadius(10)
          .width('100%')
          .backgroundColor(Color.Transparent)
          .maxLength(2)
          .border({ width: 2, color: $r('app.color.input_border') });
      }
        .transition(this.effect)
        .width('100%')
        .margin({ bottom: 10 });

      Row() {
        Text('标签颜色')
          .fontSize(15)
          .fontWeight(500);
      }
        .transition(this.effect)
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Bottom)
        .margin({ bottom: 10 });

      Row() {
        Flex({wrap: FlexWrap.Wrap, space: {main: LengthMetrics.vp(5), cross: LengthMetrics.vp(5)} } ) {
          ForEach(
            this.newTagColor,
            (color: string, index: number) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                Stack({ alignContent: Alignment.Center }) {
                  Column()
                    .width(34)
                    .height(34)
                    .borderRadius('50%')
                    .backgroundColor($r('app.color.bg_card'))
                    .border(this.selectedLabelIndex === index
                      ? { width: 2, color: $r('app.color.primary') }
                      : { width: 1, color: $r('app.color.neutral_200') })
                    .scale(this.selectedLabelIndex === index ? { x: 1.08, y: 1.08 } : {})
                    .animation({ curve: curves.springMotion(0.35, 0.6), duration: 80 });

                  Column()
                    .width(this.selectedLabelIndex === index ? 30 : 24)
                    .height(this.selectedLabelIndex === index ? 30 : 24)
                    .backgroundColor(color)
                    .borderRadius('50%')
                    .scale(this.selectedLabelIndex === index ? { x: 1.04, y: 1.04 } : { x: 1, y: 1 })
                    .animation({ curve: curves.springMotion(0.35, 0.6), duration: 80 });

                  if (this.selectedLabelIndex === index && !this.isEditingTagColors) {
                    Button({ type: ButtonType.Circle }) {
                      SymbolGlyph($r('sys.symbol.checkmark'))
                        .fontColor([$r('app.color.neutral_100')])
                        .fontSize(11)
                        .fontWeight(700)
                    }
                    .backgroundColor($r('app.color.primary'))
                    .translate({ x: 8, y: -8 })
                    .width(18)
                    .height(18)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
                    .transition(TransitionEffect.scale({ x : 0, y: 0 })
                      .animation({ curve: curves.springMotion(0.35, 0.7), duration: 60 }));
                  }
                }
                .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
                .gesture(
                  LongPressGesture({ repeat: false })
                    .onAction(() => {
                      if (this.isEditMode()) {
                        return;
                      }
                      this.enterTagColorEditMode();
                    })
                )
                .onClick(() => {
                  if (this.isEditingTagColors) {
                    return;
                  }
                  this.selectedLabelIndex = index;
                  this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                });

                if (this.isEditingTagColors && !this.isEditMode()) {
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontColor([$r('app.color.neutral_100')])
                      .fontSize(10)
                      .fontWeight(700)
                  }
                  .backgroundColor($r('app.color.error'))
                  .translate({ x: 6, y: -6 })
                  .onClick(() => {
                    this.showDeleteColorDialog(color, index);
                  })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
                  .width(18)
                  .height(18)
                  .transition(TransitionEffect.scale({ x : 0, y: 0}).animation({ curve: curves.springMotion(), duration: 50, delay: 10 * index}))
                }
              }
            }
          );

          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(34)
              .height(34)
              .borderRadius('50%')
              .backgroundColor($r('app.color.bg_card'))
              .border(this.selectedLabelIndex === -100
                ? { width: 2, color: $r('app.color.primary') }
                : { width: 1, color: $r('app.color.neutral_200') })
              .scale(this.selectedLabelIndex === -100 ? { x: 1.08, y: 1.08 } : {})
              .animation({ curve: curves.springMotion(0.35, 0.6), duration: 80 });

            Column() {
              Text('调')
                .fontSize(10)
                .fontWeight(700)
                .fontColor($r('app.color.text_secondary'));
            }
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.customizeColorState)
            .width(this.selectedLabelIndex === -100 ? 30 : 24)
            .height(this.selectedLabelIndex === -100 ? 30 : 24)
            .borderRadius('50%')
            .scale(this.selectedLabelIndex === -100 ? { x: 1.04, y: 1.04 } : { x: 1, y: 1 })
            .animation({ curve: curves.springMotion(0.35, 0.6), duration: 80 });

            if (this.selectedLabelIndex === -100) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontColor([$r('app.color.neutral_100')])
                  .fontSize(11)
                  .fontWeight(700);
              }
              .backgroundColor($r('app.color.primary'))
              .translate({ x: 8, y: -8 })
              .width(18)
              .height(18)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
              .transition(TransitionEffect.scale({ x : 0, y: 0 })
                .animation({ curve: curves.springMotion(0.35, 0.7), duration: 60 }));
            }
          }
          .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
          .onClick(() => {
            this.selectedLabelIndex = -100;
            this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
          })
          .width(34)
          .height(34);

          if (!this.isEditMode()) {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(34)
                .height(34)
                .borderRadius('50%')
                .backgroundColor($r('app.color.bg_card'))
                .border(this.selectedLabelIndex === -200
                  ? { width: 2, color: $r('app.color.primary') }
                  : { width: 1, color: $r('app.color.neutral_200') })
                .scale(this.selectedLabelIndex === -200 ? { x: 1.08, y: 1.08 } : {})
                .animation({ curve: curves.springMotion(0.35, 0.6), duration: 80 });

              Column() {
                Text('预')
                  .fontSize(10)
                  .fontWeight(700)
                  .fontColor($r('app.color.text_secondary'));
              }
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.presetCustomizeColorState)
              .width(this.selectedLabelIndex === -200 ? 30 : 24)
              .height(this.selectedLabelIndex === -200 ? 30 : 24)
              .borderRadius('50%')
              .scale(this.selectedLabelIndex === -200 ? { x: 1.04, y: 1.04 } : { x: 1, y: 1 })
              .animation({ curve: curves.springMotion(0.35, 0.6), duration: 80 });

              if (this.selectedLabelIndex === -200) {
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontColor([$r('app.color.neutral_100')])
                    .fontSize(11)
                    .fontWeight(700);
                }
                .backgroundColor($r('app.color.primary'))
                .translate({ x: 8, y: -8 })
                .width(18)
                .height(18)
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
                .transition(TransitionEffect.scale({ x : 0, y: 0 })
                  .animation({ curve: curves.springMotion(0.35, 0.7), duration: 60 }));
              }
            }
            .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
            .onClick(() => {
              this.selectedLabelIndex = -200;
              this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            })
            .width(34)
            .height(34);
          }
        }
      }
        .transition(this.effect)
        .margin({ bottom: 15 });


      // V1/V2混用：传递普通变量给V2的HSBColorPicker组件
      // 通过onChange回调同时更新普通变量和@State变量以触发UI刷新
      HSBColorPicker({
        color: this.customizeColor, // 传递普通变量给V2组件
        radius: 8,
        onChange: (color: string) => {
          this.customizeColor = color; // 更新普通变量（供下次传递）
          this.customizeColorState = color; // 更新@State变量触发UI刷新
        }
      })
        .transition(
          TransitionEffect.asymmetric(TransitionEffect.translate({ y: 50 }).animation({ curve: curves.springMotion(), duration: 50 }),
            undefined
          ))
        .height(170)
        .margin({ bottom: 15 })
        .visibility(this.selectedLabelIndex == -100 ? Visibility.Visible : Visibility.None)

      if (!this.isEditMode()) {
        Column() {
          HSBColorPicker({
            color: this.presetCustomizeColor, // 传递普通变量给V2组件
            radius: 8,
            onChange: (color: string) => {
              this.presetCustomizeColor = color; // 更新普通变量（供下次传递）
              this.presetCustomizeColorState = color; // 更新@State变量触发UI刷新
            }
          })
            .visibility(this.selectedLabelIndex == -200 ? Visibility.Visible : Visibility.None)
            .height(170)
            .margin({ bottom: 15 })
            .transition(
              TransitionEffect.asymmetric(TransitionEffect.translate({ y: 50 }).animation({ curve: curves.springMotion(), duration: 50 }),
                undefined
              ))

          Button({ type: ButtonType.Capsule }) {
            Text('新增预设')
              .fontColor($r('app.color.primary_dark'))
              .fontWeight(700);
          }
          .visibility(this.selectedLabelIndex == -200 ? Visibility.Visible : Visibility.None)
          .onClick(() => {
            this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            const updatedColors = tagColorPreferenceService.addColor(this.presetCustomizeColorState);
            this.newTagColor = updatedColors;
            const normalizedColor = ColorUtil.normalizeHexColor(this.presetCustomizeColorState);
            this.resetPresetCustomizeColor();
            const selectedIndex = updatedColors.findIndex(item => item === normalizedColor);
            if (selectedIndex >= 0) {
              this.selectedLabelIndex = selectedIndex;
            }
          })
          .backgroundColor($r('app.color.primary_lighter'))
          .border({ width: 2, color: $r('app.color.primary_light') })
          .width('100%')
          .height(40)
          .borderRadius(10)
          .transition(
            TransitionEffect.asymmetric(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(), duration: 50 }),
              undefined
            ))
        }
      }


      Row() {
        Button({ type: ButtonType.Capsule }) {
          Text(this.isEditMode() ? '保存修改' : '确认新建')
            .fontColor($r('app.color.accent_dark'))
            .fontWeight(700);
        }
          .onClick(async () => {
            this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            await this.handleTagSubmit();
          })
          .backgroundColor($r('app.color.accent_lighter'))
          .border({ width: 2, color: $r('app.color.accent_light') })
          .width(275)
          .height(40)
          .borderRadius(10)
          .width('100%');
      }
        .width('100%')
        .margin({ bottom: 10 })
      .visibility(this.isEditMode() || this.selectedLabelIndex !== -200 ? Visibility.Visible : Visibility.None)
    }
      .backgroundColor($r('app.color.bg_card'))
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, bottom: 10, top: 10 })
      .width(new BreakpointType<string>({ sm: '90%', md: '60%', lg: '40%' }).getValue(this.currentBreakpoint))
      .borderRadius(20)
      .transition(this.effect_2)
      .visibility(this.showFlag)
      .onClick(() => {
        if (!this.isEditMode()) {
          this.exitTagColorEditMode();
        }
      });
  }
}
