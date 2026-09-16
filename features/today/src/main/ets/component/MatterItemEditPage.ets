import {
  MatterItemModel,
  MatterItemModelInit,
  DEFAULT_SHEET_HEIGHT,
  calculateSheetHeight,
  BreakpointConstants,
  BreakpointSystem,
  BreakpointType,
  AppShadows,
  EmojiItem,
  EmojiUtil,
  MatterStatus,
  TimeRecord,
  TimeRecordUtil,
  VibratorUtil,
  tagService,
  StringUtil,
  ItemFormSheetConfig,
  ItemFormSheetPresets,
  buildSheetTitleBar,
  ItemFormContent,
  buildFlowDiaryImportEnvelope,
  buildFlowLightEffect,
  COLOR_MODE_STORAGE_KEY,
  COLOR_MODE_VERSION_KEY,
  generateFlowDiaryImportRequestId,
  goalFighterShareService
} from 'base';
import { LabelItem } from "./LabelItem";
import { hilog } from "@kit.PerformanceAnalysisKit";
import { common, ConfigurationConstant } from "@kit.AbilityKit";
import { todayActivityService } from "../model/TodayActivityService";
import { MatterDetailCard } from "./MatterDetailCard";
import { curves, promptAction, window } from "@kit.ArkUI";
import { TimeRecordDetailCard } from "./TimeRecordDetailCard";
import { TagModel } from "../model/TagModel";
import { TagItem } from "base/src/main/ets/common/model/TagItem";
import { addNewItemDialog } from "./AddNewItemDialog";
import { faceDetector } from "@kit.CoreVisionKit";
import { MatterItemStateManager } from "../utils/MatterItemStateManager";
import {
  hdsEffect,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';


@Builder
export function MatterItemEditPageBuilder(name: string, param?: Object) {
  MatterItemEditPage();
}

const TAG = 'MatterItemEditPage'
@Component
export struct MatterItemEditPage {

  pageInfos: NavPathStack = new NavPathStack();

  @State item: MatterItemModel | undefined = undefined;
  @State totalDuration: string | undefined = undefined;
  @State allTimeRecords: TimeRecord[] = [];
  @State averageDuration: string = '';
  @State longestDuration: string = '';
  @State isShowEditSheet: boolean = false;
  @State isShowNewSheet: boolean = false;
  @State isActivitySheetShow: boolean = false;
  @State private activitySheetDetents: [Length | SheetSize, (Length | SheetSize)?, (Length | SheetSize)?] =
    [SheetSize.MEDIUM, SheetSize.LARGE];
  @State activityName: string = ''
  @State selectedTagIndex: number = -1;
  @State selectedLabelIndex: number = -1;
  @State inputTagName: string = '';
  @State tempStartTime: Date = new Date();
  @State tempEndTime: Date = new Date();
  @State currentEditingRecord: TimeRecord | null = null;
  @State displayStartTime: string = '';
  @State displayEndTime: string = '';
  @State selectedTag: TagItem | undefined = undefined;
  @State deletingRecordIds: string[] = [];
  @State sheetHeight: number = DEFAULT_SHEET_HEIGHT;
  @State isKeyBoardHidden: boolean = false;
  // 在组件中定义一个状态变量来存储软键盘高度
  @State keyboardHeight: number = 0;
  @State viewportHeight: number = 0;
  @State emojis: EmojiItem[] = EmojiUtil.getAll();
  // 编辑事项Sheet的状态
  @State isEditingTag: boolean = false;
  @State tagShakeAngle: number = 0;
  @State directStartEnabled: boolean = false;
  @State selectedEmojiChar: string = '';
  @State private isGoalFighterAvailable: boolean = false;
  @State private shaderController: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  @State private isFlowEffectMounted: boolean = true;
  // 编辑事项Sheet配置
  private editMatterSheetConfig: ItemFormSheetConfig = ItemFormSheetPresets.createEditMatterConfig();
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  private flowEffectRemountToken: number = 0;
  private isPageActive: boolean = false;

  @StorageLink('doneMatterData') doneMatterData: MatterItemModel[] = []
  @StorageLink('unDoMatterData') unDoMatterData: MatterItemModel[] = []
  @StorageLink('tagData') tagData: TagModel[] = [];
  @StorageLink('isCustomDialogShow') isCustomDialogShow: boolean = false;
  @StorageLink('matterDataRevision') matterDataRevision: number = -1;
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange')
  private currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 版本号在系统资源真正切换之后才会递增，保证流光 shader 用新色板重建
  @StorageProp(COLOR_MODE_VERSION_KEY) @Watch('onColorModeVersionChange')
  private colorModeVersion: number = 0;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  /**
   * 重置表单状态
   */
  private resetFormState(): void {
    this.syncFormWithCurrentItem();
    this.inputTagName = '';
    this.selectedLabelIndex = -1;
    this.updateSheetHeight();
  }

  private syncFormWithCurrentItem(): void {
    this.activityName = this.item?.title ?? '';

    if (!this.tagData || this.tagData.length === 0) {
      this.selectedTagIndex = -1;
      return;
    }

    const currentTagIndex = this.item?.label
      ? this.tagData.findIndex(tag => tag.name === this.item?.label)
      : -1;

    this.selectedTagIndex = currentTagIndex;
  }

  /**
   * 根据标签数量更新编辑面板高度，保持与TodayPage一致
   */
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

  /**
   * 处理"编辑"按钮的点击事件。
   * @param name - 活动的名称。
   * @param tagId - 所选标签的ID，如果没有选择则为 null。
   */
  async handleEditActivityButtonClick(name: string, tagId: string | null): Promise<void> {
    // 验证输入
    if (!name || name.trim().length === 0) {
      hilog.error(0x0000, TAG, '活动名称不能为空');
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      return;
    }

    hilog.info(0x0000, TAG, `User trying to edit activity: ${name} with tagId: ${tagId}`);

    try {
      // 使用 updateActivityNameAndTag 方法同时更新活动名称和标签
      const updateResult = await todayActivityService.updateActivityNameAndTag(
        this.item?.id as string,
        name,
        tagId
      );

      if (updateResult) {
        hilog.info(0x0000, TAG, 'Activity updated successfully.');
        
        // 更新本地item数据以反映更改
        if (this.item) {
          this.item.title = name;
          
          // 更新标签信息
          if (tagId && this.selectedTagIndex >= 0) {
            const selectedTag = this.tagData[this.selectedTagIndex];
            this.item.label = selectedTag.name;
            this.item.labelColor = selectedTag.color;
          } else if (!tagId) {
            this.item.label = '无标签';
            this.item.labelColor = $r('app.color.text_tertiary');
          }
          
          this.selectedTag = tagId ? await todayActivityService.getTagByActivityId(this.item.id) : undefined;
          this.syncFormWithCurrentItem();

          // 同步全局状态，确保今日列表展示最新信息
          await this.refreshGlobalMatterData();
        }
        
        hilog.info(0x0000, TAG, `Activity ${this.item?.id} updated in local state`);
        await this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
      } else {
        hilog.error(0x0000, TAG, 'Failed to update the activity in the database.');
        await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Error updating activity: ${JSON.stringify(error)}`);
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    }
  }

  /**
   * 将编辑后的事项同步到全局状态管理器，触发今日列表刷新
   */
  private async refreshGlobalMatterData(): Promise<void> {
    if (!this.item) {
      return;
    }

    try {
      const manager = MatterItemStateManager.getInstance();
      await manager.refreshItemState(this.item.id);

      const latest = await todayActivityService.getTodayMatterItemById(this.item.id);
      if (latest) {
        this.item.title = latest.title;
        this.item.label = latest.label;
        this.item.labelColor = latest.labelColor;
        this.item.status = latest.status;
        this.item.durationInMilliseconds = latest.durationInMilliseconds;
      }

      const normalizedItem = this.item.clone();

      const upsertInto = (list: Array<MatterItemModel | MatterItemModelInit>): MatterItemModel[] => {
        const next = MatterItemModel.ensureList(list);
        const existingIndex = next.findIndex(existing => existing.id === normalizedItem.id);
        if (existingIndex >= 0) {
          next[existingIndex].apply(normalizedItem);
        } else {
          next.push(normalizedItem.clone());
        }
        return next;
      };

      const removeFrom = (list: Array<MatterItemModel | MatterItemModelInit>): MatterItemModel[] =>
        MatterItemModel.ensureList(list).filter(existing => existing.id !== normalizedItem.id);

      const shouldBeInDone = normalizedItem.status === MatterStatus.PAUSED
        || normalizedItem.status === MatterStatus.RECORDING;

      const updatedDone = shouldBeInDone
        ? upsertInto(this.doneMatterData)
        : removeFrom(this.doneMatterData);

      const updatedUnDo = shouldBeInDone
        ? removeFrom(this.unDoMatterData)
        : upsertInto(this.unDoMatterData);

      this.doneMatterData = updatedDone;
      this.unDoMatterData = updatedUnDo;
      AppStorage.set('doneMatterData', updatedDone);
      AppStorage.set('unDoMatterData', updatedUnDo);

      AppStorage.set('matterDataRevision', this.matterDataRevision + 1);
      hilog.info(0x0000, TAG, `Global state refreshed for activity ${this.item.id}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh global state: ${JSON.stringify(error)}`);
    }
  }

  async aboutToAppear(): Promise<void> {
    this.isPageActive = true;
    this.recreateFlowEffect();
    this.breakpointSystem.register();
    this.refreshGoalFighterAvailability();
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
        hilog.info(0x0000, TAG, 'soft keyboard pop up in height of:' + this.keyboardHeight);
        this.updateActivitySheetDetents();
      })
    })

    this.updateSheetHeight();
    await this.vibratorUtil.initialize();
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.flowEffectRemountToken += 1;
    void this.vibratorUtil.stopAllHaptics();
    this.breakpointSystem.unregister();
  }

  private onColorModeChange(): void {
    this.recreateFlowEffect();
  }

  private onColorModeVersionChange(): void {
    this.onColorModeChange();
  }

  private recreateFlowEffect(): void {
    this.flowEffectRemountToken += 1;
    const remountToken: number = this.flowEffectRemountToken;
    this.shaderController = new hdsEffect.ShaderEffectController();
    this.isFlowEffectMounted = false;
    setTimeout((): void => {
      if (this.isPageActive && remountToken === this.flowEffectRemountToken) {
        this.isFlowEffectMounted = true;
      }
    }, 0);
  }

  /**
   * 更新选中标签索引
   */
  private updateSelectedTagIndex(): void {
    if (this.selectedTag && this.tagData && this.tagData.length > 0) {
      this.selectedTagIndex = this.tagData.findIndex(item => item.id == this.selectedTag?.id);
    }
  }

  /**
   * 监听标签数据变化
   */
  onTagDataChange() {
    if (this.selectedTag) {
      this.updateSelectedTagIndex();
    }

    this.updateSheetHeight();
  }

  private getTimeFieldWidth(): number {
    return new BreakpointType<number>({ sm: 150, md: 180, lg: 200 }).getValue(this.currentBreakpoint);
  }

  private getTimeFieldHeight(): number {
    return new BreakpointType<number>({ sm: 40, md: 44, lg: 48 }).getValue(this.currentBreakpoint);
  }

  private getRecordSheetHeight(): number {
    return new BreakpointType<number>({ sm: 250, md: 280, lg: 320 }).getValue(this.currentBreakpoint);
  }

  private getListLanes(): number {
    return this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG ? 2 : 1;
  }

  @Builder
  editTimeRecordBuilder(record: TimeRecord) {
    Scroll() {
      Column() {
        Row() {
          Column() {
            Text('开始')
              .fontSize(16)
              .fontWeight(500)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ left: 5, bottom: 10 })

            Row() {
              Text(this.displayStartTime)
                .fontSize(16)
                .fontWeight(600)
                .fontColor($r('app.color.neutral_800'))
              SymbolGlyph($r('sys.symbol.clock'))
                .fontSize(16)
                .fontWeight(600)
                .fontColor([$r('app.color.neutral_500')])
            }
            .justifyContent(FlexAlign.SpaceBetween)
            .width(this.getTimeFieldWidth())
            .height(this.getTimeFieldHeight())
            .borderRadius('50%')
            .backgroundColor($r('app.color.neutral_100'))
            .padding({left: 15, right: 15, top: 5, bottom: 5})
            .onClick(() => {
              void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
              this.tempStartTime = new Date(record.startTime)
              this.getUIContext().showTimePickerDialog({
                selected: this.tempStartTime,
                format: TimePickerFormat.HOUR_MINUTE,
                useMilitaryTime: true,
                onAccept: async (value: TimePickerResult) => {
                  if (value.hour != undefined && value.minute != undefined) {
                    // 先创建临时时间对象用于验证
                    const newTempStartTime = new Date(this.tempStartTime);
                    newTempStartTime.setHours(value.hour, value.minute);
                    
                    // 检查时间合法性：开始时间必须早于结束时间
                    if (this.tempEndTime && newTempStartTime.getTime() >= this.tempEndTime.getTime()) {
                      promptAction.openToast({
                        message: '开始时间必须早于结束时间',
                        duration: 1000
                      });
                      return; // 不合法直接返回，不更新任何数据
                    }
                    
                    // 时间合法，更新临时时间和显示
                    this.tempStartTime.setHours(value.hour, value.minute);
                    console.info("TimePickerDialog:onAccept()" + JSON.stringify(value));
                    // 只更新UI显示，不更新实际数据
                    this.displayStartTime = TimeRecordUtil.formatToHHmm(this.tempStartTime.getTime());
                  }
                },
              })
            })
          }
          .alignItems(HorizontalAlign.Start)

          Column() {
            Text('结束')
              .fontSize(16)
              .fontWeight(500)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ left: 5, bottom: 10 })

            Row() {
              Text(this.displayEndTime)
                .fontSize(16)
                .fontWeight(600)
                .fontColor($r('app.color.neutral_800'))
              SymbolGlyph($r('sys.symbol.clock'))
                .fontSize(16)
                .fontWeight(600)
                .fontColor([$r('app.color.neutral_500')])
            }
            .justifyContent(FlexAlign.SpaceBetween)
            .width(this.getTimeFieldWidth())
            .height(this.getTimeFieldHeight())
            .borderRadius('50%')
            .backgroundColor($r('app.color.neutral_100'))
            .padding({left: 15, right: 15, top: 5, bottom: 5})
            .onClick(() => {
              void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
              if (record.endTime) {
                this.tempEndTime = new Date(record.endTime)
                this.getUIContext().showTimePickerDialog({
                  selected: this.tempEndTime,
                  format: TimePickerFormat.HOUR_MINUTE,
                  useMilitaryTime: true,
                  onAccept: async (value: TimePickerResult) => {
                    if (value.hour != undefined && value.minute != undefined) {
                      // 先创建临时时间对象用于验证
                      const newTempEndTime = new Date(this.tempEndTime);
                      newTempEndTime.setHours(value.hour, value.minute);
                      
                      // 检查时间合法性：结束时间必须晚于开始时间
                      if (this.tempStartTime && newTempEndTime.getTime() <= this.tempStartTime.getTime()) {
                        promptAction.openToast({
                          message: '结束时间必须晚于开始时间',
                          duration: 1000
                        });
                        return; // 不合法直接返回，不更新任何数据
                      }
                      
                      // 时间合法，更新临时时间和显示
                      this.tempEndTime.setHours(value.hour, value.minute);
                      console.info("TimePickerDialog:onAccept() for end time" + JSON.stringify(value));
                      // 只更新UI显示，不更新实际数据
                      this.displayEndTime = TimeRecordUtil.formatToHHmm(this.tempEndTime.getTime());
                    }
                  },
                })
              } else {
                // 如果记录没有结束时间，说明是进行中的记录，不能直接编辑结束时间
                promptAction.openToast({
                  message: '请先停止计时再编辑结束时间',
                  duration: 1000
                });
              }
            })
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({bottom: 10})

        Button('保存')
          .width('100%')
          .onClick(async () => {
            void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            if (this.currentEditingRecord) {
              // 验证时间有效性
              const newDuration = this.tempEndTime.getTime() - this.tempStartTime.getTime();

              if (newDuration <= 0) {
                hilog.error(0x0000, TAG, `Invalid duration: ${newDuration}ms for record ${this.currentEditingRecord.id}`);
                promptAction.openToast({
                  message: '请检查时间合法性',
                  duration: 1000
                });
                await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
                return;
              }
              
              // 调用更新方法
              await this.updateTimeRecord(this.currentEditingRecord, newDuration);
              // 关闭编辑面板
              this.isShowEditSheet = false;
            }
          })
      }
      .width('100%')
      .padding(20)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ minHeight: '100%' })
    }
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .height('100%')
  }

  @Builder
  addTimeRecordBuilder() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            Text('开始')
              .fontSize(16)
              .fontWeight(500)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ left: 5, bottom: 10 })

            Row() {
              Text(this.displayStartTime)
                .fontSize(16)
                .fontWeight(600)
                .fontColor($r('app.color.neutral_800'))
              SymbolGlyph($r('sys.symbol.clock'))
                .fontSize(16)
                .fontWeight(600)
                .fontColor([$r('app.color.neutral_500')])
            }
            .justifyContent(FlexAlign.SpaceBetween)
            .width(this.getTimeFieldWidth())
            .height(this.getTimeFieldHeight())
            .borderRadius('50%')
            .backgroundColor($r('app.color.neutral_100'))
            .padding({left: 15, right: 15, top: 5, bottom: 5})
            .onClick(() => {
              void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
              this.getUIContext().showTimePickerDialog({
                selected: this.tempStartTime,
                format: TimePickerFormat.HOUR_MINUTE,
                useMilitaryTime: true,
                onAccept: async (value: TimePickerResult) => {
                  if (value.hour != undefined && value.minute != undefined) {
                    // 先创建临时时间对象用于验证
                    const newTempStartTime = new Date(this.tempStartTime);
                    newTempStartTime.setHours(value.hour, value.minute);

                    // 检查时间合法性：开始时间必须早于结束时间
                    if (this.tempEndTime && newTempStartTime.getTime() >= this.tempEndTime.getTime()) {
                      promptAction.openToast({
                        message: '开始时间必须早于结束时间',
                        duration: 1000
                      });
                      return; // 不合法直接返回，不更新任何数据
                    }

                    // 时间合法，更新临时时间和显示
                    this.tempStartTime.setHours(value.hour, value.minute);
                    console.info("TimePickerDialog:onAccept()" + JSON.stringify(value));
                    // 只更新UI显示，不更新实际数据
                    this.displayStartTime = TimeRecordUtil.formatToHHmm(this.tempStartTime.getTime());
                  }
                },
              })
            })
          }
          .alignItems(HorizontalAlign.Start)

          Column() {
            Text('结束')
              .fontSize(16)
              .fontWeight(500)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ left: 5, bottom: 10 })

            Row() {
              Text(this.displayEndTime)
                .fontSize(16)
                .fontWeight(600)
                .fontColor($r('app.color.neutral_800'))
              SymbolGlyph($r('sys.symbol.clock'))
                .fontSize(16)
                .fontWeight(600)
                .fontColor([$r('app.color.neutral_500')])
            }
            .justifyContent(FlexAlign.SpaceBetween)
            .width(this.getTimeFieldWidth())
            .height(this.getTimeFieldHeight())
            .borderRadius('50%')
            .backgroundColor($r('app.color.neutral_100'))
            .padding({left: 15, right: 15, top: 5, bottom: 5})
            .onClick(() => {
              void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
              this.getUIContext().showTimePickerDialog({
                selected: this.tempEndTime,
                format: TimePickerFormat.HOUR_MINUTE,
                useMilitaryTime: true,
                onAccept: async (value: TimePickerResult) => {
                  if (value.hour != undefined && value.minute != undefined) {
                    // 先创建临时时间对象用于验证
                    const newTempEndTime = new Date(this.tempEndTime);
                    newTempEndTime.setHours(value.hour, value.minute);

                    // 检查时间合法性：结束时间必须晚于开始时间
                    if (this.tempStartTime && newTempEndTime.getTime() <= this.tempStartTime.getTime()) {
                      promptAction.openToast({
                        message: '结束时间必须晚于开始时间',
                        duration: 1000
                      });
                      return; // 不合法直接返回，不更新任何数据
                    }

                    // 时间合法，更新临时时间和显示
                    this.tempEndTime.setHours(value.hour, value.minute);
                    console.info("TimePickerDialog:onAccept() for end time" + JSON.stringify(value));
                    // 只更新UI显示，不更新实际数据
                    this.displayEndTime = TimeRecordUtil.formatToHHmm(this.tempEndTime.getTime());
                  }
                },
              })
            })
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({bottom: 10})

        Button('添加')
          .width('100%')
          .onClick(async () => {
            void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            if (this.item) {
              // 验证时间有效性
              const newDuration = this.tempEndTime.getTime() - this.tempStartTime.getTime();

              if (newDuration <= 0) {
                hilog.error(0x0000, TAG, `Invalid duration: ${newDuration}ms for new record`);
                promptAction.openToast({
                  message: '请检查时间合法性',
                  duration: 1000
                });
                await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
                return;
              }
              
              // 调用添加方法
              const added = await this.addTimeRecord(this.item.id, this.tempStartTime.getTime(), this.tempEndTime.getTime(), newDuration);
              
              // 仅在成功时关闭添加面板，失败时保持面板打开以便立即重试
              if (added) {
                this.isShowNewSheet = false;
              }
            }
          })
      }
      .width('100%')
      .padding(20)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ minHeight: '100%' })
    }
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .height('100%')
  }

  @Builder
  editTitleBuilder(title: string) {
    Row() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontColor([$r('app.color.text_primary')])
        }
        .height(40)
        .width(40)
        .backgroundColor($r('app.color.neutral_100'))
        .margin({right: 5})
        .onClick(() => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
          // 根据当前显示的面板类型关闭相应的面板
          this.isShowEditSheet = false
        })
        Text(title)
          .fontSize(23)
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  addTitleBuilder(title: string) {
    Row() {
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontColor([$r('app.color.text_primary')])
        }
        .height(40)
        .width(40)
        .backgroundColor($r('app.color.neutral_100'))
        .margin({right: 5})
        .onClick(() => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
          // 根据当前显示的面板类型关闭相应的面板
          this.isShowNewSheet = false
        })
        Text(title)
          .fontSize(23)
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  editItemBuilder() {
    ItemFormContent({
      config: this.editMatterSheetConfig,
      tagData: this.tagData,
      inputName: this.activityName,
      selectedTagIndex: this.selectedTagIndex,
      directStartEnabled: this.directStartEnabled,
      isEditingTag: this.isEditingTag,
      tagShakeAngle: this.tagShakeAngle,
      selectedEmoji: this.selectedEmojiChar,
      isDarkTheme: this.isDarkTheme
    })
  }

  @Builder
  titleBuilder() {
    buildSheetTitleBar({
      title: this.editMatterSheetConfig.titleBar.title,
      actionButtonText: this.editMatterSheetConfig.titleBar.actionButtonText,
      onClose: () => {
        void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
        this.isActivitySheetShow = false;
        this.resetFormState();
      },
      onSubmit: async () => {
        void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
        if (this.activityName.length <= 0) {
          promptAction.openToast({
            duration: 1000,
            message: '请完整填写事项信息'
          });
          await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
          return;
        }
        const selectedTagId = this.selectedTagIndex >= 0 ? this.tagData[this.selectedTagIndex].id : null;
        await this.handleEditActivityButtonClick(this.activityName, selectedTagId);
        this.isActivitySheetShow = false;
        this.resetFormState();
      }
    })
  }

  private addNewItemDialogController: CustomDialogController | null = new CustomDialogController({
    builder: addNewItemDialog({isShow: false, inputActivityName: this.activityName, selectedTagIndex: this.selectedTagIndex, sheetHeight: 0, inputTagName: this.inputTagName, selectedLabelIndex: this.selectedLabelIndex}),
    alignment: DialogAlignment.Center,
    maskColor: '#80000000',
    backgroundBlurStyle: BlurStyle.Thick,
    backgroundColor: $r('app.color.primary_lighter'),
    onWillDismiss:(dismissDialogAction: DismissDialogAction)=> {
      console.info(`reason= ${dismissDialogAction.reason}`);
      console.info('dialog onWillDismiss');
      if (dismissDialogAction.reason == DismissReason.PRESS_BACK) {
        dismissDialogAction.dismiss();
      }
      if (dismissDialogAction.reason == DismissReason.TOUCH_OUTSIDE) {
        dismissDialogAction.dismiss();
      }
    },
    keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
    offset: { dx: 0, dy: 0 } }
  )

  // 初始化编辑面板状态
  private initEditSheetState(record: TimeRecord) {
    this.currentEditingRecord = record;
    this.tempStartTime = new Date(record.startTime);
    this.tempEndTime = record.endTime ? new Date(record.endTime) : new Date();
    this.displayStartTime = TimeRecordUtil.formatToHHmm(record.startTime);
    this.displayEndTime = record.endTime ? TimeRecordUtil.formatToHHmm(record.endTime) : '进行中';
  }

  // 初始化添加面板状态
  private initAddSheetState() {
    const now = new Date();
    this.tempStartTime = new Date(now);
    this.tempEndTime = new Date(now);
    this.displayStartTime = TimeRecordUtil.formatToHHmm(now.getTime());
    this.displayEndTime = TimeRecordUtil.formatToHHmm(now.getTime());
  }

  async updateTimeRecord(record: TimeRecord, newDuration?: number) {

    // 更新time record的开始时间
    const updateResult = await todayActivityService.updateTimeRecordStartEndTime(record.id, this.tempStartTime.getTime(), this.tempEndTime.getTime(), newDuration);

    if (updateResult) {
      hilog.info(0x0000, TAG, `Time record time updated successfully for record ${record.id}, ${JSON.stringify(record.startTime)} - ${JSON.stringify(record.endTime)}`);

      const updatedStart = this.tempStartTime.getTime();
      const updatedEnd = this.tempEndTime.getTime();
      const updatedDuration = newDuration ?? (updatedEnd - updatedStart);

      this.getUIContext().animateTo({
        duration: 300,
        curve: curves.springMotion()
      }, () => {
        const removedRecord = this.removeRecordById(record.id) ?? record;
        removedRecord.startTime = updatedStart;
        removedRecord.endTime = updatedEnd;
        removedRecord.duration = updatedDuration;
        this.insertRecordSorted(removedRecord);
        this.onAllTimeRecordsChange();
      });

      await this.ensurePausedStatusIfNoActiveRecord();
      await this.refreshGlobalMatterData();

      // 显示成功提示
      promptAction.openToast({
        message: '时间记录已更新',
        duration: 1000
      }).catch(() => {
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
    } else {
      hilog.error(0x0000, TAG, `Failed to update time record time for record ${record.id}`);
      promptAction.openToast({
        message: '更新时间记录失败',
        duration: 1000
      }).catch(() => {
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    }
  }

  async addTimeRecord(activityId: string, startTime: number, endTime: number, duration: number): Promise<boolean> {
    try {
      // 统一通过服务层添加时间记录，避免旁路写入
      const recordId = await todayActivityService.addManualTimeRecord(activityId, startTime, endTime, duration);

      if (recordId) {
        hilog.info(0x0000, TAG, `Time record added successfully for activity ${activityId}, record ID: ${recordId}`);

        const newRecord = new TimeRecord(recordId, activityId, startTime, endTime, duration);

        this.getUIContext().animateTo({
          duration: 300,
          curve: curves.springMotion()
        }, () => {
          this.insertRecordSorted(newRecord);
          this.onAllTimeRecordsChange();
        });

        await this.ensurePausedStatusIfNoActiveRecord();
        await this.refreshGlobalMatterData();

        // 显示成功提示
        promptAction.openToast({
          message: '时间记录已添加',
          duration: 1000
        }).catch(() => {
        });
        await this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
        return true;
      } else {
        hilog.error(0x0000, TAG, `Failed to add time record for activity ${activityId} (insert returned empty id; likely transient DB busy)`);
        promptAction.openToast({
          message: '添加时间记录失败，请重试',
          duration: 1000
        }).catch(() => {
        });
        await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
        return false;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Error adding time record: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '添加时间记录时发生错误',
        duration: 1000
      }).catch(() => {
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      return false;
    }
  }

  private getRecordDuration(record: TimeRecord): number {
    if (record.duration !== undefined && record.duration > 0) {
      return record.duration;
    }
    if (record.endTime !== undefined) {
      return record.endTime - record.startTime;
    }
    return 0;
  }

  private insertRecordSorted(record: TimeRecord): void {
    const insertIndex = this.allTimeRecords.findIndex(item => item.startTime < record.startTime);
    if (insertIndex === -1) {
      this.allTimeRecords.push(record);
    } else {
      this.allTimeRecords.splice(insertIndex, 0, record);
    }
  }

  private removeRecordById(recordId: string): TimeRecord | null {
    const index = this.allTimeRecords.findIndex(item => item.id === recordId);
    if (index === -1) {
      return null;
    }
    const removedRecord = this.allTimeRecords[index];
    this.allTimeRecords.splice(index, 1);
    return removedRecord ?? null;
  }

  private calculateTodayTotalDuration(): number {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStart = today.getTime();

    return this.allTimeRecords.reduce((sum, record) => {
      if (record.startTime >= todayStart) {
        return sum + this.getRecordDuration(record);
      }
      return sum;
    }, 0);
  }

  onAllTimeRecordsChange(): void {
    if (!this.item) {
      return;
    }

    const todayDuration = this.calculateTodayTotalDuration();
    this.totalDuration = TimeRecordUtil.formatDuration(todayDuration);
    this.item.durationInMilliseconds = todayDuration;

    this.calculateDurationStats();
    
    // Handle duration-driven status changes
    this.handleDurationDrivenStatusChange(todayDuration);
  }

  /**
   * Handle automatic status changes based on duration
   * - If duration becomes zero, move to TODO status and unDoMatterData
   * - If duration becomes non-zero from TODO, move to PAUSED status and doneMatterData
   */
  private async handleDurationDrivenStatusChange(todayDuration: number): Promise<void> {
    if (!this.item) {
      return;
    }

    try {
      let statusChanged = false;
      let newStatus = this.item.status;

      if (todayDuration <= 0 && this.item.status !== MatterStatus.TODO) {
        // Duration is zero, should be TODO
        hilog.info(0x0000, TAG, `Item ${this.item.id} has zero duration, changing to TODO status`);
        const updateSuccess = await todayActivityService.updateActivityStatus(this.item.id, MatterStatus.TODO);
        if (updateSuccess) {
          newStatus = MatterStatus.TODO;
          statusChanged = true;
          hilog.info(0x0000, TAG, `Successfully changed item ${this.item.id} to TODO status`);
        }
      } else if (todayDuration > 0 && this.item.status === MatterStatus.TODO) {
        // Duration is non-zero and was TODO, should be PAUSED
        hilog.info(0x0000, TAG, `Item ${this.item.id} gained duration, changing to PAUSED status`);
        const updateSuccess = await todayActivityService.updateActivityStatus(this.item.id, MatterStatus.PAUSED);
        if (updateSuccess) {
          newStatus = MatterStatus.PAUSED;
          statusChanged = true;
          hilog.info(0x0000, TAG, `Successfully changed item ${this.item.id} to PAUSED status`);
        }
      }

      if (statusChanged) {
        this.item.status = newStatus;
        await this.refreshGlobalMatterData();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Error in handleDurationDrivenStatusChange: ${JSON.stringify(error)}`);
    }
  }

  // 计算平均时长和最长时长
  private calculateDurationStats() {
    if (this.allTimeRecords.length === 0) {
      this.averageDuration = '0h';
      this.longestDuration = '0h';
      return;
    }

    let totalDuration = 0;
    let completedCount = 0;
    let maxDuration = 0;

    this.allTimeRecords.forEach(record => {
      const duration = this.getRecordDuration(record);
      if (duration > 0) {
        totalDuration += duration;
        completedCount++;
        if (duration > maxDuration) {
          maxDuration = duration;
        }
      }
    });

    const avgDuration = completedCount > 0 ? totalDuration / completedCount : 0;

    this.averageDuration = TimeRecordUtil.formatDuration(avgDuration);
    this.longestDuration = TimeRecordUtil.formatDuration(maxDuration);
  }

  private async ensurePausedStatusIfNoActiveRecord(): Promise<void> {
    if (!this.item) {
      return;
    }

    const hasActiveRecord = this.allTimeRecords.some(record => !record.endTime);
    if (hasActiveRecord) {
      return;
    }

    if (this.allTimeRecords.length === 0) {
      return;
    }

    if (this.item.status === MatterStatus.PAUSED) {
      return;
    }

    const updateSucceeded = await todayActivityService.updateActivityStatus(this.item.id, MatterStatus.PAUSED);
    if (updateSucceeded) {
      this.item.status = MatterStatus.PAUSED;
    }
  }

  private isRecordDeleting(recordId: string): boolean {
    return this.deletingRecordIds.includes(recordId);
  }

  private markRecordDeleting(recordId: string, deleting: boolean): void {
    const keptIds: string[] = this.deletingRecordIds.filter((id: string) => id !== recordId);
    if (deleting) {
      keptIds.push(recordId);
    }
    this.deletingRecordIds = keptIds;
  }

  async handleDeleteButtonClicked(record: TimeRecord) {
    hilog.info(0x0000, TAG, `User trying to delete time record: ${record.id}`);
    if (this.isRecordDeleting(record.id)) {
      hilog.warn(0x0000, TAG, `Duplicate delete click ignored for record: ${record.id}`);
      return;
    }
    this.markRecordDeleting(record.id, true);

    try {
      const deleteResult = await todayActivityService.deleteTimeRecord(record.id);
      if (deleteResult) {
        hilog.info(0x0000, TAG, `Activity deleted successfully: ${record.id}`);

        this.getUIContext().animateTo({
          duration: 300,
          curve: curves.springMotion()
        }, () => {
          const removedRecord = this.removeRecordById(record.id);
          if (removedRecord && this.currentEditingRecord?.id === removedRecord.id) {
            this.currentEditingRecord = null;
          }
          this.onAllTimeRecordsChange();
        });

        await this.ensurePausedStatusIfNoActiveRecord();
        await this.refreshGlobalMatterData();

        promptAction.openToast({
          message: '事项已删除',
          duration: 1000
        });
        await this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'notification');
      } else {
        hilog.error(0x0000, TAG, `Failed to delete activity: ${record.id}`);
        promptAction.openToast({
          message: '删除事项失败',
          duration: 1000
        });
        await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Error deleting activity: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '删除事项时发生错误',
        duration: 1000
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    } finally {
      this.markRecordDeleting(record.id, false);
      await this.vibratorUtil.stopAllHaptics();
    }
  }

  /**
   * 分享单条 TimeRecord 到 GoalFighter（single 模式）。
   * 当前记录未结束或不合法时不允许分享。
   */
  private async handleShareRecordToGoalFighter(record: TimeRecord): Promise<void> {
    const item = this.item;
    if (!item) {
      hilog.error(0x0000, TAG, 'share aborted: matter item missing');
      return;
    }
    const envelope = buildFlowDiaryImportEnvelope('single', [record], item.id, item.title,
      generateFlowDiaryImportRequestId());
    if (envelope === null) {
      hilog.info(0x0000, TAG, `record ${record.id} is not shareable yet`);
      promptAction.openToast({
        message: $r('app.string.today_share_record_not_finished'),
        duration: 1000
      }).catch(() => {
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      return;
    }
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      hilog.error(0x0000, TAG, 'share aborted: host context missing');
      return;
    }
    const abilityContext = hostContext as common.UIAbilityContext;
    await goalFighterShareService.share(abilityContext, envelope);
  }

  private refreshGoalFighterAvailability(): void {
    this.isGoalFighterAvailable = goalFighterShareService.isGoalFighterAvailable();
  }

  @Builder
  private renderHeroCard() {
    Column() {
      Row() {
        Column(){
          Text('事项名称')
            .fontSize(12)
            .fontWeight(500)
            .fontColor($r('app.color.text_tertiary'))
            .margin({bottom: 5})
          Text(this.item?.title)
            .fontWeight(600)
            .fontSize(new BreakpointType<number>({ sm: 24, md: 26, lg: 28 }).getValue(this.currentBreakpoint))
            .fontColor($r('app.color.neutral_800'))
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .width('calc(100% - 40vp)')

        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontColor([$r('app.color.text_tertiary')])
            .fontWeight(600)
            .fontSize(18)
        }
        .backgroundColor($r('app.color.bg_page'))
        .onClick(() => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
          this.updateSheetHeight();
          this.syncFormWithCurrentItem();
          this.isActivitySheetShow = true;
        })
        .clickEffect({level: ClickEffectLevel.MIDDLE, scale: 0.8})
        .width(35)
        .height(35)
        .shadow(this.getInteractiveShadow())
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Top)
      .margin({ bottom: new BreakpointType<number>({ sm: 15, md: 20, lg: 24 }).getValue(this.currentBreakpoint) })

      Text('今日累计时间')
        .fontSize(12)
        .fontWeight(500)
        .fontColor($r('app.color.text_tertiary'))
        .margin({bottom: 5})

      Text(this.totalDuration)
        .fontColor(this.item?.labelColor)
        .fontWeight(700)
        .fontSize(new BreakpointType<number>({ sm: 24, md: 26, lg: 28 }).getValue(this.currentBreakpoint))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({bottom: 5})

      Row() {
        LabelItem({
          labelWidth: 10,
          labelName: this.item?.label,
          labelMargin: 5,
          labelColor: this.item?.labelColor
        })
          .margin({right: 10})

        LabelItem({
          labelWidth: 10,
          labelName: `共记录${this.allTimeRecords.length}次`,
          labelMargin: 5,
          labelColor: $r('app.color.primary')
        })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor(this.getHeroCardBackgroundColor())
    .linearGradient({
      direction: GradientDirection.LeftBottom,
      colors: [
        [$r('app.color.matter_card_gradient_start'), 0],
        [$r('app.color.matter_card_gradient_end'), 1],
      ]
    })
    .shadow(this.getInteractiveShadow())
    .padding(new BreakpointType<number | Resource>({ sm: $r('app.float.page_content_padding_horizontal'), md: 16, lg: 18 }).getValue(this.currentBreakpoint))
    .width('100%')
    .margin({bottom: new BreakpointType<number>({ sm: 15, md: 18, lg: 20 }).getValue(this.currentBreakpoint)})
    .borderRadius(15)
    .bindSheet($$this.isActivitySheetShow, this.editItemBuilder(), {
      detents: this.activitySheetDetents,
      preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
      showClose: false,
      dragBar: false,
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
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({x: 200})).animation({ curve: curves.springMotion(), duration: 300 }))
  }

  @Builder
  private renderStatsCards() {
    GridRow({
      breakpoints: { value: BreakpointConstants.BREAKPOINT_VALUE, reference: BreakpointsReference.WindowSize },
      columns: {
        sm: BreakpointConstants.COLUMN_SM,
        md: BreakpointConstants.COLUMN_MD,
        lg: BreakpointConstants.COLUMN_LG
      },
      gutter: { x: BreakpointConstants.GUTTER_X, y: BreakpointConstants.GUTTER_X }
    }) {
      GridCol({
        span: { sm: BreakpointConstants.COLUMN_SM / 2, md: BreakpointConstants.COLUMN_MD / 2, lg: BreakpointConstants.COLUMN_LG / 2 }
      }) {
        MatterDetailCard({title: '最长时段', value: this.longestDuration, valueColor: this.item?.labelColor})
          .shadow(this.getInteractiveShadow())
          .borderRadius(15)
          .height(new BreakpointType<number>({ sm: 80, md: 90, lg: 100 }).getValue(this.currentBreakpoint))
          .width('100%')
      }

      GridCol({
        span: { sm: BreakpointConstants.COLUMN_SM / 2, md: BreakpointConstants.COLUMN_MD / 2, lg: BreakpointConstants.COLUMN_LG / 2 }
      }) {
        MatterDetailCard({title: '平均时长', value: this.averageDuration, valueColor: this.item?.labelColor})
          .shadow(this.getInteractiveShadow())
          .borderRadius(15)
          .height(new BreakpointType<number>({ sm: 80, md: 90, lg: 100 }).getValue(this.currentBreakpoint))
          .width('100%')
      }
    }
    .margin({ bottom: new BreakpointType<number>({ sm: 15, md: 18, lg: 20 }).getValue(this.currentBreakpoint) })
    .width('100%')
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({x: 200})).animation({ curve: curves.springMotion(), duration: 300 }))
  }

  @Builder
  private renderOverviewSection() {
    Column() {
      this.renderHeroCard();
      this.renderStatsCards();
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderRecordsHeader() {
    Row() {
      Row() {
        Text('时间记录')
          .fontSize(18)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
        if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Row() {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontWeight(600)
                .fontSize(14)
                .fontColor([$r('app.color.primary')])

              Text(' 添加')
                .fontWeight(600)
                .fontSize(16)
                .fontColor($r('app.color.primary'))
            }
            .alignItems(VerticalAlign.Center)
          }
          .shadow(this.getRestingShadow())
          .height(35)
          .width(70)
          .backgroundColor($r('app.color.primary_lighter'))
          .onClick(async () => {
            void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            this.isShowNewSheet = true;
            this.initAddSheetState();
          })
          .margin({ left: 12 })
        }
      }
      if (this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_LG) {
        Row() {
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Row() {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontWeight(600)
                .fontSize(14)
                .fontColor([$r('app.color.primary')])

              Text(' 添加')
                .fontWeight(600)
                .fontSize(16)
                .fontColor($r('app.color.primary'))
            }
            .alignItems(VerticalAlign.Center)
          }
          .shadow(this.getRestingShadow())
          .height(35)
          .width(70)
          .backgroundColor($r('app.color.primary_lighter'))
          .onClick(async () => {
            void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            this.isShowNewSheet = true;
            this.initAddSheetState();
          })
        }
      }
    }
    .height(30)
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG ? FlexAlign.Start : FlexAlign.SpaceBetween)
    .padding(this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? {} : { left: 12, right: 12 })
    .margin({bottom: new BreakpointType<number>({ sm: 12, md: 15, lg: 18 }).getValue(this.currentBreakpoint)})
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({x: 200})).animation({ curve: curves.springMotion(), duration: 300 }))
  }

  @Builder
  private renderRecordsSection() {
    Column() {
      this.renderRecordsHeader();

      List() {
        ListItemGroup({ space: 16 }) {
          ForEach(this.allTimeRecords, (record: TimeRecord) => {
            if (record.endTime) {
              ListItem() {
                Row() {
                  Row() {
                    TimeRecordDetailCard({ record: record, itemColor: this.item?.labelColor })
                      .layoutWeight(1)
                    Row() {
                      if (this.isGoalFighterAvailable) {
                        Button({ type: ButtonType.Circle, stateEffect: true }) {
                        SymbolGlyph($r('sys.symbol.share'))
                          .fontColor([$r('app.color.text_tertiary')])
                          .fontWeight(600)
                          .fontSize($r('app.float.today_record_share_icon_size'))
                      }
                      .backgroundColor($r('app.color.bg_page'))
                      .onClick(() => {
                        void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                        void this.handleShareRecordToGoalFighter(record);
                      })
                      .accessibilityText($r('app.string.today_share_to_goalfighter'))
                      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
                      .width($r('app.float.today_record_share_btn_size'))
                      .height($r('app.float.today_record_share_btn_size'))
                      .shadow(this.getRestingShadow())
                      .margin({ right: $r('app.float.today_record_share_btn_margin') })
                      }

                      Button({ type: ButtonType.Circle, stateEffect: true }) {
                        SymbolGlyph($r('sys.symbol.square_and_pencil'))
                          .fontColor([$r('app.color.text_tertiary')])
                          .fontWeight(600)
                          .fontSize(18)
                      }
                      .backgroundColor($r('app.color.bg_page'))
                      .onClick(() => {
                        void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                        this.initEditSheetState(record);
                        this.isShowEditSheet = true;
                      })
                      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
                      .width(35)
                      .height(35)
                      .shadow(this.getRestingShadow())
                      .margin({ right: 10 })

                      Button({ type: ButtonType.Circle, stateEffect: true }) {
                        SymbolGlyph($r('sys.symbol.trash'))
                          .fontColor([$r('app.color.text_tertiary')])
                          .fontWeight(600)
                          .fontSize(18)
                      }
                      .backgroundColor($r('app.color.bg_page'))
                      .onClick(() => {
                        if (this.isRecordDeleting(record.id)) {
                          hilog.warn(0x0000, TAG, `Ignore delete dialog open while deleting record: ${record.id}`);
                          return;
                        }
                        void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                        this.getUIContext().showAlertDialog(
                          {
                            title: '是否确认删除时间记录？',
                            message: '时间记录删除后，累计时间将会更新',
                            autoCancel: true,
                            alignment: DialogAlignment.Center,
                            gridCount: 4,
                            offset: { dx: 0, dy: -20 },
                            primaryButton: {
                              value: '取消',
                              action: () => {
                                void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
                                hilog.info(0x0000, TAG, 'cancel delete item');
                              }
                            },
                            secondaryButton: {
                              enabled: !this.isRecordDeleting(record.id),
                              defaultFocus: true,
                              style: DialogButtonStyle.HIGHLIGHT,
                              value: '确认',
                              action: () => {
                                if (this.isRecordDeleting(record.id)) {
                                  hilog.warn(0x0000, TAG, `Ignore duplicate delete confirm for record: ${record.id}`);
                                  return;
                                }
                                hilog.info(0x0000, TAG, 'delete current item' + JSON.stringify(record));
                                void this.handleDeleteButtonClicked(record);
                              }
                            },
                            cancel: () => {
                              console.info('Closed callbacks');
                            },
                            onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
                              console.info(`reason= ${dismissDialogAction.reason}`);
                              console.info('AlertDialog onWillDismiss');
                              if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
                                dismissDialogAction.dismiss();
                              }
                              if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
                                dismissDialogAction.dismiss();
                              }
                            },
                          }
                        )
                      })
                      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
                      .width(35)
                      .height(35)
                      .shadow(this.getRestingShadow())
                    }
                  }
                  .shadow(this.getRestingShadow())
                  .alignItems(VerticalAlign.Center)
                  .justifyContent(FlexAlign.SpaceBetween)
                  .padding({
                    left: 10,
                    right: 10,
                    top: 5,
                    bottom: 5
                  })
                  .backgroundColor($r('app.color.bg_card'))
                  .borderRadius(15)
                  .height(50)
                  .width('100%')
                }
              }
              .padding(this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? {} : { left: 12, right: 12 })
              .transition(
                TransitionEffect.asymmetric(
                  TransitionEffect.translate({ x: 200})
                    .animation({ curve: curves.springMotion(), duration: 300 }),
                  TransitionEffect.opacity(0.0)
                    .combine(TransitionEffect.translate({ y: 30 }))
                    .animation({ curve: curves.springMotion(), duration: 300 }),
                )
              )
            }
          },
            (item: TimeRecord, index: number) => item.id
          )
        }
        ListItem()
          .padding(this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? {} : { left: 12, right: 12 })
          .height(35)
      }
      .clip(true)
      .width('100%')
      .lanes(this.getListLanes())
      .scrollBar(BarState.Off)
      .enableScrollInteraction(false)
      .animation({curve: curves.springMotion(), duration: 100})
    }
    .width('100%')
    .bindSheet($$this.isShowEditSheet,
      this.editTimeRecordBuilder(this.currentEditingRecord as TimeRecord), {
        height: this.getRecordSheetHeight(),
        showClose: false,
        dragBar: false,
        preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        enableOutsideInteractive: false,
        keyboardAvoidMode: SheetKeyboardAvoidMode.NONE,
        title: this.editTitleBuilder('编辑分段记录'),
        onWillDismiss: (dismissDialogAction: DismissSheetAction) => {
          // if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
          //   dismissDialogAction.dismiss();
          // }
          // if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          //   dismissDialogAction.dismiss();
          // }
          this.isShowEditSheet = false
        }
      })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({x: 200})).animation({ curve: curves.springMotion(), duration: 300 }))
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.isFlowEffectMounted) {
          Column()
            .width('100%')
            .height('100%')
            .visualEffect(buildFlowLightEffect(this.shaderController))
            .expandSafeArea(
              [SafeAreaType.SYSTEM],
              [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
            )
        }

      Scroll() {
        Column() {
          Blank()
            .height($r('app.float.immersive_nav_top_spacer_height'))
            .width('100%')

          GridRow({
            breakpoints: { value: BreakpointConstants.BREAKPOINT_VALUE, reference: BreakpointsReference.WindowSize },
            columns: {
              sm: BreakpointConstants.COLUMN_SM,
              md: BreakpointConstants.COLUMN_MD,
              lg: BreakpointConstants.COLUMN_LG
            },
            gutter: { x: BreakpointConstants.GUTTER_X, y: BreakpointConstants.GUTTER_X },
            direction: GridRowDirection.Row
          }) {
            GridCol({ span: {
              sm: BreakpointConstants.COLUMN_SM,
              md: BreakpointConstants.COLUMN_MD / 2,
              lg: 4
            } }) {
              this.renderOverviewSection();
            }

            GridCol({ span: {
              sm: BreakpointConstants.COLUMN_SM,
              md: BreakpointConstants.COLUMN_MD / 2,
              lg: BreakpointConstants.COLUMN_LG - 4
            } }) {
              this.renderRecordsSection();
            }
          }
          .width('100%')

          Blank()
            .height($r('app.float.immersive_nav_bottom_spacer_height'))
            .width('100%')
        }
        .bindSheet($$this.isShowNewSheet,
          this.addTimeRecordBuilder(), {
            height: this.getRecordSheetHeight(),
            showClose: false,
            dragBar: false,
            preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
            blurStyle: BlurStyle.COMPONENT_REGULAR,
            enableOutsideInteractive: false,
            keyboardAvoidMode: SheetKeyboardAvoidMode.NONE,
            title: this.addTitleBuilder('添加时间记录'),
            onWillDismiss: (dismissDialogAction: DismissSheetAction) => {
              this.isShowNewSheet = false;
              if (dismissDialogAction.reason == DismissReason.PRESS_BACK) {
                dismissDialogAction.dismiss();
              }
              if (dismissDialogAction.reason == DismissReason.TOUCH_OUTSIDE) {
                dismissDialogAction.dismiss();
              }
            }
          })
        .padding(new BreakpointType<number>({ sm: 12, md: 16, lg: 18 }).getValue(this.currentBreakpoint))
        .width('100%')
      }
      .backgroundColor($r('app.color.transparent'))
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM, SafeAreaEdge.TOP])
      }
      .width('100%')
      .height('100%')
    }
    .onReady(async (context: NavDestinationContext) => {
      this.item = MatterItemModel.from(context.pathInfo.param as MatterItemModel);
      this.pageInfos = context.pathStack;
      hilog.info(0x0000, TAG, 'successfully jumped to MatterItemEditPage')
      if (this.item) {
        const duration: number = await todayActivityService.getTodayTotalDuration(this.item?.id);
        this.totalDuration = TimeRecordUtil.formatDuration(duration);
        this.allTimeRecords = await todayActivityService.getTimeRecordsByActivityId(this.item.id)
        this.selectedTag = await todayActivityService.getTagByActivityId(this.item.id);
        // 确保表单状态与当前事项保持同步
        this.syncFormWithCurrentItem();
        // 计算平均时长和最长时长
        this.calculateDurationStats();
      }
    })
    .titleBar({
      content: {
        title: {
          mainTitle: '详情'
        }
      },
      style: {
        scrollEffectOpts: {
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.GENTLE
        }
      }
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .hideBackButton(false)
    .ignoreLayoutSafeArea(
      [LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]
    )
    .expandSafeArea(
      [SafeAreaType.SYSTEM],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
    )
    .backgroundColor($r('app.color.bg_main'))
  }

  private getHeroCardBackgroundColor(): ResourceColor {
    if (this.isDarkTheme) {
      return $r('app.color.matter_card_fill');
    }
    return this.item?.labelColor ?? $r('app.color.matter_card_fill');
  }

  private getInteractiveShadow(): ShadowOptions {
    return this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE;
  }

  private getRestingShadow(): ShadowOptions {
    return this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING;
  }
}
