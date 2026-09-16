import { AppShadows, ColorModeUtil, COLOR_MODE_STORAGE_KEY, buildPointLightEffect } from 'base'
import type { TagTimeDistributionItem, TagTimeDistributionPanelData } from '../model/TagTimeDistributionModel'
import { ReflectModel } from '../model/ReflectModel'
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hdsEffect } from '@kit.UIDesignKit'

const UNTAGGED_KEY: string = '__untagged__'

function resolveTagKey(tagId: string | null): string {
  return tagId ? tagId : UNTAGGED_KEY
}

function resolveTagItemKey(item: TagTimeDistributionItem): string {
  return resolveTagKey(item.tagId)
}

@Component
struct TagDistributionSummaryRow {
  @Prop item: TagTimeDistributionItem
  @Prop showMeta: boolean = true
  @Prop maxMinutes: number = 1

  private resolveRatioWidth(totalMinutes: number): string {
    const safeMax: number = this.maxMinutes > 0 ? this.maxMinutes : 1
    const ratio: number = Math.max(0, Math.min(1, totalMinutes / safeMax))
    return `${ratio * 100}%`
  }

  build(): void {
    Row({ space: this.showMeta ? 6 : 4 }) {
      Text(this.item.tagName)
        .fontSize($r('app.float.tag_distribution_widget_item_label_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width($r('app.float.day_review_tag_label_width'))

      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width('100%')
          .height($r('app.float.tag_distribution_widget_bar_height'))
          .borderRadius($r('app.float.tag_distribution_widget_bar_radius'))
          .backgroundColor($r('app.color.neutral_200'))

        Row()
          .width(this.resolveRatioWidth(this.item.totalMinutes))
          .height($r('app.float.tag_distribution_widget_bar_height'))
          .borderRadius($r('app.float.tag_distribution_widget_bar_radius'))
          .backgroundColor(this.item.tagColor)
          .opacity($r('app.float.tag_distribution_widget_bar_fill_opacity'))
      }
      .layoutWeight(1)
      .height($r('app.float.tag_distribution_widget_bar_height'))

      if (this.showMeta) {
        Text(this.item.durationLabel)
          .fontSize($r('app.float.day_review_tag_value_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.End)
          .letterSpacing($r('app.float.tag_distribution_widget_value_letter_spacing'))
          .width($r('app.float.day_review_tag_value_width'))
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct DayReviewChart {
  @Consume('reflectModel') private reflectModel: ReflectModel = new ReflectModel()
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State isDarkTheme: boolean = false;

  aboutToAppear(): void {
    this.syncColorModeState();
    void this.reflectModel.refreshDayBundle()
  }

  onColorModeChange(): void {
    this.syncColorModeState();
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private resolveTotalMinutes(): number {
    if (!this.reflectModel.dayDistributionData) {
      return 0
    }
    return this.reflectModel.dayDistributionData.totalMinutes
  }

  private resolveTotalHours(): number {
    const totalMinutes: number = this.resolveTotalMinutes()
    return Math.floor(totalMinutes / 60)
  }

  private resolveTotalMinuteRemainder(): number {
    const totalMinutes: number = this.resolveTotalMinutes()
    return totalMinutes % 60
  }

  private resolveMaxItemMinutes(panelData: TagTimeDistributionPanelData | null): number {
    if (!panelData || !panelData.items || panelData.items.length === 0) {
      return 1
    }
    let maxMinutes = 0
    panelData.items.forEach((item: TagTimeDistributionItem) => {
      if (item.totalMinutes > maxMinutes) {
        maxMinutes = item.totalMinutes
      }
    })
    return maxMinutes > 0 ? maxMinutes : 1
  }

  private resolvePanelItems(): TagTimeDistributionItem[] {
    const panelData = this.reflectModel.dayDistributionData
    return panelData?.items ?? []
  }

  build(): void {
    Column() {
      Column() {
        Row() {
          Text($r('app.string.tag_distribution_widget_label'))
            .fontColor($r('app.color.primary'))
            .fontSize(16)
            .fontWeight(600)

          Text($r('app.string.today_record_widget_total_label'))
            .fontSize($r('app.float.day_review_total_label_font_size'))
            .fontWeight(500)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.End)
            .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
        }
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
        .margin({ bottom: $r('app.float.tag_distribution_widget_title_margin_bottom_compact') })

        Stack({ alignContent: Alignment.Center }) {
          if (!this.reflectModel.dayDistributionError) {
            GridRow({
              columns: 4,
              gutter: 0,
              direction: GridRowDirection.Row
            }) {
              GridCol({ span: 3 }) {
                Column() {
                  List({ space: 14 }) {
                    if (this.resolvePanelItems().length > 0) {
                      ForEach(this.resolvePanelItems(), (item: TagTimeDistributionItem) => {
                        ListItem() {
                          TagDistributionSummaryRow({
                            item: item,
                            showMeta: true,
                            maxMinutes: this.resolveMaxItemMinutes(this.reflectModel.dayDistributionData)
                          })
                        }
                      }, resolveTagItemKey)
                    } else {
                      ListItem() {
                        Text('暂无数据')
                          .fontSize(14)
                          .fontColor($r('app.color.text_secondary'))
                          .textAlign(TextAlign.Center)
                          .width('100%')
                          .height('100%')
                      }
                    }
                  }
                  .layoutWeight(1)
                  .width('100%')
                  .scrollBar(BarState.Off)
                  .nestedScroll({
                    scrollForward: NestedScrollMode.SELF_FIRST,
                    scrollBackward: NestedScrollMode.SELF_FIRST
                  })
                  .friction(0.9)
                }
                .width('100%')
                .height('100%')
                .padding({ right: $r('app.float.today_record_widget_list_divider_spacing') })
              }

              GridCol({ span: 1 }) {
                Row() {
                  Column()
                    .width($r('app.float.today_record_widget_divider_width'))
                    .height('100%')
                    .backgroundColor($r('app.color.today_record_widget_divider'))

                  Column() {
                    Column() {
                      if (this.resolveTotalHours() > 0) {
                        Row() {
                          Text() {
                            Span(`${this.resolveTotalHours()}`)
                              .fontSize($r('app.float.day_review_total_hours_font_size'))
                              .fontWeight(FontWeight.Bold)
                              .fontColor($r('app.color.primary'))
                              .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                            Span(' h')
                              .fontSize($r('app.float.font_size'))
                              .fontWeight(FontWeight.Bold)
                              .fontColor($r('app.color.primary_light'))
                              .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                          }
                          .width('100%')
                          .textAlign(TextAlign.End)
                        }
                        .width('100%')
                        .alignItems(VerticalAlign.Bottom)
                        .justifyContent(FlexAlign.End)

                        Row() {
                          Text() {
                            Span(`${this.resolveTotalMinuteRemainder()}`)
                              .fontSize($r('app.float.day_review_total_value_font_size'))
                              .fontWeight(FontWeight.Bold)
                              .fontColor($r('app.color.primary'))
                              .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                            Span(' m')
                              .fontSize($r('app.float.font_size'))
                              .fontWeight(FontWeight.Bold)
                              .fontColor($r('app.color.primary_light'))
                              .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                          }
                          .width('100%')
                          .textAlign(TextAlign.End)
                        }
                        .width('100%')
                        .alignItems(VerticalAlign.Bottom)
                        .justifyContent(FlexAlign.End)
                      } else {
                        Text() {
                          Span(`${this.resolveTotalMinuteRemainder()}`)
                            .fontSize($r('app.float.day_review_total_hours_font_size'))
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.primary'))
                            .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                          Span('m')
                            .fontSize($r('app.float.font_size'))
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.primary_light'))
                            .letterSpacing($r('app.float.today_record_widget_total_letter_spacing'))
                        }
                        .textAlign(TextAlign.End)
                        .width('100%')
                      }
                    }
                    .layoutWeight(1)
                    .width('100%')
                    .alignItems(HorizontalAlign.End)
                    .justifyContent(FlexAlign.Start)
                    .padding({ top: $r('app.float.day_review_total_time_margin_top') })
                  }
                  .layoutWeight(1)
                  .height('100%')
                  .padding({ left: $r('app.float.today_record_widget_summary_padding_left') })
                  .alignItems(HorizontalAlign.End)
                  .justifyContent(FlexAlign.SpaceBetween)
                }
              }
            }
            .width('100%')
            .height('100%')
          }

          if (this.reflectModel.dayDistributionError) {
            Column() {
              Text('暂时无法加载标签时间分布数据')
                .fontSize(14)
                .fontColor($r('app.color.accent_dark'))
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .height('100%')
          }

        }
        .layoutWeight(1)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .padding({ top: 16, bottom: 16, left: 20, right: 20 })
      .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE)
      .backgroundColor($r('app.color.bg_card'))
      .height($r('app.float.day_review_chart_height'))
      .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseInOut }))
      .borderRadius(15)
      .visualEffect(buildPointLightEffect({
        preset: 'cardTouch',
        color: $r('app.color.immersive_glow_primary'),
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        isActive: false,
        isDarkTheme: this.isDarkTheme
      }))
    }
  }

}
