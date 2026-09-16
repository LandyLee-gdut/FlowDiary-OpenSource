import { EmojiItem, EmojiUtil } from '../EmojiUtil'
import { AppColors } from '../../constants/Color'
@Component
export struct EmojiPanel {
  @State emojis: EmojiItem[] = EmojiUtil.getAll();

  build() {
    Grid() {
      ForEach(this.emojis, (item: EmojiItem) => {
        GridItem() {
          Column() {
            Text(item.char)
              .fontSize(20)
          }
          .onClick(() => {
            // TODO: onclick的回调函数由外部传入，可以为空
          })
          .borderRadius('50%')
          .padding(10)
          .backgroundColor(AppColors.BG_CARD)
        }
      })
    }
    .width('100%')
    .height(100)
    .rowsTemplate('1fr 1fr')
    .columnsGap(5)
    .rowsGap(5)
    .layoutDirection(GridDirection.Row)
  }
}