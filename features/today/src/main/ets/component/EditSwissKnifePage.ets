import { HdsNavDestination, HdsNavDestinationAttribute } from "@hms.hds.hdsBaseComponent";
import {
  DEFAULT_SHEET_HEIGHT,
  calculateSheetHeight,
  BreakpointConstants,
  BreakpointSystem,
  BreakpointType,
  VibratorUtil,
  TagModel,
  ItemFormSheetConfig,
  ItemFormSheetPresets,
  buildSheetTitleBar,
  ItemFormContent
} from 'base';
import { DirectRecordData, FanItem, FanItemVO, toFanItemVOs } from "../model/OverLayModel";
import { hilog } from "@kit.PerformanceAnalysisKit";
import { fanItemService } from "../model/FanItemService";
import { curves, promptAction, window } from "@kit.ArkUI";
import { BusinessError } from "@kit.BasicServicesKit";

const TAG = 'EditSwissKnifePage'

@Component
export struct EditSwissKnifePage {
  onBack?: () => void;
  @StorageLink('fanItems') swissKnifeItems: FanItemVO[] = [];
  @StorageLink('tagData') tagData: TagModel[] = [];
  @StorageLink('isCustomDialogShow') isCustomDialogShow: boolean = false;
  private pageInfos: NavPathStack = new NavPathStack();
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @State isActivitySheetShow: boolean = false;
  @State private activitySheetDetents: [Length | SheetSize, (Length | SheetSize)?, (Length | SheetSize)?] =
    [SheetSize.MEDIUM, SheetSize.LARGE];
  @State activityName: string = '';
  @State selectedTagIndex: number = -1;
  @State sheetHeight: number = DEFAULT_SHEET_HEIGHT;
  @State keyboardHeight: number = 0;
  @State viewportHeight: number = 0;
  @State editingItemId: number | null = null;
  @State editingEmojiChar: string = '';
  // 通用组件所需的状态（本场景不使用，但需要提供）
  @State directStartEnabled: boolean = false;
  @State isEditingTag: boolean = false;
  @State tagShakeAngle: number = 0;
  // Sheet配置
  private sheetConfig: ItemFormSheetConfig = ItemFormSheetPresets.createEditSwissKnifeConfig();
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private breakPointSystem: BreakpointSystem = new BreakpointSystem();

  private handleCloseClick(): void {
    if (this.onBack) {
      this.onBack();
      return;
    }
    this.pageInfos.pop(1);
  }

  async aboutToAppear(): Promise<void> {
    this.breakPointSystem.register();
    this.updateSheetHeight();
    window.getLastWindow(this.getUIContext().getHostContext()).then(currentWindow => {
      const windowRect = currentWindow.getWindowProperties().windowRect;
      this.viewportHeight = this.getUIContext().px2vp(windowRect.height);
      this.updateSheetHeight();

      currentWindow.on('windowSizeChange', (size: window.Size) => {
        this.viewportHeight = this.getUIContext().px2vp(size.height);
        this.updateSheetHeight();
      });
      currentWindow.on('keyboardHeightChange', (data: number) => {
        this.keyboardHeight = this.getUIContext().px2vp(data);
        this.updateActivitySheetDetents();
      });
    }).catch((error: BusinessError) => {
      hilog.warn(0x0000, TAG, `[EditSwissKnifePage] Failed to attach keyboard listener: ${JSON.stringify(error)}`);
    });

    try {
      await this.vibratorUtil.initialize();
    } catch (error) {
      hilog.error(0x0000, TAG, `[EditSwissKnifePage] Failed to initialize haptics: ${JSON.stringify(error)}`);
    }
  }

  aboutToDisappear(): void {
    this.isActivitySheetShow = false;
    this.resetSheetState();
    this.breakPointSystem.unregister();
    void this.vibratorUtil.stopAllHaptics();
  }

  onTagDataChange(): void {
    this.updateSheetHeight();
    if (this.editingItemId !== null) {
      this.selectedTagIndex = this.resolveTagIndex(this.findFanItemById(this.editingItemId)?.directRecordData?.tagId ?? null);
    }
  }

  private updateSheetHeight(): void {
    const tagCount = this.tagData ? this.tagData.length : 0;
    this.sheetHeight = this.computeSheetHeight(tagCount);
  }

  private updateActivitySheetDetents(): void {
    if (this.isActivitySheetShow && this.keyboardHeight > 0) {
      this.activitySheetDetents = [SheetSize.LARGE];
      return;
    }
    this.activitySheetDetents = [SheetSize.MEDIUM, SheetSize.LARGE];
  }

  private computeSheetHeight(tagCount: number): number {
    return calculateSheetHeight(tagCount, this.currentBreakpoint, this.viewportHeight);
  }

  private resolveTagIndex(tagId: string | null): number {
    if (!tagId || !this.tagData || this.tagData.length === 0) {
      return -1;
    }
    return this.tagData.findIndex(tag => tag.id === tagId);
  }

  private findFanItemById(id: number): FanItemVO | undefined {
    return this.swissKnifeItems.find(item => item.id === id);
  }

  private resetSheetState(): void {
    this.activityName = '';
    this.selectedTagIndex = -1;
    this.editingItemId = null;
    this.editingEmojiChar = '';
  }

  private openEditSheetForItem(item: FanItemVO): void {
    this.editingItemId = item.id;
    this.activityName = item.label ?? '';
    this.editingEmojiChar = item.icon ?? '';
    const currentTagId = item.directRecordData?.tagId ?? item.tagMeta?.id ?? null;
    this.selectedTagIndex = this.resolveTagIndex(currentTagId);
    this.updateSheetHeight();
    this.isActivitySheetShow = true;
  }

  private getSelectedTagId(): string | null {
    if (!this.tagData || this.tagData.length === 0) {
      return null;
    }

    if (this.selectedTagIndex < 0 || this.selectedTagIndex >= this.tagData.length) {
      return null;
    }

    return this.tagData[this.selectedTagIndex].id;
  }

  private async persistSwissKnifeItem(): Promise<void> {
    const trimmedName = this.activityName.trim();
    if (trimmedName.length === 0) {
      promptAction.openToast({
        message: '请填写快捷事项名称',
        duration: 1000
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      return;
    }

    if (this.editingItemId === null) {
      hilog.warn(0x0000, TAG, '[EditSwissKnifePage] Attempted to save without an active editing item.');
      return;
    }

    const currentItem = this.findFanItemById(this.editingItemId);
    const selectedTagId = this.getSelectedTagId();
    const iconToSave = this.editingEmojiChar && this.editingEmojiChar.trim().length > 0
      ? this.editingEmojiChar
      : (currentItem?.icon ?? '');
    const directRecordData: DirectRecordData = {
      tagId: selectedTagId,
      autoStart: currentItem?.directRecordData?.autoStart ?? false
    };

    const updatedItem = fanItemService.updateFanItem(this.editingItemId, {
      icon: iconToSave,
      label: trimmedName,
      directRecordData
    });

    if (!updatedItem) {
      promptAction.openToast({
        message: '更新失败，请稍后重试',
        duration: 1000
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      return;
    }

    const refreshed: FanItem[] = fanItemService.getAllFanItems();
    this.swissKnifeItems = toFanItemVOs(refreshed, this.tagData);
    this.isActivitySheetShow = false;
    this.resetSheetState();

    promptAction.openToast({
      message: '快捷事项已更新',
      duration: 1000
    }).catch(() => {
    });
    void this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
  }

  /**
   * 使用通用组件构建编辑表单内容
   */
  @Builder
  editItemBuilder() {
    ItemFormContent({
      config: this.sheetConfig,
      tagData: this.tagData,
      inputName: this.activityName,
      selectedTagIndex: this.selectedTagIndex,
      directStartEnabled: this.directStartEnabled,
      isEditingTag: this.isEditingTag,
      tagShakeAngle: this.tagShakeAngle,
      selectedEmoji: this.editingEmojiChar,
      isDarkTheme: this.isDarkTheme
    })
  }

  /**
   * 使用通用组件构建标题栏
   */
  @Builder
  titleBuilder() {
    buildSheetTitleBar({
      title: this.sheetConfig.titleBar.title,
      actionButtonText: this.sheetConfig.titleBar.actionButtonText,
      onClose: () => {
        this.isActivitySheetShow = false;
        this.resetSheetState();
      },
      onSubmit: async () => {
        void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
        await this.persistSwissKnifeItem();
      }
    })
  }

  build() {
    NavDestination() {
      Row() {
        Button({type: ButtonType.Circle}) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(18)
            .fontWeight(500)
            .fontColor([$r('app.color.text_primary')])
        }
        .onClick(() => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
          this.handleCloseClick();
        })
        .margin({ right: 10 })
        .padding(10)
        .backgroundColor($r('app.color.neutral_100'))
        .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)

        Text($r('app.string.setting_today'))
          .fontWeight(700)
          .fontSize(26)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      .padding({ top: 16, bottom: 16 })

      List({space: 10}) {
        ForEach(this.swissKnifeItems, (item: FanItemVO)=> {
          ListItem() {
              Row() {
                Text(item.icon)
                  .fontSize(18)
                  .padding(8)
                  .margin({ right: 10 })
                  .backgroundColor($r('app.color.bg_main'))
                  .borderRadius('50%')
                Column({ space: 4 }) {
                  Text(item.label)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontWeight(600)
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                  Row() {
                    if (item.tagMeta) {
                      Row()
                        .width(5)
                        .height(5)
                        .borderRadius('50%')
                        .margin({right: 5})
                        .backgroundColor(item.tagMeta?.color)
                      Text(item.tagMeta?.name)
                        .fontSize(12)
                        .fontWeight(500)
                        .fontColor($r('app.color.text_secondary'))
                    } else {
                      Row()
                        .width(5)
                        .height(5)
                        .borderRadius('50%')
                        .margin({right: 5})
                        .backgroundColor($r('app.color.text_tertiary'))
                      Text('无标签')
                        .fontSize(12)
                        .fontWeight(400)
                        .fontColor($r('app.color.text_secondary'))
                    }
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .flexGrow(1)

                Button({type: ButtonType.Circle}) {
                  SymbolGlyph($r('sys.symbol.square_and_pencil'))
                    .fontSize(18)
                    .fontWeight(500)
                    .fontColor([$r('app.color.text_secondary')])
                }
                .onClick(() => {
                  void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                  this.openEditSheetForItem(item);
                })
                .margin({ right: 10 })
                .padding(10)
                .backgroundColor($r('app.color.bg_main'))
              }
              .justifyContent(FlexAlign.Center)
              .width('100%')
              .padding({left: 10, top: 10, bottom: 10})
            }
          .borderRadius($r('app.float.default_border_radius'))
            .backgroundColor($r('app.color.bg_card'))
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({x: 200})).animation({ curve: curves.springMotion(), duration: 300 }))
        })
      }
      .borderRadius($r('app.float.default_border_radius'))
      .bindSheet($$this.isActivitySheetShow, this.editItemBuilder(), {
        detents: this.activitySheetDetents,
        showClose: false,
        dragBar: false,
        preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        enableOutsideInteractive: false,
        keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
        title: this.titleBuilder,
        onWillAppear: () => {
          this.updateActivitySheetDetents();
        },
        onWillDismiss: ((dismissSheetAction: DismissSheetAction) => {
          this.isActivitySheetShow = false;
          this.updateActivitySheetDetents();
          this.resetSheetState();
          if (dismissSheetAction.reason === DismissReason.CLOSE_BUTTON) {
            dismissSheetAction.dismiss();
          }
          if (dismissSheetAction.reason === DismissReason.PRESS_BACK) {
            dismissSheetAction.dismiss();
          }
          if (dismissSheetAction.reason == DismissReason.SLIDE_DOWN) {
            dismissSheetAction.dismiss();
          }
        })
      })
      .width('100%')
      // .height('100%')

      Column({space: 5}) {
        // Text($r('app.string.setting_short_cut'))
        //   .fontSize(20)
        //   .fontWeight(600)
        //   .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.setting_short_cut_detail'))
          .fontSize(14)
          .lineHeight(20)
          .fontWeight(FontWeight.Normal)
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_secondary'))
      }
      .transition(TransitionEffect.OPACITY.animation({curve: Curve.EaseIn, duration: 350}))
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .margin({top: 16})
    }
    .padding({left: 16, right: 16})
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
    })
    .onBackPressed((): boolean => {
      if (this.onBack) {
        this.onBack();
        return true;
      }
      this.pageInfos.pop(1);
      return true;
    })
    // .title($r('app.string.setting_today'), {
    //   backgroundColor: $r('app.color.bg_main')
    // })
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
  }
}
