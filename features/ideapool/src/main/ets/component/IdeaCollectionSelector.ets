import { IdeaCollection } from 'base';

interface IdeaCollectionSelectorPillParams {
  id: string | null;
  title: ResourceStr;
  icon: ResourceStr;
}

@Component
export struct IdeaCollectionSelector {
  @Require @Prop label: ResourceStr;
  @Require @Prop collections: IdeaCollection[];
  @Prop selectedCollectionId: string | null = null;
  @Prop showLooseOption: boolean = true;
  @Prop looseTitle: ResourceStr = $r('app.string.ideapool_collection_loose_label');
  @Prop looseIcon: ResourceStr = $r('app.string.ideapool_collection_loose_icon');
  @Prop isDarkTheme: boolean = false;
  onSelectionChange?: (collectionId: string | null) => void;

  build() {
    Column() {
      Text(this.label)
        .fontSize($r('app.float.ideapool_collection_label_text_size'))
        .fontWeight(500)
        .margin({ bottom: $r('app.float.ideapool_collection_label_margin_bottom') })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        if (this.showLooseOption) {
          this.CollectionPill({
            id: null,
            title: this.looseTitle,
            icon: this.looseIcon
          })
        }

        ForEach(this.collections, (collection: IdeaCollection) => {
          this.CollectionPill({
            id: collection.id,
            title: collection.name,
            icon: collection.icon ? collection.icon : $r('app.string.ideapool_collection_default_icon')
          })
        }, (collection: IdeaCollection) => collection.id)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private CollectionPill(params: IdeaCollectionSelectorPillParams) {
    Row() {
      Text(params.icon)
        .fontSize($r('app.float.ideapool_collection_tag_text_size'))
        .fontColor(this.isPillSelected(params.id)
          ? $r('app.color.ideapool_collection_selector_selected_text')
          : $r('app.color.text_secondary'))
        .margin({ right: $r('app.float.ideapool_collection_tag_icon_gap') })

      Text(params.title)
        .fontSize($r('app.float.ideapool_collection_tag_text_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isPillSelected(params.id)
          ? $r('app.color.ideapool_collection_selector_selected_text')
          : $r('app.color.text_secondary'))
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
    .backgroundColor(this.isPillSelected(params.id) ? $r('app.color.ideapool_collection_selector_selected_bg') : $r('app.color.neutral_100'))
    .opacity(this.isDarkTheme ? 0.95 : 1)
    .onClick(() => {
      if (!this.isPillSelected(params.id)) {
        this.onSelectionChange?.(params.id);
      }
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
  }

  private isPillSelected(collectionId: string | null): boolean {
    const current: string | null = this.normalizeCollectionId(this.selectedCollectionId);
    const candidate: string | null = this.normalizeCollectionId(collectionId);
    return current === candidate;
  }

  private normalizeCollectionId(collectionId: string | null): string | null {
    if (!collectionId) {
      return null;
    }
    const trimmed: string = collectionId.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
}
