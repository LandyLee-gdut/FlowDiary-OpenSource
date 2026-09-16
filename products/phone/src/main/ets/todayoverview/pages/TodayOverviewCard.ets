const TODAY_OVERVIEW_FULL_PERCENT: string = '100%';
const TODAY_OVERVIEW_DIMENSION_1X2: string = '1*2';
const TODAY_OVERVIEW_DIMENSION_2X2: string = '2*2';
const TODAY_OVERVIEW_STORAGE_DIMENSION_KEY: string = 'formDimension';
const STORAGE_TOTAL_DURATION_KEY: string = 'todayOverviewTotalDuration';
const STORAGE_ITEM_COUNT_KEY: string = 'todayOverviewItemCount';
const TODAY_OVERVIEW_ROUTER_ABILITY_NAME: string = 'PhoneAbility';
const TODAY_OVERVIEW_ROUTER_TARGET_TODAY: string = 'today';

const overviewStorage: LocalStorage = new LocalStorage();

@Entry(overviewStorage)
@Component
struct TodayOverviewCard {
  @LocalStorageProp(TODAY_OVERVIEW_STORAGE_DIMENSION_KEY) @Watch('handleDimensionChange')
  private formDimension: string = TODAY_OVERVIEW_DIMENSION_2X2;
  @LocalStorageProp(STORAGE_TOTAL_DURATION_KEY) @Watch('handleTotalDurationChange')
  private totalDurationRaw: string = '';
  @LocalStorageProp(STORAGE_ITEM_COUNT_KEY) @Watch('handleItemCountChange')
  private itemCountRaw: string = '';

  @State private isCompact: boolean = false;
  @State private totalHours: number = 0;
  @State private totalMinutes: number = 0;
  @State private totalHoursLabel: string = '0';
  @State private totalMinutesLabel: string = '0';
  @State private itemCount: number = 0;

  aboutToAppear(): void {
    this.applyDimension(this.formDimension);
    this.applyTotalDuration(this.totalDurationRaw);
    this.applyItemCount(this.itemCountRaw);
  }

  private handleDimensionChange(): void {
    this.applyDimension(this.formDimension);
  }

  private handleTotalDurationChange(): void {
    this.applyTotalDuration(this.totalDurationRaw);
  }

  private handleItemCountChange(): void {
    this.applyItemCount(this.itemCountRaw);
  }

  private applyTotalDuration(raw: string): void {
    const parsed = Number(raw);
    const safeDuration = Number.isNaN(parsed) || parsed < 0 ? 0 : parsed;
    const totalMinutes = Math.floor(safeDuration / 60000);
    this.totalHours = Math.floor(totalMinutes / 60);
    this.totalMinutes = totalMinutes % 60;
    this.totalHoursLabel = this.padTime(this.totalHours);
    this.totalMinutesLabel = this.padTime(this.totalMinutes);
  }

  private applyItemCount(raw: string): void {
    const parsed = Number(raw);
    const safeCount = Number.isNaN(parsed) || parsed < 0 ? 0 : parsed;
    this.itemCount = Math.floor(safeCount);
  }

  private applyDimension(dimension: string): void {
    this.isCompact = dimension === TODAY_OVERVIEW_DIMENSION_1X2;
  }

  private padTime(value: number): string {
    return value.toString().padStart(2, '0');
  }

  private handleCardClick(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: TODAY_OVERVIEW_ROUTER_ABILITY_NAME,
      params: {
        target: TODAY_OVERVIEW_ROUTER_TARGET_TODAY
      }
    });
  }

  private handleAddClick(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: TODAY_OVERVIEW_ROUTER_ABILITY_NAME,
      params: {
        target: TODAY_OVERVIEW_ROUTER_TARGET_TODAY,
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
    Column() {
      if (this.isCompact) {
        Row() {
          Column() {
            Text($r('app.string.today_overview_widget_label'))
              .fontSize($r('app.float.today_overview_widget_small_label_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .letterSpacing($r('app.float.today_overview_widget_label_letter_spacing'))
            Row({ space: 2 }) {
              Row({space:1}) {
                Text(`${this.totalHours}`)
                  .fontSize($r('app.float.today_overview_widget_small_time_font_size'))
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary'))
                  .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                  .letterSpacing($r('app.float.today_overview_widget_time_letter_spacing'))

                Text($r('app.string.today_overview_widget_unit_hour'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary'))
                  .opacity($r('app.float.today_overview_widget_unit_opacity'))
                  .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                  .letterSpacing($r('app.float.today_overview_widget_time_letter_spacing'))
              }
              .alignItems(VerticalAlign.Bottom)

              Row({space:1}) {
                Text(`${this.totalMinutes }`)
                  .fontSize($r('app.float.today_overview_widget_small_time_font_size'))
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary'))
                  .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                  .letterSpacing($r('app.float.today_overview_widget_time_letter_spacing'))

                Text($r('app.string.today_overview_widget_unit_minute'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary'))
                  .opacity($r('app.float.today_overview_widget_unit_opacity'))
                  .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                  .letterSpacing($r('app.float.today_overview_widget_time_letter_spacing'))
              }
              .alignItems(VerticalAlign.Bottom)
            }
            .offset({ y: -4 })
            .alignItems(VerticalAlign.Top)
          }
          .height(TODAY_OVERVIEW_FULL_PERCENT)
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)

          Row() {
            Button() {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize($r('app.float.today_overview_widget_action_icon_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor([$r('app.color.primary')])
            }
            .width($r('app.float.today_overview_widget_action_size'))
            .height($r('app.float.today_overview_widget_action_size'))
            .type(ButtonType.Circle)
            .backgroundColor($r('app.color.primary_container'))
            .stateEffect(true)
            .onClick(() => {
              this.handleAddClick();
            })
          }
          .alignItems(VerticalAlign.Top)
          .height(TODAY_OVERVIEW_FULL_PERCENT)
        }
        .height(TODAY_OVERVIEW_FULL_PERCENT)
        .width(TODAY_OVERVIEW_FULL_PERCENT)
        .alignItems(VerticalAlign.Top)
        .justifyContent(FlexAlign.SpaceBetween)
      } else {
        Column() {
          Row() {
            Text($r('app.string.today_overview_widget_label'))
              .fontSize($r('app.float.today_overview_widget_label_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .letterSpacing($r('app.float.today_overview_widget_label_letter_spacing'))

            Button() {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize($r('app.float.today_overview_widget_label_font_size'))
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
          .width(TODAY_OVERVIEW_FULL_PERCENT)
          .justifyContent(FlexAlign.SpaceBetween)
          .alignItems(VerticalAlign.Top)

          Row({space: 4}) {
            Row() {
              Text(`${this.totalHours}`)
                .fontSize($r('app.float.today_overview_widget_hours_font_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary'))
                .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                .letterSpacing($r('app.float.today_overview_widget_time_letter_spacing'))

              Text($r('app.string.today_overview_widget_unit_hour'))
                .fontSize($r('app.float.today_overview_widget_hours_unit_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary'))
                .opacity($r('app.float.today_overview_widget_unit_opacity'))
                .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                .letterSpacing($r('app.float.today_overview_widget_time_letter_spacing'))
                .margin({ left: $r('app.float.today_overview_widget_unit_margin_left') })
            }
            .alignItems(VerticalAlign.Bottom)

            Row() {
              Text(`${this.totalMinutes}`)
                .fontSize($r('app.float.today_overview_widget_hours_font_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary'))
                .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                .letterSpacing($r('app.float.today_overview_widget_time_letter_spacing'))

              Text($r('app.string.today_overview_widget_unit_minute'))
                .fontSize($r('app.float.today_overview_widget_hours_unit_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.primary'))
                .opacity($r('app.float.today_overview_widget_unit_opacity'))
                .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
                .letterSpacing($r('app.float.today_overview_widget_time_letter_spacing'))
                .margin({ left: $r('app.float.today_overview_widget_unit_margin_left') })
            }
            .alignItems(VerticalAlign.Bottom)
          }
          .margin({ top: $r('app.float.today_overview_widget_title_margin_top') })
          .justifyContent(FlexAlign.End)
        }
        .alignItems(HorizontalAlign.Start)

        Row() {
          Column({ space: $r('app.float.today_overview_widget_item_gap') }) {
            Text($r('app.string.today_overview_widget_item_label'))
              .fontSize($r('app.float.today_overview_widget_item_label_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_tertiary'))

            Text(`${this.itemCount} 个`)
              .fontSize($r('app.float.today_overview_widget_item_count_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)

          Button() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize($r('app.float.today_overview_widget_action_icon_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor([$r('app.color.primary')])
          }
          .width($r('app.float.today_overview_widget_action_size'))
          .height($r('app.float.today_overview_widget_action_size'))
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.primary_container'))
          .stateEffect(true)
          .onClick(() => {
            this.handleAddClick();
          })
        }
        .width(TODAY_OVERVIEW_FULL_PERCENT)
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Bottom)
      }
    }
    .width(TODAY_OVERVIEW_FULL_PERCENT)
    .height(TODAY_OVERVIEW_FULL_PERCENT)
    .padding(this.isCompact
      ? $r('app.float.today_overview_widget_small_padding')
      : $r('app.float.today_overview_widget_padding'))
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(HorizontalAlign.Start)
    .linearGradient({
      direction: GradientDirection.RightTop,
      colors: [
        [$r('app.color.accent_lighter'), 0],
        [$r('app.color.primary_lighter'), 1],
      ]
    })
    .onClick(() => {
      this.handleCardClick();
    })
  }
}
