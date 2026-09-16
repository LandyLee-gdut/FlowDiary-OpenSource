import {
  JArrayList,
  XAxis,
  XAxisPosition,
  YAxis,
  YAxisLabelPosition,
  Description,
  Legend,
  OnChartValueSelectedListener,
  Highlight,
  EntryOhos,
  BarDataSet,
  IBarDataSet,
  BarData,
  BarEntry,
  BarChart,
  BarChartModel,
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
import { TagTimeDimension, TagTimeSummaryEntry } from '../model/TagTimeRangeService';
import { ReflectModel } from '../model/ReflectModel';

const TAG = 'TagTimeBarChart';

interface ChartPalette {
  axisTextColor: number;
  gridLineColor: number;
  valueTextColor: number;
  emptyStateBackground: number;
  loadingBackground: number;
}

class TagAxisValueFormatter implements IAxisValueFormatter {
  private labels: string[];

  constructor(labels: string[]) {
    this.labels = labels;
  }

  getFormattedValue(value: number, _axis: AxisBase): string {
    const index = Math.round(value);
    if (index < 0 || index >= this.labels.length) {
      return '';
    }
    return this.labels[index];
  }
}

@Component
export struct TagTimeBarChart {
  private model: BarChartModel = new BarChartModel();
  private leftAxis?: YAxis | null;
  private rightAxis?: YAxis | null;
  private xAxis?: XAxis | null;
  private valueSelectedListener: OnChartValueSelectedListener = {
    onValueSelected: (_e: EntryOhos, _h: Highlight) => {},
    onNothingSelected: () => {}
  };

  @Consume('reflectModel') private reflectModel: ReflectModel = new ReflectModel();
  @StorageLink(StorageKeys.SELECTED_DATE) @Watch('onFocusDateChange') selectedDate: number = new Date().getDate();
  @StorageLink(StorageKeys.SELECTED_MONTH) @Watch('onFocusDateChange') selectedMonth: number = new Date().getMonth() + 1;
  @StorageLink(StorageKeys.SELECTED_YEAR) @Watch('onFocusDateChange') selectedYear: number = new Date().getFullYear();

  @State @Watch('onModeChange') tabSelectedIndexes: number[] = [0];
  @State tabOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    // buttons: [{ text: '日' }, { text: '周' }, { text: '月' }, { text: '年' }] as ItemRestriction<SegmentButtonTextItem>,
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
  @State maxMinutes: number = 0;
  @State rangeHint: string = '按标签统计总时长';
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State isDarkTheme: boolean = false;
  private xAxisLabels: string[] = [];

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
    this.model.setReadChartText('x轴: {x}, y轴: {y}');
    this.model.setReadLegendText('legend: {legend}');
    this.model.setReadAxisText('{axis}轴: {value}');
    this.model.setOnChartValueSelectedListener(this.valueSelectedListener);
    this.model.setPinchZoom(false);
    this.model.setDoubleTapToZoomEnabled(false);
    this.model.setDrawGridBackground(false);
    this.model.setDrawBarShadow(false);
    this.model.setDrawValueAboveBar(true);
    this.model.setMaxVisibleValueCount(40);
    this.model.setVisibleXRangeMaximum(10);
    this.model.setExtraOffsets(4, 8, 4, 8);
    // 禁用缩放类交互
    this.model.setPinchZoom(false);
    this.model.setScaleEnabled(false);
    this.model.setDoubleTapToZoomEnabled(false);

    const description: Description | null = this.model.getDescription();
    if (description) {
      description.setEnabled(false);
    }

    const legend: Legend | null = this.model.getLegend();
    if (legend) {
      legend.setEnabled(false);
    }

    this.leftAxis = this.model.getAxisLeft();
    if (this.leftAxis) {
      this.leftAxis.setLabelCount(5, false);
      this.leftAxis.setPosition(YAxisLabelPosition.OUTSIDE_CHART);
      this.leftAxis.setSpaceTop(12);
      this.leftAxis.setAxisMinimum(0);
      this.leftAxis.setDrawAxisLine(false);
      this.leftAxis.setAxisLineColor(0x00000000);
      this.leftAxis.setGridLineWidth(0.6);
    }

    this.rightAxis = this.model.getAxisRight();
    if (this.rightAxis) {
      this.rightAxis.setEnabled(false);
    }

    this.xAxis = this.model.getXAxis();
    if (this.xAxis) {
      // this.xAxis.setPosition(XAxisPosition.BOTTOM);
      // this.xAxis.setDrawGridLines(false);
      // this.xAxis.setGranularity(1);
      // this.xAxis.setAxisLineColor(0x00000000);
      // this.xAxis.setYOffset(10); // increase distance from axis line
      // this.xAxis.setDrawAxisLine(false);

      this.xAxis.setPosition(XAxisPosition.BOTTOM);
      this.xAxis.setDrawGridLines(false);
      this.xAxis.setGranularity(1);
      // this.xAxis.setTextColor(palette.axisTextColor);
      this.xAxis.setAxisLineColor(0x00000000);
      this.xAxis.setYOffset(10); // increase distance from axis line
      this.xAxis.setDrawAxisLine(false);
    }

    this.applyChartPalette();
  }

  private getSelectedDimension(): TagTimeDimension {
    const index = this.tabSelectedIndexes?.[0] ?? 0;
    // switch (index) {
    //   case 1:
    //     return 'week';
    //   case 2:
    //     return 'month';
    //   case 3:
    //     return 'year';
    //   default:
    //     return 'day';
    // }

    switch (index) {
      case 0:
        return 'week';
      case 1:
        return 'month';
      case 2:
        return 'year';
      default:
        return 'week';
    }
  }

  private async refreshData(): Promise<void> {
    const dimension = this.getSelectedDimension();

    try {
      const response = await this.reflectModel.refreshTagTimeSummary(dimension);
      if (!response) {
        this.hasData = false;
        return;
      }
      const barData = this.buildBarData(response.entries, dimension);
      this.hasData = response.entries.length > 0;
      this.maxMinutes = response.entries.reduce((max: number, entry: TagTimeSummaryEntry) => Math.max(max, entry.totalMinutes), 0);
      this.rangeHint = this.buildRangeHint(response.startMs, response.endMs);
      this.xAxisLabels = response.entries.map((entry: TagTimeSummaryEntry) => entry.tagName);
      this.updateAxisBounds(this.maxMinutes);
      this.applyXAxisFormatter();
      this.model.setData(barData);
      this.model.notifyDataSetChanged();
      this.model.invalidate();
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to refresh tag time chart: ${JSON.stringify(error)}`);
      this.hasData = false;
    }
  }

  private isCurrentDimensionLoading(): boolean {
    const dimension = this.getSelectedDimension();
    switch (dimension) {
      case 'month':
        return this.reflectModel.tagTimeLoadingMonth;
      case 'year':
        return this.reflectModel.tagTimeLoadingYear;
      default:
        return this.reflectModel.tagTimeLoadingWeek;
    }
  }

  private buildBarData(entries: TagTimeSummaryEntry[], dimension: TagTimeDimension): BarData {
    const values: JArrayList<BarEntry> = new JArrayList<BarEntry>();
    const colors: number[] = [];
    entries.forEach((entry: TagTimeSummaryEntry, index: number) => {
      values.add(new BarEntry(index, entry.totalMinutes));
      colors.push(this.resolveColorInt(entry.color));
    });

    const dataSet: BarDataSet = new BarDataSet(values, '标签时长');
    const palette = this.getChartPalette();
    dataSet.setDrawIcons(false);
    dataSet.setDrawValues(true);
    dataSet.setValueTextSize(11);
    dataSet.setValueTextColor(palette.valueTextColor);
    dataSet.setHighLightColor(this.withAlpha(this.resolveColorInt('#000000'), 0.2));
    dataSet.setColorsByArr(colors);
    dataSet.setBarShadowColor(this.withAlpha(this.resolveColorInt('#000000'), 0.04));
    dataSet.setHighlightEnabled(entries.length > 0);

    const dataSetList: JArrayList<IBarDataSet> = new JArrayList<IBarDataSet>();
    dataSetList.add(dataSet);

    const barData: BarData = new BarData(dataSetList);
    barData.setBarWidth(this.resolveBarWidth(entries.length, dimension));
    barData.setTopRadius(8);
    return barData;
  }

  private resolveBarWidth(entryCount: number, dimension: TagTimeDimension): number {
    if (dimension === 'day') {
      if (entryCount <= 3) {
        return 0.35;
      }
      if (entryCount <= 6) {
        return 0.45;
      }
    }
    return 0.55;
  }

  private updateAxisBounds(maxMinutes: number): void {
    const axisMax = this.computeYAxisMax(maxMinutes);
    if (this.leftAxis) {
      this.leftAxis.setAxisMaximum(axisMax);
    }
  }

  private computeYAxisMax(maxMinutes: number): number {
    if (maxMinutes <= 0) {
      return 60;
    }
    const step = maxMinutes <= 120 ? 30 : 60;
    return Math.ceil(maxMinutes / step) * step;
  }

  private buildRangeHint(startMs: number, endMs: number): string {
    const startLabel = this.formatDateLabel(startMs);
    const endLabel = this.formatDateLabel(endMs);
    if (startLabel === endLabel) {
      return startLabel;
    }
    return `${startLabel} - ${endLabel}`;
  }

  private formatDateLabel(timestamp: number): string {
    const date = new Date(timestamp);
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${month}/${day}`;
  }

  private applyXAxisFormatter(): void {
    if (!this.xAxis || !this.xAxisLabels || this.xAxisLabels.length === 0) {
      return;
    }

    const labelCount = Math.min(this.xAxisLabels.length, 6);
    this.xAxis.setLabelCount(labelCount, false);
    const formatter = new TagAxisValueFormatter(this.xAxisLabels);
    if (this.xAxis.setValueFormatter) {
      this.xAxis.setValueFormatter(formatter);
    }
  }

  private resolveColorInt(hexColor: string | null | undefined): number {
    return this.colorStringToInt(hexColor ?? '#4d94ff', 0xff4d94ff);
  }

  private withAlpha(color: number, alpha: number): number {
    const clamped = Math.max(0, Math.min(1, alpha));
    const alphaInt = Math.round(clamped * 255) << 24;
    return (color & 0x00ffffff) | alphaInt;
  }

  private getChartPalette(): ChartPalette {
    if (this.isDarkTheme) {
      const axisTextColor = this.colorStringToInt('#CBD4E1', 0xffcbd4e1);
      const gridLineColor = this.colorStringToInt('#2A3243', 0xff2a3243);
      return {
        axisTextColor,
        gridLineColor,
        valueTextColor: this.colorStringToInt('#E5E7EB', 0xffe5e7eb),
        emptyStateBackground: this.withAlpha(this.colorStringToInt('#212836', 0xff212836), 0.12),
        loadingBackground: this.withAlpha(this.colorStringToInt('#181F2A', 0xff181f2a), 0.14)
      };
    }
    const axisTextColor = this.colorStringToInt('#4E5D66', 0xff4e5d66);
    return {
      axisTextColor,
      gridLineColor: this.colorStringToInt('#E8EBED', 0xffe8ebed),
      valueTextColor: axisTextColor,
      emptyStateBackground: this.withAlpha(this.colorStringToInt('#E8EBED', 0xffe8ebed), 0.06),
      loadingBackground: this.withAlpha(this.colorStringToInt('#F4F6F8', 0xfff4f6f8), 0.06)
    };
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
    }

    const data: BarData | null = this.model.getData ? this.model.getData() as BarData : null;
    if (data && data.getDataSetCount) {
      const count = data.getDataSetCount();
      for (let index = 0; index < count; index++) {
        const set = data.getDataSetByIndex(index) as BarDataSet | null;
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

  private onColorModeChange(): void {
    this.syncColorModeState();
    this.applyChartPalette();
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private getDimensionLabel(): string {
    switch (this.getSelectedDimension()) {
      case 'week':
        return '近7日 · 标签时长';
      case 'month':
        return '本月 · 标签时长';
      case 'year':
        return '今年 · 标签时长';
      default:
        return '今日 · 标签时长';
    }
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('标签时长')
            .fontColor($r('app.color.primary'))
            .fontSize(16)
            .fontWeight(600)
          // Text(this.getDimensionLabel())
          //   .fontColor($r('app.color.text_secondary'))
          //   .fontSize(12)
          // Text(this.rangeHint)
          //   .fontColor($r('app.color.text_tertiary'))
          //   .fontSize(12)
          //   .margin({ top: 4 })
          // Text('单位：分钟')
          //   .fontColor($r('app.color.text_tertiary'))
          //   .fontSize(12)
          //   .margin({ top: 2 })
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
          BarChart({ model: this.model })
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
          .backgroundColor(this.getChartPalette().emptyStateBackground)
          .borderRadius(16)
        }

        if (this.isCurrentDimensionLoading()) {
          Column() {
            LoadingProgress()
              .width(24)
              .height(24)
            Text('正在加载标签时长...')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 6 })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          // .height('100%')
          .backgroundColor(this.getChartPalette().loadingBackground)
          .borderRadius(16)
        }
      }
      .width('100%')
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
