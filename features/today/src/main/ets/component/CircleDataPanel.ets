// CircleDataPanel.ets

import { AppGradients, LabelSummaryModel, BreakpointConstants, BreakpointSystem, BreakpointType } from 'base';
import { hdsEffect } from '@kit.UIDesignKit';

@Component
export struct CircleDataPanel {
  // 【关键修正】使用 @Link 接收父组件传递过来的引用
  @Link @Watch('updateData') summaryData: LabelSummaryModel[];
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @State values: number[] = [];
  @State colors: LinearGradient[] = [];
  @State totalValue: number = 0;

  private updateData() {
    this.values = this.summaryData.map(item => item.totalMinutes);
    this.colors = this.summaryData.map(item =>
      AppGradients.getGradientForColor(item.labelColor)
    );
    this.totalValue = this.values.reduce((sum, val) => sum + val, 0) || 1;
  }

  aboutToAppear(): void {
    this.updateData();
  }

  private buildBorderVisualEffect(): VisualEffect | undefined {
    if (!canIUse('SystemCapability.UIDesign.HDSComponent.Core')) {
      return undefined;
    }
    return new hdsEffect.HdsEffectBuilder()
      .pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect();
  }

  build() {
    Stack() {
      DataPanel({ values: this.values, max: this.totalValue, type: DataPanelType.Circle })
        .width('100%')
        .height('100%')
        .valueColors(this.colors)
        .strokeWidth(new BreakpointType<number>({ sm: 18, md: 25, lg: 30 }).getValue(this.currentBreakpoint))
        .closeEffect(true)
        .trackBackgroundColor($r('app.color.neutral_200'))
    }
      .width('100%')
      .height('100%')
      .visualEffect(this.buildBorderVisualEffect())
  }
}
