import { IdeaCollection } from '../model/IdeaPoolModels';

@Component
export struct IdeaCollectionPicker {
  @Prop label: ResourceStr = '';
  @Prop collections: IdeaCollection[] = [];
  @Prop selectedCollectionId: string | null = null;
  @Prop showLooseOption: boolean = true;
  @Prop isDarkTheme: boolean = false;
  onSelectionChange?: (collectionId: string | null) => void;

  private normalizeCollectionId(collectionId: string | null): string | null {
    if (!collectionId) {
      return null;
    }
    const trimmed: string = collectionId.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  private isSelected(candidateId: string | null): boolean {
    return this.normalizeCollectionId(this.selectedCollectionId) === this.normalizeCollectionId(candidateId);
  }

  private resolveSelectedBackgroundColor(collection: IdeaCollection | null): ResourceColor {
    if (collection) {
      return collection.tagColorHex ?? $r('app.color.primary');
    }
    return $r('app.color.ideapool_collection_selector_selected_bg');
  }

  private resolveSelectedTextColor(collection: IdeaCollection | null): ResourceColor {
    if (collection) {
      return collection.tagLightColorHex ?? $r('app.color.neutral_100');
    }
    return $r('app.color.ideapool_collection_selector_selected_text');
  }

  private resolveUnselectedTextColor(): ResourceColor {
    return $r('app.color.text_secondary');
  }

  private resolvePillBackgroundColor(isSelected: boolean, collection: IdeaCollection | null): ResourceColor {
    return isSelected ? this.resolveSelectedBackgroundColor(collection) : $r('app.color.neutral_100');
  }

  private resolvePillTextColor(isSelected: boolean, collection: IdeaCollection | null): ResourceColor {
    return isSelected ? this.resolveSelectedTextColor(collection) : this.resolveUnselectedTextColor();
  }

  build() {
    Column() {
      if (this.label) {
        Text(this.label)
          .fontSize($r('app.float.ideapool_collection_label_text_size'))
          .fontWeight(500)
          .margin({ bottom: $r('app.float.ideapool_collection_label_margin_bottom') })
      }

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        if (this.showLooseOption) {
          Row() {
            Text($r('app.string.ideapool_collection_loose_icon'))
              .fontSize($r('app.float.ideapool_collection_tag_text_size'))
              .fontColor(this.resolvePillTextColor(this.isSelected(null), null))
              .margin({ right: $r('app.float.ideapool_collection_tag_icon_gap') })

            Text($r('app.string.ideapool_collection_loose_label'))
              .fontSize($r('app.float.ideapool_collection_tag_text_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.resolvePillTextColor(this.isSelected(null), null))
          }
          .height($r('app.float.ideapool_collection_tag_height'))
          .alignItems(VerticalAlign.Center)
          .padding({
            left: $r('app.float.ideapool_collection_tag_padding_horizontal'),
            right: $r('app.float.ideapool_collection_tag_padding_horizontal'),
            top: $r('app.float.ideapool_collection_tag_padding_vertical'),
            bottom: $r('app.float.ideapool_collection_tag_padding_vertical')
          })
          .margin({
            right: $r('app.float.ideapool_collection_tag_margin_right'),
            bottom: $r('app.float.ideapool_collection_tag_margin_bottom')
          })
          .borderRadius($r('app.float.ideapool_collection_tag_radius'))
          .backgroundColor(this.resolvePillBackgroundColor(this.isSelected(null), null))
          .opacity(this.isDarkTheme ? 0.95 : 1)
          .onClick(() => {
            if (!this.isSelected(null)) {
              this.onSelectionChange?.(null);
            }
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
        }

        ForEach(this.collections, (collection: IdeaCollection) => {
          Row() {
            Text(collection.icon ? collection.icon : $r('app.string.ideapool_collection_default_icon'))
              .fontSize($r('app.float.ideapool_collection_tag_text_size'))
              .fontColor(this.resolvePillTextColor(this.isSelected(collection.id), collection))
              .margin({ right: $r('app.float.ideapool_collection_tag_icon_gap') })

            Text(collection.name)
              .fontSize($r('app.float.ideapool_collection_tag_text_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.resolvePillTextColor(this.isSelected(collection.id), collection))
          }
          .height($r('app.float.ideapool_collection_tag_height'))
          .alignItems(VerticalAlign.Center)
          .padding({
            left: $r('app.float.ideapool_collection_tag_padding_horizontal'),
            right: $r('app.float.ideapool_collection_tag_padding_horizontal'),
            top: $r('app.float.ideapool_collection_tag_padding_vertical'),
            bottom: $r('app.float.ideapool_collection_tag_padding_vertical')
          })
          .margin({
            right: $r('app.float.ideapool_collection_tag_margin_right'),
            bottom: $r('app.float.ideapool_collection_tag_margin_bottom')
          })
          .borderRadius($r('app.float.ideapool_collection_tag_radius'))
          .backgroundColor(this.resolvePillBackgroundColor(this.isSelected(collection.id), collection))
          .opacity(this.isDarkTheme ? 0.95 : 1)
          .onClick(() => {
            if (!this.isSelected(collection.id)) {
              this.onSelectionChange?.(collection.id);
            }
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
        }, (collection: IdeaCollection) => collection.id)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
