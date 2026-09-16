import { AppShadows, ColorModeUtil, COLOR_MODE_STORAGE_KEY } from 'base'
import type { TagTimeDistributionItem, TagTimeDistributionPanelData } from '../model/TagTimeDistributionModel'
import { ConfigurationConstant } from '@kit.AbilityKit'

function resolveTagKey(tagId: string | null): string {
  return tagId ? tagId : '__untagged__'
}

function toPercentWidth(ratio: number): string {
  const clamped: number = Math.max(0, Math.min(1, ratio))
  return `${clamped * 100}%`
}

@Component
export struct TagTimeDistributionSummaryChart {
  @Prop panelData: TagTimeDistributionPanelData | undefined = undefined
  @Prop highlightTagId: string | null | undefined = undefined
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  @State private isDarkTheme: boolean = false

  aboutToAppear(): void {
    this.syncColorModeState()
  }

  onColorModeChange(): void {
    this.syncColorModeState()
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode)
  }

  build(): void {
    Column() {
      Row() {
        Text('标签时间分布')
          .fontSize(12)
          .fontWeight(600)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      if (!this.panelData || !this.panelData.items || this.panelData.items.length === 0) {
        Column() {
          Text('暂无数据')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .height(120)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.panelData.items, (item: TagTimeDistributionItem) => {
            ListItem() {
              Column() {
                Row() {
                  Row() {
                    Row()
                      .width(8)
                      .height(8)
                      .borderRadius('50%')
                      .margin({ right: 6 })
                      .backgroundColor(item.tagColor)

                    Text(item.tagName)
                      .fontSize(12)
                      .fontWeight(this.highlightTagId && item.tagId === this.highlightTagId ? 700 : 600)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .alignItems(VerticalAlign.Center)

                  Text(item.durationLabel)
                    .fontSize(12)
                    .fontWeight(600)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)

                Stack() {
                  Row()
                    .width('100%')
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor($r('app.color.text_disabled'))
                    .opacity(0.25)

                  Row()
                    .width(toPercentWidth(item.ratio))
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor(item.tagColor)
                }
                .width('100%')
                .margin({ top: 6 })
              }
              .padding({ top: 8, bottom: 8 })
            }
          }, (item: TagTimeDistributionItem) => resolveTagKey(item.tagId))
        }
        .width('100%')
        .height(136)
        .scrollBar(BarState.Off)
      }
    }
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.bg_main'))
    .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)
    .borderRadius(16)
  }
}

