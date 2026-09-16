import { curves, LengthMetrics, OverlayManager, ComponentContent, promptAction, SymbolGlyphModifier, window } from '@kit.ArkUI';
import { Context, ConfigurationConstant, abilityAccessCtrl, bundleManager, Permissions, common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';

import {
  AppShadows,
  BackupErrorCode,
  BackupResult,
  buildBackupZipFileName,
  clearAutoBackupDir,
  createAutoBackup,
  DEFAULT_SHEET_HEIGHT,
  EmojiItem,
  EmojiUtil,
  ensureAutoBackupDir,
  getAutoBackupDirState,
  importAndRestore,
  createManualBackup,
  validateBackupZip,
  PreferenceKeys,
  PreferencesUtil,
  preferencesUtil,
  RDBStoreUtil,
  VibratorUtil,
  TagModel,
  calculateSheetHeight,
  ColorModeUtil,
  COLOR_MODE_STORAGE_KEY,
  calendarSyncService,
  tagColorPreferenceService,
  ItemFormSheetConfig,
  ItemFormSheetPresets,
  buildSheetTitleBar,
  ItemFormContent,
  holdingHandService,
  reflectChartPreferenceService,
  buildPointLightEffect,
  buildFlowDiaryImportEnvelope,
  generateFlowDiaryImportRequestId,
  goalFighterShareService,
} from 'base';
import { AddNewBall } from '../component/AddNewBall';
import { TodayDataPanel } from '../component/TodayDataPanel';
import {
  MatterItemCard,
  MatterItemExpandAnimationProperties,
  MatterItemExpandPage,
  getMatterItemCardKey,
  getMatterItemNode,
  refreshAllMatterItemNodes
} from '../component/MatterItemTransition';
import { MatterItemModel } from 'base';
import { MatterStatus, BreakpointConstants, BreakpointSystem, BreakpointType } from 'base';
import { addMatterToList, buildPinnedDoneMatterList, removeMatterFromList } from '../model/TodayModel';
import { addNewItemDialog } from '../component/AddNewItemDialog'
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { todayActivityService } from '../model/TodayActivityService';
import { tagService } from 'base';
import { MatterItemStateManager } from '../utils/MatterItemStateManager';
import { recordingSessionStore } from 'base';
import { patchMatterListsAfterTagDeletion, resolveSelectedTagIndexAfterDeletion } from '../utils/TagMutationUiHelper';
import { JSON } from '@kit.ArkTS';
import { hdsEffect, hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { HdsNavigation, HdsListItemCardAttribute, HdsNavDestinationAttribute, HdsNavigationTitleMode, HdsNavigationMenuItemOptions, HdsNavigationAttribute,
  ScrollEffectType } from '@hms.hds.hdsBaseComponent'
import { FanActionKind, FanOverlayParams, FanItem, FanItemVO, toFanItemVOs, Point, DEFAULT_START_ANGLE, DEFAULT_SWEEP_ANGLE, buildFanOverlay, computeFanLayout, computeActiveFanSectorIndex, computeFanItemViewPositions, computeLegacyFanLayout, computeLegacyRenderOffsets, FAN_ITEM_ACTIVE_VIEW_SIZE } from '../model/OverLayModel';
import { liveViewController } from '../liveView/LiveViewManger';
import { fanItemService } from '../model/FanItemService';
import { VoiceInputController, VoiceInputNotice, VoiceInputState } from '../model/VoiceInputController';
import { VoiceInputOverlayParams, buildVoiceInputOverlay } from '../component/VoiceInputBar';
import { thirdPaymentService } from '@kit.PaymentKit';
import { LabelItem } from '../component/LabelItem';
import { TodaySettingsSheetContent } from '../component/TodaySettingsSheetContent';
import {
  AUTO_STOP_ENABLED_DEFAULT,
  AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT,
  clampAutoStopLimitHalfHours,
  hydrateAutoStopSettings,
  syncAutoStopUserSettingsToAppStorage
} from '../model/AutoStopSettings';

const TAG = 'Today';
const BACKUP_PROGRESS_INTERVAL_MS: number = 1200;
const BACKUP_OPERATION_EXPORT: string = 'export';
const BACKUP_OPERATION_IMPORT: string = 'import';
const BACKUP_OPERATION_RESTORE_AUTO: string = 'restore_auto';
const BACKUP_OPERATION_AUTO: string = 'auto_backup';
const CALENDAR_SYNC_APP_STORAGE_KEY: string = 'calendarSyncEnabled';
const CALENDAR_SYNC_RECOVERY_COOLDOWN_MS: number = 3 * 60 * 1000;
const CALENDAR_SYNC_REBUILD_BATCH_SIZE: number = 200;
const CALENDAR_SYNC_RECENT_DAYS: number = 7;
const CALENDAR_SYNC_DAY_MS: number = 24 * 60 * 60 * 1000;
const CALENDAR_SYNC_PERMISSION_READ: Permissions = 'ohos.permission.READ_CALENDAR';
const CALENDAR_SYNC_PERMISSION_WRITE: Permissions = 'ohos.permission.WRITE_CALENDAR';
const MINI_BAR_DIRECT_RECORD_ITEM_ID_KEY: string = 'miniBarDirectRecordItemId';
const FLOATING_TAB_BAR_BOTTOM_SPACER_HEIGHT: number = 90;
const MAX_QUICK_FAN_ITEMS: number = 4;
const VOICE_INPUT_FAN_ITEM_ID: number = -126;
// 滑到语音项后需要停留确认的时长，避免连续左右滑动时误触发监听
const VOICE_START_DWELL_MS: number = 100;
// 语音条出场动画时长 250ms，延迟 300ms 再真正卸载 overlay，保证出场动画完整播放
const VOICE_OVERLAY_EXIT_MS: number = 300;
// 扇形 item 退场动画：全部 item 同时中心缩小 100ms（无阶梯延迟），播完再卸载 overlay，避免阻挡快速连点
const FAN_EXIT_ANIMATION_MS: number = 100;
const FAN_EXIT_EXTRA_MS: number = 60;
// 跨组置顶（undo -> done）：卡片插入 done 时的淡入转场时长与状态清理延迟
const PIN_ENTRANCE_FADE_MS: number = 200;
const PIN_ENTRANCE_CLEANUP_MS: number = 250;

interface SyncMatterStorageOptions {
  updateMatterData?: boolean;
  updateDoneMatterData?: boolean;
  updateUnDoMatterData?: boolean;
}

interface WidgetAddSheetPrefillPayload {
  activityName: string;
  tagId: string;
  autoStart: boolean;
}

interface GeneratedTypeLiteralInterface_1 {
  start: number;
  sweep: number;
}

enum FanPlacement {
  Center,
  Left,
  Right
}

interface FanOverlayLayoutConfig {
  placement: FanPlacement;
  start: number;
  sweep: number;
  layoutPoints: Point[];
  itemOffsets: Point[];
  stackAlignment: Alignment;
  itemMarginBottom: number;
  reverseSectorOrder: boolean;
}

interface AppInfoLike {
  versionName?: string;
}

interface BundleInfoLike {
  versionName?: string;
  appInfo?: AppInfoLike;
}

type PickerResult = string | string[];


@Component
export struct Today {
  @StorageLink('showUserGuide') showUserGuide: boolean = false;
  @Consume('pageInfos') pageInfos: NavPathStack;
  @State @Watch('onMainVisibilityGateChanged') isShow: boolean = false;
  @State private addMatterSheetDetents: [Length | SheetSize, (Length | SheetSize)?, (Length | SheetSize)?] =
    [SheetSize.MEDIUM, SheetSize.LARGE];
  @State sheetHeight: number = DEFAULT_SHEET_HEIGHT;
  @State inputTagName: string = ''
  @State inputActivityName: string = '';
  @State selectedTagIndex: number = -1;
  @State selectedLabelIndex: number = -1;
  @State emojis: EmojiItem[] = EmojiUtil.getAll();
  @State viewportHeight: number = 0;
  @State viewportWidth: number = 0;
  @State viewportWidthPx: number = 0;
  // 添加事项Sheet状态
  @State selectedEmojiChar: string = '';
  // 添加事项Sheet配置
  private addMatterSheetConfig: ItemFormSheetConfig = ItemFormSheetPresets.createAddMatterConfig();
  @State isKeyBoardHidden: boolean = false;
  @State isEditingTag: boolean = false;
  @State tagShakeAngle: number = 0;
  @State isToggleOn: boolean = false;
  @State directStartEnabled: boolean = false;
  // 在组件中定义一个状态变量来存储软键盘高度
  @State keyboardHeight: number = 0;
  @State refreshing: boolean = false;
  @State refreshOffset: number = 0;
  @State refreshState: RefreshStatus = RefreshStatus.Inactive;
  @State isLoading: boolean = false;
  @State isAutoCancel: boolean = true;
  @State controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State positionX: number = 0;
  @State positionY: number = 0;
  @State lastPosX: number = 0;
  @State lastPosY: number = 0;
  @State swipeEditButtonPressed: boolean = false;
  @State swipeDeleteButtonPressed: boolean = false;
  @State swipeShareButtonPressed: boolean = false;
  @State private isGoalFighterAvailable: boolean = false;
  @State @Watch('onMainVisibilityGateChanged') isSettingsPanelShow: boolean = false;
  @State private isSettingsSubPageActive: boolean = false;
  private longPressActive: boolean = false
  private lastLongPressAt: number = 0  // ms 时间戳
  private readonly LONG_PRESS_MS = 400
  private readonly TAP_GUARD_MS = 200  // 长按收尾后这段时间内禁止触发 tap
  private panOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.All});
  private pendingSwissKnifeIndex: number = -1; // 保存当前 Hover 的选中项，用于 Pan 结束时读取
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  // 这个后期可以用用户首选项或者KV数据库来存储
  @StorageLink('newTagColor') newTagColor: string[] = [];
  @StorageLink("showPanel") showPanel: boolean = true;
  @StorageLink('matterData') matterData: MatterItemModel[] = [];
  @StorageLink('currentTime') currentTime: number = 0;
  @StorageLink('tagData') tagData: TagModel[] = [];
  @StorageLink('doneMatterData') @Watch('onDoneMatterDataChange') doneMatterData: MatterItemModel[] = []
  @StorageLink('unDoMatterData') @Watch('onUnDoMatterDataChange') unDoMatterData: MatterItemModel[] = []
  @StorageLink('isCustomDialogShow') isCustomDialogShow: boolean = false;
  @StorageLink('matterDataRevision') @Watch('onMatterDataRevisionChange') matterDataRevision: number = 0;
  @StorageLink('swissKnifeActiveIndex') swissKnifeActiveIndex: number = -1;
  @StorageLink('fanItems') swissKnifeItems: FanItemVO[] = [];
  @State animatedDoneMatterData: MatterItemModel[] = [];
  @State animatedUnDoMatterData: MatterItemModel[] = [];
  @State private pinningMatterId: string = '';
  @State private isPinningMatterCollapsed: boolean = false;
  @State private isMatterPinTransitionActive: boolean = false;
  // 跨组置顶（undo -> done）：done 分组顶部常驻 pin slot 承载高度动画，避免对新挂载节点做属性动画
  @State private pinSlotExpanded: boolean = false;
  @State private pinSlotWithSpacing: boolean = false;
  @State private pinEntranceItemId: string = '';
  @State defaultLinePanelEnabled: boolean = false;
  // 展开动画属性 - 用于 MatterItem 长按展开效果
  @State matterExpandAnimationProps: MatterItemExpandAnimationProperties | null = null;
  @StorageLink('isDarkTheme') @Watch('onThemeChanged') isDarkTheme: boolean = false;
  @StorageLink('useFloatingActionBar') useFloatingActionBar: boolean = false;
  @StorageLink('ideapoolUnlitFirst') ideapoolUnlitFirst: boolean = true;
  @StorageLink('ideapoolDirectRecord') ideapoolDirectRecord: boolean = false;
  @StorageLink('activeMainTabIndex') @Watch('onMainVisibilityGateChanged') activeMainTabIndex: number = 1;
  @StorageLink('userGuideSheetVisible') @Watch('onMainVisibilityGateChanged') userGuideSheetVisible: boolean = false;
  @StorageLink('todayPageVisible') todayPageVisible: boolean = false;
  @StorageProp('calendarSyncEnabled') calendarSyncEnabled: boolean = false;
  @StorageProp('autoStopEnabled') autoStopEnabled: boolean = AUTO_STOP_ENABLED_DEFAULT;
  @StorageProp('autoStopLimitHalfHours') autoStopLimitHalfHours: number = AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @StorageLink('autoBackupEnabled') autoBackupEnabled: boolean = false;
  @StorageLink('autoBackupLastRunAt') autoBackupLastRunAt: number = 0;
  @StorageLink('autoBackupLastErrorCode') autoBackupLastErrorCode: number = 0;
  @StorageLink('holdingHandEnabled') holdingHandEnabled: boolean = false;
  @StorageLink('holdingHandOffsetPercent') holdingHandOffsetPercent: number = 0;
  @StorageLink('holdingHandStatus') @Watch('onHoldingHandStatusChange')
  holdingHandStatus: number = motion.HoldingHandStatus.UNKNOWN_STATUS;
  @State private backupBusy: boolean = false;
  @State private activeBackupOperation: string = '';
  @State private backupProgressText: string = '';
  @State private calendarSyncPermissionGranted: boolean = true;
  // 监听卡片触发的打开添加 sheet 标记（热启动场景）
  @StorageLink('openAddSheetFromWidget') @Watch('onOpenAddSheetFromWidgetChange') openAddSheetFromWidget: boolean = false;
  @StorageLink(MINI_BAR_DIRECT_RECORD_ITEM_ID_KEY) @Watch('onMiniBarDirectRecordItemIdChange')
  miniBarDirectRecordItemId: number = -1;
  @StorageLink('widgetAddSheetPrefillJson') widgetAddSheetPrefillJson: string = '';
  @State @Watch('changeColorMode') tabSelectedIndexes: number[] = [0]
  private uiContext: UIContext = this.getUIContext();
  private overlayNode: OverlayManager = this.uiContext.getOverlayManager();
  private content: ComponentContent<FanOverlayParams> | undefined = undefined;
  private fanOverlayParams: FanOverlayParams | null = null;
  private voiceOverlayContent: ComponentContent<VoiceInputOverlayParams> | undefined = undefined;
  private readonly fanRadius: number = 153;
  private readonly fanInnerRadius: number = 48;
  private readonly fanOuterRadius: number = 220;
  private readonly addNewBallSize: number = 55;
  private readonly preferencesUtil: PreferencesUtil = preferencesUtil;
  // SwissKnife overlay 的配置信息，用于 PanGesture 中计算选中索引
  private swissKnifeCenter: Point | null = null;
  private swissKnifeLayoutPoints: Point[] = [];
  // 当前扇形 overlay 最高 item 的顶边 Y 坐标（vp），用于把语音输入条定位到其上方
  private fanItemsTopY: number | null = null;
  private activeFanMenuItems: FanItemVO[] = [];
  private activeFanStartAngle: number = DEFAULT_START_ANGLE;
  private activeFanSweepAngle: number = DEFAULT_SWEEP_ANGLE;
  private activeFanReverseSectorOrder: boolean = false;
  private holdingHandActive: boolean = false;
  private lastHoldingHandAlign: FlexAlign = FlexAlign.Center;
  private voiceInputState: VoiceInputState = VoiceInputState.IDLE;
  private voiceInterimText: string = '';
  private voiceStartTimer: number | null = null;
  private voiceOverlayRemovalTimer: number | null = null;
  private readonly voiceInputController: VoiceInputController = new VoiceInputController({
    onStateChanged: (state: VoiceInputState): void => {
      this.voiceInputState = state;
      this.syncVoiceInputOverlay();
    },
    onInterimText: (text: string): void => {
      this.voiceInterimText = text;
      this.syncVoiceInputOverlay();
    },
    onFinalText: (text: string): void => {
      this.voiceInterimText = '';
      this.applyVoiceInputPrefill(text);
    },
    onNotice: (notice: VoiceInputNotice): void => {
      this.showVoiceInputNotice(notice);
    }
  });

  private readonly tagShakeAmplitude: number = 4;
  private readonly tagShakeFrameDuration: number = 90;
  private isTagShakeRunning: boolean = false;
  private pendingRevisionSync: boolean = false;
  private matterListProjectionReady: boolean = false;
  private matterListSyncTimer: number = -1;
  private matterPinAnimationToken: number = 0;
  private pendingMatterListSync: boolean = false;
  private activeItemEndId: string | null = null;
  private calendarSyncToggleUpdating: boolean = false;
  private calendarSyncRecoveryRunning: boolean = false;
  private lastCalendarSyncRecoveryAt: number = 0;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private backupProgressTimer: number | null = null;

  private listScroller: ListScroller = new ListScroller();
  private pageLifecycleVisible: boolean = false;
  @State menuItems: Array<NavigationMenuItem> = [
    {
      value: 'settings',
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape')),
    },
  ];
  @State ballVisible: Visibility = Visibility.Visible
  private effect: TransitionEffect = TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.6, 0.8), duration: 300 }).combine(TransitionEffect.translate({ x: 0, y: 100 }))// 添加旋转转场效果，这里的动画参数会跟随上面带animation的TransitionEffect，也就是springMotion(0.6, 0.8)
  private matterListItemTransition: TransitionEffect = TransitionEffect.opacity(0.0)
    .combine(TransitionEffect.translate({ y: 30 }))
    .animation({ curve: curves.springMotion(0.35, 0.9) });

  // 跨组置顶时卡片插入 done 的淡入转场：镜像原展开阶段的 opacity/scale 视觉
  private pinEntranceTransition: TransitionEffect = TransitionEffect.opacity(0.0)
    .combine(TransitionEffect.scale({ x: 0.85, y: 0.85 }))
    .animation({ duration: PIN_ENTRANCE_FADE_MS, curve: curves.springMotion(0.5, 0.7) });

  private addNewItemDialogController: CustomDialogController | null = new CustomDialogController({
    builder: addNewItemDialog({isShow: this.isShow, inputActivityName: this.inputActivityName, selectedTagIndex: this.selectedTagIndex, sheetHeight: this.sheetHeight, inputTagName: this.inputTagName, selectedLabelIndex: this.selectedLabelIndex}),
    alignment: DialogAlignment.Center,
    maskColor: '#80000000',
    backgroundBlurStyle: BlurStyle.Thick,
    backgroundColor: $r('app.color.primary_lighter'),
    autoCancel: this.isAutoCancel,
    customStyle: true,
    onWillDismiss:(dismissDialogAction: DismissDialogAction)=> {
      console.info(`reason= ${dismissDialogAction.reason}`);
      if (dismissDialogAction.reason == DismissReason.PRESS_BACK) {
        dismissDialogAction.dismiss();
      }
      if (dismissDialogAction.reason == DismissReason.TOUCH_OUTSIDE) {
        dismissDialogAction.dismiss();
      }
    },
    onWillAppear: () => {
      this.isCustomDialogShow = true;
    },
    onWillDisappear: () => {
      this.isCustomDialogShow = false;
    },
    keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
    offset: { dx: 0, dy: 0 } }
  )


  @Builder
  titleBuilder() {
    buildSheetTitleBar({
      title: this.addMatterSheetConfig.titleBar.title,
      actionButtonText: this.addMatterSheetConfig.titleBar.actionButtonText,
      onClose: () => {
        if (this.isEditingTag) {
          this.updateTagEditingState(false);
        }
        this.isShow = false;
        this.resetFormState();
      },
      onSubmit: async () => {
        if (this.inputActivityName.length <= 0) {
          promptAction.openToast({
            duration: 1000,
            message: '请完整填写事项信息'
          }).catch(() => {
            hilog.error(0x0000, TAG, 'error in filling item info')
          })
          return
        }
        const selectedTagId = this.selectedTagIndex >= 0 ? this.tagData[this.selectedTagIndex].id : null;
        await this.handleAddActivityButtonClick(this.inputActivityName, selectedTagId);
        this.isShow = false;
        this.resetFormState();
      }
    })
  }

  @Builder
  addNewItemBuilder() {
    ItemFormContent({
      config: this.addMatterSheetConfig,
      tagData: this.tagData,
      inputName: this.inputActivityName,
      selectedTagIndex: this.selectedTagIndex,
      directStartEnabled: this.isToggleOn,
      isEditingTag: this.isEditingTag,
      tagShakeAngle: this.tagShakeAngle,
      selectedEmoji: this.selectedEmojiChar,
      isDarkTheme: this.isDarkTheme,
      onCreateTag: () => {
        if (this.addNewItemDialogController != null) {
          this.addNewItemDialogController.open();
          this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch')
        }
      },
      onDeleteTag: (tag: TagModel, index: number) => {
        this.showDeleteTagDialog(tag, index);
      },
      onToggleTagEditing: (isEditing: boolean) => {
        this.updateTagEditingState(isEditing);
      }
    })
  }

  @Builder
  itemEnd(item: MatterItemModel) {
    Row() {
      if (this.isGoalFighterAvailable) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.share'))
          .fontColor([$r('app.color.accent_lighter')])
          .fontWeight(700)
          .fontSize($r('app.float.today_swipe_share_icon_size'))
      }
      .visualEffect(buildPointLightEffect({
        preset: 'swipeAction',
        color: $r('app.color.immersive_glow_accent'),
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
        isActive: this.swipeShareButtonPressed,
        isDarkTheme: this.isDarkTheme
      }))
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.swipeShareButtonPressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.swipeShareButtonPressed = false;
        }
      })
      .backgroundColor($r('app.color.warning'))
      .onClick(() => {
        void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
        this.closeAllSwipeActions();
        void this.handleShareMatterToGoalFighter(item);
      })
      .accessibilityText($r('app.string.today_share_to_goalfighter'))
      .margin({left: $r('app.float.today_swipe_share_btn_margin_h')})
      .clickEffect({level: ClickEffectLevel.MIDDLE, scale: 0.8})
      .width($r('app.float.today_swipe_share_btn_width'))
      .height($r('app.float.today_swipe_share_btn_height'))
      .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)
      }

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontColor([$r('app.color.accent_lighter')])
          .fontWeight(700)
          .fontSize(20)
      }
      .visualEffect(buildPointLightEffect({
        preset: 'swipeAction',
        color: $r('app.color.immersive_glow_primary'),
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
        isActive: this.swipeEditButtonPressed,
        isDarkTheme: this.isDarkTheme
      }))
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.swipeEditButtonPressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.swipeEditButtonPressed = false;
        }
      })
      .backgroundColor($r('app.color.primary_light'))
      .onClick(() => {
        void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
        if (this.isCurrentRunningItem(item.id)) {
          promptAction.openToast({
            message: '请先暂停事项！',
            duration: 1000
          }).catch(() => {
            hilog.error(0x0000, TAG, 'error in stopping item')
          })
          hilog.warn(0x0000, TAG, `editing item ${item.id}, ${item.title} while running.`)
          return;
        }
        hilog.info(0x0000, TAG, 'pageInfos initialized: ' + JSON.stringify(this.pageInfos));
        this.pageInfos.pushPathByName("MatterItemEditPage", item); //将name指定的NavDestination页面信息入栈
        hilog.info(0x0000, TAG, 'navigating to MatterItemEditPage')
        this.closeAllSwipeActions();
      })
      .margin({right: 15, left: 15})
      .clickEffect({level: ClickEffectLevel.MIDDLE, scale: 0.8})
      .width(60)
      .height(40)
      .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontColor([$r('app.color.accent_lighter')])
          .fontWeight(700)
          .fontSize(20)
      }
      .visualEffect(buildPointLightEffect({
        preset: 'swipeAction',
        color: $r('app.color.immersive_glow_error'),
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
        isActive: this.swipeDeleteButtonPressed,
        isDarkTheme: this.isDarkTheme
      }))
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.swipeDeleteButtonPressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.swipeDeleteButtonPressed = false;
        }
      })
      .backgroundColor($r('app.color.error'))
      .onClick(() => {
        this.confirmDeleteMatter(item);
      })
      .margin({right: 15})
      .clickEffect({level: ClickEffectLevel.MIDDLE, scale: 0.8})
      .width(60)
      .height(40)
      .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)
    }
    .onAppear(() => {
      this.handleItemEndAppear(item.id);
    })
    .onDisAppear(() => {
      this.handleItemEndDisappear(item.id);
    })
  }

  @Builder
  refreshBuilder() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.shouldRunRefreshAnimation()) {
        Progress({ value: this.refreshOffset, total: 70, type: ProgressType.Ring })
          .width(24).height(24)
          .color($r('app.color.primary'))
          .style({ status: this.refreshing ? ProgressStatus.LOADING : ProgressStatus.PROGRESSING })
          .margin(10)
      }
    }
    .clip(true)
    .height("100%")
    .width("100%")
  }

  private shouldRunRefreshAnimation(): boolean {
    const numericState = this.refreshState as number;
    return numericState >= 1 && numericState < 4;
  }

  private shouldAllowForegroundAnimations(): boolean {
    return this.pageLifecycleVisible &&
      this.activeMainTabIndex === 1 &&
      !this.userGuideSheetVisible;
  }

  private shouldRunTagShakeAnimation(): boolean {
    return this.isEditingTag && this.shouldAllowForegroundAnimations();
  }

  private reconcileForegroundAnimationState(): void {
    if (this.shouldRunTagShakeAnimation()) {
      this.startTagShakeAnimation();
      return;
    }
    this.stopTagShakeAnimation();
  }

  private onMainVisibilityGateChanged(): void {
    this.syncTodayVisibilityGate('state_changed');
  }

  private syncTodayVisibilityGate(source: string): void {
    const pageVisible = this.pageLifecycleVisible &&
      this.activeMainTabIndex === 1 &&
      !this.userGuideSheetVisible &&
      !this.isSettingsPanelShow;
    this.todayPageVisible = pageVisible;
    AppStorage.setOrCreate('todayPageVisible', pageVisible);
    if (!pageVisible && this.refreshState !== RefreshStatus.Inactive) {
      this.refreshing = false;
      this.refreshState = RefreshStatus.Done;
    }
    this.reconcileForegroundAnimationState();
    hilog.info(0x0000, TAG,
      `[Today] syncTodayVisibilityGate(${source}) -> visible=${pageVisible}, tab=${this.activeMainTabIndex}, guideVisible=${this.userGuideSheetVisible}, addSheet=${this.isShow}, settingsSheet=${this.isSettingsPanelShow}`);
  }
  @Builder
  settingsBuilder() {
    TodaySettingsSheetContent({
      isSettingsSubPageActive: this.isSettingsSubPageActive,
      directStartEnabled: this.directStartEnabled,
      autoStopEnabled: this.autoStopEnabled,
      autoStopLimitHalfHours: this.autoStopLimitHalfHours,
      calendarSyncEnabled: this.calendarSyncEnabled,
      calendarSyncPermissionGranted: this.calendarSyncPermissionGranted,
      defaultLinePanelEnabled: this.defaultLinePanelEnabled,
      floatingActionBarEnabled: this.useFloatingActionBar,
      ideapoolUnlitFirst: this.ideapoolUnlitFirst,
      ideapoolDirectRecordEnabled: this.ideapoolDirectRecord,
      isDarkTheme: this.isDarkTheme,
      autoBackupEnabled: this.autoBackupEnabled,
      manualExportStatusText: this.resolveManualExportStatusText(),
      manualImportStatusText: this.resolveManualImportStatusText(),
      restoreAutoStatusText: this.resolveRestoreAutoStatusText(),
      autoBackupStatusText: this.buildAutoBackupStatusText(),
      holdingHandEnabled: this.holdingHandEnabled,
      holdingHandOffsetPercent: this.holdingHandOffsetPercent,
      currentBreakpoint: this.currentBreakpoint,
      tabSelectedIndexes: this.tabSelectedIndexes,
      onClose: () => {
        this.handleSettingsClose();
      },
      onDirectStartToggle: (isOn: boolean) => {
        this.handleDirectStartToggle(isOn);
      },
      onAutoStopEnabledChange: (enabled: boolean) => {
        this.handleAutoStopEnabledChange(enabled);
      },
      onAutoStopLimitHalfHoursChange: (limitHalfHours: number) => {
        this.handleAutoStopLimitHalfHoursChange(limitHalfHours);
      },
      onCalendarSyncToggle: async (isOn: boolean) => {
        await this.handleCalendarSyncToggle(isOn);
      },
      onCalendarResyncCopyClick: async () => {
        await this.handleCalendarResyncCopyAction();
      },
      onCalendarPermissionRecoverClick: async () => {
        await this.handleCalendarPermissionRecoverAction();
      },
      onDefaultLinePanelToggle: (isOn: boolean) => {
        this.handleDefaultLinePanelToggle(isOn);
      },
      onFloatingActionBarToggle: (isOn: boolean) => {
        this.handleFloatingActionBarToggle(isOn);
      },
      onIdeaPoolOrderToggle: (isOn: boolean) => {
        this.handleIdeaPoolOrderToggle(isOn);
      },
      onIdeaPoolDirectRecordToggle: (isOn: boolean) => {
        this.handleIdeaPoolDirectRecordToggle(isOn);
      },
      onOpenUserGuide: () => {
        this.openUserGuideFromSettings();
      },
      onManualBackupExport: () => {
        void this.handleManualBackupExport();
      },
      onManualBackupImport: () => {
        void this.handleManualBackupImport();
      },
      onRestoreAutoBackup: () => {
        void this.handleRestoreAutoBackup();
      },
      onAutoBackupToggle: (isOn: boolean) => {
        void this.handleAutoBackupToggle(isOn);
      },
      onHoldingHandToggle: (isOn: boolean) => {
        void this.handleHoldingHandToggle(isOn);
      },
      onHoldingHandOffsetChange: (nextValue: number) => {
        this.handleHoldingHandOffsetChange(nextValue);
      },
      onResetReflectChartSettings: () => {
        this.handleReflectChartSettingsReset();
      },
      onTagDataChanged: async () => {
        await this.handleTagDataChanged();
      }
    })
  }

  private handleSettingsClose(): void {
    this.isSettingsPanelShow = false;
    this.isSettingsSubPageActive = false;
  }

  private async handleTagDataChanged(): Promise<void> {
    try {
      await this.loadTagsFromDatabase();
      this.rebuildSwissKnifeItemVOs();
      await this.updateMatterItems();
      this.refreshSheetHeight();
      hilog.info(0x0000, TAG, '[Today] Tag data refreshed after settings mutation');
    } catch (error) {
      hilog.error(0x0000, TAG, `[Today] Failed to refresh tag data: ${JSON.stringify(error)}`);
    }
  }

  private handleDirectStartToggle(isOn: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Settings direct-start toggle changed to ${isOn}`);
    if (isOn) {
      this.directStartEnabled = true;
      this.isToggleOn = true;
      this.persistDirectStartPreference(true);
    } else {
      this.directStartEnabled = false;
      this.isToggleOn = false;
      this.persistDirectStartPreference(false);
    }
    promptAction.openToast({
      message: isOn ? '默认直接记录事项已开启' : '默认直接记录事项已关闭'
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error in recording item')
    });
  }

  // ========== 自动停止记录设置 ==========

  private updateAutoStopSettingsState(enabled: boolean, limitHalfHours: number): void {
    const normalizedLimit: number = clampAutoStopLimitHalfHours(limitHalfHours);
    this.autoStopEnabled = enabled;
    this.autoStopLimitHalfHours = normalizedLimit;
    syncAutoStopUserSettingsToAppStorage(enabled, normalizedLimit);
  }

  private loadAutoStopSettings(): void {
    try {
      const settingsState = hydrateAutoStopSettings(this.preferencesUtil);
      this.updateAutoStopSettingsState(settingsState.enabled, settingsState.limitHalfHours);
      hilog.info(0x0000, TAG,
        `[Today] AutoStop settings loaded. enabled=${settingsState.enabled}, limitHalfHours=${settingsState.limitHalfHours}, snapshotState=${settingsState.snapshotState}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `[Today] Failed to load autoStop settings: ${JSON.stringify(error)}`);
      this.updateAutoStopSettingsState(AUTO_STOP_ENABLED_DEFAULT, AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT);
    }
  }

  private persistAutoStopSettings(enabled: boolean, limitHalfHours: number): void {
    const normalizedLimit: number = clampAutoStopLimitHalfHours(limitHalfHours);
    this.updateAutoStopSettingsState(enabled, normalizedLimit);

    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting autoStop settings');
      return;
    }

    try {
      preferenceStore.putSync(PreferenceKeys.AUTO_STOP_ENABLED, enabled);
      preferenceStore.putSync(PreferenceKeys.AUTO_STOP_LIMIT_HALF_HOURS, normalizedLimit);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[Today] Failed to persist autoStop settings: ${JSON.stringify(error)}`);
    }
  }

  private handleAutoStopEnabledChange(enabled: boolean): void {
    if (enabled === this.autoStopEnabled) {
      return;
    }
    hilog.info(0x0000, TAG, `[Today] AutoStop enabled changed to ${enabled}`);
    this.persistAutoStopSettings(enabled, this.autoStopLimitHalfHours);
  }

  private handleAutoStopLimitHalfHoursChange(limitHalfHours: number): void {
    const normalizedLimit: number = clampAutoStopLimitHalfHours(limitHalfHours);
    if (normalizedLimit === this.autoStopLimitHalfHours) {
      return;
    }
    hilog.info(0x0000, TAG, `[Today] AutoStop limit changed to ${normalizedLimit} half-hours`);
    this.persistAutoStopSettings(this.autoStopEnabled, normalizedLimit);
  }

  private handleDefaultLinePanelToggle(isOn: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Default data panel toggle changed to ${isOn}`);
    if (isOn) {
      this.defaultLinePanelEnabled = true;
      this.persistDefaultLinePanelPreference(true);
    } else {
      this.defaultLinePanelEnabled = false;
      this.persistDefaultLinePanelPreference(false);
    }
    promptAction.openToast({
      message: isOn ? '数据面板默认展示线图' : '数据面板默认展示饼图'
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error toggling default data panel preference');
    });
  }

  private handleFloatingActionBarToggle(isOn: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Floating action minibar toggle changed to ${isOn}`);
    this.useFloatingActionBar = isOn;
    this.persistFloatingActionBarPreference(isOn);
    promptAction.openToast({
      message: isOn ? '已切换到页签栏悬浮入口' : '已恢复页面内新增入口'
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error toggling floating action minibar preference');
    });
  }

  private handleIdeaPoolOrderToggle(isOn: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Settings ideapool order toggle changed to ${isOn}`);
    if (isOn) {
      this.ideapoolUnlitFirst = true;
      this.persistIdeaPoolOrderPreference(true);
    } else {
      this.ideapoolUnlitFirst = false;
      this.persistIdeaPoolOrderPreference(false);
    }
    promptAction.openToast({
      message: isOn
        ? $r('app.string.ideapool_unlit_first_toast_on')
        : $r('app.string.ideapool_unlit_first_toast_off')
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error toggling ideapool order preference');
    });
  }

  private handleIdeaPoolDirectRecordToggle(isOn: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Ideapool direct-record toggle changed to ${isOn}`);
    this.ideapoolDirectRecord = isOn;
    this.persistIdeaPoolDirectRecordPreference(isOn);
    promptAction.openToast({
      message: isOn
        ? $r('app.string.ideapool_direct_record_toast_on')
        : $r('app.string.ideapool_direct_record_toast_off')
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error toggling ideapool direct record preference');
    });
  }

  private handleReflectChartSettingsReset(): void {
    hilog.info(0x0000, TAG, '[Today] Reflect chart settings reset requested');
    reflectChartPreferenceService.resetToDefault();
    promptAction.openToast({
      message: '已恢复默认',
      duration: 1000
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error resetting reflect chart settings');
    });
  }

  private openUserGuideFromSettings(): void {
    this.showUserGuide = true;
  }

  private changeColorMode() {
    const selectedIndex = this.tabSelectedIndexes && this.tabSelectedIndexes.length > 0 ? this.tabSelectedIndexes[0] : 0;
    const targetMode = this.mapTabIndexToColorMode(selectedIndex);
    this.applyColorModeSelection(targetMode, selectedIndex);
  }

  private applyColorModeSelection(targetMode: number, tabIndex: number): void {
    const normalizedMode = ColorModeUtil.normalize(targetMode);
    const darkTheme = ColorModeUtil.isDarkMode(normalizedMode);
    this.getUIContext().getHostContext()?.getApplicationContext().setColorMode(normalizedMode);
    AppStorage.setOrCreate(COLOR_MODE_STORAGE_KEY, normalizedMode);
    AppStorage.setOrCreate('isDarkTheme', darkTheme);
    this.persistColorModePreference(tabIndex);
  }

  private mapTabIndexToColorMode(index: number): number {
    switch (index) {
      case 1:
        return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      case 2:
        return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      default:
        return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
  }

  private updateTagEditingState(nextState: boolean): void {
    if (this.isEditingTag === nextState) {
      return;
    }

    this.isEditingTag = nextState;
    if (nextState) {
      // 进入编辑模式时，取消当前标签选中，避免删除按钮与选中按钮冲突
      this.selectedTagIndex = -1;
      this.startTagShakeAnimation();
    } else {
      this.stopTagShakeAnimation();
    }
  }

  private rebuildSwissKnifeItemVOs(): void {
    this.swissKnifeItems = toFanItemVOs(this.swissKnifeItems, this.tagData);
  }

  private loadSwissKnifeItemsFromPreferences(): void {
    const items: FanItem[] = fanItemService.getAllFanItems();
    this.swissKnifeItems = toFanItemVOs(items, this.tagData);
    this.checkAndHandleMiniBarDirectRecord();
  }

  private loadDirectStartPreference(): void {
    hilog.info(0x0000, TAG, `[Today] Loading directStart preference. Current state directStartEnabled=${this.directStartEnabled}, isToggleOn=${this.isToggleOn}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when loading directStart flag');
      this.directStartEnabled = false;
      this.isToggleOn = false;
      return;
    }
    try {
      const storedValue = preferenceStore.getSync(PreferenceKeys.DIRECT_START, false) as boolean;
      hilog.info(0x0000, TAG, `[Today] Raw directStart preference value=${JSON.stringify(storedValue)}`);
      this.directStartEnabled = storedValue;
      this.isToggleOn = storedValue;
      hilog.info(0x0000, TAG, `[Today] directStart state updated. directStartEnabled=${this.directStartEnabled}, isToggleOn=${this.isToggleOn}`);
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] directStart state updated.' + JSON.stringify(error))
    }
  }

  private persistDirectStartPreference(value: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Persisting directStart preference with value=${value}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting directStart flag');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.DIRECT_START, value);
      hilog.info(0x0000, TAG, `[Today] directStart preference saved. requiresManualFlush=${this.preferencesUtil.requiresManualFlush()}`);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] directStart preference saved.' + JSON.stringify(error))
    }
  }

  // ========== 系统日历同步设置 ==========

  private loadCalendarSyncPreferences(): void {
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      this.updateCalendarSyncState(false);
      return;
    }

    try {
      const enabledRaw = preferenceStore.getSync(PreferenceKeys.CALENDAR_SYNC_ENABLED, false);
      this.updateCalendarSyncState(!!enabledRaw);
    } catch (error) {
      hilog.error(0x0000, TAG, `error in [Today] calendar sync preference load: ${JSON.stringify(error)}`);
      this.updateCalendarSyncState(false);
    }
  }

  private persistCalendarSyncEnabledPreference(value: boolean): void {
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting calendar sync enabled');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.CALENDAR_SYNC_ENABLED, value);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `error in [Today] calendar sync enabled preference save: ${JSON.stringify(error)}`);
    }
  }

  private updateCalendarSyncState(enabled: boolean): void {
    this.calendarSyncEnabled = enabled;
    AppStorage.setOrCreate(CALENDAR_SYNC_APP_STORAGE_KEY, enabled);
  }

  private async checkCalendarSyncPermissionsGranted(): Promise<boolean> {
    const permissions: Permissions[] = [CALENDAR_SYNC_PERMISSION_READ, CALENDAR_SYNC_PERMISSION_WRITE];
    let tokenId: number = 0;
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      tokenId = bundleInfo.appInfo.accessTokenId;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `CalendarSync: failed to get bundle info during permission check: ${JSON.stringify(err)}`);
      return false;
    }

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      for (const permission of permissions) {
        const status = await atManager.checkAccessToken(tokenId, permission);
        if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return false;
        }
      }
      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `CalendarSync: permission check failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  private async refreshCalendarSyncPermissionState(): Promise<void> {
    if (!this.calendarSyncEnabled) {
      this.calendarSyncPermissionGranted = true;
      return;
    }
    const granted: boolean = await this.checkCalendarSyncPermissionsGranted();
    this.calendarSyncPermissionGranted = granted;
  }

  private async triggerCalendarSyncRecovery(source: string, force: boolean = false): Promise<void> {
    if (!this.calendarSyncEnabled || this.calendarSyncRecoveryRunning) {
      return;
    }

    const nowMs: number = Date.now();
    if (!force && nowMs - this.lastCalendarSyncRecoveryAt < CALENDAR_SYNC_RECOVERY_COOLDOWN_MS) {
      return;
    }
    this.lastCalendarSyncRecoveryAt = nowMs;
    this.calendarSyncRecoveryRunning = true;

    try {
      const granted: boolean = await this.checkCalendarSyncPermissionsGranted();
      this.calendarSyncPermissionGranted = granted;
      if (!granted) {
        hilog.warn(0x0000, TAG, `[Today] calendar sync recovery skipped due to missing permission. source=${source}`);
        return;
      }

      const reconciledCount: number = await calendarSyncService.reconcilePending();
      const recentStartMs: number = this.resolveCalendarSyncRecentStartMs(nowMs);
      const rebuildResult = await calendarSyncService.rebuildMissingMappings(recentStartMs, nowMs,
        CALENDAR_SYNC_REBUILD_BATCH_SIZE);
      if (reconciledCount <= 0 && rebuildResult.total <= 0) {
        hilog.info(0x0000, TAG, `[Today] calendar sync recovery no-op. source=${source}`);
        return;
      }
      if (rebuildResult.success < rebuildResult.total) {
        return;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[Today] calendar sync recovery failed. source=${source}, error=${JSON.stringify(error)}`);
    } finally {
      this.calendarSyncRecoveryRunning = false;
    }
  }

  private async handleCalendarPermissionRecoverAction(): Promise<void> {
    const granted: boolean = await this.ensureCalendarSyncPermissions();
    this.calendarSyncPermissionGranted = granted;
    if (!granted) {
      return;
    }
    this.showToast('日历权限已恢复，正在补同步。', 1200);
    await this.triggerCalendarSyncRecovery('manual_permission_recover', true);
  }

  private async runCalendarBootstrapSync(): Promise<void> {
    try {
      const nowMs: number = Date.now();
      const recentStartMs: number = this.resolveCalendarSyncRecentStartMs(nowMs);
      const result = await calendarSyncService.bootstrapClosedRecords(recentStartMs, nowMs);
      if (result.total <= 0) {
        this.showToast('系统日历同步已开启，最近7天暂无可初始化记录。', 1200);
        return;
      }
      if (result.success === result.total) {
        this.showToast(`系统日历同步已开启，已同步最近7天 ${result.success} 条。`, 1200);
        return;
      }
      this.showToast(`系统日历同步已开启，已同步最近7天 ${result.success}/${result.total} 条。`, 1500);
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar bootstrap sync failed: ${JSON.stringify(error)}`);
      this.showToast('系统日历同步已开启，但初始化同步失败。', 1500);
    }
  }

  private async cleanupCalendarSyncedEvents(): Promise<boolean> {
    try {
      return await calendarSyncService.cleanupAllMappedEvents();
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar cleanup mapped events failed: ${JSON.stringify(error)}`);
      return false;
    }
  }

  private async handleCalendarResyncCopyAction(): Promise<void> {
    const granted: boolean = await this.ensureCalendarSyncPermissions();
    this.calendarSyncPermissionGranted = granted;
    if (!granted) {
      this.showToast('未获得日历权限，无法重同步文案。', 1500);
      return;
    }

    try {
      const nowMs: number = Date.now();
      const copyResult = await calendarSyncService.resyncMappedEventCopy();
      const recentStartMs: number = this.resolveCalendarSyncRecentStartMs(nowMs);
      const rebuildResult = await calendarSyncService.rebuildMissingMappings(recentStartMs, nowMs,
        CALENDAR_SYNC_REBUILD_BATCH_SIZE);
      const totalCount: number = copyResult.total + rebuildResult.total;
      const successCount: number = copyResult.success + rebuildResult.success;
      if (totalCount <= 0) {
        this.showToast('暂无可重同步的日历事件。', 1200);
        return;
      }
      if (successCount === totalCount) {
        this.showToast(`已完成文案重同步 ${successCount} 条。`, 1200);
        return;
      }
      this.showToast(`文案重同步完成 ${successCount}/${totalCount} 条。`, 1500);
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar copy resync failed: ${JSON.stringify(error)}`);
      this.showToast('日历文案重同步失败，请稍后重试。', 1500);
    }
  }

  private resolveCalendarSyncRecentStartMs(endMs: number): number {
    const safeEndMs: number = Math.max(0, endMs);
    return Math.max(0, safeEndMs - CALENDAR_SYNC_RECENT_DAYS * CALENDAR_SYNC_DAY_MS);
  }

  private async handleCalendarSyncToggle(isOn: boolean): Promise<void> {
    if (this.calendarSyncToggleUpdating) {
      return;
    }
    if (isOn === this.calendarSyncEnabled) {
      return;
    }

    this.calendarSyncToggleUpdating = true;
    try {
      if (isOn) {
        const granted: boolean = await this.ensureCalendarSyncPermissions();
        this.calendarSyncPermissionGranted = granted;
        if (!granted) {
          this.updateCalendarSyncState(false);
          this.persistCalendarSyncEnabledPreference(false);
          return;
        }
        this.updateCalendarSyncState(true);
        this.persistCalendarSyncEnabledPreference(true);
        await this.runCalendarBootstrapSync();
        return;
      }

      this.updateCalendarSyncState(false);
      this.persistCalendarSyncEnabledPreference(false);
      this.calendarSyncPermissionGranted = true;
      const cleanupSuccess: boolean = await this.cleanupCalendarSyncedEvents();
      if (cleanupSuccess) {
        this.showToast('系统日历同步已关闭，并已清理同步事件。', 1500);
        return;
      }
      this.showToast('系统日历同步已关闭，部分同步事件清理失败。', 1500);
    } finally {
      this.calendarSyncToggleUpdating = false;
    }
  }

  // ========== 智感握持设置 ==========

  private loadHoldingHandPreferences(): void {
    hilog.info(0x0000, TAG, `[Today] Loading holdingHand preferences. enabled=${this.holdingHandEnabled}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when loading holdingHand settings');
      this.updateHoldingHandEnabledState(false);
      this.updateHoldingHandOffsetState(0);
      return;
    }
    try {
      const storedEnabled = preferenceStore.getSync(PreferenceKeys.HOLDING_HAND_ENABLED, false) as boolean;
      const storedOffset = preferenceStore.getSync(PreferenceKeys.HOLDING_HAND_OFFSET_PERCENT, 0) as number;
      this.updateHoldingHandEnabledState(!!storedEnabled);
      this.updateHoldingHandOffsetState(typeof storedOffset === 'number' ? storedOffset : 0);
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] holdingHand preference load.' + JSON.stringify(error));
      this.updateHoldingHandEnabledState(false);
      this.updateHoldingHandOffsetState(0);
    }
  }

  private persistHoldingHandEnabledPreference(value: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Persisting holdingHand enabled preference with value=${value}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting holdingHand enabled flag');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.HOLDING_HAND_ENABLED, value);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] holdingHand enabled preference saved.' + JSON.stringify(error));
    }
  }

  private persistHoldingHandOffsetPreference(value: number): void {
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting holdingHand offset');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.HOLDING_HAND_OFFSET_PERCENT, value);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] holdingHand offset preference saved.' + JSON.stringify(error));
    }
  }

  private updateHoldingHandEnabledState(enabled: boolean): void {
    this.holdingHandEnabled = enabled;
    AppStorage.setOrCreate('holdingHandEnabled', enabled);
    if (!enabled) {
      AppStorage.setOrCreate('holdingHandStatus', motion.HoldingHandStatus.UNKNOWN_STATUS);
    }
  }

  private updateHoldingHandOffsetState(value: number): void {
    const clamped = Math.min(50, Math.max(0, value));
    this.holdingHandOffsetPercent = clamped;
    AppStorage.setOrCreate('holdingHandOffsetPercent', clamped);
    hilog.info(0x0000, TAG, `holdingHands offset updated: percent=${clamped}`);
  }

  private async handleHoldingHandToggle(isOn: boolean): Promise<void> {
    hilog.info(0x0000, TAG, `[Today] holdingHand toggle changed to ${isOn}`);
    if (isOn) {
      const granted = await this.ensureHoldingHandPermission();
      hilog.info(0x0000, TAG, `holdingHands permission result: granted=${granted}`);
      if (!granted) {
        this.updateHoldingHandEnabledState(false);
        this.persistHoldingHandEnabledPreference(false);
        return;
      }
      this.updateHoldingHandEnabledState(true);
      this.persistHoldingHandEnabledPreference(true);
      this.syncHoldingHandSubscription();
      promptAction.openToast({
        message: '智感握持已开启'
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing holdingHand enabled toast');
      });
      return;
    }

    this.updateHoldingHandEnabledState(false);
    this.persistHoldingHandEnabledPreference(false);
    this.releaseHoldingHandSubscription();
    holdingHandService.resetStatus();
    promptAction.openToast({
      message: '智感握持已关闭'
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error showing holdingHand disabled toast');
    });
  }

  private handleHoldingHandOffsetChange(nextValue: number): void {
    this.updateHoldingHandOffsetState(nextValue);
    this.persistHoldingHandOffsetPreference(this.holdingHandOffsetPercent);
  }

  private shouldEnableHoldingHandOnThisDevice(): boolean {
    return this.holdingHandEnabled && this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_LG;
  }

  private syncHoldingHandSubscription(): void {
    const shouldEnable = this.shouldEnableHoldingHandOnThisDevice();
    hilog.info(0x0000, TAG, `holdingHands subscription sync: shouldEnable=${shouldEnable}, active=${this.holdingHandActive}`);
    if (shouldEnable && !this.holdingHandActive) {
      holdingHandService.start();
      this.holdingHandActive = true;
      hilog.info(0x0000, TAG, 'holdingHands subscription started');
      return;
    }
    if (!shouldEnable && this.holdingHandActive) {
      holdingHandService.stop();
      this.holdingHandActive = false;
      hilog.info(0x0000, TAG, 'holdingHands subscription stopped');
    }
  }

  private releaseHoldingHandSubscription(): void {
    if (!this.holdingHandActive) {
      return;
    }
    holdingHandService.stop();
    this.holdingHandActive = false;
    hilog.info(0x0000, TAG, 'holdingHands subscription released');
  }

  // ========== 数据备份设置 ==========

  private resolveString(resource: Resource): string {
    hilog.info(0x0000, TAG, 'databackup.Today.resolveString');
    try {
      const hostContext = this.getUIContext().getHostContext() as Context;
      if (hostContext && hostContext.resourceManager) {
        return hostContext.resourceManager.getStringSync(resource);
      }
    } catch (_err) {
      // ignore resource lookup failure
    }
    return '';
  }

  private resolveAbilityContext(): common.UIAbilityContext | null {
    hilog.info(0x0000, TAG, 'databackup.Today.resolveAbilityContext');
    try {
      const stored = AppStorage.get('context') as common.UIAbilityContext;
      if (stored) {
        return stored;
      }
    } catch (_error) {
      // ignore storage lookup failure
    }
    try {
      return this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (_err) {
      return null;
    }
  }

  private safePath(path: string): string {
    if (!path) {
      return '';
    }
    let cleaned = path.trim();
    if (cleaned.startsWith('file://')) {
      cleaned = cleaned.slice('file://'.length);
    }
    const parts = cleaned.split('/').filter((part: string) => part.length > 0);
    if (parts.length === 0) {
      return cleaned;
    }
    const tail = parts.slice(Math.max(0, parts.length - 2));
    return tail.join('/');
  }

  private showToast(message: string, duration?: number): void {
    hilog.info(0x0000, TAG, 'databackup.Today.showToast');
    if (!message || message.trim().length === 0) {
      return;
    }
    promptAction.openToast({
      message,
      duration
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error showing backup toast');
    });
  }

  private startBackupProgress(operation: string, messages: string[]): void {
    hilog.info(0x0000, TAG, 'databackup.Today.startBackupProgress');
    this.backupBusy = true;
    this.activeBackupOperation = operation;
    this.backupProgressText = messages.length > 0 ? messages[0] : '';
    this.stopBackupProgressTimer();
    if (messages.length > 1) {
      let index = 0;
      this.backupProgressTimer = setInterval(() => {
        if (!this.backupBusy || this.activeBackupOperation !== operation) {
          return;
        }
        index = (index + 1) % messages.length;
        this.backupProgressText = messages[index];
      }, BACKUP_PROGRESS_INTERVAL_MS);
    }
  }

  private stopBackupProgressTimer(): void {
    hilog.info(0x0000, TAG, 'databackup.Today.stopBackupProgressTimer');
    if (this.backupProgressTimer !== null) {
      clearInterval(this.backupProgressTimer);
      this.backupProgressTimer = null;
    }
  }

  private finishBackupProgress(): void {
    hilog.info(0x0000, TAG, 'databackup.Today.finishBackupProgress');
    this.stopBackupProgressTimer();
    this.backupBusy = false;
    this.activeBackupOperation = '';
    this.backupProgressText = '';
  }

  private resolveManualExportStatusText(): string {
    hilog.info(0x0000, TAG, 'databackup.Today.resolveManualExportStatusText');
    if (this.activeBackupOperation === BACKUP_OPERATION_EXPORT && this.backupProgressText.length > 0) {
      return this.backupProgressText;
    }
    return this.resolveString($r('app.string.backup_manual_export_desc'));
  }

  private resolveManualImportStatusText(): string {
    hilog.info(0x0000, TAG, 'databackup.Today.resolveManualImportStatusText');
    if (this.activeBackupOperation === BACKUP_OPERATION_IMPORT && this.backupProgressText.length > 0) {
      return this.backupProgressText;
    }
    return this.resolveString($r('app.string.backup_manual_import_desc'));
  }

  private resolveRestoreAutoStatusText(): string {
    hilog.info(0x0000, TAG, 'databackup.Today.resolveRestoreAutoStatusText');
    if (this.activeBackupOperation === BACKUP_OPERATION_RESTORE_AUTO && this.backupProgressText.length > 0) {
      return this.backupProgressText;
    }
    return this.resolveString($r('app.string.backup_restore_auto_desc'));
  }

  private resolveBackupErrorText(code: number): string {
    hilog.info(0x0000, TAG, 'databackup.Today.resolveBackupErrorText');
    return this.resolveString(this.resolveBackupErrorResource(code));
  }

  private resolveBackupErrorResource(code: number): Resource {
    hilog.info(0x0000, TAG, 'databackup.Today.resolveBackupErrorResource');
    switch (code) {
      case BackupErrorCode.INVALID_ZIP:
      case BackupErrorCode.MISSING_MANIFEST:
      case BackupErrorCode.UNSUPPORTED_VERSION:
      case BackupErrorCode.MISSING_DB_BACKUP:
      case BackupErrorCode.CORRUPT_MANIFEST:
        return $r('app.string.backup_error_invalid');
      case BackupErrorCode.PERMISSION_DENIED:
        return $r('app.string.backup_error_permission');
      case BackupErrorCode.UNSUPPORTED:
        return $r('app.string.backup_error_unsupported');
      case BackupErrorCode.IO_ERROR:
        return $r('app.string.backup_error_io');
      case BackupErrorCode.CANCELLED_BY_USER:
        return $r('app.string.backup_error_cancelled');
      case BackupErrorCode.BUSY:
        return $r('app.string.backup_error_busy');
      default:
        return $r('app.string.backup_error_generic');
    }
  }

  private formatBackupTimestamp(timestamp: number): string {
    hilog.info(0x0000, TAG, 'databackup.Today.formatBackupTimestamp');
    if (!timestamp || timestamp <= 0) {
      return '';
    }
    const date = new Date(timestamp);
    const year = date.getFullYear().toString();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}`;
  }

  private buildAutoBackupDayKey(timestamp: number): string {
    hilog.info(0x0000, TAG, 'databackup.Today.buildAutoBackupDayKey');
    const effectiveTime = timestamp > 0 ? timestamp : Date.now();
    const date = new Date(effectiveTime);
    const year = date.getFullYear().toString();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}${month}${day}`;
  }

  private buildAutoBackupStatusText(): string {
    hilog.info(0x0000, TAG, 'databackup.Today.buildAutoBackupStatusText');
    const enabledText = this.autoBackupEnabled
      ? this.resolveString($r('app.string.backup_auto_enabled'))
      : this.resolveString($r('app.string.backup_auto_disabled'));
    let status = enabledText;
    if (this.autoBackupEnabled && this.autoBackupLastRunAt > 0) {
      const lastRun = this.formatBackupTimestamp(this.autoBackupLastRunAt);
      if (lastRun.length > 0) {
        status = `${status} · ${this.resolveString($r('app.string.backup_auto_last_run_prefix'))}${lastRun}`;
      }
    }
    if (this.autoBackupLastErrorCode !== 0) {
      const errorText = this.resolveBackupErrorText(this.autoBackupLastErrorCode);
      if (errorText.length > 0) {
        status = `${status} · ${this.resolveString($r('app.string.backup_auto_last_error_prefix'))}${errorText}`;
      }
    }
    return status;
  }

  private persistAutoBackupErrorCode(code: number): void {
    hilog.info(0x0000, TAG, 'databackup.Today.persistAutoBackupErrorCode');
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting auto backup error');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.AUTO_BACKUP_LAST_ERROR_CODE, code);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] auto backup error code save.' + JSON.stringify(error));
    }
  }

  private persistAutoBackupSuccess(runAt: number): void {
    hilog.info(0x0000, TAG, 'databackup.Today.persistAutoBackupSuccess');
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting auto backup state');
      return;
    }
    const dayKey = this.buildAutoBackupDayKey(runAt);
    try {
      preferenceStore.putSync(PreferenceKeys.AUTO_BACKUP_LAST_DAY, dayKey);
      preferenceStore.putSync(PreferenceKeys.AUTO_BACKUP_LAST_RUN_AT, runAt);
      preferenceStore.putSync(PreferenceKeys.AUTO_BACKUP_LAST_ERROR_CODE, 0);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] auto backup state save.' + JSON.stringify(error));
    }
  }

  private async loadAutoBackupStatus(): Promise<void> {
    hilog.info(0x0000, TAG, 'databackup.Today.loadAutoBackupStatus');
    const context = this.resolveAbilityContext();
    if (!context) {
      hilog.warn(0x0000, TAG, '[Today] Missing context when loading auto backup status');
      return;
    }
    try {
      const dirState = await getAutoBackupDirState(context);
      this.autoBackupEnabled = dirState.enabled;
      if (dirState.issue?.code) {
        this.autoBackupLastErrorCode = dirState.issue.code;
      }
    } catch (error) {
      hilog.warn(0x0000, TAG, `Failed to load auto backup dir state: ${JSON.stringify(error)}`);
    }

    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      return;
    }
    try {
      const lastRunRaw = preferenceStore.getSync(PreferenceKeys.AUTO_BACKUP_LAST_RUN_AT, 0);
      this.autoBackupLastRunAt = typeof lastRunRaw === 'number' ? lastRunRaw : Number(lastRunRaw) || 0;
      if (this.autoBackupLastErrorCode === 0) {
        const lastErrorRaw = preferenceStore.getSync(PreferenceKeys.AUTO_BACKUP_LAST_ERROR_CODE, 0);
        const resolvedError = typeof lastErrorRaw === 'number' ? lastErrorRaw : Number(lastErrorRaw) || 0;
        this.autoBackupLastErrorCode = resolvedError;
      }
    } catch (error) {
      hilog.warn(0x0000, TAG, `Failed to load auto backup state from preferences: ${JSON.stringify(error)}`);
    }
  }

  private async handleAutoBackupToggle(isOn: boolean): Promise<void> {
    hilog.info(0x0000, TAG, 'databackup.Today.handleAutoBackupToggle');
    if (this.backupBusy) {
      this.showToast(this.resolveString($r('app.string.backup_error_busy')));
      return;
    }
    const context = this.resolveAbilityContext();
    if (!context) {
      this.showToast(this.resolveString($r('app.string.backup_error_generic')));
      return;
    }

    if (isOn) {
      const state = await ensureAutoBackupDir(context);
      if (state.enabled) {
        this.autoBackupEnabled = true;
        this.autoBackupLastErrorCode = 0;
        this.persistAutoBackupErrorCode(0);
        this.showToast(this.resolveString($r('app.string.backup_auto_enabled_toast')));
        const appVersion = await this.resolveAppVersion();
        this.startBackupProgress(BACKUP_OPERATION_AUTO, [
          this.resolveString($r('app.string.backup_progress_preparing')),
          this.resolveString($r('app.string.backup_progress_compressing'))
        ]);
        try {
          const result = await createAutoBackup({
            context,
            appVersion
          });
          if (result.ok) {
            const createdAt = typeof result.createdAt === 'number' ? result.createdAt : Date.now();
            this.autoBackupLastRunAt = createdAt;
            this.autoBackupLastErrorCode = 0;
            this.persistAutoBackupSuccess(createdAt);
          } else {
            const errorCode = result.code ?? BackupErrorCode.IO_ERROR;
            this.autoBackupLastErrorCode = errorCode;
            this.persistAutoBackupErrorCode(errorCode);
            this.showToast(this.resolveBackupErrorText(errorCode));
          }
        } catch (error) {
          hilog.error(0x0000, TAG, `auto backup run failed: ${JSON.stringify(error)}`);
          this.autoBackupLastErrorCode = BackupErrorCode.IO_ERROR;
          this.persistAutoBackupErrorCode(BackupErrorCode.IO_ERROR);
          this.showToast(this.resolveBackupErrorText(BackupErrorCode.IO_ERROR));
        } finally {
          this.finishBackupProgress();
        }
      } else {
        const code = state.issue?.code ?? BackupErrorCode.PERMISSION_DENIED;
        this.autoBackupEnabled = false;
        this.autoBackupLastErrorCode = code;
        this.persistAutoBackupErrorCode(code);
        this.showToast(this.resolveBackupErrorText(code));
      }
      return;
    }

    await clearAutoBackupDir(context);
    this.autoBackupEnabled = false;
    this.autoBackupLastErrorCode = 0;
    this.persistAutoBackupErrorCode(0);
    this.showToast(this.resolveString($r('app.string.backup_auto_disabled_toast')));
  }

  private resolvePickerUri(result: PickerResult | undefined): string | null {
    hilog.info(0x0000, TAG, 'databackup.Today.resolvePickerUri');
    if (!result) {
      return null;
    }
    if (Array.isArray(result)) {
      return result.length > 0 ? result[0] : null;
    }
    if (typeof result === 'string' && result.trim().length > 0) {
      return result;
    }
    return null;
  }

  private async pickExportUri(defaultFileName: string): Promise<string | null> {
    hilog.info(0x0000, TAG, 'databackup.Today.pickExportUri');
    const viewPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [defaultFileName];
    const filterLabel = this.resolveString($r('app.string.backup_zip_filter'));
    options.fileSuffixChoices = [`${filterLabel}|.zip`];
    try {
      const result = await viewPicker.save(options) as PickerResult;
      return this.resolvePickerUri(result);
    } catch (error) {
      const errMessage = JSON.stringify(error);
      hilog.warn(0x0000, TAG, `Backup export picker failed: ${errMessage}`);
      return null;
    }
  }

  private async pickImportUri(defaultDirUri?: string): Promise<string | null> {
    hilog.info(0x0000, TAG, 'databackup.Today.pickImportUri');
    const viewPicker = new picker.DocumentViewPicker();
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.zip'];
    if (defaultDirUri && defaultDirUri.trim().length > 0) {
      options.defaultFilePathUri = defaultDirUri.trim();
    }
    try {
      const result = await viewPicker.select(options) as PickerResult;
      return this.resolvePickerUri(result);
    } catch (error) {
      const errMessage = JSON.stringify(error);
      hilog.warn(0x0000, TAG, `Backup import picker failed: ${errMessage}`);
      return null;
    }
  }

  private copyFileByPath(srcPath: string, destPath: string): number {
    hilog.info(0x0000, TAG, 'databackup.Today.copyFileByPath');
    hilog.info(0x0000, TAG, `databackup.stage=copy_file src=${this.safePath(srcPath)} dst=${this.safePath(destPath)}`);
    let srcFd: number | null = null;
    let dstFd: number | null = null;
    try {
      srcFd = fs.openSync(srcPath, fs.OpenMode.READ_ONLY).fd;
      dstFd = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC).fd;
      const buffer = new ArrayBuffer(1024 * 1024);
      let totalWritten = 0;
      while (true) {
        const bytesRead = fs.readSync(srcFd, buffer);
        if (bytesRead <= 0) {
          break;
        }
        fs.writeSync(dstFd, buffer, { length: bytesRead });
        totalWritten += bytesRead;
      }
      return totalWritten;
    } finally {
      if (srcFd !== null) {
        try {
          fs.closeSync(srcFd);
        } catch (_err) {
          // ignore close failure
        }
      }
      if (dstFd !== null) {
        try {
          fs.closeSync(dstFd);
        } catch (_err) {
          // ignore close failure
        }
      }
    }
  }

  private cleanupFileBestEffort(path: string): void {
    hilog.info(0x0000, TAG, 'databackup.Today.cleanupFileBestEffort');
    try {
      fs.unlinkSync(path);
    } catch (_err) {
      // ignore cleanup failure
    }
  }

  private buildTempImportPath(context: common.UIAbilityContext): string {
    hilog.info(0x0000, TAG, 'databackup.Today.buildTempImportPath');
    const tempDir = context.tempDir;
    if (!tempDir || tempDir.trim().length === 0) {
      throw new Error('tempDir is missing');
    }
    const suffix = Date.now().toString();
    return `${tempDir}/import_${suffix}.zip`;
  }

  private async resolveAppVersion(): Promise<string> {
    hilog.info(0x0000, TAG, 'databackup.Today.resolveAppVersion');
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const info = bundleInfo as BundleInfoLike;
      if (typeof info.versionName === 'string' && info.versionName.trim().length > 0) {
        return info.versionName.trim();
      }
      if (info.appInfo && typeof info.appInfo.versionName === 'string' && info.appInfo.versionName.trim().length > 0) {
        return info.appInfo.versionName.trim();
      }
    } catch (error) {
      hilog.warn(0x0000, TAG, `resolveAppVersion failed: ${JSON.stringify(error)}`);
    }
    return '0.0.0';
  }

  private async showRestoreConfirmDialog(): Promise<boolean> {
    hilog.info(0x0000, TAG, 'databackup.Today.showRestoreConfirmDialog');
    return new Promise((resolve) => {
      let resolved = false;
      const finish = (value: boolean) => {
        if (resolved) {
          return;
        }
        resolved = true;
        resolve(value);
      };
      this.getUIContext().showAlertDialog({
        title: this.resolveString($r('app.string.backup_restore_confirm_title')),
        message: this.resolveString($r('app.string.backup_restore_confirm_message')),
        autoCancel: true,
        alignment: DialogAlignment.Center,
        gridCount: 4,
        offset: { dx: 0, dy: -20 },
        primaryButton: {
          value: this.resolveString($r('app.string.backup_restore_confirm_cancel')),
          action: () => {
            finish(false);
          }
        },
        secondaryButton: {
          enabled: true,
          defaultFocus: true,
          style: DialogButtonStyle.HIGHLIGHT,
          value: this.resolveString($r('app.string.backup_restore_confirm_continue')),
          action: () => {
            finish(true);
          }
        },
        cancel: () => {
          finish(false);
        },
        onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
          if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
            dismissDialogAction.dismiss();
            finish(false);
          }
          if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
            dismissDialogAction.dismiss();
            finish(false);
          }
        },
      });
    });
  }

  private async refreshAfterRestore(): Promise<void> {
    hilog.info(0x0000, TAG, 'databackup.Today.refreshAfterRestore');
    try {
      await recordingSessionStore.restoreFromDb();
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const openRecords = await rdbStoreUtil.queryActiveOpenRecords();
      const manager = MatterItemStateManager.getInstance();
      if (openRecords.length > 0) {
        for (const record of openRecords) {
          const activity = await rdbStoreUtil.queryActivityById(record.activityId);
          if (!activity) {
            hilog.warn(0x0000, TAG, `restore refresh: open record ${record.recordId} missing activity ${record.activityId}`);
            continue;
          }
          if (activity.status !== MatterStatus.RECORDING) {
            hilog.warn(0x0000, TAG,
              `restore refresh: activity ${record.activityId} status=${activity.status}, correcting to RECORDING.`);
            const updated = await rdbStoreUtil.updateActivityStatus(record.activityId, MatterStatus.RECORDING);
            if (!updated) {
              hilog.error(0x0000, TAG, `restore refresh: failed to reconcile activity status for ${record.activityId}`);
            }
          }
        }
        for (const record of openRecords) {
          await manager.refreshItemState(record.activityId);
        }
      }
      await manager.reconcileGlobalRunningState();
      await this.loadTagsFromDatabase();
      this.newTagColor = tagColorPreferenceService.getColors();
      await this.updateMatterItems();
      this.syncAllAnimatedLists(false);
      refreshAllMatterItemNodes(this.isDarkTheme);
      this.refreshSheetHeight();
    } catch (error) {
      hilog.warn(0x0000, TAG, `refreshAfterRestore failed: ${JSON.stringify(error)}`);
    }
  }

  private async handleManualBackupExport(): Promise<void> {
    hilog.info(0x0000, TAG, 'databackup.Today.handleManualBackupExport');
    if (this.backupBusy) {
      this.showToast(this.resolveString($r('app.string.backup_error_busy')));
      return;
    }
    const context = this.resolveAbilityContext();
    if (!context) {
      this.showToast(this.resolveString($r('app.string.backup_error_generic')));
      return;
    }

    const appVersion = await this.resolveAppVersion();
    this.startBackupProgress(BACKUP_OPERATION_EXPORT, [
      this.resolveString($r('app.string.backup_progress_preparing')),
      this.resolveString($r('app.string.backup_progress_compressing'))
    ]);

    let tempZipPath = '';
    let createdAt = Date.now();
    try {
      const result = await createManualBackup({
        context,
        appVersion
      });
      if (!result.ok || !result.zipUri) {
        hilog.warn(0x0000, TAG, `databackup.error stage=manual_export_prepare_fail code=${result.code}`);
        this.showToast(this.resolveBackupFailureMessage(result));
        this.finishBackupProgress();
        return;
      }
      tempZipPath = result.zipUri;
      if (typeof result.createdAt === 'number') {
        createdAt = result.createdAt;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Manual export prepare failed: ${JSON.stringify(error)}`);
      hilog.error(0x0000, TAG, `databackup.error stage=manual_export_prepare_exception msg=${JSON.stringify(error)}`);
      this.showToast(this.resolveString($r('app.string.backup_error_generic')));
      this.finishBackupProgress();
      return;
    }

    const defaultFileName = buildBackupZipFileName(createdAt);
    hilog.info(0x0000, TAG, `databackup.stage=manual_export_pick name=${defaultFileName}`);
    const exportUri = await this.pickExportUri(defaultFileName);
    if (!exportUri) {
      hilog.info(0x0000, TAG, 'databackup.stage=manual_export_cancelled');
      if (tempZipPath) {
        this.cleanupFileBestEffort(tempZipPath);
      }
      this.finishBackupProgress();
      return;
    }
    hilog.info(0x0000, TAG, `databackup.stage=manual_export_selected uri=${this.safePath(exportUri)}`);
    this.stopBackupProgressTimer();
    this.backupProgressText = this.resolveString($r('app.string.backup_progress_saving'));

    try {
      this.copyFileByPath(tempZipPath, exportUri);
      const prefix = this.resolveString($r('app.string.backup_export_success_prefix'));
      hilog.info(0x0000, TAG, `databackup.stage=manual_export_ok uri=${this.safePath(exportUri)}`);
      this.showToast(`${prefix}${exportUri}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `Manual export copy failed: ${JSON.stringify(error)}`);
      hilog.error(0x0000, TAG, `databackup.error stage=manual_export_copy msg=${JSON.stringify(error)}`);
      this.showToast(this.resolveString($r('app.string.backup_error_io')));
    } finally {
      if (tempZipPath) {
        this.cleanupFileBestEffort(tempZipPath);
      }
      this.finishBackupProgress();
    }
  }

  private async handleManualBackupImport(): Promise<void> {
    hilog.info(0x0000, TAG, 'databackup.Today.handleManualBackupImport');
    if (this.backupBusy) {
      this.showToast(this.resolveString($r('app.string.backup_error_busy')));
      return;
    }
    const context = this.resolveAbilityContext();
    if (!context) {
      this.showToast(this.resolveString($r('app.string.backup_error_generic')));
      return;
    }

    const importUri = await this.pickImportUri();
    if (!importUri) {
      hilog.info(0x0000, TAG, 'databackup.stage=manual_import_cancelled');
      return;
    }
    hilog.info(0x0000, TAG, `databackup.stage=manual_import_selected uri=${this.safePath(importUri)}`);

    let tempPath = '';
    try {
      tempPath = this.buildTempImportPath(context);
      this.copyFileByPath(importUri, tempPath);
    } catch (error) {
      hilog.error(0x0000, TAG, `Manual import copy failed: ${JSON.stringify(error)}`);
      hilog.error(0x0000, TAG, `databackup.error stage=manual_import_copy msg=${JSON.stringify(error)}`);
      this.showToast(this.resolveString($r('app.string.backup_error_io')));
      if (tempPath) {
        this.cleanupFileBestEffort(tempPath);
      }
      return;
    }

    this.startBackupProgress(BACKUP_OPERATION_IMPORT, [
      this.resolveString($r('app.string.backup_progress_validating'))
    ]);

    try {
      const validationResult = await validateBackupZip({
        context,
        zipPathOrUri: tempPath
      });
      if (!validationResult.ok) {
        hilog.warn(0x0000, TAG, `databackup.error stage=manual_import_validate_fail code=${validationResult.code}`);
        this.showToast(this.resolveBackupFailureMessage(validationResult));
        this.cleanupFileBestEffort(tempPath);
        this.finishBackupProgress();
        return;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Manual import validate failed: ${JSON.stringify(error)}`);
      hilog.error(0x0000, TAG, `databackup.error stage=manual_import_validate_exception msg=${JSON.stringify(error)}`);
      this.showToast(this.resolveString($r('app.string.backup_error_generic')));
      this.cleanupFileBestEffort(tempPath);
      this.finishBackupProgress();
      return;
    }
    this.finishBackupProgress();

    const confirmed = await this.showRestoreConfirmDialog();
    if (!confirmed) {
      hilog.info(0x0000, TAG, 'databackup.stage=manual_import_cancelled_confirm');
      this.cleanupFileBestEffort(tempPath);
      this.showToast(this.resolveString($r('app.string.backup_restore_cancelled')));
      return;
    }

    this.startBackupProgress(BACKUP_OPERATION_IMPORT, [
      this.resolveString($r('app.string.backup_progress_restoring')),
      this.resolveString($r('app.string.backup_progress_refreshing'))
    ]);

    try {
      const result = await importAndRestore({
        context,
        zipPathOrUri: tempPath
      });
      if (result.ok) {
        await this.refreshAfterRestore();
        hilog.info(0x0000, TAG, 'databackup.stage=manual_import_ok');
        this.showToast(this.resolveString($r('app.string.backup_restore_success')));
      } else {
        hilog.warn(0x0000, TAG, `databackup.error stage=manual_import_fail code=${result.code}`);
        this.showToast(this.resolveBackupFailureMessage(result));
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Manual import restore failed: ${JSON.stringify(error)}`);
      hilog.error(0x0000, TAG, `databackup.error stage=manual_import_exception msg=${JSON.stringify(error)}`);
      this.showToast(this.resolveString($r('app.string.backup_error_generic')));
    } finally {
      this.cleanupFileBestEffort(tempPath);
      this.finishBackupProgress();
    }
  }

  private async handleRestoreAutoBackup(): Promise<void> {
    hilog.info(0x0000, TAG, 'databackup.Today.handleRestoreAutoBackup');
    if (this.backupBusy) {
      this.showToast(this.resolveString($r('app.string.backup_error_busy')));
      return;
    }
    const context = this.resolveAbilityContext();
    if (!context) {
      this.showToast(this.resolveString($r('app.string.backup_error_generic')));
      return;
    }

    const dirState = await getAutoBackupDirState(context);
    if (!dirState.enabled || !dirState.dirUri) {
      const errorCode = dirState.issue?.code ?? BackupErrorCode.PERMISSION_DENIED;
      hilog.warn(0x0000, TAG, `databackup.error stage=auto_restore_dir code=${errorCode}`);
      this.showToast(this.resolveBackupErrorText(errorCode));
      return;
    }

    const importUri = await this.pickImportUri(dirState.dirUri);
    if (!importUri) {
      hilog.info(0x0000, TAG, 'databackup.stage=auto_restore_cancelled');
      return;
    }
    hilog.info(0x0000, TAG, `databackup.stage=auto_restore_selected uri=${this.safePath(importUri)}`);

    let tempPath = '';
    try {
      tempPath = this.buildTempImportPath(context);
      this.copyFileByPath(importUri, tempPath);
    } catch (error) {
      hilog.error(0x0000, TAG, `Auto restore copy failed: ${JSON.stringify(error)}`);
      hilog.error(0x0000, TAG, `databackup.error stage=auto_restore_copy msg=${JSON.stringify(error)}`);
      this.showToast(this.resolveString($r('app.string.backup_error_io')));
      if (tempPath) {
        this.cleanupFileBestEffort(tempPath);
      }
      return;
    }

    this.startBackupProgress(BACKUP_OPERATION_RESTORE_AUTO, [
      this.resolveString($r('app.string.backup_progress_validating'))
    ]);

    try {
      const validationResult = await validateBackupZip({
        context,
        zipPathOrUri: tempPath
      });
      if (!validationResult.ok) {
        hilog.warn(0x0000, TAG, `databackup.error stage=auto_restore_validate_fail code=${validationResult.code}`);
        this.showToast(this.resolveBackupFailureMessage(validationResult));
        this.cleanupFileBestEffort(tempPath);
        this.finishBackupProgress();
        return;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Auto restore validate failed: ${JSON.stringify(error)}`);
      hilog.error(0x0000, TAG, `databackup.error stage=auto_restore_validate_exception msg=${JSON.stringify(error)}`);
      this.showToast(this.resolveString($r('app.string.backup_error_generic')));
      this.cleanupFileBestEffort(tempPath);
      this.finishBackupProgress();
      return;
    }
    this.finishBackupProgress();

    const confirmed = await this.showRestoreConfirmDialog();
    if (!confirmed) {
      hilog.info(0x0000, TAG, 'databackup.stage=auto_restore_cancelled_confirm');
      this.cleanupFileBestEffort(tempPath);
      this.showToast(this.resolveString($r('app.string.backup_restore_cancelled')));
      return;
    }

    this.startBackupProgress(BACKUP_OPERATION_RESTORE_AUTO, [
      this.resolveString($r('app.string.backup_progress_restoring')),
      this.resolveString($r('app.string.backup_progress_refreshing'))
    ]);

    try {
      const result = await importAndRestore({
        context,
        zipPathOrUri: tempPath
      });
      if (result.ok) {
        await this.refreshAfterRestore();
        hilog.info(0x0000, TAG, 'databackup.stage=auto_restore_ok');
        this.showToast(this.resolveString($r('app.string.backup_restore_success')));
      } else {
        hilog.warn(0x0000, TAG, `databackup.error stage=auto_restore_fail code=${result.code}`);
        this.showToast(this.resolveBackupFailureMessage(result));
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Auto restore failed: ${JSON.stringify(error)}`);
      hilog.error(0x0000, TAG, `databackup.error stage=auto_restore_exception msg=${JSON.stringify(error)}`);
      this.showToast(this.resolveString($r('app.string.backup_error_generic')));
    } finally {
      this.cleanupFileBestEffort(tempPath);
      this.finishBackupProgress();
    }
  }

  private resolveBackupFailureMessage(result: BackupResult): string {
    hilog.info(0x0000, TAG, 'databackup.Today.resolveBackupFailureMessage');
    if (!result) {
      return this.resolveString($r('app.string.backup_error_generic'));
    }
    if (result.code) {
      return this.resolveBackupErrorText(result.code);
    }
    if (result.validation?.issue?.code) {
      return this.resolveBackupErrorText(result.validation.issue.code);
    }
    return this.resolveString($r('app.string.backup_error_generic'));
  }

  private async ensureCalendarSyncPermissions(): Promise<boolean> {
    const permissions: Permissions[] = [CALENDAR_SYNC_PERMISSION_READ, CALENDAR_SYNC_PERMISSION_WRITE];
    let abilityContext: Context | undefined;
    try {
      abilityContext = AppStorage.get('context') as Context;
    } catch (error) {
      hilog.warn(0x0000, TAG, `Failed to read ability context from AppStorage: ${JSON.stringify(error)}`);
    }
    if (!abilityContext) {
      hilog.warn(0x0000, TAG, 'CalendarSync: unable to request permission because ability context is unavailable');
      return false;
    }

    let tokenId: number = 0;
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      tokenId = bundleInfo.appInfo.accessTokenId;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `CalendarSync: Failed to get bundle info for permission check: ${JSON.stringify(err)}`);
      return false;
    }

    const missingPermissions: Permissions[] = [];
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      for (const permission of permissions) {
        const status = await atManager.checkAccessToken(tokenId, permission);
        if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          missingPermissions.push(permission);
        }
      }
      if (missingPermissions.length === 0) {
        hilog.info(0x0000, TAG, 'CalendarSync: permissions already granted');
        return true;
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `CalendarSync: permission pre-check failed: ${JSON.stringify(err)}`);
      missingPermissions.splice(0, missingPermissions.length, ...permissions);
    }

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(abilityContext, missingPermissions);
      const authResults: number[] = Array.isArray(result?.authResults) ? result.authResults : [];
      const grantedAll = authResults.length === missingPermissions.length &&
        authResults.every((value: number) => value === 0);
      if (grantedAll) {
        hilog.info(0x0000, TAG, 'CalendarSync: permissions granted by user');
        return true;
      }
      hilog.error(0x0000, TAG, 'CalendarSync: permissions denied by user');
      this.showToast('需要日历权限才能开启同步，请在系统设置中授权。', 1800);
      return false;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `CalendarSync: request permission failed: ${JSON.stringify(err)}`);
      this.showToast('请求日历权限失败，请稍后重试。', 1800);
      return false;
    }
  }


  private async ensureHoldingHandPermission(): Promise<boolean> {
    const permission: Permissions = 'ohos.permission.DETECT_GESTURE';
    let abilityContext: Context | undefined;
    try {
      abilityContext = AppStorage.get('context') as Context;
    } catch (error) {
      hilog.warn(0x0000, TAG, `Failed to read ability context from AppStorage: ${JSON.stringify(error)}`);
    }
    if (!abilityContext) {
      hilog.warn(0x0000, TAG, 'HoldingHand: unable to request permission because ability context is unavailable');
      return false;
    }

    let tokenId = 0;
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      tokenId = bundleInfo.appInfo.accessTokenId;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `HoldingHand: Failed to get bundle info for permission check: ${JSON.stringify(err)}`);
      return false;
    }

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const status = await atManager.checkAccessToken(tokenId, permission);
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        hilog.info(0x0000, TAG, 'HoldingHand: permission already granted');
        return true;
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `HoldingHand: permission pre-check failed: ${JSON.stringify(err)}`);
    }

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(abilityContext, [permission]);
      const granted = Array.isArray(result?.authResults) && result.authResults[0] === 0;
      if (granted) {
        hilog.info(0x0000, TAG, 'HoldingHand: permission granted by user');
        return true;
      }
      hilog.error(0x0000, TAG, 'HoldingHand: permission denied by user');
      promptAction.openToast({
        message: '需要动作感知权限，可在设置中开启。',
        duration: 2000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing holding hand permission denial toast');
      });
      return false;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `HoldingHand: request permission failed: ${JSON.stringify(err)}`);
      promptAction.openToast({
        message: '请求权限失败，请稍后重试。',
        duration: 2000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing holding hand permission failure toast');
      });
      return false;
    }
  }

  private loadDefaultLinePanelPreference(): void {
    hilog.info(0x0000, TAG, `[Today] Loading default data panel preference. Current state defaultLinePanelEnabled=${this.defaultLinePanelEnabled}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when loading default data panel flag');
      this.defaultLinePanelEnabled = false;
      return;
    }
    try {
      const storedValue = preferenceStore.getSync(PreferenceKeys.DEFAULT_LINE_PANEL, false) as boolean;
      hilog.info(0x0000, TAG, `[Today] Raw default data panel preference value=${JSON.stringify(storedValue)}`);
      this.defaultLinePanelEnabled = storedValue;
      hilog.info(0x0000, TAG, `[Today] Default data panel state updated. defaultLinePanelEnabled=${this.defaultLinePanelEnabled}`);
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] default data panel state updated.' + JSON.stringify(error))
    }
  }

  private persistDefaultLinePanelPreference(value: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Persisting default data panel preference with value=${value}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting default data panel flag');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.DEFAULT_LINE_PANEL, value);
      hilog.info(0x0000, TAG, `[Today] Default data panel preference saved. requiresManualFlush=${this.preferencesUtil.requiresManualFlush()}`);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] default data panel preference saved.' + JSON.stringify(error))
    }
  }

  private loadIdeaPoolOrderPreference(): void {
    hilog.info(0x0000, TAG, `[Today] Loading ideapool order preference. current=${this.ideapoolUnlitFirst}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when loading ideapool order');
      this.ideapoolUnlitFirst = true;
      return;
    }
    try {
      const storedValue = preferenceStore.getSync(PreferenceKeys.IDEAPOOL_UNLIT_FIRST, true) as boolean;
      const normalized = !!storedValue;
      this.ideapoolUnlitFirst = normalized;
      hilog.info(0x0000, TAG, `[Today] Ideapool order preference loaded. unlitFirst=${normalized}`);
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] ideapool order preference load.' + JSON.stringify(error))
    }
  }

  private persistIdeaPoolOrderPreference(value: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Persisting ideapool order preference with value=${value}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting ideapool order');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.IDEAPOOL_UNLIT_FIRST, value);
      hilog.info(0x0000, TAG, `[Today] ideapool order preference saved. requiresManualFlush=${this.preferencesUtil.requiresManualFlush()}`);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] ideapool order preference saved.' + JSON.stringify(error))
    }
  }

  private loadIdeaPoolDirectRecordPreference(): void {
    hilog.info(0x0000, TAG, `[Today] Loading ideapool direct record preference. current=${this.ideapoolDirectRecord}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when loading ideapool direct record');
      this.ideapoolDirectRecord = false;
      return;
    }
    try {
      const storedValue = preferenceStore.getSync(PreferenceKeys.IDEAPOOL_DIRECT_RECORD, false) as boolean;
      const normalized = !!storedValue;
      this.ideapoolDirectRecord = normalized;
      hilog.info(0x0000, TAG, `[Today] Ideapool direct record preference loaded. enabled=${normalized}`);
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] ideapool direct record preference load.' + JSON.stringify(error))
    }
  }

  private loadFloatingActionBarPreference(): void {
    hilog.info(0x0000, TAG, `[Today] Loading floating action minibar preference. current=${this.useFloatingActionBar}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when loading floating action minibar');
      this.useFloatingActionBar = false;
      return;
    }
    try {
      const storedValue = preferenceStore.getSync(PreferenceKeys.FLOATING_ACTION_MINIBAR, false) as boolean;
      const normalized: boolean = !!storedValue;
      this.useFloatingActionBar = normalized;
      hilog.info(0x0000, TAG, `[Today] Floating action minibar preference loaded. enabled=${normalized}`);
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] floating action minibar preference load.' + JSON.stringify(error))
    }
  }

  private persistFloatingActionBarPreference(value: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Persisting floating action minibar preference with value=${value}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting floating action minibar');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.FLOATING_ACTION_MINIBAR, value);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] floating action minibar preference saved.' + JSON.stringify(error))
    }
  }

  private persistIdeaPoolDirectRecordPreference(value: boolean): void {
    hilog.info(0x0000, TAG, `[Today] Persisting ideapool direct record preference with value=${value}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting ideapool direct record');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.IDEAPOOL_DIRECT_RECORD, value);
      hilog.info(0x0000, TAG, `[Today] ideapool direct record preference saved. requiresManualFlush=${this.preferencesUtil.requiresManualFlush()}`);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] ideapool direct record preference saved.' + JSON.stringify(error))
    }
  }

  private loadColorModePreference(): void {
    hilog.info(0x0000, TAG, `[Today] Loading color mode tab preference. current=${JSON.stringify(this.tabSelectedIndexes)}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when loading color mode tab index');
      return;
    }
    try {
      const storedValue = preferenceStore.getSync(PreferenceKeys.COLOR_MODE_TAB_INDEX, 0);
      const numericValue = typeof storedValue === 'number' ? storedValue : Number(storedValue);
      const sanitizedValue = this.normalizeColorModeTabIndex(numericValue);
      if (this.tabSelectedIndexes && this.tabSelectedIndexes.length > 0 && this.tabSelectedIndexes[0] === sanitizedValue) {
        hilog.info(0x0000, TAG, `[Today] Color mode tab preference already applied (${sanitizedValue}), skip update.`);
        return;
      }
      this.tabSelectedIndexes = [sanitizedValue];
      hilog.info(0x0000, TAG, `[Today] Color mode tab preference loaded and applied -> ${sanitizedValue}`);
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] color mode tab preference load.' + JSON.stringify(error))
    }
  }

  private persistColorModePreference(index: number): void {
    const sanitizedValue = this.normalizeColorModeTabIndex(index);
    hilog.info(0x0000, TAG, `[Today] Persisting color mode tab preference with index=${sanitizedValue}`);
    const preferenceStore = this.ensurePreferencesReady();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, '[Today] Preferences not initialized when persisting color mode tab index');
      return;
    }
    try {
      preferenceStore.putSync(PreferenceKeys.COLOR_MODE_TAB_INDEX, sanitizedValue);
      hilog.info(0x0000, TAG, `[Today] Color mode tab preference saved. requiresManualFlush=${this.preferencesUtil.requiresManualFlush()}`);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in [Today] color mode tab preference saved.' + JSON.stringify(error))
    }
  }

  private normalizeColorModeTabIndex(rawValue: number): number {
    if (!Number.isFinite(rawValue)) {
      return 0;
    }
    if (rawValue <= 0) {
      return 0;
    }
    if (rawValue >= 2) {
      return 2;
    }
    return Math.floor(rawValue);
  }

  private ensurePreferencesReady() {
    if (this.preferencesUtil.isInitialized()) {
      return this.preferencesUtil.getPreferences();
    }

    if (!this.preferencesUtil.isInitialized()) {
      hilog.error(0x0000, TAG, '[Today] Preferences initialization still unavailable after late init attempt');
      return null;
    }

    return this.preferencesUtil.getPreferences();
  }

  private applyTagMetadataToMatter(item: MatterItemModel, tagId: string | null): void {
    if (!item || !tagId) {
      return;
    }
    const matchedTag = this.tagData.find((tag: TagModel) => tag.id === tagId);
    if (!matchedTag) {
      return;
    }
    item.apply({
      label: matchedTag.name,
      labelColor: matchedTag.color || item.labelColor
    });
  }

  private handleVoiceFanIndexChange(previousIndex: number, newIndex: number): void {
    const voiceIndex: number = this.activeFanMenuItems.findIndex((menuItem: FanItemVO) =>
      menuItem.actionKind === FanActionKind.VOICE_INPUT);
    if (voiceIndex < 0) {
      return;
    }
    // 滑离语音项或未选中任何项：取消待启动的监听，并关闭进行中的会话、清空已识别内容
    if (newIndex !== voiceIndex) {
      this.cancelScheduledVoiceStart();
      if (this.voiceInputController.getState() !== VoiceInputState.IDLE) {
        this.voiceInputController.cancel();
        this.voiceInterimText = '';
        this.syncVoiceInputOverlay();
      }
      return;
    }
    if (previousIndex === voiceIndex) {
      return;
    }
    // 连续左右滑动会路过语音项，确认停留片刻后才真正开始监听
    this.scheduleVoiceStart(voiceIndex);
  }

  private scheduleVoiceStart(voiceIndex: number): void {
    this.cancelScheduledVoiceStart();
    this.voiceStartTimer = setTimeout(() => {
      this.voiceStartTimer = null;
      // 计时触发时再次确认扇形仍开着且选中项仍是语音项
      if (this.activeFanMenuItems.length === 0 || this.swissKnifeActiveIndex !== voiceIndex) {
        return;
      }
      const abilityContext: common.UIAbilityContext | null = this.resolveAbilityContext();
      if (!abilityContext) {
        hilog.error(0x0000, TAG, '[Today] Cannot start voice input without ability context');
        return;
      }
      void this.voiceInputController.start(abilityContext);
    }, VOICE_START_DWELL_MS);
  }

  private cancelScheduledVoiceStart(): void {
    if (this.voiceStartTimer !== null) {
      clearTimeout(this.voiceStartTimer);
      this.voiceStartTimer = null;
    }
  }

  private applyVoiceInputPrefill(text: string): void {
    // 识别引擎会在句末自动补标点，预填事项名称时去掉末尾的句号/点号
    const trimmed: string = text.trim().replace(/[。．.]+$/, '');
    if (trimmed.length === 0) {
      return;
    }
    this.resetFormState();
    this.inputActivityName = trimmed;
    this.isShow = true;
    this.refreshSheetHeight();
    hilog.info(0x0000, TAG, `[Today] Voice input prefilled add sheet, length=${trimmed.length}`);
  }

  private showVoiceInputNotice(notice: VoiceInputNotice): void {
    let message: Resource | null = null;
    if (notice === VoiceInputNotice.UNSUPPORTED) {
      message = $r('app.string.today_voice_input_unsupported');
    } else if (notice === VoiceInputNotice.PERMISSION_DENIED) {
      message = $r('app.string.today_voice_input_permission_denied');
    } else if (notice === VoiceInputNotice.PERMISSION_GRANTED_RETRY) {
      message = $r('app.string.today_voice_input_permission_granted_retry');
    } else if (notice === VoiceInputNotice.NO_SPEECH) {
      message = $r('app.string.today_voice_input_no_speech');
    } else if (notice === VoiceInputNotice.RECOGNITION_FAILED) {
      message = $r('app.string.today_voice_input_recognition_failed');
    }
    if (!message) {
      return;
    }
    promptAction.openToast({
      message: message,
      duration: 1500
    }).catch(() => {
      hilog.error(0x0000, TAG, '[Today] Failed to show voice input notice');
    });
  }

  private teardownVoiceInput(): void {
    this.cancelScheduledVoiceStart();
    this.voiceInputController.cancel();
    this.voiceInputController.release();
    this.voiceInterimText = '';
    this.removeVoiceInputOverlay();
  }

  private shouldShowVoiceInputOverlay(): boolean {
    return this.voiceInputState === VoiceInputState.REQUESTING_PERMISSION
      || this.voiceInputState === VoiceInputState.LISTENING
      || this.voiceInputState === VoiceInputState.FINALIZING;
  }

  private resolveVoiceInputBarWidth(): number {
    const hostContext = this.uiContext.getHostContext();
    if (!hostContext) {
      return this.viewportWidth;
    }
    const resourceManager = hostContext.resourceManager;
    const textFontSize: number = resourceManager
      .getNumber($r('app.float.today_voice_input_bar_text_font_size').id);
    const chromeWidth: number = resourceManager
      .getNumber($r('app.float.today_voice_input_bar_chrome_width').id);
    const maxWidthRatio: number = resourceManager
      .getNumber($r('app.float.today_voice_input_bar_max_width_ratio').id);
    const contentText: string | Resource = this.voiceInterimText.trim().length > 0
      ? this.voiceInterimText
      : this.resolveVoiceInputStatusText();
    const contentWidthPx: number = this.uiContext.getMeasureUtils().measureText({
      textContent: contentText,
      fontSize: `${textFontSize}px`,
      fontWeight: FontWeight.Medium
    });
    const contentDrivenWidth: number = this.uiContext
      .px2vp(contentWidthPx + chromeWidth);
    return Math.min(contentDrivenWidth, this.viewportWidth * maxWidthRatio);
  }

  private resolveVoiceInputStatusText(): Resource {
    if (this.voiceInputState === VoiceInputState.REQUESTING_PERMISSION) {
      return $r('app.string.today_voice_input_status_permission');
    }
    if (this.voiceInputState === VoiceInputState.FINALIZING) {
      return $r('app.string.today_voice_input_status_finalizing');
    }
    return $r('app.string.today_voice_input_status_listening');
  }

  // 测算扇形 overlay 中最高 item 的顶边 Y 坐标（vp）
  private computeFanItemsTopY(layoutConfig: FanOverlayLayoutConfig): number | null {
    if (layoutConfig.itemOffsets.length === 0) {
      return null;
    }
    let minTopY: number = Number.POSITIVE_INFINITY;
    layoutConfig.itemOffsets.forEach((offset: Point) => {
      // Bottom 对齐（居中扇形）：item 底边贴在 viewportHeight - itemMarginBottom，再叠加 offset；
      // TopStart 对齐（左右扇形）：offset 本身就是 item 顶边的视图坐标
      const topY: number = layoutConfig.stackAlignment === Alignment.Bottom
        ? this.viewportHeight - layoutConfig.itemMarginBottom - FAN_ITEM_ACTIVE_VIEW_SIZE + offset.y
        : offset.y;
      minTopY = Math.min(minTopY, topY);
    });
    return minTopY;
  }

  // 语音输入条底边与屏幕底边的距离：扇形最高 item 上方留出 fan_gap 间距
  private resolveVoiceInputBarBottomMargin(): number {
    const hostContext = this.uiContext.getHostContext();
    if (!hostContext) {
      return 0;
    }
    const resourceManager = hostContext.resourceManager;
    if (this.fanItemsTopY !== null && this.viewportHeight > 0) {
      const fanGap: number = resourceManager
        .getNumber($r('app.float.today_voice_input_bar_fan_gap').id);
      return this.viewportHeight - this.fanItemsTopY + fanGap;
    }
    return resourceManager.getNumber($r('app.float.today_voice_input_bar_bottom_margin').id);
  }

  private syncVoiceInputOverlay(): void {
    const visible: boolean = this.shouldShowVoiceInputOverlay();
    const params: VoiceInputOverlayParams = new VoiceInputOverlayParams(
      this.voiceInputState,
      this.voiceInterimText,
      this.viewportWidth,
      this.viewportHeight,
      this.resolveVoiceInputBarWidth(),
      this.resolveVoiceInputBarBottomMargin(),
      visible
    );
    if (this.voiceOverlayContent) {
      // 关闭时不直接卸载：先把 visible 置 false 让组件播放出场动画，动画结束后再 remove
      this.voiceOverlayContent.update(params);
      if (visible) {
        this.cancelVoiceOverlayRemoval();
      } else {
        this.scheduleVoiceOverlayRemoval();
      }
      return;
    }
    if (!visible) {
      return;
    }
    const overlayContent: ComponentContent<VoiceInputOverlayParams> = new ComponentContent(
      this.uiContext,
      wrapBuilder(buildVoiceInputOverlay),
      params
    );
    this.voiceOverlayContent = overlayContent;
    this.overlayNode.addComponentContent(overlayContent, 20);
    this.overlayNode.showComponentContent(overlayContent);
  }

  private scheduleVoiceOverlayRemoval(): void {
    this.cancelVoiceOverlayRemoval();
    this.voiceOverlayRemovalTimer = setTimeout(() => {
      this.voiceOverlayRemovalTimer = null;
      this.removeVoiceInputOverlay();
    }, VOICE_OVERLAY_EXIT_MS);
  }

  private cancelVoiceOverlayRemoval(): void {
    if (this.voiceOverlayRemovalTimer !== null) {
      clearTimeout(this.voiceOverlayRemovalTimer);
      this.voiceOverlayRemovalTimer = null;
    }
  }

  private removeVoiceInputOverlay(): void {
    this.cancelVoiceOverlayRemoval();
    if (!this.voiceOverlayContent) {
      return;
    }
    const overlayContent: ComponentContent<VoiceInputOverlayParams> = this.voiceOverlayContent;
    this.voiceOverlayContent = undefined;
    try {
      this.overlayNode.hideComponentContent(overlayContent);
    } catch (error) {
      hilog.warn(0x0000, TAG, `Failed to hide voice input overlay: ${JSON.stringify(error)}`);
    }
    try {
      this.overlayNode.removeComponentContent(overlayContent);
    } catch (error) {
      hilog.warn(0x0000, TAG, `Failed to remove voice input overlay: ${JSON.stringify(error)}`);
    }
  }

  private handleSwissKnifePick(item: FanItemVO): void {
    if (item.actionKind === FanActionKind.VOICE_INPUT) {
      if (this.voiceInputController.isActive()) {
        this.voiceInputController.stopAndFinalize();
        return;
      }
      promptAction.openToast({
        message: $r('app.string.today_voice_input_hint_retry'),
        duration: 1500
      }).catch(() => {
        hilog.error(0x0000, TAG, '[Today] Failed to show voice input retry hint');
      });
      return;
    }
    // void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    if (item.directRecordData) {
      void this.handleDirectRecordFanItem(item);
      return;
    }
    hilog.warn(0x0000, TAG, `[Today] Fan item without direct record data selected: ${item.id}`);
  }

  private async handleDirectRecordFanItem(item: FanItemVO): Promise<void> {
    const directRecordData = item.directRecordData;
    if (!directRecordData) {
      return;
    }

    const activityName = item.label ? item.label.trim() : '';
    if (!activityName) {
      hilog.warn(0x0000, TAG, '[Today] Direct record fan item has empty label, skip creating activity');
      return;
    }

    try {
      const tagId: string | null = directRecordData.tagId ?? null;
      const stateManager = MatterItemStateManager.getInstance();
      const currentRunningId: string = stateManager.getCurrentRunningItemId();
      const hasRunningMatter: boolean = typeof currentRunningId === 'string' && currentRunningId.trim().length > 0;
      const suppressSyncPush: boolean = directRecordData.autoStart !== false && !hasRunningMatter;
      const newActivity: MatterItemModel | null = await todayActivityService.createNewTodayActivity(
        activityName,
        tagId,
        suppressSyncPush
      );

      if (!newActivity) {
        hilog.error(0x0000, TAG, `[Today] Failed to create direct record activity: ${activityName}`);
        promptAction.openToast({
          message: '创建快捷事项失败',
          duration: 1000
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error in creating quick item')
        });
        return;
      }

      this.applyTagMetadataToMatter(newActivity, tagId);

      this.getUIContext().animateTo({
        duration: 300,
        curve: curves.springMotion()
      }, async () => {
        let startedDirectly = false;
        if (!hasRunningMatter) {
          startedDirectly = await this.startNewlyCreatedActivity(newActivity);
          if (!startedDirectly) {
            hilog.warn(0x0000, TAG, `[Today] Direct start failed for ${newActivity.id}, fallback to TODO list.`);
          }
        } else {
          hilog.info(0x0000, TAG, `[Today] Skip auto-start for ${newActivity.id}, running matter detected: ${currentRunningId}`);
        }

        if (!startedDirectly) {
          addMatterToList(this.unDoMatterData, newActivity, true);
          addMatterToList(this.matterData, newActivity, true);
          // this.syncMatterStorage({
          //   updateMatterData: true,
          //   updateDoneMatterData: false,
          //   updateUnDoMatterData: true
          // });
          hilog.info(0x0000, TAG, `[Today] Direct record activity ${newActivity.id} placed in TODO list.`);
          // 头插到 undo 顶部，滚动使其可见
          this.scrollMatterListToTop();
        } else {
          hilog.info(0x0000, TAG, `[Today] Direct record activity ${newActivity.id} started immediately.`);
          setTimeout(() => {
            this.scrollMatterListToTop();
          }, 500);
        }

        const toastMessage: string = startedDirectly
          ? `${activityName}已创建并开始`
          : hasRunningMatter
            ? `已有事项正在进行，${activityName}已添加待办`
            : `${activityName}已添加待办`;

        promptAction.openToast({
          message: toastMessage,
          duration: 1000
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error in auto start item')
        });
      });
    } catch (error) {
      hilog.error(0x0000, TAG, `[Today] Error creating direct record activity ${activityName}: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '创建快捷事项时发生错误',
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in auto start item')
      });
    }
  }

  // 根据全局坐标计算激活的扇形索引（使用成员变量，不依赖参数）
  private computeActiveIndexFromGlobalPosition(globalX: number, globalY: number): number {
    const itemCount: number = this.activeFanMenuItems.length;
    const center: Point | null = this.swissKnifeCenter;
    const globalPoint: Point = { x: globalX, y: globalY };

    return computeActiveFanSectorIndex(
      globalPoint,
      center,
      this.activeFanStartAngle,
      this.activeFanSweepAngle,
      itemCount,
      this.fanInnerRadius,
      this.fanOuterRadius,
      this.activeFanReverseSectorOrder
    );
  }

  private buildActiveFanMenuItems(): FanItemVO[] {
    const quickItems: FanItemVO[] = this.swissKnifeItems.slice(0, MAX_QUICK_FAN_ITEMS);
    const voiceItem: FanItemVO = {
      icon: this.resolveString($r('app.string.today_voice_input_icon')),
      label: this.resolveString($r('app.string.today_voice_input_action')),
      id: VOICE_INPUT_FAN_ITEM_ID,
      actionKind: FanActionKind.VOICE_INPUT,
      tagMeta: null
    };
    const voiceInsertIndex: number = Math.min(2, quickItems.length);
    return quickItems.slice(0, voiceInsertIndex)
      .concat([voiceItem])
      .concat(quickItems.slice(voiceInsertIndex));
  }

  private resolveFanAngles(placement: FanPlacement): GeneratedTypeLiteralInterface_1 {
    if (placement === FanPlacement.Center) {
      return {
        start: DEFAULT_START_ANGLE,
        sweep: DEFAULT_SWEEP_ANGLE
      };
    }

    if (placement === FanPlacement.Left) {
      return {
        start: -Math.PI / 2,
        sweep: Math.PI / 2
      };
    }

    return {
      start: -Math.PI,
      sweep: Math.PI / 2
    };
  }

  private resolveFanPlacement(center: Point): FanPlacement {
    const align: FlexAlign = this.resolveHoldingHandAlign();
    if (align === FlexAlign.Start) {
      return FanPlacement.Left;
    }
    if (align === FlexAlign.End) {
      return FanPlacement.Right;
    }
    if (this.viewportWidthPx > 0) {
      const leftLimit: number = this.fanRadius;
      const rightLimit: number = this.viewportWidthPx - this.fanRadius;
      if (rightLimit > leftLimit) {
        if (center.x <= leftLimit) {
          return FanPlacement.Left;
        }
        if (center.x >= rightLimit) {
          return FanPlacement.Right;
        }
      }
    }
    return FanPlacement.Center;
  }

  private resolveFanExtraOffset(placement: FanPlacement): Point {
    if (placement === FanPlacement.Center) {
      return { x: 0, y: 10 };
    }

    if (placement === FanPlacement.Left) {
      // 左侧与右侧相反方向偏移，确保与球体的相对间距一致
      return { x: 12, y: -10 };
    }

    return { x: 12, y: -10 };
  }

  private buildFanOverlayLayout(center: Point): FanOverlayLayoutConfig {
    const placement: FanPlacement = this.resolveFanPlacement(center);
    const itemCount: number = this.activeFanMenuItems.length;
    if (placement === FanPlacement.Center) {
      const angles: GeneratedTypeLiteralInterface_1 = this.resolveFanAngles(placement);
      const layoutPoints: Point[] = computeLegacyFanLayout(center, itemCount);
      return {
        placement,
        start: angles.start,
        sweep: angles.sweep,
        layoutPoints,
        itemOffsets: computeLegacyRenderOffsets(itemCount),
        stackAlignment: Alignment.Bottom,
        itemMarginBottom: 75,
        reverseSectorOrder: false
      };
    }

    const rightAngles: GeneratedTypeLiteralInterface_1 = this.resolveFanAngles(FanPlacement.Right);
    const baseLayoutPoints: Point[] = computeFanLayout(
      center,
      rightAngles.start,
      rightAngles.sweep,
      this.fanRadius,
      itemCount
    );
    const baseOffsets: Point[] = computeFanItemViewPositions(baseLayoutPoints, center);
    const rightExtraOffset: Point = this.resolveFanExtraOffset(FanPlacement.Right);
    const rightItemOffsets: Point[] = baseOffsets.map((point: Point): Point => ({
      x: point.x + rightExtraOffset.x,
      y: point.y + rightExtraOffset.y
    }));

    if (placement === FanPlacement.Right) {
      return {
        placement,
        start: rightAngles.start,
        sweep: rightAngles.sweep,
        layoutPoints: baseLayoutPoints,
        itemOffsets: rightItemOffsets,
        stackAlignment: Alignment.TopStart,
        itemMarginBottom: 0,
        reverseSectorOrder: false
      };
    }
    const leftAngles: GeneratedTypeLiteralInterface_1 = this.resolveFanAngles(FanPlacement.Left);
    const leftLayoutPointsRaw: Point[] = computeFanLayout(
      center,
      leftAngles.start,
      leftAngles.sweep,
      this.fanRadius,
      itemCount
    );
    const leftOffsetsRaw: Point[] = computeFanItemViewPositions(leftLayoutPointsRaw, center);
    const leftExtraOffset: Point = this.resolveFanExtraOffset(FanPlacement.Left);
    const leftLayoutPoints: Point[] = leftLayoutPointsRaw.slice().reverse();
    const leftItemOffsets: Point[] = leftOffsetsRaw.slice().reverse().map((point: Point): Point => ({
      x: point.x + leftExtraOffset.x,
      y: point.y + leftExtraOffset.y
    }));

    return {
      placement,
      start: leftAngles.start,
      sweep: leftAngles.sweep,
      layoutPoints: leftLayoutPoints,
      itemOffsets: leftItemOffsets,
      stackAlignment: Alignment.TopStart,
      itemMarginBottom: 0,
      reverseSectorOrder: true
    };
  }

  private openSwissKnife(center: Point): void {
    this.closeSwissKnife();
    this.activeFanMenuItems = this.buildActiveFanMenuItems();
    if (this.activeFanMenuItems.length === 0) {
      return;
    }
    this.pendingSwissKnifeIndex = -1;
    const layoutConfig: FanOverlayLayoutConfig = this.buildFanOverlayLayout(center);
    const firstOffset: Point | undefined = layoutConfig.itemOffsets.length > 0
      ? layoutConfig.itemOffsets[0]
      : undefined;
    const firstLayoutPoint: Point | undefined = layoutConfig.layoutPoints.length > 0
      ? layoutConfig.layoutPoints[0]
      : undefined;
    const offsetDeltaX: number = firstOffset && firstLayoutPoint
      ? firstOffset.x - firstLayoutPoint.x
      : 0;
    const offsetDeltaY: number = firstOffset && firstLayoutPoint
      ? firstOffset.y - firstLayoutPoint.y
      : 0;
    let minLayoutX: number = Number.POSITIVE_INFINITY;
    let maxLayoutX: number = Number.NEGATIVE_INFINITY;
    let minOffsetX: number = Number.POSITIVE_INFINITY;
    let maxOffsetX: number = Number.NEGATIVE_INFINITY;
    layoutConfig.layoutPoints.forEach((point: Point) => {
      minLayoutX = Math.min(minLayoutX, point.x);
      maxLayoutX = Math.max(maxLayoutX, point.x);
    });
    layoutConfig.itemOffsets.forEach((point: Point) => {
      minOffsetX = Math.min(minOffsetX, point.x);
      maxOffsetX = Math.max(maxOffsetX, point.x);
    });
    hilog.info(0x0000, TAG,
      `[Today] fan overlay placement=${layoutConfig.placement}, center=(${center.x}, ${center.y}), ` +
        `firstLayout=${firstLayoutPoint ? `(${firstLayoutPoint.x}, ${firstLayoutPoint.y})` : 'none'}, ` +
        `firstOffset=${firstOffset ? `(${firstOffset.x}, ${firstOffset.y})` : 'none'}, ` +
        `delta=(${offsetDeltaX}, ${offsetDeltaY}), ` +
        `layoutX=[${minLayoutX}, ${maxLayoutX}], offsetX=[${minOffsetX}, ${maxOffsetX}]`);

    // 保存 overlay 配置信息，用于 PanGesture 中计算选中索引
    this.swissKnifeCenter = center;
    this.swissKnifeLayoutPoints = layoutConfig.layoutPoints;
    this.fanItemsTopY = this.computeFanItemsTopY(layoutConfig);
    this.activeFanStartAngle = layoutConfig.start;
    this.activeFanSweepAngle = layoutConfig.sweep;
    this.activeFanReverseSectorOrder = layoutConfig.reverseSectorOrder;

    const params: FanOverlayParams = new FanOverlayParams(
      center,
      layoutConfig.start,
      layoutConfig.sweep,
      this.fanRadius,
      this.fanInnerRadius,
      this.fanOuterRadius,
      this.activeFanMenuItems,
      layoutConfig.layoutPoints,
      layoutConfig.itemOffsets,
      layoutConfig.stackAlignment,
      layoutConfig.itemMarginBottom,
      layoutConfig.reverseSectorOrder,
      (item: FanItemVO) => this.handleSwissKnifePick(item),
      () => this.closeSwissKnife()
    );

    const componentContent: ComponentContent<FanOverlayParams> = new ComponentContent(
      this.uiContext,
      wrapBuilder(buildFanOverlay),
      params
    );

    this.content = componentContent;
    this.fanOverlayParams = params;
    this.overlayNode.addComponentContent(componentContent, 10);
    this.overlayNode.showComponentContent(componentContent);
    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
  }

  private closeSwissKnife(): void {
    this.cancelScheduledVoiceStart();
    // 收尾中的识别会话不能被扇形关闭打断；仅取消尚未进入 finalizing 的会话
    if (this.voiceInputController.getState() === VoiceInputState.LISTENING
      || this.voiceInputController.getState() === VoiceInputState.REQUESTING_PERMISSION) {
      this.voiceInputController.cancel();
      this.voiceInterimText = '';
    }
    this.swissKnifeCenter = null;
    this.swissKnifeLayoutPoints = [];
    this.fanItemsTopY = null;
    this.activeFanMenuItems = [];
    this.activeFanStartAngle = DEFAULT_START_ANGLE;
    this.activeFanSweepAngle = DEFAULT_SWEEP_ANGLE;
    this.activeFanReverseSectorOrder = false;
    this.pendingSwissKnifeIndex = -1;
    AppStorage.setOrCreate('swissKnifeActiveIndex', -1);
    if (!this.content) {
      return;
    }

    const overlayContent: ComponentContent<FanOverlayParams> = this.content;
    const closingParams: FanOverlayParams | null = this.fanOverlayParams;
    this.content = undefined;
    this.fanOverlayParams = null;

    if (closingParams) {
      // 先置为不可见，让扇形 item 的退场动画（100ms 同时缩小）播完，再真正卸载 overlay
      try {
        overlayContent.update(closingParams.withVisible(false));
      } catch (error) {
        hilog.warn(0x0000, TAG, `Failed to update swiss knife overlay visibility: ${JSON.stringify(error)}`);
      }
      const exitDelay: number = FAN_EXIT_ANIMATION_MS + FAN_EXIT_EXTRA_MS;
      setTimeout(() => {
        try {
          this.overlayNode.hideComponentContent(overlayContent);
        } catch (error) {
          hilog.warn(0x0000, TAG, `Failed to hide swiss knife overlay: ${JSON.stringify(error)}`);
        }
        try {
          this.overlayNode.removeComponentContent(overlayContent);
        } catch (error) {
          hilog.warn(0x0000, TAG, `Failed to remove swiss knife overlay: ${JSON.stringify(error)}`);
        }
      }, exitDelay);
      return;
    }

    try {
      this.overlayNode.hideComponentContent(overlayContent);
    } catch (error) {
      hilog.warn(0x0000, TAG, `Failed to hide swiss knife overlay: ${JSON.stringify(error)}`);
    }

    try {
      this.overlayNode.removeComponentContent(overlayContent);
    } catch (error) {
      hilog.warn(0x0000, TAG, `Failed to remove swiss knife overlay: ${JSON.stringify(error)}`);
    }
  }

  private finalizeSwissKnifeSelection(): void {
    const selectedIndex: number = this.pendingSwissKnifeIndex >= 0
      ? this.pendingSwissKnifeIndex
      : this.swissKnifeActiveIndex;
    hilog.info(0x0000, TAG, `[Today] finalizeSwissKnifeSelection -> pending=${this.pendingSwissKnifeIndex}, storage=${this.swissKnifeActiveIndex}, selected=${selectedIndex}`);
    if (selectedIndex >= 0 && selectedIndex < this.activeFanMenuItems.length) {
      const selectedItem: FanItemVO | undefined = this.activeFanMenuItems[selectedIndex];
      if (selectedItem) {
        this.handleSwissKnifePick(selectedItem);
      }
    }
    this.closeSwissKnife();
    this.longPressActive = false;
    this.lastLongPressAt = Date.now();
    this.pendingSwissKnifeIndex = -1;
  }

  private startTagShakeAnimation(): void {
    if (!this.shouldRunTagShakeAnimation()) {
      return;
    }
    if (this.isTagShakeRunning) {
      return;
    }

    this.isTagShakeRunning = true;
    this.scheduleNextTagShake(this.tagShakeAmplitude);
  }

  private stopTagShakeAnimation(): void {
    if (!this.isTagShakeRunning && this.tagShakeAngle === 0) {
      return;
    }

    this.isTagShakeRunning = false;

    const uiContext = this.getUIContext();
    if (uiContext) {
      uiContext.animateTo({ duration: 0 }, () => {
        this.tagShakeAngle = 0;
      });
    } else {
      this.tagShakeAngle = 0;
    }
  }

  private getTagShakePhase(index: number): number {
    return index % 2 === 0 ? 1 : -1;
  }

  private scheduleNextTagShake(targetAngle: number): void {
    if (!this.isTagShakeRunning || !this.shouldRunTagShakeAnimation()) {
      return;
    }

    const uiContext = this.getUIContext();
    if (!uiContext) {
      this.isTagShakeRunning = false;
      return;
    }

    uiContext.animateTo({
      duration: this.tagShakeFrameDuration,
      curve: Curve.Linear,
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        if (!this.isTagShakeRunning || !this.shouldRunTagShakeAnimation()) {
          return;
        }
        const nextAngle = targetAngle === this.tagShakeAmplitude ? -this.tagShakeAmplitude : this.tagShakeAmplitude;
        this.scheduleNextTagShake(nextAngle);
      }
    }, () => {
      if (!this.isTagShakeRunning || !this.shouldRunTagShakeAnimation()) {
        return;
      }
      this.tagShakeAngle = targetAngle;
    });
  }

  private handleItemEndAppear(itemId: string): void {
    if (this.activeItemEndId === itemId) {
      return;
    }

    this.activeItemEndId = itemId;
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
  }

  private handleItemEndDisappear(itemId: string): void {
    if (this.activeItemEndId === itemId) {
      this.activeItemEndId = null;
    }
  }

  private closeAllSwipeActions(): void {
    try {
      this.listScroller?.closeAllSwipeActions();
    } catch (error) {
      hilog.error(0x0000, TAG, 'error in closing swipe action')
    }
  }

  /**
   * 分享事项的全部已结束 TimeRecord 到 GoalFighter（batch 模式）。
   * 正在计时的 open record 会被过滤，正在计中的事项仍可分享历史记录。
   */
  private async handleShareMatterToGoalFighter(item: MatterItemModel): Promise<void> {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      hilog.error(0x0000, TAG, 'share aborted: host context missing');
      return;
    }
    const abilityContext = hostContext as common.UIAbilityContext;
    try {
      const records = await todayActivityService.getTimeRecordsByActivityId(item.id);
      const envelope = buildFlowDiaryImportEnvelope('batch', records, item.id, item.title,
        generateFlowDiaryImportRequestId());
      if (envelope === null) {
        promptAction.openToast({
          message: $r('app.string.today_share_no_finished_records'),
          duration: 1000
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error in showing no-records toast')
        })
        hilog.info(0x0000, TAG, `no finished time records to share for activity ${item.id}`)
        return;
      }
      const result = await goalFighterShareService.share(abilityContext, envelope);
      hilog.info(0x0000, TAG, `goalfighter share finished, outcome=${result.outcome}, records=${envelope.records.length}`)
    } catch (error) {
      hilog.error(0x0000, TAG, `goalfighter share failed: ${JSON.stringify(error)}`)
      promptAction.openToast({
        message: $r('app.string.today_share_failed_toast'),
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in showing share-failed toast')
      })
    }
  }

  private refreshGoalFighterAvailability(): void {
    this.isGoalFighterAvailable = goalFighterShareService.isGoalFighterAvailable();
  }

  private isCurrentRunningItem(itemId: string): boolean {
    if (!itemId) {
      return false;
    }

    const stateManager = MatterItemStateManager.getInstance();
    if (stateManager.isItemRunning(itemId)) {
      return true;
    }

    const session = recordingSessionStore.snapshot();
    return session !== null && session.itemId === itemId;
  }

  /**
   * 从数据库加载标签数据
   */
  async loadTagsFromDatabase(): Promise<void> {
    try {
      this.tagData = await tagService.getAllTagsForUI();
      hilog.info(0x0000, TAG, `Loaded ${this.tagData.length} tags from database`);
      this.rebuildSwissKnifeItemVOs();
    } catch (error) {
      hilog.error(0x0000, TAG, `Error loading tags: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 处理"添加"按钮的点击事件。
   * @param name - 活动的名称。
   * @param tagId - 所选标签的ID，如果没有选择则为 null。
   */
  async handleAddActivityButtonClick(name: string, tagId: string | null): Promise<void> {
    // 验证输入
    if (!name || name.trim().length === 0) {
      hilog.error(0x0000, TAG, '活动名称不能为空');
      return;
    }

    hilog.info(0x0000, TAG, `User trying to add activity: ${name} with tagId: ${tagId}`);

    try {
      const shouldAutoStart = this.isToggleOn;
      const newActivity: MatterItemModel | null = await todayActivityService.createNewTodayActivity(
        name.trim(),
        tagId,
        shouldAutoStart
      );
      hilog.info(0x0000, TAG, `[Today] New activity auto-start decision -> shouldAutoStart=${shouldAutoStart}, isToggleOn=${this.isToggleOn}, directStartEnabled=${this.directStartEnabled}`);

      if (newActivity) {
        hilog.info(0x0000, TAG, 'Activity added successfully. Adding to list...');
        this.getUIContext().animateTo({
          duration: 300,
          curve: curves.springMotion()
        }, async () => {
          let autoStartSucceeded = false;

          if (shouldAutoStart) {
            autoStartSucceeded = await this.startNewlyCreatedActivity(newActivity);
          }

          if (!shouldAutoStart || !autoStartSucceeded) {
            addMatterToList(this.unDoMatterData, newActivity, true);
            addMatterToList(this.matterData, newActivity, true);
            // Only sync the arrays that actually changed - doneMatterData is unchanged
            // This prevents unnecessary updates to TodayDataPanel which watches doneMatterData
            // const syncOptions: SyncMatterStorageOptions = {
            //   updateMatterData: true,
            //   updateDoneMatterData: false,
            //   updateUnDoMatterData: true
            // };
            // this.syncMatterStorage(syncOptions);
            hilog.info(0x0000, TAG, `Activity added to unDoMatterData. Total unDo items: ${this.unDoMatterData.length}`);
            this.syncAllAnimatedLists(false);
            // 新建事项头插到 undo 顶部，滚动使其可见
            this.scrollMatterListToTop();
          } else {
            hilog.info(0x0000, TAG, `Auto-start succeeded for activity ${newActivity.id}, relying on refresh to update lists.`);
            // 新建即启动（含语音输入确认路径）：事项进入 done 顶部，滚动使其可见
            setTimeout(() => {
              this.scrollMatterListToTop();
            }, 500);
          }

          if (!autoStartSucceeded) {
            void this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
          }
        });
      } else {
        hilog.error(0x0000, TAG, 'Failed to add the new activity to the database.');
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Error adding activity: ${JSON.stringify(error)}`);
    }
  }

  private async startNewlyCreatedActivity(item: MatterItemModel): Promise<boolean> {
    try {
      const stateManager = MatterItemStateManager.getInstance();
      const snapshot = await stateManager.start(item);

      if (!snapshot) {
        hilog.warn(0x0000, TAG, `Unable to auto-start activity ${item.id}, another matter might already be running.`);
        return false;
      }
      liveViewController.startLiveView(0, item.title);
      hilog.info(0x0000, TAG, `Auto-started activity ${item.id} successfully.`);
      await this.updateMatterItems();
      return true;
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to auto-start activity ${item.id}: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '自动开始事项失败',
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in auto start item')
      });
      return false;
    }
  }

  private confirmDeleteMatter(item: MatterItemModel): void {
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    if (this.isCurrentRunningItem(item.id)) {
      promptAction.openToast({
        message: '请先暂停事项！',
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in stopping item')
      });
      hilog.warn(0x0000, TAG, `deleting item ${item.id}, ${item.title} while running.`);
      return;
    }

    this.closeAllSwipeActions();
    this.getUIContext().showAlertDialog(
      {
        title: '是否确认删除事项？',
        message: '事项删除后，相关时间记录也会被删除',
        autoCancel: true,
        alignment: DialogAlignment.Center,
        gridCount: 4,
        offset: { dx: 0, dy: -20 },
        primaryButton: {
          value: '取消',
          action: () => {
            hilog.info(0x0000, TAG, 'cancel delete item');
            this.closeAllSwipeActions();
          }
        },
        secondaryButton: {
          enabled: true,
          defaultFocus: true,
          style: DialogButtonStyle.HIGHLIGHT,
          value: '确认',
          action: () => {
            hilog.info(0x0000, TAG, 'delete current item' + JSON.stringify(item));
            void this.handleListItemButtonClick(item);
            this.closeAllSwipeActions();
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
    );
  }

  async handleListItemButtonClick(item: MatterItemModel): Promise<void> {
    if (this.isCurrentRunningItem(item.id)) {
      promptAction.openToast({
        message: '请先暂停事项！',
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in stopping item')
      })

      hilog.warn(0x0000, TAG, `deleting item ${item.id}, ${item.title} while running.`)
      return;
    }

    hilog.info(0x0000, TAG, `User trying to delete activity: ${item.id}, ${item.title}`);

    try {
      // 调用服务层删除活动
      const deleteResult = await todayActivityService.deleteActivity(item.id);

      if (deleteResult) {
        hilog.info(0x0000, TAG, `Activity deleted successfully: ${item.id}`);
        this.getUIContext().animateTo({
          duration: 300,
          curve: curves.springMotion()
        }, () => {
          const removedFromDone = removeMatterFromList(this.doneMatterData, item.id);
          if (removedFromDone) {
            hilog.info(0x0000, TAG, `Removed item from doneMatterData. Total done items: ${this.doneMatterData.length}`);
          }

          const removedFromUndo = removeMatterFromList(this.unDoMatterData, item.id);
          if (removedFromUndo) {
            hilog.info(0x0000, TAG, `Removed item from unDoMatterData. Total unDo items: ${this.unDoMatterData.length}`);
          }

          const removedFromAll = removeMatterFromList(this.matterData, item.id);
          if (removedFromAll) {
            hilog.info(0x0000, TAG, `Removed item from matterData. Total items: ${this.matterData.length}`);
          }

          this.syncAllAnimatedLists(false);
          void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
        });

        promptAction.openToast({
          message: '事项已删除',
          duration: 1000
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error in deleting item')
        });
      } else {
        hilog.error(0x0000, TAG, `Failed to delete activity: ${item.id}`);

        // 显示失败提示
        promptAction.openToast({
          message: '删除事项失败',
          duration: 1000
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error in deleting item')
        });
        void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Error deleting activity: ${JSON.stringify(error)}`);

      // 显示错误提示
      promptAction.openToast({
        message: '删除事项时发生错误',
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in deleting item')
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    }
  }

  private showDeleteTagDialog(tag: TagModel, index: number): void {
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
          hilog.info(0x0000, TAG, `cancel delete tag ${tag.id}`);
        }
      },
      secondaryButton: {
        enabled: true,
        defaultFocus: true,
        style: DialogButtonStyle.HIGHLIGHT,
        value: '确认',
        action: () => {
          hilog.info(0x0000, TAG, `confirm delete tag ${tag.id}`);
          void this.handleDeleteTag(tag, index);
        }
      },
      cancel: () => {
        hilog.info(0x0000, TAG, 'Closed delete tag dialog');
      },
      onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
        hilog.info(0x0000, TAG, `Delete tag dialog onWillDismiss reason= ${dismissDialogAction.reason}`);
        if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
          dismissDialogAction.dismiss();
        }
        if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissDialogAction.dismiss();
        }
      }
    });
  }

  private async handleDeleteTag(tag: TagModel, index: number): Promise<void> {
    hilog.info(0x0000, TAG, `User trying to delete tag: ${tag.id}, ${tag.name}`);

    try {
      const deleteResult = await tagService.deleteTag(tag.id);

      if (!deleteResult) {
        hilog.warn(0x0000, TAG, `Failed to delete tag: ${tag.id}`);
        promptAction.openToast({
          message: '删除标签失败',
          duration: 1000
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error in deleting tags')
        });
        return;
      }

      if (!Array.isArray(this.tagData) || index < 0 || index >= this.tagData.length) {
        hilog.warn(0x0000, TAG, `Invalid delete index=${index}, tagDataLength=${this.tagData?.length ?? 0}`);
        return;
      }

      this.getUIContext().animateTo({
        duration: 300,
        curve: curves.springMotion()
      }, () => {
        const removedTag = this.tagData[index];
        if (!removedTag) {
          hilog.warn(0x0000, TAG, `Failed to locate tag at index=${index} during deletion animation`);
          return;
        }
        this.tagData.splice(index, 1);
        this.selectedTagIndex = resolveSelectedTagIndexAfterDeletion(this.selectedTagIndex, index);
        this.sheetHeight = this.computeAddSheetHeight(this.tagData.length);
        this.syncTagStorage();
        this.rebuildSwissKnifeItemVOs();
        const patchResult = patchMatterListsAfterTagDeletion({
          doneMatterData: this.doneMatterData,
          unDoMatterData: this.unDoMatterData,
          matterData: this.matterData,
          matterDataRevision: this.matterDataRevision
        }, tag.name, $r('app.color.text_tertiary'));
        this.doneMatterData = patchResult.doneMatterData;
        this.unDoMatterData = patchResult.unDoMatterData;
        this.matterData = patchResult.matterData;
        this.matterDataRevision = patchResult.matterDataRevision;
      });

      promptAction.openToast({
        message: '标签已删除',
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in deleting tag')
      });

      hilog.info(0x0000, TAG, `Tag deleted successfully: ${tag.id}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error deleting tag: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '删除标签时发生错误',
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in deleting tag')
      });
    }
  }

  private syncTagStorage(): void {
    AppStorage.setOrCreate('tagData', [...this.tagData]);
  }

  /**
   * Synchronizes local matter arrays with AppStorage.
   *
   * This method now accepts optional parameters to specify which arrays should be updated,
   * preventing unnecessary AppStorage writes that trigger @Watch observers.
   *
   * @param options - Optional object specifying which arrays to update
   * @param options.updateMatterData - Whether to update matterData (default: true)
   * @param options.updateDoneMatterData - Whether to update doneMatterData (default: true)
   * @param options.updateUnDoMatterData - Whether to update unDoMatterData (default: true)
   */
  // private syncMatterStorage(options?: SyncMatterStorageOptions): void {
  //   // Default to updating all if no options provided (backward compatibility)
  //   const opts = options || {};
  //   const updateMatterData = opts.updateMatterData !== undefined ? opts.updateMatterData : true;
  //   const updateDoneMatterData = opts.updateDoneMatterData !== undefined ? opts.updateDoneMatterData : true;
  //   const updateUnDoMatterData = opts.updateUnDoMatterData !== undefined ? opts.updateUnDoMatterData : true;
  //
  //   hilog.info(0x0000, TAG, `syncMatterStorage called with options: matterData=${updateMatterData}, doneMatterData=${updateDoneMatterData}, unDoMatterData=${updateUnDoMatterData}`);
  //
  //   if (updateMatterData) {
  //     AppStorage.setOrCreate('matterData', [...this.matterData]);
  //   }
  //   if (updateDoneMatterData) {
  //     AppStorage.setOrCreate('doneMatterData', [...this.doneMatterData]);
  //   }
  //   if (updateUnDoMatterData) {
  //     AppStorage.setOrCreate('unDoMatterData', [...this.unDoMatterData]);
  //   }
  // }

  /**
   * Normalize zero-duration items to TODO status
   * If an item has zero duration, it should be in TODO status and moved to undoMatterData
   * IMPORTANT: Skip normalization for items that are currently actively recording
   */
  private async normalizeZeroDurationItem(item: MatterItemModel): Promise<MatterItemModel> {
    try {
      if (item.durationInMilliseconds <= 0 && item.status !== MatterStatus.TODO) {
        const session = recordingSessionStore.snapshot();

        if (item.status === MatterStatus.RECORDING) {
          hilog.info(0x0000, TAG, `Skipping normalization for actively recording item ${item.id}`);
          return item;
        }

        if (session !== null && session.itemId === item.id) {
          hilog.info(0x0000, TAG, `Skipping normalization for current running item ${item.id}`);
          return item;
        }

        // Additional check: Verify if there's an unfinished time record
        const rdbStoreUtil = RDBStoreUtil.getInstance();
        const latestRecord = await rdbStoreUtil.queryLatestTimeRecord(item.id);
        if (latestRecord && !latestRecord.endTime) {
          hilog.info(0x0000, TAG, `Skipping normalization for item ${item.id} with active time record`);
          return item;
        }

        // Only normalize if none of the above conditions are met
        hilog.info(0x0000, TAG, `Normalizing zero-duration item ${item.id} to TODO status`);

        const updateSuccess = await todayActivityService.updateActivityStatus(item.id, MatterStatus.TODO);
        if (updateSuccess) {
          item.status = MatterStatus.TODO;
          hilog.info(0x0000, TAG, `Successfully normalized item ${item.id} to TODO status`);
        } else {
          hilog.error(0x0000, TAG, `Failed to update status for item ${item.id}`);
        }
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Error normalizing zero-duration item ${item.id}: ${JSON.stringify(error)}`);
    }
    return item;
  }

  /**
   * 重置表单状态
   */
  private resetFormState(): void {
    this.inputActivityName = '';
    this.inputTagName = '';
    this.selectedTagIndex = -1;
    this.selectedLabelIndex = -1;
    this.refreshSheetHeight();
    this.isToggleOn = this.directStartEnabled;
  }

  private resolveTagIndexById(tagId: string): number {
    if (!tagId || tagId.length === 0) {
      return -1;
    }
    return this.tagData.findIndex((tag: TagModel) => tag.id === tagId);
  }

  private parseWidgetAddSheetPrefill(raw: string): WidgetAddSheetPrefillPayload | null {
    if (!raw || raw.length === 0) {
      return null;
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>;
      if (!parsed) {
        return null;
      }
      const activityRaw = parsed['activityName'];
      const tagIdRaw = parsed['tagId'];
      const autoStartRaw = parsed['autoStart'];

      const activityName = typeof activityRaw === 'string' ? activityRaw : '';
      const tagId = typeof tagIdRaw === 'string' ? tagIdRaw : '';
      let autoStart = this.directStartEnabled;
      if (typeof autoStartRaw === 'boolean') {
        autoStart = autoStartRaw;
      } else if (typeof autoStartRaw === 'string') {
        autoStart = autoStartRaw === 'true';
      }

      if (activityName.length === 0 && tagId.length === 0) {
        return null;
      }
      return {
        activityName: activityName,
        tagId: tagId,
        autoStart: autoStart
      };
    } catch (error) {
      hilog.error(0x0000, TAG, `[Today] parseWidgetAddSheetPrefill failed: ${JSON.stringify(error)}`);
      return null;
    }
  }

  private applyWidgetAddSheetPrefill(): void {
    const prefill = this.parseWidgetAddSheetPrefill(this.widgetAddSheetPrefillJson);
    this.widgetAddSheetPrefillJson = '';
    this.resetFormState();
    if (!prefill) {
      return;
    }
    this.inputActivityName = prefill.activityName;
    this.isToggleOn = prefill.autoStart;
    const tagIndex = this.resolveTagIndexById(prefill.tagId);
    if (tagIndex >= 0) {
      this.selectedTagIndex = tagIndex;
    }
  }

  private buildDesiredDoneMatterList(): MatterItemModel[] {
    return buildPinnedDoneMatterList(this.doneMatterData, this.animatedDoneMatterData);
  }

  private assignAnimatedMatterLists(): void {
    this.assignAnimatedDoneMatterList();
    this.assignAnimatedUnDoMatterList();
  }

  private assignAnimatedDoneMatterList(): void {
    this.animatedDoneMatterData = this.buildDesiredDoneMatterList();
    this.syncMatterItemNodeReferences('done');
  }

  private assignAnimatedUnDoMatterList(): void {
    this.animatedUnDoMatterData = [...this.unDoMatterData];
    this.syncMatterItemNodeReferences('undo');
  }

  private scheduleMatterListSync(): void {
    if (!this.matterListProjectionReady) {
      return;
    }
    if (this.isMatterPinTransitionActive) {
      this.pendingMatterListSync = true;
      return;
    }
    if (this.matterListSyncTimer >= 0) {
      clearTimeout(this.matterListSyncTimer);
    }
    this.matterListSyncTimer = setTimeout(() => {
      this.matterListSyncTimer = -1;
      this.reconcileAnimatedMatterLists();
    }, 0);
  }

  private reconcileAnimatedMatterLists(): void {
    const desiredDone: MatterItemModel[] = this.buildDesiredDoneMatterList();
    const recordingItem: MatterItemModel | undefined = desiredDone.find(
      (item: MatterItemModel) => item.status === MatterStatus.RECORDING
    );
    // 仅跨组开始（undo -> done）播放置顶转场；组内恢复保持原位，仅刷新状态
    if (recordingItem !== undefined && this.shouldAnimateMatterPin(recordingItem.id)) {
      if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
        this.startDualLaneMatterPinAnimation(recordingItem.id);
      } else {
        this.startCrossGroupMatterPinAnimation(recordingItem.id);
      }
      return;
    }

    this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 0.9) }, () => {
      this.assignAnimatedMatterLists();
    });
  }

  private shouldAnimateMatterPin(itemId: string): boolean {
    return this.animatedUnDoMatterData.some((item: MatterItemModel) => item.id === itemId);
  }

  /**
   * 跨组置顶（undo -> done）的 LG 双列路径：双列网格中收起单卡高度无法平滑合并行高
   * （行高由同行另一张卡撑住），pin slot 整行展开又会把两列同时往下推、留出半行空洞。
   * 改为单事务重组：undo 卡片以淡出+下移转场退出，done 首位卡片以淡入转场进入，
   * 其余卡片的格位迁移由 List 的布局动画承接，同时滚动到顶部。
   */
  private startDualLaneMatterPinAnimation(itemId: string): void {
    this.matterPinAnimationToken++;
    const animationToken: number = this.matterPinAnimationToken;
    // 不设置 pinningMatterId：双列路径不走折叠态，让 undo 卡片正常播放退出转场
    this.isMatterPinTransitionActive = true;
    this.pinEntranceItemId = itemId;
    this.scrollMatterListToTop();

    this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 0.9) }, () => {
      this.assignAnimatedMatterLists();
    });

    setTimeout(() => {
      if (animationToken !== this.matterPinAnimationToken) {
        return;
      }
      this.pinEntranceItemId = '';
      this.finishMatterPinAnimation(animationToken, false);
    }, PIN_ENTRANCE_CLEANUP_MS);
  }

  private finishMatterPinAnimation(animationToken: number, scrollToTop: boolean): void {
    if (animationToken !== this.matterPinAnimationToken) {
      return;
    }
    this.pinningMatterId = '';
    this.isMatterPinTransitionActive = false;
    if (scrollToTop) {
      this.scrollMatterListToTop();
    }
    if (this.pendingMatterListSync) {
      this.pendingMatterListSync = false;
      this.scheduleMatterListSync();
    }
  }

  /**
   * 跨组置顶（undo -> done）的 SM/MD 单列路径：高度动画由 done 分组顶部的常驻 pin slot 承载。
   * 文档依据：属性动画要求组件有已提交布局（常驻组件），新生节点直接以最终值布局；
   * 出现/消失的组件应使用转场。时序：undo 内折叠与 done 顶部 slot 展开同时开始
   * （同一条 springMotion 曲线，同一帧收尾），滚动在 300ms 后并行启动；
   * 折叠收尾瞬间 undo 移除卡片 + done 同帧交换 slot 与卡片（净布局零变化），卡片用转场淡入。
   */
  private startCrossGroupMatterPinAnimation(itemId: string): void {
    this.matterPinAnimationToken++;
    const animationToken: number = this.matterPinAnimationToken;
    this.pinningMatterId = itemId;
    this.isPinningMatterCollapsed = false;
    this.isMatterPinTransitionActive = true;
    // 卡片插入 done 首位后是否带底部间距（done 原本为空则它是最后一项，无间距）
    this.pinSlotWithSpacing = this.animatedDoneMatterData.length > 0;
    this.pinSlotExpanded = false;
    this.pinEntranceItemId = '';

    // springMotion 的 duration 不生效，实际 settle 约 860ms；
    // 折叠 300ms 后主要视觉变化已完成，提前并行启动滚动（300+100+500≈900ms），
    // 折叠收尾时滚动刚好完成，消除"停顿一会才滚动"的体感
    setTimeout(() => {
      if (animationToken !== this.matterPinAnimationToken) {
        return;
      }
      this.scrollMatterListToTop();
    }, 300);

    // slot 展开与折叠同时开始：同一条 springMotion 曲线则同一帧收尾，
    // undo 卡片消失的瞬间 done 顶部空间刚好就位，卡片立即插入淡入，中间无停顿
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.7)
    }, () => {
      // slot 是常驻节点，高度动画有已提交起点
      this.pinSlotExpanded = true;
    });

    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.7),
      onFinish: () => {
        this.swapCollapsedMatterIntoPinSlot(animationToken);
      }
    }, () => {
      this.isPinningMatterCollapsed = true;
    });
  }

  private swapCollapsedMatterIntoPinSlot(animationToken: number): void {
    if (animationToken !== this.matterPinAnimationToken) {
      return;
    }

    // 卡片已在 undo 折叠为 0 高度，移除无占位变化；slot 已同步长开，直接交换插入
    this.assignAnimatedUnDoMatterList();
    this.insertPinnedMatterIntoSlot(animationToken);
  }

  private insertPinnedMatterIntoSlot(animationToken: number): void {
    if (animationToken !== this.matterPinAnimationToken) {
      return;
    }

    // 同一同步事务：卡片以完整高度插入 done + slot 瞬时归零，净布局零变化
    this.isPinningMatterCollapsed = false;
    this.pinEntranceItemId = this.pinningMatterId;
    this.assignAnimatedDoneMatterList();
    this.pinSlotExpanded = false;
    this.finishMatterPinAnimation(animationToken, false);
    setTimeout(() => {
      if (animationToken !== this.matterPinAnimationToken) {
        return;
      }
      this.pinEntranceItemId = '';
    }, PIN_ENTRANCE_CLEANUP_MS);
  }

  private getDoneMatterItemTransition(itemId: string): TransitionEffect {
    if (itemId === this.pinEntranceItemId) {
      return this.pinEntranceTransition;
    }
    return this.getMatterListItemTransition();
  }

  private isMatterPinCollapsed(itemId: string): boolean {
    return this.isPinningMatterCollapsed && this.pinningMatterId === itemId;
  }

  private getMatterItemAnimatedHeight(itemId: string): number | Resource {
    // 高度折叠只在单列布局（SM/MD）生效；LG 双列行高由同行卡片撑住，折叠单卡无意义
    if (this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_LG && this.isMatterPinCollapsed(itemId)) {
      return 0;
    }
    return $r('app.float.today_matter_item_height');
  }

  private scrollMatterListToTop(): void {
    setTimeout(() => {
      this.listScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 500, curve: Curve.EaseInOut } });
    }, 100);
  }

  private getMatterItemBottomSpacing(items: MatterItemModel[], itemId: string): Resource {
    if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
      return this.getDualLaneMatterItemBottomSpacing(items, itemId);
    }
    const lastItem: MatterItemModel | undefined = items[items.length - 1];
    if (this.isMatterPinCollapsed(itemId) || lastItem === undefined || lastItem.id === itemId) {
      return $r('app.float.today_matter_item_spacing_none');
    }

    const itemBeforeLast: MatterItemModel | undefined = items[items.length - 2];
    const isGapBeforeCollapsedLastItem: boolean = itemBeforeLast !== undefined && itemBeforeLast.id === itemId &&
      this.isMatterPinCollapsed(lastItem.id);
    return isGapBeforeCollapsedLastItem ?
      $r('app.float.today_matter_item_spacing_none') : $r('app.float.today_matter_item_spacing');
  }

  // 双列布局的底部间距按"行"计算：最后一行的所有卡片（1~2 张）都不带底部间距，
  // 避免同一行左右两格间距不一致导致的组尾空白与行高抖动
  private getDualLaneMatterItemBottomSpacing(items: MatterItemModel[], itemId: string): Resource {
    const size: number = items.length;
    const lastRowStartIndex: number = size - (size % 2 === 0 ? 2 : 1);
    const itemIndex: number = items.findIndex((item: MatterItemModel) => item.id === itemId);
    return itemIndex >= lastRowStartIndex ?
      $r('app.float.today_matter_item_spacing_none') : $r('app.float.today_matter_item_spacing');
  }

  private getMatterListItemTransition(): TransitionEffect {
    // 折叠路径（SM/MD 单列置顶）中途重组列表时，其余卡片不播插入/移除转场；
    // 双列路径（LG）不设置 pinningMatterId，卡片正常播放退出/进入转场
    return this.pinningMatterId !== '' ? TransitionEffect.IDENTITY : this.matterListItemTransition;
  }

  private syncMatterItemNodeReferences(target: 'done' | 'undo'): void {
    const sourceList: MatterItemModel[] = target === 'done' ? this.animatedDoneMatterData : this.animatedUnDoMatterData;
    const isExpanded: boolean = this.matterExpandAnimationProps?.isExpandPageShow ?? false;
    const expandedItemId: string = this.matterExpandAnimationProps?.currentExpandingItemId ?? '';

    for (const item of sourceList) {
      const node = getMatterItemNode(item.id);
      if (!node) {
        continue;
      }
      const shouldBeExpanded = isExpanded && expandedItemId === item.id;
      node.update(item, shouldBeExpanded, this.isDarkTheme);
      if (shouldBeExpanded && this.matterExpandAnimationProps) {
        this.matterExpandAnimationProps.currentExpandingItem = item;
      }
    }
  }

  private syncAllAnimatedLists(animate: boolean = true): void {
    if (animate) {
      this.getUIContext().animateTo({ curve: curves.springMotion(0.35, 0.9) }, () => {
        this.assignAnimatedMatterLists();
      });
      return;
    }
    this.assignAnimatedMatterLists();
  }

  private onThemeChanged(): void {
    refreshAllMatterItemNodes(this.isDarkTheme);
  }

  private onDoneMatterDataChange(): void {
    this.scheduleMatterListSync();
  }

  private onUnDoMatterDataChange(): void {
    this.scheduleMatterListSync();
  }

  private async onMatterDataRevisionChange() {
    if (this.pendingRevisionSync) {
      return;
    }

    this.pendingRevisionSync = true;
    try {
      await this.updateMatterItems(false);
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh matter items after revision change: ${JSON.stringify(error)}`);
    } finally {
      this.pendingRevisionSync = false;
    }
  }

  private async updateMatterItems(publishRevision: boolean = true) {
    const rdbStoreUtil = RDBStoreUtil.getInstance();
    try {
      const recovered = await rdbStoreUtil.recoverArchivedActivitiesWithTodayRecords();
      if (recovered > 0) {
        hilog.info(0x0000, TAG, `Recovered ${recovered} archived activities before refreshing today list.`);
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to recover archived activities before refresh: ${JSON.stringify(error)}`);
    }

    // 最后加载和分类事项
    const allMatters: MatterItemModel[] = await todayActivityService.getTodayMatterItems();
    let normalizedMatters: MatterItemModel[] = MatterItemModel.ensureList(allMatters);

    // Normalize zero-duration items to TODO status
    normalizedMatters = await Promise.all(
      normalizedMatters.map(item => this.normalizeZeroDurationItem(item))
    );

    const newDone = buildPinnedDoneMatterList(normalizedMatters.filter(item =>
      item.status === MatterStatus.PAUSED || item.status === MatterStatus.RECORDING
    ), this.doneMatterData);

    const newUnDo = normalizedMatters.filter(item =>
      item.status === MatterStatus.TODO
    );

    hilog.info(0x0000, TAG,
      `Sync Matter Status: updateMatterItems total=${normalizedMatters.length} done=${newDone.length} todo=${newUnDo.length}`);
    newDone.forEach(item => hilog.info(0x0000, TAG,
      `Sync Matter Status: done item id=${item.id} status=${item.status} duration=${item.durationInMilliseconds}`));
    newUnDo.forEach(item => hilog.info(0x0000, TAG,
      `Sync Matter Status: todo item id=${item.id} status=${item.status} duration=${item.durationInMilliseconds}`));

    this.matterData = normalizedMatters;
    this.doneMatterData = newDone;
    this.unDoMatterData = newUnDo;
    // this.syncMatterStorage();

    if (publishRevision) {
      AppStorage.set('matterDataRevision', this.matterDataRevision + 1);
    }
  }

  private async refreshTodayData(): Promise<void> {
    this.refreshing = true;
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const openRecords = await rdbStoreUtil.queryActiveOpenRecords();
      const manager = MatterItemStateManager.getInstance();
      if (openRecords.length > 0) {
        for (const record of openRecords) {
          const activity = await rdbStoreUtil.queryActivityById(record.activityId);
          if (!activity) {
            hilog.warn(0x0000, TAG, `Open record ${record.recordId} has no activity ${record.activityId}, skipping status reconcile.`);
            continue;
          }
          if (activity.status !== MatterStatus.RECORDING) {
            hilog.warn(0x0000, TAG,
              `Open record ${record.recordId} activity ${record.activityId} status=${activity.status}, correcting to RECORDING.`);
            const updated = await rdbStoreUtil.updateActivityStatus(record.activityId, MatterStatus.RECORDING);
            if (!updated) {
              hilog.error(0x0000, TAG, `Failed to reconcile activity status for ${record.activityId} to RECORDING.`);
            }
          }
        }
        for (const record of openRecords) {
          await manager.refreshItemState(record.activityId);
        }
      }
      await manager.reconcileGlobalRunningState();
      await this.loadTagsFromDatabase();
      this.newTagColor = tagColorPreferenceService.getColors();
      await this.updateMatterItems();
      this.refreshSheetHeight();
      promptAction.openToast({
        message: '刷新成功',
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in refreshing')
      })
      await this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
    } catch (error) {
      hilog.error(0x0000, TAG, `Error refreshing today data: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '刷新失败，请稍后重试',
        duration: 1000
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error in refreshing')
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    } finally {
      this.isLoading = false;
      this.refreshing = false;
      this.refreshState = RefreshStatus.Done;
    }
  }

  private computeAddSheetHeight(tagCount: number): number {
    return calculateSheetHeight(tagCount, this.currentBreakpoint, this.viewportHeight);
  }

  private refreshSheetHeight(): void {
    const tagCount = this.tagData ? this.tagData.length : 0;
    this.sheetHeight = this.computeAddSheetHeight(tagCount);
  }

  private updateAddMatterSheetDetents(): void {
    if (this.isShow && this.keyboardHeight > 0) {
      this.addMatterSheetDetents = [SheetSize.LARGE];
      return;
    }
    this.addMatterSheetDetents = [SheetSize.MEDIUM, SheetSize.LARGE];
  }


  private getDestructiveActionShadow(): ShadowOptions {
    const base = this.isDarkTheme ? AppShadows.SUBTLE_DARK : AppShadows.SUBTLE;
    return {
      radius: base.radius,
      offsetX: base.offsetX,
      offsetY: base.offsetY,
      color: $r('app.color.error')
    };
  }

  async aboutToAppear() {
    this.pageLifecycleVisible = true;
    this.syncTodayVisibilityGate('about_to_appear');
    this.refreshGoalFighterAvailability();
    this.breakpointSystem.register();
    this.loadColorModePreference();
    // 初始化展开动画属性
    this.matterExpandAnimationProps = new MatterItemExpandAnimationProperties(this.getUIContext());
    try {
      // 初始化数据库
      await this.loadTagsFromDatabase();
      // 获取偏好中的标签颜色（若不存在则回落到默认预设）
      this.newTagColor = tagColorPreferenceService.getColors();
      hilog.info(0x0000, TAG, 'Component initialization completed');
    } catch (error) {
      hilog.error(0x0000, TAG, `Error during component initialization: ${JSON.stringify(error)}`);
    }

    this.loadSwissKnifeItemsFromPreferences();
    this.loadDirectStartPreference();
    this.loadAutoStopSettings();
    this.loadDefaultLinePanelPreference();
    this.loadFloatingActionBarPreference();
    this.loadIdeaPoolOrderPreference();
    this.loadIdeaPoolDirectRecordPreference();
    this.loadCalendarSyncPreferences();
    this.loadHoldingHandPreferences();
    await this.loadAutoBackupStatus();
    await this.refreshCalendarSyncPermissionState();
    await this.triggerCalendarSyncRecovery('about_to_appear');
    hilog.info(0x0000, TAG, `[Today] aboutToAppear -> directStartEnabled=${this.directStartEnabled}, isToggleOn=${this.isToggleOn}`);

    // 监听matterData变化，重新分类事项
    this.matterData = this.matterData.map(item => item); // 触发重新渲染

    window.getLastWindow(this.getUIContext().getHostContext()).then(currentWindow => {
      const windowRect = currentWindow.getWindowProperties().windowRect;
      this.viewportHeight = this.getUIContext().px2vp(windowRect.height);
      this.viewportWidth = this.getUIContext().px2vp(windowRect.width);
      this.viewportWidthPx = windowRect.width;
      this.refreshSheetHeight();
      this.syncVoiceInputOverlay();

      currentWindow.on('windowSizeChange', (size: window.Size) => {
        this.viewportHeight = this.getUIContext().px2vp(size.height);
        this.viewportWidth = this.getUIContext().px2vp(size.width);
        this.viewportWidthPx = size.width;
        this.refreshSheetHeight();
        this.syncVoiceInputOverlay();
      });
      currentWindow.on('keyboardHeightChange', (data: number) => {
        this.keyboardHeight = this.getUIContext().px2vp(data);
        hilog.info(0x0000, TAG, 'soft keyboard pop up in height of:' + this.keyboardHeight);
        this.updateAddMatterSheetDetents();
      })
    })

    this.refreshSheetHeight();

    await this.vibratorUtil.initialize();
    this.syncAllAnimatedLists(false);
    this.matterListProjectionReady = true;

    this.syncHoldingHandSubscription();

    // 检查是否需要自动打开添加事项 sheet（由卡片触发 - 冷启动场景）
    this.checkAndOpenAddSheetFromWidget();
    this.checkAndHandleMiniBarDirectRecord();
  }

  // 在自定义组件即将析构销毁时将dialogController置空
  aboutToDisappear() {
    this.pageLifecycleVisible = false;
    this.matterListProjectionReady = false;
    this.matterPinAnimationToken++;
    if (this.matterListSyncTimer >= 0) {
      clearTimeout(this.matterListSyncTimer);
      this.matterListSyncTimer = -1;
    }
    this.pinningMatterId = '';
    this.isPinningMatterCollapsed = false;
    this.isMatterPinTransitionActive = false;
    this.pendingMatterListSync = false;
    this.syncTodayVisibilityGate('about_to_disappear');
    this.addNewItemDialogController = null; // 将dialogController置空
    void this.vibratorUtil.stopAllHaptics();
    this.teardownVoiceInput();
    this.closeSwissKnife();
    this.breakpointSystem.unregister();
    this.finishBackupProgress();
    this.releaseHoldingHandSubscription();
  }

  async onPageShow() {
    this.pageLifecycleVisible = true;
    this.syncTodayVisibilityGate('on_page_show_start');
    this.refreshGoalFighterAvailability();
    try {
      await this.updateMatterItems();
      this.loadSwissKnifeItemsFromPreferences();
      this.loadDirectStartPreference();
      this.loadAutoStopSettings();
      this.loadDefaultLinePanelPreference();
      this.loadFloatingActionBarPreference();
      this.loadIdeaPoolOrderPreference();
      this.loadIdeaPoolDirectRecordPreference();
      this.loadCalendarSyncPreferences();
        this.loadHoldingHandPreferences();
      await this.loadAutoBackupStatus();
      await this.refreshCalendarSyncPermissionState();
      await this.triggerCalendarSyncRecovery('on_page_show');
      this.loadColorModePreference();
      hilog.info(0x0000, TAG, `[Today] onPageShow -> directStartEnabled=${this.directStartEnabled}, isToggleOn=${this.isToggleOn}`);

      // 检查是否需要自动打开添加事项 sheet（由卡片触发）
      this.checkAndOpenAddSheetFromWidget();
      this.checkAndHandleMiniBarDirectRecord();

      this.syncHoldingHandSubscription();
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh matter items on page show: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 检查并处理从卡片跳转过来需要打开添加事项 sheet 的情况
   * 用于冷启动场景（aboutToAppear/onPageShow）
   */
  private checkAndOpenAddSheetFromWidget(): void {
    hilog.info(0x0000, TAG, `[Today] checkAndOpenAddSheetFromWidget: openAddSheetFromWidget=${this.openAddSheetFromWidget}`);
    if (this.openAddSheetFromWidget === true) {
      this.openAddSheet();
    }
  }

  /**
   * 监听 openAddSheetFromWidget 变化（由卡片 router 参数触发）
   * 用于热启动场景
   */
  onOpenAddSheetFromWidgetChange(): void {
    hilog.info(0x0000, TAG, `[Today] onOpenAddSheetFromWidgetChange: openAddSheetFromWidget=${this.openAddSheetFromWidget}`);
    if (this.openAddSheetFromWidget === true) {
      this.openAddSheet();
    }
  }

  onMiniBarDirectRecordItemIdChange(): void {
    this.checkAndHandleMiniBarDirectRecord();
  }

  private checkAndHandleMiniBarDirectRecord(): void {
    if (this.miniBarDirectRecordItemId < 0 || this.activeMainTabIndex !== 1) {
      return;
    }
    const targetItem: FanItemVO | undefined = this.swissKnifeItems.find((item: FanItemVO) =>
      item.id === this.miniBarDirectRecordItemId);
    if (!targetItem) {
      return;
    }
    this.miniBarDirectRecordItemId = -1;
    this.handleSwissKnifePick(targetItem);
  }

  /**
   * 打开添加事项 sheet（由卡片触发）
   */
  private openAddSheet(): void {
    // 立即清除标记，避免重复触发
    this.openAddSheetFromWidget = false;
    hilog.info(0x0000, TAG, '[Today] Opening add sheet from widget');

    const openSheetImmediately: boolean = this.pageLifecycleVisible && this.activeMainTabIndex === 1;
    if (openSheetImmediately) {
      this.applyWidgetAddSheetPrefill();
      this.isShow = true;
      this.refreshSheetHeight();
      hilog.info(0x0000, TAG, `[Today] Add sheet opened from widget immediately, isShow=${this.isShow}`);
      return;
    }

    // 冷启动场景保留一帧缓冲，避免 sheet 在页面未完成布局时打开失败
    setTimeout(() => {
      this.applyWidgetAddSheetPrefill();
      this.isShow = true;
      this.refreshSheetHeight();
      hilog.info(0x0000, TAG, `[Today] Add sheet opened from widget (deferred), isShow=${this.isShow}`);
    }, 80);
  }

  private getAddBallBottomSpacerHeight(baseHeight: number): number {
    return this.useFloatingActionBar ? FLOATING_TAB_BAR_BOTTOM_SPACER_HEIGHT : baseHeight;
  }

  @Builder
  private renderMatterPinSlotHeader() {
    Row()
      .width('100%')
      .height(this.pinSlotExpanded ? $r('app.float.today_matter_item_height') : $r('app.float.today_pin_slot_rest_height'))
      .margin({
        bottom: this.pinSlotExpanded && this.pinSlotWithSpacing ?
          $r('app.float.today_matter_item_spacing') : $r('app.float.today_matter_item_spacing_none')
      })
  }

  @Builder
  private renderMatterGroupDividerHeader() {
    Divider()
      .height(20)
      .width('100%')
      .padding({
        left: $r('app.float.page_content_padding_horizontal'),
        right: $r('app.float.page_content_padding_horizontal')
      })
  }

  @Builder
  private renderMatterListFooter() {
    Row()
      .padding({
        left: $r('app.float.page_content_padding_horizontal'),
        right: $r('app.float.page_content_padding_horizontal')
      })
      .width('100%')
      .height(this.getAddBallBottomSpacerHeight(82))
  }

  onPageHide() {
    this.pageLifecycleVisible = false;
    this.syncTodayVisibilityGate('on_page_hide');
    this.refreshing = false;
    this.refreshState = RefreshStatus.Done;
    this.teardownVoiceInput();
    this.closeSwissKnife();
    void this.vibratorUtil.stopAllHaptics();
  }

  @Builder
  private renderDataPanelSection() {
    Column() {
      TodayDataPanel({
        defaultLinePanelEnabled: this.defaultLinePanelEnabled,
        pageVisible: this.todayPageVisible,
        currentBreakpoint: this.currentBreakpoint
      })
    }
    .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
    .width('100%')
    .margin({ bottom: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 15 : 0, left: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 25})
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 300 })
      .animation({ curve: curves.springMotion(), duration: 300 })))
  }

  @Builder
  private renderListContent() {
    // 置顶转场期间跨组搬运存在"两数组同时为空"的中间帧，必须保持 List 挂载，让 pin slot 动画得以播放
    if (this.animatedDoneMatterData.length == 0 && this.animatedUnDoMatterData.length == 0 && !this.isMatterPinTransitionActive) {
      ListItem() {
        Column() {
          Image($r('app.media.no_act_yet'))
            .width(125)
            .height(125)

          Text($r('app.string.come_and_record'))
            .fontSize(16)
            .fontWeight(600)
            .fontColor($r('app.color.text_disabled'))
        }
        .transition(TransitionEffect.scale({ x: 0, y: 0 })
          .animation({ curve: curves.springMotion(), duration: 250 }))
        .height(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 300 : '100%')
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
    } else {
      List({ scroller: this.listScroller  }) {
        // pin slot 使用跨 lane 的 group header，避免在 LG 双列布局中占掉第一行左侧卡位。
        // SM/MD 单列由它承载跨组置顶高度动画；LG 双列走转场重组路径，slot 常驻收起。
        ListItemGroup({ header: this.renderMatterPinSlotHeader() }) {
          ForEach(this.animatedDoneMatterData, (doneItem: MatterItemModel) => {
            ListItem() {
              // 按 stack-transition.md：key 放在"折叠态承载容器"上（固定宽高、即使内容迁移后也保持尺寸）
              Stack() {
                MatterItemCard({
                  item: doneItem,
                  animationProperties: this.matterExpandAnimationProps!,
                  enableExpand: true,  // 正在计时和已记录的事项允许展开
                  isDarkTheme: this.isDarkTheme
                })
                  .borderRadius(15)
                  // .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE)
              }
              .width('100%')
              .height($r('app.float.today_matter_item_height'))
              .opacity(this.isMatterPinCollapsed(doneItem.id) ? 0 : 1)
              .scale({
                x: this.isMatterPinCollapsed(doneItem.id) ? 0.85 : 1,
                y: this.isMatterPinCollapsed(doneItem.id) ? 0.85 : 1
              })
              .key(getMatterItemCardKey(doneItem.id))
            }
            .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
            .margin({ bottom: this.getMatterItemBottomSpacing(this.animatedDoneMatterData, doneItem.id) })
            .transition(this.getDoneMatterItemTransition(doneItem.id))
            .swipeAction({
              end: {
                builder: () => {
                  this.itemEnd(doneItem);
                },
                actionAreaDistance: $r('app.float.today_swipe_action_area_distance'),
                onAction: () => {
                  this.confirmDeleteMatter(doneItem);
                }
              },
              edgeEffect: SwipeEdgeEffect.Spring,
            })
            .height(this.getMatterItemAnimatedHeight(doneItem.id))
            .width('100%')
          }, (item: MatterItemModel) => this.renderMatterKey(item))
        }

        ListItemGroup({
          header: this.renderMatterGroupDividerHeader(),
          footer: this.renderMatterListFooter()
        }) {
          ForEach(this.animatedUnDoMatterData, (unDoItem: MatterItemModel) => {
            ListItem() {
              // 按 stack-transition.md：key 放在"折叠态承载容器"上（固定宽高、即使内容迁移后也保持尺寸）
              Stack() {
                MatterItemCard({
                  item: unDoItem,
                  animationProperties: this.matterExpandAnimationProps!,
                  enableExpand: true,  // 待办事项允许展开，仅用于评论
                  isDarkTheme: this.isDarkTheme
                })
                  .borderRadius(15)
              }
              .width('100%')
              .height($r('app.float.today_matter_item_height'))
              .opacity(this.isMatterPinCollapsed(unDoItem.id) ? 0 : 1)
              .scale({
                x: this.isMatterPinCollapsed(unDoItem.id) ? 0.85 : 1,
                y: this.isMatterPinCollapsed(unDoItem.id) ? 0.85 : 1
              })
              .key(getMatterItemCardKey(unDoItem.id))
            }
            .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
            .margin({ bottom: this.getMatterItemBottomSpacing(this.animatedUnDoMatterData, unDoItem.id) })
            .transition(this.getMatterListItemTransition())
            .swipeAction({
              end: {
                builder: () => {
                  this.itemEnd(unDoItem);
                },
                actionAreaDistance: $r('app.float.today_swipe_action_area_distance'),
                onAction: () => {
                  this.confirmDeleteMatter(unDoItem);
                }
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
            .height(this.getMatterItemAnimatedHeight(unDoItem.id))
            .width('100%')
          }, (item: MatterItemModel) => this.renderMatterKey(item))
        }
      }
      .layoutWeight(1)
      .friction(0.9)
      // 一多重复布局：SM/MD 单列（动画跟随 SM 单列路径），LG 双列
      .lanes(new BreakpointType<number>({ sm: 1, md: 1, lg: 2 }).getValue(this.currentBreakpoint))
      .width('100%')
      .scrollBar(BarState.Off)
      .animation({ curve: curves.springMotion(), duration: 100 })
      .onScrollStart(() => {
        this.ballVisible = Visibility.Hidden
      })
      .onScrollStop(() => {
        this.ballVisible = Visibility.Visible
      })
    }

  }

  // ForEach 使用稳定的 id 作为 key，配合 @ObjectLink 实现响应式更新
  // MatterItemModel 是 @Observed 修饰的类，MatterItemCard 使用 @ObjectLink item
  // 当 item 属性变化时，@ObjectLink 会自动触发 UI 更新，无需通过 key 变化来重建组件
  // 这样可以避免展开卡片因数据更新导致 key 变化而被重建，展开状态丢失
  private renderMatterKey(item: MatterItemModel): string {
    return item.id;
  }

  @Builder
  private renderListArea() {
    Refresh({ refreshing: $$this.refreshing, builder: this.refreshBuilder() }) {
      this.renderListContent();
    }
    .onOffsetChange((offset: number) => {
      this.refreshOffset = offset;
    })
    .onStateChange((state: RefreshStatus) => {
      this.refreshState = state;
    })
    .onRefreshing(async () => {
      hilog.info(0x0000, TAG, 'Refresh onRefreshing callback triggered');
      await this.refreshTodayData();
      hilog.info(0x0000, TAG, 'Refresh onRefreshing callback completed');
    })
    .margin({ right: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 10 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 300 })
      .animation({ curve: curves.springMotion(), duration: 300, delay: 100 })))
  }

  @Builder
  private renderGridBody() {
    GridRow({
      breakpoints: { value: BreakpointConstants.BREAKPOINT_VALUE, reference: BreakpointsReference.WindowSize },
      columns: {
        sm: BreakpointConstants.COLUMN_SM,
        md: BreakpointConstants.COLUMN_MD,
        lg: BreakpointConstants.COLUMN_LG
      },
      gutter: { x: BreakpointConstants.GUTTER_X },
      direction: GridRowDirection.Row
    }) {
      GridCol({ span: {
        sm: BreakpointConstants.COLUMN_SM,
        md: BreakpointConstants.COLUMN_MD / 2,
        lg: 4
      } }) {
        this.renderDataPanelSection();
      }

      GridCol({ span: {
        sm: BreakpointConstants.COLUMN_SM,
        md: BreakpointConstants.COLUMN_MD / 2,
        lg: BreakpointConstants.COLUMN_LG - 4
      } }) {
        this.renderListArea();
      }
    }
    .width('100%')
    .height('100%')
  }

  private resolveHoldingHandAlign(): FlexAlign {
    if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
      return FlexAlign.End;
    }
    if (!this.holdingHandEnabled) {
      return FlexAlign.Center;
    }
    switch (this.holdingHandStatus) {
      case motion.HoldingHandStatus.LEFT_HAND_HELD:
        return FlexAlign.Start;
      case motion.HoldingHandStatus.RIGHT_HAND_HELD:
        return FlexAlign.End;
      case motion.HoldingHandStatus.BOTH_HANDS_HELD:
        return this.lastHoldingHandAlign;
      case motion.HoldingHandStatus.NOT_HELD:
      case motion.HoldingHandStatus.UNKNOWN_STATUS:
      default:
        return FlexAlign.Center;
    }
  }

  private resolveHoldingHandOffsetY(): number {
    if (!this.shouldEnableHoldingHandOnThisDevice()) {
      return 0;
    }
    if (this.resolveHoldingHandAlign() === FlexAlign.Center) {
      return 0;
    }
    if (this.holdingHandOffsetPercent <= 0) {
      return 0;
    }
    const topSafeAreaPx = AppStorage.get('topSafeArea') as number;
    const bottomSafeAreaPx = AppStorage.get('bottomSafeArea') as number;
    const topSafeAreaVp = this.getUIContext().px2vp(typeof topSafeAreaPx === 'number' ? topSafeAreaPx : 0);
    const bottomSafeAreaVp = this.getUIContext().px2vp(typeof bottomSafeAreaPx === 'number' ? bottomSafeAreaPx : 0);
    const usableHeight = Math.max(0, this.viewportHeight - topSafeAreaVp - bottomSafeAreaVp);
    return usableHeight * (this.holdingHandOffsetPercent / 100);
  }

  private resolveAddBallAlign(): FlexAlign {
    if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
      return FlexAlign.End;
    }
    return this.resolveHoldingHandAlign();
  }

  private onHoldingHandStatusChange(): void {
    if (this.holdingHandStatus === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      this.lastHoldingHandAlign = FlexAlign.Start;
    } else if (this.holdingHandStatus === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      this.lastHoldingHandAlign = FlexAlign.End;
    }
    hilog.info(0x0000, TAG,
      `holdingHands status changed: enabled=${this.holdingHandEnabled}, status=${this.holdingHandStatus}, align=${this.resolveHoldingHandAlign()}, offset=${this.resolveHoldingHandOffsetY()}`);
  }

  @Builder
  private renderResponsiveGrid() {
    Stack({ alignContent: Alignment.Bottom }) {
          this.renderGridBody();

          Row() {
            AddNewBall()
              .width(this.addNewBallSize)
              .height(this.addNewBallSize)
              .margin({ bottom: new BreakpointType<number>({ sm: 100, md: 100, lg: 40 }).getValue(this.currentBreakpoint) })
              .visibility(this.ballVisible)
              .transition(this.effect)
              .bindSheet($$this.isShow, this.addNewItemBuilder(), {
                detents: this.addMatterSheetDetents,
                showClose: false,
                dragBar: false,
                preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
                blurStyle: BlurStyle.COMPONENT_REGULAR,
                enableOutsideInteractive: false,
                keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
                title: this.titleBuilder,
                onWillAppear: () => {
                  this.updateAddMatterSheetDetents();
                },
                onWillDismiss: ((dismissSheetAction: DismissSheetAction) => {
                  this.isShow = false;
                  this.updateAddMatterSheetDetents();
                  if (this.isEditingTag) {
                    this.updateTagEditingState(false);
                  }
                  this.resetFormState();
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
              .gesture(
                GestureGroup(GestureMode.Exclusive,
                  GestureGroup(
                    GestureMode.Parallel,
                    LongPressGesture({ duration: 400 })
                      .onAction((event) => {
                        // 新增：进入长按态并记录时间
                        this.longPressActive = true
                        this.lastLongPressAt = Date.now()

                        // 下面保持你的原逻辑不变
                        const finger = event?.fingerList ? event.fingerList[0] : undefined;
                        if (!finger) {
                          return;
                        }
                        if (typeof finger.globalX !== 'number' || typeof finger.globalY !== 'number') {
                          return;
                        }
                        const halfSize: number = this.addNewBallSize / 2;
                        const localX: number = typeof finger.localX === 'number' ? finger.localX : halfSize;
                        const localY: number = typeof finger.localY === 'number' ? finger.localY : halfSize;
                        const center: Point = {
                          x: finger.globalX - localX + halfSize,
                          y: finger.globalY - localY + halfSize
                        };
                        this.openSwissKnife(center);
                      })
                      .onActionEnd(() => {
                        this.finalizeSwissKnifeSelection();
                      }),
                    PanGesture()
                      .onActionStart((event: GestureEvent) => {
                        console.info('Pan start');
                        // 记录起始位置（你的原逻辑）
                        if (event && event.fingerList && event.fingerList[0]) {
                          const finger = event.fingerList[0];
                          if (typeof finger.globalX === 'number' && typeof finger.globalY === 'number') {
                            this.lastPosX = finger.globalX;
                            this.lastPosY = finger.globalY;
                          }
                        }
                      })
                      // 当该手势被触发时，根据回调获得拖动的距离，修改该组件的位移距离从而实现组件的移动（你的原逻辑）
                      .onActionUpdate((event: GestureEvent) => {
                        if (event) {
                          this.offsetX = (this.positionX + event.offsetX);
                          this.offsetY = this.positionY + event.offsetY;

                          if (this.content && event.fingerList && event.fingerList[0]) {
                            const finger = event.fingerList[0];
                            if (typeof finger.globalX === 'number' && typeof finger.globalY === 'number') {
                              // 直接使用成员变量计算选中索引
                              const newIndex = this.computeActiveIndexFromGlobalPosition(
                                finger.globalX,
                                finger.globalY
                              );

                              this.pendingSwissKnifeIndex = newIndex;

                              // 更新 StorageLink（只在索引变化时更新）
                              if (newIndex !== this.swissKnifeActiveIndex) {
                                const previousFanIndex: number = this.swissKnifeActiveIndex;
                                this.handleVoiceFanIndexChange(previousFanIndex, newIndex);
                                this.swissKnifeActiveIndex =
                                  newIndex; // mirror AppStorage immediately for same-frame reads
                                AppStorage.setOrCreate('swissKnifeActiveIndex', newIndex);
                                this.vibratorUtil.triggerHaptic('haptic.effect.sharp')
                              }
                            }
                          }
                        }
                      })
                      .onActionEnd(() => {
                        // 你的原逻辑
                        this.positionX = this.offsetX;
                        this.positionY = this.offsetY;
                        this.finalizeSwissKnifeSelection();
                      })
                      .onActionCancel(() => {
                        this.finalizeSwissKnifeSelection();
                      })
                  ),
                  TapGesture({ count: 1, fingers: 1 })
                    .onAction(() => {
                      // 新增：Tap 防抖与互斥兜底（不触碰你的后续逻辑）
                      if (this.longPressActive) {
                        return
                      }
                      if (Date.now() - this.lastLongPressAt < this.TAP_GUARD_MS) {
                        return
                      }
                      // 下面保持你的原逻辑不变
                      this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
                      this.isToggleOn = this.directStartEnabled;
                      hilog.info(0x0000, TAG,
                        `[Today] AddNewBall onClick -> directStartEnabled=${this.directStartEnabled}, isToggleOn=${this.isToggleOn}`);
                      this.isShow = true;
                      this.refreshSheetHeight();
                    })
                ),
              )
          }
          .width('100%')
          .justifyContent(this.resolveAddBallAlign())
          .visibility(Visibility.Visible)
          .padding({
            left: 12,
            right: new BreakpointType<number>({ sm: 12, md: 12, lg: 24 }).getValue(this.currentBreakpoint)
          })
          .offset({ y: -this.resolveHoldingHandOffsetY() })
          .animation({ curve: curves.springMotion(0.35, 0.9), duration: 240 })
          .hitTestBehavior(HitTestMode.Transparent)

    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.isSettingsPanelShow, this.settingsBuilder(), {
      detents: [SheetSize.LARGE],
      // blurStyle: BlurStyle.Thick,
      preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
      showClose: false,
      backgroundColor: $r('app.color.bg_main'),
      // title: {},
      onWillDismiss: ((dismissSheetAction: DismissSheetAction) => {
        this.isSettingsPanelShow = false;
        this.isSettingsSubPageActive = false;
        if (dismissSheetAction.reason === DismissReason.CLOSE_BUTTON ||
          dismissSheetAction.reason === DismissReason.PRESS_BACK ||
          dismissSheetAction.reason === DismissReason.SLIDE_DOWN ||
          dismissSheetAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissSheetAction.dismiss();
        }
      })
    })
    .padding({ top: 105 })
  }

  build() {
    if (canIUse("SystemCapability.UIDesign.HDSComponent.Core")) {
      HdsNavDestination() {
        Stack() {
          Column() {
            this.renderResponsiveGrid();
          }
          .width('100%')
          .height('100%')
          // 展开覆盖层展示时，禁用底层列表交互以保证收起回位准确
          .enabled(this.matterExpandAnimationProps === null ? true : !this.matterExpandAnimationProps.isExpandPageShow)

          // MatterItem 展开覆盖层
          if (this.matterExpandAnimationProps !== null && this.matterExpandAnimationProps.isExpandPageShow) {
            MatterItemExpandPage({
              animationProperties: this.matterExpandAnimationProps
            })
          }
        }
        .key('todayRootStack')
        .enabled(this.matterExpandAnimationProps === null ? true : this.matterExpandAnimationProps.isEnabled)
        .width('100%')
        .height('100%')
      }
      .backgroundColor($r('app.color.transparent'))
      .titleBar({
        avoidLayoutSafeArea: true,
        padding: {
          start: LengthMetrics.vp(16),
          end: LengthMetrics.vp(16)
        },
        style: {
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.GENTLE // 标题栏按钮自定义沉浸光感材质效果
          },
          scrollEffectOpts: {
            enableScrollEffect: false,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          },
          originalStyle: {
            backgroundStyle: {
              backgroundColor: $r('app.color.primary_lighter'),
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: $r('sys.color.font_primary'),
              },
              menuStyle: {
                backgroundColor: $r('sys.color.comp_background_tertiary'),
                iconColor: $r('sys.color.icon_primary')
              },
            }
          }

        },
        content: {
          title: {
            mainTitle: '今日',
          },
          menu: {
            value: [{
              content: {
                label: 'menuSetting',
                icon: $r('sys.symbol.gearshape'),
                isEnabled: true,
                action: () => {
                  this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch')
                  this.isSettingsPanelShow = true;
                }
              }
            }]
          }
        }
      })
      .hideToolBar(true)
      .hideBackButton(true)
      .width('100%')
      .height('100%')
    } else {
      NavDestination() {
        Stack() {
          Column() {
            this.renderResponsiveGrid();
          }
          .width('100%')
          .height('100%')
          // 展开覆盖层展示时，禁用底层列表交互以保证收起回位准确
          .enabled(this.matterExpandAnimationProps === null ? true : !this.matterExpandAnimationProps.isExpandPageShow)

          // MatterItem 展开覆盖层
          if (this.matterExpandAnimationProps !== null && this.matterExpandAnimationProps.isExpandPageShow) {
            MatterItemExpandPage({
              animationProperties: this.matterExpandAnimationProps
            })
          }
        }
        .key('todayRootStack')
        .enabled(this.matterExpandAnimationProps === null ? true : this.matterExpandAnimationProps.isEnabled)
        .width('100%')
        .height('100%')
      }
      .backgroundColor($r('app.color.transparent'))
      .hideToolBar(true)
      .hideBackButton(true)
      .width('100%')
      .height('100%')
    }
  }
}
