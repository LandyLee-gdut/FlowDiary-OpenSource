import dayjs from 'dayjs';
import { ItemRestriction, LengthMetrics, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem } from '@kit.ArkUI';
import {
  ReflectChartIds,
  ReflectChartSettingItem,
  StorageKeys,
  reflectChartPreferenceService,
  VibratorUtil
} from 'base';
import {
  REFLECT_CHART_SETTINGS_HIDDEN_OPACITY,
  REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION,
  REFLECT_CHART_SETTINGS_TOGGLE_DURATION,
  reflectChartSettingsSpringCurve
} from './ReflectChartSettingsMotionTokens';
import { DayReviewChart } from '../preview/reflect/component/DayReviewChart';
import { DayTimeline } from '../preview/reflect/component/DayTimeline';
import { TagTimeBarChart } from '../preview/reflect/component/TagTimeBarChart';
import { TagTrendChart } from '../preview/reflect/component/TagTrendChart';
import { WeeklyReviewChart } from '../preview/reflect/component/WeeklyReviewChart';
import { ReflectModel as ReflectPreviewModel } from '../preview/reflect/model/ReflectModel';
import { ReflectChartOrderSettingsContent } from './ReflectChartOrderSettingsPage';
import { SettingsPageHeader } from './settings/SettingsPageHeader';

class ReflectChartMeta {
  chartId: string;
  title: string;
  description: string;

  constructor(chartId: string, title: string, description: string) {
    this.chartId = chartId;
    this.title = title;
    this.description = description;
  }
}

const REFLECT_CHART_META_LIST: ReflectChartMeta[] = [
  new ReflectChartMeta(ReflectChartIds.TIMELINE, '时间轴', '按时间查看当天活动轨迹'),
  new ReflectChartMeta(ReflectChartIds.DAY_REVIEW, '标签分布', '查看当天完成与记录概览'),
  new ReflectChartMeta(ReflectChartIds.TAG_TREND, '标签趋势', '查看标签变化趋势'),
  new ReflectChartMeta(ReflectChartIds.TAG_TIME_BAR, '标签时长', '对比不同标签时长占比'),
  new ReflectChartMeta(ReflectChartIds.WEEKLY_REVIEW, '周度', '回顾近 7 天表现趋势')
];

const DEFAULT_REFLECT_CHART_META: ReflectChartMeta = new ReflectChartMeta('UNKNOWN', '未知图表', '暂不支持的图表类型');

@Component
struct ReflectChartPreviewCard {
  @ObjectLink item: ReflectChartSettingItem;
  @Prop isDarkTheme: boolean = false;

  @Builder
  private buildPreviewChartContent(): void {
    if (this.item.chartId === ReflectChartIds.TIMELINE) {
      DayTimeline()
        .height(125);
    } else if (this.item.chartId === ReflectChartIds.DAY_REVIEW) {
      DayReviewChart()
        .height(187.5);
    } else if (this.item.chartId === ReflectChartIds.TAG_TREND) {
      TagTrendChart();
    } else if (this.item.chartId === ReflectChartIds.TAG_TIME_BAR) {
      TagTimeBarChart();
    } else if (this.item.chartId === ReflectChartIds.WEEKLY_REVIEW) {
      WeeklyReviewChart()
        .height(250);
    } else {
      Column() {
        Text('暂不支持该图表预览')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'));
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.buildPreviewChartContent();
      }
      .justifyContent(FlexAlign.Center)
      .height(300)
      .width('100%')
      .opacity(this.item.visible ? 1 : REFLECT_CHART_SETTINGS_HIDDEN_OPACITY)
      .animation({ curve: reflectChartSettingsSpringCurve(), duration: REFLECT_CHART_SETTINGS_TOGGLE_DURATION })

      if (!this.item.visible) {
        SymbolGlyph($r('sys.symbol.eye_slash'))
          .fontSize(26)
          .fontColor([this.isDarkTheme ? $r('app.color.neutral_800') : $r('app.color.text_secondary')])
          .padding(10)
          .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)
          .borderRadius('50%')
          .transition(TransitionEffect.opacity(0)
            .combine(TransitionEffect.scale({ x: 0.88, y: 0.88 }))
            .animation({
              curve: reflectChartSettingsSpringCurve(),
              duration: REFLECT_CHART_SETTINGS_TOGGLE_DURATION
            }));
      }
    }
    .width('100%')
    .height(270)
    .clip(false)
    .animation({ duration: REFLECT_CHART_SETTINGS_TOGGLE_DURATION, curve: reflectChartSettingsSpringCurve() });
  }
}

@Component
export struct ReflectChartVisibilitySettingsPage {
  onBack?: () => void;
  onResetToDefault?: () => void;
  @StorageLink(StorageKeys.REFLECT_CHART_SETTINGS_REVISION) @Watch('handleChartSettingsRevisionChange')
  chartSettingsRevision: number = 0;
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @Provide('reflectModel') private previewReflectModel: ReflectPreviewModel = new ReflectPreviewModel();
  @State private chartItems: ReflectChartSettingItem[] = [];
  @State private flowCardGalleryVisible: boolean = true;
  @State private visibleChartCount: number = 0;
  @State private previewIndex: number = 0;
  @State private selectedTabIndexes: number[] = [0];
  @State private tabOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [
      { text: $r('app.string.settings_reflect_tab_visibility') },
      { text: $r('app.string.settings_reflect_tab_order') }
    ] as ItemRestriction<SegmentButtonTextItem>,
    backgroundColor: $r('app.color.segment_background'),
    selectedFontSize: $r('app.float.settings_segment_font_size'),
    selectedBackgroundColor: $r('app.color.segment_selected_background'),
    selectedFontColor: $r('app.color.primary'),
    selectedFontWeight: FontWeight.Bold,
    fontSize: $r('app.float.settings_segment_font_size'),
    fontWeight: FontWeight.Medium,
    fontColor: $r('app.color.text_secondary'),
    localizedButtonPadding: {
      end: LengthMetrics.resource($r('app.float.settings_segment_button_padding')),
      start: LengthMetrics.resource($r('app.float.settings_segment_button_padding'))
    }
  });
  private pageInfos: NavPathStack = new NavPathStack();
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private skipNextRevisionReload: boolean = false;

  aboutToAppear(): void {
    if (AppStorage.get(StorageKeys.REFLECT_CHART_SETTINGS_REVISION) === undefined) {
      AppStorage.setOrCreate(StorageKeys.REFLECT_CHART_SETTINGS_REVISION, 0);
    }
    this.ensurePreviewStorageKeys();
    this.reloadChartItems();
    void this.previewReflectModel.refreshAll();
  }

  private handleChartSettingsRevisionChange(): void {
    if (this.skipNextRevisionReload) {
      this.skipNextRevisionReload = false;
      return;
    }
    this.reloadChartItems();
  }

  private reloadChartItems(): void {
    this.chartItems = reflectChartPreferenceService.loadSettings().items
      .map((item: ReflectChartSettingItem) => new ReflectChartSettingItem(item.chartId, item.visible, item.order))
      .sort((left: ReflectChartSettingItem, right: ReflectChartSettingItem) => left.order - right.order);
    this.flowCardGalleryVisible = reflectChartPreferenceService.isFlowCardGalleryVisible();
    this.syncVisibleChartCount();
    if (this.previewIndex >= this.chartItems.length) {
      this.previewIndex = this.chartItems.length > 0 ? this.chartItems.length - 1 : 0;
    }
  }

  private syncVisibleChartCount(): void {
    this.visibleChartCount = this.chartItems.filter((item: ReflectChartSettingItem) => item.visible).length;
  }

  private resolveChartMeta(chartId: string): ReflectChartMeta {
    const matched: ReflectChartMeta | undefined = REFLECT_CHART_META_LIST.find(
      (meta: ReflectChartMeta) => meta.chartId === chartId
    );
    return matched ?? DEFAULT_REFLECT_CHART_META;
  }

  private resolveVisibleChartCount(): number {
    return this.visibleChartCount;
  }

  private resolveChartCountText(): string {
    return `已显示 ${this.resolveVisibleChartCount()}/${this.chartItems.length}`;
  }

  private isLastItem(index: number): boolean {
    return index === this.chartItems.length - 1;
  }

  @Builder
  private buildChartSymbol(chartId: string): void {
    if (chartId === ReflectChartIds.TIMELINE) {
      SymbolGlyph($r('sys.symbol.clock'))
        .fontSize(18)
        .fontColor([$r('app.color.text_primary')]);
    } else if (chartId === ReflectChartIds.DAY_REVIEW) {
      SymbolGlyph($r('sys.symbol.collection_panel'))
        .fontSize(18)
        .fontColor([$r('app.color.text_primary')]);
    } else if (chartId === ReflectChartIds.TAG_TREND) {
      SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
        .fontSize(18)
        .fontColor([$r('app.color.text_primary')]);
    } else if (chartId === ReflectChartIds.TAG_TIME_BAR) {
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(18)
        .fontColor([$r('app.color.text_primary')]);
    } else if (chartId === ReflectChartIds.WEEKLY_REVIEW) {
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(18)
        .fontColor([$r('app.color.text_primary')]);
    } else {
      SymbolGlyph($r('sys.symbol.rectangle_split_2x1'))
        .fontSize(18)
        .fontColor([$r('app.color.text_primary')]);
    }
  }

  private handleChartVisibleChange(chartId: string, isVisible: boolean): void {
    const matched: ReflectChartSettingItem | undefined = this.chartItems.find(
      (item: ReflectChartSettingItem) => item.chartId === chartId
    );
    if (!matched || matched.visible === isVisible) {
      return;
    }
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    this.updateChartVisibleLocally(chartId, isVisible);
    this.skipNextRevisionReload = true;
    reflectChartPreferenceService.toggleVisible(chartId, isVisible);
  }

  private updateChartVisibleLocally(chartId: string, isVisible: boolean): void {
    const target: ReflectChartSettingItem | undefined = this.chartItems.find(
      (item: ReflectChartSettingItem) => item.chartId === chartId
    );
    if (!target) {
      return;
    }
    target.visible = isVisible;
    this.syncVisibleChartCount();
  }

  private handleFlowCardGalleryVisibleChange(isVisible: boolean): void {
    if (this.flowCardGalleryVisible === isVisible) {
      return;
    }
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    this.flowCardGalleryVisible = isVisible;
    this.skipNextRevisionReload = true;
    reflectChartPreferenceService.setFlowCardGalleryVisible(isVisible);
  }

  private ensurePreviewStorageKeys(): void {
    if (AppStorage.get(StorageKeys.SELECTED_DATE) === undefined) {
      AppStorage.setOrCreate(StorageKeys.SELECTED_DATE, dayjs().date());
    }
    if (AppStorage.get(StorageKeys.SELECTED_MONTH) === undefined) {
      AppStorage.setOrCreate(StorageKeys.SELECTED_MONTH, dayjs().month() + 1);
    }
    if (AppStorage.get(StorageKeys.SELECTED_YEAR) === undefined) {
      AppStorage.setOrCreate(StorageKeys.SELECTED_YEAR, dayjs().year());
    }
    if (AppStorage.get(StorageKeys.REFLECT_REFRESH_REVISION) === undefined) {
      AppStorage.setOrCreate(StorageKeys.REFLECT_REFRESH_REVISION, 0);
    }
    if (AppStorage.get(StorageKeys.REFLECT_CALENDAR_REVISION) === undefined) {
      AppStorage.setOrCreate(StorageKeys.REFLECT_CALENDAR_REVISION, 0);
    }
  }

  private handleCloseClick(): void {
    if (this.onBack) {
      this.onBack();
      return;
    }
    this.pageInfos.pop(1);
  }

  private isOrderTabSelected(): boolean {
    return this.selectedTabIndexes.length > 0 && this.selectedTabIndexes[0] === 1;
  }

  private confirmResetToDefault(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.settings_reflect_reset_confirm_title'),
      message: $r('app.string.settings_reflect_reset_confirm_message'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      gridCount: 4,
      primaryButton: {
        value: $r('app.string.settings_reflect_reset_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        enabled: true,
        defaultFocus: true,
        style: DialogButtonStyle.HIGHLIGHT,
        value: $r('app.string.settings_reflect_reset_confirm'),
        action: () => {
          this.onResetToDefault?.();
          void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
        }
      }
    });
  }

  build() {
    NavDestination() {
      Column() {
        SettingsPageHeader({
          title: $r('app.string.settings_entry_reflect_chart'),
          onAction: () => {
            this.handleCloseClick();
          }
        })
        .padding({
          left: $r('app.float.settings_page_padding_horizontal'),
          right: $r('app.float.settings_page_padding_horizontal')
        })

        Row() {
          SegmentButton({ options: this.tabOptions, selectedIndexes: this.selectedTabIndexes })
            .width($r('app.float.settings_reflect_segment_width'))
            .height($r('app.float.settings_segment_height'))
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
            })
            .borderRadius($r('app.float.settings_segment_radius'))

          Button($r('app.string.settings_reflect_reset'))
            .fontSize($r('app.float.settings_reflect_reset_font_size'))
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.transparent'))
            .onClick(() => {
              this.confirmResetToDefault();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .padding({
          left: $r('app.float.settings_page_padding_horizontal'),
          right: $r('app.float.settings_page_padding_horizontal'),
          bottom: $r('app.float.settings_reflect_tab_margin_bottom')
        })

        if (!this.isOrderTabSelected()) {
          Scroll() {
          Column() {
            Column() {
              Row() {
                Text('显示预览')
                  .fontSize(14)
                  .fontWeight(600)
                  .fontColor($r('app.color.text_primary'));

                Text(this.resolveChartCountText())
                  .fontSize(14)
                  .fontWeight(600)
                  .fontColor($r('app.color.text_secondary'))
              }
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Center)
              .width('100%')
              .padding({ left: 0, right: 0, top: 0, bottom: 8 });

              Swiper() {
                ForEach(this.chartItems, (item: ReflectChartSettingItem) => {
                    ReflectChartPreviewCard({
                      item: item,
                      isDarkTheme: this.isDarkTheme
                    })
                }, (item: ReflectChartSettingItem) => item.chartId)
              }
              .displayCount(1)
              .index(this.previewIndex)
              .onChange((index: number) => {
                this.previewIndex = index;
              })
              .clip(false)
              .autoPlay(false)
              .itemSpace(16)
              .indicator(false)
              .width('100%')
            }
            .width('100%')
            .padding({ left: 0, right: 0, top: 4, bottom: 0 })
            .margin({ bottom: 14 })

            List({ space: 0 }) {
              ListItem() {
                Column() {
                  Row() {
                    Row({ space: 10 }) {
                      SymbolGlyph($r('sys.symbol.picture_2'))
                        .fontSize(18)
                        .fontColor([$r('app.color.text_primary')]);
                      Column({ space: 4 }) {
                        Text('回顾画廊')
                          .fontSize(16)
                          .fontWeight(600)
                          .fontColor($r('app.color.text_primary'));

                        Text('固定置顶，仅支持显示开关')
                          .fontSize(13)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis });
                      }
                      .alignItems(HorizontalAlign.Start)
                      .width('68%');
                    }

                    Toggle({ type: ToggleType.Switch, isOn: this.flowCardGalleryVisible })
                      .selectedColor($r('app.color.primary'))
                      .onChange((isOn: boolean) => {
                        this.handleFlowCardGalleryVisibleChange(isOn);
                      });
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.SpaceBetween)
                  .alignItems(VerticalAlign.Center)
                  .padding({ left: 16, right: 16, top: 14, bottom: 14 });

                  Divider()
                    .strokeWidth(1)
                    .color($r('app.color.neutral_100'))
                    .margin({ left: 44, right: 16 });
                }
              }
              .backgroundColor($r('app.color.bg_card'));

              ForEach(this.chartItems, (item: ReflectChartSettingItem, index: number) => {
                ListItem() {
                  Column() {
                    Row() {
                      Row({ space: 10 }) {
                        this.buildChartSymbol(item.chartId);
                        Column({ space: 4 }) {
                          Text(this.resolveChartMeta(item.chartId).title)
                            .fontSize(16)
                            .fontWeight(600)
                            .fontColor($r('app.color.text_primary'));

                          Text(this.resolveChartMeta(item.chartId).description)
                            .fontSize(13)
                            .fontColor($r('app.color.text_secondary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis });
                        }
                        .alignItems(HorizontalAlign.Start)
                        .width('68%');
                      }

                      Toggle({ type: ToggleType.Switch, isOn: item.visible })
                        .selectedColor($r('app.color.primary'))
                        .onChange((isOn: boolean) => {
                          this.handleChartVisibleChange(item.chartId, isOn);
                        });
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.SpaceBetween)
                    .alignItems(VerticalAlign.Center)
                    .padding({ left: 16, right: 16, top: 14, bottom: 14 });

                    if (!this.isLastItem(index)) {
                      Divider()
                        .strokeWidth(1)
                        .color($r('app.color.neutral_100'))
                        .margin({ left: 44, right: 16 });
                    }
                  }
                }
                .backgroundColor($r('app.color.bg_card'));
              }, (item: ReflectChartSettingItem) => item.chartId)
            }
            .width('100%')
            .scrollBar(BarState.Off)
            .borderRadius(16)
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 20 })
          .backgroundColor($r('app.color.bg_main'))
        }
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .align(Alignment.Top)
          .width('100%')
          .layoutWeight(1)
        } else {
          ReflectChartOrderSettingsContent()
            .padding({
              left: $r('app.float.settings_page_padding_horizontal'),
              right: $r('app.float.settings_page_padding_horizontal'),
              bottom: $r('app.float.settings_page_padding_bottom')
            })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_main'))
    }
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
    })
    .onBackPressed((): boolean => {
      this.handleCloseClick();
      return true;
    })
    .hideTitleBar(true)
    .systemTransition(REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
  }
}
