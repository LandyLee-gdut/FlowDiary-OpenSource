@Component
export struct TabsDisplayRow {
  @Link
  build() {
    Grid() {
      ForEach(
        this.newTagColor,
        (color: string, index: number) => {
          GridItem() {
            Column()
              .clickEffect({level: ClickEffectLevel.MIDDLE, scale: 0.8})
              .onClick(() => {
                this.selectedLabelIndex = index;
                this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch')
              })
              .border(this.selectedLabelIndex == index ? {width: 3, color: $r('app.color.accent')} : {width: 0})
              .width(30)
              .height(30)
              .backgroundColor(color)
              .borderRadius('50%')
          }
        }
      )
    }
    .columnsGap(10)
  }
}