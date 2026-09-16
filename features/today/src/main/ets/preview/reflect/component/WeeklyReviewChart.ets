import { hilog } from '@kit.PerformanceAnalysisKit'
import { McBarChart, Options, chartInterface } from '@mcui/mccharts'
import { TimeRecordUtil, StorageKeys, ColorModeUtil, COLOR_MODE_STORAGE_KEY } from 'base'
import { ConfigurationConstant } from '@kit.AbilityKit'
import dayjs from 'dayjs'
import { ReflectModel, CalendarDaySummary } from '../model/ReflectModel'

const TAG: string = 'WeeklyReviewChart'
const DAY_IN_MS: number = 24 * 60 * 60 * 1000
const WEEKDAY_LABELS: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
const BAR_BASE_COLORS: string[] = ['#dbeafe', '#dbeafe', '#dbeafe', '#dbeafe', '#dbeafe', '#dbeafe', '#dbeafe']
const BAR_FOCUS_COLOR: string = '#296DFF'
const BAR_NEUTRAL_COLOR: string = '#e5e7eb'
const CARD_BACKGROUND: string = '#fff'
const CARD_BORDER: string = '#ffffff99'
const DARK_BAR_BASE_COLORS: string[] = ['#3755A3', '#3755A3', '#3755A3', '#3755A3', '#3755A3', '#3755A3', '#3755A3']
const DARK_BAR_FOCUS_COLOR: string = '#82A6FF'
const DARK_BAR_NEUTRAL_COLOR: string = '#1f2937'
const DARK_CARD_BACKGROUND: string = '#111827'
const DARK_X_AXIS_LABEL_COLOR: string = '#E5E7EB'
const DARK_Y_AXIS_LABEL_COLOR: string = '#94A3B8'
const DARK_BAR_LABEL_COLOR: string = '#F9FAFB'

function formatMinutesValue(rawValue: number): string {
  const numericValue: number = typeof rawValue === 'number' ? rawValue : Number(rawValue ?? 0)
  if (!numericValue || numericValue <= 0) {
    return '0m'
  }
  return TimeRecordUtil.formatDurationForMinutes(numericValue)
}

const formatBarLabel = (params: chartInterface.InterfaceObj): string => {
  return formatMinutesValue(params?.value)
}

interface FormattedSeries {
  value: number,
  color: string,
  name?: string
}
interface WeeklyBarData {
  dayStartMs: number;
  label: string;
  dayLabel: string;
  totalMinutes: number;
  color: string;
  isFocus: boolean;
}
const X_AXIS_LABEL_COLOR: string = '#4b5563'
const X_AXIS_LABEL_FONT_SIZE: number = 40
const X_AXIS_LABEL_MARGIN: number = 0

const Y_AXIS_LABEL_COLOR: string = '#9ca3af'
const Y_AXIS_LABEL_FONT_SIZE: number = 0

interface GeneratedTypeLiteralInterface_1 {
  dayStart: number;
  weekStart: number;
  selectionKey: string;
}

@Component
export struct WeeklyReviewChart {
  @Consume('reflectModel') private reflectModel: ReflectModel = new ReflectModel();
  @State private chartOptions: Options = this.createChartOptions(this.buildInitialChartData())
  @State private darkChartOptions: Options = this.createDarkChartOptions(this.buildInitialChartData())
  @State private chartData: WeeklyBarData[] = this.buildInitialChartData()
  @State private maxMinutes: number = 0
  @State badgeText: string = ''
  @StorageLink(StorageKeys.SELECTED_DATE) @Watch('handleSelectionChange') selectedDate: number = dayjs().date()
  @StorageLink(StorageKeys.SELECTED_MONTH) @Watch('handleSelectionChange') selectedMonth: number = dayjs().month() + 1
  @StorageLink(StorageKeys.SELECTED_YEAR) @Watch('handleSelectionChange') selectedYear: number = dayjs().year()
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  @State private isDarkTheme: boolean = false

  private selectionReloadTimer?: number
  private isInitialLoadDone: boolean = false
  private isLoadingWeek: boolean = false
  private pendingSelectionReload: boolean = false
  private pendingForceReload: boolean = false
  private lastSelectionKey?: string
  private lastLoadedWeekStart?: number

  aboutToAppear(): void {
    this.syncColorModeState()
    void this.syncSelectedDateAndReload()
  }

  aboutToDisappear(): void {
    if (this.selectionReloadTimer !== undefined) {
      clearTimeout(this.selectionReloadTimer)
      this.selectionReloadTimer = undefined
    }
  }

  private onColorModeChange(): void {
    this.syncColorModeState()
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode)
  }

  private handleSelectionChange(): void {
    this.scheduleSelectionSync()
  }

  private scheduleSelectionSync(): void {
    if (this.selectionReloadTimer !== undefined) {
      clearTimeout(this.selectionReloadTimer)
    }
    this.selectionReloadTimer = setTimeout(() => {
      this.selectionReloadTimer = undefined
      void this.syncSelectedDateAndReload()
    }, 0)
  }

  private async syncSelectedDateAndReload(forceReload: boolean = false): Promise<void> {
    if (this.isLoadingWeek) {
      this.pendingSelectionReload = true
      return
    }

    const selectionInfo = this.resolveSelectionInfo()
    if (!selectionInfo) {
      if (!this.isInitialLoadDone) {
        this.isLoadingWeek = true
        this.pendingSelectionReload = false
        try {
          await this.loadWeekDataFor(TimeRecordUtil.getDayStart(Date.now()), forceReload)
          this.isInitialLoadDone = true
        } finally {
          this.isLoadingWeek = false
          if (this.pendingSelectionReload) {
            this.pendingSelectionReload = false
            this.syncSelectedDateAndReload()
          }
        }
      }
      return
    }

    const dayStart = selectionInfo.dayStart;
    const weekStart = selectionInfo.weekStart;
    const selectionKey = selectionInfo.selectionKey;

    if (!forceReload && this.isInitialLoadDone && this.lastSelectionKey === selectionKey && this.lastLoadedWeekStart === weekStart) {
      return
    }

    this.isLoadingWeek = true
    this.pendingSelectionReload = false
    this.pendingForceReload = false
    try {
      await this.loadWeekDataFor(dayStart, forceReload)
      this.lastSelectionKey = selectionKey
      this.lastLoadedWeekStart = weekStart
      this.isInitialLoadDone = true
    } finally {
      this.isLoadingWeek = false
      if (this.pendingSelectionReload) {
        this.pendingSelectionReload = false
        const shouldForceReload = this.pendingForceReload
        this.pendingForceReload = false
        await this.syncSelectedDateAndReload(shouldForceReload)
      }
    }
  }

  private resolveSelectionInfo(): GeneratedTypeLiteralInterface_1 | undefined {
    if (!this.selectedYear || !this.selectedMonth || !this.selectedDate) {
      return undefined
    }

    const baseDate = new Date(this.selectedYear, this.selectedMonth - 1, this.selectedDate)
    if (baseDate.getFullYear() !== this.selectedYear || baseDate.getMonth() + 1 !== this.selectedMonth || baseDate.getDate() !== this.selectedDate) {
      return undefined
    }

    const dayStart = TimeRecordUtil.getDayStart(baseDate.getTime())
    const weekStart = this.getWeekStart(dayStart)
    const selectionKey = `${baseDate.getFullYear()}-${this.pad(baseDate.getMonth() + 1)}-${this.pad(baseDate.getDate())}`

    return { dayStart, weekStart, selectionKey }
  }

  private pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`
  }

  private async loadWeekDataFor(anchorDayStart: number, forceReload: boolean = false): Promise<void> {
    try {
      const focusDayStart = TimeRecordUtil.getDayStart(anchorDayStart)
      const weekStart = this.getWeekStart(focusDayStart)
      const weekEnd = weekStart + 7 * DAY_IN_MS

      const daySummaries = await this.reflectModel.getCalendarDaySummaries(weekStart, weekEnd, forceReload)
      const weeklyTotals = this.mapSummariesToWeek(daySummaries, weekStart)
      const chartData = this.buildChartData(weeklyTotals, weekStart, focusDayStart)
      const maxMinutes = chartData.reduce((max, item) => Math.max(max, item.totalMinutes), 0)

      this.chartData = chartData
      this.maxMinutes = maxMinutes
      this.badgeText = maxMinutes > 0 ? `最高 ${TimeRecordUtil.formatDurationForMinutes(maxMinutes)}` : ''

      const formattedSeries = chartData.map(item => ({
        value: item.totalMinutes,
        color: item.color,
        name: `${item.label} ${item.dayLabel}`
      } as FormattedSeries))
      const darkFormattedSeries = this.buildDarkSeries(chartData)

      this.chartOptions.setVal({
        xAxis: this.buildXAxisOptions(chartData),
        yAxis: this.buildYAxisOptions(maxMinutes),
        series: [
          {
            name: '每日总时长',
            barStyle: {
              borderRadius: [10, 10],
              width: 30
            },
            backgroundBar: {
              show: true
            },
            label: {
              show: true,
              position: 'top',
              color: '#1f2937',
              fontSize: 35,
              FontWeight: 1000,
              formatter: formatBarLabel
            },
            data: formattedSeries
          }
        ]
      })
      this.darkChartOptions.setVal({
        xAxis: this.buildDarkXAxisOptions(chartData),
        yAxis: this.buildDarkYAxisOptions(maxMinutes),
        series: [
          {
            name: '每日总时长',
            barStyle: {
              borderRadius: [10, 10],
              width: 30
            },
            backgroundBar: {
              show: true,
              color: DARK_BAR_NEUTRAL_COLOR
            },
            label: {
              show: true,
              position: 'top',
              color: DARK_BAR_LABEL_COLOR,
              fontSize: 35,
              FontWeight: 1000,
              formatter: formatBarLabel
            },
            data: darkFormattedSeries
          }
        ]
      })

      this.lastLoadedWeekStart = weekStart
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to load weekly data: ${JSON.stringify(error)}`)
    }
  }

  private getWeekStart(timestamp: number): number {
    const dayStart = TimeRecordUtil.getDayStart(timestamp)
    const date = new Date(dayStart)
    const dayOfWeek = date.getDay()
    const offsetToMonday = (dayOfWeek + 6) % 7
    date.setHours(0, 0, 0, 0)
    date.setDate(date.getDate() - offsetToMonday)
    return date.getTime()
  }

  private mapSummariesToWeek(daySummaries: Array<CalendarDaySummary>, weekStart: number): number[] {
    const dailyTotalsMs: number[] = new Array(7).fill(0)

    if (daySummaries && daySummaries.length > 0) {
      daySummaries.forEach(summary => {
        const bucketIndex = Math.floor((summary.dayStartMs - weekStart) / DAY_IN_MS)
        if (bucketIndex >= 0 && bucketIndex < dailyTotalsMs.length) {
          dailyTotalsMs[bucketIndex] += summary.totalDurationMs
        }
      })
    }

    return dailyTotalsMs
  }

  private buildChartData(dailyTotalsMs: number[], weekStart: number, focusDayStart: number): WeeklyBarData[] {
    return dailyTotalsMs.map((totalMs: number, index: number) => {
      const dayStart = weekStart + index * DAY_IN_MS
      const totalMinutes = Math.round(totalMs / 60000)
      const displayDate = new Date(dayStart)
      const dayLabel = `${displayDate.getDate()}日`
      const isFocus = dayStart === focusDayStart
      const color = this.resolveBarColor(index, totalMinutes, isFocus)

      return {
        dayStartMs: dayStart,
        label: WEEKDAY_LABELS[index],
        dayLabel,
        totalMinutes,
        color,
        isFocus
      } as WeeklyBarData
    })
  }

  private resolveBarColor(index: number, totalMinutes: number, isFocus: boolean): string {
    if (isFocus) {
      return BAR_FOCUS_COLOR
    }
    if (totalMinutes <= 0) {
      return BAR_NEUTRAL_COLOR
    }
    const paletteIndex = Math.min(index, BAR_BASE_COLORS.length - 1)
    return BAR_BASE_COLORS[paletteIndex]
  }

  private resolveDarkBarColor(index: number, totalMinutes: number, isFocus: boolean): string {
    if (isFocus) {
      return DARK_BAR_FOCUS_COLOR
    }
    if (totalMinutes <= 0) {
      return DARK_BAR_NEUTRAL_COLOR
    }
    const paletteIndex = Math.min(index, DARK_BAR_BASE_COLORS.length - 1)
    return DARK_BAR_BASE_COLORS[paletteIndex]
  }

  private computeYAxisMax(maxMinutes: number): number | undefined {
    if (maxMinutes <= 0) {
      return 60
    }
    const step = maxMinutes <= 120 ? 30 : 60
    return Math.ceil(maxMinutes / step) * step
  }

  private buildInitialChartData(): WeeklyBarData[] {
    return WEEKDAY_LABELS.map((label: string) => ({
      dayStartMs: 0,
      label,
      dayLabel: '--日',
      totalMinutes: 0,
      color: BAR_NEUTRAL_COLOR,
      isFocus: false
    } as WeeklyBarData))
  }

  private createChartOptions(data: WeeklyBarData[]): Options {
    return new Options({
      title: {
        show: false,
      },
      legend: {
        show: false
      },
      xAxis: this.buildXAxisOptions(data),
      yAxis: this.buildYAxisOptions(0),
      grid: {
        containLabel: true, // Ensures labels are not cut off
        bottom: 24,
        top: 20,
        left: 12,
        right: 12,
      },
      tooltip: {
        show: false
      },
      series: [
        {
          barStyle: {
            borderRadius: [8, 8],
            width: 30
          },
          backgroundBar: {
            show: false
          },
          label: {
            show: true,
            position: 'top',
            color: '#1f2937',
            fontSize: 25,
            formatter: formatBarLabel
          },
          data: data.map(item => ({
            value: item.totalMinutes,
            color: item.color,
            name: `${item.label} ${item.dayLabel}`
          } as FormattedSeries))
        }
      ]
    })
  }

  private createDarkChartOptions(data: WeeklyBarData[]): Options {
    return new Options({
      title: {
        show: false,
      },
      legend: {
        show: false
      },
      xAxis: this.buildDarkXAxisOptions(data),
      yAxis: this.buildDarkYAxisOptions(0),
      grid: {
        containLabel: true,
        bottom: 24,
        top: 20,
        left: 12,
        right: 12,
      },
      tooltip: {
        show: false
      },
      series: [
        {
          barStyle: {
            borderRadius: [8, 8],
            width: 30
          },
          backgroundBar: {
            show: false
          },
          label: {
            show: true,
            position: 'top',
            color: DARK_BAR_LABEL_COLOR,
            fontSize: 25,
            formatter: formatBarLabel
          },
          data: this.buildDarkSeries(data)
        }
      ]
    })
  }

  private buildDarkSeries(data: WeeklyBarData[]): FormattedSeries[] {
    return data.map((item, index) => ({
      value: item.totalMinutes,
      color: this.resolveDarkBarColor(index, item.totalMinutes, item.isFocus),
      name: `${item.label} ${item.dayLabel}`
    } as FormattedSeries))
  }

  private buildXAxisOptions(data: WeeklyBarData[]): chartInterface.InterfaceObj {
    return {
      data: data.map(item => item.label),

      axisLine: {
        show: false
      },
      axisTick: {
        show: false
      },
      splitLine: {
        show: false
      },
      axisLabel: this.buildXAxisLabelStyle()
    }
  }

  private buildYAxisOptions(maxMinutes: number): chartInterface.InterfaceObj {
    return {
      max: this.computeYAxisMax(maxMinutes),
      axisLine: {
        show: false
      },
      axisTick: {
        show: false
      },
      splitLine: {
        show: false
      },
      axisLabel: this.buildYAxisLabelStyle()
    }
  }

  private buildXAxisLabelStyle(): chartInterface.InterfaceObj {
    return {
      show: true,
      color: X_AXIS_LABEL_COLOR,
      fontSize: X_AXIS_LABEL_FONT_SIZE,
      FontWeight: 1000,
      margin: X_AXIS_LABEL_MARGIN
    }
  }

  private buildYAxisLabelStyle(): chartInterface.InterfaceObj {
    return {
      color: Y_AXIS_LABEL_COLOR,
      fontSize: Y_AXIS_LABEL_FONT_SIZE
    }
  }

  private buildDarkXAxisOptions(data: WeeklyBarData[]): chartInterface.InterfaceObj {
    return {
      data: data.map(item => item.label),
      axisLine: {
        show: false
      },
      axisTick: {
        show: false
      },
      splitLine: {
        show: false
      },
      axisLabel: this.buildDarkXAxisLabelStyle()
    }
  }

  private buildDarkYAxisOptions(maxMinutes: number): chartInterface.InterfaceObj {
    return {
      max: this.computeYAxisMax(maxMinutes),
      axisLine: {
        show: false
      },
      axisTick: {
        show: false
      },
      splitLine: {
        show: false
      },
      axisLabel: this.buildDarkYAxisLabelStyle()
    }
  }

  private buildDarkXAxisLabelStyle(): chartInterface.InterfaceObj {
    return {
      show: true,
      color: DARK_X_AXIS_LABEL_COLOR,
      fontSize: X_AXIS_LABEL_FONT_SIZE,
      FontWeight: 1000,
      margin: X_AXIS_LABEL_MARGIN
    }
  }

  private buildDarkYAxisLabelStyle(): chartInterface.InterfaceObj {
    return {
      color: DARK_Y_AXIS_LABEL_COLOR,
      fontSize: Y_AXIS_LABEL_FONT_SIZE
    }
  }

  @Builder
  private lightChart(): void {
    Row() {
      McBarChart({
        options: this.chartOptions
      })
        .height('85%')
    }
    .width('100%')
  }

  @Builder
  private darkChart(): void {
    Row() {
      McBarChart({
        options: this.darkChartOptions
      })
        .height('85%')
    }
    .width('100%')
  }

  build() {
      Column() {
        Row() {
          Column() {
            Text('周度')
              .fontColor($r('app.color.primary'))
              .fontSize(16)
              .fontWeight(600)
          }
          .alignItems(HorizontalAlign.Start)

          if (this.maxMinutes > 0) {
            Row() {
              Text(this.badgeText)
                .fontColor($r('app.color.warning'))
                .fontSize(14)
                .fontWeight(600)
            }
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.accent_lighter'))
              .borderRadius(16)
          }
        }
        .padding({left: 15, right: 15})
        .margin({bottom: 10})
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
        .height(30)

        Column() {
          if (this.isDarkTheme) {
            this.darkChart()
          } else {
            this.lightChart()
          }
        }
        .width('100%')
      }
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(15)
      .width('100%')
      .shadow(this.isDarkTheme ? {
        radius: 40,
        color: '#66000000'
      } : {
        radius: 40,
        color: '#33000000'
      })
      .padding({ top: 10, bottom: 10, left: 5, right: 5 })

  }
}
