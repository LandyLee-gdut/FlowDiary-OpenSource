import { IdeaCollection, AppShadows } from 'base'
import { IdeaCollectionCardEntryViewModel } from '../model/IdeaCollectionCardEntryViewModel'
import { IdeaCollectionCard } from './IdeaCollectionCard'

@Component
export struct IdeaCollectionGridRow {
  @Prop items: IdeaCollectionCardEntryViewModel[];
  @Prop cardWidth: number;
  @Prop cardHeight: number;
  @BuilderParam addNewItemBuilder?: () => void;
  onSelect?: (collection: IdeaCollection) => void;

  private getEffectiveCardWidth(): number {
    return this.cardWidth * 0.92;
  }

  private getEffectiveCardHeight(): number {
    return this.cardHeight * 0.88;
  }

  build() {
    if (this.items.length > 0 || this.addNewItemBuilder) {
      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.items, (item: IdeaCollectionCardEntryViewModel) => {
            Column() {
              IdeaCollectionCard({
                entry: item
              })

                .width('100%')
                .height('100%')
            }
            .width(this.getEffectiveCardWidth())
            .height(this.getEffectiveCardHeight())
            .onClick(() => {
              if (this.onSelect) {
                this.onSelect(item.collection);
              }
            })
          }, (item: IdeaCollectionCardEntryViewModel) => item.id)
          if (this.addNewItemBuilder) {
            Column() {
              this.addNewItemBuilder();
            }
            .width(this.getEffectiveCardWidth())
            .height(this.getEffectiveCardHeight())
          }
        }
        .height(this.getEffectiveCardHeight())
        .padding({ left: $r('app.float.page_content_padding_horizontal'), right: $r('app.float.page_content_padding_horizontal') })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .clip(false)
      .width('100%')
      .height(this.getEffectiveCardHeight())
    }
  }
}
