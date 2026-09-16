// CircleDataPanel.ets

import { AppGradients } from 'base' // AppGradients 不再需要，因为颜色已由父组件分配好
import { LabelSummaryModel } from 'base';

@Component
export struct CalendarDayPanel {

  // Use @Prop to receive summary data from parent component
  @Prop @Watch('updateData') summaryData: LabelSummaryModel[] = [];
  @State values: number[] = [];
  @State colors: LinearGradient[] = [];
  @State totalValue: number = 0;

  private updateData() {
    if (this.summaryData && this.summaryData.length > 0) {
      this.values = this.summaryData.map(item => item.totalMinutes);
      this.colors = this.summaryData.map(item =>
        AppGradients.getGradientForColor(item.labelColor)
      );
      this.totalValue = this.values.reduce((sum, val) => sum + val, 0) || 1;
    } else {
      this.values = [];
      this.colors = [];
      this.totalValue = 1;
    }
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
        .strokeWidth(5)
        .trackBackgroundColor($r('app.color.neutral_200'))
        .closeEffect(true)
    } else {
      // Show empty circle for days with no data
      Circle()
        .width('100%')
        .height('100%')
        .stroke($r('app.color.neutral_200'))
        .strokeWidth(3)
        .fill(Color.Transparent)
    }
  }
}
