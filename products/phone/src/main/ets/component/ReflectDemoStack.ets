import dayjs from 'dayjs';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { UIContext, curves, LengthMetrics } from '@kit.ArkUI';
import { JArrayList, ChartColorStop, XAxis, XAxisPosition, YAxis, YAxisLabelPosition, LineDataSet, ILineDataSet, LineData, Mode, LineChart, LineChartModel, IAxisValueFormatter, AxisBase, EntryOhos } from '@ohos/mpchart';
import { AppShadows, COLOR_MODE_STORAGE_KEY, ColorModeUtil, VibratorUtil } from 'base';
import { HmCalendarSelectedDay } from 'reflect/src/main/ets/model/CalendarModel';
import {
  ReflectStreamTimelineItem,
  ReflectTimelineSegment,
  ReflectTrendData,
  ReflectTrendSeries
} from '../model/ReflectUserGuideMockData';

const STREAM_CONTENT_VERTICAL_PADDING: number = 16
const STREAM_CONTENT_HORIZONTAL_PADDING: number = 20
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

type ReflectDemoLayerType = 'calendar' | 'timeline' | 'trend';

interface ReflectDemoLayerConfig {
  id: string;
  type: ReflectDemoLayerType;
  offsetY: number;
  offsetX: number;
  scale: number;
  opacity: number;
  motionScale: number;
  floatAngle: number;
  parallaxScale: number;
  floatMotionScale: number;
}

interface LegendItem {
  name: string;
  color: number;
}

interface ReflectChartPalette {
  axisTextColor: number;
  gridLineColor: number;
}

interface TwoWeekDayView {
  key: string;
  day: number;
  month: number;
  dateLabel: string;
  isSelected: boolean;
  textColor?: ResourceColor;
  backgroundColor?: ResourceColor;
}

interface ParsedRange {
  start: number;
  end: number;
}

interface DemoTimelineSegment {
  id: string;
  label: string;
  range: string;
  startMinutes: number;
  endMinutes: number;
  durationMinutes: number;
  color: ResourceColor;
  textColor: ResourceColor;
  isGap: boolean;
}

interface DemoStreamRow {
  id: string;
  time: string;
  title: string;
  durationLabel: string;
  rangeLabel: string;
  color: ResourceColor;
  isLast: boolean;
  rowHeight: number;
}

const REFLECT_DEMO_LAYERS: ReflectDemoLayerConfig[] = [
  // 1. 日历层 (Calendar)
  // 策略：向下沉，避开顶部的副标题，往左移露出边缘
  {
    id: 'reflect-calendar-layer',
    type: 'calendar',
    offsetY: -105,    // 原 -130 -> 改为 -105 (大幅向中间收缩)
    offsetX: -55,     // 原 -30 -> 改为 -55 (向左探出头，防止被挡住)
    scale: 0.65,      // 稍微调小一点点，显得更精致
    opacity: 0.5,
    motionScale: 0.4,
    floatAngle: -6,   // 角度稍微大一点，增加灵动感
    parallaxScale: -0.08,
    floatMotionScale: -0.04
  },

  // 2. 趋势层 (Trend)
  // 策略：向上提，彻底把底部文字区域让出来
  {
    id: 'reflect-trend-layer',
    type: 'trend',
    offsetY: 100,     // 原 125 -> 改为 100 (这是关键！向上提了25px，文字就安全了)
    offsetX: 55,      // 原 30 -> 改为 55 (向右探出头)
    scale: 0.65,      // 保持与日历一致
    opacity: 0.5,
    motionScale: 0.6,
    floatAngle: 5,
    parallaxScale: 0.08,
    floatMotionScale: 0.03
  },

  // 3. 时间轴层 (Timeline)
  // 策略：C位不动
  {
    id: 'reflect-timeline-layer',
    type: 'timeline',
    offsetY: 0,
    offsetX: 0,
    scale: 1,
    opacity: 1,
    motionScale: 1,
    floatAngle: 0,
    parallaxScale: 0,
    floatMotionScale: 0
  },
];

@Component
export struct ReflectDemoStack {
  @Watch('onActiveStateChanged') @Prop isActive: boolean = false;
  @Prop calendarHighlights: HmCalendarSelectedDay[] = [];
  @Prop timelineSegments: ReflectTimelineSegment[] = [];
  @Prop streamItems: ReflectStreamTimelineItem[] = [];
  @Prop trendData: ReflectTrendData = { labels: [], series: [] };
  @Prop dateLabel: string = (new Date().toString());
  @StorageLink('userGuideSheetVisible') @Watch('onGuideSheetVisibilityChanged') userGuideSheetVisible: boolean = false;
  @State floatOffsetY: number = 0;
  @State floatOffsetX: number = 0;
  @State private isComponentVisible: boolean = false;
  private readonly stackHeight: number = 350;
  private readonly floatAmplitudeY: number = 6;
  private readonly floatAmplitudeX: number = 4;
  private readonly floatFrameDuration: number = 2800;
  private isFloatRunning: boolean = false;

  aboutToAppear(): void {
    this.reconcileFloatingState();
  }

  aboutToDisappear(): void {
    this.stopFloating();
  }

  private onActiveStateChanged(): void {
    this.reconcileFloatingState();
  }

  private onGuideSheetVisibilityChanged(): void {
    this.reconcileFloatingState();
  }

  private shouldRunFloating(): boolean {
    return this.isActive && this.userGuideSheetVisible && this.isComponentVisible;
  }

  private reconcileFloatingState(): void {
    if (this.shouldRunFloating()) {
      this.startFloating();
      return;
    }
    this.stopFloating();
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        ForEach(REFLECT_DEMO_LAYERS, (layer: ReflectDemoLayerConfig, index: number) => {
          Column() {
            if (layer.type === 'calendar') {
              TwoWeekCalendarDemo({ selectedDays: this.calendarHighlights });
            } else if (layer.type === 'timeline') {
              ReflectDayTimelineDemo({
                segments: this.timelineSegments,
                streamItems: this.streamItems,
                dateLabel: this.dateLabel
              });
            } else {
              TagTrendChartDemo({ data: this.trendData });
            }
          }
            .transition(
              TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
                .animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 80 * index })
            )
            .translate({
              x: layer.offsetX + this.floatOffsetX * layer.motionScale * layer.parallaxScale,
              y: layer.offsetY + this.floatOffsetY * layer.motionScale
            })
            .scale({ x: layer.scale, y: layer.scale })
            .opacity(layer.opacity)
            .rotate({ x: 0, y: 0, z: 1, angle: layer.floatAngle + this.floatOffsetY * layer.floatMotionScale });
        }, (layer: ReflectDemoLayerConfig) => layer.id);
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height(this.stackHeight)
    .alignItems(HorizontalAlign.Center)
    .onVisibleAreaChange([0, 1], (_isExpanding: boolean, currentRatio: number) => {
      const nextVisible = currentRatio > 0;
      if (this.isComponentVisible === nextVisible) {
        return;
      }
      this.isComponentVisible = nextVisible;
      this.reconcileFloatingState();
    })
  }

  private startFloating(): void {
    if (this.isFloatRunning) {
      return;
    }
    this.isFloatRunning = true;
    this.scheduleNextFloat(this.floatAmplitudeY, this.floatAmplitudeX);
  }

  private stopFloating(): void {
    if (!this.isFloatRunning && this.floatOffsetY === 0 && this.floatOffsetX === 0) {
      return;
    }
    this.isFloatRunning = false;
    this.resetFloatPosition();
  }

  private resetFloatPosition(): void {
    const uiContext: UIContext | undefined = this.getUIContext();
    if (uiContext) {
      uiContext.animateTo({ duration: 150 }, () => {
        this.floatOffsetY = 0;
        this.floatOffsetX = 0;
      });
      return;
    }
    this.floatOffsetY = 0;
    this.floatOffsetX = 0;
  }

  private scheduleNextFloat(targetOffsetY: number, targetOffsetX: number): void {
    if (!this.isFloatRunning || !this.shouldRunFloating()) {
      return;
    }
    const uiContext = this.getUIContext();
    if (!uiContext) {
      this.isFloatRunning = false;
      return;
    }

    uiContext.animateTo({
      duration: this.floatFrameDuration,
      curve: Curve.EaseInOut,
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        if (!this.isFloatRunning || !this.shouldRunFloating()) {
          return;
        }
        const nextY = targetOffsetY > 0 ? -targetOffsetY : Math.abs(targetOffsetY);
        const nextX = targetOffsetX > 0 ? -targetOffsetX : Math.abs(targetOffsetX);
        this.scheduleNextFloat(nextY, nextX);
      }
    }, () => {
      if (!this.isFloatRunning || !this.shouldRunFloating()) {
        return;
      }
      this.floatOffsetY = targetOffsetY;
      this.floatOffsetX = targetOffsetX;
    });
  }
}

@Component
struct TwoWeekCalendarDemo {
  @Prop @Watch('refreshDays') selectedDays: HmCalendarSelectedDay[] = [];
  @State private days: TwoWeekDayView[] = [];
  private readonly weeks: ResourceStr[] = [
    $r('app.string.hm_calendar_sunday'),
    $r('app.string.hm_calendar_monday'),
    $r('app.string.hm_calendar_tuesday'),
    $r('app.string.hm_calendar_wednesday'),
    $r('app.string.hm_calendar_thursday'),
    $r('app.string.hm_calendar_friday'),
    $r('app.string.hm_calendar_saturday'),
  ];
  private readonly cardPadding: number = 16;
  private readonly daySize: number = 42;
  private readonly gutter: number = 8;

  aboutToAppear(): void {
    this.refreshDays();
  }

  private refreshDays(): void {
    this.days = this.buildTwoWeekDays();
  }

  private buildTwoWeekDays(): TwoWeekDayView[] {
    const selectionMap = new Map<string, HmCalendarSelectedDay>();
    this.selectedDays.forEach((item: HmCalendarSelectedDay) => {
      const parsed = dayjs(item.date);
      if (parsed.isValid()) {
        selectionMap.set(parsed.format('YYYY-MM-DD'), item);
      }
    });

    const start = dayjs().startOf('week');
    const days: TwoWeekDayView[] = [];
    for (let index = 0; index < 14; index++) {
      const current = start.add(index, 'day');
      const key = current.format('YYYY-MM-DD');
      const selected = selectionMap.get(key);
      const view: TwoWeekDayView = {
        key,
        day: current.date(),
        month: current.month() + 1,
        dateLabel: current.format('MM/DD'),
        isSelected: !!selected,
        textColor: selected?.textColor,
        backgroundColor: selected?.backgroundColor
      };
      days.push(view);
    }
    return days;
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Column() {
          Text('月度')
            .fontSize(16)
            .fontWeight(700)
            .fontColor($r('app.color.primary'))
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      .width('100%')

      GridRow({ columns: 7 }) {
        ForEach(this.weeks, (label: ResourceStr) => {
          GridCol() {
            Text(label)
              .fontSize(12)
              .fontWeight(500)
              .fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center)
          }
        })

        ForEach(this.days, (item: TwoWeekDayView) => {
          GridCol() {
            Column({ space: 4 }) {
              Stack({ alignContent: Alignment.Center }) {
                Text(item.day.toString())
                  .fontSize(14)
                  .fontWeight(600)
                  .fontColor(item.isSelected ? $r('app.color.primary') : $r('app.color.text_secondary'))
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 2, right: 2 })
                  .backgroundColor(item.isSelected ? item.backgroundColor ?? $r('app.color.primary_lighter') : Color.Transparent)
                  .borderRadius('50%')
              }
              .width(this.daySize)
              .height(this.daySize)
              .backgroundColor($r('app.color.bg_main'))
              .borderRadius('50%')
              .shadow(AppShadows.SUBTLE)

              // Text(item.dateLabel)
              //   .fontSize(10)
              //   .fontColor(item.isSelected ? item.textColor ?? $r('app.color.primary') : $r('app.color.text_tertiary'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        }, (item: TwoWeekDayView) => item.key)
      }
    }
    .padding({ top: this.cardPadding, bottom: this.cardPadding, left: this.cardPadding, right: this.cardPadding })
    .borderRadius(18)
    .backgroundColor($r('app.color.bg_card'))
    .shadow(AppShadows.CARD_INTERACTIVE)
  }
}

const GRID_LIGHT_COLOR: ResourceColor = $r('app.color.timeline_grid_light');
const GRID_DARK_COLOR: ResourceColor = $r('app.color.timeline_grid_dark');
const MAJOR_DIVIDER_COLOR: ResourceColor = $r('app.color.timeline_major_divider');
const MINOR_DIVIDER_COLOR: ResourceColor = $r('app.color.timeline_minor_divider');
const GRID_BORDER_COLOR: ResourceColor = $r('app.color.timeline_grid_border');
const DAY_TOTAL_MINUTES: number = 24 * 60;
const TIMELINE_MARKERS: string[] = ['00:00', '06:00', '12:00', '18:00', '24:00'];

interface HourGridCellStyle {
  backgroundColor: ResourceColor;
  leftBorderWidth: number;
  rightBorderWidth: number;
  leftBorderColor: ResourceColor;
  rightBorderColor: ResourceColor;
}

interface HourGridCell {
  key: string;
  style: HourGridCellStyle;
  weight: number;
}

function buildHourGridCells(): HourGridCell[] {
  const cells: HourGridCell[] = [];
  for (let index = 0; index < 24; index++) {
    const style: HourGridCellStyle = {
      backgroundColor: index % 2 === 0 ? GRID_LIGHT_COLOR : GRID_DARK_COLOR,
      leftBorderWidth: index === 0 ? 1 : 0,
      rightBorderWidth: 1,
      leftBorderColor: MAJOR_DIVIDER_COLOR,
      rightBorderColor: ((index + 1) % 6 === 0 || index === 23) ? MAJOR_DIVIDER_COLOR : MINOR_DIVIDER_COLOR
    };
    const cell: HourGridCell = {
      key: `${index}`,
      style,
      weight: 60
    };
    cells.push(cell);
  }
  return cells;
}

const HOUR_GRID_CELLS: HourGridCell[] = buildHourGridCells();

const STREAM_TIME_COLUMN_WIDTH: number = 55;
const STREAM_AXIS_COLUMN_WIDTH: number = 24;
const STREAM_DOT_SIZE: number = 14;
const STREAM_DOT_SHADOW_RADIUS: number = 8;
const STREAM_DOT_SHADOW_OFFSET_Y: number = 2;
const STREAM_LINE_WIDTH: number = 2;
const STREAM_LINE_TOP_OFFSET: number = 10;
const STREAM_MIN_ROW_HEIGHT: number = 56;
const STREAM_HEIGHT_PER_MINUTE: number = 0.4;
const STREAM_MAX_ROW_HEIGHT: number = 170;

@Component
struct ReflectDayTimelineDemo {
  @Prop @Watch('refreshSegments') segments: ReflectTimelineSegment[] = [];
  @Prop @Watch('refreshStreamRows') streamItems: ReflectStreamTimelineItem[] = [];
  @Prop dateLabel: string = '';
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  @State private displaySegments: DemoTimelineSegment[] = [];
  @State private streamRows: DemoStreamRow[] = [];
  @State private isExpanded: boolean = false;
  private readonly headerSpacing: number = 6;
  private readonly gridHeight: number = 38;
  private readonly cardPadding: number = 16;
  private readonly collapsedHeight: number = 120;
  private readonly expandedHeight: number = 350;

  aboutToAppear(): void {
    this.refreshSegments();
    this.refreshStreamRows();
  }

  private refreshSegments(): void {
    this.displaySegments = this.buildNormalizedSegments();
  }

  private refreshStreamRows(): void {
    this.streamRows = this.buildStreamRows();
  }

  private buildNormalizedSegments(): DemoTimelineSegment[] {
    const normalized: DemoTimelineSegment[] = [];
    this.segments.forEach((segment: ReflectTimelineSegment, index: number) => {
      const parsed = this.parseRange(segment.range);
      if (!parsed) {
        return;
      }
      const duration = Math.max(parsed.end - parsed.start, 1);
      const view: DemoTimelineSegment = {
        id: `segment-${segment.id ?? index}`,
        label: segment.label,
        range: segment.range,
        startMinutes: Math.max(parsed.start, 0),
        endMinutes: Math.min(parsed.end, DAY_TOTAL_MINUTES),
        durationMinutes: duration,
        color: segment.color,
        textColor: segment.textColor,
        isGap: false
      };
      normalized.push(view);
    });

    normalized.sort((a, b) => a.startMinutes - b.startMinutes);

    const segments: DemoTimelineSegment[] = [];
    let cursor = 0;
    normalized.forEach((segment: DemoTimelineSegment, index: number) => {
      if (segment.startMinutes > cursor) {
        segments.push(this.createGapSegment(cursor, segment.startMinutes, index));
      }
      segments.push(segment);
      cursor = Math.max(cursor, segment.endMinutes);
    });

    if (cursor < DAY_TOTAL_MINUTES) {
      segments.push(this.createGapSegment(cursor, DAY_TOTAL_MINUTES, normalized.length));
    }
    return segments;
  }

  private createGapSegment(start: number, end: number, index: number): DemoTimelineSegment {
    const clampedStart = Math.max(start, 0);
    const clampedEnd = Math.max(end, clampedStart + 1);
    return {
      id: `gap-${index}-${clampedStart}`,
      label: '',
      range: '',
      startMinutes: clampedStart,
      endMinutes: clampedEnd,
      durationMinutes: clampedEnd - clampedStart,
      color: Color.Transparent as ResourceColor,
      textColor: $r('app.color.text_secondary'),
      isGap: true
    };
  }

  private parseRange(range: string): ParsedRange | null {
    const parts = range.split('-').map(part => part.trim());
    if (parts.length !== 2) {
      return null;
    }
    const start = this.parseTime(parts[0]);
    const end = this.parseTime(parts[1]);
    if (start === null || end === null || end <= start) {
      return null;
    }
    return { start, end };
  }

  private parseTime(label: string): number | null {
    const parts = label.split(':').map(part => parseInt(part, 10));
    if (parts.length !== 2 || Number.isNaN(parts[0]) || Number.isNaN(parts[1])) {
      return null;
    }
    const hours = Math.min(Math.max(parts[0], 0), 23);
    const minutes = Math.min(Math.max(parts[1], 0), 59);
    return hours * 60 + minutes;
  }

  private buildStreamRows(): DemoStreamRow[] {
    const rows: DemoStreamRow[] = [];
    this.streamItems.forEach((item: ReflectStreamTimelineItem, index: number) => {
      const parsed = this.parseRange(item.range);
      const durationMinutes = parsed ? parsed.end - parsed.start : 40;
      const rowHeight = this.resolveStreamRowHeight(durationMinutes);
      const rangeLabel = parsed ? `${item.range}` : `${item.time} · ${item.duration}`;
      const row: DemoStreamRow = {
        id: item.id,
        time: item.time,
        title: item.title,
        durationLabel: item.duration,
        rangeLabel,
        color: item.color,
        isLast: item.isLast,
        rowHeight
      };
      rows.push(row);
    });
    return rows;
  }

  private resolveStreamRowHeight(durationMinutes: number): number {
    const scaled = STREAM_MIN_ROW_HEIGHT + durationMinutes * STREAM_HEIGHT_PER_MINUTE;
    if (scaled > STREAM_MAX_ROW_HEIGHT) {
      return STREAM_MAX_ROW_HEIGHT;
    }
    if (scaled < STREAM_MIN_ROW_HEIGHT) {
      return STREAM_MIN_ROW_HEIGHT;
    }
    return scaled;
  }

  private animateExpanded(target: boolean): void {
    const uiContext: UIContext | undefined = this.getUIContext();
    if (!uiContext) {
      this.isExpanded = target;
      return;
    }
    uiContext.animateTo({
      duration: 320,
      curve: curves.springMotion(0.4, 0.7)
    }, () => {
      this.isExpanded = target;
    });
  }

  build() {
    Column({ space: this.headerSpacing }) {
      Row() {
        Text('时间轴')
          .fontColor($r('app.color.primary'))
          .fontSize(16)
          .fontWeight(700)

        if (this.dateLabel) {
          Text(this.dateLabel)
            .fontColor($r('app.color.warning'))
            .fontSize(13)
            .fontWeight(600)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.accent_lighter'))
            .borderRadius(14)
        }
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')

      Column({ space: 12 }) {
        Stack() {
          this.buildHourGrid()

          Row() {
            ForEach(this.displaySegments, (segment: DemoTimelineSegment) => {
              Column() {
                // if (!segment.isGap && segment.durationMinutes > 45) {
                //   Text(segment.label)
                //     .fontSize(11)
                //     .fontWeight(600)
                //     .fontColor($r('app.color.text_on_primary'))
                //     .maxLines(1)
                //     .textOverflow({ overflow: TextOverflow.Ellipsis })
                // }
                // if (!segment.isGap && segment.durationMinutes > 60) {
                //   Text(segment.range)
                //     .fontSize(10)
                //     .fontColor($r('app.color.text_on_primary'))
                //     .opacity(0.9)
                // }
              }
              .padding({ left: 8, right: 8, top: 6, bottom: 6 })
              .alignItems(HorizontalAlign.Start)
              .justifyContent(FlexAlign.Start)
              .height('100%')
              .backgroundColor(segment.isGap ? Color.Transparent : segment.color)
              .layoutWeight(Math.max(segment.durationMinutes, 1))
              .onClick(() => {
                if (this.isExpanded) {
                  this.animateExpanded(false);
                }
              });
            }, (segment: DemoTimelineSegment) => segment.id);
          }
          .height('100%')
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .height(this.gridHeight)
        .width('100%')
        .clip(true)

        Row() {
          ForEach(TIMELINE_MARKERS, (marker: string) => {
            Text(marker)
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
          }, (marker: string) => marker);
        }
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')

        if (this.isExpanded && this.streamRows.length > 0) {
          Column({ space: 12 }) {
            Row() {
              Text('时光流')
                .fontColor($r('app.color.primary'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
            }
            .width('100%')

            List() {
              ForEach(this.streamRows, (row: DemoStreamRow, index: number) => {
                ListItem() {
                  this.buildStreamRow(row)
                }
                .transition(
                  TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.85, y: 0.85 }))
                    .animation({ curve: curves.springMotion(), duration: 160, delay: 60 * index })
                )
              }, (row: DemoStreamRow) => row.id);
            }
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Off)
            .width('100%')
            .layoutWeight(1)
            .clip(true)
          }
          .layoutWeight(1)
          .transition(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 }))
              .animation({ curve: curves.springMotion(0.6, 0.9), duration: 240 })
          )
        }
      }
    }
    .padding({ top: this.cardPadding, bottom: this.cardPadding, left: this.cardPadding, right: this.cardPadding })
    .borderRadius(18)
    .clip(true)
    .backgroundColor($r('app.color.bg_card'))
    .shadow(AppShadows.CARD_INTERACTIVE)
    .width('100%')
    .height(this.isExpanded ? this.expandedHeight : this.collapsedHeight)
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ duration: 420 })
          .onAction(() => {
            this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch')
            this.animateExpanded(true);
          }),
        TapGesture()
          .onAction(() => {
            if (this.isExpanded) {
              this.animateExpanded(false);
            }
          })
      )
    )
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
    .height(this.gridHeight)
    .borderWidth({ top: 1, bottom: 1, left: 1, right: 1 })
    .borderColor({
      top: GRID_BORDER_COLOR,
      bottom: GRID_BORDER_COLOR,
      left: GRID_BORDER_COLOR,
      right: GRID_BORDER_COLOR
    })
    .backgroundColor(GRID_LIGHT_COLOR)
  }

  @Builder
  private buildStreamRow(item: DemoStreamRow): void {
    Row() {
      Column() {
        Text(item.time)
          .fontSize(STREAM_TIME_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(STREAM_PRIMARY_TEXT_COLOR)
          .height(20)

        Text(item.durationLabel)
          .fontSize(STREAM_DURATION_FONT_SIZE)
          .fontColor(STREAM_SECONDARY_TEXT_COLOR)
          .margin({ top: 2 })
      }
      .width(STREAM_TIME_COLUMN_WIDTH)
      .alignItems(HorizontalAlign.End)
      .margin({ right: 12 })

      Stack({ alignContent: Alignment.Top }) {
        if (!item.isLast) {
          Column()
            .width(STREAM_LINE_WIDTH)
            .height('100%')
            .backgroundColor(STREAM_AXIS_LINE_COLOR)
            .margin({ top: STREAM_LINE_TOP_OFFSET })
        }

        Circle({ width: STREAM_DOT_SIZE, height: STREAM_DOT_SIZE })
          .fill(item.color)
          // .stroke(STREAM_DOT_STROKE_COLOR)
          // // .strokeWidth(STREAM_DOT_STROKE_WIDTH)
          // .shadow({
          //   radius: STREAM_DOT_SHADOW_RADIUS,
          //   color: `${item.color}${this.resolveStreamDotShadowAlpha()}`,
          //   offsetY: STREAM_DOT_SHADOW_OFFSET_Y
          // })
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

        Text(item.rangeLabel)
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
    .height(item.rowHeight)
    .alignItems(VerticalAlign.Top)
  }
}

@Component
struct TagTrendChartDemo {
  @Prop data: ReflectTrendData = { labels: [], series: [] };
  private model: LineChartModel = new LineChartModel();
  private leftAxis?: YAxis | null;
  private rightAxis?: YAxis | null;
  private xAxis?: XAxis | null;
  @State legendItems: LegendItem[] = [];
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State isDarkTheme: boolean = false;

  aboutToAppear(): void {
    this.syncColorModeState();
    this.configureChart();
    this.applyChartPalette();
    this.applyData();
  }

  private onColorModeChange(): void {
    this.syncColorModeState();
    this.applyChartPalette();
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private configureChart(): void {
    this.model.setPinchZoom(false);
    this.model.setScaleEnabled(false);
    this.model.setDoubleTapToZoomEnabled(false);
    this.model.setDrawGridBackground(false);
    this.model.setMaxVisibleValueCount(120);
    this.model.setVisibleXRangeMaximum(60);
    this.model.setExtraOffsets(4, 8, 4, 8);

    const description = this.model.getDescription();
    if (description) {
      description.setEnabled(false);
    }

    const legend = this.model.getLegend();
    if (legend) {
      legend.setEnabled(false);
    }

    this.leftAxis = this.model.getAxisLeft();
    if (this.leftAxis) {
      this.leftAxis.setLabelCount(5, false);
      this.leftAxis.setPosition(YAxisLabelPosition.OUTSIDE_CHART);
      this.leftAxis.setSpaceTop(10);
      this.leftAxis.setAxisMinimum(0);
      this.leftAxis.setDrawAxisLine(false);
    }

    this.rightAxis = this.model.getAxisRight();
    if (this.rightAxis) {
      this.rightAxis.setEnabled(false);
    }

    this.xAxis = this.model.getXAxis();
    if (this.xAxis) {
      this.xAxis.setPosition(XAxisPosition.BOTTOM);
      this.xAxis.setDrawGridLines(false);
      this.xAxis.setGranularity(1);
    }
  }

  private applyChartPalette(): void {
    const palette = this.getChartPalette();

    if (this.leftAxis) {
      this.leftAxis.setTextColor(palette.axisTextColor);
      this.leftAxis.setGridColor(palette.gridLineColor);
    }
    if (this.rightAxis) {
      this.rightAxis.setTextColor(palette.axisTextColor);
      this.rightAxis.setGridColor(palette.gridLineColor);
    }
    if (this.xAxis) {
      this.xAxis.setTextColor(palette.axisTextColor);
      this.xAxis.setAxisLineColor(0x00000000);
    }
  }

  private applyData(): void {
    if (!this.data.labels || this.data.labels.length === 0 || !this.data.series || this.data.series.length === 0) {
      this.legendItems = [];
      return;
    }
    const lineData = this.buildLineData(this.data);
    this.model.setData(lineData);
    this.model.notifyDataSetChanged();
    this.model.invalidate();
    this.legendItems = this.data.series.map((series: ReflectTrendSeries): LegendItem => {
      return { name: series.name, color: this.toColorInt(series.color) };
    });
  }

  private buildLineData(data: ReflectTrendData): LineData {
    const dataSetList: JArrayList<ILineDataSet> = new JArrayList<ILineDataSet>();
    data.series.forEach((series: ReflectTrendSeries) => {
      const entries: JArrayList<EntryOhos> = new JArrayList<EntryOhos>();
      series.values.forEach((value: number, idx: number) => {
        entries.add(new EntryOhos(idx, value));
      });

      const dataSet = new LineDataSet(entries, series.name);
      const baseColor = this.toColorInt(series.color);
      const fillColor = this.toColorInt(series.lightColor);
      dataSet.setMode(Mode.CUBIC_BEZIER);
      dataSet.setDrawCircles(false);
      dataSet.setDrawCircleHole(false);
      dataSet.setLineWidth(2);
      dataSet.setColorByColor(baseColor);
      dataSet.setCircleColor(baseColor);
      dataSet.setHighlightEnabled(false);
      dataSet.setDrawHorizontalHighlightIndicator(false);
      dataSet.setDrawFilled(true);
      dataSet.setDrawValues(false);

      const gradientFill: JArrayList<ChartColorStop> = new JArrayList<ChartColorStop>();
      gradientFill.add([this.toColorString(this.withAlpha(fillColor, 0.32)), 0]);
      gradientFill.add([this.toColorString(this.withAlpha(fillColor, 0.08)), 1]);
      dataSet.setGradientFillColor(gradientFill);

      dataSetList.add(dataSet);
    });

    this.applyXAxisFormatter(data.labels);
    return new LineData(dataSetList);
  }

  private applyXAxisFormatter(labels: string[]): void {
    if (!this.xAxis) {
      return;
    }
    const formatter: IAxisValueFormatter = {
      getFormattedValue: (value: number, _axis: AxisBase): string => {
        const index = Math.round(value);
        if (index < 0 || index >= labels.length) {
          return '';
        }
        return labels[index];
      }
    };
    if (this.xAxis.setValueFormatter) {
      this.xAxis.setValueFormatter(formatter);
    }
    const labelCount = Math.min(labels.length, 7);
    this.xAxis.setLabelCount(labelCount, false);
  }

  private toColorInt(hexColor: string): number {
    const fallback = 0xff4d94ff;
    const trimmed = hexColor.trim();
    if (!trimmed.startsWith('#')) {
      return fallback;
    }
    let normalized = trimmed.substring(1);
    if (normalized.length === 6) {
      normalized = `FF${normalized}`;
    }
    if (normalized.length !== 8) {
      return fallback;
    }
    const parsed = parseInt(normalized, 16);
    if (Number.isNaN(parsed)) {
      return fallback;
    }
    return parsed;
  }

  private withAlpha(color: number, alpha: number): number {
    const clamped = Math.max(0, Math.min(1, alpha));
    const alphaInt = Math.round(clamped * 255) << 24;
    return (color & 0x00ffffff) | alphaInt;
  }

  private toColorString(color: number): string {
    const unsigned = color >>> 0;
    return `#${unsigned.toString(16).padStart(8, '0')}`;
  }

  private getChartPalette(): ReflectChartPalette {
    if (this.isDarkTheme) {
      const palette: ReflectChartPalette = {
        axisTextColor: this.toColorInt('#CBD4E1'),
        gridLineColor: this.toColorInt('#2A3243')
      };
      return palette;
    }
    const palette: ReflectChartPalette = {
      axisTextColor: this.toColorInt('#4E5D66'),
      gridLineColor: this.toColorInt('#E8EBED')
    };
    return palette;
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        Text('标签趋势')
          .fontColor($r('app.color.primary'))
          .fontSize(16)
          .fontWeight(700)
      }
      .width('100%')

      LineChart({ model: this.model })
        .width('100%')
        .height(200)
        .borderRadius(16)

      if (this.legendItems.length > 0) {
        Row() {
          Flex({
            wrap: FlexWrap.Wrap,
            direction: FlexDirection.Row,
            justifyContent: FlexAlign.Center,
            alignItems: ItemAlign.Center,
            space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(8) }
          }) {
            ForEach(this.legendItems, (item: LegendItem) => {
              Row() {
                Stack() {}
                  .width(10)
                  .height(10)
                  .backgroundColor(item.color)
                  .borderRadius(10)
                Text(item.name)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ left: 6 })
              }
              .backgroundColor($r('app.color.neutral_100'))
              .borderRadius(12)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            }, (item: LegendItem) => `${item.name}-${item.color}`);
          }
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding({ left: 8, right: 8 })
      }
    }
    .padding({ top: 16, bottom: 16, left: 16, right: 16 })
    .borderRadius(18)
    .backgroundColor($r('app.color.bg_card'))
    .shadow(AppShadows.CARD_INTERACTIVE)
  }
}
