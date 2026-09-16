import { IdeaActivity } from 'base';
import { hdsEffect } from '@kit.UIDesignKit';

@Component
export struct IdeaCardDemo {
  @ObjectLink idea: IdeaActivity;

  build() {
    Column() {
      // 上方名称和按钮区域
      Row() {
        Text(this.idea.name)
          .fontSize(16)
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .width('75%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(8)
            .fontWeight(400)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .padding(5)
        .backgroundColor($r('app.color.neutral_100'))
      }
      .height(50)
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 20 })

      // 下方标签和时间信息
      Column() {
        Row() {
          Row()
            .width(8)
            .height(8)
            .borderRadius('50%')
            .margin({ right: 5 })
            .backgroundColor(this.idea.tagColorHex ?? $r('app.color.neutral_200'))
          Text(this.idea.tagName ?? '无标签')
            .fontSize(11)
            .fontWeight(400)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        Row() {
          Text('创建: 今天')
            .fontSize(11)
            .fontWeight(500)
            .fontColor($r('app.color.text_disabled'))

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.sun_max'))
              .fontSize(8)
              .fontWeight(700)
              .fontColor([$r('app.color.neutral_100')])
          }
          .padding(5)
          .backgroundColor($r('app.color.accent'))
        }
        .alignItems(VerticalAlign.Bottom)
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER // 照亮区域
      })
      .buildEffect())
    .borderRadius(15)
    .shadow({
      color: $r('app.color.neutral_300'),
      radius: 50,
    })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.bg_card'))
    .width('100%')
    .padding(15)
    .height('100%')
  }
}