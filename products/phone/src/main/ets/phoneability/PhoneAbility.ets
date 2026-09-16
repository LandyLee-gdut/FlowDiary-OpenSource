import type { Configuration } from '@kit.AbilityKit';
import { AbilityConstant, ConfigurationConstant, EnvironmentCallback, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window, promptAction } from '@kit.ArkUI';
import { rpc } from '@kit.IPCKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { MatterStatus, PreferenceKeys, RDBStoreUtil, StorageKeys, PreferencesUtil, preferencesUtil, BreakpointConstants, tagService } from 'base';
import {
  todayActivityService,
  fanItemService,
  FanItemPayload,
  MatterItemStateManager,
  ensureAutoStopAppStorageDefaults,
  hydrateAutoStopSettings,
  getAutoStopRunningSnapshotFromAppStorage,
  doesAutoStopRunningSnapshotMatch,
  persistAutoStopRunningSnapshot,
  setupRecordingSession
} from 'today';
import { buildDefaultIdeaPoolSeedCollections } from 'ideapool';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { ResumeTimeRecord, liveViewController, LIVE_VIEW_STOP_EVENT } from 'today'
import { MatterItemModel, AppColors, ColorModeUtil, COLOR_MODE_STORAGE_KEY, COLOR_MODE_VERSION_KEY, recordingSessionStore } from 'base'
import dayjs from 'dayjs';
import { common } from '@kit.AbilityKit';
import { pushService } from '@kit.PushKit';
import { preferences } from '@kit.ArkData';
import { todayOverviewWidgetService } from '../todayoverview/model/TodayOverviewWidgetService';
import { todayRecordWidgetService } from '../todayrecordwidget/model/TodayRecordWidgetService';
import { todayTimerWidgetService } from '../todaytimerwidget/model/TodayTimerWidgetService';
import { tagDistributionWidgetService } from '../tagdistribution/model/TagDistributionWidgetService';
import { reflectTodayWidgetService } from '../reflecttoday/model/ReflectTodayWidgetService';
import { BackupScheduler } from '../backup/BackupScheduler';

const DOMAIN = 0x0000;
const TAG = 'PhoneAbility';
const WIDGET_ROUTER_TARGET_REFLECT: string = 'reflect';
const WIDGET_ROUTER_TARGET_TODAY: string = 'today';
const WIDGET_ROUTER_TARGET_IDEAPOOL: string = 'ideapool';
const WIDGET_TARGET_TAB_REFLECT: number = 0;
const WIDGET_TARGET_TAB_TODAY: number = 1;
const WIDGET_TARGET_TAB_IDEAPOOL: number = 2;
const WIDGET_CALL_METHOD_STOP_TIMER: string = 'stopTimer';
const WIDGET_ADD_SHEET_PREFILL_STORAGE_KEY: string = 'widgetAddSheetPrefillJson';
const WIDGET_ROUTER_SHORTCUT_ACTIVITY_KEY: string = 'shortcutActivityName';
const WIDGET_ROUTER_SHORTCUT_TAG_ID_KEY: string = 'shortcutTagId';
const WIDGET_ROUTER_SHORTCUT_AUTO_START_KEY: string = 'shortcutAutoStart';
const LIVE_VIEW_ROUTER_ACTION_KEY: string = 'liveViewAction';
const LIVE_VIEW_ROUTER_ACTION_STOP_TIMER: string = 'stopTimer';
const PHONE_UI_ABILITY_NAME: string = 'PhoneAbility';
const BACKGROUND_TASK_LOG_PREFIX: string = 'background task';

interface TodayAddSheetPrefill {
  activityName: string;
  tagId: string;
  autoStart: boolean;
}

class EmptyParcelable implements rpc.Parcelable {
  marshalling(messageSequence: rpc.MessageSequence): boolean {
    messageSequence.writeInt(0);
    return true;
  }

  unmarshalling(messageSequence: rpc.MessageSequence): boolean {
    messageSequence.readInt();
    return true;
  }
}

/**
 * 系统环境变化监听（ApplicationContext 'environment' 通道）。
 * 与 UIAbility.onConfigurationUpdate 互为补充：应用处于后台等场景下
 * onConfigurationUpdate 不一定送达，该通道能保证收到配色变化。
 */
class ColorModeEnvironmentCallback extends EnvironmentCallback {
  private readonly updateHandler: (config: Configuration) => void;

  constructor(updateHandler: (config: Configuration) => void) {
    super();
    this.updateHandler = updateHandler;
  }

  onConfigurationUpdated(config: Configuration): void {
    this.updateHandler(config);
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    // 只关心配色变化，内存等级忽略
  }
}

export default class PhoneAbility extends UIAbility {
  private windowObj?: window.Window;
  private timerWidgetListenerRegistered: boolean = false;
  private matterWidgetListenerRegistered: boolean = false;
  private widgetCallHandlersRegistered: boolean = false;
  private backupScheduler: BackupScheduler | null = null;
  private liveViewStopSubscriber: commonEventManager.CommonEventSubscriber | null = null;
  private recordingRuntimeReady: boolean = false;
  private pendingStopTimerAction: boolean = false;
  private stopTimerCommandInFlight: boolean = false;
  private colorModeEnvironmentCallbackId: number = -1;
  private readonly colorModeEnvironmentCallback: ColorModeEnvironmentCallback =
    new ColorModeEnvironmentCallback((config: Configuration): void => {
      this.updateColorMode(config?.colorMode);
    });

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    hilog.info(DOMAIN, TAG, 'databackup.PhoneAbility.onCreate');
    AppStorage.setOrCreate('context', this.context);
    AppStorage.setOrCreate(StorageKeys.PHONE_UI_ABILITY_NAME, PHONE_UI_ABILITY_NAME);
    ensureAutoStopAppStorageDefaults();
    AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_ENABLED, false);
    AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_RUN_AT, 0);
    AppStorage.setOrCreate(StorageKeys.AUTO_BACKUP_LAST_ERROR_CODE, 0);
    AppStorage.setOrCreate(WIDGET_ADD_SHEET_PREFILL_STORAGE_KEY, '');
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    this.backupScheduler = new BackupScheduler(this.context);
    this.registerTimerWidgetListener();
    this.registerMatterWidgetListener();
    this.registerWidgetCallHandlers();
    this.subscribeLiveViewStopEvent();

    this.initializeColorMode();
    this.registerColorModeEnvironmentListener();
    // 初始化数据库工具类
    RDBStoreUtil.init(this.context);
    // 注册计时会话 store（DB 命令 + AppStorage 投影单写通道）
    setupRecordingSession();
    // 处理卡片与实况窗 router 参数；计时会话已就绪后才允许结束记录。
    this.handleWidgetRouterParams(want);
    // 获取Push Token
    // try {
    //   const pushToken: string = await pushService.getToken();
    //   hilog.info(0x0000, TAG, `${TAG} token is ${JSON.stringify(pushToken)}`)
    //   hilog.info(0x0000, TAG, 'Succeeded in getting push token');
    // } catch (err) {
    //   let e: BusinessError = err as BusinessError;
    //   hilog.error(0x0000, TAG, 'Failed to get push token: %{public}d %{public}s', e.code, e.message);
    // }
    // 上报Push Token并上报到您的服务端
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'databackup.PhoneAbility.onDestroy');
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    this.stopLiveViewForAbilityTeardown('onDestroy');
    this.unregisterColorModeEnvironmentListener();
    this.backupScheduler?.stop();
    this.unregisterWidgetCallHandlers();
    this.unsubscribeLiveViewStopEvent();
  }

  /**
   * 订阅实况窗"结束"图标的公共事件：点击图标时无需拉起应用界面即可停止记录。
   * 计时期间已申请长时任务，进程保持存活，订阅可正常收到事件。
   */
  private subscribeLiveViewStopEvent(): void {
    if (this.liveViewStopSubscriber !== null) {
      return;
    }
    const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [LIVE_VIEW_STOP_EVENT]
    };
    commonEventManager.createSubscriber(subscribeInfo, (err: BusinessError, subscriber: commonEventManager.CommonEventSubscriber) => {
      if (err) {
        hilog.error(DOMAIN, TAG, `create live view stop subscriber failed: ${err.code} ${err.message}`);
        return;
      }
      this.liveViewStopSubscriber = subscriber;
      commonEventManager.subscribe(subscriber, (subscribeErr: BusinessError, data: commonEventManager.CommonEventData) => {
        if (subscribeErr) {
          hilog.error(DOMAIN, TAG, `subscribe live view stop event failed: ${subscribeErr.code} ${subscribeErr.message}`);
          return;
        }
        hilog.info(DOMAIN, TAG, `live view stop event received: ${data.event}`);
        this.requestStopTimer();
      });
    });
  }

  private unsubscribeLiveViewStopEvent(): void {
    const subscriber = this.liveViewStopSubscriber;
    if (subscriber === null) {
      return;
    }
    commonEventManager.unsubscribe(subscriber, (err: BusinessError) => {
      if (err) {
        hilog.error(DOMAIN, TAG, `unsubscribe live view stop event failed: ${err.code} ${err.message}`);
      }
    });
    this.liveViewStopSubscriber = null;
  }

  /**
   * 单实例应用热启动处理（卡片 router 参数等）
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, `onNewWant called, launchReason=${launchParam.launchReason}`);

    // 处理卡片 router 参数（热启动场景）
    this.handleWidgetRouterParams(want);
  }

  async onWindowStageCreate(windowStage: window.WindowStage) {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    // 初始化用户首选项
    const sharedPreferences = preferencesUtil;
    try {
      await sharedPreferences.init(this.context, 'todayStore', true);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[PhoneAbility] Failed to initialize preferences: ${JSON.stringify(error)}`);
    }
    const preferenceStore = sharedPreferences.getPreferences();
    hilog.info(DOMAIN, TAG, `[PhoneAbility] Preferences initialized: ${sharedPreferences.isInitialized()}`);
    const autoStopSettingsState = hydrateAutoStopSettings(sharedPreferences);
    hilog.info(
      DOMAIN,
      TAG,
      `[PhoneAbility] autoStop hydrated enabled=${autoStopSettingsState.enabled}, limitHalfHours=${autoStopSettingsState.limitHalfHours}, snapshotState=${autoStopSettingsState.snapshotState}`
    );
    if (!preferenceStore) {
      hilog.error(DOMAIN, TAG, '[PhoneAbility] Preference store is null after init');
    } else {
      try {
        const existingValue = preferenceStore.getSync(PreferenceKeys.DIRECT_START, false);
        hilog.info(DOMAIN, TAG, `[PhoneAbility] directStart existing value before default enforcement: ${JSON.stringify(existingValue)}`);
      } catch (error) {
        hilog.error(DOMAIN, TAG, `[PhoneAbility] Failed to read directStart before default: ${JSON.stringify(error)}`);
      }
    }
    if (preferenceStore && !preferenceStore.hasSync(PreferenceKeys.DIRECT_START)) {
      preferenceStore.putSync(PreferenceKeys.DIRECT_START, false);
      if (sharedPreferences.requiresManualFlush()) {
        sharedPreferences.flush();
      }
      hilog.info(DOMAIN, TAG, '[PhoneAbility] directStart preference missing. Default value false persisted.');
    } else if (preferenceStore) {
      const persistedValue = preferenceStore.getSync(PreferenceKeys.DIRECT_START, false);
      hilog.info(DOMAIN, TAG, `[PhoneAbility] directStart preference already set to ${JSON.stringify(persistedValue)}`);
    }

    if (preferenceStore && !preferenceStore.hasSync(PreferenceKeys.DEFAULT_LINE_PANEL)) {
      preferenceStore.putSync(PreferenceKeys.DEFAULT_LINE_PANEL, false);
      if (sharedPreferences.requiresManualFlush()) {
        sharedPreferences.flush();
      }
      hilog.info(DOMAIN, TAG, '[PhoneAbility] default data panel preference missing. Default value false persisted.');
    } else if (preferenceStore) {
      const persistedLinePreference = preferenceStore.getSync(PreferenceKeys.DEFAULT_LINE_PANEL, false);
      hilog.info(DOMAIN, TAG, `[PhoneAbility] default data panel preference already set to ${JSON.stringify(persistedLinePreference)}`);
    }

    if (preferenceStore && !preferenceStore.hasSync(PreferenceKeys.COLOR_MODE_TAB_INDEX)) {
      preferenceStore.putSync(PreferenceKeys.COLOR_MODE_TAB_INDEX, 0);
      if (sharedPreferences.requiresManualFlush()) {
        sharedPreferences.flush();
      }
      hilog.info(DOMAIN, TAG, '[PhoneAbility] color mode tab preference missing. Default index 0 persisted.');
    } else if (preferenceStore) {
      const persistedColorModeTab = preferenceStore.getSync(PreferenceKeys.COLOR_MODE_TAB_INDEX, 0);
      hilog.info(DOMAIN, TAG, `[PhoneAbility] color mode tab preference already set to ${JSON.stringify(persistedColorModeTab)}`);
    }
    this.applyColorModeFromPreferences(preferenceStore);

    // Initialize calendar sync preference (default off)
    let calendarSyncPreferred = false;
    if (preferenceStore && !preferenceStore.hasSync(PreferenceKeys.CALENDAR_SYNC_ENABLED)) {
      preferenceStore.putSync(PreferenceKeys.CALENDAR_SYNC_ENABLED, false);
      if (sharedPreferences.requiresManualFlush()) {
        sharedPreferences.flush();
      }
      hilog.info(DOMAIN, TAG, '[PhoneAbility] calendarSyncEnabled preference missing. Persisted default=false');
    } else if (preferenceStore) {
      const persistedCalendarSync = preferenceStore.getSync(PreferenceKeys.CALENDAR_SYNC_ENABLED, false);
      calendarSyncPreferred = !!persistedCalendarSync;
      hilog.info(DOMAIN, TAG, `[PhoneAbility] calendarSyncEnabled preference already set to ${JSON.stringify(persistedCalendarSync)}`);
    }
    AppStorage.setOrCreate('calendarSyncEnabled', calendarSyncPreferred);

    // Initialize show user guide preference (default true)
    let showUserGuidePreferred = true;
    if (preferenceStore && !preferenceStore.hasSync(PreferenceKeys.SHOW_USER_GUIDE)) {
      preferenceStore.putSync(PreferenceKeys.SHOW_USER_GUIDE, true);
      if (sharedPreferences.requiresManualFlush()) {
        sharedPreferences.flush();
      }
      hilog.info(DOMAIN, TAG, '[PhoneAbility] showUserGuide preference missing. Default value true persisted.');
    } else if (preferenceStore) {
      const persistedShowUserGuide = preferenceStore.getSync(PreferenceKeys.SHOW_USER_GUIDE, true);
      showUserGuidePreferred = !!persistedShowUserGuide;
      hilog.info(DOMAIN, TAG, `[PhoneAbility] showUserGuide preference already set to ${JSON.stringify(persistedShowUserGuide)}`);
    }
    AppStorage.setOrCreate('showUserGuide', showUserGuidePreferred);
    AppStorage.setOrCreate('userGuideSheetVisible', false);

    let floatingActionMiniBarPreferred = false;
    if (preferenceStore && !preferenceStore.hasSync(PreferenceKeys.FLOATING_ACTION_MINIBAR)) {
      preferenceStore.putSync(PreferenceKeys.FLOATING_ACTION_MINIBAR, false);
      if (sharedPreferences.requiresManualFlush()) {
        sharedPreferences.flush();
      }
      hilog.info(DOMAIN, TAG, '[PhoneAbility] floatingActionMiniBar preference missing. Persisted default=false');
    } else if (preferenceStore) {
      const persistedFloatingActionMiniBar = preferenceStore.getSync(PreferenceKeys.FLOATING_ACTION_MINIBAR, false);
      floatingActionMiniBarPreferred = !!persistedFloatingActionMiniBar;
      hilog.info(DOMAIN, TAG, `[PhoneAbility] floatingActionMiniBar preference already set to ${JSON.stringify(persistedFloatingActionMiniBar)}`);
    }
    AppStorage.setOrCreate('useFloatingActionBar', floatingActionMiniBarPreferred);

    // 写入默认的扇形菜单 Mock 数据，便于在首次启动时展示示例 FanItem
    const existingFanItems = fanItemService.getAllFanItems();
    if (existingFanItems.length <= 0) {
      const mockFanItems: FanItemPayload[] = [
        { icon: '🏃', label: '运动', id: 1, directRecordData: { tagId: 'tag-004', autoStart: true } },
        { icon: '💼', label: '工作', id: 2, directRecordData: { tagId: 'tag-001', autoStart: true } },
        { icon: '📖', label: '学习', id: 3, directRecordData: { tagId: 'tag-002', autoStart: true} },
        { icon: '🧘', label: '生活', id: 4, directRecordData: { tagId: 'tag-006', autoStart: true } }
      ];
      fanItemService.saveFanItems(mockFanItems);
      console.info('[FanItemService] Seeded mock fan items into preferences');
    }

    hilog.info(DOMAIN, TAG, 'User preferences initialized with name: todayStore');
    // 1. 获取应用主窗口
    windowStage.getMainWindow((err, windowClass) => {
      if (err.code) {
        console.error('Failed to obtain the main window. Cause: ' + JSON.stringify(err));
        return;
      }
      console.info('Succeeded in obtaining the main window.');
      try {
        // 2. 获取系统避让区域 (状态栏、导航栏等)
        let avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        console.info('Succeeded in obtaining the avoid area. Data: ' + JSON.stringify(avoidArea));

        // 3. 将获取到的避让高度存入 AppStorage，方便页面UI使用
        AppStorage.setOrCreate('topSafeArea', avoidArea.topRect.height);
        AppStorage.setOrCreate('bottomSafeArea', avoidArea.bottomRect.height);
      } catch (exception) {
        console.error('Failed to obtain the avoid area. Cause:' + JSON.stringify(exception));
      }
    });

    try {
      // 获取数据库实例并初始化数据库
      const dbUtil = RDBStoreUtil.getInstance();
      await dbUtil.initRDB();
      hilog.info(DOMAIN, TAG, 'Database initialization successful.');

      // Seed default IdeaPool collections on first run to avoid an empty collection list.
      const existingCollections = await dbUtil.queryIdeaCollections();
      if (existingCollections.length <= 0) {
        const existingTags = await dbUtil.queryAllTags();
        const collections = buildDefaultIdeaPoolSeedCollections(existingTags);
        for (let index = 0; index < collections.length; index += 1) {
          const collection = collections[index];
          await dbUtil.insertIdeaCollection(
            collection.id,
            collection.name,
            collection.icon ?? null,
            collection.tagId ?? null,
            collection.coverStyle ?? null,
            collection.summaryText ?? null,
            collection.displayOrder
          );
        }
        hilog.info(DOMAIN, TAG, '[PhoneAbility] Seeded default IdeaPool collections into RDB');
      }

      const recoveredCount = await dbUtil.recoverArchivedActivitiesWithTodayRecords();
      hilog.info(0x0000, TAG, `Recovered ${recoveredCount} archived activities with today records.`);

      // 归档非今天的事项
      hilog.info(0x0000, TAG, 'Archiving non-today activities...');
      const archiveResult = await dbUtil.archiveNonTodayActivities();
      if (archiveResult) {
        hilog.info(0x0000, TAG, 'Non-today activities archived successfully.');
      } else {
        hilog.error(0x0000, TAG, 'Failed to archive non-today activities.');
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to initialize database. Cause: %{public}s', JSON.stringify(err));
    }

    try {
      hilog.info(0x0000, TAG, 'Loading and categorizing matters...');

      // 运行态键（isRunning/currentRunningItemId 等）已由 RecordingSessionBoot 投影单写（Phase 4-6）
      AppStorage.setOrCreate('showPanel', true);
      AppStorage.setOrCreate('matterData', [])
      AppStorage.setOrCreate('tagData', [])
      AppStorage.setOrCreate('newTagColor', [])
      AppStorage.setOrCreate('currentTime', 0);
      AppStorage.setOrCreate('doneMatterData', []);
      AppStorage.setOrCreate('unDoMatterData', []);
      AppStorage.setOrCreate('isCustomDialogShow', false)
      AppStorage.setOrCreate('liveViewId', 0)
      AppStorage.setOrCreate('holdingHandEnabled', false);
      AppStorage.setOrCreate('holdingHandOffsetPercent', 0);
      AppStorage.setOrCreate('holdingHandStatus', motion.HoldingHandStatus.UNKNOWN_STATUS);

      // Initialize shared date storage with today's values
      const today = dayjs();
      AppStorage.setOrCreate(StorageKeys.SELECTED_DATE, today.date());
      AppStorage.setOrCreate(StorageKeys.SELECTED_MONTH, today.month() + 1); // dayjs month is 0-indexed
      AppStorage.setOrCreate(StorageKeys.SELECTED_YEAR, today.year());
      AppStorage.setOrCreate(StorageKeys.VIEW_DATE, today.date());
      AppStorage.setOrCreate(StorageKeys.VIEW_MONTH, today.month() + 1);
      AppStorage.setOrCreate(StorageKeys.VIEW_YEAR, today.year());

      // 然后执行崩溃恢复逻辑
      await this.recoverIncompleteRecords();
      this.recordingRuntimeReady = true;
      this.drainPendingStopTimerAction();

      // 最后加载和分类事项
      const allMatters: MatterItemModel[] = await todayActivityService.getTodayMatterItems();

      const doneMatterData = allMatters.filter(item =>
        item.status === MatterStatus.PAUSED || item.status === MatterStatus.RECORDING
      );

      const unDoMatterData = allMatters.filter(item =>
        item.status === MatterStatus.TODO
      );

      AppStorage.setOrCreate('matterData', allMatters);
      AppStorage.setOrCreate('doneMatterData', doneMatterData);
      AppStorage.setOrCreate('unDoMatterData', unDoMatterData);

      hilog.info(0x0000, TAG, `Matters loaded. Done: ${doneMatterData.length}, ToDo: ${unDoMatterData.length}`);
    } catch (err) {
      hilog.error(0x0000, TAG, `errors in loading Matter data`);
    }


    windowStage.loadContent('pages/Index', (err, data) => {
      try {
        AppStorage.setOrCreate('uiContext', windowStage.getMainWindowSync().getUIContext());
      } catch (error) {
        hilog.error(DOMAIN, TAG, `Failed to cache uiContext: ${JSON.stringify(error)}`);
      }
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }

      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      windowStage.getMainWindow().then((data: window.Window) => {
        try {
          this.windowObj = data;
          const uiContext = data.getUIContext();

          this.updateBreakpoint(data.getWindowProperties().windowRect.width, uiContext);
          data.on('windowSizeChange', (windowSize: window.Size) => {
            this.updateBreakpoint(windowSize.width, uiContext);
          });

          const navArea = data.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
          AppStorage.setOrCreate('bottomRectHeight', navArea.bottomRect.height);

          const sysArea = data.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          AppStorage.setOrCreate('topRectHeight', sysArea.topRect.height);
        } catch (err) {
          let error = err as BusinessError;
          hilog.error(0x0000, TAG, `getMainWindow error ${error.code} ${error.message}`);
        }
      }).catch((error: BusinessError) => {
        hilog.error(0x0000, TAG, 'Failed to getMainWindow. Cause: ',
          JSON.stringify(error.code) + JSON.stringify(error.message));
      })
    });
  }

  onWindowStageWillDestroy(windowStage: window.WindowStage): void {
    // 添加自动保存逻辑
    this.stopLiveViewForAbilityTeardown('onWindowStageWillDestroy');
    const isRunning = recordingSessionStore.snapshot() !== null;
    if (isRunning) {
      hilog.info(DOMAIN, TAG, 'Sync Restart: skipping saveActiveTimers on stage destroy because a timer is running (preserve for resume).');
      return;
    }
    hilog.info(DOMAIN, TAG, 'Sync Restart: no active timer, proceeding with saveActiveTimers on stage destroy.');
    this.saveActiveTimers();
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /** Ability 或窗口被系统销毁时只清理实况窗，保留 DB 中的计时会话供下次启动恢复。 */
  private stopLiveViewForAbilityTeardown(source: string): void {
    liveViewController.stopLiveView().catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, `Failed to stop live view during ${source}: ${JSON.stringify(error)}`);
    });
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'databackup.PhoneAbility.onForeground');
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    this.backupScheduler?.start();

    const previousSession = recordingSessionStore.snapshot();
    const previousIsRunning = previousSession !== null;
    const previousItemId = previousSession !== null ? previousSession.itemId : '';
    const previousRecordId = previousSession !== null ? previousSession.recordId : '';

    // 设置应用前台状态
    AppStorage.setOrCreate('appInForeground', true);
    AppStorage.setOrCreate('lastForegroundTime', Date.now());
    recordingSessionStore.setForeground(true);

    // 应用从后台恢复时，不再重置StorageLink状态，保持原有状态
    hilog.info(DOMAIN, TAG, 'Screen unlocked, preserving StorageLink state');
    hilog.info(DOMAIN, TAG, `Current StorageLink state - isRunning: ${previousIsRunning}, itemId: ${previousItemId}, recordId: ${previousRecordId}`);
    void this.reconcileActiveRecordingState();

    // 应用从后台恢复时，检查后台任务状态
    if (previousIsRunning) {
      // 如果之前有计时器在运行，检查后台任务是否需要重启
      hilog.info(
        DOMAIN,
        TAG,
        `${BACKGROUND_TASK_LOG_PREFIX}: ability foreground check begin itemId=${previousItemId} recordId=${previousRecordId} isRunning=${previousIsRunning}`
      );
      // 获取所有长时任务信息
      backgroundTaskManager.getAllContinuousTasks(this.context).then((res: backgroundTaskManager.ContinuousTaskInfo[]) => {
        hilog.info(DOMAIN, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ability foreground tasks count=${res.length} itemId=${previousItemId}`);
        if (res.length === 0) {
          // 如果没有长时任务，重新启动
          hilog.info(DOMAIN, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ability foreground found no tasks, scheduling restart itemId=${previousItemId}`);
          if (previousItemId) {
            void MatterItemStateManager.getInstance().ensureBackgroundTask(
              previousItemId,
              this.context,
              'PhoneAbility.onForeground-missing-task'
            );
          }
        }
      }).catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ability foreground getAllContinuousTasks failed error=${JSON.stringify(error)}`);
      });
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'databackup.PhoneAbility.onBackground');
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    this.backupScheduler?.stop();

    // 设置应用后台状态
    AppStorage.setOrCreate('appInForeground', false);
    recordingSessionStore.setForeground(false);

    // 锁屏时不再自动保存计时器状态，让计时器继续运行
    hilog.info(DOMAIN, TAG, 'Screen locked, preserving timer state (not saving)');

    // 锁屏时确保后台任务正在运行
    const backgroundSession = recordingSessionStore.snapshot();

    if (backgroundSession !== null) {
      // 如果有计时器在运行，确保后台任务也在运行
      const currentRunningItemId = backgroundSession.itemId;
      hilog.info(
        DOMAIN,
        TAG,
        `${BACKGROUND_TASK_LOG_PREFIX}: ability background check begin itemId=${currentRunningItemId} isRunning=true`
      );
      // 获取所有长时任务信息
      backgroundTaskManager.getAllContinuousTasks(this.context).then((res: backgroundTaskManager.ContinuousTaskInfo[]) => {
        hilog.info(DOMAIN, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ability background tasks count=${res.length} itemId=${currentRunningItemId}`);
        if (res.length === 0) {
          // 如果没有长时任务，直接经 manager 重启后台任务
          hilog.info(DOMAIN, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ability background found no tasks, scheduling restart itemId=${currentRunningItemId}`);
          if (currentRunningItemId) {
            void MatterItemStateManager.getInstance().ensureBackgroundTask(
              currentRunningItemId,
              this.context,
              'PhoneAbility.onBackground-missing-task'
            );
          }
        }
      }).catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, `${BACKGROUND_TASK_LOG_PREFIX}: ability background getAllContinuousTasks failed error=${JSON.stringify(error)}`);
      });
    }
  }

  private updateBreakpoint(windowWidth: number, uiContext: UIContext): void{
    try {
      const density = display.getDefaultDisplaySync().densityPixels;
      const windowWidthVp = windowWidth / density;
      let curBp: string = BreakpointConstants.BREAKPOINT_SM;

      if (windowWidthVp < BreakpointConstants.BREAKPOINT_VALUE_NUMBER[1]) {
        curBp = BreakpointConstants.BREAKPOINT_SM;
      } else if (windowWidthVp < BreakpointConstants.BREAKPOINT_VALUE_NUMBER[2]) {
        curBp = BreakpointConstants.BREAKPOINT_MD;
      } else {
        curBp = BreakpointConstants.BREAKPOINT_LG;
      }

      AppStorage.setOrCreate(BreakpointConstants.CURRENT_BREAKPOINT, curBp);

      const currentHeightBreakpoint = uiContext.getWindowHeightBreakpoint();
      AppStorage.setOrCreate('currentHeightBreakpoint', currentHeightBreakpoint);
    } catch (error) {
      hilog.error(0x0000, TAG, 'Failed to updateBreakpoint. Cause: %{public}s', JSON.stringify(error) ?? '');
    }
  }

  /**
   * 保存正在进行的计时器
   * 当应用进入后台或被销毁时，保存所有正在进行的计时器状态
   */
  private async saveActiveTimers(): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Saving active timers...');

      // 获取所有事项
      const allMatters: MatterItemModel[] = await todayActivityService.getTodayMatterItems();

      // 查找正在计时的事项
      const recordingMatters = allMatters.filter(item => item.status === MatterStatus.RECORDING);

      if (recordingMatters.length > 0) {
        hilog.info(DOMAIN, TAG, `Found ${recordingMatters.length} active timers to save`);

        // 对每个正在计时的事项，停止计时并保存状态
        for (const matter of recordingMatters) {
          hilog.info(DOMAIN, TAG, `Saving timer for activity: ${matter.id}`);

          // 首先检查是否有活跃的时间记录
          const latestRecord = await todayActivityService.queryLatestTimeRecord(matter.id);

          if (!latestRecord) {
            // 如果没有活跃的时间记录，说明状态不一致，需要创建一个时间记录
            hilog.warn(DOMAIN, TAG, `Activity ${matter.id} has RECORDING status but no active time record, creating one`);

            // 从会话快照获取记录ID（如果有的话）
            const activeSession = recordingSessionStore.snapshot();
            const timerStateRecordId: string =
              activeSession !== null && activeSession.itemId === matter.id ? activeSession.recordId : '';

            // 如果会话中有记录ID，尝试使用它
            if (timerStateRecordId && timerStateRecordId.trim() !== '') {
              const record = await todayActivityService.getTimeRecordById(timerStateRecordId);
              if (record && record.activityId === matter.id) {
                // 找到了记录，使用它
                hilog.info(DOMAIN, TAG, `Found record in StorageLink: ${timerStateRecordId}`);
                const success = await todayActivityService.stopTimeRecord(matter.id, timerStateRecordId);
                if (success) {
                  hilog.info(DOMAIN, TAG, `Successfully saved timer for activity: ${matter.id}`);
                } else {
                  hilog.error(DOMAIN, TAG, `Failed to save timer for activity: ${matter.id}`);
                }
                continue;
              }
            }

            // 如果会话中没有有效的记录ID，直接更新活动状态为PAUSED
            // 不创建新的时间记录，因为我们无法准确计算持续时间
            const rdbStoreUtil = RDBStoreUtil.getInstance();
            const statusUpdateResult = await rdbStoreUtil.updateActivityStatus(matter.id, MatterStatus.PAUSED);

            if (statusUpdateResult) {
              hilog.info(DOMAIN, TAG, `Updated activity status to PAUSED for ${matter.id} without creating time record`);
            } else {
              hilog.error(DOMAIN, TAG, `Failed to update activity status for ${matter.id}`);
            }
          } else {
            // 有活跃的时间记录，正常处理
            const success = await todayActivityService.stopTimeRecord(matter.id, latestRecord.id);
            if (success) {
              hilog.info(DOMAIN, TAG, `Successfully saved timer for activity: ${matter.id}`);
            } else {
              hilog.error(DOMAIN, TAG, `Failed to save timer for activity: ${matter.id}`);

              // 如果停止失败，尝试直接更新活动状态为PAUSED
              hilog.warn(DOMAIN, TAG, `Attempting fallback: updating activity status to PAUSED for ${matter.id}`);
              const rdbStoreUtil = RDBStoreUtil.getInstance();
              const fallbackResult = await rdbStoreUtil.updateActivityStatus(matter.id, MatterStatus.PAUSED);

              if (fallbackResult) {
                hilog.info(DOMAIN, TAG, `Fallback successful: updated activity status to PAUSED for ${matter.id}`);
              } else {
                hilog.error(DOMAIN, TAG, `Fallback failed: could not update activity status for ${matter.id}`);
              }
            }
          }
        }
      } else {
        hilog.info(DOMAIN, TAG, 'No active timers to save');
      }

      // 额外的安全检查：确保没有遗漏的活跃时间记录
      hilog.info(DOMAIN, TAG, 'Performing safety check for any remaining active time records...');
      await this.cleanupRemainingActiveRecords();

    } catch (error) {
      hilog.error(DOMAIN, TAG, `Error saving active timers: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 清理剩余的活跃时间记录
   * 这是一个安全检查，确保没有遗漏的活跃时间记录
   */
  private async cleanupRemainingActiveRecords(): Promise<void> {
    try {
      // 获取所有今日活动
      const allMatters: MatterItemModel[] = await todayActivityService.getTodayMatterItems();

      // 检查每个活动是否有活跃的时间记录
      for (const matter of allMatters) {
        const latestRecord = await todayActivityService.queryLatestTimeRecord(matter.id);

        // 如果有活跃的时间记录（没有结束时间），则进行处理
        if (latestRecord && !latestRecord.endTime) {
          hilog.warn(DOMAIN, TAG, `Found remaining active record for activity ${matter.id}, cleaning up...`);

          // 尝试停止时间记录
          const stopSuccess = await todayActivityService.stopTimeRecord(matter.id, latestRecord.id);

          if (stopSuccess) {
            hilog.info(DOMAIN, TAG, `Successfully stopped remaining active record for activity ${matter.id}`);
          } else {
            hilog.error(DOMAIN, TAG, `Failed to stop remaining active record for activity ${matter.id}, deleting it instead`);

            // 如果停止失败，删除不完整的时间记录
            const deleteSuccess = await todayActivityService.deleteTimeRecord(latestRecord.id);

            if (deleteSuccess) {
              hilog.info(DOMAIN, TAG, `Successfully deleted remaining active record for activity ${matter.id}`);

              // 更新活动状态为PAUSED
              const rdbStoreUtil = RDBStoreUtil.getInstance();
              const statusUpdateResult = await rdbStoreUtil.updateActivityStatus(matter.id, MatterStatus.PAUSED);

              if (statusUpdateResult) {
                hilog.info(DOMAIN, TAG, `Successfully updated activity status to PAUSED for ${matter.id}`);
              } else {
                hilog.error(DOMAIN, TAG, `Failed to update activity status for ${matter.id}`);
              }
            } else {
              hilog.error(DOMAIN, TAG, `Failed to delete remaining active record for activity ${matter.id}`);
            }
          }
        }
      }

      hilog.info(DOMAIN, TAG, 'Safety check for remaining active records completed');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Error during safety check for remaining active records: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 恢复未完成的记录
   * 当应用启动时，检查并恢复可能因崩溃而未正确保存的记录
   */
  private async recoverIncompleteRecords(): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Sync Restart: begin recovery for possible incomplete records');
      const allMatters: MatterItemModel[] = await todayActivityService.getTodayMatterItems();
      const recoverySession = recordingSessionStore.snapshot();
      hilog.info(DOMAIN, TAG, `Sync Restart: loaded ${allMatters.length} matters for recovery, sessionActive=${recoverySession !== null}, sessionItem=${recoverySession ? recoverySession.itemId : ''}`);
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const persistedSnapshot = getAutoStopRunningSnapshotFromAppStorage();

      let resumedRecord: ResumeTimeRecord | null = null;
      let resumedMatter: MatterItemModel | null = null;
      let fallbackRecord: ResumeTimeRecord | null = null;
      let fallbackMatter: MatterItemModel | null = null;
      let activeRecordCounter = 0;

      for (const matter of allMatters) {
        const latestRecord = await todayActivityService.queryLatestTimeRecord(matter.id);
        const hasActiveRecord = latestRecord && !latestRecord.endTime;

        if (hasActiveRecord && latestRecord) {
          activeRecordCounter++;
          hilog.info(DOMAIN, TAG, `Sync Restart: found active record ${latestRecord.id} for activity ${matter.id}, start=${latestRecord.startTime}, status=${matter.status}`);

          if (matter.status !== MatterStatus.RECORDING) {
            hilog.info(DOMAIN, TAG, `Sync Restart: bump activity ${matter.id} status ${matter.status} -> RECORDING to match active record`);
            await rdbStoreUtil.updateActivityStatus(matter.id, MatterStatus.RECORDING);
            matter.status = MatterStatus.RECORDING;
          }

          if (!fallbackRecord || latestRecord.startTime > fallbackRecord.startTime) {
            fallbackRecord = {
              recordId: latestRecord.id,
              startTime: latestRecord.startTime,
              activityId: latestRecord.activityId
            };
            fallbackMatter = matter;
          }

          if (persistedSnapshot
            && doesAutoStopRunningSnapshotMatch(persistedSnapshot, matter.id, latestRecord.id, latestRecord.startTime)) {
            resumedRecord = {
              recordId: latestRecord.id,
              startTime: latestRecord.startTime,
              activityId: latestRecord.activityId
            };
            resumedMatter = matter;
            hilog.info(
              DOMAIN,
              TAG,
              `Sync Restart: matched autoStop snapshot to active record ${latestRecord.id} for activity ${matter.id}`
            );
          }
        } else if (!hasActiveRecord && matter.status === MatterStatus.RECORDING) {
          hilog.warn(DOMAIN, TAG, `Sync Restart: activity ${matter.id} marked RECORDING but no active record, forcing PAUSED`);
          await rdbStoreUtil.updateActivityStatus(matter.id, MatterStatus.PAUSED);
          matter.status = MatterStatus.PAUSED;
        }
      }

      if (activeRecordCounter > 1) {
        hilog.warn(DOMAIN, TAG, `Sync Restart: detected ${activeRecordCounter} concurrent active records, will resume most recent`);
      }

      if (!resumedRecord && fallbackRecord && fallbackMatter) {
        resumedRecord = fallbackRecord;
        resumedMatter = fallbackMatter;
      }

      if (persistedSnapshot && (!resumedRecord
        || !doesAutoStopRunningSnapshotMatch(persistedSnapshot, resumedRecord.activityId, resumedRecord.recordId, resumedRecord.startTime))) {
        hilog.warn(
          DOMAIN,
          TAG,
          `Sync Restart: clearing stale autoStop snapshot, snapshotActivityId=${persistedSnapshot.activityId}, snapshotRecordId=${persistedSnapshot.recordId}`
        );
        persistAutoStopRunningSnapshot(preferencesUtil, undefined);
      }

      if (resumedRecord && resumedMatter) {
        const manager = MatterItemStateManager.getInstance();
        const autoStoppedSnapshot = await manager.enforceAutoStopIfNeeded(resumedMatter.id, 'coldStartRecovery');
        if (autoStoppedSnapshot) {
          hilog.info(
            DOMAIN,
            TAG,
            `Sync Restart: auto-stop consumed active record ${resumedRecord.recordId} for activity ${resumedMatter.id} during cold start recovery`
          );
          return;
        }

        const now = Date.now();
        const elapsed = Math.max(0, now - resumedRecord.startTime);
        const elapsedSeconds = Math.floor(elapsed / 1000);

        // Phase 4-3: 会话经 store 收养 DB open record（幂等，异会话不抢占），运行键由投影单写者维护
        await recordingSessionStore.adoptOpenRecord(resumedMatter.id);
        hilog.info(DOMAIN, TAG,
          `Sync Restart: resumed record ${resumedRecord.recordId} for matter ${resumedMatter.id}, elapsed=${elapsedSeconds}s, sessionActive=${recordingSessionStore.snapshot() !== null}`);

        try {
          // TODO: start the live view with params
          await liveViewController.startLiveView(elapsed, resumedMatter.title);
        } catch (error) {
          hilog.error(DOMAIN, TAG, `Failed to resume live view: ${JSON.stringify(error)}`);
        }

        hilog.info(DOMAIN, TAG, `Sync Restart: recovery complete for record ${resumedRecord.recordId} on ${resumedMatter.id}, elapsed=${elapsedSeconds}s`);
      } else {
        if (persistedSnapshot) {
          hilog.warn(
            DOMAIN,
            TAG,
            `Sync Restart: no active records detected, clearing stale autoStop snapshot ${persistedSnapshot.recordId}`
          );
          persistAutoStopRunningSnapshot(preferencesUtil, undefined);
        }
        hilog.info(DOMAIN, TAG, 'Sync Restart: no active records detected during recovery');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Error recovering incomplete records: ${JSON.stringify(error)}`);
    }
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    super.onConfigurationUpdate(newConfig);
    this.updateColorMode(newConfig?.colorMode);
  }

  private initializeColorMode(): void {
    const preferenceStore = preferencesUtil.isInitialized() ? preferencesUtil.getPreferences() : null;
    if (preferenceStore) {
      this.applyColorModeFromPreferences(preferenceStore);
      return;
    }

    const fallbackMode = this.context?.config?.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    hilog.warn(DOMAIN, TAG, '[PhoneAbility] Preferences not ready during onCreate, falling back to config color mode.');
    this.applyColorModeSetting(fallbackMode);

    void preferencesUtil.init(this.context, 'todayStore', true)
      .then(() => {
        this.applyColorModeFromPreferences(preferencesUtil.getPreferences());
      })
      .catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, `[PhoneAbility] Failed to initialize preferences for color mode: ${JSON.stringify(error)}`);
      });
  }

  private registerColorModeEnvironmentListener(): void {
    if (this.colorModeEnvironmentCallbackId >= 0) {
      return;
    }
    try {
      this.colorModeEnvironmentCallbackId =
        this.context.getApplicationContext().on('environment', this.colorModeEnvironmentCallback);
      hilog.info(DOMAIN, TAG, `[PhoneAbility] Color mode environment listener registered, id=${this.colorModeEnvironmentCallbackId}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[PhoneAbility] Failed to register environment listener: ${JSON.stringify(error)}`);
    }
  }

  private unregisterColorModeEnvironmentListener(): void {
    if (this.colorModeEnvironmentCallbackId < 0) {
      return;
    }
    try {
      this.context.getApplicationContext().off('environment', this.colorModeEnvironmentCallbackId);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[PhoneAbility] Failed to unregister environment listener: ${JSON.stringify(error)}`);
    }
    this.colorModeEnvironmentCallbackId = -1;
  }

  private updateColorMode(colorMode?: number): void {
    if (typeof colorMode !== 'number') {
      // 部分配置回调不携带 colorMode，绝不能回退成 LIGHT 覆盖当前主题
      hilog.warn(DOMAIN, TAG, '[PhoneAbility] Ignoring configuration update without colorMode.');
      return;
    }
    const normalized = ColorModeUtil.normalize(colorMode);
    AppStorage.setOrCreate(COLOR_MODE_STORAGE_KEY, normalized);
    const isDarkTheme = ColorModeUtil.isDarkMode(normalized);
    AppStorage.setOrCreate('isDarkTheme', isDarkTheme);
    // 版本号单调递增：即使本次写入的模式值与 AppStorage 中相同（应用内切换主题时
    // 已被提前同步写入），也能保证 @Watch 在系统资源真正切换之后再次触发，
    // 让 shader/visualEffect 用新色板重建。
    const previousVersion = AppStorage.get<number>(COLOR_MODE_VERSION_KEY) ?? 0;
    AppStorage.setOrCreate(COLOR_MODE_VERSION_KEY, previousVersion + 1);
    hilog.info(DOMAIN, TAG, `[PhoneAbility] Color mode updated to ${normalized} (${ColorModeUtil.describe(normalized)}), isDarkTheme=${isDarkTheme}, version=${previousVersion + 1}`);
  }

  private applyColorModeFromPreferences(preferenceStore?: preferences.Preferences | null): void {
    if (!preferenceStore) {
      hilog.warn(DOMAIN, TAG, '[PhoneAbility] Cannot apply color mode – preference store unavailable.');
      this.applyColorModeSetting(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      return;
    }

    try {
      const rawValue = preferenceStore.getSync(PreferenceKeys.COLOR_MODE_TAB_INDEX, 0);
      const numericValue = typeof rawValue === 'number' ? rawValue : Number(rawValue);
      const tabIndex = this.normalizeColorModeTabIndex(numericValue);
      const targetMode = this.mapTabIndexToColorMode(tabIndex);
      hilog.info(DOMAIN, TAG, `[PhoneAbility] Applying stored color mode tab index ${tabIndex}`);
      this.applyColorModeSetting(targetMode);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[PhoneAbility] Failed to read color mode preference: ${JSON.stringify(error)}`);
      this.applyColorModeSetting(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  }

  private applyColorModeSetting(targetMode: number): void {
    this.updateColorMode(targetMode);
    this.setApplicationColorMode(targetMode);
  }

  private setApplicationColorMode(targetMode: number): void {
    try {
      this.context?.getApplicationContext()?.setColorMode(targetMode);
      hilog.info(DOMAIN, TAG, `[PhoneAbility] Application color mode set to ${targetMode}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[PhoneAbility] Failed to set application color mode: ${JSON.stringify(error)}`);
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


  /**
   * Align runtime timer state with any open records (foreground return / recovery paths).
   */
  private async reconcileActiveRecordingState(): Promise<void> {
    try {
      const openRecords = await RDBStoreUtil.getInstance().queryActiveOpenRecords();
      const manager = MatterItemStateManager.getInstance();
      if (!openRecords.length) {
        await manager.reconcileGlobalRunningState();
        return;
      }
      for (const record of openRecords) {
        await manager.refreshItemState(record.activityId);
      }
      await manager.reconcileGlobalRunningState();
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to reconcile active recording state: ${JSON.stringify(err)}`);
    }
  }


  private registerTimerWidgetListener(): void {
    if (this.timerWidgetListenerRegistered) {
      return;
    }
    this.timerWidgetListenerRegistered = true;
    recordingSessionStore.onSessionChange(() => {
      void todayTimerWidgetService.refreshRegisteredForms(this.context);
    });
  }

  private registerMatterWidgetListener(): void {
    if (this.matterWidgetListenerRegistered) {
      return;
    }
    this.matterWidgetListenerRegistered = true;
    MatterItemStateManager.getInstance().addStateListener(() => {
      void todayRecordWidgetService.refreshRegisteredForms(this.context);
      void todayOverviewWidgetService.refreshRegisteredForms(this.context);
      void tagDistributionWidgetService.refreshRegisteredForms(this.context);
      void reflectTodayWidgetService.refreshRegisteredForms(this.context);
    });
  }

  private registerWidgetCallHandlers(): void {
    if (this.widgetCallHandlersRegistered) {
      return;
    }
    this.widgetCallHandlersRegistered = true;
    try {
      this.callee.on(WIDGET_CALL_METHOD_STOP_TIMER, (data: rpc.MessageSequence) => {
        try {
          const payload = data.readString();
          hilog.info(DOMAIN, TAG, `Widget call payload: ${JSON.stringify(payload)}`);
        } catch (_error) {
          // ignore optional payload parsing errors
        }
        this.requestStopTimer();
        return new EmptyParcelable();
      });
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to register widget call handler: ${JSON.stringify(err)}`);
    }
  }

  private unregisterWidgetCallHandlers(): void {
    if (!this.widgetCallHandlersRegistered) {
      return;
    }
    try {
      this.callee.off(WIDGET_CALL_METHOD_STOP_TIMER);
      this.widgetCallHandlersRegistered = false;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to unregister widget call handler: ${JSON.stringify(err)}`);
    }
  }

  private async handleWidgetStopTimer(): Promise<void> {
    let session = recordingSessionStore.snapshot();
    if (session === null) {
      await recordingSessionStore.restoreFromDb();
      session = recordingSessionStore.snapshot();
    }
    const itemId = session !== null ? session.itemId : '';
    if (!itemId) {
      hilog.info(DOMAIN, TAG, 'Widget stop timer ignored: no running item');
      return;
    }

    const item = await todayActivityService.getTodayMatterItemById(itemId);
    if (!item) {
      hilog.warn(DOMAIN, TAG, `Widget stop timer failed: item not found id=${itemId}`);
      return;
    }

    let stopError: Error | undefined = undefined;
    try {
      await MatterItemStateManager.getInstance().stop(item);
    } catch (error) {
      const err = error as Error;
      stopError = err;
      hilog.error(DOMAIN, TAG, `Widget stop timer failed: ${JSON.stringify(err)}`);
    } finally {
      MatterItemStateManager.getInstance().stopBackgroundTask(itemId);
      try {
        await liveViewController.stopLiveView();
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, `Widget stop live view failed: ${JSON.stringify(err)}`);
      }
    }

    if (!stopError) {
      hilog.info(DOMAIN, TAG, `Widget stop timer handled for item=${itemId}`);
    }
  }

  /**
   * 统一承接实况窗、卡片与热启动的停止命令。
   * 冷启动时先挂起，等 DB 初始化和未完成记录恢复后再幂等执行。
   */
  private requestStopTimer(): void {
    this.pendingStopTimerAction = true;
    this.drainPendingStopTimerAction();
  }

  private drainPendingStopTimerAction(): void {
    if (!this.recordingRuntimeReady || !this.pendingStopTimerAction || this.stopTimerCommandInFlight) {
      return;
    }
    this.pendingStopTimerAction = false;
    this.stopTimerCommandInFlight = true;
    void this.runPendingStopTimerAction();
  }

  private async runPendingStopTimerAction(): Promise<void> {
    try {
      await this.handleWidgetStopTimer();
    } finally {
      this.stopTimerCommandInFlight = false;
      this.drainPendingStopTimerAction();
    }
  }

  /**
   * 处理卡片 router 参数
   * 解析从 postCardAction router 传递的参数，设置相应的 AppStorage 标记
   */
  private buildTodayAddSheetPrefill(routerParams: Record<string, Object>): string {
    const activityRaw = routerParams[WIDGET_ROUTER_SHORTCUT_ACTIVITY_KEY];
    const tagIdRaw = routerParams[WIDGET_ROUTER_SHORTCUT_TAG_ID_KEY];
    const autoStartRaw = routerParams[WIDGET_ROUTER_SHORTCUT_AUTO_START_KEY];

    const activityName = typeof activityRaw === 'string' ? activityRaw : '';
    const tagId = typeof tagIdRaw === 'string' ? tagIdRaw : '';

    let hasAutoStart = false;
    let autoStart = false;
    if (typeof autoStartRaw === 'boolean') {
      hasAutoStart = true;
      autoStart = autoStartRaw;
    } else if (typeof autoStartRaw === 'string') {
      hasAutoStart = true;
      autoStart = autoStartRaw === 'true';
    }

    if (activityName.length === 0 && tagId.length === 0 && !hasAutoStart) {
      return '';
    }

    const prefill: TodayAddSheetPrefill = {
      activityName: activityName,
      tagId: tagId,
      autoStart: autoStart
    };
    return JSON.stringify(prefill);
  }

  private handleWidgetRouterParams(want: Want): void {
    hilog.info(DOMAIN, TAG, `handleWidgetRouterParams called, want.parameters: ${JSON.stringify(want.parameters)}`);

    if (!want.parameters) {
      hilog.info(DOMAIN, TAG, 'handleWidgetRouterParams: no parameters');
      return;
    }

    if (!want.parameters.params) {
      hilog.info(DOMAIN, TAG, 'handleWidgetRouterParams: no params in parameters');
      return;
    }

    let routerParams: Record<string, Object> | null = null;
    try {
      const paramsStr = want.parameters.params as string;
      hilog.info(DOMAIN, TAG, `Widget router params string: ${paramsStr}`);
      routerParams = JSON.parse(paramsStr) as Record<string, Object>;
      hilog.info(DOMAIN, TAG, `Widget router params parsed: ${JSON.stringify(routerParams)}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to parse widget router params: ${JSON.stringify(error)}`);
      return;
    }

    if (!routerParams) {
      return;
    }

    const liveViewAction = routerParams[LIVE_VIEW_ROUTER_ACTION_KEY] as string | undefined;
    if (liveViewAction === LIVE_VIEW_ROUTER_ACTION_STOP_TIMER) {
      this.requestStopTimer();
      return;
    }

    // 处理 target 参数：切换到指定页签
    const target = routerParams['target'] as string | undefined;
    hilog.info(DOMAIN, TAG, `Widget router target: ${target}`);
    if (target === WIDGET_ROUTER_TARGET_REFLECT) {
      AppStorage.setOrCreate('widgetTargetTabIndex', WIDGET_TARGET_TAB_REFLECT);
      hilog.info(DOMAIN, TAG, 'Widget router: set widgetTargetTabIndex to 0 (Reflect)');
    }
    if (target === WIDGET_ROUTER_TARGET_TODAY) {
      // Today 页面对应 Tab 索引为 1
      // 使用 widgetTargetTabIndex 来触发页签切换（适用于冷启动和热启动）
      AppStorage.setOrCreate('widgetTargetTabIndex', WIDGET_TARGET_TAB_TODAY);
      hilog.info(DOMAIN, TAG, 'Widget router: set widgetTargetTabIndex to 1 (Today)');
    }
    if (target === WIDGET_ROUTER_TARGET_IDEAPOOL) {
      // IdeaPool 页面对应 Tab 索引为 2
      AppStorage.setOrCreate('widgetTargetTabIndex', WIDGET_TARGET_TAB_IDEAPOOL);
      hilog.info(DOMAIN, TAG, 'Widget router: set widgetTargetTabIndex to 2 (IdeaPool)');
    }

    // 处理 openAddSheet 参数：标记需要打开添加事项 sheet
    const openAddSheet = routerParams['openAddSheet'] as boolean | undefined;
    hilog.info(DOMAIN, TAG, `Widget router openAddSheet: ${openAddSheet}`);
    if (openAddSheet === true) {
      if (target === WIDGET_ROUTER_TARGET_IDEAPOOL) {
        AppStorage.setOrCreate(WIDGET_ADD_SHEET_PREFILL_STORAGE_KEY, '');
        AppStorage.setOrCreate('openIdeaAddSheetFromWidget', true);
        hilog.info(DOMAIN, TAG, 'Widget router: set openIdeaAddSheetFromWidget to true');
      } else {
        const prefillJson = this.buildTodayAddSheetPrefill(routerParams);
        AppStorage.setOrCreate(WIDGET_ADD_SHEET_PREFILL_STORAGE_KEY, prefillJson);
        AppStorage.setOrCreate('openAddSheetFromWidget', true);
        hilog.info(DOMAIN, TAG, `Widget router: set openAddSheetFromWidget to true, prefill=${prefillJson}`);
      }
    }
  }
}
