import { LabelSummaryModel } from 'base';

@Component
export struct ReflectTodayCirclePanel {
  @Prop @Watch('updateData') summaryData: LabelSummaryModel[] = [];
  @State private values: number[] = [];
  @State private colors: ResourceColor[] = [];
  @State private totalValue: number = 0;

  private updateData(): void {
    if (this.summaryData && this.summaryData.length > 0) {
      this.values = this.summaryData.map(item => item.totalMinutes);
      this.colors = this.summaryData.map(item => this.resolveSolidColor(item.labelColor));
      this.totalValue = this.values.reduce((sum, val) => sum + val, 0) || 1;
      return;
    }

    this.values = [];
    this.colors = [];
    this.totalValue = 1;
  }

  private resolveSolidColor(color: ResourceColor): ResourceColor {
    if (typeof color !== 'string') {
      return color;
    }
    const trimmed = color.trim();
    if (trimmed.length === 0) {
      return $r('app.color.neutral_200');
    }
    return trimmed;
  }

  aboutToAppear(): void {
    this.updateData();
  }

  build() {
    if (this.values.length > 0 && this.totalValue > 0) {
      DataPanel({ values: this.values, max: this.totalValue, type: DataPanelType.Circle })
        .width('100%')
        .height('100%')
        .valueColors(this.colors)
        .strokeWidth($r('app.float.reflect_today_widget_chart_stroke_width'))
        .closeEffect(true)
        .trackBackgroundColor($r('app.color.neutral_200'));
    }
  }
}
