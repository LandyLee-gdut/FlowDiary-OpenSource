import { AppGradients } from 'base'; // 只需引入渐变配置用于背景色
import { LabelSummaryModel } from 'base'; // 引入数据模型
import { hdsEffect } from '@kit.UIDesignKit';

@Component
export struct LineDataPanel {
  // 【关键修正】使用 @Link 接收父组件传递过来的引用
  @Link @Watch('updateData') summaryData: LabelSummaryModel[];
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
      DataPanel({ values: this.values, max: this.totalValue, type: DataPanelType.Line })
        .width('100%')
        .height('100%')
        .closeEffect(true)
        // 【关键改动】使用从 props 提取的渐变色344
        .valueColors(this.colors)
        .strokeWidth(15) // 你可以根据需要调整线宽
        .trackBackgroundColor($r('app.color.neutral_200'))
    }
      .width('100%')
      .height('100%')
      .visualEffect(this.buildBorderVisualEffect())
  }
}
