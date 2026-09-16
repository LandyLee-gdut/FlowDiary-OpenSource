import dayjs from 'dayjs'
import {
  StorageKeys,
  AppShadows,
  LabelSummaryModel,
  VibratorUtil,
  ColorModeUtil,
  COLOR_MODE_STORAGE_KEY,
  TimeRecordUtil,
  AppGradients,
  buildPointLightEffect
} from 'base'
import { CalendarDayPanel } from './CalendarDayPanel'
import { curves } from '@kit.ArkUI'
import {
  HmCalendarSelectedDay,
  HmCalendarType,
  HmCalendarItem,
  ViewDateState,
  computeMonthSwipe,
  loadCalendarItems
} from '../model/CalendarModel'
import { hdsEffect } from '@kit.UIDesignKit'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { HistoricalActivityData, historicalDayService } from '../model/HistoricalDayService'

@Component
export struct HmCalendar {
  // week labels
  private weeks: ResourceStr[] = [
    $r('app.string.hm_calendar_sunday'),
    $r('app.string.hm_calendar_monday'),
    $r('app.string.hm_calendar_tuesday'),
    $r('app.string.hm_calendar_wednesday'),
    $r('app.string.hm_calendar_thursday'),
    $r('app.string.hm_calendar_friday'),
    $r('app.string.hm_calendar_saturday'),
  ]
  // default selected text
  private text: ResourceStr = $r('app.string.hm_calendar_clocked')
  // default selected color
  private color: ResourceColor = $r('app.color.hm_calendar_color')
  // default date format rule
  private format: string = 'YYYY-MM-DD'
  // selected day from parent component
  @Prop @Watch('requestRefresh') selectedDays: HmCalendarSelectedDay[] = []
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State isDarkTheme: boolean = false;
  // Shared date selection state via AppStorage
  @StorageLink(StorageKeys.SELECTED_DATE) @Watch('requestRefresh') selectedDate: number = dayjs().date();
  @StorageLink(StorageKeys.SELECTED_MONTH)  selectedMonth: number = dayjs().month() + 1;
  @StorageLink(StorageKeys.SELECTED_YEAR) selectedYear: number = dayjs().year();
  @StorageLink(StorageKeys.VIEW_DATE) @Watch('requestRefresh') viewDate: number = dayjs().date();
  @StorageLink(StorageKeys.VIEW_MONTH) @Watch('requestRefresh') viewMonth: number = dayjs().month() + 1;
  @StorageLink(StorageKeys.VIEW_YEAR) @Watch('requestRefresh') viewYear: number = dayjs().year();
  private vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  
  // Expanded day detail state
  @State isExpanded: boolean = false;
  @State expandedIndex: number = -1;
  @State expandedItem: HmCalendarItem | null = null;
  @State selectedDateString: string = '';
  @State selectedDayText: string = '';  // Day number text (e.g., "15日")
  @State selectedYearMonthText: string = '';  // Year-month text (e.g., "2025年12月")
  @State selectedDateGeometryId: string = '';  // Geometry ID for day number
  @State selectedYearMonthGeometryId: string = 'year-month-label';  // Geometry ID for year-month label
  @State selectedLabelSummaries: LabelSummaryModel[] = [];
  @State selectedActivities: HistoricalActivityData[] = [];
  @State selectedTotalDuration: number = 0;
  @State isDetailLoading: boolean = false;
  
  // Circle data for DataPanel
  @State selectedCircleValues: number[] = [];
  @State selectedCircleColors: LinearGradient[] = [];
  @State selectedCircleTotalValue: number = 1;

  // Optional callback functions for parent component
  onClickDate?: (date: string) => void
  onChangeMonth?: (month: string) => void
  // calendar type
  type: HmCalendarType = HmCalendarType.MONTH
  // calendar gutter
  gutter: number = 4
  @State items: HmCalendarItem[] = []
  private panOption: PanGestureOptions = new PanGestureOptions({
    direction: PanDirection.Left | PanDirection.Right,
    fingers: 1,
    distance: 12
  })
  private readonly swipeThreshold: number = 30
  private hasAppeared: boolean = false
  // Coalesce multiple watcher triggers into a single refresh pass
  private refreshQueued: boolean = false
  // Track whether another refresh was requested while the current one is queued/running
  private refreshDirty: boolean = false

  onColorModeChange(): void {
    this.syncColorModeState();
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private getViewState(): ViewDateState {
    return {
      viewYear: this.viewYear,
      viewMonth: this.viewMonth,
      viewDate: this.viewDate
    }
  }

  private isSelectedDay(item: HmCalendarItem): boolean {
    return item.year === this.selectedYear &&
      item.month === this.selectedMonth &&
      item.date === this.selectedDate;
  }

  private isMonthAtOrAfterCurrent(year: number, month: number, currentYear: number, currentMonth: number): boolean {
    return year > currentYear || (year === currentYear && month >= currentMonth)
  }

  private isMonthAfterCurrent(year: number, month: number, currentYear: number, currentMonth: number): boolean {
    return year > currentYear || (year === currentYear && month > currentMonth)
  }

  private async refreshItems(): Promise<void> {
    try {
      this.items = await loadCalendarItems({
        viewState: this.getViewState(),
        selectedDays: this.selectedDays || [],
        type: this.type,
        format: this.format,
        defaultText: this.text,
        defaultColor: this.color
      })
    } catch (error) {
      console.error('MiniCalendar: Failed to load calendar items', error)
      this.items = []
    }
  }

  private handleMonthSwipe(isNext: boolean): void {
    const today = dayjs()
    const currentYear = today.year()
    const currentMonth = today.month() + 1

    if (isNext && this.isMonthAtOrAfterCurrent(this.viewYear, this.viewMonth, currentYear, currentMonth)) {
      return
    }

    const swipeResult = computeMonthSwipe(this.getViewState(), isNext, this.format)

    if (isNext && this.isMonthAfterCurrent(swipeResult.viewYear, swipeResult.viewMonth, currentYear, currentMonth)) {
      return
    }

    this.viewYear = swipeResult.viewYear
    this.viewMonth = swipeResult.viewMonth
    this.viewDate = swipeResult.viewDate

    if (this.onChangeMonth) {
      this.onChangeMonth(swipeResult.monthString)
      VibratorUtil.getInstance().triggerHaptic('haptic.effect.sharp')
    }
    if (this.onClickDate) {
      this.onClickDate(swipeResult.dateString)
    }
  }

  /**
   * Handle long press on a calendar day to show expanded detail
   */
  private onDayLongPressed(item: HmCalendarItem, index: number): void {
    // Build geometry transition ids
    const dateGeometryId = `date-text-${item.year}-${item.month}-${item.date}`;
    
    // Update shared storage values (same as onClick for consistency)
    this.selectedYear = item.year;
    this.selectedMonth = item.month;
    this.selectedDate = item.date;
    this.viewYear = item.year;
    this.viewMonth = item.month;
    this.viewDate = item.date;
    
    // Notify parent component (same as onClick for consistency)
    const date = `${item.year}-${item.month.toString().padStart(2, '0')}-${item.date.toString().padStart(2, '0')}`;
    this.onClickDate && this.onClickDate(date);
    this.onChangeMonth && this.onChangeMonth(`${item.year}-${item.month.toString().padStart(2, '0')}`);
    
    // Set initial state for expanded view
    this.expandedItem = item;
    this.expandedIndex = index;
    this.selectedDateGeometryId = dateGeometryId;
    this.selectedDayText = `${item.date}日`;
    this.selectedYearMonthText = `${item.year}年${item.month}月`;
    this.selectedDateString = `${item.year}年${item.month}月${item.date}日`;
    this.selectedLabelSummaries = item.labelSummaryData || [];
    this.isDetailLoading = true;
    
    // Pre-compute circle data from current item for immediate display
    this.updateCircleDataFromSummaries(this.selectedLabelSummaries);
    
    // Trigger haptic feedback
    this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'physicalFeedback');
    
    // Trigger expansion with animation
    this.getUIContext()?.animateTo({
      duration: 350,
      curve: Curve.Friction
    }, () => {
      this.isExpanded = true;
    });
    
    // Load full data asynchronously
    this.loadDayDetail(item);
  }

  /**
   * Load detailed data for the selected day
   */
  private async loadDayDetail(item: HmCalendarItem): Promise<void> {
    try {
      const dateMs = dayjs(`${item.year}-${item.month}-${item.date}`).valueOf();
      const snapshot = await historicalDayService.getDaySnapshot(dateMs);
      this.selectedLabelSummaries = snapshot.labelSummaries;
      this.selectedActivities = snapshot.activities;
      this.selectedTotalDuration = snapshot.totalDurationMinutes;
      this.selectedDateString = snapshot.dateString;
      this.updateCircleDataFromSummaries(snapshot.labelSummaries);
      this.isDetailLoading = false;
    } catch (error) {
      console.error('MiniCalendar: Failed to load day detail', error);
      this.isDetailLoading = false;
    }
  }

  /**
   * Update circle data panel values from label summaries
   */
  private updateCircleDataFromSummaries(summaries: LabelSummaryModel[]): void {
    if (summaries && summaries.length > 0) {
      this.selectedCircleValues = summaries.map((item: LabelSummaryModel): number => item.totalMinutes);
      this.selectedCircleColors = summaries.map((item: LabelSummaryModel): LinearGradient =>
        AppGradients.getGradientForColor(item.labelColor)
      );
      this.selectedCircleTotalValue = this.selectedCircleValues.reduce((sum: number, val: number): number => sum + val, 0) || 1;
    } else {
      this.selectedCircleValues = [];
      this.selectedCircleColors = [];
      this.selectedCircleTotalValue = 1;
    }
  }

  /**
   * Close the expanded detail view
   */
  private closeExpandedDetail(): void {
    this.getUIContext()?.animateTo({
      duration: 350,
      curve: Curve.Friction
    }, () => {
      this.isExpanded = false;
    });
    
    // Reset state after animation
    setTimeout(() => {
      this.expandedItem = null;
      this.expandedIndex = -1;
      this.selectedActivities = [];
      this.selectedLabelSummaries = [];
    }, 400);
  }

  /**
   * Get tag color with fallback
   */
  private getTagColor(color: ResourceColor | string | null | undefined): ResourceColor {
    if (!color) {
      return '#9CA3AF';
    }
    return color as ResourceColor;
  }

  /**
   * Builder for legend item in the detail view
   */
  @Builder
  LegendItem(item: LabelSummaryModel) {
    Row({ space: 8 }) {
      Circle()
        .width(10)
        .height(10)
        .fill(this.getTagColor(item.labelColor))
      Text(item.labelName)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Text(TimeRecordUtil.formatDurationForMinutes(item.totalMinutes))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
  }

  /**
   * Builder for activity row in the detail view
   */
  @Builder
  ActivityRow(item: HistoricalActivityData) {
    Row() {
      Row({ space: 10 }) {
        Circle()
          .width(10)
          .height(10)
          .fill(this.getTagColor(item.tagColorHex))
        Column({ space: 2 }) {
          Text(item.activityName || '未命名活动')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.tagName || '未分配')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .layoutWeight(1)

      Text(TimeRecordUtil.formatDurationForMinutes(item.totalDurationMinutes))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.primary_lighter'))
        .borderRadius(12)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding(12)
    .backgroundColor($r('app.color.bg_main'))
    .borderRadius(12)
    .shadow(AppShadows.CARD_RESTING)
  }

  /**
   * Builder for expanded day detail content
   */
  @Builder
  ExpandedDayDetailContent() {
    Column() {
      // Header with dual geometry transition targets
      Row() {
        // Left side: Title text (no geometry transition)
        Text('日期详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -20 }))
              .animation({ curve: curves.springMotion(0.6, 0.9), duration: 350, delay: 100 }),
            TransitionEffect.OPACITY.animation({ duration: 150 })
          ))
        
        Blank()
        
        // Right side: Year-month and day texts with geometry transitions
        Row({ space: 4 }) {
          // Year-month text (from header badge)
          Text(this.selectedYearMonthText)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.badge_warning_text'))
            .geometryTransition(this.selectedYearMonthGeometryId, { follow: true })
            .transition(TransitionEffect.OPACITY.animation({ duration: 350, curve: Curve.Friction }))
          
          // Day text (from calendar grid)
          Text(this.selectedDayText)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.badge_primary_text'))
            .geometryTransition(this.selectedDateGeometryId, { follow: true })
            .transition(TransitionEffect.OPACITY.animation({ duration: 350, curve: Curve.Friction }))
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.badge_date_bg'))
        .borderRadius(16)
        
        // Close button
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontColor([$r('app.color.text_primary')])
            .fontSize(16)
        }
        .width(32)
        .height(32)
        .backgroundColor($r('app.color.neutral_100'))
        .margin({ left: 12 })
        .onClick(() => {
          this.closeExpandedDetail();
        })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.8, y: 0.8 }))
            .animation({ curve: curves.springMotion(0.6, 0.9), duration: 350, delay: 100 }),
          TransitionEffect.OPACITY.animation({ duration: 150 })
        ))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 16 })
      .margin({ bottom: 10 })
      
      // Circle Data Panel and Legend - Left-Right Layout
      if (this.selectedCircleValues.length > 0) {
        Row() {
          // Left side: Circle DataPanel
          Column() {
            DataPanel({ values: this.selectedCircleValues, max: this.selectedCircleTotalValue, type: DataPanelType.Circle })
              .width(120)
              .height(120)
              .valueColors(this.selectedCircleColors)
              .strokeWidth(15)
              .trackBackgroundColor($r('app.color.neutral_200'))
              .closeEffect(true)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          
          // Right side: Legend items list
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.selectedLabelSummaries, (item: LabelSummaryModel) => {
                Row() {
                  this.LegendItem(item)
                }
                .width('100%')
                .justifyContent(FlexAlign.Start)
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
          }
          // .height('100%')
          .align(Alignment.Center)
          .scrollBar(BarState.Off)
          .nestedScroll({
            scrollForward: NestedScrollMode.SELF_FIRST,
            scrollBackward: NestedScrollMode.SELF_FIRST
          })
          .friction(0.9)
          .layoutWeight(1)
          .height(120)
          .padding(5)
          .margin({ left: 16 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 30 }))
            .animation({ curve: curves.springMotion(0.6, 0.9), duration: 350, delay: 50 }),
          TransitionEffect.OPACITY.animation({ duration: 150 })
        ))
      } else if (!this.isDetailLoading) {
        Text('暂无数据')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .padding({ top: 20, bottom: 20 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }

      // Divider
      Divider()
        .strokeWidth(1)
        .color($r('app.color.neutral_200'))
        .margin({left: 16, right: 16, top: 5, bottom: 10})
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, delay: 100 }))

      // Activity list
      if (this.isDetailLoading) {
        // Column() {
        //   LoadingProgress().width(40).height(40)
        //   Text('加载中...')
        //     .fontSize(14)
        //     .fontColor($r('app.color.text_secondary'))
        //     .margin({ top: 12 })
        // }
        // .justifyContent(FlexAlign.Center)
        // .alignItems(HorizontalAlign.Center)
        // .width('100%')
        // .layoutWeight(1)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            // Activity list header with total duration
            Row() {
              Text('活动记录')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              
              Blank()
              
              // Total duration display
              Text(`总时长：${TimeRecordUtil.formatDurationForMinutes(this.selectedTotalDuration)}`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.selectedActivities && this.selectedActivities.length > 0) {
              ForEach(this.selectedActivities, (item: HistoricalActivityData) => {
                this.ActivityRow(item)
              })
            } else {
              Column() {
                Text('暂无活动记录')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
              }
              .padding({ top: 20, bottom: 20 })
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
        }
        .height('100%')
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .nestedScroll({
          scrollForward: NestedScrollMode.SELF_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
        .friction(0.9)
        .layoutWeight(1)
        .align(Alignment.Top) // 解决 Scroll 子组件无法顶部对齐的问题
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 50 }))
            .animation({ curve: curves.springMotion(0.6, 0.9), duration: 350, delay: 150 }),
          TransitionEffect.OPACITY.animation({ duration: 150 })
        ))
      }
    }
    .width('100%')
    .height('80%')
    // .backgroundColor($r('app.color.bg_card'))
    .backgroundBlurStyle(this.isDarkTheme ? BlurStyle.BACKGROUND_THIN : BlurStyle.COMPONENT_ULTRA_THIN)
    .borderRadius(15)
    .shadow(AppShadows.CARD_INTERACTIVE)
    .clip(true)
  }

  async aboutToAppear() {
    this.syncColorModeState();
    this.hasAppeared = true
    await this.refreshItems()
    if (this.refreshDirty) {
      this.refreshDirty = false
      this.requestRefresh()
    }
  }

  requestRefresh(): void {
    if (!this.hasAppeared) {
      this.refreshDirty = true
      return
    }

    if (this.refreshQueued) {
      this.refreshDirty = true
      return
    }

    this.refreshQueued = true
    this.refreshDirty = false
    Promise.resolve().then(async () => {
      try {
        await this.refreshItems()
      } finally {
        this.refreshQueued = false
        if (this.refreshDirty) {
          this.refreshDirty = false
          this.requestRefresh()
        }
      }
    })
  }

  build() {
    if (this.type === HmCalendarType.MONTH || this.type === HmCalendarType.WEEK) {
      if (!this.isExpanded) {
        Column() {
          Row() {
            Column() {
              Text($r('app.string.month_panel_subtitle'))
                .fontColor($r('app.color.primary'))
                .fontSize(16)
                .fontWeight(600)
            }
            .alignItems(HorizontalAlign.Start)

            Column() {
              Text(`${this.viewYear}年${this.viewMonth}月`)
                .fontColor($r('app.color.badge_warning_text'))
                .fontSize(14)
                .fontWeight(600)
                // Geometry transition for year-month label
                .geometryTransition('year-month-label', { follow: true })
                .transition(TransitionEffect.OPACITY.animation({ duration: 350, curve: Curve.Friction }))
            }
            .backgroundColor($r('app.color.badge_date_bg'))
            .borderRadius('50%')
            .padding({left: 10, right: 10, top: 5, bottom: 5})
          }
          .padding({left: 15, right: 15})
          .margin({bottom: 10})
          .justifyContent(FlexAlign.SpaceBetween)
          .width('100%')
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -20 }))
            .animation({ duration: 350, curve: Curve.Friction }))

          GridRow({ columns: 7 }) {
            ForEach(this.weeks, (label: string) => {
              GridCol() {
                Text(label)
                  .fontSize(13)
                  .height(20)
                  .fontWeight(400)
                  .fontColor($r('app.color.text_tertiary'))
                  .textAlign(TextAlign.Center)
              }
            })
            ForEach(this.items, (item: HmCalendarItem, index: number) => {
              GridCol() {
                Column() {
                  Stack({ alignContent: Alignment.Center }) {
                    // Date number display with geometry transition
                    Row() {
                      Text(item.date.toString())
                        // .lineHeight(this.isSelectedDay(item) ? 16 : 12)
                        .fontSize(this.isSelectedDay(item) ? 16 : 12)
                        .fontWeight(600)
                        .fontColor(item.inMonth ? (this.isSelectedDay(item) ? $r('app.color.primary') : $r('app.color.text_secondary')) : $r('app.color.text_tertiary'))
                        .textAlign(TextAlign.Center)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        // Add geometry transition for the date text
                        .geometryTransition(`date-text-${item.year}-${item.month}-${item.date}`, { follow: true })
                        .transition(TransitionEffect.OPACITY.animation({ duration: 350, curve: Curve.Friction }))
                    }
                    .width(35)
                    .height(35)
                    .alignItems(VerticalAlign.Center)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(item.inMonth ? $r('app.color.bg_page') : $r('app.color.bg_main'))
                    .shadow(AppShadows.SUBTLE)
                    .visualEffect(buildPointLightEffect({
                      preset: 'selection',
                      color: $r('app.color.immersive_glow_primary'),
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
                      isActive: this.isSelectedDay(item),
                      isDarkTheme: this.isDarkTheme,
                      overrides: {
                        height: 90
                      }
                    }))
                    .borderRadius('50%')
                    if (item.inMonth && item.labelSummaryData.length > 0) {
                      CalendarDayPanel({ summaryData: item.labelSummaryData })
                        .width(45)
                        .height(45)
                    }
                  }
                  .width(45)
                  .height(45)
                  // Long press gesture to expand detail
                  .gesture(
                    LongPressGesture({ repeat: false, duration: 400 })
                      .onAction(() => {
                        if (item.inMonth) {
                          this.onDayLongPressed(item, index);
                        }
                      })
                  )
                }
                .clickEffect({level: ClickEffectLevel.MIDDLE, scale: 0.7})
                .onClick(() => {
                  const today = dayjs()
                  const currentYear = today.year()
                  const currentMonth = today.month() + 1

                  if (this.viewYear === currentYear && this.viewMonth === currentMonth &&
                  this.isMonthAfterCurrent(item.year, item.month, currentYear, currentMonth)) {
                    return
                  }

                  const date = `${item.year}-${item.month.toString().padStart(2, '0')}-${item.date.toString()
                    .padStart(2, '0')}`
                  // Update shared storage values
                  this.selectedYear = item.year;
                  this.selectedMonth = item.month;
                  this.selectedDate = item.date;
                  this.viewYear = item.year;
                  this.viewMonth = item.month;
                  this.viewDate = item.date;
                  // Notify parent component
                  this.onClickDate && this.onClickDate(date)
                  this.onChangeMonth && this.onChangeMonth(`${item.year}-${item.month.toString().padStart(2, '0')}`)
                  this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'physicalFeedback');
                })
              }
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({x: .5, y: .5})).animation({ curve: curves.springMotion(.6, .6), duration: 30, delay: 10 * index}))
            }, (item: HmCalendarItem) => {
              return `${item.year}-${item.month}-${item.date}`;
            })
          }
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 }))
            .animation({ duration: 350, curve: Curve.Friction,  }))
          // Calendar grid or expanded detail
        }
        .gesture(
          PanGesture(this.panOption)
            .onActionEnd((event: GestureEvent) => {
              if (!event || this.isExpanded) {
                return;
              }

              if (event.offsetX <= -this.swipeThreshold) {
                this.handleMonthSwipe(true);

              } else if (event.offsetX >= this.swipeThreshold) {
                this.handleMonthSwipe(false);
              }
            })
        )
        .visualEffect(buildPointLightEffect({
          preset: 'selection',
          color: $r('app.color.immersive_glow_primary'),
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
          isActive: false,
          isDarkTheme: this.isDarkTheme
        }))
        .borderRadius(15)
        .padding({ top: 15, bottom: 10, left: 5, right: 5 })
        .height($r('app.float.reflect_calendar_collapsed_height'))
        .backgroundColor($r('app.color.bg_card'))
      } else {
        // Expanded detail view
        this.ExpandedDayDetailContent()
      }


    }
  }
}
