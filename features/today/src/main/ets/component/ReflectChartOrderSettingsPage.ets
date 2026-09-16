import {
  ReflectChartIds,
  ReflectChartSettingItem,
  StorageKeys,
  reflectChartPreferenceService,
  VibratorUtil
} from 'base';
import {
  REFLECT_CHART_SETTINGS_DRAG_SHADOW_DARK_COLOR,
  REFLECT_CHART_SETTINGS_DRAG_SHADOW_LIGHT_COLOR,
  REFLECT_CHART_SETTINGS_DRAG_SHADOW_RADIUS,
  REFLECT_CHART_SETTINGS_DRAGGING_SCALE,
  REFLECT_CHART_SETTINGS_REORDER_DURATION,
  reflectChartSettingsSpringCurve
} from './ReflectChartSettingsMotionTokens';

class ReflectChartOrderMeta {
  chartId: string;
  title: string;
  description: string;

  constructor(chartId: string, title: string, description: string) {
    this.chartId = chartId;
    this.title = title;
    this.description = description;
  }
}

const REFLECT_CHART_ORDER_META_LIST: ReflectChartOrderMeta[] = [
  new ReflectChartOrderMeta(ReflectChartIds.TIMELINE, '时间轴', '按时间查看当天活动轨迹'),
  new ReflectChartOrderMeta(ReflectChartIds.DAY_REVIEW, '标签分布', '查看当天完成与记录概览'),
  new ReflectChartOrderMeta(ReflectChartIds.TAG_TREND, '标签趋势', '查看标签变化趋势'),
  new ReflectChartOrderMeta(ReflectChartIds.TAG_TIME_BAR, '标签时长', '对比不同标签时长占比'),
  new ReflectChartOrderMeta(ReflectChartIds.WEEKLY_REVIEW, '周度', '回顾近 7 天表现趋势')
];

const DEFAULT_REFLECT_CHART_ORDER_META: ReflectChartOrderMeta = new ReflectChartOrderMeta(
  'UNKNOWN',
  '未知图表',
  '暂不支持的图表类型'
);

@Component
export struct ReflectChartOrderSettingsContent {
  @StorageLink(StorageKeys.REFLECT_CHART_SETTINGS_REVISION) @Watch('handleChartSettingsRevisionChange')
  chartSettingsRevision: number = 0;
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @State private visibleChartItems: ReflectChartSettingItem[] = [];
  @State private draggingChartId: string = '';
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private skipNextRevisionReload: boolean = false;

  aboutToAppear(): void {
    this.ensureRevisionStorageKey();
    this.reloadVisibleChartItems();
  }

  private ensureRevisionStorageKey(): void {
    if (AppStorage.get(StorageKeys.REFLECT_CHART_SETTINGS_REVISION) === undefined) {
      AppStorage.setOrCreate(StorageKeys.REFLECT_CHART_SETTINGS_REVISION, 0);
    }
  }

  private handleChartSettingsRevisionChange(): void {
    if (this.skipNextRevisionReload) {
      this.skipNextRevisionReload = false;
      return;
    }
    this.reloadVisibleChartItems();
    if (!this.visibleChartItems.some((item: ReflectChartSettingItem) => item.chartId === this.draggingChartId)) {
      this.draggingChartId = '';
    }
  }

  private reloadVisibleChartItems(): void {
    this.visibleChartItems = reflectChartPreferenceService.loadSettings().items
      .filter((item: ReflectChartSettingItem) => item.visible)
      .sort((left: ReflectChartSettingItem, right: ReflectChartSettingItem) => left.order - right.order)
      .map((item: ReflectChartSettingItem) => new ReflectChartSettingItem(item.chartId, item.visible, item.order));
  }

  private canDragSort(): boolean {
    return this.visibleChartItems.length > 1;
  }

  private resolveChartMeta(chartId: string): ReflectChartOrderMeta {
    const matched: ReflectChartOrderMeta | undefined = REFLECT_CHART_ORDER_META_LIST.find(
      (meta: ReflectChartOrderMeta) => meta.chartId === chartId
    );
    return matched ?? DEFAULT_REFLECT_CHART_ORDER_META;
  }

  private resolveSortTipsText(): string {
    if (this.canDragSort()) {
      return '长按列表项右侧把手可拖拽排序';
    }
    return '当前已显示图表不足 2 个，暂不支持排序';
  }

  private isLastItem(index: number): boolean {
    return index === this.visibleChartItems.length - 1;
  }

  private resolveItemScale(chartId: string): number {
    return this.draggingChartId === chartId ? REFLECT_CHART_SETTINGS_DRAGGING_SCALE : 1;
  }

  private resolveItemShadow(chartId: string): ShadowOptions {
    if (this.draggingChartId !== chartId) {
      return {
        radius: 0,
        color: '#00000000',
        offsetX: 0,
        offsetY: 0
      };
    }
    return {
      radius: REFLECT_CHART_SETTINGS_DRAG_SHADOW_RADIUS,
      color: this.isDarkTheme ? REFLECT_CHART_SETTINGS_DRAG_SHADOW_DARK_COLOR : REFLECT_CHART_SETTINGS_DRAG_SHADOW_LIGHT_COLOR,
      offsetX: 0,
      offsetY: 0
    };
  }

  private normalizeTargetIndex(index: number): number {
    if (index < 0) {
      return 0;
    }
    if (index >= this.visibleChartItems.length) {
      return this.visibleChartItems.length - 1;
    }
    return index;
  }

  private moveItemLocally(from: number, to: number): boolean {
    if (!this.canDragSort()) {
      return false;
    }
    if (from < 0 || to < 0 || from >= this.visibleChartItems.length || to >= this.visibleChartItems.length) {
      return false;
    }
    if (from === to) {
      return false;
    }
    const movedItems: ReflectChartSettingItem[] = this.visibleChartItems.splice(from, 1);
    if (movedItems.length === 0) {
      return false;
    }
    this.visibleChartItems.splice(to, 0, movedItems[0]);
    return true;
  }

  private persistVisibleOrder(): void {
    const orderedVisibleChartIds: string[] = this.visibleChartItems.map((item: ReflectChartSettingItem) => item.chartId);
    this.skipNextRevisionReload = true;
    reflectChartPreferenceService.reorderVisibleCharts(orderedVisibleChartIds);
  }

  private handleItemMove(from: number, to: number): boolean {
    if (!this.canDragSort()) {
      return false;
    }
    const targetIndex: number = this.normalizeTargetIndex(to);
    const moved: boolean = this.moveItemLocally(from, targetIndex);
    if (!moved) {
      return false;
    }
    this.persistVisibleOrder();
    return true;
  }

  private handleItemDragStart(itemIndex: number): void {
    if (itemIndex < 0 || itemIndex >= this.visibleChartItems.length) {
      this.draggingChartId = '';
      return;
    }
    this.draggingChartId = this.visibleChartItems[itemIndex].chartId;
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
  }

  private handleItemDrop(isSuccess: boolean): void {
    this.draggingChartId = '';
    if (isSuccess) {
      void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    }
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

  build() {
    Column() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.list_bullet'))
          .fontSize(14)
          .fontColor([$r('app.color.text_secondary')]);
        Text(this.resolveSortTipsText())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'));
      }
      .width('100%')
      .padding({ top: 0, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      List({ space: 0 }) {
        ForEach(this.visibleChartItems, (item: ReflectChartSettingItem, index: number) => {
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

                Row({ space: 6 }) {
                  Text(index + 1 + '')
                    .fontSize(14)
                    .fontWeight(600)
                    .fontColor($r('app.color.text_secondary'));
                  SymbolGlyph($r('sys.symbol.line_3_horizontal'))
                    .fontSize(18)
                    .fontColor([this.canDragSort() ? $r('app.color.text_secondary') : $r('app.color.neutral_300')]);
                }
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
          .editable(this.canDragSort() ? EditMode.Movable : EditMode.None)
          .backgroundColor($r('app.color.bg_card'))
          .scale({
            x: this.resolveItemScale(item.chartId),
            y: this.resolveItemScale(item.chartId)
          })
          .shadow(this.resolveItemShadow(item.chartId))
          .animation({ duration: REFLECT_CHART_SETTINGS_REORDER_DURATION, curve: reflectChartSettingsSpringCurve() });
        }, (item: ReflectChartSettingItem) => item.chartId)
          .onMove((from: number, to: number) => {
            this.handleItemMove(from, to);
          });
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .borderRadius(16)
      .editMode(this.canDragSort())
      .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
        this.handleItemDragStart(itemIndex);
      })
      .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
        this.handleItemDrop(isSuccess);
      });
    }
    .width('100%')
    .height('100%')
  }
}
