import { HmCalendar } from '../component/MiniCalendar';
import { HmCalendarSelectedDay } from '../model/CalendarModel';
import {
  StorageKeys,
  AppShadows,
  VibratorUtil,
  ColorModeUtil,
  COLOR_MODE_STORAGE_KEY,
  RDBStoreUtil,
  reflectChartPreferenceService,
  ReflectChartIds,
  ReflectChartSettingItem
} from 'base'
import { DateTitleBar } from '../component/DateTitleBar'
import dayjs from 'dayjs';
import { ComponentContent, LengthMetrics, promptAction, PromptAction } from '@kit.ArkUI';
import { curves } from '@kit.ArkUI';
import { WeeklyReviewChart } from '../component/WeeklyReviewChart';
import { TagTrendChart } from '../component/TagTrendChart';
import { TagTimeBarChart } from '../component/TagTimeBarChart';
import { DayReviewChart } from '../component/DayReviewChart';
import { DayTimeline } from '../component/DayTimeline';
import { TimelineCard, TimelineExpandAnimationProperties, TimelineExpandPage, refreshTimelineNode } from '../component/TimelineTransition';
import { ReflectModel } from '../model/ReflectModel';
import { HdsNavigation, ScrollEffectType, HdsNavigationAttribute, HdsNavDestinationAttribute, HdsNavigationTitleMode,
  HdsNavDestination,
  hdsEffect,
  TextStyleMode,
  hdsMaterial} from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// import { reflectRefreshCoordinator } from '../utils/ReflectRefreshCoordinator';

@Builder
function customRefreshingContent() {
  Stack() {
    Row() {
      LoadingProgress().height(32)
    }
    .alignItems(VerticalAlign.Center)
  }
  .align(Alignment.Center)
  .clip(true)
  // 设置最小高度约束保证自定义组件高度随刷新区域高度变化时自定义组件高度不会低于minHeight。
  .constraintSize({ minHeight: 32 })
  .width("100%")
}


@Builder
export function ReflectBuilder() {
  Reflect();
}

@Component
export struct Reflect {
  private static readonly DEFAULT_TAB_BAR_BOTTOM_MARGIN: number = 75;
  private static readonly FLOATING_MINI_BAR_BOTTOM_MARGIN: number = 90;

  // Use shared storage for date selection
  @StorageLink(StorageKeys.SELECTED_DATE) @Watch('handleFocusDateChange') selectedDate: number = dayjs().date();
  @StorageLink(StorageKeys.SELECTED_MONTH) @Watch('handleFocusDateChange') selectedMonth: number = dayjs().month() + 1;
  @StorageLink(StorageKeys.SELECTED_YEAR) @Watch('handleFocusDateChange') selectedYear: number = dayjs().year();
  @StorageLink(StorageKeys.REFLECT_REFRESH_REVISION) refreshRevision: number = 0;
  @StorageLink(StorageKeys.REFLECT_CHART_SETTINGS_REVISION) @Watch('handleChartSettingsRevisionChange') chartSettingsRevision: number = 0;
  @StorageLink('chartHeight') chartHeight: number = 300
  @Consume('pageInfos') pageInfos: NavPathStack;
  @Provide('reflectModel') reflectModel: ReflectModel = new ReflectModel();
  // @StorageLink(StorageKeys.REFLECT_DATA_REVISION) reflectDataRevision: number = 0
  scroller: Scroller = new Scroller();
  /**
   * Get current date string from storage values
   */
  private getCurrentDateString(): string {
    return `${this.selectedYear}-${this.selectedMonth.toString().padStart(2, '0')}-${this.selectedDate.toString().padStart(2, '0')}`;
  }
  @State controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  @State isRefreshing: boolean = false;
  @State maxRefreshingHeight: number = 100.0;
  @State ratio: number = 1;
  @State refreshing: boolean = false;
  @State refreshOffset: number = 0;
  @State refreshState: RefreshStatus = RefreshStatus.Inactive;
  @State visibleChartItems: ReflectChartSettingItem[] = [];
  @State flowCardGalleryVisible: boolean = true;
  @State flowCardComponentVisible: boolean = false;
  @State flowCardEffect: VisualEffect | undefined = undefined;
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink('useFloatingActionBar') useFloatingActionBar: boolean = false;
  @StorageLink('activeMainTabIndex') @Watch('onVisibilityGateChanged') activeMainTabIndex: number = 1;
  @StorageLink('userGuideSheetVisible') @Watch('onVisibilityGateChanged') userGuideSheetVisible: boolean = false;
  @StorageLink('reflectPageVisible') reflectPageVisible: boolean = false;
  @State isDarkTheme: boolean = false;
  private contentNode?: ComponentContent<Object> = undefined;
  @State private timelineAnimationProperties: TimelineExpandAnimationProperties | null = null;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private pageLifecycleVisible: boolean = false;

  aboutToAppear(): void {
    this.pageLifecycleVisible = true;
    this.syncReflectVisibilityGate('about_to_appear');
    this.syncColorModeState();
    let uiContext = this.getUIContext();
    this.contentNode = new ComponentContent(uiContext, wrapBuilder(customRefreshingContent));
    // 初始化震动工具
    void this.vibratorUtil.initialize();
    if (!this.timelineAnimationProperties && uiContext) {
      this.timelineAnimationProperties = new TimelineExpandAnimationProperties(uiContext);
    }
    if (AppStorage.get(StorageKeys.REFLECT_REFRESH_REVISION) === undefined) {
      AppStorage.setOrCreate(StorageKeys.REFLECT_REFRESH_REVISION, 0);
    }
    if (AppStorage.get(StorageKeys.REFLECT_CALENDAR_REVISION) === undefined) {
      AppStorage.setOrCreate(StorageKeys.REFLECT_CALENDAR_REVISION, 0);
    }
    if (AppStorage.get(StorageKeys.REFLECT_CHART_SETTINGS_REVISION) === undefined) {
      AppStorage.setOrCreate(StorageKeys.REFLECT_CHART_SETTINGS_REVISION, 0);
    }
    this.reloadVisibleChartItems();
    void this.reflectModel.refreshAll();
    this.updateFlowCardEffect();
  }

  aboutToDisappear(): void {
    this.pageLifecycleVisible = false;
    this.syncReflectVisibilityGate('about_to_disappear');
  }

  onPageShow(): void {
    this.pageLifecycleVisible = true;
    this.syncReflectVisibilityGate('on_page_show');
  }

  onPageHide(): void {
    this.pageLifecycleVisible = false;
    this.syncReflectVisibilityGate('on_page_hide');
    this.refreshing = false;
    this.refreshState = RefreshStatus.Done;
  }

  onColorModeChange(): void {
    this.syncColorModeState();
    refreshTimelineNode();
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private onVisibilityGateChanged(): void {
    this.syncReflectVisibilityGate('gate_changed');
  }

  private syncReflectVisibilityGate(source: string): void {
    const pageVisible = this.pageLifecycleVisible &&
      this.activeMainTabIndex === 0 &&
      !this.userGuideSheetVisible;
    this.reflectPageVisible = pageVisible;
    AppStorage.setOrCreate('reflectPageVisible', pageVisible);
    if (!pageVisible && this.refreshState !== RefreshStatus.Inactive) {
      this.refreshing = false;
      this.refreshState = RefreshStatus.Done;
    }
    hilog.info(0x0000, 'Reflect',
      `[Reflect] syncReflectVisibilityGate(${source}) -> visible=${pageVisible}, tab=${this.activeMainTabIndex}, guideVisible=${this.userGuideSheetVisible}`);
    this.updateFlowCardEffect();
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

  @Builder titleBuilder() {
    Column() {
      Row() {
        Column() {
          Text('回顾')
            .textAlign(TextAlign.Start)
            .fontWeight(700)
            .fontSize(28)
        }
        DateTitleBar({
          onDateChange: (dateString: string) => this.handleSelectDate(dateString),
          onMonthChange: (monthString: string) => this.handleMonthChange(monthString)
        })
          .height('100%')
          .width(100)
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
      .width('100%')
    }
    .height(40)
    .margin({
      top: '12vp',
      bottom: '12vp'
    })
  }

  private reloadVisibleChartItems(): void {
    this.flowCardGalleryVisible = reflectChartPreferenceService.isFlowCardGalleryVisible();
    this.visibleChartItems = reflectChartPreferenceService.loadSettings().items
      .filter((item: ReflectChartSettingItem) => item.visible)
      .sort((left: ReflectChartSettingItem, right: ReflectChartSettingItem) => left.order - right.order);
    this.updateFlowCardEffect();
  }

  private shouldRunRefreshAnimation(): boolean {
    const numericState = this.refreshState as number;
    return numericState >= 1 && numericState < 4;
  }

  private shouldRunFlowCardShader(): boolean {
    return this.flowCardGalleryVisible &&
      this.reflectPageVisible &&
      this.flowCardComponentVisible;
  }

  private resetFlowCardEffect(): void {
    this.flowCardEffect = new hdsEffect.HdsEffectBuilder()
      .pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT
      })
      .buildEffect();
  }

  private buildFlowCardEffect(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT
      })
      .shaderEffect({
        effectType: hdsEffect.EffectType.UV_BACKGROUND_FLOW_LIGHT,
        animation: {
          duration: 5000,
          iterations: -1,
          autoPlay: true,
          onFinish: () => {
            console.info('Reflect flow card shader finished');
          },
        },
        params: {
          colorSource: [$r('app.color.sky_clear'), $r('app.color.accent_light'), $r('app.color.data_viz_1'), $r('app.color.sky_sunset_gold_light')],
          colorTarget: [$r('app.color.primary_lighter'), $r('app.color.accent_lighter'), $r('app.color.data_viz_1_light'), $r('app.color.warning')]
        },
        controller: this.controller,
      })
      .buildEffect();
  }

  private updateFlowCardEffect(): void {
    if (!this.shouldRunFlowCardShader()) {
      this.resetFlowCardEffect();
      this.controller = new hdsEffect.ShaderEffectController();
      return;
    }
    this.controller = new hdsEffect.ShaderEffectController();
    this.flowCardEffect = this.buildFlowCardEffect();
  }

  private resolveChartBottomMargin(index: number): number {
    if (index !== this.visibleChartItems.length - 1) {
      return 18;
    }
    return this.useFloatingActionBar ? Reflect.FLOATING_MINI_BAR_BOTTOM_MARGIN :
      Reflect.DEFAULT_TAB_BAR_BOTTOM_MARGIN;
  }

  @Builder
  private buildConfiguredChartItem(item: ReflectChartSettingItem, index: number): void {
    if (item.chartId === ReflectChartIds.TIMELINE) {
      if (this.timelineAnimationProperties) {
        TimelineCard({ animationProperties: this.timelineAnimationProperties })
          .margin({ bottom: this.resolveChartBottomMargin(index) })
          .width('100%')
          .animation({ curve: curves.springMotion(), duration: 150 })
          .clickEffect({ level: ClickEffectLevel.HEAVY, scale: .8 })
      } else {
        DayTimeline()
          .margin({ bottom: this.resolveChartBottomMargin(index) })
          .width('100%')
          .animation({ curve: curves.springMotion(), duration: 150 })
      }
    } else if (item.chartId === ReflectChartIds.DAY_REVIEW) {
      DayReviewChart()
        .margin({ bottom: this.resolveChartBottomMargin(index) })
        .animation({ curve: curves.springMotion(), duration: 150 })
    } else if (item.chartId === ReflectChartIds.TAG_TREND) {
      TagTrendChart()
        .margin({ bottom: this.resolveChartBottomMargin(index) })
        .animation({ curve: curves.springMotion(), duration: 150 })
    } else if (item.chartId === ReflectChartIds.TAG_TIME_BAR) {
      TagTimeBarChart()
        .margin({ bottom: this.resolveChartBottomMargin(index) })
        .animation({ curve: curves.springMotion(), duration: 150 })
    } else if (item.chartId === ReflectChartIds.WEEKLY_REVIEW) {
      WeeklyReviewChart()
        .height(250)
        .margin({ bottom: this.resolveChartBottomMargin(index) })
        .animation({ curve: curves.springMotion(), duration: 150 })
    }
  }

  @Builder
  private buildConfiguredCharts(): void {
    ForEach(this.visibleChartItems, (item: ReflectChartSettingItem, index: number) => {
      this.buildConfiguredChartItem(item, index);
    }, (item: ReflectChartSettingItem) => item.chartId)
  }

  build(): void {
    if (canIUse("SystemCapability.UIDesign.HDSComponent.Core")) {
      HdsNavDestination() {
        Stack({ alignContent: Alignment.Top }) {
          Refresh({ refreshing: $$this.refreshing, builder: this.refreshBuilder() }) {
            Scroll() {
              Column() {

                if (this.flowCardGalleryVisible) {
                  Stack(){
                    Row() {
                      Row({space: 10}) {
                        SymbolGlyph($r('sys.symbol.picture_2'))
                          .fontSize(22)
                          .fontColor([$r('app.color.text_primary')])
                        Column({space: 5}) {
                          Text('回顾画廊')
                            .fontSize(18)
                            .fontWeight(700)
                            .fontColor($r('app.color.primary'))

                          Text('通过滑动卡片进行"沉浸式"回顾')
                            .fontSize(14)
                            .fontColor($r('app.color.text_secondary'))
                        }
                        .alignItems(HorizontalAlign.Start)

                      }

                      Row() {
                        Column() {
                          SymbolGlyph($r('sys.symbol.arrow_right'))
                            .fontSize(22)
                            .fontColor([$r('app.color.text_primary')])
                        }
                      }
                    }
                    .borderRadius(15)
                    .width('100%')
                    .padding({left: 15, top: 10, right: 15, bottom: 10})
                    .justifyContent(FlexAlign.SpaceBetween)
                    .backgroundBlurStyle(this.isDarkTheme ? BlurStyle.BACKGROUND_REGULAR : BlurStyle.COMPONENT_ULTRA_THIN)
                  }
                  .clickEffect({ level: ClickEffectLevel.HEAVY, scale: 0.8})
                  .onClick(() => {
                    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
                    this.pageInfos.pushPathByName('ReflectFlowCardGallery', undefined);
                  })
                  .borderRadius(15)
                  .margin({ bottom: 18 })
                  .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE)
                  .visualEffect(this.flowCardEffect)
                  .onVisibleAreaChange([0, 1], (_isExpanding: boolean, currentRatio: number) => {
                    const nextVisible = currentRatio > 0;
                    if (this.flowCardComponentVisible === nextVisible) {
                      return;
                    }
                    this.flowCardComponentVisible = nextVisible;
                    this.updateFlowCardEffect();
                  })
                }

                HmCalendar({
                  selectedDays: this.buildSelectedDays(),
                  onClickDate: (date: string) => this.handleSelectDate(date),
                  onChangeMonth: (month: string) => this.handleMonthChange(month)
                })
                  .width('100%')
                  .borderRadius(15)
                  // .backgroundColor($r('app.color.bg_card'))
                  .margin({ bottom: 18 })
                  .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE)
                  .animation({ curve: curves.springMotion(), duration: 150 })

                this.buildConfiguredCharts()

                // Calendar with real data integration
              }
            }
            .width('100%')
            .align(Alignment.Top)
            .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal'), top: 105 })
            .scrollable(ScrollDirection.Vertical) // 滚动方向纵向
            .scrollBar(BarState.Off) // 滚动条常驻显示
            .friction(0.9)
            .edgeEffect(EdgeEffect.Spring)
            .height('100%')
          }
          .onOffsetChange((offset: number) => {
            this.refreshOffset = offset;
          })
          .onStateChange((state: RefreshStatus) => {
            this.refreshState = state;
          })
          .onRefreshing(async () => {
            console.info('Reflect Refresh onRefreshing callback triggered');
            await this.refreshReflectData();
            console.info('Reflect Refresh onRefreshing callback completed');
          })

          if (this.timelineAnimationProperties?.isExpandPageShow) {
            TimelineExpandPage({ animationProperties: this.timelineAnimationProperties })
          }
        }
        .clip(false)
        .enabled(this.timelineAnimationProperties?.isEnabled ?? true)
        .width('100%')
        .height('100%')
        .key('reflectTimelineRootStack')
      }
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
            mainTitle: '回顾',
          },
          menu: {
            value: [{
              content: {
                label: 'menuSetting',
                icon: $r('sys.symbol.picture_2'),
                isEnabled: true,
                action: () => {
                  void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
                  this.pageInfos.pushPathByName('ReflectFlowCardGallery', undefined);
                }
              }
            }]
          }
        }
      })
      .hideToolBar(true)
      .hideBackButton(true)
    } else {
      // Fallback for unsupported SystemCapability
    }
  }

  private buildSelectedDays(): HmCalendarSelectedDay[] {
    const selectedDays: HmCalendarSelectedDay[] = [];

    // Add currently selected date from storage
    const currentDateString = this.getCurrentDateString();
    const focusDay: HmCalendarSelectedDay = {
      date: currentDateString,
      backgroundColor: $r('app.color.primary') as ResourceColor,
      textColor: $r('app.color.bg_card') as ResourceColor
    };
    selectedDays.push(focusDay);

    return selectedDays;
  }

  private handleSelectDate(date: string): void {
    // Storage is already updated by MiniCalendar
    // This callback can be used for additional logic if needed
    console.info(`Date selected: ${date}`);
  }

  private handleMonthChange(month: string): void {
    // Storage is already updated by DateTitleBar
    // This callback can be used for additional logic if needed
    console.info(`Month changed to: ${month}`);
  }

  private handleFocusDateChange(): void {
    if (this.refreshing) {
      return;
    }
    void this.reflectModel.refreshAll();
  }

  private handleChartSettingsRevisionChange(): void {
    this.reloadVisibleChartItems();
  }

  private resolveTodayKey(): string {
    const now = new Date();
    return `${now.getFullYear()}-${this.pad(now.getMonth() + 1)}-${this.pad(now.getDate())}`;
  }

  private pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 刷新Reflect页面数据，将selected和View的日期月份与年份都重置回到当日
   */
  private async refreshReflectData(): Promise<void> {
    this.refreshing = true;
    try {
      // 获取当前日期
      const today = dayjs();
      const currentDate = today.date();
      const currentMonth = today.month() + 1; // dayjs的月份从0开始，需要+1
      const currentYear = today.year();
      
      // 重置selected日期相关状态
      this.selectedDate = currentDate;
      this.selectedMonth = currentMonth;
      this.selectedYear = currentYear;
      
      // 重置view日期相关状态
      AppStorage.setOrCreate(StorageKeys.VIEW_DATE, currentDate);
      AppStorage.setOrCreate(StorageKeys.VIEW_MONTH, currentMonth);
      AppStorage.setOrCreate(StorageKeys.VIEW_YEAR, currentYear);

      this.reflectModel.invalidateCaches();
      await this.reflectModel.refreshAll(true);
      this.refreshRevision += 1;
      
      // 显示刷新成功提示
      promptAction.openToast({
        message: '已重置到今日',
        duration: 1000
      });
      
      // 触发震动反馈
      const vibratorUtil = VibratorUtil.getInstance();
      await vibratorUtil.triggerHaptic('haptic.notice.success', 'notification');
    } catch (error) {
      console.error(`Error refreshing reflect data: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: '刷新失败，请稍后重试',
        duration: 1000
      });
      
      // 触发失败震动反馈
      const vibratorUtil = VibratorUtil.getInstance();
      await vibratorUtil.triggerHaptic('haptic.notice.fail', 'notification');
    } finally {
      this.refreshing = false;
      this.refreshState = RefreshStatus.Done;
    }
  }
}
