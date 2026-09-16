import {
  JArrayList,
  ChartColorStop,
  XAxis,
  XAxisPosition,
  YAxis,
  YAxisLabelPosition,
  Description,
  Legend,
  LegendForm,
  LegendHorizontalAlignment,
  LegendOrientation,
  LegendVerticalAlignment,
  OnChartValueSelectedListener,
  Highlight,
  EntryOhos,
  LineDataSet,
  ILineDataSet,
  LineData,
  Mode,
  LineChart,
  LineChartModel,
  IAxisValueFormatter,
  AxisBase
} from '@ohos/mpchart';
import {
  SegmentButton,
  SegmentButtonOptions,
  SegmentButtonTextItem,
  ItemRestriction,
  LengthMetrics,
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageKeys, ColorModeUtil, COLOR_MODE_STORAGE_KEY } from 'base';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { TagTrendResponse, TagTrendDimension } from '../model/TagActivityTrendService';
import { ReflectModel } from '../model/ReflectModel';

const TAG = 'TagTrendChart';

interface ChartPalette {
  axisTextColor: number;
  gridLineColor: number;
  valueTextColor: number;
  legendTextColor: number;
  emptyStateBackground: number;
  loadingBackground: number;
}

interface LegendItem {
  name: string;
  color: number;
}

class TagAxisValueFormatter implements IAxisValueFormatter {
  private labels: string[];
  private labelCount: number;
  private visibleIndices?: Set<number>;

  constructor(labels: string[], labelCount: number, visibleIndices?: Set<number>) {
    this.labels = labels;
    this.labelCount = labelCount;
    this.visibleIndices = visibleIndices;
  }

  getFormattedValue(value: number, _axis: AxisBase): string {
    const index = Math.round(value);
    if (index < 0 || index >= this.labels.length) {
      return '';
    }
    if (this.visibleIndices && !this.visibleIndices.has(index)) {
      return '';
    }
    if (this.visibleIndices) {
      return this.labels[index];
    }
    const step = Math.max(1, Math.floor(this.labels.length / this.labelCount));
    if (this.labelCount < this.labels.length && index % step !== 0) {
      return '';
    }
    return this.labels[index];
  }
}

class FixedIndexAxisValueFormatter implements IAxisValueFormatter {
  private labels: string[];
  private targetIndices: number[];

  constructor(labels: string[], targetIndices: number[]) {
    this.labels = labels;
    this.targetIndices = targetIndices;
  }

  getFormattedValue(value: number, _axis: AxisBase): string {
    if (!this.targetIndices || this.targetIndices.length === 0) {
      return '';
    }
    const nearestIndex = this.findNearestIndex(value);
    if (nearestIndex < 0 || nearestIndex >= this.labels.length) {
      return '';
    }
    return this.labels[nearestIndex];
  }

  private findNearestIndex(value: number): number {
    let closestIndex = this.targetIndices[0];
    let closestDistance = Math.abs(value - closestIndex);
    for (let index = 1; index < this.targetIndices.length; index++) {
      const candidate = this.targetIndices[index];
      const distance = Math.abs(value - candidate);
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = candidate;
      }
    }
    return closestIndex;
  }
}

class IntegerAxisValueFormatter implements IAxisValueFormatter {
  getFormattedValue(value: number, _axis: AxisBase): string {
    return Math.round(value).toString();
  }
}

@Component
export struct TagTrendChart {
  private model: LineChartModel = new LineChartModel();
  private leftAxis?: YAxis | null;
  private rightAxis?: YAxis | null;
  private xAxis?: XAxis | null;
  private valueSelectedListener: OnChartValueSelectedListener = {
    onValueSelected: (_e: EntryOhos, _h: Highlight) => {
      // Placeholder for future marker/tooltip wiring
    },
    onNothingSelected: () => {}
  };

  @Consume('reflectModel') private reflectModel: ReflectModel = new ReflectModel();
  @StorageLink(StorageKeys.SELECTED_DATE) @Watch('onFocusDateChange') selectedDate: number = new Date().getDate();
  @StorageLink(StorageKeys.SELECTED_MONTH) @Watch('onFocusDateChange') selectedMonth: number = new Date().getMonth() + 1;
  @StorageLink(StorageKeys.SELECTED_YEAR) @Watch('onFocusDateChange') selectedYear: number = new Date().getFullYear();

  @State @Watch('onModeChange') tabSelectedIndexes: number[] = [0];
  @State tabOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '周' }, { text: '月' }, { text: '年' }] as ItemRestriction<SegmentButtonTextItem>,
    backgroundColor: $r('app.color.neutral_100'),
    selectedBackgroundColor: $r('app.color.primary_lighter'),
    selectedFontColor: $r('app.color.primary'),
    selectedFontWeight: 700,
    fontSize: 13,
    fontWeight: 500,
    fontColor: $r('app.color.text_secondary'),
    localizedButtonPadding: {
      start: LengthMetrics.vp(10),
      end: LengthMetrics.vp(10)
    }
  });

  @State hasData: boolean = false;
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State isDarkTheme: boolean = false;
  @State legendItems: LegendItem[] = [];
  private xAxisLabels: string[] = [];
  private xAxisLabelDates: number[] = [];
  private currentDimension: TagTrendDimension = 'week';

  aboutToAppear(): void {
    this.syncColorModeState();
    this.configureChart();
    void this.refreshData();
  }

  private onModeChange(): void {
    void this.refreshData();
  }

  private onFocusDateChange(): void {
    void this.refreshData();
  }

  private configureChart(): void {
    const palette = this.getChartPalette();

    this.model.setReadChartText('x轴: {x}, y轴: {y}');
    this.model.setReadLegendText('legend: {legend}');
    this.model.setReadAxisText('{axis}轴: {value}');
    this.model.setOnChartValueSelectedListener(this.valueSelectedListener);
    // 禁用缩放类交互
    this.model.setPinchZoom(false);
    this.model.setScaleEnabled(false);
    this.model.setDoubleTapToZoomEnabled(false);
    if (this.model.setHighlightPerTapEnabled) {
      this.model.setHighlightPerTapEnabled(false);
    }
    if (this.model.setHighlightPerDragEnabled) {
      this.model.setHighlightPerDragEnabled(false);
    }
    this.model.setDrawGridBackground(false);

    const description: Description | null = this.model.getDescription();
    if (description) {
      description.setEnabled(false);
    }

    const legend: Legend | null = this.model.getLegend();
    if (legend) {
      // Use custom legend layout to allow wrapping instead of truncation.
      legend.setEnabled(false);
      legend.setVerticalAlignment(LegendVerticalAlignment.BOTTOM);
      legend.setHorizontalAlignment(LegendHorizontalAlignment.CENTER);
      legend.setOrientation(LegendOrientation.HORIZONTAL);
      legend.setDrawInside(false);
      legend.setYOffset(12);
      legend.setTextColor(palette.legendTextColor);
      legend.setForm(LegendForm.CIRCLE);
      legend.setFormSize(8);
      legend.setXEntrySpace(14);
    }

    this.model.setMaxVisibleValueCount(120);
    this.model.setVisibleXRangeMaximum(60);
    this.model.setExtraOffsets(4, 8, 4, 8);

    this.leftAxis = this.model.getAxisLeft();
    if (this.leftAxis) {
      this.leftAxis.setLabelCount(6, false);
      this.leftAxis.setPosition(YAxisLabelPosition.OUTSIDE_CHART);
      this.leftAxis.setSpaceTop(10);
      this.leftAxis.setAxisMinimum(0);
      this.leftAxis.setGranularity(1);
      this.leftAxis.setTextColor(palette.axisTextColor);
      this.leftAxis.setGridColor(palette.gridLineColor);
      this.leftAxis.setAxisLineColor(0x00000000);
      this.leftAxis.setGridLineWidth(0.6);
      this.leftAxis.setDrawAxisLine(false);
    }

    this.rightAxis = this.model.getAxisRight();
    if (this.rightAxis) {
      this.rightAxis.setEnabled(false);
      this.rightAxis.setTextColor(palette.axisTextColor);
      this.rightAxis.setGridColor(palette.gridLineColor);
    }

    this.xAxis = this.model.getXAxis();
    if (this.xAxis) {
      this.xAxis.setPosition(XAxisPosition.BOTTOM);
      this.xAxis.setDrawGridLines(false);
      this.xAxis.setGranularity(1);
      this.xAxis.setTextColor(palette.axisTextColor);
      this.xAxis.setAxisLineColor(0x00000000);
      this.xAxis.setYOffset(10); // increase distance from axis line
      this.xAxis.setDrawAxisLine(false);
    }

    this.applyChartPalette();
  }

  private getSelectedDimension(): TagTrendDimension {
    const index = this.tabSelectedIndexes?.[0] ?? 0;
    if (index === 1) {
      return 'month';
    }
    if (index === 2) {
      return 'year';
    }
    return 'week';
  }

  private async refreshData(): Promise<void> {
    const dimension = this.getSelectedDimension();
    try {
      const response = await this.reflectModel.refreshTagTrend(dimension);
      if (!response) {
        this.hasData = false;
        this.legendItems = [];
        return;
      }
      const lineData = this.buildLineData(response);
      this.legendItems = this.buildLegendItems(response);
      this.hasData = !!lineData && response.series.length > 0;
      this.model.setData(lineData);
      this.model.notifyDataSetChanged();
      this.model.invalidate();
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh tag trend chart: ${JSON.stringify(error)}`);
      this.hasData = false;
      this.legendItems = [];
    }
  }

  private isCurrentDimensionLoading(): boolean {
    const dimension = this.getSelectedDimension();
    switch (dimension) {
      case 'month':
        return this.reflectModel.tagTrendLoadingMonth;
      case 'year':
        return this.reflectModel.tagTrendLoadingYear;
      default:
        return this.reflectModel.tagTrendLoadingWeek;
    }
  }

  private buildLineData(response: TagTrendResponse): LineData {
    const dataSetList: JArrayList<ILineDataSet> = new JArrayList<ILineDataSet>();
    this.xAxisLabels = this.buildXAxisLabels(response);
    this.xAxisLabelDates = this.buildXAxisLabelDates(response);
    this.currentDimension = response.dimension;

    response.series.forEach((series) => {
      const entries: JArrayList<EntryOhos> = new JArrayList<EntryOhos>();
      series.points.forEach((point, idx) => {
        entries.add(new EntryOhos(idx, point.activityCount));
      });

      const dataSet = new LineDataSet(entries, series.tagName);
      const baseColor = this.resolveColorInt(series.color);
      const fillColor = this.resolveColorInt(series.lightColor ?? series.color);
      dataSet.setMode(Mode.CUBIC_BEZIER);
      dataSet.setDrawCircles(false);
      dataSet.setDrawCircleHole(false);
      dataSet.setCircleRadius(3);
      dataSet.setLineWidth(2);
      dataSet.setColorByColor(baseColor);
      dataSet.setCircleColor(baseColor);
      dataSet.setHighlightEnabled(false);
      dataSet.setDrawHorizontalHighlightIndicator(false);
      dataSet.setDrawFilled(true);
      dataSet.setValueTextSize(9);
      dataSet.setValueTextColor(this.getChartPalette().valueTextColor);
      dataSet.setHighLightColor(this.withAlpha(baseColor, 0.7));
      dataSet.setHighlightLineWidth(0.6);
      dataSet.setDrawValues(false);

      const gradientFill = new JArrayList<ChartColorStop>();
      gradientFill.add([this.toColorString(this.withAlpha(fillColor, 0.28)), 0]);
      gradientFill.add([this.toColorString(this.withAlpha(fillColor, 0.06)), 1]);
      dataSet.setGradientFillColor(gradientFill);

      dataSetList.add(dataSet);
    });

    this.applyXAxisFormatter();
    this.applyYAxisFormatter();
    return new LineData(dataSetList);
  }

  private buildLegendItems(response: TagTrendResponse): LegendItem[] {
    if (!response.series || response.series.length === 0) {
      return [];
    }
    return response.series.map((series) => {
      const item: LegendItem = {
        name: series.tagName,
        color: this.resolveColorInt(series.color)
      };
      return item;
    });
  }

  private buildXAxisLabels(response: TagTrendResponse): string[] {
    if (!response.series || response.series.length === 0) {
      return [];
    }
    const sampleSeries = response.series[0];
    return sampleSeries.points.map(point => this.formatLabel(point.dateMs, response.dimension));
  }

  private buildXAxisLabelDates(response: TagTrendResponse): number[] {
    if (!response.series || response.series.length === 0) {
      return [];
    }
    const sampleSeries = response.series[0];
    return sampleSeries.points.map(point => point.dateMs);
  }

  private formatLabel(dateMs: number, dimension: TagTrendDimension): string {
    const date = new Date(dateMs);
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');

    switch (dimension) {
      case 'week':
        return this.formatMonthDayLabel(month, day);
      case 'month':
        return this.formatMonthDayLabel(month, day);
      case 'year':
      default:
        return `${month}月`;
    }
  }

  private formatMonthDayLabel(month: string, day: string): string {
    return `${month}/${day}`;
  }

  private applyXAxisFormatter(): void {
    if (!this.xAxis || !this.xAxisLabels || this.xAxisLabels.length === 0) {
      return;
    }

    if (this.isFebruaryMonthView()) {
      const februaryIndices = this.buildFebruaryWeekLabelIndices();
      const labelCount = februaryIndices.length > 0 ? februaryIndices.length : this.getFebruaryLabelCount();
      this.xAxis.setLabelCount(labelCount, true);
      const formatter = new FixedIndexAxisValueFormatter(this.xAxisLabels, februaryIndices);
      if (this.xAxis.setValueFormatter) {
        this.xAxis.setValueFormatter(formatter);
      }
      return;
    }

    // Limit labels for dense ranges, but keep all 12 monthly ticks in yearly view.
    const labelCount = this.currentDimension === 'year'
      ? this.xAxisLabels.length
      : Math.min(this.xAxisLabels.length, 12);
    this.xAxis.setLabelCount(labelCount, false);

    const formatter = new TagAxisValueFormatter(this.xAxisLabels, labelCount);
    if (this.xAxis.setValueFormatter) {
      this.xAxis.setValueFormatter(formatter);
    }
  }

  private isFebruaryMonthView(): boolean {
    if (this.currentDimension !== 'month') {
      return false;
    }
    if (!this.xAxisLabelDates || this.xAxisLabelDates.length === 0) {
      return false;
    }
    const firstDate = new Date(this.xAxisLabelDates[0]);
    return firstDate.getMonth() === 1;
  }

  private buildFebruaryWeekLabelIndices(): number[] {
    const indices: number[] = [];
    if (!this.xAxisLabelDates || this.xAxisLabelDates.length === 0) {
      return indices;
    }
    const has28 = this.hasFebruaryDay(28);
    const has29 = this.hasFebruaryDay(29);
    const tailDay = has28 ? 28 : (has29 ? 29 : -1);
    for (let index = 0; index < this.xAxisLabelDates.length; index++) {
      const date = new Date(this.xAxisLabelDates[index]);
      if (date.getMonth() !== 1) {
        continue;
      }
      const day = date.getDate();
      if (day === 1 || day === 8 || day === 15 || day === 22 || (tailDay > 0 && day === tailDay)) {
        indices.push(index);
      }
    }
    return indices;
  }

  private getFebruaryLabelCount(): number {
    if (!this.xAxisLabelDates || this.xAxisLabelDates.length === 0) {
      return 4;
    }
    const has28 = this.hasFebruaryDay(28);
    const has29 = this.hasFebruaryDay(29);
    return (has28 || has29) ? 5 : 4;
  }

  private hasFebruaryDay(targetDay: number): boolean {
    if (!this.xAxisLabelDates || this.xAxisLabelDates.length === 0) {
      return false;
    }
    for (let index = 0; index < this.xAxisLabelDates.length; index++) {
      const date = new Date(this.xAxisLabelDates[index]);
      if (date.getMonth() === 1 && date.getDate() === targetDay) {
        return true;
      }
    }
    return false;
  }

  private applyYAxisFormatter(): void {
    if (!this.leftAxis) {
      return;
    }
    const formatter = new IntegerAxisValueFormatter();
    if (this.leftAxis.setValueFormatter) {
      this.leftAxis.setValueFormatter(formatter);
    }
  }

  private resolveColorInt(hexColor: string | null | undefined): number {
    const fallback = 0xff4d94ff; // Primary blue
    if (!hexColor) {
      return fallback;
    }

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

  private getDimensionLabel(): string {
    switch (this.getSelectedDimension()) {
      case 'month':
        return '最近一月 · 标签活跃度';
      case 'year':
        return '全年走势 · 标签活跃度';
      default:
        return '近一周 · 标签活跃度';
    }
  }

  private getRangeHint(): string {
    if (!this.xAxisLabels || this.xAxisLabels.length === 0) {
      return '数据按标签统计';
    }
    const first = this.xAxisLabels[0];
    const last = this.xAxisLabels[this.xAxisLabels.length - 1];
    if (first === last) {
      return first;
    }
    return `${first} - ${last}`;
  }

  private onColorModeChange(): void {
    this.syncColorModeState();
    this.applyChartPalette();
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private getChartPalette(): ChartPalette {
    if (this.isDarkTheme) {
      const axisTextColor = this.colorStringToInt('#CBD4E1', 0xffcbd4e1);
      const gridLineColor = this.colorStringToInt('#2A3243', 0xff2a3243);
      return {
        axisTextColor,
        gridLineColor,
        valueTextColor: this.colorStringToInt('#E5E7EB', 0xffe5e7eb),
        legendTextColor: axisTextColor,
        emptyStateBackground: this.withAlpha(this.colorStringToInt('#212836', 0xff212836), 0.12),
        loadingBackground: this.withAlpha(this.colorStringToInt('#181F2A', 0xff181f2a), 0.14)
      };
    }
    const axisTextColor = this.colorStringToInt('#4E5D66', 0xff4e5d66);
    return {
      axisTextColor,
      gridLineColor: this.colorStringToInt('#E8EBED', 0xffe8ebed),
      valueTextColor: axisTextColor,
      legendTextColor: axisTextColor,
      emptyStateBackground: this.withAlpha(this.colorStringToInt('#E8EBED', 0xffe8ebed), 0.06),
      loadingBackground: this.withAlpha(this.colorStringToInt('#F4F6F8', 0xfff4f6f8), 0.06)
    };
  }

  private applyChartPalette(): void {
    const palette = this.getChartPalette();
    const legend: Legend | null = this.model.getLegend();
    if (legend) {
      legend.setTextColor(palette.legendTextColor);
    }

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
    }

    const data: LineData | null = this.model.getData ? this.model.getData() : null;
    if (data && data.getDataSetCount) {
      const dataSetCount = data.getDataSetCount();
      for (let index = 0; index < dataSetCount; index++) {
        const set = data.getDataSetByIndex(index) as LineDataSet | null;
        if (set && set.setValueTextColor) {
          set.setValueTextColor(palette.valueTextColor);
        }
      }
    }
    this.model.invalidate();
  }

  private colorStringToInt(hexColor: string, fallback: number): number {
    const trimmed = (hexColor ?? '').trim();
    if (!trimmed) {
      return fallback;
    }
    let normalized = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    if (normalized.length === 6) {
      normalized = `FF${normalized}`;
    }
    if (normalized.length !== 8) {
      return fallback;
    }
    const parsed = parseInt(normalized, 16);
    return Number.isNaN(parsed) ? fallback : parsed;
  }

  private getEmptyStateBackgroundColor(): number {
    return this.getChartPalette().emptyStateBackground;
  }

  private getLoadingBackgroundColor(): number {
    return this.getChartPalette().loadingBackground;
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('标签趋势')
            .fontColor($r('app.color.primary'))
            .fontSize(16)
            .fontWeight(600)
          // Column() {
          //   Text(this.getDimensionLabel())
          //     .fontColor($r('app.color.text_secondary'))
          //     .fontSize(12)
          //   Text(this.getRangeHint())
          //     .fontColor($r('app.color.text_tertiary'))
          //     .fontSize(12)
          //     .margin({ left: 8 })
          //     .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          //     .backgroundColor(0x14e8ebed)
          //     .borderRadius(12)
          // }
          // .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        SegmentButton({ options: this.tabOptions, selectedIndexes: this.tabSelectedIndexes })
          .height(24)
          .borderRadius(12)
          .padding({ left: 2, right: 2 })
          .width(120)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 12, right: 12, top: 0, bottom: 0 })
      .width('100%')

      Stack({ alignContent: Alignment.Center }) {
        Column() {
          LineChart({ model: this.model })
            .width('100%')
            .height('100%')
        }
        .width('100%')
        .height(200)
        .borderRadius(16)

        if (!this.hasData && !this.isCurrentDimensionLoading()) {
          Column() {
            Text('暂无数据')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text('选择其他时间范围或标签试试')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 6 })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .backgroundColor(this.getEmptyStateBackgroundColor())
          .borderRadius(16)
        }

        if (this.isCurrentDimensionLoading()) {
          Column() {
            LoadingProgress()
              .width(24)
              .height(24)
            Text('正在同步趋势...')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 6 })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          // .height('100%')
          .backgroundColor(this.getLoadingBackgroundColor())
          .borderRadius(16)
        }
      }
      .width('100%')

      if (this.hasData && this.legendItems.length > 0) {
        Row() {
          Flex({
            wrap: FlexWrap.Wrap,
            direction: FlexDirection.Row,
            justifyContent: FlexAlign.Center,
            alignItems: ItemAlign.Center,
            space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(8)}
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
              // .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(12)
              .backgroundColor(this.getEmptyStateBackgroundColor())
            }, (item: LegendItem) => `${item.name}-${item.color}`)
          }
        }
        // .backgroundColor(Color.Red)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding({left: 16, right: 16})
        .margin({ bottom: 5 })
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 5, left: 8, right: 8 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(20)
    .shadow(this.isDarkTheme ? {
      radius: 40,
      color: '#66000000'
    } : {
      radius: 40,
      color: '#33000000'
    })
  }
}
