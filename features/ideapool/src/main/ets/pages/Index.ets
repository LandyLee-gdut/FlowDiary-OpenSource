import {
  AppShadows,
  DEFAULT_SHEET_HEIGHT,
  EmojiItem,
  EmojiUtil,
  IdeaPoolState,
  IdeaActivity,
  VibratorUtil,
  TagModel,
  TagItem,
  tagService,
  IdeaPoolViewMode,
  MatterStatus,
  IdeaLightState,
  IdeaLightSummary,
  IdeaCollection,
  IdeaCollectionSummary,
  MatterItemModel,
  SortEntry,
  calculateSheetHeight,
  ColorModeUtil,
  COLOR_MODE_STORAGE_KEY,
  PreferenceKeys,
  PreferencesUtil,
  preferencesUtil,
  BreakpointType,
  BreakpointConstants,
  BreakpointSystem,
  RDBStoreUtil,
  recordingSessionStore,
  ItemFormSheetConfig,
  ItemFormSheetPresets,
  buildSheetTitleBar,
  IdeaFormSheet,
  IdeaCollectionFormContent,
  holdingHandService,
} from 'base'
import { HdsNavigation, HdsNavDestinationAttribute, HdsNavigationTitleMode, HdsNavigationMenuItemOptions, HdsNavigationAttribute,
  ScrollEffectType,
  HdsNavDestination } from '@hms.hds.hdsBaseComponent'
import {
  ComponentContent,
  curves,
  ItemRestriction,
  LengthMetrics,
  // LongPressGesture,
  promptAction,
  SegmentButton,
  SegmentButtonOptions,
  SegmentButtonTextItem,
  SymbolGlyphModifier,
  window
} from '@kit.ArkUI'
import {IdeaCollectionCard} from '../component/IdeaCollectionCard'
import { IdeaCard } from '../component/IdeaCard'
import { IdeaExpandPage } from '../component/IdeaExpandPage'
import { IdeaExpandAnimationProperties, CollapseAnimationType } from '../component/IdeaExpandAnimation'
import { AddIdeaBall } from '../component/AddIdeaBall'
import { AddNewIdeaDialog } from '../component/AddNewIdeaDialog'
import { IdeaLightSummaryCards } from '../component/IdeaLightSummaryCards'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AddIdeaToTodayResult, DEFAULT_IDEA_USER_ID, IdeaCollectionCardEntry, IdeaPoolService, initIdeaPoolService } from '../model/IdeaPoolService'
import { IdeaCollectionCardEntryViewModel } from '../model/IdeaCollectionCardEntryViewModel'
import { BusinessError } from '@kit.BasicServicesKit'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { motion } from '@kit.MultimodalAwarenessKit';
import { hdsMaterial } from '@kit.UIDesignKit'

const TAG = 'IdeaPoolIndex';
const IDEAPOOL_IDEA_LIST_LANES: BreakpointType<number> = new BreakpointType<number>({ sm: 2, md: 3, lg: 4 });
const IDEAPOOL_LIST_BOTTOM_SPACER_HEIGHT: BreakpointType<number> = new BreakpointType<number>({ sm: 82, md: 82, lg: 75 });
const FLOATING_TAB_BAR_BOTTOM_SPACER_HEIGHT: number = 90;
const IDEAPOOL_SECTION_HEADER_HEIGHT: number = 40;
const IDEAPOOL_SECTION_HEADER_FONT_SIZE: number = 14;
const IDEAPOOL_SECTION_HEADER_FONT_WEIGHT: number = 400;
const IDEAPOOL_SECTION_HEADER_LINE_HEIGHT: number = 1;
const IDEAPOOL_TOP_SUMMARY_HEIGHT: number = 85;
const IDEAPOOL_COLLECTION_CARD_HEIGHT: number = 165;
const IDEAPOOL_COLLECTION_CARD_GUTTER: number = 12;

enum IdeaPoolListFilter {
  ALL = 0,
  UNLIT = 1,
  LIT = 2
}

enum IdeaPoolDragSource {
  NONE = 0,
  COLLECTION = 1,
  UNLIT = 2,
  LIT = 3
}

class IdeaSectionHeaderParams {
  title: ResourceStr;
  rowWidthPercent: string;

  constructor(title: ResourceStr, rowWidthPercent: string) {
    this.title = title;
    this.rowWidthPercent = rowWidthPercent;
  }
}

interface IdeaCollectionDetailRouteParam {
  collectionId: string;
}

@Builder
function ideaSectionHeader(params: IdeaSectionHeaderParams) {
    Row() {
      Column()
        .height(IDEAPOOL_SECTION_HEADER_LINE_HEIGHT)
        .layoutWeight(1)
        .backgroundColor($r('app.color.neutral_200'))

      Text(params.title)
        .fontSize(IDEAPOOL_SECTION_HEADER_FONT_SIZE)
        .fontWeight(IDEAPOOL_SECTION_HEADER_FONT_WEIGHT)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 15, right: 15, top: 2, bottom: 2 })
        .borderRadius(10)

      Column()
        .height(IDEAPOOL_SECTION_HEADER_LINE_HEIGHT)
        .layoutWeight(1)
        .backgroundColor($r('app.color.neutral_200'))
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
    .width('100%')
    .height(IDEAPOOL_SECTION_HEADER_HEIGHT)
    .clip(false)
}

interface RefreshStateOptions {
  animate?: boolean;
  onApplied?: () => void;
}

interface IdeaPoolPreferencesState {
  viewMode: IdeaPoolViewMode;
  enableDragPrototype: boolean;
  lastBulkSelection: string[];
}

class IdeaLightPartitions {
  lit: IdeaActivity[];
  unlit: IdeaActivity[];

  constructor(lit: IdeaActivity[], unlit: IdeaActivity[]) {
    this.lit = lit;
    this.unlit = unlit;
  }
}

@Builder
export function IdeaPoolBuilder() {
  IdeaPool();
}

function createEmptyIdeaPoolState(): IdeaPoolState {
  return {
    activities: [],
    tags: [],
    ideaPoolOrder: [],
    todayOrder: [],
    preferences: {
      viewMode: 'list',
      enableDragPrototype: false,
      lastBulkSelection: []
    },
    collections: [],
    categories: [],
    collectionSummaries: [],
    categorySummaries: [],
    globalSummary: { totalCount: 0, litCount: 0, unlitCount: 0 }
  };
}

@Component
export struct IdeaPool {
  @Consume('pageInfos') pageInfos: NavPathStack;
  @State private ideaPoolState: IdeaPoolState = createEmptyIdeaPoolState()
  @StorageLink('ideapoolActivities') @Watch('onIdeaActivitiesChange') private ideaActivities: IdeaActivity[] = []
  @StorageLink('openIdeaAddSheetFromWidget') @Watch('onOpenIdeaAddSheetFromWidgetChange')
  private openIdeaAddSheetFromWidget: boolean = false;
  @StorageLink('ideapoolCollections') @Watch('onIdeaCollectionsChange') private ideaCollections: IdeaCollection[] = [];
  @StorageLink('ideapoolCollectionSummaries') @Watch('onIdeaCollectionSummariesChange')
  private ideaCollectionSummaries: IdeaCollectionSummary[] = [];
  @State private ideaCollectionCardEntries: IdeaCollectionCardEntryViewModel[] = []
  @State segmentOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [
      { text: '全部' },
      { text: '未点亮' },
      { text: '已点亮' }
    ] as ItemRestriction<SegmentButtonTextItem>,
    backgroundColor: $r('app.color.segment_background'),
    selectedFontSize: 16,
    selectedBackgroundColor: $r('app.color.segment_selected_background'),
    selectedFontColor: $r('app.color.text_primary'),
    selectedFontWeight: 700,
    fontSize: 14,
    fontWeight: 500,
    fontColor: $r('app.color.text_secondary'),
    localizedButtonPadding: {
      end: LengthMetrics.vp(5),
      start: LengthMetrics.vp(5),
      top: LengthMetrics.vp(7),
      bottom: LengthMetrics.vp(7)
    },
  })
  @State @Watch('onIdeaFilterChanged') segmentSelectedIndexes: number[] = [IdeaPoolListFilter.ALL]
  @State selectedTagIndex: number = -1;
  @State selectedLabelIndex: number = -1;
  @State private selectedCollectionId: string | null = null;
  @State private selectableCollections: IdeaCollection[] = [];
  @State @Watch('onVisibilityGateStateChanged') isShow: boolean = false;
  @State private ideaFormSheetDetents: [Length | SheetSize, (Length | SheetSize)?, (Length | SheetSize)?] =
    [SheetSize.MEDIUM, SheetSize.LARGE];
  @State ballVisible: Visibility = Visibility.Visible
  @StorageLink('useFloatingActionBar') private useFloatingActionBar: boolean = false;
  @State sheetHeight: number = DEFAULT_SHEET_HEIGHT;
  @State inputTagName: string = ''
  @State inputActivityName: string = '';
  @State isAutoCancel: boolean = true;
  @State isCustomDialogShow: boolean = false;
  @State isEditingTag: boolean = false;
  @State tagShakeAngle: number = 0;
  @State isEditingIdeas: boolean = false;
  @State ideaShakeAngle: number = 0;
  @State private isEditingCollections: boolean = false;
  @State private collectionShakeAngle: number = 0;
  private isReordering: boolean = false;
  @State emojis: EmojiItem[] = EmojiUtil.getAll();
  @State private isIdeaLoading: boolean = true;
  @State private isCollectionLoading: boolean = true;
  @State private hasLoadedIdeaPool: boolean = false;
  // 添加灵感Sheet配置
  private addIdeaSheetConfig: ItemFormSheetConfig = ItemFormSheetPresets.createAddIdeaConfig();
  // 编辑灵感Sheet配置  
  private editIdeaSheetConfig: ItemFormSheetConfig = ItemFormSheetPresets.createEditIdeaConfig();
  @State @Watch('onVisibilityGateStateChanged') private isIdeaEditSheetShow: boolean = false;
  @State private editingIdeaName: string = '';
  @State private editingSelectedTagIndex: number = -1;
  @State private editingSelectedCollectionId: string | null = null;
  @State private editingInitialCollectionId: string | null = null;
  @State private editingIdea: IdeaActivity | undefined = undefined;
  @State private isSavingIdeaEdit: boolean = false;
  @State keyboardHeight: number = 0;
  @State viewportHeight: number = 0;
  @State viewportWidth: number = 0;
  @State private pageContentPaddingHorizontalVp: number = 20;
  @State refreshing: boolean = false;
  @State refreshOffset: number = 0;
  @State refreshState: RefreshStatus = RefreshStatus.Inactive;
  @State private relativeTimeBaseline: number = Date.now();
  @State private ideaExpandAnimationProps: IdeaExpandAnimationProperties | null = null;
  // 占位状态变量，用于通用组件的@Link绑定（灵感池不使用直接开始功能）
  @State private directStartPlaceholder: boolean = false;
  @State private editingTagShakeAngle: number = 0;
  @State private selectedEmojiChar: string = '';
  @State @Watch('onVisibilityGateStateChanged') private isCollectionAddSheetShow: boolean = false;
  @State private collectionName: string = '';
  @State private collectionSummary: string = '';
  @State private collectionSelectedTagIndex: number = -1;
  @State private collectionSelectedEmojiChar: string = '';
  @State private isSavingCollection: boolean = false;
  @StorageLink('tagData') tagData: TagModel[] = [];
  @StorageLink('matterData') matterData: MatterItemModel[] = [];
  @StorageLink('doneMatterData') doneMatterData: MatterItemModel[] = [];
  @StorageLink('unDoMatterData') unDoMatterData: MatterItemModel[] = [];
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @StorageLink('ideapoolLitData') private animatedLitIdeas: IdeaActivity[] = [];
  @StorageLink('ideapoolUnlitData') private animatedUnlitIdeas: IdeaActivity[] = [];
  @StorageLink('ideapoolUnlitFirst') private ideapoolUnlitFirst: boolean = true;
  @StorageLink('ideapoolDirectRecord') private ideapoolDirectRecord: boolean = false;
  @StorageLink('holdingHandEnabled') private holdingHandEnabled: boolean = false;
  @StorageLink('holdingHandOffsetPercent') private holdingHandOffsetPercent: number = 0;
  @StorageLink('holdingHandStatus') @Watch('onHoldingHandStatusChange')
  private holdingHandStatus: number = motion.HoldingHandStatus.UNKNOWN_STATUS;
  @StorageLink('activeMainTabIndex') @Watch('onVisibilityGateStateChanged') private activeMainTabIndex: number = 1;
  @StorageLink('userGuideSheetVisible') @Watch('onVisibilityGateStateChanged') private userGuideSheetVisible: boolean = false;
  @StorageLink('ideaPoolPageVisible') private ideaPoolPageVisible: boolean = false;
  @StorageLink('ideapoolRefreshToken') @Watch('onIdeaPoolRefreshTokenChange') private ideaPoolRefreshToken: number = 0;
  @State private litIdeaCount: number = 0;
  @State private unlitIdeaCount: number = 0;
  @State private lastRefreshToken: number = 0;

  private ideaPoolServiceReady: boolean = false;
  private readonly defaultUserId: string = DEFAULT_IDEA_USER_ID;
  private readonly deleteAnimationDuration: number = 250;
  private readonly tagShakeAmplitude: number = 4;
  private readonly tagShakeFrameDuration: number = 90;
  private isTagShakeRunning: boolean = false;
  private readonly ideaCardShakeAmplitude: number = 2;
  private readonly ideaCardShakeFrameDuration: number = 90;
  private isIdeaCardShakeRunning: boolean = false;
  private readonly collectionCardShakeAmplitude: number = 2;
  private readonly collectionCardShakeFrameDuration: number = 90;
  private isCollectionCardShakeRunning: boolean = false;
  private activeDragSource: IdeaPoolDragSource = IdeaPoolDragSource.NONE;
  private ideaDragPreviewWidth: number = 160;
  private ideaDragPreviewHeight: number = 165;
  private collectionDragPreviewWidth: number = 150;
  private collectionDragPreviewHeight: number = 145;
  private readonly preferencesUtil: PreferencesUtil = preferencesUtil;
  private lastHoldingHandAlign: FlexAlign = FlexAlign.Center;
  private holdingHandActive: boolean = false;

  private openIdeaCollectionDetail(collection: IdeaCollection): void {
    this.pageInfos.pushPathByName(
      'IdeaCollectionDetailPage',
      { collectionId: collection.id } as IdeaCollectionDetailRouteParam,
      () => {
        void this.refreshIdeaPoolState({ animate: false });
      }
    );
  }
  private vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private listScroller: ListScroller = new ListScroller();
  private litHeaderContent: ComponentContent<IdeaSectionHeaderParams> | undefined = undefined;
  private unlitHeaderContent: ComponentContent<IdeaSectionHeaderParams> | undefined = undefined;
  private effect: TransitionEffect = TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.6, 0.8), duration: 300 }).combine(TransitionEffect.translate({ x: 0, y: 100 }))// 添加旋转转场效果，这里的动画参数会跟随上面带animation的TransitionEffect，也就是springMotion(0.6, 0.8)
  private pageLifecycleVisible: boolean = false;
  private addNewItemDialogController: CustomDialogController = new CustomDialogController({
    builder: AddNewIdeaDialog({
      isShow: this.isShow,
      inputActivityName: this.inputActivityName,
      selectedTagIndex: this.selectedTagIndex,
      sheetHeight: this.sheetHeight,
      inputTagName: this.inputTagName,
      selectedLabelIndex: this.selectedLabelIndex
    }),
    alignment: DialogAlignment.Center,
    maskColor: $r('app.color.overlay_mask'),
    backgroundBlurStyle: BlurStyle.Thick,
    backgroundColor: $r('app.color.primary_lighter'),
    autoCancel: this.isAutoCancel,
    customStyle: true,
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
    onWillAppear: () => {
      this.isCustomDialogShow = true;
    },
    onWillDisappear: () => {
      this.isCustomDialogShow = false;
    },
    keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
    offset: { dx: 0, dy: 0 } }
  )
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();

  async aboutToAppear() {
    this.pageLifecycleVisible = true;
    this.syncIdeaPoolVisibilityGate('about_to_appear');
    this.ensureIdeaPoolStorageDefaults();
    this.lastRefreshToken = this.ideaPoolRefreshToken;
    this.breakpointSystem.register();
    this.resolvePageContentPaddingHorizontal();
    this.syncColorModeState();
    this.loadIdeaPoolOrderPreference();
    this.loadIdeaPoolDirectRecordPreference();
    this.loadHoldingHandPreferences();
    this.ideaExpandAnimationProps = new IdeaExpandAnimationProperties(this.getUIContext());
    const sortedActivities: IdeaActivity[] = this.sortActivitiesByDisplayOrder(this.ideaActivities);
    this.updateIdeaActivities(sortedActivities);
    this.syncIdeaCollectionCardsFromState();
    this.syncSelectableCollectionsFromState();
    this.syncAnimatedIdeaLists(false);
    this.ensureSectionHeaderContent();
    this.hasLoadedIdeaPool = this.ideaActivities.length > 0 || this.ideaCollections.length > 0
      || this.ideaCollectionCardEntries.length > 0;
    this.isIdeaLoading = !this.hasLoadedIdeaPool;
    this.isCollectionLoading = !this.hasLoadedIdeaPool;
    try {
      await this.vibratorUtil.initialize();
    } catch (error) {
      hilog.error(0x0000, TAG, `Error during IdeaPool page initialization: ${JSON.stringify(error)}`);
    }

    window.getLastWindow(this.getUIContext().getHostContext()).then(currentWindow => {
      const windowRect = currentWindow.getWindowProperties().windowRect;
      this.viewportHeight = this.getUIContext().px2vp(windowRect.height);
      this.viewportWidth = this.getUIContext().px2vp(windowRect.width);
      this.recalculateSheetHeight();

      currentWindow.on('windowSizeChange', (size: window.Size) => {
        this.viewportHeight = this.getUIContext().px2vp(size.height);
        this.viewportWidth = this.getUIContext().px2vp(size.width);
        this.recalculateSheetHeight();
      });
      currentWindow.on('keyboardHeightChange', (data: number) => {
        this.keyboardHeight = this.getUIContext().px2vp(data);
        hilog.info(0x0000, TAG, `soft keyboard pop up in height of: ${this.keyboardHeight}`);
        this.updateIdeaFormSheetDetents();
      });
    }).catch((reason: BusinessError) => {
      hilog.error(0x0000, TAG, `Failed to get last window: ${JSON.stringify(reason)}`);
    });
    try {
      await this.refreshIdeaPoolState();
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to load idea pool data on appear: ${JSON.stringify(error)}`);
    } finally {
      this.recalculateSheetHeight();
    }
    this.checkAndOpenAddIdeaSheetFromWidget();

    this.syncHoldingHandSubscription();
  }

  aboutToDisappear() {
    this.pageLifecycleVisible = false;
    this.syncIdeaPoolVisibilityGate('about_to_disappear');
    // this.addNewItemDialogController = null;
    this.litHeaderContent = undefined;
    this.unlitHeaderContent = undefined;
    if (this.isEditingIdeas) {
      this.updateIdeaEditingState(false);
    }
    if (this.isEditingCollections) {
      this.updateCollectionEditingState(false);
    }
    if (this.isIdeaEditSheetShow) {
      this.isIdeaEditSheetShow = false;
      this.resetEditIdeaForm();
    }
    void this.vibratorUtil.stopAllHaptics();
    this.breakpointSystem.unregister();
    this.releaseHoldingHandSubscription();
  }

  async onPageShow() {
    this.pageLifecycleVisible = true;
    this.syncIdeaPoolVisibilityGate('on_page_show_start');
    this.loadIdeaPoolOrderPreference();
    this.loadIdeaPoolDirectRecordPreference();
    this.loadHoldingHandPreferences();
    try {
      await this.refreshIdeaPoolState();
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh idea pool data on page show: ${JSON.stringify(error)}`);
    } finally {
      this.recalculateSheetHeight();
    }
    this.checkAndOpenAddIdeaSheetFromWidget();

    this.syncHoldingHandSubscription();
  }

  onPageHide(): void {
    this.pageLifecycleVisible = false;
    this.syncIdeaPoolVisibilityGate('on_page_hide');
    this.refreshing = false;
    this.refreshState = RefreshStatus.Done;
    void this.vibratorUtil.stopAllHaptics();
  }

  /**
   * 检查并处理从卡片跳转过来需要打开添加灵感 sheet 的情况
   * 用于冷启动场景（aboutToAppear/onPageShow）
   */
  private checkAndOpenAddIdeaSheetFromWidget(): void {
    hilog.info(0x0000, TAG, `[IdeaPool] checkAndOpenAddIdeaSheetFromWidget: openIdeaAddSheetFromWidget=${this.openIdeaAddSheetFromWidget}`);
    if (this.openIdeaAddSheetFromWidget === true) {
      this.openAddIdeaSheetFromWidget();
    }
  }

  /**
   * 监听 openIdeaAddSheetFromWidget 变化（由卡片 router 参数触发）
   * 用于热启动场景
   */
  onOpenIdeaAddSheetFromWidgetChange(): void {
    hilog.info(0x0000, TAG, `[IdeaPool] onOpenIdeaAddSheetFromWidgetChange: openIdeaAddSheetFromWidget=${this.openIdeaAddSheetFromWidget}`);
    if (this.openIdeaAddSheetFromWidget === true) {
      this.openAddIdeaSheetFromWidget();
    }
  }

  /**
   * 打开添加灵感 sheet（由卡片触发）
   */
  private openAddIdeaSheetFromWidget(): void {
    this.openIdeaAddSheetFromWidget = false;
    hilog.info(0x0000, TAG, '[IdeaPool] Opening add idea sheet from widget');
    const openSheetImmediately: boolean = this.pageLifecycleVisible && this.activeMainTabIndex === 2;
    if (openSheetImmediately) {
      this.recalculateSheetHeight();
      this.isShow = true;
      hilog.info(0x0000, TAG, `[IdeaPool] Add idea sheet opened from widget immediately, isShow=${this.isShow}`);
      return;
    }

    setTimeout(() => {
      this.recalculateSheetHeight();
      this.isShow = true;
      hilog.info(0x0000, TAG, `[IdeaPool] Add idea sheet opened from widget (deferred), isShow=${this.isShow}`);
    }, 80);
  }

  onColorModeChange(): void {
    this.syncColorModeState();
  }

  private onIdeaPoolRefreshTokenChange(): void {
    if (this.ideaPoolRefreshToken === this.lastRefreshToken) {
      return;
    }
    this.lastRefreshToken = this.ideaPoolRefreshToken;
    void this.refreshIdeaPoolState({ animate: false });
  }

  private onIdeaActivitiesChange(): void {
    this.ideaPoolState.activities = this.ideaActivities;
    this.updateRelativeTimeBaseline();
    const previousCount: number = this.animatedLitIdeas.length + this.animatedUnlitIdeas.length;
    const shouldAnimate: boolean = this.ideaActivities.length !== previousCount;
    this.syncAnimatedIdeaLists(shouldAnimate);
    this.syncIdeaLightCountsFromActivities();
  }

  private onIdeaCollectionsChange(): void {
    this.syncIdeaCollectionCardsFromState(true);
    this.syncSelectableCollectionsFromState();
  }

  private onIdeaCollectionSummariesChange(): void {
    this.syncIdeaCollectionCardsFromState(true);
  }

  private syncSelectableCollectionsFromState(): void {
    const resolvedCollections: IdeaCollection[] = Array.isArray(this.ideaCollections) ? [...this.ideaCollections] : [];
    resolvedCollections.sort((left: IdeaCollection, right: IdeaCollection) => {
      const orderDelta: number = left.displayOrder - right.displayOrder;
      if (orderDelta !== 0) {
        return orderDelta;
      }
      return left.createdAt - right.createdAt;
    });
    this.selectableCollections = resolvedCollections;
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private loadIdeaPoolOrderPreference(): void {
    if (!this.preferencesUtil.isInitialized()) {
      hilog.warn(0x0000, TAG, '[IdeaPool] Preferences not initialized when loading ideapool order');
      this.ideapoolUnlitFirst = true;
      return;
    }
    const storedValue = this.preferencesUtil.getSync(PreferenceKeys.IDEAPOOL_UNLIT_FIRST, true) as boolean;
    const normalized = !!storedValue;
    this.ideapoolUnlitFirst = normalized;
  }

  private loadIdeaPoolDirectRecordPreference(): void {
    if (!this.preferencesUtil.isInitialized()) {
      hilog.warn(0x0000, TAG, '[IdeaPool] Preferences not initialized when loading ideapool direct record');
      this.ideapoolDirectRecord = false;
      return;
    }
    const storedValue = this.preferencesUtil.getSync(PreferenceKeys.IDEAPOOL_DIRECT_RECORD, false) as boolean;
    const normalized = !!storedValue;
    this.ideapoolDirectRecord = normalized;
  }

  private loadHoldingHandPreferences(): void {
    if (!this.preferencesUtil.isInitialized()) {
      hilog.warn(0x0000, TAG, '[IdeaPool] Preferences not initialized when loading holdingHand settings');
      this.updateHoldingHandEnabledState(false);
      this.updateHoldingHandOffsetState(0);
      return;
    }
    const storedEnabled = this.preferencesUtil.getSync(PreferenceKeys.HOLDING_HAND_ENABLED, false) as boolean;
    const storedOffset = this.preferencesUtil.getSync(PreferenceKeys.HOLDING_HAND_OFFSET_PERCENT, 0) as number;
    this.updateHoldingHandEnabledState(!!storedEnabled);
    this.updateHoldingHandOffsetState(typeof storedOffset === 'number' ? storedOffset : 0);
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

  private shouldEnableHoldingHandOnThisDevice(): boolean {
    return this.holdingHandEnabled && this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_LG;
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

  private onIdeaFilterChanged(): void {
  }

  @Builder
  titleBuilder() {
    buildSheetTitleBar({
      title: this.addIdeaSheetConfig.titleBar.title,
      actionButtonText: this.addIdeaSheetConfig.titleBar.actionButtonText,
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
            message: '请完整填写灵感信息'
          }).catch(() => {});
          return;
        }
        const selectedTagId = this.selectedTagIndex >= 0 ? this.tagData[this.selectedTagIndex].id : null;
        await this.handleAddIdeaButtonClick(this.inputActivityName, selectedTagId, this.selectedCollectionId);
        void this.vibratorUtil.triggerHaptic('haptic.notice.success', 'touch');
        this.isShow = false;
        this.resetFormState();
      }
    });
  }

  @Builder
  addNewItemBuilder() {
    IdeaFormSheet({
      config: this.addIdeaSheetConfig,
      tagData: this.tagData,
      inputName: this.inputActivityName,
      selectedTagIndex: this.selectedTagIndex,
      directStartEnabled: this.directStartPlaceholder,
      isEditingTag: this.isEditingTag,
      tagShakeAngle: this.tagShakeAngle,
      selectedEmoji: this.selectedEmojiChar,
      isDarkTheme: this.isDarkTheme,
      showCollectionPicker: true,
      collectionPickerLabel: $r('app.string.ideapool_collection_selector_label'),
      collections: this.selectableCollections,
      selectedCollectionId: this.selectedCollectionId,
      showCollectionLooseOption: true,
      onCollectionSelectionChange: (collectionId: string | null) => {
        this.selectedCollectionId = collectionId;
        void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
      },
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
  editIdeaSheetTitleBuilder() {
    buildSheetTitleBar({
      title: this.editIdeaSheetConfig.titleBar.title,
      actionButtonText: this.isSavingIdeaEdit
        ? $r('app.string.ideapool_idea_action_saving')
        : this.editIdeaSheetConfig.titleBar.actionButtonText,
      actionButtonDisabled: this.isSavingIdeaEdit,
      onClose: () => {
        void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
        this.isIdeaEditSheetShow = false;
        this.resetEditIdeaForm();
      },
      onSubmit: async () => {
        await this.handleIdeaEditSave();
      }
    });
  }

  @Builder
  editIdeaSheetContentBuilder() {
    IdeaFormSheet({
      config: this.editIdeaSheetConfig,
      tagData: this.tagData,
      inputName: this.editingIdeaName,
      selectedTagIndex: this.editingSelectedTagIndex,
      directStartEnabled: this.directStartPlaceholder,
      isEditingTag: this.isEditingTag,
      tagShakeAngle: this.editingTagShakeAngle,
      selectedEmoji: this.selectedEmojiChar,
      isDarkTheme: this.isDarkTheme,
      showCollectionPicker: true,
      collectionPickerLabel: $r('app.string.ideapool_collection_selector_label'),
      collections: this.selectableCollections,
      selectedCollectionId: this.editingSelectedCollectionId,
      showCollectionLooseOption: true,
      onCollectionSelectionChange: (collectionId: string | null) => {
        this.editingSelectedCollectionId = collectionId;
        void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
      }
    })
  }

  @Builder
  addIdeaCollectionPlaceholderBuilder() {
    Column() {
      Column() {
        Text($r('app.string.ideapool_collection_add_plus'))
          .fontSize($r('app.float.ideapool_collection_add_plus_font_size'))
          .fontColor($r('app.color.text_tertiary'))
      }
      .width($r('app.float.ideapool_collection_add_icon_size'))
      .height($r('app.float.ideapool_collection_add_icon_size'))
      .borderRadius('50%')
      .backgroundColor($r('app.color.bg_card'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text($r('app.string.ideapool_collection_add_new'))
        .fontSize($r('app.float.ideapool_collection_add_text_size'))
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: $r('app.float.ideapool_collection_add_text_margin_top') })
    }
    .clickEffect({ level: ClickEffectLevel.HEAVY, scale: 0.8 })
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.neutral_100'))
    .borderRadius($r('app.float.ideapool_collection_add_card_radius'))
    .border({ width: $r('app.float.ideapool_collection_add_border_width'), color: $r('app.color.neutral_300'), style: BorderStyle.Dashed })
    .onClick(() => {
      void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
      this.openIdeaCollectionSheet();
    })
    .bindSheet($$this.isCollectionAddSheetShow, this.addIdeaCollectionSheetContentBuilder(), {
      detents: [SheetSize.LARGE],
      showClose: false,
      dragBar: false,
      preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
      blurStyle: BlurStyle.COMPONENT_REGULAR,
      enableOutsideInteractive: false,
      keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
      // title: this.addIdeaCollectionTitleBuilder,
      onWillAppear: () => {
        this.recalculateSheetHeight();
      },
      onAppear: () => {
        hilog.info(0x0000, TAG, 'Collection sheet onAppear.');
      },
      onWillDisappear: () => {
        hilog.info(0x0000, TAG, 'Collection sheet onWillDisappear.');
      },
      onDisappear: () => {
        hilog.info(0x0000, TAG, 'Collection sheet onDisappear.');
      },
      onWillDismiss: (dismissSheetAction: DismissSheetAction) => {
        this.isCollectionAddSheetShow = false;
        this.resetIdeaCollectionForm();
        if (dismissSheetAction.reason === DismissReason.CLOSE_BUTTON) {
          dismissSheetAction.dismiss();
        }
        if (dismissSheetAction.reason === DismissReason.PRESS_BACK) {
          dismissSheetAction.dismiss();
        }
        if (dismissSheetAction.reason == DismissReason.SLIDE_DOWN) {
          dismissSheetAction.dismiss();
        }
      }
    })
  }

  @Builder
  private addIdeaCollectionTitleBuilder() {
    buildSheetTitleBar({
      title: $r('app.string.ideapool_collection_add_title'),
      actionButtonText: $r('app.string.ideapool_collection_add_action'),
      actionButtonDisabled: this.isSavingCollection,
      actionButtonDisabledText: $r('app.string.ideapool_collection_add_action_saving'),
      onClose: () => {
        this.isCollectionAddSheetShow = false;
        this.resetIdeaCollectionForm();
      },
      onSubmit: async () => {
        await this.handleCreateIdeaCollection();
      }
    })
  }

  @Builder
  private addIdeaCollectionSheetContentBuilder() {
    IdeaCollectionFormContent({
      name: this.collectionName,
      summaryText: this.collectionSummary,
      selectedTagIndex: this.collectionSelectedTagIndex,
      selectedEmojiChar: this.collectionSelectedEmojiChar,
      tagData: this.tagData,
      emojis: this.emojis,
      isDarkTheme: this.isDarkTheme,
      headerLabel: $r('app.string.ideapool_collection_header_new'),
      namePlaceholder: $r('app.string.ideapool_collection_name_placeholder'),
      descLabel: $r('app.string.ideapool_collection_desc_label'),
      descPlaceholder: $r('app.string.ideapool_collection_desc_placeholder'),
      tagLabel: $r('app.string.ideapool_collection_tag_label'),
      emojiLabel: $r('app.string.ideapool_collection_emoji_label'),
      defaultEmoji: $r('app.string.ideapool_collection_default_emoji'),
      confirmText: $r('app.string.ideapool_collection_add_action'),
      confirmDisabled: this.isSavingCollection,
      confirmDisabledText: $r('app.string.ideapool_collection_add_action_saving'),
      onClose: () => {
        this.isCollectionAddSheetShow = false;
        this.resetIdeaCollectionForm();
      },
      onConfirm: async () => {
        await this.handleCreateIdeaCollection();
      }
    })
      .width('100%')
  }

  @Builder
  private CollectionPreviewSection() {
    Column() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          Text(this.resolveCollectionPreviewEmoji())
            .fontSize($r('app.float.ideapool_collection_preview_emoji_size'))
        }
        .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)
        .width($r('app.float.ideapool_collection_preview_size'))
        .height($r('app.float.ideapool_collection_preview_size'))
        .borderRadius($r('app.float.ideapool_collection_preview_radius'))
        .backgroundColor(this.resolveCollectionPreviewColor())
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: $r('app.float.ideapool_collection_preview_margin_top') })
  }

  @Builder
  private CollectionNameSection() {
    Column() {
      // Row() {
      //   Text($r('app.string.ideapool_collection_name_label'))
      //     .fontSize(15)
      //     .fontWeight(500)
      // }
      // .width('100%')
      // .justifyContent(FlexAlign.Start)
      // .margin({ bottom: 10 })

      TextInput({
        text: this.collectionName,
        placeholder: $r('app.string.ideapool_collection_name_placeholder'),
      })
        .fontSize(22)
        .fontWeight(600)
        .textAlign(TextAlign.Center)
        .placeholderFont({
          size: 22,
          weight: 600
        })
        .caretColor($r('app.color.primary'))
        .backgroundColor($r('app.color.bg_card'))
        .placeholderColor($r('app.color.text_disabled'))
        // .border({ width: $r('app.float.ideapool_collection_input_border_width'), color: $r('app.color.neutral_200') })
        .borderRadius($r('app.float.ideapool_collection_input_radius'))
        .height($r('app.float.ideapool_collection_input_height'))
        .width('100%')
        .onChange((value: string) => {
          this.collectionName = value;
        })
      Divider()
        .strokeWidth(5)
        .width(35)
        .borderRadius('50%')
        .backgroundColor($r('app.color.neutral_100'))
    }
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 15, bottom: 15 })
    .width('100%')
  }

  @Builder
  private CollectionDescriptionSection() {
    Column() {
      Row() {
        Text($r('app.string.ideapool_collection_desc_label'))
          .fontSize(15)
          .fontWeight(500)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 10 })

      TextArea({
        text: this.collectionSummary,
        placeholder: $r('app.string.ideapool_collection_desc_placeholder')
      })
        .caretColor($r('app.color.primary'))
        .backgroundColor($r('app.color.bg_card'))
        .placeholderColor($r('app.color.text_disabled'))
        .border({ width: $r('app.float.ideapool_collection_input_border_width'), color: $r('app.color.neutral_200') })
        .borderRadius($r('app.float.ideapool_collection_textarea_radius'))
        .height($r('app.float.ideapool_collection_textarea_height'))
        .width('100%')
        .onChange((value: string) => {
          this.collectionSummary = value;
        })
    }
    .margin({ top: $r('app.float.ideapool_collection_section_gap') })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private CollectionTagSelectorSection() {
    Column() {
      Row() {
        Text($r('app.string.ideapool_collection_tag_label'))
          .fontSize(15)
          .fontWeight(500)
      }
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 10 })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach(this.tagData, (tag: TagModel, index: number) => {
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
            .translate({ z: this.collectionSelectedTagIndex === index ? -30 : 0 })
            .scale(this.collectionSelectedTagIndex === index ? { x: 1.1 , y: 1.1 } : {})
            .animation({ curve: curves.springMotion(0.35, 0.6), duration: 50 })
            .shadow(this.collectionSelectedTagIndex === index
              ? AppShadows.getTagPillShadow(tag.color, this.isDarkTheme)
              : AppShadows.NONE)
            .justifyContent(FlexAlign.Center)
            .borderRadius(20)
            .onClick(() => {
              if (this.collectionSelectedTagIndex !== index) {
                this.collectionSelectedTagIndex = index;
                void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
              }
            })

            if (this.collectionSelectedTagIndex === index) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontColor([$r('app.color.neutral_100')])
                  .fontSize(10)
                  .fontWeight(700)
              }
              .backgroundColor($r('app.color.primary'))
              .translate({ x: -3, y: -5 })
              .transition(TransitionEffect.scale({ x: 0, y: 0 })
                .animation({ curve: curves.springMotion(0.35, 0.7), duration: 10}))
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
              .width(15)
              .height(15)
            }
          }
        }, (tag: TagModel) => tag.id)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .margin({ top: $r('app.float.ideapool_collection_section_gap') })
    .width('100%')
  }

  @Builder
  private CollectionEmojiSelectorSection() {
    Column() {
      Row() {
        Text($r('app.string.ideapool_collection_emoji_label'))
          .fontSize(15)
          .fontWeight(500)
      }
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 5 })

      Grid() {
        ForEach(this.emojis, (emoji: EmojiItem) => {
          GridItem() {
            Text(emoji.char)
              .fontSize(16)
              .padding(8)
              .borderRadius('50%')
              .backgroundColor($r('app.color.bg_main'))
              .shadow(this.collectionSelectedEmojiChar === emoji.char
                ? { color: $r('app.color.primary'), radius: 12 }
                : { radius: 0 })
          }
          .onClick(() => {
            if (this.collectionSelectedEmojiChar !== emoji.char) {
              this.collectionSelectedEmojiChar = emoji.char;
              void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            }
          })
        }, (emoji: EmojiItem) => emoji.char)
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
    .margin({ top: $r('app.float.ideapool_collection_section_gap') })
    .width('100%')
  }

  // ===== 核心业务逻辑方法 =====

  private computeSheetHeight(tagCount: number): number {
    return calculateSheetHeight(tagCount, this.currentBreakpoint, this.viewportHeight);
  }

  private openIdeaCollectionSheet(): void {
    this.resetIdeaCollectionForm();
    this.recalculateSheetHeight();
    this.isCollectionAddSheetShow = true;
  }

  private resetIdeaCollectionForm(): void {
    this.collectionName = '';
    this.collectionSummary = '';
    this.collectionSelectedTagIndex = -1;
    this.collectionSelectedEmojiChar = '';
    this.isSavingCollection = false;
  }

  private resolveCollectionPreviewColor(): ResourceColor {
    if (this.collectionSelectedTagIndex >= 0 && this.collectionSelectedTagIndex < this.tagData.length) {
      return this.tagData[this.collectionSelectedTagIndex].lightColor;
    }
    return $r('app.color.neutral_100');
  }

  private resolveCollectionPreviewEmoji(): ResourceStr {
    if (this.collectionSelectedEmojiChar && this.collectionSelectedEmojiChar.length > 0) {
      return this.collectionSelectedEmojiChar;
    }
    return $r('app.string.ideapool_collection_default_emoji');
  }

  private resolveCollectionTagId(): string | null {
    if (this.collectionSelectedTagIndex >= 0 && this.collectionSelectedTagIndex < this.tagData.length) {
      return this.tagData[this.collectionSelectedTagIndex].id;
    }
    return null;
  }

  private updateCollectionSummaryCounts(collectionId: string, deltaLit: number, deltaUnlit: number): void {
    if (!collectionId) {
      return;
    }
    let updated: boolean = false;
    for (let index: number = 0; index < this.ideaCollectionSummaries.length; index += 1) {
      const summary: IdeaCollectionSummary = this.ideaCollectionSummaries[index];
      if (summary.collectionId === collectionId) {
        const nextLit: number = Math.max(0, summary.litCount + deltaLit);
        const nextUnlit: number = Math.max(0, summary.unlitCount + deltaUnlit);
        this.ideaCollectionSummaries.splice(index, 1, {
          collectionId: summary.collectionId,
          litCount: nextLit,
          unlitCount: nextUnlit,
          totalCount: nextLit + nextUnlit
        });
        updated = true;
        break;
      }
    }
    if (!updated) {
      const initialLit: number = Math.max(0, deltaLit);
      const initialUnlit: number = Math.max(0, deltaUnlit);
      if (initialLit + initialUnlit > 0) {
        this.ideaCollectionSummaries.push({
          collectionId: collectionId,
          litCount: initialLit,
          unlitCount: initialUnlit,
          totalCount: initialLit + initialUnlit
        });
        updated = true;
      }
    }
    if (updated) {
      this.ideaPoolState.collectionSummaries = this.ideaCollectionSummaries;
      this.syncIdeaCollectionCardsFromState(false);
    }
  }

  private async handleCreateIdeaCollection(): Promise<void> {
    if (this.isSavingCollection) {
      return;
    }
    const trimmedName: string = this.collectionName.trim();
    if (trimmedName.length === 0) {
      promptAction.openToast({
        duration: 1000,
        message: $r('app.string.ideapool_collection_name_required')
      }).catch(() => {
      });
      return;
    }
    this.isSavingCollection = true;
    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const tagId: string | null = this.resolveCollectionTagId();
      const summaryText: string | null = this.collectionSummary.trim().length > 0 ? this.collectionSummary.trim() : null;
      const icon: string | null = this.collectionSelectedEmojiChar.length > 0 ? this.collectionSelectedEmojiChar : null;
      const created: IdeaCollection | null = await service.createIdeaCollection(this.defaultUserId, {
        name: trimmedName,
        icon: icon,
        tagId: tagId,
        summaryText: summaryText
      });
      if (created) {
        const applyAdd = () => {
          this.ideaCollectionSummaries.push({
            collectionId: created.id,
            totalCount: 0,
            litCount: 0,
            unlitCount: 0
          });
          this.ideaPoolState.collectionSummaries = this.ideaCollectionSummaries;
          this.ideaCollections.push(created);
          this.ideaPoolState.collections = this.ideaCollections;
          this.syncIdeaCollectionCardsFromState(false);
          this.syncSelectableCollectionsFromState();
        };
        const uiContext = this.getUIContext();
        if (uiContext) {
          uiContext.animateTo({ duration: this.deleteAnimationDuration, curve: curves.springMotion() }, applyAdd);
        } else {
          applyAdd();
        }
        void this.vibratorUtil.triggerHaptic('haptic.notice.success', 'touch');
        this.isCollectionAddSheetShow = false;
        this.resetIdeaCollectionForm();
      } else {
        promptAction.openToast({
          duration: 1000,
          message: $r('app.string.ideapool_collection_add_failed')
        }).catch(() => {
        });
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Create idea collection failed: ${JSON.stringify(error)}`);
      promptAction.openToast({
        duration: 1000,
        message: $r('app.string.ideapool_collection_add_failed')
      }).catch(() => {
      });
    } finally {
      this.isSavingCollection = false;
    }
  }

  private getIdeaListLanes(): number {
    return IDEAPOOL_IDEA_LIST_LANES.getValue(this.currentBreakpoint);
  }

  private getIdeaGridColumnsTemplate(): string {
    const lanes: number = this.getIdeaListLanes();
    if (lanes === 4) {
      return '1fr 1fr 1fr 1fr';
    }
    if (lanes === 3) {
      return '1fr 1fr 1fr';
    }
    return '1fr 1fr';
  }

  private isIdeaDragSource(source: IdeaPoolDragSource): boolean {
    return source === IdeaPoolDragSource.UNLIT || source === IdeaPoolDragSource.LIT;
  }

  private showRejectedDropToast(target: IdeaPoolDragSource): void {
    if (this.isIdeaDragSource(this.activeDragSource) && this.isIdeaDragSource(target)) {
      promptAction.openToast({
        message: $r('app.string.ideapool_sort_cross_group_rejected'),
        duration: 1200
      }).catch(() => {
      });
    }
  }

  private updateIdeaDragPreviewSize(newValue: Area): void {
    const measuredWidth: number = Number(newValue.width);
    const measuredHeight: number = Number(newValue.height);
    if (!Number.isNaN(measuredWidth) && measuredWidth > 0) {
      this.ideaDragPreviewWidth = measuredWidth;
    }
    if (!Number.isNaN(measuredHeight) && measuredHeight > 0) {
      this.ideaDragPreviewHeight = measuredHeight;
    }
  }

  private updateCollectionDragPreviewSize(newValue: Area): void {
    const measuredWidth: number = Number(newValue.width);
    const measuredHeight: number = Number(newValue.height);
    if (!Number.isNaN(measuredWidth) && measuredWidth > 0) {
      this.collectionDragPreviewWidth = measuredWidth;
    }
    if (!Number.isNaN(measuredHeight) && measuredHeight > 0) {
      this.collectionDragPreviewHeight = measuredHeight;
    }
  }

  @Builder
  private buildIdeaDragPreview(activity: IdeaActivity) {
    Column() {
      IdeaCard({
        idea: activity,
        relativeTimeBaseline: this.relativeTimeBaseline,
        isInteractionEnabled: false
      })
        .width(this.ideaDragPreviewWidth)
        .height(this.ideaDragPreviewHeight)
    }
    .width(this.ideaDragPreviewWidth)
    .height(this.ideaDragPreviewHeight)
    .clip(false)
  }

  @Builder
  private buildCollectionDragPreview(item: IdeaCollectionCardEntryViewModel) {
    Column() {
      IdeaCollectionCard({
        entry: item,
        isInteractionEnabled: false,
        isProgressiveBlurEnabled: false
      })
        .width(this.collectionDragPreviewWidth)
        .height(this.collectionDragPreviewHeight)
    }
    .width(this.collectionDragPreviewWidth)
    .height(this.collectionDragPreviewHeight)
    .clip(false)
  }

  private mergeReorderedIdeaGroup(
    reorderedGroup: IdeaActivity[],
    source: IdeaPoolDragSource
  ): IdeaActivity[] {
    const merged: IdeaActivity[] = [];
    let groupIndex: number = 0;
    const orderedActivities: IdeaActivity[] = this.sortActivitiesByDisplayOrder(this.ideaActivities);
    for (const activity of orderedActivities) {
      const belongsToSource: boolean = source === IdeaPoolDragSource.LIT
        ? activity.ideaLightState === IdeaLightState.LIT
        : activity.ideaLightState !== IdeaLightState.LIT;
      if (belongsToSource) {
        merged.push(reorderedGroup[groupIndex]);
        groupIndex += 1;
      } else {
        merged.push(activity);
      }
    }
    return merged;
  }

  private async reorderIdeas(
    source: IdeaPoolDragSource,
    itemIndex: number,
    insertIndex: number,
    isSuccess: boolean
  ): Promise<void> {
    if (this.activeDragSource !== source) {
      this.showRejectedDropToast(source);
      this.activeDragSource = IdeaPoolDragSource.NONE;
      return;
    }
    if (!isSuccess) {
      return;
    }
    this.activeDragSource = IdeaPoolDragSource.NONE;
    const sourceItems: IdeaActivity[] = source === IdeaPoolDragSource.LIT
      ? this.animatedLitIdeas
      : this.animatedUnlitIdeas;
    if (!this.isEditingIdeas || this.isReordering ||
      itemIndex < 0 || itemIndex >= sourceItems.length ||
      insertIndex < 0 || insertIndex >= sourceItems.length || itemIndex === insertIndex) {
      return;
    }

    const previousGroup: IdeaActivity[] = sourceItems.slice();
    const reorderedGroup: IdeaActivity[] = sourceItems.slice();
    const moved: IdeaActivity[] = reorderedGroup.splice(itemIndex, 1);
    reorderedGroup.splice(insertIndex, 0, moved[0]);
    sourceItems.splice(0, sourceItems.length, ...reorderedGroup);
    const merged: IdeaActivity[] = this.mergeReorderedIdeaGroup(reorderedGroup, source);
    this.isReordering = true;
    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const savedOrder: SortEntry[] = await service.reorderIdeas(
        this.defaultUserId,
        merged.map((activity: IdeaActivity): string => activity.id)
      );
      if (savedOrder.length !== merged.length) {
        throw new Error('Idea order update was not fully persisted.');
      }
      for (let index: number = 0; index < merged.length; index += 1) {
        merged[index].displayOrder = index + 1;
      }
      this.ideaActivities.splice(0, this.ideaActivities.length, ...merged);
      this.ideaPoolState.activities = this.ideaActivities;
      this.ideaPoolState.ideaPoolOrder = savedOrder;
      void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
    } catch (error) {
      sourceItems.splice(0, sourceItems.length, ...previousGroup);
      hilog.error(0x0000, TAG, `Failed to reorder ideas: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: $r('app.string.ideapool_sort_save_failed'),
        duration: 1200
      }).catch(() => {
      });
      await this.refreshIdeaPoolState({ animate: false });
    } finally {
      this.isReordering = false;
    }
  }

  private async reorderCollections(
    itemIndex: number,
    insertIndex: number,
    isSuccess: boolean
  ): Promise<void> {
    if (this.activeDragSource !== IdeaPoolDragSource.COLLECTION) {
      this.activeDragSource = IdeaPoolDragSource.NONE;
      return;
    }
    if (!isSuccess) {
      return;
    }
    this.activeDragSource = IdeaPoolDragSource.NONE;
    if (!this.isEditingCollections || this.isReordering ||
      itemIndex < 0 || itemIndex >= this.ideaCollectionCardEntries.length ||
      insertIndex < 0 || insertIndex >= this.ideaCollectionCardEntries.length || itemIndex === insertIndex) {
      return;
    }

    const previous: IdeaCollectionCardEntryViewModel[] = this.ideaCollectionCardEntries.slice();
    const reordered: IdeaCollectionCardEntryViewModel[] = this.ideaCollectionCardEntries.slice();
    const moved: IdeaCollectionCardEntryViewModel[] = reordered.splice(itemIndex, 1);
    reordered.splice(insertIndex, 0, moved[0]);
    this.ideaCollectionCardEntries.splice(0, this.ideaCollectionCardEntries.length, ...reordered);
    this.isReordering = true;
    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const saved: boolean = await service.reorderIdeaCollections(
        this.defaultUserId,
        reordered.map((item: IdeaCollectionCardEntryViewModel): string => item.id)
      );
      if (!saved) {
        throw new Error('Idea collection order update failed.');
      }
      void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
    } catch (error) {
      this.ideaCollectionCardEntries.splice(0, this.ideaCollectionCardEntries.length, ...previous);
      hilog.error(0x0000, TAG, `Failed to reorder idea collections: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: $r('app.string.ideapool_sort_save_failed'),
        duration: 1200
      }).catch(() => {
      });
      await this.refreshIdeaPoolState({ animate: false });
    } finally {
      this.isReordering = false;
    }
  }

  private getIdeaListLaneIndexes(): number[] {
    const lanes: number = this.getIdeaListLanes();
    const indexes: number[] = [];
    for (let index: number = 0; index < lanes; index++) {
      indexes.push(index);
    }
    return indexes;
  }

  private getIdeaListBottomSpacerHeight(): number {
    if (this.useFloatingActionBar) {
      return FLOATING_TAB_BAR_BOTTOM_SPACER_HEIGHT;
    }
    return IDEAPOOL_LIST_BOTTOM_SPACER_HEIGHT.getValue(this.currentBreakpoint);
  }

  private getIdeaListRowWidthPercent(): string {
    return `${this.getIdeaListLanes() * 100}%`;
  }

  private getCurrentIdeaListFilter(): IdeaPoolListFilter {
    if (!this.segmentSelectedIndexes || this.segmentSelectedIndexes.length <= 0) {
      return IdeaPoolListFilter.ALL;
    }
    const selected: IdeaPoolListFilter = this.segmentSelectedIndexes[0] as IdeaPoolListFilter;
    if (selected === IdeaPoolListFilter.UNLIT || selected === IdeaPoolListFilter.LIT) {
      return selected;
    }
    return IdeaPoolListFilter.ALL;
  }

  private shouldRenderUnlitIdeas(): boolean {
    const filter: IdeaPoolListFilter = this.getCurrentIdeaListFilter();
    return filter === IdeaPoolListFilter.ALL || filter === IdeaPoolListFilter.UNLIT;
  }

  private shouldRenderLitIdeas(): boolean {
    const filter: IdeaPoolListFilter = this.getCurrentIdeaListFilter();
    return filter === IdeaPoolListFilter.ALL || filter === IdeaPoolListFilter.LIT;
  }

  private shouldRenderUnlitFirst(): boolean {
    return this.ideapoolUnlitFirst;
  }

  private ensureSectionHeaderContent(): void {
    if (this.litHeaderContent && this.unlitHeaderContent) {
      return;
    }
    const uiContext: UIContext = this.getUIContext();
    this.litHeaderContent = new ComponentContent<IdeaSectionHeaderParams>(
      uiContext,
      wrapBuilder(ideaSectionHeader),
      new IdeaSectionHeaderParams($r('app.string.ideapool_section_lit'), this.getIdeaListRowWidthPercent())
    );
    this.unlitHeaderContent = new ComponentContent<IdeaSectionHeaderParams>(
      uiContext,
      wrapBuilder(ideaSectionHeader),
      new IdeaSectionHeaderParams($r('app.string.ideapool_section_unlit'), this.getIdeaListRowWidthPercent())
    );
  }

  private getLitSectionHeader(): ComponentContent<IdeaSectionHeaderParams> | undefined {
    this.ensureSectionHeaderContent();
    this.litHeaderContent?.update(
      new IdeaSectionHeaderParams($r('app.string.ideapool_section_lit'), this.getIdeaListRowWidthPercent())
    );
    return this.litHeaderContent;
  }

  private getUnlitSectionHeader(): ComponentContent<IdeaSectionHeaderParams> | undefined {
    this.ensureSectionHeaderContent();
    this.unlitHeaderContent?.update(
      new IdeaSectionHeaderParams($r('app.string.ideapool_section_unlit'), this.getIdeaListRowWidthPercent())
    );
    return this.unlitHeaderContent;
  }

  @Builder
  private renderUnlitIdeaListGroup() {
    if (this.shouldRenderUnlitIdeas() && this.animatedUnlitIdeas.length > 0) {
      Column() {
        ideaSectionHeader(
          new IdeaSectionHeaderParams($r('app.string.ideapool_section_unlit'), this.getIdeaListRowWidthPercent())
        )
        Grid() {
          ForEach(this.animatedUnlitIdeas, (activity: IdeaActivity) => {
            GridItem() {
            Stack({ alignContent: Alignment.TopEnd }) {
              IdeaCard({
                idea: activity,
                relativeTimeBaseline: this.relativeTimeBaseline,
                isInteractionEnabled: !this.isEditingIdeas,
                // onExpand: () => {
                //   if (!this.isEditingIdeas) {
                //     void this.openIdeaEditSheet(activity);
                //   }
                // },
                onEdit: () => {
                  void this.openIdeaEditSheet(activity);
                },
                onMoveToToday: () => {
                  void this.handleMoveIdeaToToday(activity);
                },
                onLongPress: () => {
                  this.handleIdeaCardLongPress(activity);
                }
              })
                .height('100%')
                .rotate({
                  x: 0,
                  y: 0,
                  z: 1,
                  angle: this.isEditingIdeas ? this.ideaShakeAngle * this.getCardShakePhase(activity.id) : 0,
                  centerX: '50%',
                  centerY: '50%'
                })
                .translate({ x: this.isEditingIdeas ? 0.8 * this.getCardShakePhase(activity.id) : 0 })

              if (this.isEditingIdeas) {
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.xmark'))
                    .fontColor([$r('app.color.neutral_100')])
                    .fontSize(12)
                    .fontWeight(700)
                }
                .backgroundColor($r('app.color.error'))
                .translate({ x: 6, y: 6 })
                .shadow(this.getDestructiveActionShadow())
                .onClick(() => {
                  this.showDeleteIdeaDialog(activity);
                })
                .transition(TransitionEffect.IDENTITY)
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
                .width(20)
                .height(20)
              }
            }
            .width('100%')
            .height(165)
            .key(`ideaCard_${activity.id}`)
            .clickEffect({ level: ClickEffectLevel.HEAVY, scale: 0.9 })
          }
          .onAreaChange((_: Area, newValue: Area): void => {
            this.updateIdeaDragPreviewSize(newValue);
          })
          .transition(this.isEditingIdeas ? TransitionEffect.IDENTITY : TransitionEffect.opacity(0.0)
              .combine(TransitionEffect.translate({ y: 30 }))
              .animation({ curve: curves.springMotion(), duration: 300 }))
          .height(165)
          .width('100%')
          }, (activity: IdeaActivity) => activity.id)
        }
        .columnsTemplate(this.getIdeaGridColumnsTemplate())
        .columnsGap($r('app.float.ideapool_idea_grid_gap'))
        .rowsGap($r('app.float.ideapool_idea_grid_gap'))
        .editMode(this.isEditingIdeas)
        .supportAnimation(true)
        .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
          this.activeDragSource = IdeaPoolDragSource.UNLIT;
          void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
          return this.buildIdeaDragPreview(this.animatedUnlitIdeas[itemIndex]);
        })
        .onItemDrop((
          event: ItemDragInfo,
          itemIndex: number,
          insertIndex: number,
          isSuccess: boolean
        ): void => {
          void this.reorderIdeas(IdeaPoolDragSource.UNLIT, itemIndex, insertIndex, isSuccess);
        })
        .width('100%')
        .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
        .clip(false)
      }
      .width('100%')
    }
  }

  @Builder
  private renderLitIdeaListGroup() {
    if (this.shouldRenderLitIdeas() && this.animatedLitIdeas.length > 0) {
      Column() {
        ideaSectionHeader(
          new IdeaSectionHeaderParams($r('app.string.ideapool_section_lit'), this.getIdeaListRowWidthPercent())
        )
        Grid() {
          ForEach(this.animatedLitIdeas, (activity: IdeaActivity) => {
            GridItem() {
            Stack({ alignContent: Alignment.TopEnd }) {
              IdeaCard({
                idea: activity,
                relativeTimeBaseline: this.relativeTimeBaseline,
                isInteractionEnabled: !this.isEditingIdeas,
                // onExpand: () => {
                //   if (!this.isEditingIdeas) {
                //     void this.openIdeaEditSheet(activity);
                //   }
                // },
                onEdit: () => {
                  void this.openIdeaEditSheet(activity);
                },
                onMoveToToday: () => {
                  void this.handleMoveIdeaToToday(activity);
                },
                onLongPress: () => {
                  this.handleIdeaCardLongPress(activity);
                }
              })
                .height('100%')
                .rotate({
                  x: 0,
                  y: 0,
                  z: 1,
                  angle: this.isEditingIdeas ? this.ideaShakeAngle * this.getCardShakePhase(activity.id) : 0,
                  centerX: '50%',
                  centerY: '50%'
                })
                .translate({ x: this.isEditingIdeas ? 0.8 * this.getCardShakePhase(activity.id) : 0 })

              if (this.isEditingIdeas) {
                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.xmark'))
                    .fontColor([$r('app.color.neutral_100')])
                    .fontSize(12)
                    .fontWeight(700)
                }
                .backgroundColor($r('app.color.error'))
                .translate({ x: 6, y: 6 })
                .shadow(this.getDestructiveActionShadow())
                .onClick(() => {
                  this.showDeleteIdeaDialog(activity);
                })
                .transition(TransitionEffect.IDENTITY)
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
                .width(20)
                .height(20)
              }
            }
            .width('100%')
            .height(165)
            .key(`ideaCard_${activity.id}`)
            .clickEffect({ level: ClickEffectLevel.HEAVY, scale: 0.9 })
          }
          .onAreaChange((_: Area, newValue: Area): void => {
            this.updateIdeaDragPreviewSize(newValue);
          })
          .transition(this.isEditingIdeas ? TransitionEffect.IDENTITY : TransitionEffect.opacity(0.0)
              .combine(TransitionEffect.translate({ y: 30 }))
              .animation({ curve: curves.springMotion(), duration: 300 }))
          .height(165)
          .width('100%')
          }, (activity: IdeaActivity) => activity.id)
        }
        .columnsTemplate(this.getIdeaGridColumnsTemplate())
        .columnsGap($r('app.float.ideapool_idea_grid_gap'))
        .rowsGap($r('app.float.ideapool_idea_grid_gap'))
        .editMode(this.isEditingIdeas)
        .supportAnimation(true)
        .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
          this.activeDragSource = IdeaPoolDragSource.LIT;
          void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
          return this.buildIdeaDragPreview(this.animatedLitIdeas[itemIndex]);
        })
        .onItemDrop((
          event: ItemDragInfo,
          itemIndex: number,
          insertIndex: number,
          isSuccess: boolean
        ): void => {
          void this.reorderIdeas(IdeaPoolDragSource.LIT, itemIndex, insertIndex, isSuccess);
        })
        .width('100%')
        .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
        .clip(false)
      }
      .width('100%')
    }
  }

  @Builder
  private renderIdeaListBottomSpacers() {
    ForEach(this.getIdeaListLaneIndexes(), (laneIndex: number) => {
      ListItem() {
        Row()
      }
      .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
      .width('100%')
      .height(this.getIdeaListBottomSpacerHeight())
    }, (laneIndex: number) => `idea_bottom_spacer_lane_${laneIndex}`)
  }

  @Builder
  private renderIdeaPoolEmptyState() {
    Column() {
      Image($r('app.media.no_idea_yet'))
        .width($r('app.float.ideapool_empty_icon_size'))
        .height($r('app.float.ideapool_empty_icon_size'))
        .objectFit(ImageFit.Contain)

      Text($r('app.string.no_idea_yet'))
        .fontSize($r('app.float.ideapool_empty_text_font_size'))
        .fontWeight(400)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: $r('app.float.ideapool_empty_text_top_margin') })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: $r('app.float.ideapool_empty_top_margin') })
    .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
  }

  @Builder
  private renderIdeaCollections() {
    if (this.isCollectionLoading) {
      Scroll() {
        Row({ space: IDEAPOOL_COLLECTION_CARD_GUTTER }) {
          Stack({ alignContent: Alignment.Center }) {
            LoadingProgress()
              .width(24)
              .height(24)
          }
          .width(this.getIdeaCollectionEffectiveWidth())
          .height(this.getIdeaCollectionEffectiveHeight())
          .key('collection_loading')
        }
        .height(this.getIdeaCollectionEffectiveHeight())
        .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .align(Alignment.Start)
      .edgeEffect(EdgeEffect.Spring)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .clip(false)
      .height(IDEAPOOL_COLLECTION_CARD_HEIGHT)
      .padding({ top: 8, bottom: 16 })
    } else {
      Grid() {
          ForEach(this.ideaCollectionCardEntries, (item: IdeaCollectionCardEntryViewModel, index: number) => {
            GridItem() {
              Stack({ alignContent: Alignment.TopEnd }) {
                IdeaCollectionCard({
                  entry: item,
                  isInteractionEnabled: !this.isEditingCollections,
                  onOpen: () => {
                    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
                    this.openIdeaCollectionDetail(item.collection);
                  }
                })
                  .width('100%')
                  .height('100%')
                  .rotate({
                    x: 0,
                    y: 0,
                    z: 1,
                    angle: this.isEditingCollections ?
                      this.collectionShakeAngle * this.getCardShakePhase(item.id) : 0,
                    centerX: '50%',
                    centerY: '50%'
                  })
                  .translate({
                    x: this.isEditingCollections ? 0.8 * this.getCardShakePhase(item.id) : 0
                  })

                if (this.isEditingCollections) {
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontColor([$r('app.color.neutral_100')])
                      .fontSize(12)
                      .fontWeight(700)
                  }
                  .backgroundColor($r('app.color.error'))
                  .translate({ x: 6, y: 6 })
                  .shadow(this.getDestructiveActionShadow())
                  .onClick(() => {
                    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
                    this.showDeleteCollectionDialog(item.collection);
                  })
                  .transition(TransitionEffect.IDENTITY)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
                  .width(20)
                  .height(20)
                }
            }
                .width('100%')
                .height('100%')
                .key(`ideaCollectionCard_${item.id}`)
                .transition(this.isEditingCollections ? TransitionEffect.IDENTITY :
                  TransitionEffect.OPACITY.combine(TransitionEffect.scale({x: 0, y: 0})).animation({
                    curve: curves.springMotion(),
                    duration: 250,
                    delay: 100 * index
                  }))
            }
            .width(this.getIdeaCollectionEffectiveWidth())
            .height(this.getIdeaCollectionEffectiveHeight())
            .onAreaChange((_: Area, newValue: Area): void => {
              this.updateCollectionDragPreviewSize(newValue);
            })
          }, (item: IdeaCollectionCardEntryViewModel) => item.id)
          if (!this.isEditingCollections) {
            GridItem() {
              this.addIdeaCollectionPlaceholderBuilder()
            }
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({x: 0, y: 0})).animation({curve: curves.springMotion(), duration: 250}))
            .width(this.getIdeaCollectionEffectiveWidth())
            .height(this.getIdeaCollectionEffectiveHeight())
          }
      }
      .rowsTemplate('1fr')
      .columnsGap(IDEAPOOL_COLLECTION_CARD_GUTTER)
      .editMode(this.isEditingCollections)
      .supportAnimation(true)
      .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
        this.activeDragSource = IdeaPoolDragSource.COLLECTION;
        void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
        return this.buildCollectionDragPreview(this.ideaCollectionCardEntries[itemIndex]);
      })
      .onItemDrop((
        event: ItemDragInfo,
        itemIndex: number,
        insertIndex: number,
        isSuccess: boolean
      ): void => {
        void this.reorderCollections(itemIndex, insertIndex, isSuccess);
      })
      .width('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .clip(false)
      .height(IDEAPOOL_COLLECTION_CARD_HEIGHT)
      .padding({
        left: $r('app.float.page_content_padding_horizontal'),
        right: $r('app.float.page_content_padding_horizontal'),
        top: 8,
        bottom: 16
      })
    }
  }

  @Builder
  private renderBarDivider() {
    Divider().strokeWidth(1).color($r('app.color.neutral_200')).padding({left: 12, right: 12, top: 10, bottom: 10})
  }

  @Builder
  private renderIdeaFilterSegment() {
    Row() {
      SegmentButton({ options: this.segmentOptions, selectedIndexes: this.segmentSelectedIndexes })
        .width('100%')
        // .height(32)
        .borderRadius('50%')
        .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
        })
    }
    .width('100%')
    .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal'), bottom: 8 })
    // .margin({ top: 2 })
  }

  private recalculateSheetHeight(tagCount?: number): void {
    const count = tagCount !== undefined ? tagCount : this.tagData.length;
    this.sheetHeight = this.computeSheetHeight(count);
  }

  private updateIdeaFormSheetDetents(): void {
    if ((this.isShow || this.isIdeaEditSheetShow) && this.keyboardHeight > 0) {
      this.ideaFormSheetDetents = [SheetSize.LARGE];
      return;
    }
    this.ideaFormSheetDetents = [SheetSize.MEDIUM, SheetSize.LARGE];
  }

  private syncIdeaCollectionCardsFromState(animate: boolean = false): void {
    const nextEntries: IdeaCollectionCardEntry[] = IdeaPoolService.buildIdeaCollectionCardEntries(
      this.ideaCollections,
      this.ideaCollectionSummaries
    );
    const shouldAnimate: boolean = animate && nextEntries.length !== this.ideaCollectionCardEntries.length;
    const existingById: Map<string, IdeaCollectionCardEntryViewModel> = new Map(
      this.ideaCollectionCardEntries.map((entry: IdeaCollectionCardEntryViewModel): [string, IdeaCollectionCardEntryViewModel] => [entry.id, entry])
    );
    const merged: IdeaCollectionCardEntryViewModel[] = [];
    for (let index: number = 0; index < nextEntries.length; index += 1) {
      const nextEntry: IdeaCollectionCardEntry = nextEntries[index];
      const existing: IdeaCollectionCardEntryViewModel | undefined = existingById.get(nextEntry.id);
      if (existing) {
        existing.collection = nextEntry.collection;
        existing.ideaCount = nextEntry.ideaCount;
        merged.push(existing);
      } else {
        merged.push(new IdeaCollectionCardEntryViewModel(nextEntry.id, nextEntry.collection, nextEntry.ideaCount));
      }
    }
    const applyUpdate = () => {
      this.ideaCollectionCardEntries.splice(0, this.ideaCollectionCardEntries.length, ...merged);
    };
    if (shouldAnimate) {
      const uiContext = this.getUIContext();
      if (uiContext) {
        uiContext.animateTo({ duration: this.deleteAnimationDuration, curve: curves.springMotion() }, applyUpdate);
        return;
      }
    }
    applyUpdate();
  }

  private resolvePageContentPaddingHorizontal(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (!hostContext) {
      return;
    }
    const paddingPx: number = hostContext.resourceManager
      .getNumber($r('app.float.page_content_padding_horizontal').id);
    if (paddingPx > 0) {
      this.pageContentPaddingHorizontalVp = this.getUIContext().px2vp(paddingPx);
    }
  }

  private getIdeaCollectionCardWidth(): number {
    if (this.viewportWidth <= 0) {
      return 170;
    }
    const lanes: number = this.getIdeaListLanes();
    const availableWidth: number = this.viewportWidth - this.pageContentPaddingHorizontalVp * 2;
    const gutterWidth: number = IDEAPOOL_COLLECTION_CARD_GUTTER * (lanes - 1);
    const candidate: number = (availableWidth - gutterWidth) / lanes;
    return candidate > 0 ? candidate : 170;
  }

  private getIdeaCollectionEffectiveWidth(): number {
    return this.getIdeaCollectionCardWidth() * 0.92;
  }

  private getIdeaCollectionEffectiveHeight(): number {
    return IDEAPOOL_COLLECTION_CARD_HEIGHT * 0.88;
  }

  private updateRelativeTimeBaseline(): void {
    this.relativeTimeBaseline = Date.now();
  }

  private shouldEnableIdeaPoolContent(): boolean {
    return this.ideaExpandAnimationProps === null ? true : !this.ideaExpandAnimationProps.isExpandPageShow;
  }

  private shouldEnableIdeaPoolRoot(): boolean {
    return this.ideaExpandAnimationProps === null ? true : this.ideaExpandAnimationProps.isEnabled;
  }

  private handleIdeaCardLongPress(activity: IdeaActivity): void {
    if (this.isEditingIdeas) {
      return;
    }
    if (this.ideaExpandAnimationProps === null) {
      return;
    }
    if (this.ideaExpandAnimationProps.isExpandPageShow) {
      return;
    }
    this.updateRelativeTimeBaseline();
    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
    this.ideaExpandAnimationProps.expandAnimation(activity, this.relativeTimeBaseline);
    void this.syncExpandedIdeaCollection(activity);
  }

  private async syncExpandedIdeaCollection(activity: IdeaActivity): Promise<void> {
    if (this.ideaExpandAnimationProps === null) {
      return;
    }
    const activityId: string = activity.id;
    this.ideaExpandAnimationProps.currentCollectionId = null;
    try {
      await this.ensureCollectionStateLoaded();
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const resolvedCollectionId: string | null = await service.resolveCollectionIdByActivity(activityId);
      const normalizedCollectionId: string | null = this.normalizeCollectionId(resolvedCollectionId);
      if (this.ideaExpandAnimationProps !== null && this.ideaExpandAnimationProps.currentIdea?.id === activityId) {
        this.ideaExpandAnimationProps.currentCollectionId = normalizedCollectionId;
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `syncExpandedIdeaCollection failed: ${JSON.stringify(error)}`);
    }
  }

  private async ensureIdeaPoolService(): Promise<IdeaPoolService> {
    if (!this.ideaPoolServiceReady) {
      const uiContext = this.getUIContext();
      const hostContext = uiContext ? uiContext.getHostContext() : undefined;
      if (!hostContext) {
        throw new Error('Unable to initialize IdeaPoolService without a host context.');
      }
      try {
        await initIdeaPoolService(hostContext);
        this.ideaPoolServiceReady = true;
      } catch (error) {
        this.ideaPoolServiceReady = false;
      }
    }
    return IdeaPoolService.getInstance();
  }

  private async ensureCollectionStateLoaded(): Promise<void> {
    if (Array.isArray(this.ideaCollections) && this.ideaCollections.length > 0) {
      if (!Array.isArray(this.ideaCollectionCardEntries) || this.ideaCollectionCardEntries.length === 0) {
        this.syncIdeaCollectionCardsFromState();
      }
      this.isCollectionLoading = false;
      return;
    }

    try {
      const store: RDBStoreUtil = RDBStoreUtil.getInstance();
      const collections: IdeaCollection[] = await store.queryIdeaCollections();
      const summaries: IdeaCollectionSummary[] = await store.queryIdeaCollectionSummaries();
      this.ideaCollections = Array.isArray(collections) ? [...collections] : [];
      this.ideaCollectionSummaries = Array.isArray(summaries) ? [...summaries] : [];
      this.syncIdeaCollectionCardsFromState();
      this.syncSelectableCollectionsFromState();
      this.isCollectionLoading = false;
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to ensure collection state loaded: ${JSON.stringify(error)}`);
    }
  }

  private sortActivitiesByDisplayOrder(activities: IdeaActivity[]): IdeaActivity[] {
    if (!Array.isArray(activities) || activities.length <= 1) {
      return Array.isArray(activities) ? [...activities] : [];
    }
    const sorted: IdeaActivity[] = [...activities];
    sorted.sort((left: IdeaActivity, right: IdeaActivity) => {
      const leftOrder: number = typeof left.displayOrder === 'number' ? left.displayOrder : Number.MAX_SAFE_INTEGER;
      const rightOrder: number = typeof right.displayOrder === 'number' ? right.displayOrder : Number.MAX_SAFE_INTEGER;
      if (leftOrder !== rightOrder) {
        return leftOrder - rightOrder;
      }
      const leftId: string = left.id ?? '';
      const rightId: string = right.id ?? '';
      return leftId.localeCompare(rightId);
    });
    return sorted;
  }

  private updateIdeaActivities(nextActivities: IdeaActivity[], animateList: boolean = false): void {
    // For activities that exist in both arrays, update properties in place
    // to maintain @ObjectLink references. For new items, add them.
    const sortedActivities: IdeaActivity[] = this.sortActivitiesByDisplayOrder(nextActivities);
    const shouldAnimate: boolean = animateList && sortedActivities.length !== this.ideaActivities.length;
    const existingItems = new Map<string, IdeaActivity>();
    for (const item of this.ideaActivities) {
      existingItems.set(item.id, item);
    }

    const orderedActivities: IdeaActivity[] = [];
    for (const nextItem of sortedActivities) {
      const existingItem = existingItems.get(nextItem.id);
      if (existingItem) {
        // Update properties directly to trigger @Observed reactivity
        existingItem.name = nextItem.name;
        existingItem.status = nextItem.status;
        existingItem.ideaType = nextItem.ideaType;
        existingItem.ideaLightState = nextItem.ideaLightState;
        existingItem.ideaLightCount = nextItem.ideaLightCount;
        existingItem.tagId = nextItem.tagId;
        existingItem.tagName = nextItem.tagName;
        existingItem.tagColorHex = nextItem.tagColorHex;
        existingItem.tagLightColorHex = nextItem.tagLightColorHex;
        existingItem.createdAt = nextItem.createdAt;
        existingItem.updatedAt = nextItem.updatedAt;
        existingItem.displayOrder = nextItem.displayOrder;
        orderedActivities.push(existingItem);
      } else {
        orderedActivities.push(nextItem);
      }
    }

    this.ideaActivities.splice(0, this.ideaActivities.length, ...orderedActivities);
    this.ideaPoolState.activities = this.ideaActivities;

    if (this.editingIdea) {
      const refreshed = this.ideaActivities.find(item => item.id === this.editingIdea?.id);
      if (refreshed) {
        this.editingIdea = refreshed;
      }
    }

    if (this.ideaActivities.length === 0 && this.isEditingIdeas) {
      this.updateIdeaEditingState(false);
    }

    this.updateRelativeTimeBaseline();
    this.syncAnimatedIdeaLists(shouldAnimate);
    this.syncIdeaLightCountsFromActivities();
  }

  @Builder
  private renderIdeaListLoading() {
    List() {
      ListItem() {
        Stack({ alignContent: Alignment.Center }) {
          LoadingProgress()
            .width(24)
            .height(24)
        }
        .width('100%')
        .height('100%')
      }
      .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
      .height(165)
      .width('100%')
      .key('idea_loading')

      this.renderIdeaListBottomSpacers();
    }
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .lanes(this.getIdeaListLanes())
    .enableScrollInteraction(false)
  }

  @Builder
  refreshBuilder() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 可以通过刷新状态控制是否存在Progress组件。
      // 当刷新状态处于下拉中或刷新中状态时Progress组件才存在。
      if (this.shouldRunRefreshAnimation()) {
        Progress({ value: this.refreshOffset, total: 150, type: ProgressType.Ring })
          .width(24).height(24)
          .color($r('app.color.primary'))
          .style({ status: this.refreshing ? ProgressStatus.LOADING : ProgressStatus.PROGRESSING })
          .margin(10)
      }
    }
    .offset({ y: 100 })
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
      this.activeMainTabIndex === 2 &&
      !this.userGuideSheetVisible;
  }

  private reconcileForegroundAnimationState(): void {
    if (!this.shouldAllowForegroundAnimations()) {
      this.stopTagShakeAnimation();
      this.stopIdeaCardShakeAnimation();
      this.stopCollectionCardShakeAnimation();
      return;
    }
    if (this.isEditingTag) {
      this.startTagShakeAnimation();
    } else {
      this.stopTagShakeAnimation();
    }
    if (this.isEditingIdeas) {
      this.startIdeaCardShakeAnimation();
    } else {
      this.stopIdeaCardShakeAnimation();
    }
    if (this.isEditingCollections) {
      this.startCollectionCardShakeAnimation();
    } else {
      this.stopCollectionCardShakeAnimation();
    }
  }

  private onVisibilityGateStateChanged(): void {
    this.syncIdeaPoolVisibilityGate('state_changed');
  }

  private syncIdeaPoolVisibilityGate(source: string): void {
    const pageVisible = this.pageLifecycleVisible &&
      this.activeMainTabIndex === 2 &&
      !this.userGuideSheetVisible &&
      !this.isShow &&
      !this.isIdeaEditSheetShow &&
      !this.isCollectionAddSheetShow;
    this.ideaPoolPageVisible = pageVisible;
    AppStorage.setOrCreate('ideaPoolPageVisible', pageVisible);
    if (!pageVisible && this.refreshState !== RefreshStatus.Inactive) {
      this.refreshing = false;
      this.refreshState = RefreshStatus.Done;
    }
    this.reconcileForegroundAnimationState();
    hilog.info(0x0000, TAG,
      `[IdeaPool] syncIdeaPoolVisibilityGate(${source}) -> visible=${pageVisible}, tab=${this.activeMainTabIndex}, guideVisible=${this.userGuideSheetVisible}, addSheet=${this.isShow}, editSheet=${this.isIdeaEditSheetShow}, collectionSheet=${this.isCollectionAddSheetShow}`);
  }

  private async refreshIdeaPoolData(): Promise<void> {
    this.refreshing = true;
    try {
      await this.refreshIdeaPoolState({
        animate: true,
        onApplied: () => {
          hilog.info(0x0000, TAG, 'IdeaPool data refreshed successfully');
        }
      });
      promptAction.openToast({
        message: '刷新成功',
        duration: 1000
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
    } catch (error) {
      hilog.error(0x0000, TAG, `Error refreshing idea pool data: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '刷新失败，请稍后重试',
        duration: 1000
      }).catch(() => {
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    } finally {
      this.refreshing = false;
      this.refreshState = RefreshStatus.Done;
    }
  }

  private async refreshIdeaPoolState(options: RefreshStateOptions = {}): Promise<void> {
    const animate: boolean = options.animate === true;
    const onApplied = options.onApplied;
    try {
      if (!this.hasLoadedIdeaPool) {
        this.isIdeaLoading = true;
        this.isCollectionLoading = true;
      }
      const ideaPoolService = await this.ensureIdeaPoolService();
      const nextState = await ideaPoolService.fetchIdeaPool(this.defaultUserId);
      const applyState = () => {
        this.applyIdeaPoolState(nextState, animate);
        onApplied?.();
      };
      const uiContext = this.getUIContext();

      if (animate && uiContext) {
        uiContext.animateTo({
          duration: 300,
          curve: curves.springMotion()
        }, applyState);
      } else {
        applyState();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh idea pool state: ${JSON.stringify(error)}`);
      if (!this.hasLoadedIdeaPool) {
        this.isIdeaLoading = false;
        this.isCollectionLoading = false;
      }
    }
  }

  private applyIdeaPoolState(nextState: IdeaPoolState, animate: boolean = false): void {
    const preferencesSource = nextState.preferences ?? this.ideaPoolState.preferences;
    const nextPreferences: IdeaPoolPreferencesState = {
      viewMode: preferencesSource.viewMode,
      enableDragPrototype: preferencesSource.enableDragPrototype,
      lastBulkSelection: Array.isArray(preferencesSource.lastBulkSelection)
        ? [...preferencesSource.lastBulkSelection]
        : []
    };

    // Direct property assignment to avoid ArkTS object literal issues
    this.updateIdeaActivities(nextState.activities, animate);
    this.ideaPoolState.tags = [...nextState.tags];
    this.ideaPoolState.ideaPoolOrder = [...nextState.ideaPoolOrder];
    this.ideaPoolState.todayOrder = [...nextState.todayOrder];
    this.ideaPoolState.globalSummary = nextState.globalSummary;
    this.ideaCollections = Array.isArray(nextState.collections) ? [...nextState.collections] : [];
    this.ideaCollectionSummaries = Array.isArray(nextState.collectionSummaries) ? [...nextState.collectionSummaries] : [];
    this.ideaPoolState.collections = this.ideaCollections;
    this.ideaPoolState.collectionSummaries = this.ideaCollectionSummaries;
    this.ideaPoolState.categories = Array.isArray(nextState.categories) ? [...nextState.categories] : [];
    this.ideaPoolState.categorySummaries = Array.isArray(nextState.categorySummaries) ? [...nextState.categorySummaries] : [];
    this.ideaPoolState.preferences.viewMode = nextPreferences.viewMode;
    this.ideaPoolState.preferences.enableDragPrototype = nextPreferences.enableDragPrototype;
    this.ideaPoolState.preferences.lastBulkSelection = nextPreferences.lastBulkSelection;

    this.updateTagListFromItems(nextState.tags);
    this.syncIdeaCollectionCardsFromState(animate);
    this.syncSelectableCollectionsFromState();
    this.isIdeaLoading = false;
    this.isCollectionLoading = false;
    this.hasLoadedIdeaPool = true;
  }

  private ensureIdeaPoolStorageDefaults(): void {
    if (AppStorage.get('ideapoolActivities') === undefined) {
      AppStorage.setOrCreate('ideapoolActivities', []);
    }
    if (AppStorage.get('ideapoolCollections') === undefined) {
      AppStorage.setOrCreate('ideapoolCollections', []);
    }
    if (AppStorage.get('ideapoolCollectionSummaries') === undefined) {
      AppStorage.setOrCreate('ideapoolCollectionSummaries', []);
    }
    if (AppStorage.get('ideapoolLitData') === undefined) {
      AppStorage.setOrCreate('ideapoolLitData', this.animatedLitIdeas);
    }
    if (AppStorage.get('ideapoolUnlitData') === undefined) {
      AppStorage.setOrCreate('ideapoolUnlitData', this.animatedUnlitIdeas);
    }
    if (AppStorage.get('ideapoolUnlitFirst') === undefined) {
      AppStorage.setOrCreate('ideapoolUnlitFirst', true);
    }
    if (AppStorage.get('ideapoolDirectRecord') === undefined) {
      AppStorage.setOrCreate('ideapoolDirectRecord', false);
    }
    if (AppStorage.get('ideapoolRefreshToken') === undefined) {
      AppStorage.setOrCreate('ideapoolRefreshToken', 0);
    }
  }

  private partitionIdeasByLightState(activities: IdeaActivity[]): IdeaLightPartitions {
    const lit: IdeaActivity[] = [];
    const unlit: IdeaActivity[] = [];
    for (const activity of activities) {
      if (activity.ideaLightState === IdeaLightState.LIT) {
        lit.push(activity);
      } else {
        unlit.push(activity);
      }
    }
    return new IdeaLightPartitions(lit, unlit);
  }

  private syncIdeaLightCountsFromActivities(): void {
    const summary: IdeaLightSummary = IdeaPoolService.deriveIdeaLightSummary(this.ideaActivities);
    this.litIdeaCount = summary.litCount;
    this.unlitIdeaCount = summary.unlitCount;
  }

  private syncAnimatedIdeaLists(animate: boolean = true): void {
    const uiContext = this.getUIContext();
    const sortedActivities: IdeaActivity[] = this.sortActivitiesByDisplayOrder(this.ideaActivities);
    const partition: IdeaLightPartitions = this.partitionIdeasByLightState(sortedActivities);
    const assign = () => {
      this.animatedLitIdeas.splice(0, this.animatedLitIdeas.length, ...partition.lit);
      this.animatedUnlitIdeas.splice(0, this.animatedUnlitIdeas.length, ...partition.unlit);
    };

    if (animate && uiContext) {
      uiContext.animateTo({ duration: 300, curve: curves.springMotion() }, assign);
    } else {
      assign();
    }
  }

  private updateTagListFromItems(tagItems: TagItem[]): void {
    const mappedTags: TagModel[] = tagItems.map(item => ({
      id: item.id,
      name: item.name,
      color: item.color,
      lightColor: item.lightColor
    } as TagModel));

    this.tagData = mappedTags;

    if (this.selectedTagIndex >= mappedTags.length) {
      this.selectedTagIndex = -1;
    }

    if (this.isIdeaEditSheetShow && this.editingIdea) {
      this.editingSelectedTagIndex = this.resolveTagIndex(this.editingIdea.tagId);
    }

    this.syncTagStorage();
    this.recalculateSheetHeight(mappedTags.length);
  }

  async handleAddIdeaButtonClick(name: string, tagId: string | null, collectionId: string | null): Promise<void> {
    // 验证输入
    if (!name || name.trim().length === 0) {
      hilog.error(0x0000, TAG, '灵感名称不能为空');
      return;
    }

    const trimmedName: string = name.trim();
    hilog.info(0x0000, TAG, `User trying to add idea: ${trimmedName} with tagId: ${tagId}`);

    try {
      const ideaPoolService = await this.ensureIdeaPoolService();
      const newIdea = await ideaPoolService.createIdea(this.defaultUserId, {
        name: trimmedName,
        tagId: tagId
      });

      if (newIdea) {
        let assignedCollectionId: string | null = null;
        const trimmedCollectionId: string = collectionId !== null && collectionId !== undefined
          ? collectionId.trim()
          : '';
        if (trimmedCollectionId.length > 0) {
          const assigned: boolean = await ideaPoolService.assignIdeaToCollection(
            this.defaultUserId,
            newIdea.id,
            trimmedCollectionId,
            999999
          );
          if (!assigned) {
            promptAction.openToast({
              message: '加入灵感集失败',
              duration: 1000
            }).catch(() => {
            });
          } else {
            assignedCollectionId = trimmedCollectionId;
          }
        }

        const applyAdd = () => {
          this.ideaActivities.push(newIdea);
          this.ideaPoolState.activities = this.ideaActivities;
          if (assignedCollectionId) {
            const isLit: boolean = newIdea.ideaLightState === IdeaLightState.LIT;
            this.updateCollectionSummaryCounts(assignedCollectionId, isLit ? 1 : 0, isLit ? 0 : 1);
          }
          this.updateRelativeTimeBaseline();
          this.syncAnimatedIdeaLists(false);
          this.syncIdeaLightCountsFromActivities();
        };
        const uiContext = this.getUIContext();
        if (uiContext) {
          uiContext.animateTo({ duration: this.deleteAnimationDuration, curve: curves.springMotion() }, applyAdd);
        } else {
          applyAdd();
        }

        promptAction.openToast({
          message: '灵感已添加',
          duration: 1000
        });

        hilog.info(0x0000, TAG, `Idea added to pool. Total ideas: ${this.ideaActivities.length}`);
      } else {
        hilog.error(0x0000, TAG, 'Failed to add the new idea to the database.');
        promptAction.openToast({
          message: '添加灵感失败',
          duration: 1000
        }).catch(() => {
        });
        void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Error adding idea: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '添加灵感时发生错误',
        duration: 1000
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    }
  }

  // ===== 灵感项编辑相关方法 =====

  private normalizeCollectionId(collectionId: string | null): string | null {
    if (!collectionId) {
      return null;
    }
    const trimmed: string = collectionId.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  private async syncEditingCollectionSelection(activityId: string): Promise<void> {
    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const resolvedCollectionId: string | null = await service.resolveCollectionIdByActivity(activityId);
      this.editingSelectedCollectionId = this.normalizeCollectionId(resolvedCollectionId);
      this.editingInitialCollectionId = this.normalizeCollectionId(resolvedCollectionId);
    } catch (error) {
      hilog.error(0x0000, TAG, `syncEditingCollectionSelection failed: ${JSON.stringify(error)}`);
      this.editingSelectedCollectionId = null;
      this.editingInitialCollectionId = null;
    }
  }

  private async applyCollectionAssignmentChanges(
    activityId: string,
    nextCollectionId: string | null,
    previousCollectionId: string | null
  ): Promise<void> {
    const trimmedNext: string | null = this.normalizeCollectionId(nextCollectionId);
    const trimmedPrev: string | null = this.normalizeCollectionId(previousCollectionId);
    if (trimmedNext === trimmedPrev) {
      return;
    }

    const service: IdeaPoolService = await this.ensureIdeaPoolService();
    if (trimmedNext !== null) {
      const assigned: boolean = await service.assignIdeaToCollection(this.defaultUserId, activityId, trimmedNext, 999999);
      if (!assigned) {
        promptAction.openToast({
          message: '更新灵感集失败',
          duration: 1000
        }).catch(() => {
        });
      }
      return;
    }

    if (trimmedPrev !== null) {
      const cleared: boolean = await service.clearIdeaCollectionAssignment(this.defaultUserId, activityId);
      if (!cleared) {
        promptAction.openToast({
          message: '移出灵感集失败',
          duration: 1000
        }).catch(() => {
        });
      }
    }
  }

  private resolveTagIndex(tagId: string | null): number {
    if (!tagId) {
      return -1;
    }
    if (!this.tagData || this.tagData.length === 0) {
      return -1;
    }
    return this.tagData.findIndex(item => item.id === tagId);
  }

  private resolveTagIdByIndex(index: number): string | null {
    if (index < 0 || index >= this.tagData.length) {
      return null;
    }
    return this.tagData[index].id;
  }

  private applyIdeaUpdateToLocalState(updated: IdeaActivity): void {
    // Find and directly mutate the object in the @State array
    // Since IdeaActivity is @Observed, this triggers reactivity automatically
    const target = this.ideaActivities.find(item => item.id === updated.id);
    
    if (target) {
      target.name = updated.name;
      target.status = updated.status;
      target.ideaType = updated.ideaType;
      target.ideaLightState = updated.ideaLightState;
      target.ideaLightCount = updated.ideaLightCount;
      target.tagId = updated.tagId;
      target.tagName = updated.tagName;
      target.tagColorHex = updated.tagColorHex;
      target.tagLightColorHex = updated.tagLightColorHex;
      target.createdAt = updated.createdAt;
      target.updatedAt = updated.updatedAt;
      target.displayOrder = updated.displayOrder;
      
      hilog.info(0x0000, TAG, `Updated idea ${updated.id} via direct mutation`);
    }
  }

  private async openIdeaEditSheet(activity: IdeaActivity): Promise<void> {
    this.resetEditIdeaForm();
    this.editingIdea = activity;
    this.editingIdeaName = activity.name;
    this.editingSelectedTagIndex = this.resolveTagIndex(activity.tagId);
    this.editingSelectedCollectionId = null;
    this.editingInitialCollectionId = null;
    await this.syncEditingCollectionSelection(activity.id);
    this.recalculateSheetHeight();
    this.stopIdeaCardShakeAnimation();
    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
    this.isIdeaEditSheetShow = true;
  }

  private async handleIdeaEditSave(): Promise<void> {
    if (!this.editingIdea) {
      return;
    }

    const trimmedName = this.editingIdeaName ? this.editingIdeaName.trim() : '';
    if (!trimmedName) {
      promptAction.openToast({
        message: '灵感名称不能为空',
        duration: 1000
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      return;
    }

    this.editingIdeaName = trimmedName;

    const selectedTagId = this.resolveTagIdByIndex(this.editingSelectedTagIndex);
    const targetCollectionId: string | null = this.normalizeCollectionId(this.editingSelectedCollectionId);
    const initialCollectionId: string | null = this.normalizeCollectionId(this.editingInitialCollectionId);

    if (this.isSavingIdeaEdit) {
      return;
    }

    this.isSavingIdeaEdit = true;

    try {
      const ideaPoolService = await this.ensureIdeaPoolService();
      const updated = await ideaPoolService.updateIdea(this.defaultUserId, this.editingIdea.id, {
        name: trimmedName,
        tagId: selectedTagId
      });

      if (!updated) {
        promptAction.openToast({
          message: '更新灵感失败',
          duration: 1000
        }).catch(() => {
        });
        await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
        return;
      }

      // Direct mutation of @Observed object in @State array triggers UI update
      this.applyIdeaUpdateToLocalState(updated);
      await this.applyCollectionAssignmentChanges(updated.id, targetCollectionId, initialCollectionId);
      await this.refreshIdeaPoolState({ animate: true });

      promptAction.openToast({
        message: '灵感已更新',
        duration: 1000
      }).catch(() => {
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');

      this.isIdeaEditSheetShow = false;
      this.resetEditIdeaForm();
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to update idea: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '更新灵感时发生错误',
        duration: 1000
      }).catch(() => {
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    } finally {
      this.isSavingIdeaEdit = false;
    }
  }

  private updateIdeaEditingState(nextState: boolean): void {
    if (this.isReordering) {
      return;
    }
    if (this.isEditingIdeas === nextState) {
      return;
    }

    if (nextState && this.isIdeaEditSheetShow) {
      return;
    }

    this.isEditingIdeas = nextState;
    if (nextState) {
      this.startIdeaCardShakeAnimation();
    } else {
      this.activeDragSource = IdeaPoolDragSource.NONE;
      this.stopIdeaCardShakeAnimation();
    }
  }

  private updateCollectionEditingState(nextState: boolean): void {
    if (this.isReordering) {
      return;
    }
    if (this.isEditingCollections === nextState) {
      return;
    }

    if (nextState && (this.isCollectionAddSheetShow || this.isIdeaEditSheetShow)) {
      return;
    }

    this.isEditingCollections = nextState;
    if (nextState) {
      this.startCollectionCardShakeAnimation();
    } else {
      this.activeDragSource = IdeaPoolDragSource.NONE;
      this.stopCollectionCardShakeAnimation();
      this.syncCollectionDisplayOrderFromEntries();
      this.syncSelectableCollectionsFromState();
    }
  }

  private syncCollectionDisplayOrderFromEntries(): void {
    const collectionById: Map<string, IdeaCollection> = new Map<string, IdeaCollection>();
    for (const collection of this.ideaCollections) {
      collectionById.set(collection.id, collection);
    }
    for (let index: number = 0; index < this.ideaCollectionCardEntries.length; index += 1) {
      const collection: IdeaCollection | undefined = collectionById.get(this.ideaCollectionCardEntries[index].id);
      if (collection) {
        collection.displayOrder = index + 1;
      }
    }
  }

  private startIdeaCardShakeAnimation(): void {
    if (!this.shouldAllowForegroundAnimations()) {
      return;
    }
    if (this.isIdeaCardShakeRunning) {
      return;
    }

    this.isIdeaCardShakeRunning = true;
    this.scheduleNextIdeaCardShake(this.ideaCardShakeAmplitude);
  }

  private stopIdeaCardShakeAnimation(): void {
    if (!this.isIdeaCardShakeRunning && this.ideaShakeAngle === 0) {
      return;
    }

    this.isIdeaCardShakeRunning = false;

    const uiContext = this.getUIContext();
    if (uiContext) {
      uiContext.animateTo({ duration: 0 }, () => {
        this.ideaShakeAngle = 0;
      });
    } else {
      this.ideaShakeAngle = 0;
    }
  }

  private scheduleNextIdeaCardShake(targetAngle: number): void {
    if (!this.isIdeaCardShakeRunning) {
      return;
    }
    if (!this.shouldAllowForegroundAnimations()) {
      this.stopIdeaCardShakeAnimation();
      return;
    }

    if (this.isIdeaEditSheetShow) {
      this.stopIdeaCardShakeAnimation();
      return;
    }

    const uiContext = this.getUIContext();
    if (!uiContext) {
      this.isIdeaCardShakeRunning = false;
      return;
    }

    uiContext.animateTo({
      duration: this.ideaCardShakeFrameDuration,
      curve: Curve.Linear,
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        if (!this.isIdeaCardShakeRunning || !this.shouldAllowForegroundAnimations()) {
          return;
        }
        const nextAngle = targetAngle === this.ideaCardShakeAmplitude
          ? -this.ideaCardShakeAmplitude
          : this.ideaCardShakeAmplitude;
        this.scheduleNextIdeaCardShake(nextAngle);
      }
    }, () => {
      if (!this.isIdeaCardShakeRunning || !this.shouldAllowForegroundAnimations()) {
        return;
      }
      this.ideaShakeAngle = targetAngle;
    });
  }

  private getCardShakePhase(id: string): number {
    let hash: number = 0;
    for (let index: number = 0; index < id.length; index += 1) {
      hash = ((hash << 5) - hash) + id.charCodeAt(index);
    }
    return hash % 2 === 0 ? 1 : -1;
  }

  private startCollectionCardShakeAnimation(): void {
    if (!this.shouldAllowForegroundAnimations()) {
      return;
    }
    if (this.isCollectionCardShakeRunning) {
      return;
    }

    this.isCollectionCardShakeRunning = true;
    this.scheduleNextCollectionCardShake(this.collectionCardShakeAmplitude);
  }

  private stopCollectionCardShakeAnimation(): void {
    if (!this.isCollectionCardShakeRunning && this.collectionShakeAngle === 0) {
      return;
    }

    this.isCollectionCardShakeRunning = false;

    const uiContext = this.getUIContext();
    if (uiContext) {
      uiContext.animateTo({ duration: 0 }, () => {
        this.collectionShakeAngle = 0;
      });
    } else {
      this.collectionShakeAngle = 0;
    }
  }

  private scheduleNextCollectionCardShake(targetAngle: number): void {
    if (!this.isCollectionCardShakeRunning) {
      return;
    }
    if (!this.shouldAllowForegroundAnimations()) {
      this.stopCollectionCardShakeAnimation();
      return;
    }

    if (this.isCollectionAddSheetShow) {
      this.stopCollectionCardShakeAnimation();
      return;
    }

    const uiContext = this.getUIContext();
    if (!uiContext) {
      this.isCollectionCardShakeRunning = false;
      return;
    }

    uiContext.animateTo({
      duration: this.collectionCardShakeFrameDuration,
      curve: Curve.Linear,
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        if (!this.isCollectionCardShakeRunning || !this.shouldAllowForegroundAnimations()) {
          return;
        }
        const nextAngle = targetAngle === this.collectionCardShakeAmplitude
          ? -this.collectionCardShakeAmplitude
          : this.collectionCardShakeAmplitude;
        this.scheduleNextCollectionCardShake(nextAngle);
      }
    }, () => {
      if (!this.isCollectionCardShakeRunning || !this.shouldAllowForegroundAnimations()) {
        return;
      }
      this.collectionShakeAngle = targetAngle;
    });
  }

  // ===== 标签编辑相关方法 =====

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

  private startTagShakeAnimation(): void {
    if (!this.shouldAllowForegroundAnimations()) {
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
    if (!this.isTagShakeRunning) {
      return;
    }
    if (!this.shouldAllowForegroundAnimations()) {
      this.stopTagShakeAnimation();
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
        if (!this.isTagShakeRunning || !this.shouldAllowForegroundAnimations()) {
          return;
        }
        const nextAngle = targetAngle === this.tagShakeAmplitude ? -this.tagShakeAmplitude : this.tagShakeAmplitude;
        this.scheduleNextTagShake(nextAngle);
      }
    }, () => {
      if (!this.isTagShakeRunning || !this.shouldAllowForegroundAnimations()) {
        return;
      }
      this.tagShakeAngle = targetAngle;
    });
  }

  private showDeleteTagDialog(tag: TagModel, index: number): void {
    this.getUIContext().showAlertDialog({
      title: '是否确认删除标签？',
      message: `删除后将移除标签 "${tag.name}"，相关灵感会标记为无标签`,
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
        this.adjustSelectedTagIndexAfterDeletion(index);
        this.recalculateSheetHeight();
        this.syncTagStorage();
        this.updateIdeasAfterTagDeletion(tag);
      });

      promptAction.openToast({
        message: '标签已删除',
        duration: 1000
      }).catch(() => {
      });

      hilog.info(0x0000, TAG, `Tag deleted successfully: ${tag.id}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error deleting tag: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '删除标签时发生错误',
        duration: 1000
      }).catch(() => {
      });
    }
  }

  private adjustSelectedTagIndexAfterDeletion(deletedIndex: number): void {
    if (this.selectedTagIndex === deletedIndex) {
      this.selectedTagIndex = -1;
    } else if (this.selectedTagIndex > deletedIndex) {
      this.selectedTagIndex -= 1;
    }
  }

  private syncTagStorage(): void {
    AppStorage.setOrCreate('tagData', [...this.tagData]);
  }

  private updateIdeasAfterTagDeletion(tag: TagModel): void {
    // 更新灵感池中受影响的灵感，将其标签设置为null
    let mutated = false;

    const updatedActivities = this.ideaActivities.map(activity => {
      if (activity.tagId !== tag.id) {
        return activity;
      }

      activity.tagId = null;
      activity.tagName = null;
      activity.tagColorHex = null;
      activity.tagLightColorHex = null;
      mutated = true;
      return activity;
    });

    if (mutated) {
      hilog.info(0x0000, TAG, `Updated ideas after tag deletion: ${tag.name}`);
      // 触发UI更新
      this.updateIdeaActivities(updatedActivities);
    }
  }

  private showDeleteIdeaDialog(activity: IdeaActivity): void {
    const uiContext = this.getUIContext();
    if (!uiContext) {
      hilog.warn(0x0000, TAG, 'UI context unavailable when showing delete idea dialog');
      return;
    }

    uiContext.showAlertDialog({
      title: '确认删除灵感？',
      message: `删除后将从灵感池移除 “${activity.name}”`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      gridCount: 4,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: '取消',
        action: () => {
          hilog.info(0x0000, TAG, `Cancel delete idea ${activity.id}`);
        }
      },
      secondaryButton: {
        enabled: true,
        defaultFocus: true,
        style: DialogButtonStyle.HIGHLIGHT,
        value: '确认',
        action: () => {
          hilog.info(0x0000, TAG, `Confirm delete idea ${activity.id}`);
          void this.handleDeleteIdea(activity);
        }
      },
      cancel: () => {
        hilog.info(0x0000, TAG, 'Closed delete idea dialog');
      },
      onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
        hilog.info(0x0000, TAG, `Delete idea dialog onWillDismiss reason= ${dismissDialogAction.reason}`);
        if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
          dismissDialogAction.dismiss();
        }
        if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissDialogAction.dismiss();
        }
      }
    });
  }

  private showRollbackIdeaDialog(activity: IdeaActivity): void {
    const uiContext = this.getUIContext();
    if (!uiContext) {
      hilog.warn(0x0000, TAG, 'UI context unavailable when showing rollback idea dialog');
      return;
    }

    uiContext.showAlertDialog({
      title: $r('app.string.ideapool_expand_rollback_title'),
      message: $r('app.string.ideapool_expand_rollback_message'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      gridCount: 4,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: $r('app.string.ideapool_expand_rollback_cancel'),
        action: () => {
          hilog.info(0x0000, TAG, `Cancel rollback idea ${activity.id}`);
        }
      },
      secondaryButton: {
        enabled: true,
        defaultFocus: true,
        style: DialogButtonStyle.HIGHLIGHT,
        value: $r('app.string.ideapool_expand_rollback_confirm'),
        action: () => {
          hilog.info(0x0000, TAG, `Confirm rollback idea ${activity.id}`);
          void this.handleRollbackIdeaToUnlit(activity);
        }
      },
      cancel: () => {
        hilog.info(0x0000, TAG, 'Closed rollback idea dialog');
      },
      onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
        hilog.info(0x0000, TAG, `Rollback idea dialog onWillDismiss reason= ${dismissDialogAction.reason}`);
        if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
          dismissDialogAction.dismiss();
        }
        if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissDialogAction.dismiss();
        }
      }
    });
  }


  private showDeleteCollectionDialog(collection: IdeaCollection): void {
    const uiContext = this.getUIContext();
    if (!uiContext) {
      hilog.warn(0x0000, TAG, 'UI context unavailable when showing delete collection dialog');
      return;
    }

    uiContext.showAlertDialog({
      title: '确认删除收藏集？',
      message: `删除后将移除收藏集 “${collection.name}”，其中灵感将回到“散落灵感”`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      gridCount: 4,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: '取消',
        action: () => {
          hilog.info(0x0000, TAG, `Cancel delete collection ${collection.id}`);
        }
      },
      secondaryButton: {
        enabled: true,
        defaultFocus: true,
        style: DialogButtonStyle.HIGHLIGHT,
        value: '确认',
        action: () => {
          hilog.info(0x0000, TAG, `Confirm delete collection ${collection.id}`);
          void this.handleDeleteCollection(collection);
        }
      },
      cancel: () => {
        hilog.info(0x0000, TAG, 'Closed delete collection dialog');
      },
      onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
        hilog.info(0x0000, TAG, `Delete collection dialog onWillDismiss reason= ${dismissDialogAction.reason}`);
        if (dismissDialogAction.reason === DismissReason.PRESS_BACK) {
          dismissDialogAction.dismiss();
        }
        if (dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissDialogAction.dismiss();
        }
      }
    });
  }

  private applyCollectionDeletion(collectionId: string): void {
    const collectionIndex: number = this.ideaCollections.findIndex((item: IdeaCollection) => item.id === collectionId);
    if (collectionIndex >= 0) {
      this.ideaCollections.splice(collectionIndex, 1);
    }
    const summaryIndex: number = this.ideaCollectionSummaries.findIndex(
      (summary: IdeaCollectionSummary) => summary.collectionId === collectionId
    );
    if (summaryIndex >= 0) {
      this.ideaCollectionSummaries.splice(summaryIndex, 1);
    }
    this.ideaPoolState.collections = this.ideaCollections;
    this.ideaPoolState.collectionSummaries = this.ideaCollectionSummaries;

    if (this.selectedCollectionId === collectionId) {
      this.selectedCollectionId = null;
    }
    if (this.editingSelectedCollectionId === collectionId) {
      this.editingSelectedCollectionId = null;
    }
    if (this.editingInitialCollectionId === collectionId) {
      this.editingInitialCollectionId = null;
    }

    if (!Array.isArray(this.ideaCollections) || this.ideaCollections.length === 0) {
      this.updateCollectionEditingState(false);
    }
    this.syncIdeaCollectionCardsFromState(false);
    this.syncSelectableCollectionsFromState();
  }

  private async handleDeleteCollection(collection: IdeaCollection): Promise<void> {
    hilog.info(0x0000, TAG, `User trying to delete collection: ${collection.id}, ${collection.name}`);

    try {
      const ideaPoolService = await this.ensureIdeaPoolService();
      const deleted: boolean = await ideaPoolService.deleteIdeaCollection(this.defaultUserId, collection.id);

      if (!deleted) {
        hilog.warn(0x0000, TAG, `Failed to delete collection: ${collection.id}`);
        promptAction.openToast({
          message: '删除收藏集失败',
          duration: 1000
        }).catch(() => {
        });
        void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
        return;
      }

      const uiContext = this.getUIContext();
      if (uiContext) {
        uiContext.animateTo({
          duration: this.deleteAnimationDuration,
          curve: curves.springMotion()
        }, () => {
          this.applyCollectionDeletion(collection.id);
        });
      } else {
        this.applyCollectionDeletion(collection.id);
      }

      promptAction.openToast({
        message: '收藏集已删除',
        duration: 1000
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
      hilog.info(0x0000, TAG, `Collection deleted successfully: ${collection.id}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error deleting collection: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '删除收藏集时发生错误',
        duration: 1000
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    }
  }

  private applyIdeaDeletion(
    activityId: string,
    nextIdeaPoolOrder: SortEntry[],
    nextSelection: string[] | null,
    collectionId: string | null,
    ideaLightState: IdeaLightState
  ): void {
    const removeIndex: number = this.ideaActivities.findIndex(item => item.id === activityId);
    if (removeIndex >= 0) {
      this.ideaActivities.splice(removeIndex, 1);
    }
    this.ideaPoolState.activities = this.ideaActivities;
    this.ideaPoolState.ideaPoolOrder = [...nextIdeaPoolOrder];
    if (nextSelection) {
      this.ideaPoolState.preferences.lastBulkSelection = nextSelection;
    }
    if (collectionId) {
      const isLit: boolean = ideaLightState === IdeaLightState.LIT;
      this.updateCollectionSummaryCounts(collectionId, isLit ? -1 : 0, isLit ? 0 : -1);
    }
    if (this.ideaActivities.length === 0 && this.isEditingIdeas) {
      this.updateIdeaEditingState(false);
    }
    this.updateRelativeTimeBaseline();
    this.syncAnimatedIdeaLists(false);
    this.syncIdeaLightCountsFromActivities();
  }

  private async handleDeleteIdea(activity: IdeaActivity): Promise<void> {
    hilog.info(0x0000, TAG, `User trying to delete idea: ${activity.id}, ${activity.name}`);

    try {
      const ideaPoolService = await this.ensureIdeaPoolService();
      const assignedCollectionId: string | null = await ideaPoolService.resolveCollectionIdByActivity(activity.id);
      const deleteResult = await ideaPoolService.deleteIdeas(this.defaultUserId, { ids: [activity.id] });

      if (!deleteResult.deletedIds.includes(activity.id)) {
        hilog.warn(0x0000, TAG, `Failed to delete idea: ${activity.id}`);
        promptAction.openToast({
          message: '删除灵感失败',
          duration: 1000
        }).catch(() => {
        });
        void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
        return;
      }

      // 确认删除后，先触发动画，再更新数据
      if (this.ideaExpandAnimationProps && this.ideaExpandAnimationProps.isExpandPageShow) {
        this.ideaExpandAnimationProps.collapseAnimation(() => {}, CollapseAnimationType.DELETE);
      }

      const nextIdeaPoolOrder: SortEntry[] = this.ideaPoolState.ideaPoolOrder.filter(entry => entry.activityId !== activity.id);

      const currentSelection = this.ideaPoolState.preferences.lastBulkSelection ?? [];
      let nextSelection: string[] | null = null;
      if (currentSelection.length > 0) {
        const selectionIndex = currentSelection.indexOf(activity.id);
        if (selectionIndex !== -1) {
          const before = currentSelection.slice(0, selectionIndex);
          const after = currentSelection.slice(selectionIndex + 1);
          nextSelection = [...before, ...after];
        }
      }

      const uiContext = this.getUIContext();
      if (uiContext) {
        uiContext.animateTo({
          duration: this.deleteAnimationDuration,
          curve: curves.springMotion()
        }, () => {
          this.applyIdeaDeletion(activity.id, nextIdeaPoolOrder, nextSelection, assignedCollectionId, activity.ideaLightState);
        });
      } else {
        this.applyIdeaDeletion(activity.id, nextIdeaPoolOrder, nextSelection, assignedCollectionId, activity.ideaLightState);
      }

      promptAction.openToast({
        message: '灵感已删除',
        duration: 1000
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');

      hilog.info(0x0000, TAG, `Idea deleted successfully: ${activity.id}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error deleting idea: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '删除灵感时发生错误',
        duration: 1000
      }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    }
  }

  private applyIdeaRollbackToState(activityId: string, assignedCollectionId: string | null, updatedAt: number): void {
    const target: IdeaActivity | undefined = this.ideaActivities.find(item => item.id === activityId);
    if (!target) {
      return;
    }
    const wasLit: boolean = target.ideaLightState === IdeaLightState.LIT;
    target.ideaLightState = IdeaLightState.UNLIT;
    target.ideaLightCount = 0;
    target.updatedAt = updatedAt;
    if (wasLit && assignedCollectionId) {
      this.updateCollectionSummaryCounts(assignedCollectionId, -1, 1);
    }
    this.ideaActivities = [...this.ideaActivities];
  }

  private async handleRollbackIdeaToUnlit(activity: IdeaActivity): Promise<void> {
    if (activity.ideaLightState !== IdeaLightState.LIT) {
      return;
    }
    hilog.info(0x0000, TAG, `User trying to rollback idea to unlit: ${activity.id}, ${activity.name}`);
    try {
      const ideaPoolService = await this.ensureIdeaPoolService();
      const assignedCollectionId: string | null = await ideaPoolService.resolveCollectionIdByActivity(activity.id);
      const updated: boolean = await ideaPoolService.rollbackIdeaToUnlit(this.defaultUserId, activity.id);
      if (!updated) {
        hilog.warn(0x0000, TAG, `Failed to rollback idea to unlit: ${activity.id}`);
        return;
      }
      // 确认回退后，先触发动画，再更新数据
      if (this.ideaExpandAnimationProps && this.ideaExpandAnimationProps.isExpandPageShow) {
        this.ideaExpandAnimationProps.collapseAnimation(() => {}, CollapseAnimationType.ROLLBACK);
      }
      this.applyIdeaRollbackToState(activity.id, assignedCollectionId, Date.now());
    } catch (error) {
      hilog.error(0x0000, TAG, `Error rolling back idea to unlit: ${JSON.stringify(error)}`);
    }
  }

  private resetFormState(): void {
    this.inputActivityName = '';
    this.inputTagName = '';
    this.selectedTagIndex = -1;
    this.selectedLabelIndex = -1;
    this.selectedCollectionId = null;
    this.recalculateSheetHeight();
  }

  private resetEditIdeaForm(): void {
    this.editingIdea = undefined;
    this.editingIdeaName = '';
    this.editingSelectedTagIndex = -1;
    this.editingSelectedCollectionId = null;
    this.editingInitialCollectionId = null;
    this.isSavingIdeaEdit = false;
  }

  private async handleMoveIdeaToToday(activity: IdeaActivity): Promise<void> {
    hilog.info(0x0000, TAG, `Attempting to move idea ${activity.id} to Today list`);

    const ideaSnapshot: IdeaActivity = new IdeaActivity(
      activity.id,
      activity.name,
      activity.status,
      activity.tagId,
      activity.tagName,
      activity.tagColorHex,
      activity.tagLightColorHex,
      activity.createdAt,
      Date.now(),
      activity.displayOrder,
      activity.ideaType,
      activity.ideaLightState,
      activity.ideaLightCount
    );

    try {
      const ideaPoolService = await this.ensureIdeaPoolService();
      const addResult: AddIdeaToTodayResult | null = await ideaPoolService.addIdeaToToday(
        this.defaultUserId,
        ideaSnapshot,
        this.ideapoolDirectRecord
      );
      if (!addResult) {
        hilog.warn(0x0000, TAG, `Idea ${activity.id} add-to-today failed (null result).`);
        void promptAction.openToast({ message: '添加失败，请重试', duration: 1000 }).catch(() => {});
        return;
      }

      this.applyAddIdeaToTodayResultToState(activity.id, addResult);
      const todayItem = this.mapIdeaActivityToTodayItem(ideaSnapshot, addResult.createdActivityId, addResult.status);
      if (addResult.status === MatterStatus.RECORDING) {
        await this.syncAutoRecordRunningState(todayItem);
      }
      this.appendTodayActivityToStorage(todayItem);
      this.syncAnimatedIdeaLists(true);
      void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');

      void promptAction.openToast({
        message: '已添加到今日清单',
        duration: 1000
      }).catch(() => {
      });
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to move idea to today: ${JSON.stringify(error)}`);
      void promptAction.openToast({
        message: '移动到今日清单时发生错误',
        duration: 1000
      }).catch(() => {
      });
    }
  }

  private applyAddIdeaToTodayResultToState(activityId: string, addResult: AddIdeaToTodayResult): void {
    const currentActivities = this.ideaActivities;
    const target = currentActivities.find(item => item.id === activityId);
    if (target) {
      const wasLit: boolean = target.ideaLightState === IdeaLightState.LIT;
      target.ideaLightState = IdeaLightState.LIT;
      target.ideaLightCount = target.ideaLightCount + 1;
      target.updatedAt = addResult.timestamp;
      hilog.info(0x0000, TAG, `Updated idea ${activityId} as lit in Idea Pool list (today activity=${addResult.createdActivityId}).`);

      if (!wasLit) {
        this.ideaPoolState.activities = this.ideaActivities;
      }
    }

    const currentSelection = this.ideaPoolState.preferences.lastBulkSelection ?? [];
    const selectionIndex = currentSelection.indexOf(activityId);
    if (selectionIndex !== -1) {
      const beforeSelection = currentSelection.slice(0, selectionIndex);
      const afterSelection = currentSelection.slice(selectionIndex + 1);
      this.ideaPoolState.preferences.lastBulkSelection = [...beforeSelection, ...afterSelection];
    }

    this.ideaPoolState.todayOrder = [...addResult.todayOrder];
    this.syncIdeaLightCountsFromActivities();
  }

  private appendTodayActivityToStorage(todayItem: MatterItemModel): void {
    this.matterData = this.upsertMatterItem(this.matterData, todayItem);
    if (todayItem.status === MatterStatus.TODO) {
      this.unDoMatterData = this.upsertMatterItem(this.unDoMatterData, todayItem);
      this.doneMatterData = this.removeMatterItem(this.doneMatterData, todayItem.id);
      hilog.info(0x0000, TAG, `unDoMatterData appended (id=${todayItem.id}), total items: ${this.unDoMatterData.length}`);
      return;
    }
    this.doneMatterData = this.upsertMatterItem(this.doneMatterData, todayItem);
    this.unDoMatterData = this.removeMatterItem(this.unDoMatterData, todayItem.id);
    hilog.info(0x0000, TAG, `doneMatterData appended (id=${todayItem.id}), total items: ${this.doneMatterData.length}`);
  }

  private mapIdeaActivityToTodayItem(
    activity: IdeaActivity,
    todayActivityId: string,
    status: MatterStatus
  ): MatterItemModel {
    const labelName = activity.tagName ?? '无标签';
    const labelColor = activity.tagColorHex ?? $r('app.color.tag_placeholder_gray');

    return new MatterItemModel({
      id: todayActivityId,
      title: activity.name,
      label: labelName,
      labelColor: labelColor,
      status: status,
      durationInMilliseconds: 0
    });
  }

  private async syncAutoRecordRunningState(todayItem: MatterItemModel): Promise<void> {
    // Phase 4-2: 会话统一经 store 收养（DB open record 为准），全局运行键由投影单写者维护
    await recordingSessionStore.adoptOpenRecord(todayItem.id);
  }

  private upsertMatterItem(items: MatterItemModel[], item: MatterItemModel): MatterItemModel[] {
    const filtered = items.filter(existing => existing.id !== item.id);
    filtered.push(item);
    return filtered;
  }

  private removeMatterItem(items: MatterItemModel[], itemId: string): MatterItemModel[] {
    if (!items || items.length === 0) {
      return [];
    }
    return items.filter(existing => existing.id !== itemId);
  }

  private getIdeaCardTransition(index: number): TransitionEffect {
    return TransitionEffect.OPACITY
      .animation({
        curve: curves.springMotion(0.5, 0.6),
        duration: 250,
        delay: index * 50
      }).combine(TransitionEffect.scale({ x: 0.5, y: 0.5 }));
  }

  build() {
    if (canIUse("SystemCapability.UIDesign.HDSComponent.Core")) {
      HdsNavDestination() {
        // 卡片折叠态、展开态的共同父组件
        Stack({ alignContent: Alignment.Bottom }) {
          if (this.animatedLitIdeas.length == 0 && this.animatedUnlitIdeas.length == 0) {
            Refresh({ refreshing: $$this.refreshing, builder: this.refreshBuilder() }) {
              Scroll() {
                Column() {
                  this.renderIdeaFilterSegment()

                  this.renderIdeaCollections()

                  Column() {
                    IdeaLightSummaryCards({
                      unlitCount: this.unlitIdeaCount,
                      litCount: this.litIdeaCount,
                      isDarkTheme: this.isDarkTheme
                    })
                      .height('100%')
                      .width('100%')
                  }
                  .height(IDEAPOOL_TOP_SUMMARY_HEIGHT)
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
                  .align(Alignment.TopStart)
                  .zIndex(1)

                  if (this.isIdeaLoading) {
                    this.renderIdeaListLoading();
                  } else {
                    this.renderIdeaPoolEmptyState();
                  }
                }
                .padding({ top: 105 })
              }
              .width('100%')
              .height('100%')
              .align(Alignment.Top)
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .friction(0.9)
              .onScrollStart(() => {
                this.ballVisible = Visibility.Hidden;
              })
              .onScrollStop(() => {
                this.ballVisible = Visibility.Visible;
              })
            }
            .onOffsetChange((offset: number) => {
              this.refreshOffset = offset;
            })
            .onStateChange((state: RefreshStatus) => {
              this.refreshState = state;
            })
            .onRefreshing(async () => {
              hilog.info(0x0000, TAG, 'Refresh onRefreshing callback triggered');
              await this.refreshIdeaPoolData();
              hilog.info(0x0000, TAG, 'Refresh onRefreshing callback completed');
            })
            .enabled(this.shouldEnableIdeaPoolContent())
          } else {
            Refresh({ refreshing: $$this.refreshing, builder: this.refreshBuilder() }) {
              Scroll() {
                Column() {

                  this.renderIdeaFilterSegment()

                  this.renderIdeaCollections()

                  Column() {
                    IdeaLightSummaryCards({
                      unlitCount: this.unlitIdeaCount,
                      litCount: this.litIdeaCount,
                      isDarkTheme: this.isDarkTheme
                    })
                      .height('100%')
                      .width('100%')
                  }
                  .height(IDEAPOOL_TOP_SUMMARY_HEIGHT)
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
                  .align(Alignment.TopStart)
                  .zIndex(1)

                  if (this.isIdeaLoading) {
                    this.renderIdeaListLoading();
                  } else {
                    Column() {
                      if (this.shouldRenderUnlitFirst()) {
                        this.renderUnlitIdeaListGroup();
                        this.renderLitIdeaListGroup();
                      } else {
                        this.renderLitIdeaListGroup();
                        this.renderUnlitIdeaListGroup();
                      }
                      Blank()
                        .height(this.getIdeaListBottomSpacerHeight())
                    }
                    .width('100%')
                    .animation({ curve: curves.springMotion(), duration: 100 })
                  }
                }
                  .padding({top: 105})
              }
              .width('100%')
              .height('100%')
              .align(Alignment.Top)
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .friction(0.9)
              .onScrollStart(() => {
                this.ballVisible = Visibility.Hidden;
              })
              .onScrollStop(() => {
                this.ballVisible = Visibility.Visible;
              })
            }
            .onOffsetChange((offset: number) => {
              this.refreshOffset = offset;
            })
            .onStateChange((state: RefreshStatus) => {
              this.refreshState = state;
            })
            .onRefreshing(async () => {
              hilog.info(0x0000, TAG, 'Refresh onRefreshing callback triggered');
              await this.refreshIdeaPoolData();
              hilog.info(0x0000, TAG, 'Refresh onRefreshing callback completed');
            })
            .enabled(this.shouldEnableIdeaPoolContent())
          }

          Row() {
            AddIdeaBall()
              .width(55)
              .height(55)
              .margin({ bottom: new BreakpointType<number>({ sm: 100, md: 100, lg: 40 }).getValue(this.currentBreakpoint) })
              .visibility(this.ballVisible)
              .transition(this.effect)
              .onClick(() => {
                void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
                this.recalculateSheetHeight();
                this.isShow = true;
              })
              .bindSheet($$this.isShow, this.addNewItemBuilder(), {
                detents: this.ideaFormSheetDetents,
                showClose: false,
                preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
                dragBar: false,
                blurStyle: BlurStyle.COMPONENT_REGULAR,
                enableOutsideInteractive: false,
                keyboardAvoidMode: SheetKeyboardAvoidMode.POPUP_SHEET,
                title: this.titleBuilder,
                onWillAppear: () => {
                  void this.ensureCollectionStateLoaded();
                  this.updateIdeaFormSheetDetents();
                },
                onWillDismiss: ((dismissSheetAction: DismissSheetAction) => {
                  this.isShow = false;
                  this.updateIdeaFormSheetDetents();
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
          }
          .enabled(this.shouldEnableIdeaPoolContent())
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

          if (this.ideaExpandAnimationProps !== null && this.ideaExpandAnimationProps.isExpandPageShow) {
            IdeaExpandPage({
              animationProperties: this.ideaExpandAnimationProps,
              onDelete: (idea: IdeaActivity) => {
                this.showDeleteIdeaDialog(idea);
              },
              onRollbackToUnlit: (idea: IdeaActivity) => {
                this.showRollbackIdeaDialog(idea);
              }
            })
          }
        }
        .key('ideaPoolRootStack')
        .enabled(this.shouldEnableIdeaPoolRoot())
      .bindSheet($$this.isIdeaEditSheetShow, this.editIdeaSheetContentBuilder(), {
          detents: this.ideaFormSheetDetents,
          showClose: false,
          dragBar: false,
          preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
          blurStyle: BlurStyle.COMPONENT_REGULAR,
          enableOutsideInteractive: false,
          keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
          title: this.editIdeaSheetTitleBuilder,
          onWillAppear: () => {
            void this.ensureCollectionStateLoaded();
            this.updateIdeaFormSheetDetents();
          },
          onWillDismiss: (dismissSheetAction: DismissSheetAction) => {
            this.isIdeaEditSheetShow = false;
            this.updateIdeaFormSheetDetents();
            this.resetEditIdeaForm();
            if (dismissSheetAction.reason === DismissReason.CLOSE_BUTTON) {
              dismissSheetAction.dismiss();
            }
            if (dismissSheetAction.reason === DismissReason.PRESS_BACK) {
              dismissSheetAction.dismiss();
            }
            if (dismissSheetAction.reason == DismissReason.SLIDE_DOWN) {
              dismissSheetAction.dismiss();
            }
          }
        })
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.transparent'))
      // .titleMode(HdsNavigationTitleMode.MINI)
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
            mainTitle: '灵感池',
          },
          menu: {
            value: [{
              content: {
                label: 'menu1',
                icon: this.isEditingIdeas ? $r('sys.symbol.xmark') : $r('sys.symbol.square_and_pencil'),
                isEnabled: !this.isReordering,
                action: () => {
                  if (this.ideaActivities.length === 0 && this.ideaCollectionCardEntries.length === 0) {
                    promptAction.openToast({
                      message: '暂无内容可编辑',
                      duration: 1000
                    }).catch(() => {
                    });
                    return;
                  }

                  const nextState = !this.isEditingIdeas;
                  if (nextState && (this.isIdeaEditSheetShow || this.isCollectionAddSheetShow)) {
                    return;
                  }
                  this.updateIdeaEditingState(nextState);
                  this.updateCollectionEditingState(nextState);
                  void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                  promptAction.openToast({
                    message: nextState ? '编辑模式已开启' : '编辑模式已关闭',
                    duration: 800
                  });
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
    }
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
}
