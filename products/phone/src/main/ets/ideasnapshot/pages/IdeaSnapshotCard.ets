import { ValuePosition } from '@ohos/mpchart';

const ideaSnapshotStorage: LocalStorage = new LocalStorage();

const IDEA_SNAPSHOT_FULL_PERCENT: string = '100%';
const IDEA_SNAPSHOT_DIMENSION_1X2: string = '1*2';
const IDEA_SNAPSHOT_DIMENSION_2X2: string = '2*2';
const IDEA_SNAPSHOT_STORAGE_DIMENSION_KEY: string = 'formDimension';
const STORAGE_UNLIT_COUNT_KEY: string = 'ideaSnapshotUnlitCount';
const STORAGE_LATEST_TITLE_KEY: string = 'ideaSnapshotLatestTitle';
const IDEA_SNAPSHOT_ROUTER_ABILITY_NAME: string = 'PhoneAbility';
const IDEA_SNAPSHOT_ROUTER_TARGET_IDEAPOOL: string = 'ideapool';

@Entry(ideaSnapshotStorage)
@Component
struct IdeaSnapshotCard {
  @LocalStorageProp(IDEA_SNAPSHOT_STORAGE_DIMENSION_KEY) @Watch('handleDimensionChange')
  private formDimension: string = IDEA_SNAPSHOT_DIMENSION_2X2;
  @LocalStorageProp(STORAGE_UNLIT_COUNT_KEY) @Watch('handleUnlitCountChange')
  private unlitCountRaw: string = '';
  @LocalStorageProp(STORAGE_LATEST_TITLE_KEY) @Watch('handleLatestTitleChange')
  private latestTitleRaw: string = '';

  @State private isCompact: boolean = false;
  @State private unlitCount: number = 0;
  @State private latestIdeaTitle: ResourceStr = $r('app.string.idea_snapshot_widget_placeholder');

  aboutToAppear(): void {
    this.applyDimension(this.formDimension);
    this.applyUnlitCount(this.unlitCountRaw);
    this.applyLatestTitle(this.latestTitleRaw);
  }

  private handleDimensionChange(): void {
    this.applyDimension(this.formDimension);
  }

  private handleUnlitCountChange(): void {
    this.applyUnlitCount(this.unlitCountRaw);
  }

  private handleLatestTitleChange(): void {
    this.applyLatestTitle(this.latestTitleRaw);
  }

  private applyUnlitCount(raw: string): void {
    const parsed = Number(raw);
    const safeCount = Number.isNaN(parsed) || parsed < 0 ? 0 : Math.floor(parsed);
    this.unlitCount = safeCount;
  }

  private applyLatestTitle(raw: string): void {
    const trimmed = raw ? raw.trim() : '';
    if (trimmed.length > 0) {
      this.latestIdeaTitle = trimmed;
      return;
    }
    this.latestIdeaTitle = $r('app.string.idea_snapshot_widget_placeholder');
  }

  private applyDimension(dimension: string): void {
    this.isCompact = dimension === IDEA_SNAPSHOT_DIMENSION_1X2;
  }

  private handleCardClick(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: IDEA_SNAPSHOT_ROUTER_ABILITY_NAME,
      params: {
        target: IDEA_SNAPSHOT_ROUTER_TARGET_IDEAPOOL
      }
    });
  }

  private handleAddClick(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: IDEA_SNAPSHOT_ROUTER_ABILITY_NAME,
      params: {
        target: IDEA_SNAPSHOT_ROUTER_TARGET_IDEAPOOL,
        openAddSheet: true
      }
    });
  }

  build() {
    Column() {
      if (this.isCompact) {
        Row() {
          Row({ space: 5 }) {
            Column({space: 2}) {
              SymbolGlyph($r('sys.symbol.lightbulb'))
                .fontSize($r('app.float.idea_snapshot_widget_icon_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor([$r('app.color.idea_snapshot_accent')]);

              Text($r('app.string.idea_snapshot_widget_label_unlit'))
                .fontSize($r('app.float.idea_snapshot_widget_label_font_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.idea_snapshot_accent'))
                .letterSpacing($r('app.float.idea_snapshot_widget_label_letter_spacing'));
            }
            .alignItems(HorizontalAlign.Start)
            Row() {
              Text(`${this.unlitCount}`)
                .fontSize($r('app.float.idea_snapshot_widget_small_count_font_size'))
                .fontWeight(FontWeight.Bold)
                .textAlign(TextAlign.Center)
                .fontColor($r('app.color.text_primary'))
                .lineHeight($r('app.float.idea_snapshot_widget_small_count_font_size'))
                .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
            }
            .height(IDEA_SNAPSHOT_FULL_PERCENT)
            .alignItems(VerticalAlign.Center)
          }
          .alignItems(VerticalAlign.Center)
          .height(IDEA_SNAPSHOT_FULL_PERCENT)

          Button() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize($r('app.float.idea_snapshot_widget_action_icon_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor([$r('app.color.idea_snapshot_accent')]);
          }
          .width($r('app.float.idea_snapshot_widget_action_size'))
          .height($r('app.float.idea_snapshot_widget_action_size'))
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.idea_snapshot_accent_soft'))
          .stateEffect(true)
          .onClick(() => {
            this.handleAddClick();
          })
        }
        .height(IDEA_SNAPSHOT_FULL_PERCENT)
        .width(IDEA_SNAPSHOT_FULL_PERCENT)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
      } else {
        Row() {
          Column() {
            Row({ space: $r('app.float.idea_snapshot_widget_label_gap') }) {
              SymbolGlyph($r('sys.symbol.lightbulb'))
                .fontSize($r('app.float.idea_snapshot_widget_icon_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor([$r('app.color.idea_snapshot_accent')]);

              Text($r('app.string.idea_snapshot_widget_label_unlit'))
                .fontSize($r('app.float.idea_snapshot_widget_label_font_size'))
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.idea_snapshot_accent'))
                .letterSpacing($r('app.float.idea_snapshot_widget_label_letter_spacing'));
            }
            .margin({ bottom: $r('app.float.idea_snapshot_widget_label_margin_bottom') })

            Text(`${this.unlitCount}`)
              .fontSize($r('app.float.idea_snapshot_widget_count_font_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .lineHeight($r('app.float.idea_snapshot_widget_count_line_height'))
              .fontFamily($r('app.string.today_widget_time_font_family_monospace'))
              .margin({ top: 15 })
          }
          .alignItems(HorizontalAlign.Start)

          Button() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize($r('app.float.idea_snapshot_widget_action_icon_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor([$r('app.color.idea_snapshot_accent')]);
          }
          .width($r('app.float.idea_snapshot_widget_action_size'))
          .height($r('app.float.idea_snapshot_widget_action_size'))
          .type(ButtonType.Circle)
          .backgroundColor($r('app.color.idea_snapshot_accent_soft'))
          .stateEffect(true)
          .margin({
            top: $r('app.float.idea_snapshot_widget_action_offset'),
            right: $r('app.float.idea_snapshot_widget_action_offset')
          })
          .onClick(() => {
            this.handleAddClick();
          })
        }
        .width(IDEA_SNAPSHOT_FULL_PERCENT)
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Top)

        Column() {
          // Column()
          //   .height($r('app.float.idea_snapshot_widget_divider_width'))
          //   .width(IDEA_SNAPSHOT_FULL_PERCENT)
          //   .backgroundColor($r('app.color.neutral_200'))
          //   .opacity($r('app.float.idea_snapshot_widget_divider_opacity'))

          Column({ space: 5}) {
            Text($r('app.string.idea_snapshot_widget_recent_label'))
              .fontSize($r('app.float.idea_snapshot_widget_recent_label_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ bottom: $r('app.float.idea_snapshot_widget_recent_label_margin_bottom') })

            Text(this.latestIdeaTitle)
              .fontSize($r('app.float.idea_snapshot_widget_recent_content_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .lineHeight($r('app.float.idea_snapshot_widget_recent_content_line_height'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ top: $r('app.float.idea_snapshot_widget_bottom_padding_top') })
        }
        .width(IDEA_SNAPSHOT_FULL_PERCENT)
        .margin({ top: $r('app.float.idea_snapshot_widget_bottom_margin_top') })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width(IDEA_SNAPSHOT_FULL_PERCENT)
    .height(IDEA_SNAPSHOT_FULL_PERCENT)
    .padding(this.isCompact
      ? $r('app.float.idea_snapshot_widget_small_padding')
      : $r('app.float.idea_snapshot_widget_padding'))
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.idea_snapshot_card_bg'))
    .linearGradient({
      direction: GradientDirection.RightTop,
      colors: [
        [$r('app.color.accent_lighter'), 0],
        [$r('app.color.primary_lighter'), 1],
      ]
    })
    .borderRadius(this.isCompact
      ? $r('app.float.idea_snapshot_widget_small_card_radius')
      : $r('app.float.idea_snapshot_widget_card_radius'))
    .onClick(() => {
      this.handleCardClick();
    })
  }
}
