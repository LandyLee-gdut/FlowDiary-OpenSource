import { HdsListItemCard, IconSize, PrefixIcon, SuffixSwitch } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { Context, Permissions, abilityAccessCtrl, bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys, PreferencesUtil, VibratorUtil, calendarSyncService, preferencesUtil } from 'base';
import { REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION } from './ReflectChartSettingsMotionTokens';

const TAG: string = 'CalendarSyncSettingsPage';
const CALENDAR_SYNC_PERMISSION_READ: Permissions = 'ohos.permission.READ_CALENDAR';
const CALENDAR_SYNC_PERMISSION_WRITE: Permissions = 'ohos.permission.WRITE_CALENDAR';
const CALENDAR_SYNC_RECENT_DAYS: number = 7;
const CALENDAR_SYNC_DAY_MS: number = 24 * 60 * 60 * 1000;

@Component
export struct CalendarSyncSettingsPage {
  @Prop calendarSyncEnabled: boolean = false;
  @Watch('onCalendarSyncPermissionPropChanged') @Prop calendarSyncPermissionGranted: boolean = true;
  onBack?: () => void;
  onCalendarSyncToggle?: (isOn: boolean) => Promise<void> | void;
  onCalendarResyncCopyClick?: () => Promise<void> | void;
  onCalendarPermissionRecoverClick?: () => Promise<void> | void;
  @State private localCalendarSyncEnabled: boolean = false;
  @State private localCalendarSyncPermissionGranted: boolean = true;
  @State private hasShownPermissionMissingToast: boolean = false;
  @State private isCalendarSyncProcessing: boolean = false;
  @State private calendarSyncProcessingText: string = '';
  private toggleFlowRunning: boolean = false;
  private pendingProgrammaticSwitchValue: boolean | null = null;
  private pageInfos: NavPathStack = new NavPathStack();
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private readonly preferencesUtil: PreferencesUtil = preferencesUtil;
  private readonly calendarSyncStorageKey: string = 'calendarSyncEnabled';
  private readonly preferenceStoreName: string = 'todayStore';

  aboutToAppear(): void {
    this.hasShownPermissionMissingToast = false;
    this.pendingProgrammaticSwitchValue = null;
    this.refreshLocalCalendarSyncMetaState();
    void this.syncLocalCalendarSyncState();
  }

  private handleCloseClick(): void {
    if (this.isCalendarSyncProcessing) {
      this.showCalendarSyncProcessingToast();
      return;
    }
    if (this.onBack) {
      this.onBack();
      return;
    }
    this.pageInfos.pop(1);
  }

  private async syncLocalCalendarSyncState(): Promise<void> {
    await this.refreshLocalCalendarSyncState();
    await this.refreshCalendarPermissionState();
    this.maybeShowPermissionMissingToast();
  }

  private refreshLocalCalendarSyncMetaState(): void {
    this.localCalendarSyncPermissionGranted = this.calendarSyncPermissionGranted;
  }

  private onCalendarSyncPermissionPropChanged(): void {
    this.localCalendarSyncPermissionGranted = this.calendarSyncPermissionGranted;
    this.maybeShowPermissionMissingToast();
  }

  private async refreshLocalCalendarSyncState(): Promise<void> {
    const preferenceValue: boolean | null = await this.readCalendarSyncEnabledPreference();
    if (preferenceValue === true || preferenceValue === false) {
      this.applyLocalCalendarSyncEnabled(preferenceValue);
      AppStorage.setOrCreate(this.calendarSyncStorageKey, preferenceValue);
      return;
    }

    const storageValue: boolean | undefined = AppStorage.get(this.calendarSyncStorageKey) as boolean | undefined;
    if (storageValue === true || storageValue === false) {
      this.applyLocalCalendarSyncEnabled(storageValue);
      return;
    }
    this.applyLocalCalendarSyncEnabled(this.calendarSyncEnabled);
  }

  private async handleCalendarSyncToggle(isOn: boolean): Promise<void> {
    if (this.toggleFlowRunning) {
      return;
    }
    this.pendingProgrammaticSwitchValue = null;
    this.localCalendarSyncEnabled = isOn;
    this.isCalendarSyncProcessing = true;
    this.calendarSyncProcessingText = isOn
      ? '正在写入系统日历，请勿退出页面。'
      : '正在删除系统日历事件，请勿退出页面。';
    this.toggleFlowRunning = true;
    try {
      if (this.onCalendarSyncToggle) {
        await this.onCalendarSyncToggle(isOn);
      } else {
        await this.handleCalendarSyncToggleFallback(isOn);
      }
    } finally {
      this.refreshLocalCalendarSyncMetaState();
      await this.syncLocalCalendarSyncState();
      this.isCalendarSyncProcessing = false;
      this.calendarSyncProcessingText = '';
      this.toggleFlowRunning = false;
    }
  }

  private applyLocalCalendarSyncEnabled(nextValue: boolean): void {
    if (this.localCalendarSyncEnabled === nextValue) {
      return;
    }
    if (this.toggleFlowRunning) {
      this.pendingProgrammaticSwitchValue = nextValue;
    }
    this.localCalendarSyncEnabled = nextValue;
  }

  private async handleCalendarResyncCopyClick(): Promise<void> {
    if (this.isCalendarSyncProcessing) {
      this.showCalendarSyncProcessingToast();
      return;
    }

    this.isCalendarSyncProcessing = true;
    this.calendarSyncProcessingText = '正在重同步日历事件';
    try {
      if (this.onCalendarResyncCopyClick) {
        await this.onCalendarResyncCopyClick();
      } else {
        await this.handleCalendarResyncFallback();
      }
    } finally {
      this.refreshLocalCalendarSyncMetaState();
      await this.syncLocalCalendarSyncState();
      this.isCalendarSyncProcessing = false;
      this.calendarSyncProcessingText = '';
    }
  }

  private async handleCalendarPermissionRecoverClick(): Promise<void> {
    if (this.onCalendarPermissionRecoverClick) {
      await this.onCalendarPermissionRecoverClick();
      this.refreshLocalCalendarSyncMetaState();
      await this.syncLocalCalendarSyncState();
      return;
    }
    await this.handleCalendarPermissionRecoverFallback();
    await this.syncLocalCalendarSyncState();
  }

  private async handleCalendarSyncToggleFallback(isOn: boolean): Promise<void> {
    if (isOn) {
      const granted: boolean = await this.ensureCalendarSyncPermissions();
      if (!granted) {
        return;
      }
      AppStorage.setOrCreate(this.calendarSyncStorageKey, true);
      await this.persistCalendarSyncEnabledPreference(true);
      await this.runBootstrapAllHistory();
      return;
    }

    AppStorage.setOrCreate(this.calendarSyncStorageKey, false);
    await this.persistCalendarSyncEnabledPreference(false);
    const cleanupSuccess: boolean = await this.cleanupCalendarSyncedEvents();
    if (cleanupSuccess) {
      promptAction.openToast({
        message: '系统日历同步已关闭，并已清理同步事件。',
        duration: 1500
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing cleanup success toast');
      });
      return;
    }
    promptAction.openToast({
      message: '系统日历同步已关闭，部分同步事件清理失败。',
      duration: 1500
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error showing cleanup failed toast');
    });
  }

  private async handleCalendarResyncFallback(): Promise<void> {
    const granted: boolean = await this.ensureCalendarSyncPermissions();
    if (!granted) {
      return;
    }

    try {
      const result = await calendarSyncService.resyncMappedEventCopy();
      if (result.total <= 0) {
        promptAction.openToast({
          message: '暂无可重同步的日历事件。',
          duration: 1200
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error showing empty resync toast');
        });
        return;
      }
      if (result.success === result.total) {
        promptAction.openToast({
          message: `已完成文案重同步 ${result.success} 条。`,
          duration: 1200
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error showing resync success toast');
        });
        return;
      }
      promptAction.openToast({
        message: `文案重同步完成 ${result.success}/${result.total} 条。`,
        duration: 1500
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing resync partial toast');
      });
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar copy resync fallback failed: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '日历文案重同步失败，请稍后重试。',
        duration: 1500
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing resync failure toast');
      });
    }
  }

  private async handleCalendarPermissionRecoverFallback(): Promise<void> {
    const granted: boolean = await this.ensureCalendarSyncPermissions();
    if (!granted) {
      this.localCalendarSyncPermissionGranted = false;
      promptAction.openToast({
        message: '尚未获得日历权限，请在系统设置中授权后重试。',
        duration: 1800
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing calendar recover denied toast');
      });
      return;
    }
    this.localCalendarSyncPermissionGranted = true;
    try {
      const nowMs: number = Date.now();
      const recentStartMs: number = this.resolveCalendarSyncRecentStartMs(nowMs);
      const reconcileCount: number = await calendarSyncService.reconcilePending();
      const rebuildResult = await calendarSyncService.rebuildMissingMappings(recentStartMs, nowMs, 200);
      const successCount: number = reconcileCount + rebuildResult.success;
      promptAction.openToast({
        message: `权限已恢复，已补同步 ${successCount} 条。`,
        duration: 1500
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing calendar recover success toast');
      });
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar permission recover fallback failed: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '权限已恢复，但补同步失败，请稍后重试。',
        duration: 1500
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing calendar recover failed toast');
      });
    }
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
      const grantedAll: boolean = authResults.length === missingPermissions.length &&
        authResults.every((value: number) => value === 0);
      if (grantedAll) {
        return true;
      }
      promptAction.openToast({
        message: '需要日历权限才能开启同步，请在系统设置中授权。',
        duration: 1800
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing calendar permission denied toast');
      });
      return false;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `CalendarSync: request permission failed: ${JSON.stringify(err)}`);
      promptAction.openToast({
        message: '请求日历权限失败，请稍后重试。',
        duration: 1800
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing calendar permission request failed toast');
      });
      return false;
    }
  }

  private async runBootstrapAllHistory(): Promise<void> {
    try {
      const nowMs: number = Date.now();
      const recentStartMs: number = this.resolveCalendarSyncRecentStartMs(nowMs);
      const result = await calendarSyncService.bootstrapClosedRecords(recentStartMs, nowMs);
      if (result.total <= 0) {
        promptAction.openToast({
          message: '系统日历同步已开启，最近7天暂无可初始化记录。',
          duration: 1200
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error showing bootstrap empty toast');
        });
        return;
      }
      if (result.success === result.total) {
        promptAction.openToast({
          message: `系统日历同步已开启，已同步最近7天 ${result.success} 条。`,
          duration: 1200
        }).catch(() => {
          hilog.error(0x0000, TAG, 'error showing bootstrap success toast');
        });
        return;
      }
      promptAction.openToast({
        message: `系统日历同步已开启，已同步最近7天 ${result.success}/${result.total} 条。`,
        duration: 1500
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing bootstrap partial toast');
      });
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar bootstrap fallback failed: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '系统日历同步已开启，但初始化同步失败。',
        duration: 1500
      }).catch(() => {
        hilog.error(0x0000, TAG, 'error showing bootstrap failure toast');
      });
    }
  }

  private async cleanupCalendarSyncedEvents(): Promise<boolean> {
    try {
      return await calendarSyncService.cleanupAllMappedEvents();
    } catch (error) {
      hilog.error(0x0000, TAG, `calendar cleanup fallback failed: ${JSON.stringify(error)}`);
      return false;
    }
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

  private async refreshCalendarPermissionState(): Promise<void> {
    if (!this.localCalendarSyncEnabled) {
      this.localCalendarSyncPermissionGranted = true;
      return;
    }
    const granted: boolean = await this.checkCalendarSyncPermissionsGranted();
    this.localCalendarSyncPermissionGranted = granted;
  }

  private resolveCalendarSyncSecondaryText(): string {
    if (!this.localCalendarSyncEnabled) {
      return '开启后自动同步已完成记录';
    }
    if (!this.localCalendarSyncPermissionGranted) {
      return '已开启，但未获得日历权限，同步已暂停';
    }
    return '已开启，已初始化同步近7天数据';
  }

  private maybeShowPermissionMissingToast(): void {
    if (!this.localCalendarSyncEnabled || this.localCalendarSyncPermissionGranted || this.hasShownPermissionMissingToast) {
      return;
    }
    this.hasShownPermissionMissingToast = true;
    promptAction.openToast({
      message: '日历权限未授权，同步已暂停，请点击授权恢复。',
      duration: 1800
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error showing calendar permission missing reminder toast');
    });
  }

  private showCalendarSyncProcessingToast(): void {
    promptAction.openToast({
      message: '系统日历同步处理中，请勿退出页面。',
      duration: 1200
    }).catch(() => {
      hilog.error(0x0000, TAG, 'error showing calendar processing toast');
    });
  }

  private resolveCalendarSyncRecentStartMs(endMs: number): number {
    const safeEndMs: number = Math.max(0, endMs);
    return Math.max(0, safeEndMs - CALENDAR_SYNC_RECENT_DAYS * CALENDAR_SYNC_DAY_MS);
  }

  private async ensurePreferencesReady(): Promise<boolean> {
    if (this.preferencesUtil.isInitialized()) {
      return true;
    }

    let abilityContext: Context | undefined;
    try {
      abilityContext = AppStorage.get('context') as Context;
    } catch (error) {
      hilog.warn(0x0000, TAG, `CalendarSync: unable to read context for preferences init: ${JSON.stringify(error)}`);
    }

    if (!abilityContext) {
      return false;
    }

    try {
      await this.preferencesUtil.init(abilityContext, this.preferenceStoreName, true);
      return this.preferencesUtil.isInitialized();
    } catch (error) {
      hilog.error(0x0000, TAG, `CalendarSync: preferences init failed in fallback: ${JSON.stringify(error)}`);
      return false;
    }
  }

  private async readCalendarSyncEnabledPreference(): Promise<boolean | null> {
    const ready: boolean = await this.ensurePreferencesReady();
    if (!ready) {
      return null;
    }

    const preferenceStore = this.preferencesUtil.getPreferences();
    if (!preferenceStore) {
      return null;
    }

    try {
      const storedValue = preferenceStore.getSync(PreferenceKeys.CALENDAR_SYNC_ENABLED, false);
      return !!storedValue;
    } catch (error) {
      hilog.error(0x0000, TAG, `CalendarSync: read enabled preference failed in fallback: ${JSON.stringify(error)}`);
      return null;
    }
  }

  private async persistCalendarSyncEnabledPreference(value: boolean): Promise<void> {
    const ready: boolean = await this.ensurePreferencesReady();
    if (!ready) {
      hilog.warn(0x0000, TAG, 'CalendarSync: preferences unavailable when persisting enabled state in fallback');
      return;
    }

    const preferenceStore = this.preferencesUtil.getPreferences();
    if (!preferenceStore) {
      hilog.warn(0x0000, TAG, 'CalendarSync: preference store missing when persisting enabled state in fallback');
      return;
    }

    try {
      preferenceStore.putSync(PreferenceKeys.CALENDAR_SYNC_ENABLED, value);
      if (this.preferencesUtil.requiresManualFlush()) {
        this.preferencesUtil.flush();
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `CalendarSync: persist enabled preference failed in fallback: ${JSON.stringify(error)}`);
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          Row() {
            Button({ type: ButtonType.Circle }) {
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

            Text('系统日历同步')
              .fontWeight(700)
              .fontSize(26)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
          .padding({ top: 16, bottom: 16 })

          List({ space: 0 }) {
            ListItem() {
              HdsListItemCard({
                cardBackgroundColor: Color.Transparent,
                cardPrefixMargin: $r('app.string.card_margin'),
                cardSuffixMargin: $r('app.string.card_margin'),
                prefixItem: new PrefixIcon({
                  iconSize: IconSize.SYSTEM_ICON,
                  iconValue: {
                    symbol: $r('sys.symbol.calendar_badge_clock')
                  },
                }),
                textItem: {
                  primaryText: {
                    text: '同步到系统日历'
                  },
                  secondaryText: {
                    text: this.resolveCalendarSyncSecondaryText()
                  }
                },
                suffixItem: new SuffixSwitch({
                  isCheck: this.localCalendarSyncEnabled,
                  selectColor: $r('app.color.primary'),
                  onChange: (isOn: boolean) => {
                    if (this.isCalendarSyncProcessing) {
                      this.showCalendarSyncProcessingToast();
                      return;
                    }
                    if (this.pendingProgrammaticSwitchValue !== null &&
                      isOn === this.pendingProgrammaticSwitchValue) {
                      this.pendingProgrammaticSwitchValue = null;
                      return;
                    }
                    if (isOn === this.localCalendarSyncEnabled) {
                      return;
                    }
                    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                    void this.handleCalendarSyncToggle(isOn);
                  },
                })
              })
            }
            .borderRadius(
              this.localCalendarSyncEnabled
                ? { topLeft: 16, topRight: 16 }
                : {
                topLeft: 16,
                topRight: 16,
                bottomLeft: 16,
                bottomRight: 16
              }
            )
            .backgroundColor($r('app.color.bg_card'))

            if (this.localCalendarSyncEnabled) {
              ListItem() {
                Stack({ alignContent: Alignment.End }) {
                  HdsListItemCard({
                    cardBackgroundColor: Color.Transparent,
                    cardPrefixMargin: $r('app.string.card_margin'),
                    cardSuffixMargin: $r('app.string.card_margin'),
                    prefixItem: new PrefixIcon({
                      iconSize: IconSize.SYSTEM_ICON,
                      iconValue: {
                        symbol: $r('sys.symbol.arrow_clockwise')
                      },
                    }),
                    textItem: {
                      primaryText: {
                        text: '重同步日历事件'
                      },
                      description: {
                        text: '刷新历史已同步事件文案'
                      }
                    }
                  })

                  Button({ type: ButtonType.Circle, stateEffect: true }) {
                    SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                      .fontSize(18)
                      .fontWeight(600)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .width(40)
                  .height(40)
                  .margin({ right: 12 })
                  .backgroundColor($r('app.color.neutral_100'))
                .onClick(() => {
                  if (this.isCalendarSyncProcessing) {
                    this.showCalendarSyncProcessingToast();
                    return;
                  }
                  void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
                  void this.handleCalendarResyncCopyClick();
                })
                }
              }
              .borderRadius({ bottomLeft: 16, bottomRight: 16 })
              .backgroundColor($r('app.color.bg_card'))
            }
          }
          .width('100%')
          .scrollBar(BarState.Off)

          Column({ space: 5 }) {
            Text('* 请勿频繁开启或关闭系统日历同步，写入系统日历需要一定时间，频繁操作可能导致同步延迟。')
              .fontSize(14)
              .lineHeight(20)
              .fontWeight(FontWeight.Normal)
              .textAlign(TextAlign.Center)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .margin({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 14, right: 14, bottom: 15 })
        .backgroundColor($r('app.color.bg_main'))

        if (this.isCalendarSyncProcessing) {
          Column() {
            Column({ space: 8 }) {
              LoadingProgress()
                .width(36)
                .height(36)
              Text(this.calendarSyncProcessingText)
                .fontSize(14)
                .fontWeight(600)
                .textAlign(TextAlign.Center)
                .fontColor($r('app.color.text_primary'))
              Text('请勿退出当前页面')
                .fontSize(12)
                .fontWeight(FontWeight.Normal)
                .textAlign(TextAlign.Center)
                .fontColor($r('app.color.text_secondary'))
            }
            .padding({
              left: 20,
              right: 20,
              top: 18,
              bottom: 18
            })
            .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
            .borderRadius(14)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#33000000')
        }
      }
    }
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
    })
    .onBackPressed((): boolean => {
      if (this.isCalendarSyncProcessing) {
        this.showCalendarSyncProcessingToast();
        return true;
      }
      this.handleCloseClick();
      return true;
    })
    .hideTitleBar(true)
    .systemTransition(REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
  }
}
