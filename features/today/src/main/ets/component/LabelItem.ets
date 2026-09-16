@Component
export struct LabelItem {
  @Prop labelWidth: number;
  @Prop labelName: string;
  @Prop labelMargin?: number = 5;
  @Prop labelColor: ResourceColor = '#FFFFFF';
  @Prop fontSize?: number = 12

  build() {
    Row() {
      Row()
        .width(this.labelWidth)
        .height(this.labelWidth)
        .borderRadius('50%')
        .margin({right: this.labelMargin ? this.labelMargin : 5})
        .backgroundColor(this.labelColor)
      Text(this.labelName)
        .fontSize(this.fontSize)
        .fontWeight(400)
        .fontColor($r('app.color.text_secondary'))
        .flexShrink(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }
}
