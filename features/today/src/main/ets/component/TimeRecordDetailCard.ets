import { ColorUtil, TimeRecord, TimeRecordUtil } from "base"

@Component

export struct TimeRecordDetailCard {
  @ObjectLink record: TimeRecord;
  @Prop itemColor: ResourceColor;

  build() {
    Row() {
      Row() {
        Text(`${TimeRecordUtil.formatDuration(this.record.duration)}`)
          .fontWeight(600)
          .fontSize(14)
          .fontColor(this.itemColor)
          .textAlign(TextAlign.Center)
      }
      .justifyContent(FlexAlign.Center)
      .width(70)
      .borderRadius(10)
      .padding({ top: 10, bottom: 10 })
      .backgroundColor(ColorUtil.generateLighterColor(this.itemColor as string))
      .margin({ right: 10 })

      Text(`${TimeRecordUtil.formatToHHmm(this.record.startTime)} - ${TimeRecordUtil.formatToHHmm(this.record.endTime)}`)
        .fontWeight(600)
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }
}
