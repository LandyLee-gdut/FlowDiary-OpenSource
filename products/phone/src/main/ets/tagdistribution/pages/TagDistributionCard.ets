import { TimeRecordUtil } from 'base';

const FULL_PERCENT: string = '100%';
const FORM_DIMENSION_2X2: string = '2*2';
const FORM_DIMENSION_2X4: string = '2*4';
const STORAGE_DIMENSION_KEY: string = 'formDimension';
const STORAGE_ITEMS_KEY: string = 'tagDistributionWidgetItems';
const ROUTER_ABILITY_NAME: string = 'PhoneAbility';
const ROUTER_TARGET_REFLECT: string = 'reflect';

interface TagDistributionItemPayload {
  id?: string;
  name?: string;
  durationMs?: number;
  tagColorHex?: string;
}

@Observed
class TagDistributionItem {
  id: string = '';
  name: ResourceStr = '';
  durationMs: number = 0;
  durationLabel: string = '';
  ratioWidth: string = '0%';
  color: ResourceColor = $r('app.color.neutral_200');
}

const tagDistributionStorage: LocalStorage = new LocalStorage();

@Component
struct TagDistributionRow {
  @ObjectLink item: TagDistributionItem;
  @Prop showMeta: boolean = true;
  @Prop isLarge: boolean = false;

  build() {
    Row({ space: this.showMeta ? 6 : 4 }) {
      Text(this.item.name)
        .fontSize($r('app.float.tag_distribution_widget_item_label_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.isLarge ? '15%' : '25%')

      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(FULL_PERCENT)
          .height($r('app.float.tag_distribution_widget_bar_height'))
          .borderRadius($r('app.float.tag_distribution_widget_bar_radius'))
          .backgroundColor($r('app.color.neutral_200'));

        Row()
          .width(this.item.ratioWidth)
          .height($r('app.float.tag_distribution_widget_bar_height'))
          .borderRadius($r('app.float.tag_distribution_widget_bar_radius'))
          .backgroundColor(this.item.color)
          .opacity($r('app.float.tag_distribution_widget_bar_fill_opacity'));
      }
      .layoutWeight(1)
      .height($r('app.float.tag_distribution_widget_bar_height'));

      if (this.showMeta) {
        Text(this.item.durationLabel)
          .fontSize($r('app.float.tag_distribution_widget_value_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.End)
          .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
          .letterSpacing($r('app.float.tag_distribution_widget_value_letter_spacing'))
          .width('20%')
      }
    }
    .width(FULL_PERCENT)
    .alignItems(VerticalAlign.Center);
  }
}

@Entry(tagDistributionStorage)
@Component
struct TagDistributionCard {
  @LocalStorageProp(STORAGE_DIMENSION_KEY) @Watch('handleDimensionChange')
  private formDimension: string = FORM_DIMENSION_2X2;
  @LocalStorageProp(STORAGE_ITEMS_KEY) @Watch('handleItemsChange')
  private itemsJson: string = '';

  @State private isLarge: boolean = false;
  @State private items: TagDistributionItem[] = [];
  @State private totalDurationLabel: string = '0m';
  @State private totalHours: number = 0;
  @State private totalMinutes: number = 0;

  aboutToAppear(): void {
    this.applyDimension(this.formDimension);
    this.applyItems(this.itemsJson);
  }

  private handleDimensionChange(): void {
    this.applyDimension(this.formDimension);
  }

  private handleItemsChange(): void {
    this.applyItems(this.itemsJson);
  }

  private applyDimension(dimension: string): void {
    this.isLarge = dimension === FORM_DIMENSION_2X4;
  }

  private applyItems(raw: string): void {
    this.items = this.parseItems(raw, this.items);
    this.updateTotalDuration(this.items);
  }

  private parseItems(raw: string, existingItems: TagDistributionItem[]): TagDistributionItem[] {
    if (raw.length === 0) {
      return [];
    }

    let parsed: TagDistributionItemPayload[] = [];
    try {
      parsed = JSON.parse(raw) as TagDistributionItemPayload[];
    } catch (error) {
      return [];
    }

    const maxDuration = this.resolveMaxDuration(parsed);
    const existingMap = new Map<string, TagDistributionItem>();
    existingItems.forEach((item: TagDistributionItem) => {
      existingMap.set(item.id, item);
    });
    const items = parsed.map((payload: TagDistributionItemPayload, index: number) => {
      const normalized = this.normalizeItem(payload, index, maxDuration);
      const existing = existingMap.get(normalized.id);
      if (existing) {
        existing.name = normalized.name;
        existing.durationMs = normalized.durationMs;
        existing.durationLabel = normalized.durationLabel;
        existing.ratioWidth = normalized.ratioWidth;
        existing.color = normalized.color;
        return existing;
      }
      return normalized;
    });
    items.sort((a: TagDistributionItem, b: TagDistributionItem) => b.durationMs - a.durationMs);
    return items;
  }

  private resolveMaxDuration(payloads: TagDistributionItemPayload[]): number {
    let maxDuration = 0;
    payloads.forEach((payload: TagDistributionItemPayload) => {
      const duration = typeof payload.durationMs === 'number' && payload.durationMs > 0 ? payload.durationMs : 0;
      if (duration > maxDuration) {
        maxDuration = duration;
      }
    });
    return maxDuration > 0 ? maxDuration : 1;
  }

  private normalizeItem(payload: TagDistributionItemPayload, index: number, maxDuration: number): TagDistributionItem {
    const safeId = payload.id && payload.id.length > 0
      ? payload.id
      : (payload.name && payload.name.length > 0 ? payload.name : `tag-${index}`);
    const safeName: ResourceStr = payload.name && payload.name.length > 0
      ? payload.name
      : $r('app.string.tag_distribution_widget_item_default');
    const safeDuration = typeof payload.durationMs === 'number' && payload.durationMs > 0 ? payload.durationMs : 0;

    const item = new TagDistributionItem();
    item.id = safeId;
    item.name = safeName;
    item.durationMs = safeDuration;
    item.durationLabel = TimeRecordUtil.formatDuration(safeDuration);
    item.ratioWidth = this.resolveRatioWidth(safeDuration, maxDuration);
    item.color = this.resolveTagColor(payload.tagColorHex);
    return item;
  }

  private resolveRatioWidth(durationMs: number, maxDuration: number): string {
    const safeMax = maxDuration > 0 ? maxDuration : 1;
    const ratio = Math.max(0, Math.min(1, durationMs / safeMax));
    return `${ratio * 100}%`;
  }

  private resolveTagColor(tagColorHex?: string): ResourceColor {
    if (tagColorHex && tagColorHex.length > 0) {
      return tagColorHex;
    }
    return $r('app.color.neutral_200');
  }

  private updateTotalDuration(items: TagDistributionItem[]): void {
    let totalDuration = 0;
    items.forEach((item: TagDistributionItem) => {
      totalDuration += item.durationMs;
    });
    this.totalDurationLabel = TimeRecordUtil.formatDuration(totalDuration);

    const totalMinutes = Math.floor(totalDuration / 60000);
    this.totalHours = Math.floor(totalMinutes / 60);
    this.totalMinutes = totalMinutes % 60;
  }

  private handleCardClick(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: ROUTER_ABILITY_NAME,
      params: {
        target: ROUTER_TARGET_REFLECT
      }
    });
  }

  private handleRefreshClick(): void {
    postCardAction(this, {
      action: 'message',
      params: {
        action: 'refresh'
      }
    });
  }

  build() {
    GridRow({
      columns: 4,
      gutter: 0,
      direction: GridRowDirection.Row
    }) {
      GridCol({ span: this.isLarge ? 3 : 4 }) {
        Column() {
          Row() {
             Text($r('app.string.tag_distribution_widget_label'))
              .fontSize($r('app.float.tag_distribution_widget_title_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_tertiary'))
              .letterSpacing($r('app.float.tag_distribution_widget_title_letter_spacing'));

            if (!this.isLarge) {
               Text(this.totalDurationLabel)
                .fontSize($r('app.float.tag_distribution_widget_total_font_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                .letterSpacing($r('app.float.tag_distribution_widget_value_letter_spacing'));
            }
          }
          .width(FULL_PERCENT)
          .margin({ bottom: $r('app.float.tag_distribution_widget_title_margin_bottom_compact') })
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Center);

          List({ space: 10 }) {
            if (this.items.length > 0) {
              ForEach(this.items, (item: TagDistributionItem) => {
                ListItem() {
                  TagDistributionRow({
                    item: item,
                    showMeta: this.isLarge,
                    isLarge: this.isLarge
                  })
                }
              }, (item: TagDistributionItem) => item.id)
            } else {
              ListItem() {
                Text($r('app.string.tag_distribution_widget_empty'))
                  .fontSize($r('app.float.tag_distribution_widget_empty_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_tertiary'))
                  .opacity($r('app.float.tag_distribution_widget_empty_opacity'))
                  .textAlign(TextAlign.Center)
                  .width(FULL_PERCENT)
                  .height(FULL_PERCENT);
              }
            }
          }
          .layoutWeight(1)
          .width(FULL_PERCENT)
          .scrollBar(BarState.Off);
        }
        .width(FULL_PERCENT)
        .height(FULL_PERCENT)
        .padding({ right: this.isLarge ? $r('app.float.today_record_widget_list_divider_spacing') : 0 })
      }

      if (this.isLarge) {
        GridCol({ span: 1 }) {
          Row() {
            Column()
              .width($r('app.float.today_record_widget_divider_width'))
              .height(FULL_PERCENT)
              .backgroundColor($r('app.color.today_record_widget_divider'))

            Column() {
              Text($r('app.string.today_record_widget_total_label'))
                .fontSize($r('app.float.today_record_widget_label_font_size'))
                .fontWeight(500)
                .fontColor($r('app.color.text_tertiary'))
                .textAlign(TextAlign.End)
                .width('100%')
                .letterSpacing($r('app.float.today_record_widget_label_letter_spacing'));

              Column() {
                if (this.totalHours > 0) {
                  Row () {
                    Text(`${this.totalHours}`)
                      .fontSize(28)
                      .fontWeight(FontWeight.Bold)
                      .margin({right: 2})
                      .fontColor($r('app.color.primary'))
                      .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                      .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))

                    Text('h')
                      .fontSize(20)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.primary_light'))
                      .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                      .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Bottom)
                  .justifyContent(FlexAlign.End)

                  Row () {
                    Text(`${this.totalMinutes}`)
                      .fontSize(24)
                      .fontWeight(FontWeight.Bold)
                      .margin({right: 2})
                      .fontColor($r('app.color.primary'))
                      .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                      .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))

                    Text('m')
                      .fontSize(20)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.primary_light'))
                      .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                      .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Bottom)
                  .justifyContent(FlexAlign.End)
                } else {
                  Text() {
                    Span(`${this.totalMinutes}`)
                      .fontSize($r('app.float.today_record_widget_total_hours_font_size'))
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.primary'))
                      .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                      .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                    Span('m')
                      .fontSize($r('app.float.font_size'))
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_tertiary'))
                      .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                      .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                  }
                  .textAlign(TextAlign.End)
                  .width('100%')
                }
              }
              .layoutWeight(1)
              .width('100%')
              .alignItems(HorizontalAlign.End)
              .justifyContent(FlexAlign.Center)

              Row() {
                Button() {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize($r('app.float.today_record_widget_refresh_font_size'))
                    .fontWeight(FontWeight.Bold)
                    .fontColor([$r('app.color.text_secondary')])
                }
                .type(ButtonType.Circle)
                .height($r('app.float.today_record_widget_refresh_button_size'))
                .padding({
                  left: $r('app.float.today_record_widget_refresh_padding_horizontal'),
                  right: $r('app.float.today_record_widget_refresh_padding_horizontal'),
                  top: $r('app.float.today_record_widget_refresh_padding_vertical'),
                  bottom: $r('app.float.today_record_widget_refresh_padding_vertical')
                })
                .backgroundColor($r('app.color.neutral_200'))
                .borderRadius($r('app.float.today_record_widget_refresh_radius'))
                .stateEffect(true)
                .onClick(() => {
                  this.handleRefreshClick();
                })
              }
              .width('100%')
              .justifyContent(FlexAlign.End)
            }
             .layoutWeight(1)
             .height(FULL_PERCENT)
             .padding({ left: $r('app.float.today_record_widget_summary_padding_left') })
             .alignItems(HorizontalAlign.End)
             .justifyContent(FlexAlign.SpaceBetween)
          }
        }
      }
    }
    .linearGradient({
      direction: GradientDirection.RightTop,
      colors: [
        [$r('app.color.accent_lighter'), 0],
        [$r('app.color.primary_lighter'), 1],
      ]
    })
    .width(FULL_PERCENT)
    .height(FULL_PERCENT)
    .padding($r('app.float.tag_distribution_widget_padding'))
    .backgroundColor($r('app.color.bg_card'))
    .onClick(() => {
      this.handleCardClick();
    });
  }
}
