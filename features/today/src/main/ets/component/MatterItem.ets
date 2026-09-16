import { LabelItem } from "./LabelItem";
import {
  AppShadows,
  BreakpointConstants,
  BreakpointType,
  buildPointLightEffect,
  FilesDirCarrier,
  MatterStatus,
  RDBStoreUtil,
  pickSingleImageUri,
  relPathToImageUri,
  SessionSnapshot,
  TimeRecordUtil,
  VibratorUtil
} from 'base';
import { MatterItemModel } from 'base';
import { hilog } from "@kit.PerformanceAnalysisKit";
import { curves, promptAction } from "@kit.ArkUI";
import { MatterItemStateManager, MatterItemStateSnapshot } from "../utils/MatterItemStateManager";
import { hdsEffect } from "@kit.UIDesignKit";
import { liveViewController } from "../liveView/LiveViewManger";
import { common } from '@kit.AbilityKit';
import { todayActivityService } from '../model/TodayActivityService';
import {
  doesAutoStopRunningSnapshotMatch,
  getAutoStopRunningSnapshotFromAppStorage
} from '../model/AutoStopSettings';

const TAG = 'MatterItem';
const BACKGROUND_TASK_LOG_PREFIX: string = 'background task';

function createEmptySnapshot(): MatterItemStateSnapshot {
  return {
    itemId: '',
    status: MatterStatus.TODO,
    durationInMilliseconds: 0,
    isRunning: false,
    currentRecordId: '',
    record: undefined,
    restartBackgroundTask: false,
    lastKnownStartTime: 0
  };
}

const EMPTY_SNAPSHOT: MatterItemStateSnapshot = createEmptySnapshot();

// 动画曲线常量
const EXPAND_ANIMATION_CURVE = curves.springMotion(0.45, 0.75);
const EXPAND_ANIMATION_DURATION = 200;
const EXPANDED_CARD_RADIUS = 20;
const EXPANDED_ENTRY_CURVE = curves.springMotion(0.5, 0.82);
const EXPANDED_ENTRY_DURATION = 260;
type ButtonGlowTarget = 'collapsed' | 'expandedAction' | 'expandedSave' | null;

interface TouchBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

function createExpandedEntryTransition(offsetY: number, delay: number, scaleFrom: number = 0.96): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: offsetY }))
      .combine(TransitionEffect.scale({ x: scaleFrom, y: scaleFrom }))
      .animation({ curve: EXPANDED_ENTRY_CURVE, duration: EXPANDED_ENTRY_DURATION, delay: delay }),
    undefined
  );
}

/** 秒数 → mm:ss / hh:mm:ss（承接原 TextTimerModifier.timeFormat）。 */
function formatSecondsAsClock(totalSeconds: number): string {
  const safeSeconds = Math.max(0, Math.floor(totalSeconds));
  const hours = Math.floor(safeSeconds / 3600);
  const minutes = Math.floor((safeSeconds % 3600) / 60);
  const seconds = safeSeconds % 60;
  const minutesText = minutes < 10 ? `0${minutes}` : `${minutes}`;
  const secondsText = seconds < 10 ? `0${seconds}` : `${seconds}`;
  if (hours <= 0) {
    return `${minutesText}:${secondsText}`;
  }
  const hoursText = hours < 10 ? `0${hours}` : `${hours}`;
  return `${hoursText}:${minutesText}:${secondsText}`;
}

@Component
export struct MatterItem {
  @State isButtonGlowActive: boolean = false;
  @State isExpandedActionButtonGlowActive: boolean = false;
  @State isExpandedSaveButtonGlowActive: boolean = false;
  @State comment: string = ''
  @StorageLink('liveViewId') liveViewId: number = 0 % 1000;
  @State controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  @Watch('onItemLinkChanged') @ObjectLink item: MatterItemModel;
  // 展开模式标志 - 用于控制展开视图的布局
  @Watch('onExpandedChanged') @Prop expanded: boolean = false;
  // 从父组件（NodeBuilder）传入的深色模式状态，用于 BuilderNode 上下文中的主题响应
  @Watch('onThemeChanged') @Prop isDarkThemeProp?: boolean;

  private manager: MatterItemStateManager = MatterItemStateManager.getInstance();
  private isInitializing: boolean = true; // Guard flag to prevent @Watch during initialization

  @State runtimeState: MatterItemStateSnapshot = createEmptySnapshot();
  @Watch('onItemStatusChanged') @State itemStatus: MatterStatus = MatterStatus.TODO;
  @State isRunning: boolean = false;
  @State currentRecordId: string = '';
  @State itemDurationInMilliseconds: number = 0;
  @State progressValue: number = 0;
  @State animationId: number | null = null;
  @State itemVersion: number = 0;
  private isStoppingFromLongPress: boolean = false;
  private isReconcilingIncomingRecording: boolean = false;
  private runningStateSyncVersion: number = 0;
  @StorageLink('isDarkTheme') @Watch('onThemeChanged') isDarkThemeStorage: boolean = false;
  @StorageLink('isDarkTheme') @Watch('onThemeChanged') isDarkTheme: boolean = false;
  @StorageLink('todayPageVisible') @Watch('onPageVisibilityGateChanged') todayPageVisible: boolean = false;
  @State borderEffect: VisualEffect | undefined = undefined;
  @State isCardTouchActive: boolean = false;
  @State showRecordingBorder: boolean = false;
  @StorageProp(BreakpointConstants.CURRENT_BREAKPOINT) currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  // Phase 3 去控制器化：计时文本 = store 投影派生（runningSessionView 匹配本 item 时显示 sessionElapsedSeconds）
  // Phase 4-5：唯一会话订阅（身份键变更/清空时触发对账），颜色直接取快照
  @StorageProp('runningSessionView') @Watch('onRunningSessionViewChanged') runningSessionView: SessionSnapshot | null = null;
  @StorageProp('sessionElapsedSeconds') sessionElapsedSeconds: number = 0;

  // private buttonEffect: TransitionEffect | undefined = undefined;
  private buttonEffect: TransitionEffect = TransitionEffect.asymmetric(
    TransitionEffect.scale({x:0.6, y:0.6}),
    undefined
  )
    .animation({ curve: curves.springMotion(0.6, 0.8), duration: 150 });

  @StorageLink('appInForeground') @Watch('onAppForegroundStateChanged') appInForeground: boolean = true;

  private context: Context = this.getUIContext().getHostContext() as Context;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  @State coverImageUri: string | null = null;
  @State coverImageLocalPath: string | null = null;
  @State isSavingCoverImage: boolean = false;
  @State commentDirty: boolean = false;
  @State isSavingComment: boolean = false;
  private lastSavedComment: string = '';
  private lastSavedActivityId: string = '';

  // 预加载相关状态
  private isPreloading: boolean = false; // 是否正在预加载
  private preloadTimer: number = -1; // 预加载延迟定时器
  private preloadTouchStartTime: number = 0; // 触摸开始时间
  private commentLoaded: boolean = false; // 评论是否已加载
  private static readonly PRELOAD_DELAY_MS = 50; // 预加载延迟，快速响应触摸
  private static readonly LONG_PRESS_THRESHOLD_MS = 300; // 长按阈值，用于判断是否真的要展开
  private static readonly CARD_TOUCH_LIGHT_HEIGHT = 90;
  private static readonly CARD_RECORDING_LIGHT_HEIGHT = 110;
  private static readonly BUTTON_TOUCH_LIGHT_HEIGHT = 110;
  private activeButtonGlowTarget: ButtonGlowTarget = null;
  private activeButtonGlowBounds: TouchBounds | null = null;

  /**
   * Save comment to database
   */
  private async saveCommentNow(): Promise<void> {
    if (!this.item?.id) {
      return;
    }
    if (this.isSavingComment || !this.commentDirty) {
      return;
    }
    this.isSavingComment = true;
    try {
      const currentText = this.comment ?? '';
      const success = await todayActivityService.saveActivityDiary(this.item.id, currentText);
      if (success) {
        this.lastSavedActivityId = this.item.id;
        this.lastSavedComment = currentText;
        this.commentDirty = false;
        hilog.info(0x0000, TAG, `saveComment success: activityId=${this.item.id}, textLength=${currentText.length}`);
        promptAction.openToast({ message: '评论已保存', duration: 1200 });
      } else {
        hilog.error(0x0000, TAG, `saveComment failed: activityId=${this.item.id}`);
        promptAction.openToast({ message: '保存失败，请重试', duration: 1200 });
      }
    } finally {
      this.isSavingComment = false;
    }
  }

  private updateCommentState(value: string): void {
    this.comment = value;
    this.commentDirty = value !== this.lastSavedComment;
  }

  /**
   * Load comment from database
   */
  private async loadComment(): Promise<void> {
    if (!this.item?.id) {
      return;
    }
    if (this.commentLoaded) {
      hilog.info(0x0000, TAG, `loadComment skipped: commentLoaded=true activityId=${this.item.id}`);
      return;
    }
    const text = await todayActivityService.queryActivityDiary(this.item.id);
    this.comment = text;
    this.lastSavedActivityId = this.item.id;
    this.lastSavedComment = text;
    this.commentLoaded = true;
    this.commentDirty = false;
    hilog.info(0x0000, TAG, `loadComment success activityId=${this.item.id} textLength=${text.length} commentContent="${text}"`);
  }

  /**
   * Load comment if not already loaded
   */
  private async loadCommentIfNeeded(): Promise<void> {
    if (this.commentLoaded) {
      hilog.info(0x0000, TAG, `loadCommentIfNeeded skipped: commentLoaded=true activityId=${this.item.id}`);
      return;
    }
    await this.loadComment();
  }

  private promptSaveDialog(): void {
    if (!this.commentDirty) {
      return;
    }
    const uiContext = this.getUIContext();
    uiContext.showAlertDialog({
      title: '保存评论',
      message: '有未保存的评论，是否现在保存？',
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '稍后',
        action: () => {
          hilog.info(0x0000, TAG, 'User chose not to save comment yet');
        }
      },
      secondaryButton: {
        value: '保存',
        style: DialogButtonStyle.HIGHLIGHT,
        action: () => {
          void this.saveCommentNow();
        }
      },
      onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
        if (dismissDialogAction.reason === DismissReason.PRESS_BACK
          || dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissDialogAction.dismiss();
        }
      }
    });
  }

  /**
   * Lifecycle: save comment when component is about to disappear
   */
  aboutToDisappear(): void {
    // Prompt save before component disappears
    this.promptSaveDialog();
    // Clear preload timer
    this.cancelPreload();
    this.resetProgressAnimation();
  }

  private onItemLinkChanged(): void {
    if (!this.item) {
      return;
    }
    const sessionOwnsThisItem = this.runningSessionView !== null && this.runningSessionView.itemId === this.item.id;
    const shouldDeferIncomingRecording = !this.isStoppingFromLongPress &&
      this.item.status === MatterStatus.RECORDING &&
      !this.isRunning &&
      !sessionOwnsThisItem;

    hilog.info(0x0000, TAG,
      `Sync Matter Status: onItemLinkChanged id=${this.item.id} incomingStatus=${this.item.status} localStatus=${this.itemStatus} isRunning=${this.isRunning} sessionOwnsThisItem=${sessionOwnsThisItem} deferIncomingRecording=${shouldDeferIncomingRecording}`);

    // 如果 item.id 发生变化，需要重置评论加载状态
    if (this.lastSavedActivityId && this.lastSavedActivityId !== this.item.id) {
      hilog.info(0x0000, TAG, `Item changed, resetting commentLoaded: old=${this.lastSavedActivityId} new=${this.item.id}`);
      this.commentLoaded = false;
      this.comment = '';
      this.lastSavedActivityId = '';
      this.lastSavedComment = '';
      this.commentDirty = false;
    }

    if (this.itemStatus !== this.item.status &&
      !(this.isStoppingFromLongPress && this.item.status === MatterStatus.RECORDING) &&
      !shouldDeferIncomingRecording) {
      this.itemStatus = this.item.status;
    }

    if (this.itemDurationInMilliseconds !== this.item.durationInMilliseconds) {
      this.itemDurationInMilliseconds = this.item.durationInMilliseconds;

      const updatedSnapshot = this.copySnapshot(this.runtimeState);
      updatedSnapshot.itemId = this.item.id;
      updatedSnapshot.status = shouldDeferIncomingRecording ? this.itemStatus : this.item.status;
      updatedSnapshot.durationInMilliseconds = this.item.durationInMilliseconds;
      updatedSnapshot.isRunning = this.isRunning;
      updatedSnapshot.currentRecordId = this.currentRecordId;
      updatedSnapshot.record = this.runtimeState.record;
      updatedSnapshot.restartBackgroundTask = this.runtimeState.restartBackgroundTask;
      updatedSnapshot.lastKnownStartTime = this.runtimeState.lastKnownStartTime;
      this.runtimeState = updatedSnapshot;
    }

    this.itemVersion++;
    // If storage says this is the current running item but status is not RECORDING yet,
    // reconcile to pull the active state from DB/manager (covers cross-device resume).
    if (shouldDeferIncomingRecording) {
      hilog.warn(0x0000, TAG,
        `Sync Matter Status: deferred incoming RECORDING snapshot item=${this.item.id}, verifying with manager`);
      void this.reconcileIncomingRecordingState();
    } else if (!this.isStoppingFromLongPress &&
      sessionOwnsThisItem && this.itemStatus !== MatterStatus.RECORDING) {
      void this.manager.refreshItemState(this.item.id);
    } else if (!this.isStoppingFromLongPress && this.itemStatus === MatterStatus.RECORDING && !this.isRunning) {
      void this.manager.refreshItemState(this.item.id);
    }

    // Force UI status to RECORDING if runtime/session indicates running but incoming status is paused.
    if (!this.isStoppingFromLongPress &&
      (this.isRunning || sessionOwnsThisItem) &&
      this.itemStatus !== MatterStatus.RECORDING) {
      hilog.info(0x0000, TAG,
        `Sync Matter Status: force RECORDING for item=${this.item.id} due to running flag mismatch`);
      this.itemStatus = MatterStatus.RECORDING;
      this.item.status = MatterStatus.RECORDING;
    }

    this.updateCardVisualStates();
  }

  private async reconcileIncomingRecordingState(): Promise<void> {
    if (this.isReconcilingIncomingRecording || !this.item?.id) {
      return;
    }
    this.isReconcilingIncomingRecording = true;
    const targetItemId = this.item.id;
    try {
      const snapshot = await this.manager.refreshItemState(targetItemId);
      if (!snapshot || this.item.id !== targetItemId) {
        return;
      }
      this.applySnapshot(snapshot);
      this.updateCardVisualStates();
    } catch (error) {
      hilog.error(0x0000, TAG,
        `Sync Matter Status: reconcileIncomingRecordingState failed item=${targetItemId}, error=${JSON.stringify(error)}`);
    } finally {
      this.isReconcilingIncomingRecording = false;
    }
  }

  private copySnapshot(source: MatterItemStateSnapshot): MatterItemStateSnapshot {
    return {
      itemId: source.itemId,
      status: source.status,
      durationInMilliseconds: source.durationInMilliseconds,
      isRunning: source.isRunning,
      currentRecordId: source.currentRecordId,
      record: source.record,
      restartBackgroundTask: source.restartBackgroundTask,
      lastKnownStartTime: source.lastKnownStartTime
    };
  }

  private applySnapshot(snapshot?: MatterItemStateSnapshot): void {
    if (!snapshot) {
      return;
    }
    this.runtimeState = this.copySnapshot(snapshot);
    this.itemStatus = snapshot.status;
    this.item.status = snapshot.status;
    this.isRunning = snapshot.isRunning;
    this.currentRecordId = snapshot.currentRecordId;
    this.itemDurationInMilliseconds = snapshot.durationInMilliseconds;
    this.item.durationInMilliseconds = snapshot.durationInMilliseconds;
  }

  private resetProgressAnimation(): void {
    if (this.animationId !== null) {
      clearInterval(this.animationId);
      this.animationId = null;
    }
    this.progressValue = 0;
  }

  private applyImmediatePausedStateForLongPress(): void {
    this.isRunning = false;
    this.itemStatus = MatterStatus.PAUSED;
    this.item.status = MatterStatus.PAUSED;
    this.resetProgressAnimation();
    this.updateCardVisualStates();
  }

  private async completeLongPressStop(): Promise<void> {
    try {
      await this.stopAndSave();
      await this.recoverRecordingUiWhenStopFailed();
    } finally {
      this.isStoppingFromLongPress = false;
    }
  }

  private async recoverRecordingUiWhenStopFailed(): Promise<void> {
    const snapshot = await this.manager.refreshItemState(this.item.id);
    if (!snapshot || !snapshot.isRunning) {
      return;
    }

    this.applySnapshot(snapshot);
    this.manager.startBackgroundTask(this.item, this.context);
    this.updateCardVisualStates();
    await liveViewController.startLiveView(0, this.item.title);
  }

  private async onPauseLongPressAction(event: GestureEvent | undefined): Promise<void> {
    if (!event || this.isStoppingFromLongPress || this.itemStatus !== MatterStatus.RECORDING) {
      return;
    }

    if (this.animationId !== null) {
      clearInterval(this.animationId);
      this.animationId = null;
    }

    const nextProgress = Math.min(100, this.progressValue + 1);
    this.progressValue = nextProgress;
    if (nextProgress < 100) {
      return;
    }

    this.isStoppingFromLongPress = true;
    this.applyImmediatePausedStateForLongPress();
    await this.completeLongPressStop();
  }

  private onPauseLongPressEnd(): void {
    if (this.isStoppingFromLongPress || this.itemStatus !== MatterStatus.RECORDING) {
      this.resetProgressAnimation();
      return;
    }

    if (this.progressValue <= 0) {
      return;
    }

    if (this.animationId !== null) {
      clearInterval(this.animationId);
    }
    this.animationId = setInterval(() => {
      this.progressValue = Math.max(0, this.progressValue - 1);
      if (this.progressValue <= 0 && this.animationId !== null) {
        clearInterval(this.animationId);
        this.animationId = null;
      }
    }, 10);
  }

  /** 纯渲染判断（Phase 3）：运行态光效/动画降级用，不再守卫任何功能路径。 */
  private shouldAnimateRunningEffects(): boolean {
    return this.appInForeground && this.todayPageVisible;
  }

  /**
   * 计时文本（Phase 3 去控制器化）：会话投影匹配本 item 时显示 sessionElapsedSeconds，
   * 否则 0；显示层按自动停止快照封顶（承接 Stage 5 行为）。
   */
  private buildRunningDurationText(): string {
    const isSessionItem = this.runningSessionView !== null && this.runningSessionView.itemId === this.item.id;
    if (!isSessionItem) {
      return formatSecondsAsClock(0);
    }
    let seconds = this.sessionElapsedSeconds;
    const limitSeconds = this.getAutoStopDisplayLimitSeconds();
    if (limitSeconds > 0 && seconds >= limitSeconds) {
      seconds = limitSeconds;
    }
    return formatSecondsAsClock(seconds);
  }

  private getAutoStopDisplayLimitSeconds(): number {
    const view = this.runningSessionView;
    if (view === null || view.itemId !== this.item.id) {
      return 0;
    }
    const snapshot = getAutoStopRunningSnapshotFromAppStorage();
    if (!snapshot || !snapshot.enabledAtStart || snapshot.limitSeconds <= 0) {
      return 0;
    }
    if (!doesAutoStopRunningSnapshotMatch(snapshot, view.itemId, view.recordId, view.startTime)) {
      return 0;
    }
    return snapshot.limitSeconds;
  }

  private getRunningTimerFontColor(): ResourceColor {
    const session = this.runningSessionView;
    const sessionColor = session !== null && session.itemId === this.item.id ? session.color : '';
    return sessionColor !== '' ? sessionColor : $r('app.color.text_secondary');
  }

  async startTimer() {
    const snapshot = await this.manager.start(this.item);
    if (!snapshot) {
      return;
    }

    this.applySnapshot(snapshot);
    this.manager.startBackgroundTask(this.item, this.context);
    this.manager.consumeRestartBackgroundFlag(snapshot.itemId);
    this.updateCardVisualStates();

    hilog.info(0x0000, TAG, `开始计时成功: ${this.item.title}, 记录ID: ${snapshot.currentRecordId}`);
  }

  async continueTimer() {
    const snapshot = await this.manager.continue(this.item);
    if (!snapshot) {
      return;
    }

    this.applySnapshot(snapshot);
    this.manager.startBackgroundTask(this.item, this.context);
    this.manager.consumeRestartBackgroundFlag(snapshot.itemId);
    this.updateCardVisualStates();

    hilog.info(0x0000, TAG, `继续计时成功: ${this.item.title}, 记录ID: ${snapshot.currentRecordId}`);
  }

  async stopAndSave() {
    // Long-press path may set isRunning=false before stopAndSave runs, so
    // also consult the session view to decide whether the live view should be stopped.
    // Phase 4-5：全局键清理由 store 停止链路的投影单写承担，组件不再直写。
    const sessionOwnsThisItem = this.runningSessionView !== null && this.runningSessionView.itemId === this.item.id;
    const shouldStopLiveView = sessionOwnsThisItem || this.isRunning;

    // Always stop background task and progress animation to ensure local recording stops
    this.manager.stopBackgroundTask(this.item.id);
    this.manager.consumeRestartBackgroundFlag(this.item.id);
    this.resetProgressAnimation();
    if (shouldStopLiveView) {
      try {
        await liveViewController.stopLiveView();
      } catch (error) {
        hilog.error(0x0000, TAG, `stopAndSave stopLiveView failed item=${this.item.id}, error=${JSON.stringify(error)}`);
      }
    }

    try {
      const snapshot = await this.manager.stop(this.item);
      if (snapshot) {
        this.applySnapshot(snapshot);
        hilog.info(0x0000, TAG, `停止并保存计时成功: ${this.item.title}`);
      } else {
        // Sync failed, but local recording is already stopped
        // Reset local state to PAUSED to ensure UI consistency
        hilog.warn(0x0000, TAG, `停止计时同步失败，但本地已停止: ${this.item.title}`);
        this.isRunning = false;
        this.itemStatus = MatterStatus.PAUSED;
        this.item.status = MatterStatus.PAUSED;
        this.currentRecordId = '';
      }
    } catch (error) {
      // Even if an exception occurs, local recording is already stopped
      hilog.error(0x0000, TAG, `停止计时异常，但本地已停止: ${this.item.title}, ${JSON.stringify(error)}`);
      this.isRunning = false;
      this.itemStatus = MatterStatus.PAUSED;
      this.item.status = MatterStatus.PAUSED;
      this.currentRecordId = '';
    }

    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    this.updateCardVisualStates();
  }

  async aboutToAppear() {
    // Load comment from database on component appear
    await this.loadComment();
    this.isInitializing = true;
    try {
      hilog.info(0x0000, TAG, `组件初始化: ${this.item.title}`);
      this.resetProgressAnimation();
      this.itemStatus = this.item.status;
      this.itemDurationInMilliseconds = this.item.durationInMilliseconds;

      const snapshot = await this.manager.initialize(this.item);
      this.applySnapshot(snapshot);

      if (this.expanded) {
        void this.refreshCoverImageBackground();
      }

      if (snapshot.isRunning) {
        if (snapshot.restartBackgroundTask) {
          this.manager.startBackgroundTask(this.item, this.context);
          this.manager.consumeRestartBackgroundFlag(this.item.id);
        }
      } else {
        this.manager.stopBackgroundTask(this.item.id);
        this.manager.consumeRestartBackgroundFlag(this.item.id);
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `组件初始化异常: ${JSON.stringify(error)}`);
      this.manager.stopBackgroundTask(this.item.id);
      this.manager.consumeRestartBackgroundFlag(this.item.id);
      const resetSnapshot = this.copySnapshot(EMPTY_SNAPSHOT);
      resetSnapshot.itemId = this.item.id;
      this.applySnapshot(resetSnapshot);
    }
    this.updateCardVisualStates();
    this.isInitializing = false;
  }
  private onExpandedChanged(): void {
    hilog.info(0x0000, TAG,
      `ColorProcess onExpandedChanged expanded=${this.expanded} activityId=${this.item.id} coverImageLocalPath=${this.coverImageLocalPath ?? 'null'} isPreloading=${this.isPreloading}`);
    this.resetButtonGlowStates();
    if (this.expanded) {
      // 展开时，取消预加载定时器，确保封面图片已加载
      this.cancelPreload();
      // 如果已经预加载了封面图片，则跳过加载步骤
      const skipLoad = this.coverImageLocalPath !== null;
      void this.processCoverImageForBackground(skipLoad);
    } else  {
      // 折叠时提示保存，保留封面图片路径用于下次预加载
      this.promptSaveDialog();
      this.cancelPreload();
    }
    this.updateCardVisualStates();
  }

  private get sandboxContext(): FilesDirCarrier {
    let abilityCtx: common.UIAbilityContext | null = null;
    try {
      abilityCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const filesDir = abilityCtx?.filesDir;
      if (typeof filesDir === 'string' && filesDir.trim().length > 0) {
        hilog.info(0x0000, TAG, 'PhotoPicker get context' + filesDir);
        return { filesDir };
      }
    } catch (_err) {
      abilityCtx = null;
      // ignore and fallback below
    }

    hilog.error(0x0000, TAG, 'PhotoPick sandboxContext failed to resolve filesDir from UIAbilityContext host context');
    return {};
  }

  private async loadCoverImage(): Promise<void> {
    try {
      hilog.info(0x0000, TAG, `PhotoPick loadCoverImage start activityId=${this.item.id}`);
      const localPath = await RDBStoreUtil.getInstance().queryActivityCoverMediaLocalPath(this.item.id);
      hilog.info(0x0000, TAG,
        `PhotoPick loadCoverImage queried localPath=${localPath ?? 'null'} activityId=${this.item.id}`);
      this.coverImageLocalPath = localPath;
      if (!localPath) {
        this.coverImageUri = null;
        hilog.info(0x0000, TAG, `PhotoPick loadCoverImage no localPath activityId=${this.item.id}`);
        return;
      }
      const coverUri = relPathToImageUri(this.sandboxContext, localPath);
      this.coverImageUri = coverUri;
      hilog.info(0x0000, TAG,
        `PhotoPick loadCoverImage resolved imageUri=${coverUri ?? 'null'} relPath=${localPath} activityId=${this.item.id}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `PhotoPick loadCoverImage failed activityId=${this.item.id}: ${JSON.stringify(error)}`);
      this.coverImageUri = null;
      this.coverImageLocalPath = null;
    }
  }

  private async refreshCoverImageBackground(): Promise<void> {
    await this.loadCoverImage();
  }

  /**
   * 轻量级预加载 - 并行加载封面图片与评论
   * 用于按下卡片时的预加载，当用户确实展开时无需等待
   */
  private async preloadBackground(): Promise<void> {
    if (this.isPreloading || this.expanded) {
      hilog.info(0x0000, TAG, `PreloadBackground skipped: isPreloading=${this.isPreloading} expanded=${this.expanded} activityId=${this.item.id}`);
      return;
    }

    this.isPreloading = true;
    hilog.info(0x0000, TAG, `PreloadBackground start activityId=${this.item.id} commentLoaded=${this.commentLoaded}`);

    try {
      // 封面图片 + 评论 并行加载
      await Promise.all([
        this.loadCoverImage(),
        this.loadCommentIfNeeded(),
      ]);
      hilog.info(0x0000, TAG, `PreloadBackground completed activityId=${this.item.id} coverImageLocalPath=${this.coverImageLocalPath ?? 'null'} commentLoaded=${this.commentLoaded}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `PreloadBackground failed activityId=${this.item.id}: ${JSON.stringify(error)}`);
    } finally {
      this.isPreloading = false;
    }
  }

  /**
   * 取消预加载
   */
  private cancelPreload(): void {
    if (this.preloadTimer !== -1) {
      clearTimeout(this.preloadTimer);
      this.preloadTimer = -1;
      hilog.info(0x0000, TAG, `PreloadBackground cancelled activityId=${this.item.id}`);
    }
    this.isPreloading = false;
  }

  /**
   * 处理封面图片背景（已移除模糊像素计算）
   * @param skipLoad 如果为 true，跳过 loadCoverImage（用于预加载场景）
   */
  private async processCoverImageForBackground(skipLoad: boolean = false): Promise<void> {
    if (!skipLoad) {
      await this.loadCoverImage();
    }
  }

  private async openPhotoPicker(): Promise<void> {
    if (this.isSavingCoverImage) {
      hilog.warn(0x0000, TAG, `PhotoPick openPhotoPicker ignored: already saving activityId=${this.item.id}`);
      return;
    }

    hilog.info(0x0000, TAG, `PhotoPick openPhotoPicker activityId=${this.item.id} expanded=${this.expanded}`);

    let pickedUri: string | null = null;
    if (!pickedUri) {
      try {
        pickedUri = await pickSingleImageUri({
          isSearchSupported: true,
          isPhotoTakingSupported: true
        });
      } catch (error) {
        hilog.error(0x0000, TAG, `PhotoPick openPhotoPicker failed: ${JSON.stringify(error)}`);
        promptAction.openToast({ message: '打开相册失败', duration: 1200 });
        return;
      }
    }

    if (!pickedUri) {
      hilog.info(0x0000, TAG, `PhotoPick openPhotoPicker cancelled activityId=${this.item.id}`);
      return;
    }

    this.isSavingCoverImage = true;
    try {
      hilog.info(0x0000, TAG, `PhotoPick save cover start activityId=${this.item.id} uri=${pickedUri}`);
      const result = await todayActivityService.replaceActivityCoverImage(this.item.id, pickedUri, this.sandboxContext);
      if (!result) {
        hilog.error(0x0000, TAG,
          `PhotoPick save cover failed: replaceActivityCoverImage returned null activityId=${this.item.id}`);
        promptAction.openToast({ message: '保存图片失败', duration: 1200 });
        return;
      }
      this.coverImageLocalPath = result.relPath;
      this.coverImageUri = result.imageUri;
      hilog.info(0x0000, TAG,
        `PhotoPick save cover success activityId=${this.item.id} relPath=${result.relPath} imageUri=${result.imageUri}`);
      // 更新封面图片背景
      void this.processCoverImageForBackground(true);
    } finally {
      this.isSavingCoverImage = false;
    }
  }

  async onAppForegroundStateChanged() {
    try {
      hilog.info(
        0x0000,
        TAG,
        `${BACKGROUND_TASK_LOG_PREFIX}: ui foreground change itemId=${this.item.id} appInForeground=${this.appInForeground} localRunning=${this.isRunning}`
      );
      const snapshot = await this.manager.handleForegroundChange(this.item, this.appInForeground);
      hilog.info(
        0x0000,
        TAG,
        `${BACKGROUND_TASK_LOG_PREFIX}: ui foreground snapshot itemId=${this.item.id} snapshotRunning=${snapshot.isRunning} restartBackground=${snapshot.restartBackgroundTask} recordId=${snapshot.currentRecordId}`
      );
      this.applySnapshot(snapshot);
      if (this.appInForeground && snapshot.isRunning && snapshot.restartBackgroundTask) {
        hilog.info(0x0000, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ui foreground restarting background task itemId=${this.item.id}`);
        this.manager.startBackgroundTask(this.item, this.context);
        this.manager.consumeRestartBackgroundFlag(this.item.id);
      }
      this.updateCardVisualStates();
    } catch (error) {
      hilog.error(0x0000, TAG, `onAppForegroundStateChanged异常: ${this.item.title}, ${JSON.stringify(error)}`);
    }
  }

  private onPageVisibilityGateChanged(): void {
    this.updateCardVisualStates();
  }

  private onThemeChanged(): void {
    this.updateCardVisualStates();
  }

  private onItemStatusChanged(): void {
    this.resetButtonGlowStates();
    this.updateCardVisualStates();
  }

  /**
   * 会话视图变化（身份键 recordId:phase 变更/清空）时的唯一反应式触发：
   * 覆盖跨设备同步、恢复、自动停止等一切会话变化。
   */
  private onRunningSessionViewChanged(): void {
    void this.checkAndUpdateRunningState();
  }

  /**
   * Check if this item should be in RECORDING state based on global running state.
   * Updates local state and starts/stops timer accordingly.
   */
  private async checkAndUpdateRunningState(): Promise<void> {
    // Skip during initialization to avoid race conditions with aboutToAppear
    if (this.isInitializing) {
      hilog.info(0x0000, TAG, `Sync Matter Status: checkAndUpdateRunningState skipped (initializing) item=${this.item.id}`);
      return;
    }
    if (this.isStoppingFromLongPress) {
      hilog.info(0x0000, TAG, `Sync Matter Status: checkAndUpdateRunningState skipped (stoppingFromLongPress) item=${this.item.id}`);
      return;
    }

    const isThisItemRunning = this.runningSessionView !== null && this.runningSessionView.itemId === this.item.id;
    const syncVersion = ++this.runningStateSyncVersion;

    hilog.info(0x0000, TAG,
      `Sync Matter Status: checkAndUpdateRunningState item=${this.item.id} viewItem=${this.runningSessionView ? this.runningSessionView.itemId : ''} isThisItemRunning=${isThisItemRunning} localIsRunning=${this.isRunning} localStatus=${this.itemStatus}`);

    if (isThisItemRunning && !this.isRunning) {
      // Reconcile from manager first so the visual timer never starts from stale local state.
      hilog.info(0x0000, TAG, `Sync Matter Status: reconciling running snapshot for item=${this.item.id}`);
      const snapshot = await this.manager.refreshItemState(this.item.id);
      if (syncVersion !== this.runningStateSyncVersion) {
        hilog.info(0x0000, TAG, `Sync Matter Status: stale running sync ignored item=${this.item.id}`);
        return;
      }
      if (!snapshot || !snapshot.isRunning) {
        hilog.warn(0x0000, TAG,
          `Sync Matter Status: running signal rejected after refresh item=${this.item.id}, snapshotRunning=${snapshot?.isRunning ?? false}`);
        this.updateCardVisualStates();
        return;
      }

      this.applySnapshot(snapshot);
      this.manager.startBackgroundTask(this.item, this.context);
      this.manager.consumeRestartBackgroundFlag(this.item.id);
      void (async () => {
        try {
          await liveViewController.startLiveView(0, this.item.title);
        } catch (error) {
          hilog.error(0x0000, TAG, `Sync Matter Status: failed to start live view on sync start: ${JSON.stringify(error)}`);
        }
      })();
      this.updateCardVisualStates();
    } else if (!isThisItemRunning && this.isRunning) {
      hilog.info(0x0000, TAG, `Sync Matter Status: applying local stop finalization for item=${this.item.id}`);
      if (syncVersion !== this.runningStateSyncVersion) {
        hilog.info(0x0000, TAG, `Sync Matter Status: stale stop sync ignored item=${this.item.id}`);
        return;
      }

      const stoppedSnapshot = this.copySnapshot(this.runtimeState);
      stoppedSnapshot.status = MatterStatus.PAUSED;
      stoppedSnapshot.isRunning = false;
      stoppedSnapshot.currentRecordId = '';
      stoppedSnapshot.record = undefined;
      stoppedSnapshot.restartBackgroundTask = false;
      stoppedSnapshot.lastKnownStartTime = 0;
      this.applySnapshot(stoppedSnapshot);
      this.manager.stopBackgroundTask(this.item.id);
      this.manager.consumeRestartBackgroundFlag(this.item.id);
      this.resetProgressAnimation();
      this.updateCardVisualStates();
    }
  }

  private updateCardVisualStates(): void {
    this.showRecordingBorder = this.shouldShowRunningCardGlow();
    this.updateBorderEffect();
  }

  private shouldShowRunningCardGlow(): boolean {
    return this.itemStatus === MatterStatus.RECORDING && this.shouldAnimateRunningEffects();
  }

  private updateBorderEffect(): void {
    const showRunningGlow: boolean = this.shouldShowRunningCardGlow();
    const showTouchGlow: boolean = !showRunningGlow && this.isCardTouchActive;
    this.borderEffect = buildPointLightEffect({
      preset: showRunningGlow ? 'cardActive' : 'cardTouch',
      color: showRunningGlow ? $r('app.color.immersive_glow_recording') : $r('app.color.immersive_glow_primary'),
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      isActive: showRunningGlow || showTouchGlow,
      isDarkTheme: this.isDarkTheme,
      overrides: {
        height: showRunningGlow ? MatterItem.CARD_RECORDING_LIGHT_HEIGHT : MatterItem.CARD_TOUCH_LIGHT_HEIGHT
      }
    });
  }

  private getActionButtonGlowColor(): ResourceColor {
    if (this.itemStatus === MatterStatus.RECORDING) {
      return $r('app.color.immersive_glow_error');
    }
    if (this.itemStatus === MatterStatus.PAUSED) {
      return $r('app.color.immersive_glow_warning');
    }
    return $r('app.color.immersive_glow_primary');
  }

  private getButtonGlowEffect(): VisualEffect {
    return buildPointLightEffect({
      preset: 'buttonTouch',
      color: this.getActionButtonGlowColor(),
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
      isActive: this.isButtonGlowActive,
      isDarkTheme: this.isDarkTheme,
      overrides: {
        height: MatterItem.BUTTON_TOUCH_LIGHT_HEIGHT
      }
    });
  }

  private getExpandedActionButtonGlowEffect(): VisualEffect {
    return buildPointLightEffect({
      preset: 'buttonTouch',
      color: this.getActionButtonGlowColor(),
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
      isActive: this.isExpandedActionButtonGlowActive,
      isDarkTheme: this.isDarkTheme,
      overrides: {
        height: MatterItem.BUTTON_TOUCH_LIGHT_HEIGHT
      }
    });
  }

  private getExpandedSaveButtonGlowEffect(): VisualEffect {
    return buildPointLightEffect({
      preset: 'buttonTouch',
      color: $r('app.color.immersive_glow_primary'),
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
      isActive: this.isExpandedSaveButtonGlowActive,
      isDarkTheme: this.isDarkTheme,
      overrides: {
        height: MatterItem.BUTTON_TOUCH_LIGHT_HEIGHT
      }
    });
  }

  private setButtonGlowActive(active: boolean): void {
    this.isButtonGlowActive = active;
  }

  private setExpandedActionButtonGlowActive(active: boolean): void {
    this.isExpandedActionButtonGlowActive = active;
  }

  private setExpandedSaveButtonGlowActive(active: boolean): void {
    this.isExpandedSaveButtonGlowActive = active;
  }

  private resetButtonGlowStates(): void {
    this.setButtonGlowActive(false);
    this.setExpandedActionButtonGlowActive(false);
    this.setExpandedSaveButtonGlowActive(false);
    this.activeButtonGlowTarget = null;
    this.activeButtonGlowBounds = null;
  }

  private getPrimaryTouch(event: TouchEvent): TouchObject | undefined {
    if (event.changedTouches.length > 0) {
      return event.changedTouches[0];
    }
    if (event.touches.length > 0) {
      return event.touches[0];
    }
    return undefined;
  }

  private getLengthNumber(length: Length | undefined): number | null {
    if (typeof length === 'number') {
      return length;
    }
    if (typeof length === 'string') {
      const parsed = Number.parseFloat(length);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  }

  private updateActiveButtonGlowBounds(event: TouchEvent, target: ButtonGlowTarget): boolean {
    const width = this.getLengthNumber(event.target.area.width);
    const height = this.getLengthNumber(event.target.area.height);
    const left = this.getLengthNumber(event.target.area.globalPosition.x);
    const top = this.getLengthNumber(event.target.area.globalPosition.y);
    if (target === null || width === null || height === null || left === null || top === null) {
      this.activeButtonGlowTarget = null;
      this.activeButtonGlowBounds = null;
      return false;
    }
    this.activeButtonGlowTarget = target;
    this.activeButtonGlowBounds = {
      left: left,
      top: top,
      right: left + width,
      bottom: top + height
    };
    return true;
  }

  private isTouchInsideActiveButton(event: TouchEvent): boolean {
    if (this.activeButtonGlowBounds === null) {
      return false;
    }
    const touch = this.getPrimaryTouch(event);
    if (!touch) {
      return false;
    }
    const touchX = touch.windowX;
    const touchY = touch.windowY;
    return touchX >= this.activeButtonGlowBounds.left
      && touchX <= this.activeButtonGlowBounds.right
      && touchY >= this.activeButtonGlowBounds.top
      && touchY <= this.activeButtonGlowBounds.bottom;
  }

  private syncActiveButtonGlowWithTouch(event: TouchEvent): void {
    if (this.activeButtonGlowTarget === null) {
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.resetButtonGlowStates();
      return;
    }
    if (event.type !== TouchType.Move || this.isTouchInsideActiveButton(event)) {
      return;
    }
    switch (this.activeButtonGlowTarget) {
      case 'collapsed':
        this.setButtonGlowActive(false);
        break;
      case 'expandedAction':
        this.setExpandedActionButtonGlowActive(false);
        break;
      case 'expandedSave':
        this.setExpandedSaveButtonGlowActive(false);
        break;
      default:
        break;
    }
    this.activeButtonGlowTarget = null;
    this.activeButtonGlowBounds = null;
  }

  private handleButtonTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.updateActiveButtonGlowBounds(event, 'collapsed');
      this.setButtonGlowActive(true);
    } else if (event.type === TouchType.Move) {
      if (!this.isTouchInsideActiveButton(event)) {
        this.setButtonGlowActive(false);
        if (this.activeButtonGlowTarget === 'collapsed') {
          this.activeButtonGlowTarget = null;
          this.activeButtonGlowBounds = null;
        }
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.setButtonGlowActive(false);
      if (this.activeButtonGlowTarget === 'collapsed') {
        this.activeButtonGlowTarget = null;
        this.activeButtonGlowBounds = null;
      }
    }
  }

  private handleExpandedActionButtonTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.updateActiveButtonGlowBounds(event, 'expandedAction');
      this.setExpandedActionButtonGlowActive(true);
    } else if (event.type === TouchType.Move) {
      if (!this.isTouchInsideActiveButton(event)) {
        this.setExpandedActionButtonGlowActive(false);
        if (this.activeButtonGlowTarget === 'expandedAction') {
          this.activeButtonGlowTarget = null;
          this.activeButtonGlowBounds = null;
        }
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.setExpandedActionButtonGlowActive(false);
      if (this.activeButtonGlowTarget === 'expandedAction') {
        this.activeButtonGlowTarget = null;
        this.activeButtonGlowBounds = null;
      }
    }
  }

  private handleExpandedSaveButtonTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.updateActiveButtonGlowBounds(event, 'expandedSave');
      this.setExpandedSaveButtonGlowActive(true);
    } else if (event.type === TouchType.Move) {
      if (!this.isTouchInsideActiveButton(event)) {
        this.setExpandedSaveButtonGlowActive(false);
        if (this.activeButtonGlowTarget === 'expandedSave') {
          this.activeButtonGlowTarget = null;
          this.activeButtonGlowBounds = null;
        }
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.setExpandedSaveButtonGlowActive(false);
      if (this.activeButtonGlowTarget === 'expandedSave') {
        this.activeButtonGlowTarget = null;
        this.activeButtonGlowBounds = null;
      }
    }
  }

  private handleCardTouchState(active: boolean): void {
    if (this.isCardTouchActive === active) {
      return;
    }
    this.isCardTouchActive = active;
    this.updateCardVisualStates();
  }

  private getCardBaseBackground(): string | ResourceColor {
    if (this.isDarkTheme) {
      return $r('app.color.matter_card_fill');
    }
    return $r('app.color.matter_card_fill');
  }

  build() {
    if (canIUse("SystemCapability.UIDesign.HDSComponent.Core")) {
      this.buildUnifiedLayout();
    } else {
      // 兼容模式 - 空布局
    }
  }

  /**
   * 统一布局 - 根据 expanded 状态动态渲染
   * 在同一个组件结构中，使用条件表达式控制属性值，实现更丝滑的过渡动画
   * 参考 IdeaCardNode 的设计模式
   */
  @Builder
  private buildUnifiedLayout() {
    Column({ space: this.expanded ? 24 : 0 }) {
      // 主内容区域 - Row 包含标题/标签和操作区域
      Row() {
        // 左侧/上方：标题和标签
        Column({ space: this.expanded ? 8 : 4 }) {
          // 标题
          if (this.expanded) {
            Text(this.item.title)
              .fontWeight(700)
              .fontSize(30)
              .maxLines(2)
              .textAlign(TextAlign.Center)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .transition(createExpandedEntryTransition(54, 85, 0.88))
          } else {
            Text(this.item.title)
              .fontWeight(600)
              .fontSize(18)
              .maxLines(1)
              .textAlign(TextAlign.Start)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          // 展开态的时间显示
          if (this.expanded) {
            Column() {
              this.buildExpandedDuration()
            }
            .transition(createExpandedEntryTransition(46, 90, 0.9))
          }

          // 标签行
          if (this.expanded) {
            Row({ space: 8 }) {
              Row()
                .width(7)
                .height(7)
                .borderRadius('50%')
                .backgroundColor(this.item.labelColor)
              Text(this.item.label)
                .fontSize(12)
                .fontWeight(500)
                .fontColor($r('app.color.text_secondary'))
            }
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.bg_main'))
            .borderRadius(14)
            .alignItems(VerticalAlign.Center)
            .transition(createExpandedEntryTransition(30, 150, 0.92))
          } else {
            Row({ space: 6 }) {
              Row()
                .width(7)
                .height(7)
                .borderRadius('50%')
                .backgroundColor(this.item.labelColor)
              Text(this.item.label)
                .fontSize(12)
                .fontWeight(400)
                .fontColor($r('app.color.text_secondary'))
            }
            .padding(0)
            .backgroundColor(Color.Transparent)
            .borderRadius(0)
            .alignItems(VerticalAlign.Center)
          }
        }
        .width('100%')
        .alignItems(this.expanded ? HorizontalAlign.Center : HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)
        .flexGrow(1)
        .flexShrink(this.expanded ? 0 : 1)
        .height(this.expanded ? undefined : 45)

        // 折叠态的操作区域（展开态隐藏）
        if (!this.expanded) {
          this.buildActionRow()
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(this.expanded ? VerticalAlign.Top : VerticalAlign.Center)
      .padding(this.expanded ? { top: 32 } : 0)

      // 展开态的图片和感受记录区域
      if (this.expanded) {
        Column() {
          Stack({ alignContent: Alignment.Center }) {
            if (this.coverImageUri) {
              Image(this.coverImageUri)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            }
            if (!this.coverImageUri) {
              Row() {
                Text('添加图片')
                  .fontSize(14)
                  .fontWeight(500)
                  .fontColor($r('app.color.text_disabled'))
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(12)
              .backgroundColor(Color.Transparent)
              .align(Alignment.Center)
            }

          }
          .width('100%')
          .height('75%')
          .backgroundColor($r('app.color.neutral_100'))
          .borderRadius(16)
          .clip(true)
          .onClick(() => {
            void this.openPhotoPicker();
          })

          Column() {
            TextArea({ placeholder: '记录此刻的感受...', text: this.comment })
              .placeholderFont({
                weight: 500,
                size: 16,
              })
              .onAppear(() => {
                hilog.info(0x0000, TAG, `TextArea onAppear activityId=${this.item.id} commentLoaded=${this.commentLoaded} commentLength=${this.comment.length} commentContent="${this.comment}"`);
              })
              .onChange((value: string) => {
                this.updateCommentState(value);
              })
              // .onEditChange((isEditing: boolean) => {
              //   if (!isEditing) {
              //     this.promptSaveDialog();
              //   }
              // })
              .maxLines(4)
              .placeholderColor($r('app.color.text_tertiary'))
              .fontSize(16)
              .fontWeight(500)
              .fontColor($r('app.color.neutral_800'))
              .textAlign(TextAlign.Center)
              .backgroundColor($r('app.color.bg_card'))
              .width('100%')
              .height('100%')
          }
          .padding({ top: 5 })
          .width('100%')
          .height('25%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(16)
        }
        .rotate({
          angle: 3,       // 设置为正数，即向右（顺时针）旋转 15 度
          centerX: '50%',  // 旋转中心点 X轴：50% 代表组件中心（如果不写默认为50%）
          centerY: '50%'   // 旋转中心点 Y轴：50% 代表组件中心
        })
        .padding(10)
        .width(new BreakpointType<Dimension>({ sm: '90%', md: 340, lg: 340 }).getValue(this.currentBreakpoint))
        .height(280)
        .borderRadius(26)
        .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : {
          radius: 50,
          offsetX: 0,
          offsetY: 8,
          color: 'rgba(31, 35, 38, 0.2)' // Slightly darker to enhance the lift effect
        })
        .backgroundColor(this.getCardBaseBackground())
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 100 }))
            .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION, delay: 150 }),
          undefined)
        )
      }

      // 展开态的操作按钮
      if (this.expanded) {
        this.buildExpandedActionButton()

      }
    }
    .onAppear(() => {
      this.refreshCoverImageBackground();
    })
    .clickEffect(this.expanded ? { level: ClickEffectLevel.HEAVY, scale: 1 } : { level: ClickEffectLevel.HEAVY, scale: .9 })
    .width('100%')
    .height('100%')
    .alignItems(this.expanded ? HorizontalAlign.Center : HorizontalAlign.Start)
    .justifyContent(this.expanded ? FlexAlign.SpaceBetween : FlexAlign.Center)
    .padding(this.expanded
      ? { left: this.getCardPadding(), right: this.getCardPadding(), top: 24, bottom: 32 }
      : this.getCardPadding())
    .borderRadius(this.expanded ? EXPANDED_CARD_RADIUS : 15)
    .backgroundColor(this.expanded ? this.getCardBaseBackground() : this.getCardFillColor())
    .backgroundImage(this.expanded ? this.coverImageUri : null)
    .backgroundImageSize(ImageSize.Cover)
    .backgroundBlurStyle(this.expanded && this.coverImageUri ? BlurStyle.COMPONENT_THIN : BlurStyle.NONE)
    .border({
      width: this.showRecordingBorder ? $r('app.float.matter_card_recording_border_width_active') :
        $r('app.float.matter_card_recording_border_width_inactive'),
      color: $r('app.color.immersive_glow_primary')
    })
    .visualEffect(this.borderEffect)
    .onTouch((event: TouchEvent) => {
      this.syncActiveButtonGlowWithTouch(event);
      if (event.type === TouchType.Down) {
        this.handleCardTouchState(true);
        // 智能预加载策略
        if (!this.expanded) {
          // 记录触摸开始时间
          this.preloadTouchStartTime = Date.now();

          // 延迟预加载，避免误触
          if (this.preloadTimer !== -1) {
            clearTimeout(this.preloadTimer);
          }
          this.preloadTimer = setTimeout(() => {
            // 延迟后开始轻量级预加载（仅加载图片，不处理）
            void this.preloadBackground();
            this.preloadTimer = -1;
          }, MatterItem.PRELOAD_DELAY_MS);
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.handleCardTouchState(false);

        if (!this.expanded) {
          // 计算触摸持续时间
          const touchDuration = Date.now() - this.preloadTouchStartTime;

          // 如果触摸时间非常短（< 30ms），认为是误触，立即取消预加载
          if (touchDuration < 30) {
            this.cancelPreload();
            hilog.info(0x0000, TAG, `PreloadBackground cancelled due to short touch (${touchDuration}ms) activityId=${this.item.id}`);
          }
          // 如果触摸时间较长，说明用户可能真的要展开，让预加载继续进行
        }
      }
    })
    .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE)
  }

  @Builder
  private buildExpandedDuration() {
    if (this.itemStatus === MatterStatus.RECORDING) {
      Text(this.buildRunningDurationText())
        .fontSize(55)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    } else {
      Text(TimeRecordUtil.formatDuration(this.itemDurationInMilliseconds))
        .fontSize(55)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    }
  }

  /**
   * 状态文字区域 - 显示计时信息或已记录时间
   * 仅在折叠态显示，保持原有布局和 breakpoint 适配
   */
  @Builder
  private buildStatusText() {
    if (this.itemStatus === MatterStatus.RECORDING) {
      Column() {
        Text("正在计时...")
          .fontColor($r('app.color.text_secondary'))
          .fontSize(14)
          .fontWeight(500)
        Text(this.buildRunningDurationText())
          .fontSize(18)
          .fontWeight(700)
          .fontColor(this.getRunningTimerFontColor())
      }
      .height(45)
      .width(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? '100%' : null)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
    } else if (this.itemStatus === MatterStatus.PAUSED) {
      Column() {
        Text(`已记录:  `)
          .fontSize($r('app.float.item_recorded_font_size'))
          .fontColor($r('app.color.text_tertiary'))
          .fontWeight(500)
        Text(TimeRecordUtil.formatTime(this.itemDurationInMilliseconds))
          .fontSize(18)
          .fontWeight(700)
          .fontColor($r('app.color.text_secondary'))
          .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION })
      }
      .height(45)
      .width(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? '100%' : null)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
    }
  }

  /**
   * 折叠态的操作按钮 - Capsule 型
   * 保持原有的小尺寸 Capsule 设计，响应式 breakpoint 适配
   */
  @Builder
  private buildCollapsedActionButton() {
    if (this.itemStatus === MatterStatus.TODO) {
      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontColor([$r('app.color.primary')])
          .fontWeight(700)
          .fontSize(20)
      }
      .visualEffect(this.getButtonGlowEffect())
      .onClick(async () => {
        await this.startTimer();
        await liveViewController.startLiveView(0, this.item.title);
        this.updateCardVisualStates();
      })
      .onTouch((event: TouchEvent) => {
        this.handleButtonTouch(event);
      })
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
      .width(this.getActionButtonWidth())
      .height(this.getActionButtonHeight())
      .backgroundColor(this.getSecondaryButtonBackground())
      .shadow(AppShadows.CARD_RESTING)
      .transition(this.buttonEffect)
    } else if (this.itemStatus === MatterStatus.RECORDING) {
      Stack() {
        Progress({ value: this.progressValue, total: 100, type: ProgressType.Ring })
          .color($r('app.color.warning'))
          .width(60)
          .height(this.getRecordingProgressHeight())
          .style({ strokeWidth: 5, enableSmoothEffect: true })
          .backgroundColor(Color.Transparent)
        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.pause'))
            .fontColor([$r('app.color.neutral_100')])
            .fontWeight(700)
            .fontSize(20)
        }
        .visualEffect(this.getButtonGlowEffect())
        .onTouch((event: TouchEvent) => {
          this.handleButtonTouch(event);
        })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.6 })
        .width(this.getActionButtonWidth())
        .height(this.getActionButtonHeight())
        .backgroundColor($r('app.color.error'))
        .shadow({ color: $r('app.color.error'), radius: 20 })
        .gesture(
          LongPressGesture({ repeat: true, duration: 10 })
            .onAction(async (event: GestureEvent | undefined) => {
              await this.onPauseLongPressAction(event);
            })
            .onActionEnd(() => {
              this.onPauseLongPressEnd();
            })
        )
      }
      .transition(this.buttonEffect)
    } else if (this.itemStatus === MatterStatus.PAUSED) {
      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontColor([$r('app.color.primary')])
          .fontWeight(700)
          .fontSize(20)
      }
      .visualEffect(this.getButtonGlowEffect())
      .onTouch((event: TouchEvent) => {
        this.handleButtonTouch(event);
      })
      .onClick(async () => {
        if (this.isStoppingFromLongPress) {
          return;
        }
        await this.continueTimer();
        await liveViewController.startLiveView(0, this.item.title);
        this.updateCardVisualStates();
      })
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
      .width(this.getActionButtonWidth())
      .height(this.getActionButtonHeight())
      .backgroundColor(this.getSecondaryButtonBackground())
      .shadow(AppShadows.CARD_RESTING)
      .transition(this.buttonEffect)
    }
  }

  /**
   * 展开态的操作按钮区域 - Circle 型大按钮
   * 根据状态渲染不同按钮，通过 expanded 条件控制渲染
   */
  @Builder
  private buildExpandedActionButton() {
    Row({space: 12 }) {
      if (this.itemStatus === MatterStatus.RECORDING) {
        Stack() {
          Progress({ value: this.progressValue, total: 100, type: ProgressType.Ring })
            .color($r('app.color.warning'))
            .width(50)
            .height(50)
            .style({ strokeWidth: 5, enableSmoothEffect: true })
            .backgroundColor(Color.Transparent)
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.pause'))
              .fontColor([$r('app.color.neutral_100')])
              .fontWeight(600)
              .fontSize(20)
          }
          .width(40)
          .height(40)
          .visualEffect(this.getExpandedActionButtonGlowEffect())
          .onTouch((event: TouchEvent) => {
            this.handleExpandedActionButtonTouch(event);
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.6 })
          .backgroundColor($r('app.color.error'))
          .shadow({ color: $r('app.color.error'), radius: 20 })
          .gesture(
            LongPressGesture({ repeat: true, duration: 10 })
              .onAction(async (event: GestureEvent | undefined) => {
                await this.onPauseLongPressAction(event);
              })
              .onActionEnd(() => {
                this.onPauseLongPressEnd();
              })
          )
        }
        .width(40)
        .height(40)
      } else if (this.itemStatus === MatterStatus.PAUSED) {
        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontColor([$r('app.color.primary')])
            .fontWeight(600)
            .fontSize(20)
        }
        .visualEffect(this.getExpandedActionButtonGlowEffect())
        .onTouch((event: TouchEvent) => {
          this.handleExpandedActionButtonTouch(event);
        })
        .onClick(async () => {
          if (this.isStoppingFromLongPress) {
            return;
          }
          await this.continueTimer();
          await liveViewController.startLiveView(0, this.item.title);
        })
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.matter_card_secondary_button_bg'))
        .shadow(AppShadows.CARD_RESTING)
      }

      Button() {
        SymbolGlyph($r('sys.symbol.save'))
          .fontColor([this.commentDirty && !this.isSavingComment ? $r('app.color.primary') : $r('app.color.text_disabled')])
          .fontWeight(600)
          .fontSize(20)
      }
        .type(ButtonType.Circle)
      .visualEffect(this.getExpandedSaveButtonGlowEffect())
      .onTouch((event: TouchEvent) => {
        this.handleExpandedSaveButtonTouch(event);
      })
        .onClick(() => {
          if (this.isSavingComment) {
            return;
          }
          if (!this.commentDirty) {
            promptAction.openToast({ message: $r('app.string.today_comment_no_save'), duration: 1200 });
            return;
          }
          void this.saveCommentNow();
        })
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.8 })
        .width(40)
        .height(40)
        .backgroundColor(this.commentDirty && !this.isSavingComment
          ? $r('app.color.matter_card_secondary_button_bg')
          : $r('app.color.neutral_200'))
        .shadow(AppShadows.CARD_RESTING)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 200 }))
        .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION, delay: 250 }),
      undefined)
    )
  }

  /**
   * 折叠态的操作区域 - 文字（仅 RECORDING/PAUSED）+ 按钮
   * 使用 buildCollapsedActionButton，仅在折叠态渲染
   */
  @Builder
  private buildActionRow() {
    Row({ space: this.getTextActionSpacing() }) {
      // 文字区域（仅 RECORDING 和 PAUSED 状态显示）
      if (this.itemStatus === MatterStatus.RECORDING || this.itemStatus === MatterStatus.PAUSED) {
        Column() {
          this.buildStatusText()
        }
        .transition(this.buttonEffect)
        .alignItems(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? HorizontalAlign.Start : HorizontalAlign.End)
        .justifyContent(FlexAlign.Center)
        .height(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 45 : null)
        .width(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 120 : null)
        .flexGrow(0)
        .flexShrink(1)
        .transition(this.buttonEffect)
      }

      // 折叠态按钮
      this.buildCollapsedActionButton()
    }
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .height(this.getActionAreaHeight())
    .flexShrink(0)
  }

  private getExpandedMetaLine(): string {
    if (this.itemStatus === MatterStatus.RECORDING) {
      return '计时进行中';
    }
    if (this.itemStatus === MatterStatus.TODO) {
      return '准备开始你的记录';
    }
    return '已暂停，可继续记录';
  }

  private getActionButtonWidth(): number {
    return new BreakpointType<number>({ sm: 56, md: 56, lg: 60 }).getValue(this.currentBreakpoint);
  }

  private getActionButtonHeight(): number {
    return new BreakpointType<number>({ sm: 38, md: 38, lg: 40 }).getValue(this.currentBreakpoint);
  }

  private getActionAreaHeight(): number {
    if (this.itemStatus === MatterStatus.RECORDING) {
      return this.getRecordingProgressHeight();
    }
    // Keep a baseline height for text blocks so they visually center with buttons
    return Math.max(this.getActionButtonHeight(), 45);
  }

  private getRecordingProgressHeight(): number {
    return new BreakpointType<number>({ sm: 90, md: 100, lg: 110 }).getValue(this.currentBreakpoint);
  }

  private getTextActionSpacing(): number {
    return new BreakpointType<number>({ sm: 6, md: 8, lg: 10 }).getValue(this.currentBreakpoint);
  }

  private getActionTextWidth(): number {
    return new BreakpointType<number>({ sm: 120, md: 60, lg: 70 }).getValue(this.currentBreakpoint);
  }

  private getCardPadding(): number {
    return new BreakpointType<number>({
      sm: 14,
      md: 16,
      lg: 20
    }).getValue(this.currentBreakpoint);
  }

  private getCardFillColor(): string | ResourceColor {
    return this.getCardBaseBackground();
  }

  private getSecondaryButtonBackground(): ResourceColor | string {
    return $r('app.color.matter_card_secondary_button_bg');
  }
}
