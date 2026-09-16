import { AppShadows } from "base/src/main/ets/constants/Shadow"

@Component
export struct MatterDetailCard {
  @Prop title: string;
  @Prop value: string;
  @Prop valueColor: ResourceColor;

  build() {
    Column() {
      Text(this.title)
        .fontSize(12)
        .fontWeight(500)
        .fontColor($r('app.color.text_tertiary'))
        .margin({bottom: 5})
        .textAlign(TextAlign.Center)

      Text(this.value)
        .fontSize(24)
        .fontWeight(700)
        .fontColor(this.valueColor)
        .textAlign(TextAlign.Center)
    }
    .shadow(AppShadows.CARD_RESTING)
    .padding({left: 10, right: 10, top: 5, bottom: 5})
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .borderRadius(15)
    .backgroundColor($r('app.color.bg_card'))
    .width('100%')
    .height('100%')
  }
}
