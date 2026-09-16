import dayjs from 'dayjs'
import { promptAction, curves } from '@kit.ArkUI'
import { StorageKeys, ColorModeUtil, COLOR_MODE_STORAGE_KEY, buildPointLightEffect } from 'base'
import { hdsEffect } from '@kit.UIDesignKit'
import { ReflectModel, ReflectTimelineSegment } from '../model/ReflectModel'
import { ConfigurationConstant } from '@kit.AbilityKit';
import type { FlowTimelineItem } from '../model/FlowEventModel'

const SECONDS_PER_HOUR: number = 60 * 60
const GRID_LIGHT_COLOR: ResourceColor = $r('app.color.timeline_grid_light')
const GRID_DARK_COLOR: ResourceColor = $r('app.color.timeline_grid_dark')
const MAJOR_DIVIDER_COLOR: ResourceColor = $r('app.color.timeline_major_divider')
const MINOR_DIVIDER_COLOR: ResourceColor = $r('app.color.timeline_minor_divider')
const GRID_BORDER_COLOR: ResourceColor = $r('app.color.timeline_grid_border')
const HOUR_INDICES: number[] = buildHourIndices()

// Inline Stream timeline chart (previously TimeLineChart.ets).
const STREAM_TIME_COLUMN_WIDTH: number = 55
const STREAM_AXIS_COLUMN_WIDTH: number = 24
const STREAM_DOT_SIZE: number = 14
const STREAM_DOT_SHADOW_RADIUS: number = 8
const STREAM_DOT_SHADOW_OFFSET_Y: number = 2
const STREAM_LINE_WIDTH: number = 2
const STREAM_LINE_TOP_OFFSET: number = 10
const STREAM_HEADER_BOTTOM_MARGIN: number = 12
const STREAM_MIN_ROW_HEIGHT: number = 56
const STREAM_HEIGHT_PER_MINUTE: number = 0.4
const STREAM_MAX_ROW_HEIGHT: number = 180
const STREAM_TIME_FONT_SIZE: number = 16
const STREAM_DURATION_FONT_SIZE: number = 12
const STREAM_TITLE_FONT_SIZE: number = 16
const STREAM_PRIMARY_TEXT_COLOR: ResourceColor = $r('app.color.text_primary')
const STREAM_SECONDARY_TEXT_COLOR: ResourceColor = $r('app.color.text_secondary')
const STREAM_TITLE_TEXT_COLOR: ResourceColor = $r('app.color.text_primary')
const STREAM_AXIS_LINE_COLOR: ResourceColor = $r('app.color.timeline_minor_divider')
const STREAM_DOT_STROKE_COLOR: ResourceColor = $r('app.color.bg_card')
const STREAM_DOT_SHADOW_ALPHA_LIGHT: string = '66'
const STREAM_DOT_SHADOW_ALPHA_DARK: string = '33'

interface HourGridCellStyle {
  backgroundColor: ResourceColor
  leftBorderWidth: number
  rightBorderWidth: number
  leftBorderColor: ResourceColor
  rightBorderColor: ResourceColor
}

interface HourGridCell {
  key: string
  style: HourGridCellStyle
  weight: number
}

function buildHourIndices(): number[] {
  const result: number[] = []
  let index = 0
  while (index < 24) {
    result.push(index)
    index += 1
  }
  return result
}

function resolveHourGridCellStyle(hourIndex: number, totalHours: number): HourGridCellStyle {
  const backgroundColor = hourIndex % 2 === 0 ? GRID_LIGHT_COLOR : GRID_DARK_COLOR
  const leftBorderWidth = hourIndex === 0 ? 1 : 0
  const rightBorderWidth = 1
  const rightBorderColor = ((hourIndex + 1) % 6 === 0 || hourIndex === totalHours - 1)
    ? MAJOR_DIVIDER_COLOR
    : MINOR_DIVIDER_COLOR

  return {
    backgroundColor,
    leftBorderWidth,
    rightBorderWidth,
    leftBorderColor: MAJOR_DIVIDER_COLOR,
    rightBorderColor
  }
}

const HOUR_GRID_CELLS: HourGridCell[] = buildHourGridCells(HOUR_INDICES)

function buildHourGridCells(hourIndices: number[]): HourGridCell[] {
  const totalHours = hourIndices.length
  const cells: HourGridCell[] = []
  for (let i = 0; i < totalHours; i++) {
    const style = resolveHourGridCellStyle(hourIndices[i], totalHours)
    const cell: HourGridCell = {
      key: `${hourIndices[i]}`,
      style,
      weight: SECONDS_PER_HOUR
    }
    cells.push(cell)
  }
  return cells
}


@Component
export struct DayTimeline {
  // Expanded mode renders the detailed chart within the same card.
  @Prop expanded: boolean = false
  @Consume('reflectModel') private reflectModel: ReflectModel = new ReflectModel()
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State isDarkTheme: boolean = false;
  private markers: string[] = ['00:00', '06:00', '12:00', '18:00', '24:00']
  @StorageLink(StorageKeys.SELECTED_DATE) @Watch('handleSelectionChange') selectedDate: number = dayjs().date()
  @StorageLink(StorageKeys.SELECTED_MONTH) @Watch('handleSelectionChange') selectedMonth: number = dayjs().month() + 1
  @StorageLink(StorageKeys.SELECTED_YEAR) @Watch('handleSelectionChange') selectedYear: number = dayjs().year()
  @StorageLink(StorageKeys.REFLECT_REFRESH_REVISION) @Watch('handleRefreshRevisionChange') refreshRevision: number = 0

  onColorModeChange(): void {
    this.syncColorModeState();
    void this.reflectModel.refreshStreamTimeline(this.isDarkTheme);
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  aboutToAppear(): void {
    this.syncColorModeState();
    void this.reflectModel.refreshDayBundle()
    void this.reflectModel.refreshStreamTimeline(this.isDarkTheme)
  }

  private handleSelectionChange(): void {
    void this.reflectModel.refreshDayBundle()
    void this.reflectModel.refreshStreamTimeline(this.isDarkTheme)
  }

  private handleRefreshRevisionChange(): void {
    void this.reflectModel.refreshDayBundle(undefined, true)
    void this.reflectModel.refreshStreamTimeline(this.isDarkTheme, true)
  }

  private resolveStreamRowHeight(durationMinutes: number): number {
    const scaled = STREAM_MIN_ROW_HEIGHT + durationMinutes * STREAM_HEIGHT_PER_MINUTE
    if (scaled > STREAM_MAX_ROW_HEIGHT) {
      return STREAM_MAX_ROW_HEIGHT
    }
    if (scaled < STREAM_MIN_ROW_HEIGHT) {
      return STREAM_MIN_ROW_HEIGHT
    }
    return scaled
  }

  private buildStreamRangeLabel(item: FlowTimelineItem): string {
    return `${item.time} - ${item.endLabel}`
  }

  private isStreamLastIndex(index: number, total: number): boolean {
    return index >= total - 1
  }

  build(): void {
    Column() {
      Column() {
        Row() {
          Column() {
            Text('时间轴')
              .fontColor($r('app.color.primary'))
              .fontSize(16)
              .fontWeight(600)
              .geometryTransition('timelineTitle', { follow: true })
              .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })
          }
          .alignItems(HorizontalAlign.Start)

          Row() {
            if (this.reflectModel.dayTimelineDateLabel) {
              Text(this.reflectModel.dayTimelineDateLabel)
                .fontColor($r('app.color.badge_warning_text'))
                .fontSize(14)
                .fontWeight(600)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor($r('app.color.badge_date_bg'))
                .borderRadius(16)
                .geometryTransition('timelineDay_dateLabel', { follow: true })
                .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })
            }
          }
        }
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
        .height(30)
        .margin({ bottom: 10 })
        .geometryTransition('timelineDay_header', { follow: true })
        .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })

        Stack({ alignContent: Alignment.Center }) {
          this.buildDayTimelineBody()

          if (this.reflectModel.dayTimelineError) {
            this.buildDayTimelineError()
          }
        }
        .width('100%')

        if (this.expanded) {
          Column() {
            this.buildStreamTimelineChart()
          }
          // .height(STREAM_CARD_BODY_HEIGHT + 100)
          .width('100%')
          .layoutWeight(1)
          .transition(
            TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
                .animation({ curve: curves.springMotion(0.6, 0.9), duration: 220 }),
              undefined
            )
          )
        } else {
          Column()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 15, bottom: 15, left: 20, right: 20 })
      .borderRadius(14)
      .geometryTransition('timelineDay_container', { follow: true })
      .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })
      .backgroundColor(this.expanded ? Color.Transparent : $r('app.color.bg_card'))
      .backgroundBlurStyle(this.expanded ? this.isDarkTheme ? BlurStyle.BACKGROUND_THIN : BlurStyle.COMPONENT_ULTRA_THIN : undefined)
      .visualEffect(buildPointLightEffect({
        preset: 'cardTouch',
        color: $r('app.color.immersive_glow_primary'),
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        isActive: false,
        isDarkTheme: this.isDarkTheme
      }))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildDayTimelineBody(): void {
    Column() {
      Stack() {
        this.buildHourGrid()

        Row() {
          ForEach(this.reflectModel.dayTimelineSegments, (segment: ReflectTimelineSegment, index: number) => {
            Stack() {
              Column() {
                if (!segment.isGap && segment.weight > 1800) {
                  // Only show labels when segment is wide enough (~30 minutes)
                  // Text(segment.activityTitle)
                  //   .fontColor($r('app.color.text_on_primary'))
                  //   .fontSize(10)
                  //   .fontWeight(FontWeight.Medium)
                  //   .maxLines(1)
                  //   .textOverflow({ overflow: TextOverflow.Ellipsis })
                  //   .margin({ bottom: 2 })
                }
                if (!segment.isGap && segment.weight > 2400) {
                  // Text(this.formatDuration(segment))
                  //   .fontColor($r('app.color.text_on_primary'))
                  //   .fontSize(9)
                  //   .opacity(0.85)
                  //   .maxLines(1)
                }
              }
              .padding({ left: 6, right: 6, top: 6, bottom: 6 })
              .alignItems(HorizontalAlign.Start)
              .justifyContent(FlexAlign.Start)
            }
            .height(35)
            .backgroundColor(segment.color)
            .layoutWeight(segment.weight)
            .onClick(() => this.handleSegmentTap(segment))
          }, (segment: ReflectTimelineSegment) => segment.id)
        }
        .height('100%')
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .height(35)
      .width('100%')
      .clip(true)
      .geometryTransition('timelineDay_grid', { follow: true })
      .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })

      Row() {
        this.buildTimelineMarkers()
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .margin({ top: 8 })
      .geometryTransition('timelineDay_markers', { follow: true })
      .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })

      // if (!this.reflectModel.dayTimelineHasRecords) {
      //   Text('今日还没有记录，开始记录你的第一段时光吧～')
      //     .fontColor($r('app.color.text_secondary'))
      //     .fontSize(12)
      //     .textAlign(TextAlign.Center)
      //     .margin({ top: 12 })
      //     .geometryTransition('timelineDay_empty', { follow: true })
      //     .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })
      // }
    }
    .geometryTransition('timelineDay_body', { follow: true })
    .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })
  }

  @Builder
  @Builder
  private buildDayTimelineError(): void {
    Column() {
      Text('暂时无法加载时间轴数据')
        .fontColor($r('app.color.error'))
        .fontSize(14)
      Button('重试', { type: ButtonType.Capsule })
        .margin({ top: 12 })
        .borderRadius(18)
        .backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.text_on_primary'))
        .onClick(() => {
          void this.reflectModel.refreshDayBundle()
        })
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .geometryTransition('timelineDay_state', { follow: true })
    .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })
  }

  @Builder
  private buildTimelineMarkers() {
    ForEach(this.markers, (label: string) => {
      Text(label)
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
    })
  }

  @Builder
  private buildStreamTimelineChart(): void {
    Column() {
      Row() {
        Text('时光流')
          .fontColor($r('app.color.primary'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .margin({ bottom: STREAM_HEADER_BOTTOM_MARGIN, top: 5 })

      if (this.reflectModel.streamTimelineError) {
        Column() {
          Text('加载失败，请稍后重试')
            .fontColor($r('app.color.error'))
            .fontSize(13)
          Button('重试', { type: ButtonType.Capsule })
            .margin({ top: 12 })
            .borderRadius(18)
            .backgroundColor($r('app.color.primary'))
            .fontColor($r('app.color.text_on_primary'))
            .onClick(() => {
              void this.reflectModel.refreshStreamTimeline(this.isDarkTheme)
            })
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      } else if (this.reflectModel.streamTimelineItems.length === 0) {
        Column() {
          Text('还没有记录，开始你的第一颗“串珠”吧～')
            .fontColor($r('app.color.text_secondary'))
            .fontSize(12)
            .textAlign(TextAlign.Center)
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      } else {
        List() {
          ForEach(this.reflectModel.streamTimelineItems, (item: FlowTimelineItem, index: number) => {
            ListItem() {
              this.buildStreamTimelineRow(item, index, this.reflectModel.streamTimelineItems.length)
            }
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({x: .8, y: .8})).animation({curve: curves.springMotion(), duration: 150, delay: 50 * index}))
          }, (item: FlowTimelineItem) => `${item.startMs}-${item.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .clip(true)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildStreamTimelineRow(item: FlowTimelineItem, index: number, total: number): void {
    Row() {
      Column() {
        Text(item.time)
          .fontSize(STREAM_TIME_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(STREAM_PRIMARY_TEXT_COLOR)
          .height(20)

        Text(item.duration)
          .fontSize(STREAM_DURATION_FONT_SIZE)
          .fontColor(STREAM_SECONDARY_TEXT_COLOR)
          .margin({ top: 2 })
      }
      .width(STREAM_TIME_COLUMN_WIDTH)
      .alignItems(HorizontalAlign.End)
      .margin({ right: 12 })

      Stack({ alignContent: Alignment.Top }) {
        if (!this.isStreamLastIndex(index, total)) {
          Column()
            .width(STREAM_LINE_WIDTH)
            .height('100%')
            .backgroundColor(STREAM_AXIS_LINE_COLOR)
            .margin({ top: STREAM_LINE_TOP_OFFSET })
        }

        Circle({ width: STREAM_DOT_SIZE, height: STREAM_DOT_SIZE })
          .fill(item.color)
          .stroke(STREAM_DOT_STROKE_COLOR)
          // .strokeWidth(STREAM_DOT_STROKE_WIDTH)
          .shadow({
            radius: STREAM_DOT_SHADOW_RADIUS,
            color: `${item.color}${this.resolveStreamDotShadowAlpha()}`,
            offsetY: STREAM_DOT_SHADOW_OFFSET_Y
          })
          .borderRadius('50%')
          .margin({ top: 3 })
      }
      .borderRadius('50%')
      .width(STREAM_AXIS_COLUMN_WIDTH)
      .height('100%')

      Column() {
        Text(item.title)
          .fontSize(STREAM_TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(STREAM_TITLE_TEXT_COLOR)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.buildStreamRangeLabel(item))
          .fontSize(STREAM_DURATION_FONT_SIZE)
          .fontColor(STREAM_SECONDARY_TEXT_COLOR)
          .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .margin({ left: 8, right: 8, top: 2, bottom: 2 })
    }
    .width('100%')
    .height(this.resolveStreamRowHeight(item.durationMinutes))
    .alignItems(VerticalAlign.Top)
  }

  private resolveStreamDotShadowAlpha(): string {
    return this.isDarkTheme ? STREAM_DOT_SHADOW_ALPHA_DARK : STREAM_DOT_SHADOW_ALPHA_LIGHT
  }
 
  @Builder
  private buildHourGrid() {
    Row() {
      ForEach(HOUR_GRID_CELLS, (cell: HourGridCell) => {
        Column() {}
          .height('100%')
          .backgroundColor(cell.style.backgroundColor)
          .borderWidth({ left: cell.style.leftBorderWidth, right: cell.style.rightBorderWidth })
          .borderColor({ left: cell.style.leftBorderColor, right: cell.style.rightBorderColor })
          .layoutWeight(cell.weight)
      }, (cell: HourGridCell) => cell.key)
    }
    .width('100%')
    .height(52)
    .borderWidth({ top: 1, bottom: 1, left: 1, right: 1 })
    .borderColor({
      top: GRID_BORDER_COLOR,
      bottom: GRID_BORDER_COLOR,
      left: GRID_BORDER_COLOR,
      right: GRID_BORDER_COLOR
    })
    .backgroundColor(GRID_LIGHT_COLOR)
  }


  private handleSegmentTap(segment: ReflectTimelineSegment): void {
    if (segment.isGap) {
      return
    }
    promptAction.openToast({
      message: `${segment.activityTitle} ${segment.label}`,
      duration: 1500
    })
  }
}
