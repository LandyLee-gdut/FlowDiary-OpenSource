import {
  AppShadows,
  DEFAULT_SHEET_HEIGHT,
  EmojiItem,
  EmojiUtil,
  IdeaActivity,
  IdeaCollection,
  IdeaCollectionSummary,
  IdeaLightState,
  MatterItemModel,
  MatterStatus,
  PreferenceKeys,
  PreferencesUtil,
  preferencesUtil,
  recordingSessionStore,
  TagModel,
  VibratorUtil,
  calculateSheetHeight,
  BreakpointConstants,
  BreakpointSystem,
  BreakpointType,
  ColorModeUtil,
  COLOR_MODE_STORAGE_KEY,
  COLOR_MODE_VERSION_KEY,
  ItemFormContent,
  ItemFormSheetConfig,
  ItemFormSheetPresets,
  buildSheetTitleBar,
  buildFlowLightEffect,
  IdeaFormSheet,
  IdeaCollectionFormContent,
  holdingHandService,
} from 'base';
import { curves, ComponentContent, promptAction, window } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AddIdeaBall } from '../component/AddIdeaBall';
import { AddNewIdeaDialog } from '../component/AddNewIdeaDialog';
import { IdeaCard } from '../component/IdeaCard';
import { IdeaExpandPage } from '../component/IdeaExpandPage';
import { IdeaExpandAnimationProperties, CollapseAnimationType } from '../component/IdeaExpandAnimation';
import { AddIdeaToTodayResult, IdeaCollectionDetailPayload, IdeaPoolService, initIdeaPoolService } from '../model/IdeaPoolService';
import {
  hdsEffect,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationAttribute,
  HdsNavDestinationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';

const TAG = 'IdeaCollectionDetailPage';
const DEFAULT_ICON: string = '📚';

const COLLECTION_HEADER_CARD_HEIGHT: number = 190;
const COLLECTION_HEADER_ICON_SIZE: number = 42;
const COLLECTION_HEADER_TITLE_SIZE: number = 24;
const COLLECTION_HEADER_SUBTITLE_SIZE: number = 14;
const COLLECTION_HEADER_STAT_NUMBER_SIZE: number = 22;
const COLLECTION_HEADER_STAT_LABEL_SIZE: number = 12;
const COLLECTION_SECTION_HEADER_HEIGHT: number = 40;
const COLLECTION_SECTION_HEADER_FONT_SIZE: number = 14;
const COLLECTION_SECTION_HEADER_FONT_WEIGHT: number = 400;
const COLLECTION_SECTION_HEADER_LINE_HEIGHT: number = 1;
const COLLECTION_IDEA_LIST_LANES: BreakpointType<number> = new BreakpointType<number>({ sm: 2, md: 3, lg: 4 });
const COLLECTION_LIST_BOTTOM_SPACER_HEIGHT: BreakpointType<number> = new BreakpointType<number>({ sm: 75, md: 75, lg: 75 });
const COLLECTION_IDEA_CARD_HEIGHT: number = 165;

interface IdeaCollectionDetailRouteParam {
  collectionId: string;
}

class IdeaSectionHeaderParams {
  title: ResourceStr;

  constructor(title: ResourceStr) {
    this.title = title;
  }
}

@Builder
function ideaSectionHeader(params: IdeaSectionHeaderParams) {
  Row() {
    Column()
      .height(COLLECTION_SECTION_HEADER_LINE_HEIGHT)
      .layoutWeight(1)
      .backgroundColor($r('app.color.neutral_200'))

    Text(params.title)
      .fontSize(COLLECTION_SECTION_HEADER_FONT_SIZE)
      .fontWeight(COLLECTION_SECTION_HEADER_FONT_WEIGHT)
      .fontColor($r('app.color.text_tertiary'))
      .padding({ left: 15, right: 15, top: 2, bottom: 2 })
      .borderRadius(10)

    Column()
      .height(COLLECTION_SECTION_HEADER_LINE_HEIGHT)
      .layoutWeight(1)
      .backgroundColor($r('app.color.neutral_200'))
  }
  .alignItems(VerticalAlign.Center)
  .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
  .width('100%')
  .height(COLLECTION_SECTION_HEADER_HEIGHT)
  .clip(false)
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
export function IdeaCollectionDetailPageBuilder(name: string, param?: Object) {
  IdeaCollectionDetailPage();
}

@Component
export struct IdeaCollectionDetailPage {
  pageInfos: NavPathStack = new NavPathStack();

  @State private collectionId: string = '';
  @State private collection: IdeaCollection | null = null;
  @State private collectionSummary: IdeaCollectionSummary | null = null;
  @State private ideaActivities: IdeaActivity[] = [];
  @State private animatedLitIdeas: IdeaActivity[] = [];
  @State private animatedUnlitIdeas: IdeaActivity[] = [];
  @State private litIdeaCount: number = 0;
  @State private unlitIdeaCount: number = 0;
  @State private litTimesCount: number = 0;
  @State private relativeTimeBaseline: number = Date.now();
  @State private ideaExpandAnimationProps: IdeaExpandAnimationProperties | null = null;
  @State private litCountTransition: NumericTextTransition =
    new NumericTextTransition({ flipDirection: FlipDirection.DOWN, enableBlur: false });
  @State private unlitCountTransition: NumericTextTransition =
    new NumericTextTransition({ flipDirection: FlipDirection.DOWN, enableBlur: false });
  @State private litTimesTransition: NumericTextTransition =
    new NumericTextTransition({ flipDirection: FlipDirection.DOWN, enableBlur: false });

  @State private isShowAddSheet: boolean = false;
  @State private ideaFormSheetDetents: [Length | SheetSize, (Length | SheetSize)?, (Length | SheetSize)?] =
    [SheetSize.MEDIUM, SheetSize.LARGE];
  @State private sheetHeight: number = DEFAULT_SHEET_HEIGHT;
  @State private inputTagName: string = '';
  @State private inputIdeaName: string = '';
  @State private selectedTagIndex: number = -1;
  @State private selectedLabelIndex: number = -1;
  @State private isEditingTag: boolean = false;
  @State private tagShakeAngle: number = 0;
  @State private selectedEmojiChar: string = '';
  @State private selectedCollectionId: string | null = null;
  @State private selectableCollections: IdeaCollection[] = [];
  @State private emojis: EmojiItem[] = EmojiUtil.getAll();
  @State private ballVisible: Visibility = Visibility.Visible;
  @State private viewportHeight: number = 0;
  @State private keyboardHeight: number = 0;
  // 占位状态变量，用于通用组件的@Link绑定（详情页不使用直接开始功能）
  @State private directStartPlaceholder: boolean = false;
  @State private isCollectionEditSheetShow: boolean = false;
  @State private editCollectionName: string = '';
  @State private editCollectionSummary: string = '';
  @State private editCollectionSelectedTagIndex: number = -1;
  @State private editCollectionSelectedEmojiChar: string = '';
  @State private isSavingCollectionEdit: boolean = false;

  private addIdeaSheetConfig: ItemFormSheetConfig = ItemFormSheetPresets.createAddIdeaConfig();
  private editIdeaSheetConfig: ItemFormSheetConfig = ItemFormSheetPresets.createEditIdeaConfig();
  @State private isIdeaEditSheetShow: boolean = false;
  @State private editingIdeaName: string = '';
  @State private editingSelectedTagIndex: number = -1;
  @State private editingSelectedCollectionId: string | null = null;
  @State private editingInitialCollectionId: string | null = null;
  @State private editingIdea: IdeaActivity | null = null;
  @State private isSavingIdeaEdit: boolean = false;
  @State private editingTagShakeAngle: number = 0;
  private addNewItemDialogController: CustomDialogController = new CustomDialogController({
    builder: AddNewIdeaDialog({
      isShow: this.isShowAddSheet,
      inputActivityName: this.inputIdeaName,
      selectedTagIndex: this.selectedTagIndex,
      sheetHeight: this.sheetHeight,
      inputTagName: this.inputTagName,
      selectedLabelIndex: this.selectedLabelIndex
    }),
    alignment: DialogAlignment.Center,
    maskColor: $r('app.color.overlay_mask'),
    backgroundBlurStyle: BlurStyle.Thick,
    backgroundColor: $r('app.color.primary_lighter'),
    autoCancel: true,
    customStyle: true,
    onWillDisappear: () => {
      // noop
    },
    keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
    offset: { dx: 0, dy: 0 }
  });

  private readonly defaultUserId: string = 'default_user';
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  private ideaPoolServiceReady: boolean = false;
  private readonly ideaPoolRefreshTokenKey: string = 'ideapoolRefreshToken';
  private readonly preferencesUtil: PreferencesUtil = preferencesUtil;
  private effect: TransitionEffect = TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.6, 0.8), duration: 300 })
    .combine(TransitionEffect.translate({ x: 0, y: 100 }));

  @StorageLink('tagData') tagData: TagModel[] = [];
  @StorageLink('matterData') matterData: MatterItemModel[] = [];
  @StorageLink('doneMatterData') doneMatterData: MatterItemModel[] = [];
  @StorageLink('unDoMatterData') unDoMatterData: MatterItemModel[] = [];
  @StorageLink('ideapoolActivities') private ideaPoolActivities: IdeaActivity[] = [];
  @StorageLink('ideapoolCollections') @Watch('onIdeaPoolCollectionsChange') private ideaPoolCollections: IdeaCollection[] = [];
  @StorageLink('ideapoolCollectionSummaries') private ideaPoolCollectionSummaries: IdeaCollectionSummary[] = [];
  @StorageLink('ideapoolUnlitFirst') private ideapoolUnlitFirst: boolean = true;
  @StorageLink('ideapoolDirectRecord') private ideapoolDirectRecord: boolean = false;
  @StorageLink('holdingHandEnabled') private holdingHandEnabled: boolean = false;
  @StorageLink('holdingHandOffsetPercent') private holdingHandOffsetPercent: number = 0;
  @StorageLink('holdingHandStatus') @Watch('onHoldingHandStatusChange')
  private holdingHandStatus: number = motion.HoldingHandStatus.UNKNOWN_STATUS;
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 版本号在系统资源真正切换之后才会递增，保证流光 shader 用新色板重建
  @StorageProp(COLOR_MODE_VERSION_KEY) @Watch('onColorModeVersionChange') private colorModeVersion: number = 0;
  @StorageProp(BreakpointConstants.CURRENT_BREAKPOINT) currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @State private shaderController: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  @State private isFlowEffectMounted: boolean = true;

  private litHeaderContent: ComponentContent<IdeaSectionHeaderParams> | undefined = undefined;
  private unlitHeaderContent: ComponentContent<IdeaSectionHeaderParams> | undefined = undefined;
  private lastHoldingHandAlign: FlexAlign = FlexAlign.Center;
  private holdingHandActive: boolean = false;
  private flowEffectRemountToken: number = 0;
  private isPageActive: boolean = false;

  aboutToAppear(): void {
    this.isPageActive = true;
    this.recreateFlowEffect();
    this.ensureIdeaPoolStorageDefaults();
    this.breakpointSystem.register();
    this.syncColorModeState();
    this.loadIdeaPoolDirectRecordPreference();
    this.loadHoldingHandPreferences();
    this.ideaExpandAnimationProps = new IdeaExpandAnimationProperties(this.getUIContext());
    this.syncSelectableCollectionsFromState();
    void this.vibratorUtil.initialize();
    this.recalculateSheetHeight();

    window.getLastWindow(this.getUIContext().getHostContext()).then(currentWindow => {
      const windowRect = currentWindow.getWindowProperties().windowRect;
      this.viewportHeight = this.getUIContext().px2vp(windowRect.height);
      this.recalculateSheetHeight();

      currentWindow.on('windowSizeChange', (size: window.Size) => {
        this.viewportHeight = this.getUIContext().px2vp(size.height);
        this.recalculateSheetHeight();
      });

      currentWindow.on('keyboardHeightChange', (data: number) => {
        this.keyboardHeight = this.getUIContext().px2vp(data);
        this.updateIdeaFormSheetDetents();
      });
    }).catch((reason: BusinessError) => {
      hilog.error(0x0000, TAG, `Failed to get last window: ${JSON.stringify(reason)}`);
    });

    this.syncHoldingHandSubscription();
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.flowEffectRemountToken += 1;
    this.breakpointSystem.unregister();
    this.releaseHoldingHandSubscription();
  }

  onPageShow(): void {
    this.loadHoldingHandPreferences();
    this.syncHoldingHandSubscription();
  }

  onColorModeChange(): void {
    this.syncColorModeState();
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

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private loadIdeaPoolDirectRecordPreference(): void {
    if (!this.preferencesUtil.isInitialized()) {
      hilog.warn(0x0000, TAG, '[IdeaCollectionDetail] Preferences not initialized when loading ideapool direct record');
      this.ideapoolDirectRecord = false;
      return;
    }
    const storedValue = this.preferencesUtil.getSync(PreferenceKeys.IDEAPOOL_DIRECT_RECORD, false) as boolean;
    const normalized = !!storedValue;
    this.ideapoolDirectRecord = normalized;
  }

  private loadHoldingHandPreferences(): void {
    if (!this.preferencesUtil.isInitialized()) {
      hilog.warn(0x0000, TAG, '[IdeaCollectionDetail] Preferences not initialized when loading holdingHand settings');
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

  private onIdeaPoolCollectionsChange(): void {
    this.syncSelectableCollectionsFromState();
  }

  private syncSelectableCollectionsFromState(): void {
    const resolvedCollections: IdeaCollection[] = Array.isArray(this.ideaPoolCollections) ? [...this.ideaPoolCollections] : [];
    resolvedCollections.sort((left: IdeaCollection, right: IdeaCollection) => {
      const orderDelta: number = left.displayOrder - right.displayOrder;
      if (orderDelta !== 0) {
        return orderDelta;
      }
      return right.updatedAt - left.updatedAt;
    });
    this.selectableCollections = resolvedCollections;
  }

  private computeSheetHeight(tagCount: number): number {
    return calculateSheetHeight(tagCount, this.currentBreakpoint, this.viewportHeight);
  }

  private getIdeaListLanes(): number {
    return COLLECTION_IDEA_LIST_LANES.getValue(this.currentBreakpoint);
  }

  private getIdeaListLaneIndexes(): number[] {
    const lanes: number = this.getIdeaListLanes();
    const indexes: number[] = [];
    for (let index: number = 0; index < lanes; index += 1) {
      indexes.push(index);
    }
    return indexes;
  }

  private getIdeaListBottomSpacerHeight(): number {
    return COLLECTION_LIST_BOTTOM_SPACER_HEIGHT.getValue(this.currentBreakpoint);
  }

  private recalculateSheetHeight(): void {
    const tagCount: number = this.tagData ? this.tagData.length : 0;
    this.sheetHeight = this.computeSheetHeight(tagCount);
  }

  private updateIdeaFormSheetDetents(): void {
    if ((this.isShowAddSheet || this.isIdeaEditSheetShow) && this.keyboardHeight > 0) {
      this.ideaFormSheetDetents = [SheetSize.LARGE];
      return;
    }
    this.ideaFormSheetDetents = [SheetSize.MEDIUM, SheetSize.LARGE];
  }

  private updateRelativeTimeBaseline(): void {
    this.relativeTimeBaseline = Date.now();
  }

  private shouldEnableCollectionContent(): boolean {
    return this.ideaExpandAnimationProps === null ? true : !this.ideaExpandAnimationProps.isExpandPageShow;
  }

  private shouldEnableCollectionRoot(): boolean {
    return this.ideaExpandAnimationProps === null ? true : this.ideaExpandAnimationProps.isEnabled;
  }

  private handleIdeaCardLongPress(activity: IdeaActivity): void {
    if (this.ideaExpandAnimationProps === null) {
      return;
    }
    if (this.ideaExpandAnimationProps.isExpandPageShow) {
      return;
    }
    this.updateRelativeTimeBaseline();
    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
    if (this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_LG) {
      this.ideaExpandAnimationProps.positionCorrectionY = 0;
    } else {
      this.ideaExpandAnimationProps.positionCorrectionY = 0;
    }
    this.ideaExpandAnimationProps.expandAnimation(activity, this.relativeTimeBaseline);
    if (this.collectionId.trim().length > 0) {
      this.ideaExpandAnimationProps.currentCollectionId = this.collectionId;
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

  private ensureSectionHeaderContent(): void {
    if (this.litHeaderContent && this.unlitHeaderContent) {
      return;
    }
    const uiContext: UIContext = this.getUIContext();
    this.litHeaderContent = new ComponentContent<IdeaSectionHeaderParams>(
      uiContext,
      wrapBuilder(ideaSectionHeader),
      new IdeaSectionHeaderParams($r('app.string.ideapool_section_lit'))
    );
    this.unlitHeaderContent = new ComponentContent<IdeaSectionHeaderParams>(
      uiContext,
      wrapBuilder(ideaSectionHeader),
      new IdeaSectionHeaderParams($r('app.string.ideapool_section_unlit'))
    );
  }

  private getLitSectionHeader(): ComponentContent<IdeaSectionHeaderParams> | undefined {
    this.ensureSectionHeaderContent();
    this.litHeaderContent?.update(new IdeaSectionHeaderParams($r('app.string.ideapool_section_lit')));
    return this.litHeaderContent;
  }

  private getUnlitSectionHeader(): ComponentContent<IdeaSectionHeaderParams> | undefined {
    this.ensureSectionHeaderContent();
    this.unlitHeaderContent?.update(new IdeaSectionHeaderParams($r('app.string.ideapool_section_unlit')));
    return this.unlitHeaderContent;
  }

  private shouldRenderUnlitFirst(): boolean {
    return this.ideapoolUnlitFirst;
  }

  @Builder
  private renderUnlitIdeaListGroup() {
    if (this.animatedUnlitIdeas.length > 0) {
      ListItemGroup({ space: 16, headerComponent: this.getUnlitSectionHeader() }) {
        ForEach(this.animatedUnlitIdeas, (activity: IdeaActivity, index: number) => {
          ListItem() {
            Stack({ alignContent: Alignment.TopEnd }) {
              IdeaCard({
                idea: activity,
                relativeTimeBaseline: this.relativeTimeBaseline,
                // onExpand: () => {
                //   this.openIdeaEditSheet(activity);
                // },
                onEdit: () => {
                  this.openIdeaEditSheet(activity);
                },
                onMoveToToday: () => {
                  void this.handleMoveIdeaToToday(activity);
                }
              })
              .height('100%')
              .width('100%')
            }
            .width('100%')
            .height(COLLECTION_IDEA_CARD_HEIGHT)
            .key(`ideaCard_${activity.id}`)
            .clickEffect({ level: ClickEffectLevel.HEAVY, scale: 0.9 })
            .gesture(
              LongPressGesture({ repeat: false, duration: 500 })
                .onAction(() => {
                  this.handleIdeaCardLongPress(activity);
                })
            )
          }
          .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
          .transition(
            TransitionEffect.opacity(0.0)
              .combine(TransitionEffect.translate({ y: 30 }))
              .animation({ curve: curves.springMotion(), duration: 300 })
          )
          .height(COLLECTION_IDEA_CARD_HEIGHT)
          .width('100%')
        }, (activity: IdeaActivity) => activity.id)
      }
    }
  }

  @Builder
  private renderLitIdeaListGroup() {
    if (this.animatedLitIdeas.length > 0) {
      ListItemGroup({ space: 16, headerComponent: this.getLitSectionHeader() }) {
        ForEach(this.animatedLitIdeas, (activity: IdeaActivity, index: number) => {
          ListItem() {
            Stack({ alignContent: Alignment.TopEnd }) {
              IdeaCard({
                idea: activity,
                relativeTimeBaseline: this.relativeTimeBaseline,
                // onExpand: () => {
                //   this.openIdeaEditSheet(activity);
                // },
                onEdit: () => {
                  this.openIdeaEditSheet(activity);
                },
                onMoveToToday: () => {
                  void this.handleMoveIdeaToToday(activity);
                }
              })
              .height('100%')
              .width('100%')
            }
            .width('100%')
            .height(COLLECTION_IDEA_CARD_HEIGHT)
            .key(`ideaCard_${activity.id}`)
            .clickEffect({ level: ClickEffectLevel.HEAVY, scale: 0.9 })
            .gesture(
              LongPressGesture({ repeat: false, duration: 500 })
                .onAction(() => {
                  this.handleIdeaCardLongPress(activity);
                })
            )
          }
          .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
          .transition(
            TransitionEffect.opacity(0.0)
              .combine(TransitionEffect.translate({ y: 30 }))
              .animation({ curve: curves.springMotion(), duration: 300 })
          )
          .height(COLLECTION_IDEA_CARD_HEIGHT)
          .width('100%')
        }, (activity: IdeaActivity) => activity.id)
      }
    }
  }

  private syncAnimatedIdeaLists(animate: boolean): void {
    // 仅使用当前列表不再重新排序，确保顺序稳定，只在初始化或显式刷新时排序
    const sortedActivities: IdeaActivity[] = this.ideaActivities;
    const partition: IdeaLightPartitions = this.partitionIdeas(sortedActivities);
    const assign = () => {
      this.animatedLitIdeas = partition.lit;
      this.animatedUnlitIdeas = partition.unlit;
      this.litIdeaCount = partition.lit.length;
      this.unlitIdeaCount = partition.unlit.length;
      this.litTimesCount = this.computeCollectionLitTimes(sortedActivities);
    };

    const uiContext = this.getUIContext();
    if (animate && uiContext) {
      uiContext.animateTo({ duration: 300, curve: curves.springMotion() }, assign);
    } else {
      assign();
    }
  }

  private partitionIdeas(activities: IdeaActivity[]): IdeaLightPartitions {
    const lit: IdeaActivity[] = [];
    const unlit: IdeaActivity[] = [];
    for (let index: number = 0; index < activities.length; index += 1) {
      const activity: IdeaActivity = activities[index];
      if (activity.ideaLightState === IdeaLightState.LIT) {
        lit.push(activity);
      } else {
        unlit.push(activity);
      }
    }
    return new IdeaLightPartitions(lit, unlit);
  }

  private computeCollectionLitTimes(activities: IdeaActivity[]): number {
    if (!Array.isArray(activities) || activities.length === 0) {
      return 0;
    }
    let total: number = 0;
    for (let index: number = 0; index < activities.length; index += 1) {
      const count: number = activities[index].ideaLightCount;
      total += typeof count === 'number' && count > 0 ? count : 0;
    }
    return total;
  }

  private resolveCollectionIcon(): string {
    const icon: string | null = this.collection ? this.collection.icon : null;
    return icon !== null && icon.trim().length > 0 ? icon : DEFAULT_ICON;
  }

  private resolveCollectionTitle(): string {
    return this.collection ? this.collection.name : '';
  }

  private getPageTitle(): string {
    const title: string = this.resolveCollectionTitle();
    return title.length > 0 ? title : '灵感集';
  }

  private resolveCollectionSubtitle(): string {
    const summary: string | null = this.collection ? this.collection.summaryText : null;
    if (summary !== null && summary.trim().length > 0) {
      return summary;
    }
    return '';
  }

  private resolveCollectionUnlitCount(): number {
    return this.unlitIdeaCount;
  }

  private resolveCollectionLitCount(): number {
    return this.litIdeaCount;
  }

  private resolveCollectionLitTimesCount(): number {
    return this.litTimesCount;
  }

  private resolveEditCollectionPreviewColor(): ResourceColor {
    if (this.editCollectionSelectedTagIndex >= 0 && this.editCollectionSelectedTagIndex < this.tagData.length) {
      return this.tagData[this.editCollectionSelectedTagIndex].lightColor;
    }
    if (this.collection && this.collection.tagLightColorHex) {
      return this.collection.tagLightColorHex;
    }
    return $r('app.color.accent_lighter');
  }

  private resolveEditCollectionPreviewEmoji(): ResourceStr {
    if (this.editCollectionSelectedEmojiChar && this.editCollectionSelectedEmojiChar.length > 0) {
      return this.editCollectionSelectedEmojiChar;
    }
    if (this.collection && this.collection.icon && this.collection.icon.length > 0) {
      return this.collection.icon;
    }
    return $r('app.string.ideapool_collection_default_emoji');
  }

  private resolveEditCollectionTagId(): string | null {
    if (this.editCollectionSelectedTagIndex >= 0 && this.editCollectionSelectedTagIndex < this.tagData.length) {
      return this.tagData[this.editCollectionSelectedTagIndex].id;
    }
    return null;
  }

  private resolveTagIndexById(tagId: string | null): number {
    if (!tagId || !this.tagData || this.tagData.length === 0) {
      return -1;
    }
    return this.tagData.findIndex((tag: TagModel) => tag.id === tagId);
  }

  private syncEditCollectionFormFromCollection(): void {
    if (!this.collection) {
      return;
    }
    this.editCollectionName = this.collection.name;
    this.editCollectionSummary = this.collection.summaryText ?? '';
    this.editCollectionSelectedEmojiChar = this.collection.icon ?? '';
    this.editCollectionSelectedTagIndex = this.resolveTagIndexById(this.collection.tagId);
  }

  private resetEditCollectionForm(): void {
    this.editCollectionName = '';
    this.editCollectionSummary = '';
    this.editCollectionSelectedTagIndex = -1;
    this.editCollectionSelectedEmojiChar = '';
    this.isSavingCollectionEdit = false;
  }

  private openCollectionEditSheet(): void {
    if (!this.collection) {
      return;
    }
    this.syncEditCollectionFormFromCollection();
    this.isCollectionEditSheetShow = true;
  }

  private async handleUpdateCollectionInfo(): Promise<void> {
    if (this.isSavingCollectionEdit || !this.collection) {
      return;
    }
    const trimmedName: string = this.editCollectionName.trim();
    if (trimmedName.length === 0) {
      promptAction.openToast({ duration: 1000, message: $r('app.string.ideapool_collection_name_required') }).catch(() => {
      });
      return;
    }
    this.isSavingCollectionEdit = true;
    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const tagId: string | null = this.resolveEditCollectionTagId();
      const summaryText: string | null =
        this.editCollectionSummary.trim().length > 0 ? this.editCollectionSummary.trim() : null;
      const icon: string | null = this.editCollectionSelectedEmojiChar.length > 0 ? this.editCollectionSelectedEmojiChar : null;
      const updated: IdeaCollection | null = await service.updateIdeaCollection(this.defaultUserId, this.collection.id, {
        name: trimmedName,
        tagId: tagId,
        icon: icon,
        summaryText: summaryText
      });
      if (updated) {
        this.collection = updated;
        this.syncEditCollectionFormFromCollection();
        await this.syncIdeaPoolStorage();
        this.notifyIdeaPoolRefresh();
        this.isCollectionEditSheetShow = false;
        promptAction.openToast({ duration: 1000, message: $r('app.string.ideapool_collection_edit_success') }).catch(() => {
        });
      } else {
        promptAction.openToast({ duration: 1000, message: $r('app.string.ideapool_collection_edit_failed') }).catch(() => {
        });
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `Update collection failed: ${JSON.stringify(error)}`);
      promptAction.openToast({ duration: 1000, message: $r('app.string.ideapool_collection_edit_failed') }).catch(() => {
      });
    } finally {
      this.isSavingCollectionEdit = false;
    }
  }

  private resetAddIdeaForm(): void {
    this.inputIdeaName = '';
    this.selectedTagIndex = -1;
    this.selectedLabelIndex = -1;
    this.selectedEmojiChar = '';
    this.inputTagName = '';
    this.tagShakeAngle = 0;
    this.isEditingTag = false;
    this.selectedCollectionId = this.collectionId;
    this.recalculateSheetHeight();
  }

  private resolveTagIndex(tagId: string | null): number {
    if (!tagId || !Array.isArray(this.tagData)) {
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

  private normalizeCollectionId(collectionId: string | null): string | null {
    if (!collectionId) {
      return null;
    }
    const trimmed: string = collectionId.trim();
    return trimmed.length > 0 ? trimmed : null;
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
        promptAction.openToast({ duration: 1200, message: '更新灵感集失败' }).catch(() => {
        });
      }
      return;
    }

    if (trimmedPrev !== null) {
      const cleared: boolean = await service.clearIdeaCollectionAssignment(this.defaultUserId, activityId);
      if (!cleared) {
        promptAction.openToast({ duration: 1200, message: '移出灵感集失败' }).catch(() => {
        });
      }
    }
  }

  @Builder
  private titleBuilder() {
    buildSheetTitleBar({
      title: this.addIdeaSheetConfig.titleBar.title,
      actionButtonText: this.addIdeaSheetConfig.titleBar.actionButtonText,
      onClose: () => {
        if (this.isEditingTag) {
          this.isEditingTag = false;
        }
        this.isShowAddSheet = false;
        this.resetAddIdeaForm();
      },
      onSubmit: async () => {
        if (this.inputIdeaName.length <= 0) {
          promptAction.openToast({ duration: 1000, message: '请完整填写灵感信息' }).catch(() => {
          });
          return;
        }
        const selectedTagId = this.selectedTagIndex >= 0 ? this.tagData[this.selectedTagIndex].id : null;
        await this.handleAddIdeaToCollection(this.inputIdeaName, selectedTagId, this.selectedCollectionId);
        void this.vibratorUtil.triggerHaptic('haptic.notice.success', 'touch');
        this.isShowAddSheet = false;
        this.resetAddIdeaForm();
      }
    });
  }

  @Builder
  private addNewItemBuilder() {
    IdeaFormSheet({
      config: this.addIdeaSheetConfig,
      tagData: this.tagData,
      inputName: this.inputIdeaName,
      selectedTagIndex: this.selectedTagIndex,
      directStartEnabled: this.directStartPlaceholder,
      isEditingTag: this.isEditingTag,
      tagShakeAngle: this.tagShakeAngle,
      selectedEmoji: this.selectedEmojiChar,
      isDarkTheme: this.isDarkTheme,
      onCreateTag: () => {
        if (this.addNewItemDialogController != null) {
          this.addNewItemDialogController.open();
          this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
        }
      },
      onDeleteTag: (tag: TagModel, index: number) => {
        // Collection detail page does not support tag deletion yet.
        promptAction.openToast({ duration: 1000, message: '请前往灵感池管理标签' }).catch(() => {
        });
      },
      onToggleTagEditing: (isEditing: boolean) => {
        this.isEditingTag = isEditing;
      }
    });
  }

  @Builder
  private editCollectionTitleBuilder() {
    buildSheetTitleBar({
      title: $r('app.string.ideapool_collection_edit_title'),
      actionButtonText: this.isSavingCollectionEdit
        ? $r('app.string.ideapool_collection_edit_action_saving')
        : $r('app.string.ideapool_collection_edit_action'),
      actionButtonDisabled: this.isSavingCollectionEdit,
      onClose: () => {
        this.isCollectionEditSheetShow = false;
        this.resetEditCollectionForm();
      },
      onSubmit: async () => {
        await this.handleUpdateCollectionInfo();
      }
    });
  }

  @Builder
  private editCollectionSheetContentBuilder() {
    IdeaCollectionFormContent({
      name: this.editCollectionName,
      summaryText: this.editCollectionSummary,
      selectedTagIndex: this.editCollectionSelectedTagIndex,
      selectedEmojiChar: this.editCollectionSelectedEmojiChar,
      tagData: this.tagData,
      emojis: this.emojis,
      isDarkTheme: this.isDarkTheme,
      headerLabel: $r('app.string.ideapool_collection_header_edit'),
      enableTagSelectionScale: false,
      namePlaceholder: $r('app.string.ideapool_collection_name_placeholder'),
      descLabel: $r('app.string.ideapool_collection_desc_label'),
      descPlaceholder: $r('app.string.ideapool_collection_desc_placeholder'),
      tagLabel: $r('app.string.ideapool_collection_tag_label'),
      emojiLabel: $r('app.string.ideapool_collection_emoji_label'),
      defaultEmoji: $r('app.string.ideapool_collection_default_emoji'),
      confirmText: $r('app.string.ideapool_collection_edit_action'),
      confirmDisabled: this.isSavingCollectionEdit,
      confirmDisabledText: $r('app.string.ideapool_collection_edit_action_saving'),
      onClose: () => {
        this.isCollectionEditSheetShow = false;
        this.resetEditCollectionForm();
      },
      onConfirm: async () => {
        await this.handleUpdateCollectionInfo();
      }
    })
  }

  @Builder
  private editCollectionPreviewSection() {
    Column() {
        Column() {
          Text(this.resolveEditCollectionPreviewEmoji())
            .fontSize($r('app.float.ideapool_collection_preview_emoji_size'))
        }
        .width($r('app.float.ideapool_collection_preview_size'))
        .height($r('app.float.ideapool_collection_preview_size'))
        .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)
        .borderRadius($r('app.float.ideapool_collection_preview_radius'))
        .backgroundColor(this.resolveEditCollectionPreviewColor())
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: $r('app.float.ideapool_collection_preview_margin_top') })
  }

  @Builder
  private editCollectionNameSection() {
    Column() {
      Text($r('app.string.ideapool_collection_name_label'))
        .fontSize(15)
        .fontWeight(500)
        .margin({ bottom: 10 })

      TextInput({
        text: this.editCollectionName,
        placeholder: $r('app.string.ideapool_collection_name_placeholder')
      })
        .caretColor($r('app.color.primary'))
        .backgroundColor($r('app.color.bg_card'))
        .placeholderColor($r('app.color.text_disabled'))
        .border({ width: $r('app.float.ideapool_collection_input_border_width'), color: $r('app.color.neutral_200') })
        .borderRadius($r('app.float.ideapool_collection_input_radius'))
        .height($r('app.float.ideapool_collection_input_height'))
        .width('100%')
        .onChange((value: string) => {
          this.editCollectionName = value;
        })
    }
    .margin({ top: $r('app.float.ideapool_collection_section_gap') })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private editCollectionDescriptionSection() {
    Column() {
      Text($r('app.string.ideapool_collection_desc_label'))
        .fontSize(15)
        .fontWeight(500)
        .margin({ bottom: 10 })

      TextArea({
        text: this.editCollectionSummary,
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
          this.editCollectionSummary = value;
        })
    }
    .margin({ top: $r('app.float.ideapool_collection_section_gap') })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private editCollectionTagSelectorSection() {
    Column() {
      Row() {
        Text($r('app.string.ideapool_collection_tag_label'))
          .fontSize(15)
          .fontWeight(500)
      }
      .alignItems(VerticalAlign.Bottom)
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
            .translate({ z: this.editCollectionSelectedTagIndex === index ? -30 : 0 })
            // .scale(this.editCollectionSelectedTagIndex === index ? { x: 1.1 , y: 1.1 } : {})
            .animation({ curve: curves.springMotion(0.35, 0.6), duration: 50 })
            .shadow(this.editCollectionSelectedTagIndex === index
              ? AppShadows.getTagPillShadow(tag.color, this.isDarkTheme)
              : AppShadows.NONE)
            .justifyContent(FlexAlign.Center)
            .borderRadius(20)
            .onClick(() => {
              if (this.editCollectionSelectedTagIndex !== index) {
                this.editCollectionSelectedTagIndex = index;
                void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
              }
            })

            if (this.editCollectionSelectedTagIndex === index) {
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
  private editCollectionEmojiSelectorSection() {
    Column() {
      Row() {
        Text($r('app.string.ideapool_collection_emoji_label'))
          .fontSize(15)
          .fontWeight(500)
      }
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 5 })

      Grid() {
        ForEach(this.emojis, (emoji: EmojiItem) => {
          GridItem() {
            Text(emoji.char)
              .fontSize(16)
              .padding(8)
              .borderRadius('50%')
              .backgroundColor($r('app.color.bg_main'))
              .shadow(this.editCollectionSelectedEmojiChar === emoji.char
                ? { color: $r('app.color.primary'), radius: 12 }
                : { radius: 0 })
          }
          .onClick(() => {
            if (this.editCollectionSelectedEmojiChar !== emoji.char) {
              this.editCollectionSelectedEmojiChar = emoji.char;
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

  @Builder
  private editIdeaSheetTitleBuilder() {
    buildSheetTitleBar({
      title: this.editIdeaSheetConfig.titleBar.title,
      actionButtonText: this.isSavingIdeaEdit
        ? $r('app.string.ideapool_idea_action_saving')
        : this.editIdeaSheetConfig.titleBar.actionButtonText,
      actionButtonDisabled: this.isSavingIdeaEdit,
      onClose: () => {
        this.isIdeaEditSheetShow = false;
        this.resetEditIdeaForm();
      },
      onSubmit: async () => {
        await this.handleIdeaEditSave();
      }
    });
  }

  @Builder
  private editIdeaSheetContentBuilder() {
    ItemFormContent({
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
      onClose: () => {
        this.isIdeaEditSheetShow = false;
        this.resetEditIdeaForm();
      },
      onConfirm: async () => {
        await this.handleIdeaEditSave();
      },
      onCollectionSelectionChange: (collectionId: string | null) => {
        this.editingSelectedCollectionId = collectionId;
        void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
      }
    });
  }

  private async loadCollectionDetail(animate: boolean): Promise<void> {
    if (!this.collectionId || this.collectionId.trim().length === 0) {
      promptAction.openToast({ duration: 1200, message: '未获取到灵感集ID' }).catch(() => {
      });
      return;
    }
    this.selectedCollectionId = this.collectionId;
    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const payload: IdeaCollectionDetailPayload = await service.fetchIdeaCollectionDetail(this.defaultUserId, this.collectionId);
      this.collection = payload.collection;
      this.collectionSummary = payload.summary;
      this.ideaActivities = this.sortActivitiesByLightCount(payload.activities);
      if (!this.isCollectionEditSheetShow) {
        this.syncEditCollectionFormFromCollection();
      }
      this.relativeTimeBaseline = Date.now();
      this.syncAnimatedIdeaLists(animate);
      this.ensureSectionHeaderContent();
    } catch (error) {
      hilog.error(0x0000, TAG, `loadCollectionDetail failed: ${JSON.stringify(error)}`);
    }
  }

  private sortActivitiesByLightCount(activities: IdeaActivity[]): IdeaActivity[] {
    if (!Array.isArray(activities) || activities.length <= 1) {
      return Array.isArray(activities) ? [...activities] : [];
    }
    const sorted: IdeaActivity[] = [...activities];
    sorted.sort((left: IdeaActivity, right: IdeaActivity) => {
      const leftCount: number = typeof left.ideaLightCount === 'number' ? left.ideaLightCount : 0;
      const rightCount: number = typeof right.ideaLightCount === 'number' ? right.ideaLightCount : 0;
      if (rightCount !== leftCount) {
        return rightCount - leftCount;
      }
      const leftOrder: number = typeof left.displayOrder === 'number' ? left.displayOrder : Number.MAX_SAFE_INTEGER;
      const rightOrder: number = typeof right.displayOrder === 'number' ? right.displayOrder : Number.MAX_SAFE_INTEGER;
      if (leftOrder !== rightOrder) {
        return leftOrder - rightOrder;
      }
      return right.updatedAt - left.updatedAt;
    });
    return sorted;
  }

  private async handleAddIdeaToCollection(name: string, tagId: string | null, collectionId: string | null): Promise<void> {
    const trimmedName: string = name !== undefined && name !== null ? name.trim() : '';
    if (trimmedName.length === 0 || this.collectionId.trim().length === 0) {
      return;
    }

    const resolvedCollectionId: string | null = collectionId !== undefined
      ? this.normalizeCollectionId(collectionId)
      : this.normalizeCollectionId(this.collectionId);
    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const newIdea: IdeaActivity | null = await service.createIdea(this.defaultUserId, { name: trimmedName, tagId: tagId });
      if (!newIdea) {
        promptAction.openToast({ duration: 1000, message: '添加灵感失败' }).catch(() => {
        });
        return;
      }
      if (resolvedCollectionId !== null) {
        hilog.info(0x0000, TAG, `IdeaCollection assign begin: collectionId=${resolvedCollectionId}, activityId=${newIdea.id}`);
        const assigned: boolean = await service.assignIdeaToCollection(this.defaultUserId, newIdea.id, resolvedCollectionId, 999999);
        if (!assigned) {
          hilog.error(0x0000, TAG, `IdeaCollection assign failed: collectionId=${resolvedCollectionId}, activityId=${newIdea.id}`);
          promptAction.openToast({ duration: 1200, message: '加入灵感集失败' }).catch(() => {
          });
          return;
        }
        hilog.info(0x0000, TAG, `IdeaCollection assign success: collectionId=${resolvedCollectionId}, activityId=${newIdea.id}`);
      }
      await this.loadCollectionDetail(true);
      await this.syncIdeaPoolStorage();
      this.notifyIdeaPoolRefresh();
      promptAction.openToast({ duration: 1000, message: '灵感已添加' }).catch(() => {
      });
    } catch (error) {
      hilog.error(0x0000, TAG, `handleAddIdeaToCollection failed: ${JSON.stringify(error)}`);
      promptAction.openToast({ duration: 1000, message: '添加灵感时发生错误' }).catch(() => {
      });
    }
  }

  private applyIdeaUpdateToLocalState(updated: IdeaActivity): void {
    const target: IdeaActivity | undefined = this.ideaActivities.find(item => item.id === updated.id);
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
    }
  }

  private openIdeaEditSheet(activity: IdeaActivity): void {
    this.resetEditIdeaForm();
    this.editingIdea = activity;
    this.editingIdeaName = activity.name;
    this.editingSelectedTagIndex = this.resolveTagIndex(activity.tagId);
    const resolvedCollectionId: string | null = this.normalizeCollectionId(this.collectionId);
    this.editingSelectedCollectionId = resolvedCollectionId;
    this.editingInitialCollectionId = resolvedCollectionId;
    this.recalculateSheetHeight();
    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
    this.isIdeaEditSheetShow = true;
  }

  private async handleIdeaEditSave(): Promise<void> {
    if (!this.editingIdea) {
      return;
    }
    const trimmedName: string = this.editingIdeaName ? this.editingIdeaName.trim() : '';
    if (!trimmedName) {
      promptAction.openToast({ duration: 1000, message: '灵感名称不能为空' }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
      return;
    }
    if (this.isSavingIdeaEdit) {
      return;
    }

    this.isSavingIdeaEdit = true;
    const selectedTagId: string | null = this.resolveTagIdByIndex(this.editingSelectedTagIndex);
    const targetCollectionId: string | null = this.normalizeCollectionId(this.editingSelectedCollectionId);
    const initialCollectionId: string | null = this.normalizeCollectionId(this.editingInitialCollectionId);

    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const updated: IdeaActivity | null = await service.updateIdea(this.defaultUserId, this.editingIdea.id, {
        name: trimmedName,
        tagId: selectedTagId
      });
      if (!updated) {
        promptAction.openToast({ duration: 1000, message: '更新灵感失败' }).catch(() => {
        });
        await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
        return;
      }

      this.applyIdeaUpdateToLocalState(updated);
      await this.applyCollectionAssignmentChanges(updated.id, targetCollectionId, initialCollectionId);
      await this.loadCollectionDetail(false);
      await this.syncIdeaPoolStorage();
      this.notifyIdeaPoolRefresh();

      promptAction.openToast({ duration: 1000, message: '灵感已更新' }).catch(() => {
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
      this.isIdeaEditSheetShow = false;
      this.resetEditIdeaForm();
    } catch (error) {
      hilog.error(0x0000, TAG, `handleIdeaEditSave failed: ${JSON.stringify(error)}`);
      promptAction.openToast({ duration: 1000, message: '更新灵感时发生错误' }).catch(() => {
      });
      await this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    } finally {
      this.isSavingIdeaEdit = false;
    }
  }

  private resetEditIdeaForm(): void {
    this.editingIdea = null;
    this.editingIdeaName = '';
    this.editingSelectedTagIndex = -1;
    this.editingSelectedCollectionId = null;
    this.editingInitialCollectionId = null;
    this.isSavingIdeaEdit = false;
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

  private appendTodayActivityToStorage(todayItem: MatterItemModel): void {
    this.matterData = this.upsertMatterItem(this.matterData, todayItem);
    if (todayItem.status === MatterStatus.TODO) {
      this.unDoMatterData = this.upsertMatterItem(this.unDoMatterData, todayItem);
      this.doneMatterData = this.removeMatterItem(this.doneMatterData, todayItem.id);
      return;
    }
    this.doneMatterData = this.upsertMatterItem(this.doneMatterData, todayItem);
    this.unDoMatterData = this.removeMatterItem(this.unDoMatterData, todayItem.id);
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

  private async handleMoveIdeaToToday(activity: IdeaActivity): Promise<void> {
    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const addResult: AddIdeaToTodayResult | null = await service.addIdeaToToday(
        this.defaultUserId,
        activity,
        this.ideapoolDirectRecord
      );
      if (!addResult) {
        promptAction.openToast({ duration: 1000, message: '移入今日失败' }).catch(() => {
        });
        return;
      }
      const todayItem = this.mapIdeaActivityToTodayItem(activity, addResult.createdActivityId, addResult.status);
      if (addResult.status === MatterStatus.RECORDING) {
        await this.syncAutoRecordRunningState(todayItem);
      }
      this.appendTodayActivityToStorage(todayItem);
      await this.loadCollectionDetail(true);
      await this.syncIdeaPoolStorage();
      this.notifyIdeaPoolRefresh();
    } catch (error) {
      hilog.error(0x0000, TAG, `handleMoveIdeaToToday failed: ${JSON.stringify(error)}`);
    }
  }

  private async syncAutoRecordRunningState(todayItem: MatterItemModel): Promise<void> {
    // Phase 4-2: 会话统一经 store 收养（DB open record 为准），全局运行键由投影单写者维护
    await recordingSessionStore.adoptOpenRecord(todayItem.id);
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

  private applyIdeaDeletion(activityId: string): void {
    const removeIndex: number = this.ideaActivities.findIndex(item => item.id === activityId);
    if (removeIndex >= 0) {
      this.ideaActivities.splice(removeIndex, 1);
    }
    this.updateRelativeTimeBaseline();
    this.syncAnimatedIdeaLists(true);
  }

  private async handleDeleteIdea(activity: IdeaActivity): Promise<void> {
    hilog.info(0x0000, TAG, `User trying to delete idea: ${activity.id}, ${activity.name}`);
    try {
      const ideaPoolService: IdeaPoolService = await this.ensureIdeaPoolService();
      const deleteResult = await ideaPoolService.deleteIdeas(this.defaultUserId, { ids: [activity.id] });
      if (!deleteResult.deletedIds.includes(activity.id)) {
        hilog.warn(0x0000, TAG, `Failed to delete idea: ${activity.id}`);
        promptAction.openToast({ message: '删除灵感失败', duration: 1000 }).catch(() => {
        });
        void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
        return;
      }

      // 确认删除后，先触发动画，再更新数据
      if (this.ideaExpandAnimationProps && this.ideaExpandAnimationProps.isExpandPageShow) {
        this.ideaExpandAnimationProps.collapseAnimation(() => {}, CollapseAnimationType.DELETE);
      }

      this.applyIdeaDeletion(activity.id);
      await this.syncIdeaPoolStorage();
      this.notifyIdeaPoolRefresh();

      promptAction.openToast({ message: '灵感已删除', duration: 1000 }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
      hilog.info(0x0000, TAG, `Idea deleted successfully: ${activity.id}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `Error deleting idea: ${JSON.stringify(error)}`);
      promptAction.openToast({ message: '删除灵感时发生错误', duration: 1000 }).catch(() => {
      });
      void this.vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    }
  }

  private applyIdeaRollbackToState(activityId: string, updatedAt: number): void {
    const target: IdeaActivity | undefined = this.ideaActivities.find(item => item.id === activityId);
    if (!target) {
      return;
    }
    target.ideaLightState = IdeaLightState.UNLIT;
    target.ideaLightCount = 0;
    target.updatedAt = updatedAt;
    this.updateRelativeTimeBaseline();
    this.syncAnimatedIdeaLists(true);
  }

  private async handleRollbackIdeaToUnlit(activity: IdeaActivity): Promise<void> {
    if (activity.ideaLightState !== IdeaLightState.LIT) {
      return;
    }
    hilog.info(0x0000, TAG, `User trying to rollback idea to unlit: ${activity.id}, ${activity.name}`);
    try {
      const ideaPoolService: IdeaPoolService = await this.ensureIdeaPoolService();
      const updated: boolean = await ideaPoolService.rollbackIdeaToUnlit(this.defaultUserId, activity.id);
      if (!updated) {
        hilog.warn(0x0000, TAG, `Failed to rollback idea to unlit: ${activity.id}`);
        return;
      }
      // 确认回退后，先触发动画，再更新数据
      if (this.ideaExpandAnimationProps && this.ideaExpandAnimationProps.isExpandPageShow) {
        this.ideaExpandAnimationProps.collapseAnimation(() => {}, CollapseAnimationType.ROLLBACK);
      }
      this.applyIdeaRollbackToState(activity.id, Date.now());
      await this.syncIdeaPoolStorage();
      this.notifyIdeaPoolRefresh();
    } catch (error) {
      hilog.error(0x0000, TAG, `Error rolling back idea to unlit: ${JSON.stringify(error)}`);
    }
  }

  private notifyIdeaPoolRefresh(): void {
    const currentToken = AppStorage.get(this.ideaPoolRefreshTokenKey) as number | undefined;
    const nextToken: number = typeof currentToken === 'number' ? currentToken + 1 : 1;
    AppStorage.setOrCreate(this.ideaPoolRefreshTokenKey, nextToken);
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
    if (AppStorage.get('ideapoolUnlitFirst') === undefined) {
      AppStorage.setOrCreate('ideapoolUnlitFirst', true);
    }
    if (AppStorage.get('ideapoolDirectRecord') === undefined) {
      AppStorage.setOrCreate('ideapoolDirectRecord', false);
    }
  }

  private async syncIdeaPoolStorage(): Promise<void> {
    try {
      const service: IdeaPoolService = await this.ensureIdeaPoolService();
      const nextState = await service.fetchIdeaPool(this.defaultUserId);
      this.ideaPoolActivities = nextState.activities;
      this.ideaPoolCollections = Array.isArray(nextState.collections) ? [...nextState.collections] : [];
      const summaries = Array.isArray(nextState.collectionSummaries)
        ? [...nextState.collectionSummaries]
        : [];
      const localSummary = this.buildLocalCollectionSummary();
      if (localSummary) {
        const summaryIndex = summaries.findIndex(item => item.collectionId === localSummary.collectionId);
        if (summaryIndex >= 0) {
          summaries[summaryIndex] = localSummary;
        } else {
          summaries.push(localSummary);
        }
      }
      this.ideaPoolCollectionSummaries = summaries;
    } catch (error) {
      hilog.error(0x0000, TAG, `syncIdeaPoolStorage failed: ${JSON.stringify(error)}`);
    }
  }

  private buildLocalCollectionSummary(): IdeaCollectionSummary | null {
    const collectionId = this.collectionId ? this.collectionId.trim() : '';
    if (collectionId.length === 0) {
      return null;
    }
    const summary = IdeaPoolService.deriveIdeaLightSummary(this.ideaActivities);
    return {
      collectionId: collectionId,
      totalCount: summary.totalCount,
      litCount: summary.litCount,
      unlitCount: summary.unlitCount
    };
  }

  @Builder
  private renderHeaderCard() {
    Column() {
      Row() {
        Row() {
          Text(this.resolveCollectionIcon())
            .fontSize(COLLECTION_HEADER_ICON_SIZE)

          Column() {
            Text(this.resolveCollectionTitle())
              .fontSize(COLLECTION_HEADER_TITLE_SIZE)
              .fontWeight(700)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.resolveCollectionSubtitle().length > 0) {
              Text(this.resolveCollectionSubtitle())
                .fontSize(COLLECTION_HEADER_SUBTITLE_SIZE)
                .fontWeight(400)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 8 })
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .margin({ left: 12 })
          .alignItems(HorizontalAlign.Start)
        }
        .alignItems(VerticalAlign.Top)
        .layoutWeight(1)

        if (this.collection !== null) {
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(16)
              .fontWeight(500)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.5 })
          .shadow({ color: $r('app.color.accent_lighter'), radius: 10 })
          .padding(8)
          .backgroundColor($r('app.color.bg_card'))
          .border({ width: 1, color: $r('app.color.neutral_200') })
          .borderRadius(18)
          .onClick(() => {
            void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
            this.openCollectionEditSheet();
          })
          .bindSheet($$this.isCollectionEditSheetShow, this.editCollectionSheetContentBuilder(), {
            detents: [SheetSize.LARGE],
            showClose: false,
            dragBar: false,
            preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER }).getValue(this.currentBreakpoint),
            blurStyle: BlurStyle.COMPONENT_REGULAR,
            enableOutsideInteractive: false,
            keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
            onWillAppear: () => {
              this.syncEditCollectionFormFromCollection();
            },
            onWillDismiss: (dismissSheetAction: DismissSheetAction) => {
              this.isCollectionEditSheetShow = false;
              this.resetEditCollectionForm();
              if (dismissSheetAction.reason === DismissReason.CLOSE_BUTTON) {
                dismissSheetAction.dismiss();
              }
              if (dismissSheetAction.reason === DismissReason.PRESS_BACK) {
                dismissSheetAction.dismiss();
              }
              if (dismissSheetAction.reason === DismissReason.SLIDE_DOWN) {
                dismissSheetAction.dismiss();
              }
            }
          })
        }
      }
      .alignItems(VerticalAlign.Top)
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 18, right: 18, top: 18 })
      .width('100%')

      Divider()
        .color($r('app.color.neutral_200'))
        .strokeWidth(1)
        .margin({ top: 16, bottom: 16, left: 18, right: 18 })

      Row() {
        Column() {
          Text(this.resolveCollectionLitCount().toString())
            .fontSize(COLLECTION_HEADER_STAT_NUMBER_SIZE)
            .fontWeight(700)
            .fontColor($r('app.color.text_primary'))
            .contentTransition(this.litCountTransition)

          Text($r('app.string.ideapool_summary_lit'))
            .fontSize(COLLECTION_HEADER_STAT_LABEL_SIZE)
            .fontWeight(400)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 6 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.resolveCollectionUnlitCount().toString())
            .fontSize(COLLECTION_HEADER_STAT_NUMBER_SIZE)
            .fontWeight(700)
            .fontColor($r('app.color.text_primary'))
            .contentTransition(this.unlitCountTransition)

          Text($r('app.string.ideapool_summary_unlit'))
            .fontSize(COLLECTION_HEADER_STAT_LABEL_SIZE)
            .fontWeight(400)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 6 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.resolveCollectionLitTimesCount().toString())
            .fontSize(COLLECTION_HEADER_STAT_NUMBER_SIZE)
            .fontWeight(700)
            .fontColor($r('app.color.text_primary'))
            .contentTransition(this.litTimesTransition)

          Text($r('app.string.ideapool_summary_lit_times'))
            .fontSize(COLLECTION_HEADER_STAT_LABEL_SIZE)
            .fontWeight(400)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 6 })
        }
        .layoutWeight(1)
      }
      .padding({ left: 18, right: 18, bottom: 18 })
      .width('100%')
    }
    .width('100%')
    // .height(COLLECTION_HEADER_CARD_HEIGHT)
    .backgroundColor($r('app.color.bg_main'))
    .borderRadius(24)
    .clip(true)
    .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)
  }

  @Builder
  private renderEmptyState() {
    Column() {
      Image($r('app.media.no_idea_yet'))
        .width($r('app.float.ideapool_empty_icon_size'))
        .height($r('app.float.ideapool_empty_icon_size'))
        .objectFit(ImageFit.Contain)

      Text($r('app.string.ideapool_collection_empty_title'))
        .fontSize($r('app.float.ideapool_empty_text_font_size'))
        .fontWeight(400)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: $r('app.float.ideapool_empty_text_top_margin') })

      Button($r('app.string.ideapool_collection_empty_action'))
        .margin({ top: 18 })
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.primary'))
        .fontSize(16)
        .onClick(() => {
          void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
          this.recalculateSheetHeight();
          this.isShowAddSheet = true;
        })
    }
    .width('100%')
    .margin({ top: 120 })
    .alignItems(HorizontalAlign.Center)
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
    }, (laneIndex: number) => `collection_bottom_spacer_lane_${laneIndex}`)
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
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

            Column() {
              this.renderHeaderCard()
            }
            .margin({ left: 12, right: 12, top: 12 })

            if (this.animatedLitIdeas.length === 0 && this.animatedUnlitIdeas.length === 0) {
              this.renderEmptyState()
            } else {
              List() {
                if (this.shouldRenderUnlitFirst()) {
                  this.renderUnlitIdeaListGroup();
                  this.renderLitIdeaListGroup();
                } else {
                  this.renderLitIdeaListGroup();
                  this.renderUnlitIdeaListGroup();
                }

                this.renderIdeaListBottomSpacers();
              }
              .width('100%')
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .lanes(this.getIdeaListLanes())
              .enableScrollInteraction(false)
              .padding({ top: 12 })
            }

            Blank()
              .height($r('app.float.immersive_nav_bottom_spacer_height'))
              .width('100%')
          }
          .width('100%')
        }
        .width('100%')
        .enabled(this.shouldEnableCollectionContent())
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
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Row() {
          AddIdeaBall()
            .width(55)
            .height(55)
            .margin({ bottom: new BreakpointType<number>({ sm: 75, md: 75, lg: 40 }).getValue(this.currentBreakpoint) })
            .visibility(this.ballVisible)
            .transition(this.effect)
            .onClick(() => {
              void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
              this.recalculateSheetHeight();
              this.isShowAddSheet = true;
            })
            .bindSheet($$this.isShowAddSheet, this.addNewItemBuilder(), {
              detents: this.ideaFormSheetDetents,
              showClose: false,
              preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER }).getValue(this.currentBreakpoint),
              dragBar: false,
              blurStyle: BlurStyle.COMPONENT_REGULAR,
              enableOutsideInteractive: false,
              keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
              title: this.titleBuilder,
              onWillAppear: () => {
                this.updateIdeaFormSheetDetents();
              },
              onWillDismiss: (dismissSheetAction: DismissSheetAction) => {
                this.isShowAddSheet = false;
                this.updateIdeaFormSheetDetents();
                this.resetAddIdeaForm();
                if (dismissSheetAction.reason === DismissReason.CLOSE_BUTTON ||
                  dismissSheetAction.reason === DismissReason.PRESS_BACK ||
                  dismissSheetAction.reason === DismissReason.SLIDE_DOWN) {
                  dismissSheetAction.dismiss();
                }
              }
            })
        }
        .width(this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG ? '100%' : (this.holdingHandEnabled ? '100%' : undefined))
        .justifyContent(this.resolveHoldingHandAlign())
        .padding({
          left: new BreakpointType<number>({ sm: 12, md: 12, lg: 12 }).getValue(this.currentBreakpoint),
          right: new BreakpointType<number>({ sm: 12, md: 12, lg: 24 }).getValue(this.currentBreakpoint)
        })
        .offset({ y: -this.resolveHoldingHandOffsetY() })
        .animation({ curve: curves.springMotion(0.35, 0.9), duration: 240 })
        .hitTestBehavior(HitTestMode.Transparent)
        .enabled(this.shouldEnableCollectionContent())

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
      .enabled(this.shouldEnableCollectionRoot())
      .bindSheet($$this.isIdeaEditSheetShow, this.editIdeaSheetContentBuilder(), {
        detents: this.ideaFormSheetDetents,
        showClose: false,
        preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER }).getValue(this.currentBreakpoint),
        dragBar: false,
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        enableOutsideInteractive: false,
        keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
        title: this.editIdeaSheetTitleBuilder,
        onWillAppear: () => {
          this.updateIdeaFormSheetDetents();
        },
        onWillDismiss: (dismissSheetAction: DismissSheetAction) => {
          this.isIdeaEditSheetShow = false;
          this.updateIdeaFormSheetDetents();
          this.resetEditIdeaForm();
          if (dismissSheetAction.reason === DismissReason.CLOSE_BUTTON ||
            dismissSheetAction.reason === DismissReason.PRESS_BACK ||
            dismissSheetAction.reason === DismissReason.SLIDE_DOWN) {
            dismissSheetAction.dismiss();
          }
        }
      })
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
      const param: IdeaCollectionDetailRouteParam | null =
        context.pathInfo.param as IdeaCollectionDetailRouteParam;
      const nextId: string = param && typeof param.collectionId === 'string' ? param.collectionId : '';
      this.collectionId = nextId;
      this.selectedCollectionId = nextId;
      void this.loadCollectionDetail(false);
      hilog.info(0x0000, TAG, `navigated to collection detail, id=${nextId}`);
    })
    .titleBar({
      content: {
        title: {
          mainTitle: this.getPageTitle()
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
    .ignoreLayoutSafeArea(
      [LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]
    )
    .width('100%')
    .height('100%')
    .expandSafeArea(
      [SafeAreaType.SYSTEM],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
    )
    .backgroundColor($r('app.color.bg_main'))
  }
}
