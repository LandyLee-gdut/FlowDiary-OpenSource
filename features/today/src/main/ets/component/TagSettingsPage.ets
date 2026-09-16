import { curves, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AddNewTagDialog,
  BreakpointConstants,
  ColorUtil,
  DEFAULT_SHEET_HEIGHT,
  TagDialogDependencies,
  TagDialogMode,
  TagItem,
  TagModel,
  VibratorUtil,
  calculateSheetHeight,
  tagService
} from 'base';
import { REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION } from './ReflectChartSettingsMotionTokens';
import { MatterItemModel } from 'base';
import {
  patchMatterListsAfterTagDeletion,
  patchMatterListsAfterTagUpdate,
  resolveSelectedTagIndexAfterDeletion
} from '../utils/TagMutationUiHelper';

const TAG: string = 'TagSettingsPage';
const TAG_ROW_MOTION_DURATION_MS: number = 350;
const TAG_ROW_LIST_MOTION_DURATION_MS: number = 350;
const TAG_ROW_HOST_NOTIFY_DELAY_MS: number = 360;

function tagRowMotionCurve() {
  return curves.springMotion(0.35, 0.8);
}

@Observed
class TagSettingsTagModel {
  id: string;
  name: string;
  color: string;
  lightColor: string;

  constructor(id: string, name: string, color: string, lightColor: string) {
    this.id = id;
    this.name = name;
    this.color = color;
    this.lightColor = lightColor;
  }

  applyFrom(source: TagSettingsTagModel): void {
    this.name = source.name;
    this.color = source.color;
    this.lightColor = source.lightColor;
  }

  static fromTagModel(tag: TagModel): TagSettingsTagModel {
    return new TagSettingsTagModel(tag.id, tag.name, tag.color, tag.lightColor);
  }

  static fromTagItem(tag: TagItem): TagSettingsTagModel {
    return new TagSettingsTagModel(tag.id, tag.name, tag.color, tag.lightColor);
  }
}

@Component
struct TagSettingsListRow {
  @ObjectLink tag: TagSettingsTagModel;
  @Prop index: number = -1;
  onEdit?: (tag: TagSettingsTagModel, index: number) => void;
  onDelete?: (tag: TagSettingsTagModel) => void;

  build() {
    Row() {
      Row({ space: 10 }) {
        Row()
          .width(12)
          .height(12)
          .borderRadius('50%')
          .backgroundColor(ColorUtil.normalizeHexColor(this.tag.color));

        Column() {
          Text(this.tag.name)
            .fontSize(16)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'));
        }
        .alignItems(HorizontalAlign.Start);
      }

      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(18)
            .fontWeight(500)
            .fontColor([$r('app.color.text_secondary')]);
        }
        .padding(10)
        .backgroundColor($r('app.color.bg_main'))
        .onClick(() => {
          this.onEdit?.(this.tag, this.index);
        });

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontWeight(500)
            .fontColor([$r('app.color.text_secondary')]);
        }
        .padding(10)
        .backgroundColor($r('app.color.bg_main'))
        .onClick(() => {
          this.onDelete?.(this.tag);
        });
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 14, bottom: 14 });
  }
}

@CustomDialog
struct TagUpsertDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: TagUpsertDialog({
      isShow: this.isShow,
      inputActivityName: this.inputActivityName,
      selectedTagIndex: this.selectedTagIndex,
      sheetHeight: this.sheetHeight,
      inputTagName: this.inputTagName,
      selectedLabelIndex: this.selectedLabelIndex,
      mode: this.mode,
      editingTagId: this.editingTagId
    }),
    autoCancel: true
  });
  @State showFlag: Visibility = Visibility.Visible;
  @Link inputActivityName: string;
  @Link selectedTagIndex: number;
  @Link sheetHeight: number;
  @Link inputTagName: string;
  @Link selectedLabelIndex: number;
  @Link isShow: boolean;
  @Link mode: TagDialogMode;
  @Link editingTagId: string;
  @StorageLink('tagData') tagData: TagModel[] = [];
  dependencies?: TagDialogDependencies;
  onTagSaved?: (tagId: string, mode: TagDialogMode) => Promise<void> | void;

  private resolveEditingTag(): TagModel | undefined {
    if (!this.editingTagId) {
      return undefined;
    }
    return this.tagData.find((tag: TagModel) => tag.id === this.editingTagId);
  }

  build() {
    AddNewTagDialog({
      controller: this.controller,
      inputActivityName: this.inputActivityName,
      selectedTagIndex: this.selectedTagIndex,
      sheetHeight: this.sheetHeight,
      inputTagName: this.inputTagName,
      selectedLabelIndex: this.selectedLabelIndex,
      isShow: this.isShow,
      showFlag: this.showFlag,
      mode: this.mode,
      editingTag: this.resolveEditingTag(),
      onTagSaved: this.onTagSaved,
      dependencies: this.dependencies
    });
  }

  cancel() {
    this.showFlag = Visibility.Hidden;
    setTimeout(() => {
      this.controller.close();
    }, 400);
  }
}

@Component
export struct TagSettingsPage {
  onBack?: () => void;
  onTagDataChanged?: () => Promise<void> | void;

  @StorageLink('tagData') tagData: TagModel[] = [];
  @StorageLink('matterData') matterData: MatterItemModel[] = [];
  @StorageLink('doneMatterData') doneMatterData: MatterItemModel[] = [];
  @StorageLink('unDoMatterData') unDoMatterData: MatterItemModel[] = [];
  @StorageLink('matterDataRevision') matterDataRevision: number = 0;
  @StorageLink('isCustomDialogShow') isCustomDialogShow: boolean = false;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  @State private dialogVisible: boolean = false;
  @State private inputActivityName: string = '';
  @State private selectedTagIndex: number = -1;
  @State private sheetHeight: number = DEFAULT_SHEET_HEIGHT;
  @State private inputTagName: string = '';
  @State private selectedLabelIndex: number = -1;
  @State private dialogMode: TagDialogMode = 'create';
  @State private editingTagId: string = '';
  @State private editingTagNameSnapshot: string = '';
  @State private displayTags: TagSettingsTagModel[] = [];
  @State private animatedDisplayTags: TagSettingsTagModel[] = [];
  private pageInfos: NavPathStack = new NavPathStack();
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private readonly dialogDeps: TagDialogDependencies = {
    refreshTags: async (): Promise<TagModel[]> => this.tagData
  };

  private tagDialogController: CustomDialogController | null = new CustomDialogController({
    builder: TagUpsertDialog({
      isShow: this.dialogVisible,
      inputActivityName: this.inputActivityName,
      selectedTagIndex: this.selectedTagIndex,
      sheetHeight: this.sheetHeight,
      inputTagName: this.inputTagName,
      selectedLabelIndex: this.selectedLabelIndex,
      mode: this.dialogMode,
      editingTagId: this.editingTagId,
      dependencies: this.dialogDeps,
      onTagSaved: async (tagId: string, mode: TagDialogMode): Promise<void> => {
        await this.handleTagSaved(tagId, mode);
      }
    }),
    alignment: DialogAlignment.Center,
    maskColor: '#80000000',
    backgroundBlurStyle: BlurStyle.Thick,
    backgroundColor: $r('app.color.primary_lighter'),
    autoCancel: true,
    customStyle: true,
    onWillAppear: () => {
      this.isCustomDialogShow = true;
    },
    onWillDisappear: () => {
      this.isCustomDialogShow = false;
      this.dialogVisible = false;
    },
    onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
      if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
        dismissDialogAction.dismiss();
      }
      if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
        dismissDialogAction.dismiss();
      }
      this.dialogVisible = false;
    },
    keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
    offset: { dx: 0, dy: 0 }
  });

  aboutToAppear(): void {
    hilog.info(0x0000, TAG, '[TagSettingsPage] aboutToAppear');
    void this.reloadTagDataLocal();
  }

  aboutToDisappear(): void {
    this.dialogVisible = false;
    this.resetDialogState();
  }

  private resetDialogState(): void {
    this.inputTagName = '';
    this.selectedLabelIndex = -1;
    this.editingTagId = '';
    this.editingTagNameSnapshot = '';
    this.selectedTagIndex = -1;
    this.dialogMode = 'create';
  }

  private updateSheetHeight(): void {
    const tagCount = this.displayTags ? this.displayTags.length : 0;
    this.sheetHeight = calculateSheetHeight(tagCount, this.currentBreakpoint);
  }

  private async reloadTagDataLocal(): Promise<void> {
    const tags: TagModel[] = await tagService.getAllTagsForUI();
    const nextDisplayTags: TagSettingsTagModel[] = [];
    for (const tag of tags) {
      nextDisplayTags.push(TagSettingsTagModel.fromTagModel(tag));
    }
    this.displayTags.splice(0, this.displayTags.length, ...nextDisplayTags);
    this.syncAnimatedTagList(false);
    this.tagData.splice(0, this.tagData.length, ...tags);
    AppStorage.setOrCreate('tagData', [...this.tagData]);
    hilog.info(0x0000, TAG, `[TagSettingsPage] reload local tags, size=${this.displayTags.length}`);
    this.updateSheetHeight();
  }

  private async syncStorageTagDataFromDatabase(): Promise<void> {
    const tags: TagModel[] = await tagService.getAllTagsForUI();
    this.tagData.splice(0, this.tagData.length, ...tags);
    AppStorage.setOrCreate('tagData', [...this.tagData]);
  }

  private applyTagUpsertLocally(tagModel: TagSettingsTagModel, mode: TagDialogMode): void {
    if (mode === 'create') {
      this.displayTags.push(tagModel);
      this.selectedTagIndex = this.displayTags.length - 1;
      this.updateSheetHeight();
      this.syncAnimatedTagList(false);
      return;
    }

    const targetIndex = this.displayTags.findIndex((item: TagSettingsTagModel) => item.id === tagModel.id);
    if (targetIndex < 0) {
      this.displayTags.push(tagModel);
      this.selectedTagIndex = this.displayTags.length - 1;
      this.updateSheetHeight();
      this.syncAnimatedTagList(false);
      return;
    }

    this.displayTags[targetIndex].applyFrom(tagModel);
    this.selectedTagIndex = targetIndex;
    this.syncAnimatedTagList(false);
  }

  private removeTagLocallyById(tagId: string): void {
    const removeIndex = this.displayTags.findIndex((item: TagSettingsTagModel) => item.id === tagId);
    if (removeIndex < 0) {
      return;
    }

    this.displayTags.splice(removeIndex, 1);
    this.selectedTagIndex = resolveSelectedTagIndexAfterDeletion(this.selectedTagIndex, removeIndex);
    this.updateSheetHeight();
    this.syncAnimatedTagList(false);
  }

  private syncAnimatedTagList(animate: boolean = true): void {
    const assign = () => {
      this.animatedDisplayTags.splice(0, this.animatedDisplayTags.length, ...this.displayTags);
    };
    if (animate) {
      this.getUIContext().animateTo({
        duration: TAG_ROW_MOTION_DURATION_MS,
        curve: tagRowMotionCurve()
      }, assign);
      return;
    }
    assign();
  }

  private async notifyHostTagChanged(delay: number = 0): Promise<void> {
    if (delay > 0) {
      setTimeout(() => {
        void this.notifyHostTagChanged(0);
      }, delay);
      return;
    }
    if (!this.onTagDataChanged) {
      return;
    }
    try {
      await this.onTagDataChanged();
    } catch (error) {
      hilog.error(0x0000, TAG, `[TagSettingsPage] notifyHostTagChanged failed: ${JSON.stringify(error)}`);
    }
  }

  private publishMatterMutationToGlobalState(source: string): void {
    const nextMatterData: MatterItemModel[] = [...MatterItemModel.ensureList(this.matterData)];
    const nextDoneMatterData: MatterItemModel[] = [...MatterItemModel.ensureList(this.doneMatterData)];
    const nextUnDoMatterData: MatterItemModel[] = [...MatterItemModel.ensureList(this.unDoMatterData)];

    this.matterData = nextMatterData;
    this.doneMatterData = nextDoneMatterData;
    this.unDoMatterData = nextUnDoMatterData;

    AppStorage.set('matterData', nextMatterData);
    AppStorage.set('doneMatterData', nextDoneMatterData);
    AppStorage.set('unDoMatterData', nextUnDoMatterData);

    const nextRevision: number = this.matterDataRevision + 1;
    this.matterDataRevision = nextRevision;
    AppStorage.set('matterDataRevision', nextRevision);
    hilog.info(0x0000, TAG, `[TagSettingsPage] publish matter mutation to global state, source=${source}, revision=${nextRevision}`);
  }

  private async handleTagSaved(tagId: string, mode: TagDialogMode): Promise<void> {
    const editingTagIdSnapshot: string = this.editingTagId;
    const editingTagNameSnapshot: string = this.editingTagNameSnapshot;
    const updatedTagItem = await tagService.getTagById(tagId);
    if (updatedTagItem) {
      const updatedTag = TagSettingsTagModel.fromTagItem(updatedTagItem);
      if (mode === 'create') {
        this.getUIContext().animateTo({
          duration: TAG_ROW_MOTION_DURATION_MS,
          curve: tagRowMotionCurve()
        }, () => {
          this.applyTagUpsertLocally(updatedTag, mode);
        });
      } else {
        this.applyTagUpsertLocally(updatedTag, mode);
      }
      await this.syncStorageTagDataFromDatabase();
      if (mode === 'edit' && editingTagIdSnapshot && editingTagNameSnapshot) {
        const patchResult = patchMatterListsAfterTagUpdate({
          doneMatterData: this.doneMatterData,
          unDoMatterData: this.unDoMatterData,
          matterData: this.matterData,
          matterDataRevision: this.matterDataRevision
        }, editingTagNameSnapshot, updatedTag.name, ColorUtil.normalizeHexColor(updatedTag.color));
        this.doneMatterData = patchResult.doneMatterData;
        this.unDoMatterData = patchResult.unDoMatterData;
        this.matterData = patchResult.matterData;
        if (patchResult.mutated) {
          hilog.info(0x0000, TAG,
            `[TagSettingsPage] patched matter labels after update, old=${editingTagNameSnapshot}, new=${updatedTag.name}`);
          this.publishMatterMutationToGlobalState('edit');
        }
      }
    } else {
      await this.reloadTagDataLocal();
    }
    this.dialogVisible = false;
    this.resetDialogState();
    promptAction.openToast({
      message: mode === 'create' ? $r('app.string.tag_settings_create_success') : $r('app.string.tag_settings_update_success'),
      duration: 1000
    }).catch(() => {
      hilog.error(0x0000, TAG, `Failed to show save toast, tagId=${tagId}, mode=${mode}`);
    });
    void this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
    void this.notifyHostTagChanged();
  }

  private openCreateDialog(): void {
    this.dialogMode = 'create';
    this.editingTagId = '';
    this.inputTagName = '';
    this.selectedLabelIndex = -1;
    this.dialogVisible = true;
    this.tagDialogController?.open();
  }

  private openEditDialog(tag: TagSettingsTagModel, index: number): void {
    this.dialogMode = 'edit';
    this.editingTagId = tag.id;
    this.editingTagNameSnapshot = tag.name;
    this.inputTagName = tag.name;
    this.selectedTagIndex = index;
    this.selectedLabelIndex = -1;
    this.dialogVisible = true;
    this.tagDialogController?.open();
  }

  private confirmDeleteTag(tag: TagSettingsTagModel): void {
    hilog.info(0x0000, TAG, `[TagSettingsPage] confirm delete dialog open, id=${tag.id}`);
    this.getUIContext().showAlertDialog({
      title: '是否确认删除标签？',
      message: `删除后将移除标签 "${tag.name}"，相关事项会标记为无标签`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      gridCount: 4,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        enabled: true,
        defaultFocus: true,
        style: DialogButtonStyle.HIGHLIGHT,
        value: '确认',
        action: () => {
          void this.handleDeleteTag(tag);
        }
      },
      onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
        if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
          dismissDialogAction.dismiss();
        }
        if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissDialogAction.dismiss();
        }
      }
    });
  }

  private async handleDeleteTag(tag: TagSettingsTagModel): Promise<void> {
    hilog.info(0x0000, TAG, `[TagSettingsPage] delete requested, id=${tag.id}, name=${tag.name}`);
    try {
      const deleted = await tagService.deleteTag(tag.id);
      if (!deleted) {
        hilog.warn(0x0000, TAG, `[TagSettingsPage] delete failed, id=${tag.id}`);
        promptAction.openToast({
          message: $r('app.string.tag_settings_delete_failed'),
          duration: 1000
        }).catch(() => {
        });
        void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
        return;
      }

      const patchResult = patchMatterListsAfterTagDeletion({
        doneMatterData: this.doneMatterData,
        unDoMatterData: this.unDoMatterData,
        matterData: this.matterData,
        matterDataRevision: this.matterDataRevision
      }, tag.name, $r('app.color.text_tertiary'));
      this.doneMatterData = patchResult.doneMatterData;
      this.unDoMatterData = patchResult.unDoMatterData;
      this.matterData = patchResult.matterData;
      if (patchResult.mutated) {
        hilog.info(0x0000, TAG, `[TagSettingsPage] patched matter labels after delete, tag=${tag.name}`);
        this.publishMatterMutationToGlobalState('delete');
      }
      const targetId: string = tag.id;
      this.getUIContext().animateTo({
        duration: TAG_ROW_MOTION_DURATION_MS,
        curve: tagRowMotionCurve()
      }, () => {
        this.removeTagLocallyById(targetId);
      });
      await this.syncStorageTagDataFromDatabase();
      hilog.info(0x0000, TAG, `[TagSettingsPage] delete success, id=${tag.id}`);
      promptAction.openToast({
        message: $r('app.string.tag_settings_delete_success'),
        duration: 1000
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
      void this.notifyHostTagChanged(TAG_ROW_HOST_NOTIFY_DELAY_MS);
    } catch (error) {
      hilog.error(0x0000, TAG, `Delete tag failed: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: $r('app.string.tag_settings_delete_error'),
        duration: 1000
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    }
  }

  private handleCloseClick(): void {
    if (this.onBack) {
      this.onBack();
      return;
    }
    this.pageInfos.pop(1);
  }

  build() {
    NavDestination() {
      Column({ space: 14 }) {
        Row() {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.arrow_left'))
              .fontSize(18)
              .fontWeight(500)
              .fontColor([$r('app.color.text_primary')]);
          }
          .onClick(() => {
            void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            this.handleCloseClick();
          })
          .margin({ right: 10 })
          .padding(10)
          .backgroundColor($r('app.color.neutral_100'))
          .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR);

          Text($r('app.string.tag_settings_title'))
            .fontWeight(700)
            .fontSize(26)
            .fontColor($r('app.color.text_primary'));
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .padding({ top: 16, bottom: 16 });

        if (this.animatedDisplayTags.length === 0) {
          Column({ space: 8 }) {
            Text($r('app.string.tag_settings_empty_title'))
              .fontSize(18)
              .fontWeight(600)
              .fontColor($r('app.color.text_primary'));

            Text($r('app.string.tag_settings_empty_desc'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'));
          }
          .width('100%')
          .padding({ top: 36, bottom: 36 })
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(16)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center);
        } else {
          List() {
            ListItemGroup({ space: 10 }) {
              ForEach(this.animatedDisplayTags, (tag: TagSettingsTagModel, index: number) => {
                ListItem() {
                  TagSettingsListRow({
                    tag: tag,
                    index: index,
                    onEdit: (targetTag: TagSettingsTagModel, targetIndex: number) => {
                      void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                      this.openEditDialog(targetTag, targetIndex);
                    },
                    onDelete: (targetTag: TagSettingsTagModel) => {
                      void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                      this.confirmDeleteTag(targetTag);
                    }
                  })
                }
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(16)
                .transition(
                  TransitionEffect.asymmetric(
                    TransitionEffect.translate({ y: 30 })
                      .animation({ curve: tagRowMotionCurve(), duration: TAG_ROW_MOTION_DURATION_MS }),
                    TransitionEffect.opacity(0)
                      .combine(TransitionEffect.translate({ y: 20 }))
                      .animation({ curve: tagRowMotionCurve(), duration: TAG_ROW_MOTION_DURATION_MS })
                  )
                );
              }, (tag: TagSettingsTagModel) => tag.id);
            }
          }
          .clip(true)
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .animation({ curve: tagRowMotionCurve(), duration: TAG_ROW_LIST_MOTION_DURATION_MS });
        }

        Button({ type: ButtonType.Capsule }) {
          Text($r('app.string.tag_settings_add_button'))
            .fontColor($r('app.color.primary_dark'))
            .fontWeight(700);
        }
        .onClick(() => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
          this.openCreateDialog();
        })
        .backgroundColor($r('app.color.primary_lighter'))
        .border({ width: 2, color: $r('app.color.primary_light') })
        .width('100%')
        .height(44)
        .borderRadius(12)
        .margin({ top: 4, bottom: 12 });
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 14, bottom: 15 })
      .backgroundColor($r('app.color.bg_main'));
    }
    .onReady((context: NavDestinationContext) => {
      hilog.info(0x0000, TAG, '[TagSettingsPage] NavDestination ready');
      this.pageInfos = context.pathStack;
    })
    .onBackPressed((): boolean => {
      this.handleCloseClick();
      return true;
    })
    .hideTitleBar(true)
    .systemTransition(REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'));
  }
}
