import { TimeRecordUtil } from 'base';

const FULL_PERCENT: string = '100%';
const FORM_DIMENSION_2X2: string = '2*2';
const FORM_DIMENSION_2X4: string = '2*4';
const STORAGE_DIMENSION_KEY: string = 'formDimension';
const STORAGE_ITEMS_KEY: string = 'todayRecordWidgetItems';
const STORAGE_TOTAL_DURATION_KEY: string = 'todayRecordWidgetTotalDuration';

interface ActivityItemPayload {
  id?: string;
  name?: string;
  durationMs?: number;
  tagColorHex?: string;
}

@Observed
class ActivityItem {
  id: string = '';
  name: ResourceStr = '';
  durationMs: number = 0;
  durationLabel: string = '';
  color: ResourceColor = $r('app.color.today_record_widget_dot_placeholder');
}

const widgetStorage: LocalStorage = new LocalStorage();

function resolveDotColor(tagColorHex?: string): ResourceColor {
  if (tagColorHex && tagColorHex.length > 0) {
    return tagColorHex;
  }
  return $r('app.color.today_record_widget_dot_placeholder');
}

@Component
struct TodayRecordActivityRow {
  @ObjectLink item: ActivityItem;
  @Prop isLarge?: boolean;

  build() {
    Row() {
      Row({ space: this.isLarge ? 10 : 5 }) {
        Column()
          .width($r('app.float.today_record_widget_item_dot_size'))
          .height($r('app.float.today_record_widget_item_dot_size'))
          .borderRadius($r('app.float.today_record_widget_dot_radius'))
          .backgroundColor(this.item.color);

        Text(this.item.name)
          .fontSize($r('app.float.today_record_widget_item_name_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .padding({right: 20})
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      Text(this.item.durationLabel)
        .fontSize($r('app.float.today_record_widget_item_duration_font_size'))
        .fontWeight(500)
        .fontColor($r('app.color.text_tertiary'))
        .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
        .letterSpacing($r('app.float.today_record_widget_time_letter_spacing'))
        .margin({ left: $r('app.float.today_record_widget_item_duration_margin_left') });
    }
    .width(FULL_PERCENT)
    .alignItems(VerticalAlign.Center)
  }
}

@Entry(widgetStorage)
@Component
struct TodayRecordWidgetCard {
  @LocalStorageProp(STORAGE_DIMENSION_KEY) @Watch('handleDimensionChange')
  private formDimension: string = FORM_DIMENSION_2X2;
  @LocalStorageProp(STORAGE_ITEMS_KEY) @Watch('handleItemsChange')
  private itemsJson: string = '';
  @LocalStorageProp(STORAGE_TOTAL_DURATION_KEY) @Watch('handleTotalDurationChange')
  private totalDurationRaw: string = '';

  @State private isLarge: boolean = false;
  @State private items: ActivityItem[] = [];
  @State private displayItems: ActivityItem[] = [];
  @State private totalHours: number = 0;
  @State private totalMinutes: number = 0;
  @State private totalDurationLabel: string = '0m';

  aboutToAppear(): void {
    this.applyDimension(this.formDimension);
    this.applyItems(this.itemsJson);
    this.applyTotalDuration(this.totalDurationRaw);
  }

  private handleDimensionChange(): void {
    this.applyDimension(this.formDimension);
  }

  private handleItemsChange(): void {
    this.applyItems(this.itemsJson);
  }

  private handleTotalDurationChange(): void {
    this.applyTotalDuration(this.totalDurationRaw);
  }

  private applyDimension(dimension: string): void {
    this.isLarge = dimension === FORM_DIMENSION_2X4;
    this.updateDisplayItems();
  }

  private applyItems(raw: string): void {
    this.items = this.parseItems(raw);
    this.updateDisplayItems();
  }

  private applyTotalDuration(raw: string): void {
    const parsed = Number(raw);
    const safeDuration = Number.isNaN(parsed) || parsed < 0 ? 0 : parsed;
    const totalMinutes = Math.floor(safeDuration / 60000);
    this.totalHours = Math.floor(totalMinutes / 60);
    this.totalMinutes = totalMinutes % 60;
    const hasHours = this.totalHours > 0;
    this.totalDurationLabel = hasHours
      ? `${this.totalHours}h ${this.totalMinutes}m`
      : `${this.totalMinutes}m`;
  }

  private parseItems(raw: string): ActivityItem[] {
    if (raw.length === 0) {
      return [];
    }

    let parsed: ActivityItemPayload[] = [];
    try {
      parsed = JSON.parse(raw) as ActivityItemPayload[];
    } catch (error) {
      return [];
    }

    return parsed.map((item: ActivityItemPayload, index: number) => this.normalizeItem(item, index));
  }

  private normalizeItem(payload: ActivityItemPayload, index: number): ActivityItem {
    const safeId: string = payload.id && payload.id.length > 0 ? payload.id : `activity-${index}`;
    const safeName: ResourceStr = payload.name && payload.name.length > 0
      ? payload.name
      : $r('app.string.today_record_widget_item_default');
    const safeDuration: number = typeof payload.durationMs === 'number' && payload.durationMs > 0 ? payload.durationMs : 0;
    const safeTagColor: string | undefined = payload.tagColorHex && payload.tagColorHex.length > 0
      ? payload.tagColorHex
      : undefined;

    const item = new ActivityItem();
    item.id = safeId;
    item.name = safeName;
    item.durationMs = safeDuration;
    item.durationLabel = TimeRecordUtil.formatDuration(safeDuration);
    item.color = resolveDotColor(safeTagColor);
    return item;
  }

  private updateDisplayItems(): void {
    this.displayItems = this.items.slice(0);
  }

  private handleCardClick(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'PhoneAbility',
      params: {
        target: 'today'
      }
    });
  }

  private handleAddClick(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'PhoneAbility',
      params: {
        target: 'today',
        openAddSheet: true
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
        Column({ space: $r('app.float.today_record_widget_label_margin_bottom') }) {
          Row() {
            Text($r('app.string.today_record_widget_label'))
              .fontSize($r('app.float.today_record_widget_label_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_tertiary'))
              .letterSpacing($r('app.float.today_record_widget_label_letter_spacing'))

            if (!this.isLarge) {
              Button() {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize($r('app.float.today_record_widget_label_font_size'))
                  .fontWeight(FontWeight.Bold)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .type(ButtonType.Circle)
              .padding(5)
              .backgroundColor($r('app.color.neutral_200'))
              .borderRadius($r('app.float.today_record_widget_refresh_radius'))
              .stateEffect(true)
              .onClick(() => {
                this.handleRefreshClick();
              })
            }
          }
          .width('100%')
          .margin(this.isLarge ? {bottom: 5} : {})
          .justifyContent(this.isLarge ? FlexAlign.Start : FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Top)

          List({ space: this.isLarge ? 6 : 4 }) {
            if (this.displayItems.length > 0) {
              ForEach(this.displayItems, (item: ActivityItem) => {
                ListItem() {
                  TodayRecordActivityRow({ item: item, isLarge: this.isLarge })
                }
              }, (item: ActivityItem) => JSON.stringify(item))
            } else {
              ListItem() {
                Text($r('app.string.today_record_widget_empty'))
                  .fontSize($r('app.float.today_record_widget_item_duration_font_size'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_tertiary'))
                  .opacity($r('app.float.today_record_widget_empty_opacity'))
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .height('100%')
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
        .width(FULL_PERCENT)
        .height(FULL_PERCENT)
        .padding({ right: this.isLarge ? $r('app.float.today_record_widget_list_divider_spacing') : 0 })
        .alignItems(HorizontalAlign.Start)
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
                .letterSpacing($r('app.float.today_record_widget_label_letter_spacing'))


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

                Button() {
                  SymbolGlyph($r('sys.symbol.plus'))
                    .fontSize($r('app.float.today_record_widget_refresh_font_size'))
                    .fontWeight(FontWeight.Bold)
                    .fontColor([$r('app.color.primary')])
                }
                .padding({
                  left: $r('app.float.today_record_widget_refresh_padding_horizontal'),
                  right: $r('app.float.today_record_widget_refresh_padding_horizontal'),
                  top: $r('app.float.today_record_widget_refresh_padding_vertical'),
                  bottom: $r('app.float.today_record_widget_refresh_padding_vertical')
                })
                .type(ButtonType.Circle)
                .height($r('app.float.today_record_widget_refresh_button_size'))
                .backgroundColor($r('app.color.primary_container'))
                .stateEffect(true)
                .onClick(() => {
                  this.handleAddClick();
                })
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
            }
            .height(FULL_PERCENT)
            .padding({ left: $r('app.float.today_record_widget_summary_padding_left') })
            .alignItems(HorizontalAlign.End)
            .justifyContent(FlexAlign.SpaceBetween)
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 }) // Guarantee content has default width limits
          }
          .width(FULL_PERCENT)
          .height(FULL_PERCENT)
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
    .alignItems(ItemAlign.Start)
    .padding($r('app.float.today_record_widget_padding'))
    .backgroundColor($r('app.color.bg_card'))
    .onClick(() => {
      this.handleCardClick();
    })
  }
}
