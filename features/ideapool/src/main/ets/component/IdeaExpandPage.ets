import { AppShadows, BreakpointConstants, BreakpointType, IdeaActivity, IdeaLightState, TimeRecordUtil, IdeaCollection } from 'base';
import { IdeaExpandAnimationProperties, CollapseAnimationType } from './IdeaExpandAnimation';
import { IdeaLightSummaryCard, SummaryCardVariant } from './IdeaLightSummaryCards';
import { curves } from '@kit.ArkUI';

const IDEA_EXPAND_CONTENT_CURVE = curves.springMotion(0.4, 0.86);
const IDEA_EXPAND_CONTENT_DURATION = 320;

function createIdeaExpandContentTransition(offsetY: number, delay: number, scaleFrom: number = 0.94): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: offsetY }))
      .combine(TransitionEffect.scale({ x: scaleFrom, y: scaleFrom }))
      .animation({ curve: IDEA_EXPAND_CONTENT_CURVE, duration: IDEA_EXPAND_CONTENT_DURATION, delay: delay }),
    undefined
  );
}

@Component
export struct IdeaExpandPage {
  @ObjectLink animationProperties: IdeaExpandAnimationProperties;
  onDelete?: (idea: IdeaActivity) => void;
  onRollbackToUnlit?: (idea: IdeaActivity) => void;
  @StorageProp(BreakpointConstants.CURRENT_BREAKPOINT) currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @StorageLink('ideapoolCollections') ideaCollections: IdeaCollection[] = [];
  @State private panOffsetX: number = 0;
  @State private panOffsetY: number = 0;
  @State private panPositionX: number = 0;
  @State private panPositionY: number = 0;
  private panOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.Up | PanDirection.Down });

  private getExpandedIdea(): IdeaActivity | null {
    return this.animationProperties.currentIdea;
  }

  private getExpandedCollection(): IdeaCollection | null {
    const collectionId: string | null = this.animationProperties.currentCollectionId;
    if (!collectionId) {
      return null;
    }
    return this.ideaCollections.find((collection: IdeaCollection) => collection.id === collectionId) ?? null;
  }

  private getCollectionTitleText(): ResourceStr {
    const collection: IdeaCollection | null = this.getExpandedCollection();
    if (collection && collection.name.trim().length > 0) {
      return collection.name;
    }
    return $r('app.string.ideapool_collection_loose_label');
  }

  private getCollectionIconText(): ResourceStr {
    const collection: IdeaCollection | null = this.getExpandedCollection();
    if (collection) {
      const icon: string | null = collection.icon;
      if (icon && icon.trim().length > 0) {
        return icon;
      }
      return $r('app.string.ideapool_collection_default_icon');
    }
    return $r('app.string.ideapool_collection_loose_icon');
  }

  private getStatusTitle(idea: IdeaActivity): ResourceStr {
    if (idea.ideaLightState === IdeaLightState.LIT) {
      return $r('app.string.ideapool_expand_status_lit_title');
    }
    return $r('app.string.ideapool_expand_status_unlit_title');
  }

  private getTagName(idea: IdeaActivity): string | ResourceStr {
    return idea.tagName ?? $r('app.string.ideapool_expand_tag_fallback');
  }

  private getTagDotColor(idea: IdeaActivity): ResourceColor {
    return idea.tagColorHex ?? $r('app.color.ideapool_expand_tag_dot');
  }

  private getStatusVariant(idea: IdeaActivity): SummaryCardVariant {
    return idea.ideaLightState === IdeaLightState.LIT ? SummaryCardVariant.LIT : SummaryCardVariant.UNLIT;
  }

  private getLightCountVariant(): SummaryCardVariant {
    return SummaryCardVariant.LIT;
  }

  private getExpandCardShadow(): ShadowOptions {
    return this.isDarkTheme ? AppShadows.ELEVATION_2_DARK : AppShadows.ELEVATION_2;
  }

  private getCardPadding(): number {
    return new BreakpointType<number>({
      sm: 14,
      md: 16,
      lg: 20
    }).getValue(this.currentBreakpoint);
  }

  private formatMonthDayTime(timestamp: number): string {
    const date = new Date(timestamp);
    const month = (date.getMonth() + 1).toString();
    const day = date.getDate().toString();
    const time = TimeRecordUtil.formatToHHmm(timestamp);
    return `${month}月${day}日 ${time}`;
  }

  private collapse(): void {
    if (!this.animationProperties.isExpandPageShow) {
      return;
    }
    this.animationProperties.collapseAnimation(() => {}, CollapseAnimationType.NORMAL);
  }

  private handleDeleteIdea(idea: IdeaActivity): void {
    // 只触发回调，让父组件显示确认对话框
    if (this.onDelete) {
      this.onDelete(idea);
    }
  }

  private handleRollbackIdeaToUnlit(idea: IdeaActivity): void {
    // 只触发回调，让父组件显示确认对话框
    if (this.onRollbackToUnlit) {
      this.onRollbackToUnlit(idea);
    }
  }

  private shouldShowRollbackAction(idea: IdeaActivity): boolean {
    return idea.ideaLightState === IdeaLightState.LIT;
  }

  private isExpandedContentReady(): boolean {
    return this.animationProperties.isEnabled
      && this.animationProperties.changedSize
      && !this.animationProperties.isCollapsingToIcon;
  }

  private shouldKeepTitleOnCollapse(): boolean {
    return !this.animationProperties.isEnabled && !this.animationProperties.isCollapsingToIcon;
  }

  @Builder
  private renderHeader(idea: IdeaActivity): void {
    Column({ space: this.isExpandedContentReady() ? $r('app.float.ideapool_expand_header_gap') : 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        // 根据动画类型显示不同的icon
        if (this.animationProperties.collapseAnimationType === CollapseAnimationType.DELETE) {
          // 删除动画：显示删除icon
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(26)
            .fontWeight(600)
            .fontColor([$r('app.color.error')])
            .rotate({ angle: this.animationProperties.isCollapsingToIcon ? 30 : 0 })
        } else if (this.animationProperties.collapseAnimationType === CollapseAnimationType.ROLLBACK) {
          // 回退动画：显示回退icon
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(26)
            .fontWeight(600)
            .fontColor([$r('app.color.accent')])
        } else {
          // 普通状态：显示collection icon
          Text(this.getCollectionIconText())
            .fontSize($r('app.float.ideapool_expand_header_icon_size'))
            .fontWeight(600)
            .fontColor($r('app.color.accent_dark'))
        }
      }
      .margin(this.isExpandedContentReady() ? { bottom: $r('app.float.ideapool_collection_label_margin_bottom')} : undefined)
      .width(this.isExpandedContentReady() ? $r('app.float.ideapool_expand_header_icon_container_size') : 52)
      .height(this.isExpandedContentReady() ? $r('app.float.ideapool_expand_header_icon_container_size') : 52)
      .borderRadius($r('app.float.ideapool_expand_header_icon_container_radius'))
      .backgroundColor(this.animationProperties.collapseAnimationType === CollapseAnimationType.DELETE 
        ? $r('app.color.error_light')
        : (this.animationProperties.collapseAnimationType === CollapseAnimationType.ROLLBACK 
          ? $r('app.color.accent_light')
          : $r('app.color.neutral_100')))
      .shadow(this.isDarkTheme ? AppShadows.SUBTLE_DARK : AppShadows.SUBTLE)

      if (this.isExpandedContentReady()) {
        Column({ space: 6 }) {
          Text(this.getCollectionTitleText())
            .fontSize($r('app.float.ideapool_expand_collection_title_size'))
            .fontWeight(500)
            .fontColor($r('app.color.text_tertiary'))

          Text(idea.name)
            .fontSize($r('app.float.ideapool_expand_title_font_size'))
            .fontWeight(700)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
        }
        .alignItems(HorizontalAlign.Center)
        .transition(createIdeaExpandContentTransition(18, 30, 0.95))

        this.renderTagPill(idea);
      } else if (this.shouldKeepTitleOnCollapse()) {
        Text(idea.name)
          .fontSize(16)
          .fontWeight(700)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .transition(createIdeaExpandContentTransition(-14, 0, 0.96))
  }

  @Builder
  private renderTagPill(idea: IdeaActivity): void {
    Row({ space: $r('app.float.ideapool_expand_tag_dot_margin_right') }) {
      Row()
        .width($r('app.float.ideapool_expand_tag_dot_size'))
        .height($r('app.float.ideapool_expand_tag_dot_size'))
        .borderRadius('50%')
        .backgroundColor(this.getTagDotColor(idea))

      Text(this.getTagName(idea))
        .fontSize($r('app.float.ideapool_expand_tag_text_size'))
        .fontWeight(500)
        .fontColor($r('app.color.text_secondary'))
    }
    .padding({
      left: $r('app.float.ideapool_expand_tag_pill_padding_horizontal'),
      right: $r('app.float.ideapool_expand_tag_pill_padding_horizontal'),
      top: $r('app.float.ideapool_expand_tag_pill_padding_vertical'),
      bottom: $r('app.float.ideapool_expand_tag_pill_padding_vertical')
    })
    .borderRadius($r('app.float.ideapool_expand_tag_pill_radius'))
    .border({
      width: $r('app.float.ideapool_expand_tag_pill_border_width'),
      color: $r('app.color.neutral_300')
    })
    .backgroundColor($r('app.color.bg_card'))
    .transition(createIdeaExpandContentTransition(24, 90, 0.92))
  }

  @Builder
  private renderSummaryCards(idea: IdeaActivity): void {
    Row({ space: $r('app.float.ideapool_expand_stats_gap') }) {
      IdeaLightSummaryCard({
        title: $r('app.string.ideapool_expand_status_subtitle'),
        count: 0,
        valueText: this.getStatusTitle(idea),
        variant: this.getStatusVariant(idea),
        isDarkTheme: this.isDarkTheme,
        titleFontSize: $r('app.float.ideapool_expand_summary_title_size'),
        valueFontSize: $r('app.float.ideapool_expand_summary_value_size'),
        alignCenter: true
      })
        .layoutWeight(1)
        .height($r('app.float.ideapool_expand_summary_card_height'))

      IdeaLightSummaryCard({
        title: $r('app.string.ideapool_summary_lit_times'),
        count: idea.ideaLightCount,
        variant: this.getLightCountVariant(),
        isDarkTheme: this.isDarkTheme,
        titleFontSize: $r('app.float.ideapool_expand_summary_title_size'),
        valueFontSize: $r('app.float.ideapool_expand_summary_value_size'),
        alignCenter: true
      })
        .layoutWeight(1)
        .height($r('app.float.ideapool_expand_summary_card_height'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .transition(createIdeaExpandContentTransition(28, 140, 0.92))
  }

  @Builder
  private renderInfoRow(icon: Resource, iconBackground: ResourceColor, iconColor: ResourceColor,
    label: ResourceStr, value: string): void {
    Row({ space: $r('app.float.ideapool_expand_info_row_gap') }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(icon)
          .fontSize($r('app.float.ideapool_expand_info_icon_font_size'))
          .fontWeight(600)
          .fontColor([iconColor])
      }
      .width($r('app.float.ideapool_expand_info_icon_size'))
      .height($r('app.float.ideapool_expand_info_icon_size'))
      .borderRadius($r('app.float.ideapool_expand_info_icon_radius'))
      .backgroundColor(iconBackground)

      Text(label)
        .fontSize($r('app.float.ideapool_expand_info_label_size'))
        .fontWeight(400)
        .fontColor($r('app.color.text_tertiary'))
        .layoutWeight(1)

      Text(value)
        .fontSize($r('app.float.ideapool_expand_info_value_size'))
        .fontWeight(600)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private renderInfoCard(idea: IdeaActivity): void {
    Column({ space: $r('app.float.ideapool_expand_info_row_gap') }) {
      this.renderInfoRow(
        $r('sys.symbol.leaf'),
        $r('app.color.ideapool_expand_info_birth_bg'),
        $r('app.color.ideapool_expand_info_birth_icon'),
        $r('app.string.ideapool_expand_birth_label'),
        this.formatMonthDayTime(idea.createdAt)
      );
      this.renderInfoRow(
        $r('sys.symbol.arrow_clockwise'),
        $r('app.color.ideapool_expand_info_touch_bg'),
        $r('app.color.ideapool_expand_info_touch_icon'),
        $r('app.string.ideapool_expand_recent_label'),
        this.formatMonthDayTime(idea.updatedAt)
      );
    }
    .padding($r('app.float.ideapool_expand_info_card_padding'))
    .borderRadius($r('app.float.ideapool_expand_info_card_radius'))
    .backgroundColor($r('app.color.bg_card'))
    // .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_RESTING)
    .width('100%')
    .transition(createIdeaExpandContentTransition(34, 210, 0.9))
  }

  @Builder
  private renderActionBar(idea: IdeaActivity): void {
    Row({ space: $r('app.float.ideapool_expand_stats_gap') }) {
      if (this.shouldShowRollbackAction(idea)) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize($r('app.float.ideapool_expand_action_icon_size'))
            .fontWeight(600)
            .fontColor([$r('app.color.text_primary')]);
        }
        .onClick(() => {
          this.handleRollbackIdeaToUnlit(idea);
        })
        .width($r('app.float.ideapool_expand_action_button_size'))
        .height($r('app.float.ideapool_expand_action_button_size'))
        .backgroundColor($r('app.color.neutral_200'))
        .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_INTERACTIVE)
      }

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize($r('app.float.ideapool_expand_action_icon_size'))
          .fontWeight(600)
          .fontColor([$r('app.color.text_primary')]);
      }
      .onClick(() => {
        this.handleDeleteIdea(idea);
      })
      .width($r('app.float.ideapool_expand_action_button_size'))
      .height($r('app.float.ideapool_expand_action_button_size'))
      .backgroundColor($r('app.color.neutral_200'))
      .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_INTERACTIVE)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .transition(createIdeaExpandContentTransition(42, 280, 0.9))
  }

  @Builder
  private renderCollapseHint(): void {
    Column({ space: $r('app.float.ideapool_expand_hint_gap') }) {
      Row()
        .width($r('app.float.ideapool_expand_hint_bar_width'))
        .height($r('app.float.ideapool_expand_hint_bar_height'))
        .borderRadius($r('app.float.ideapool_expand_hint_bar_radius'))
        .backgroundColor($r('app.color.neutral_200'))

      Row({ space: $r('app.float.ideapool_expand_hint_icon_gap') }) {
        SymbolGlyph($r('sys.symbol.chevron_up'))
          .fontSize($r('app.float.ideapool_expand_hint_icon_size'))
          .fontWeight(600)
          .fontColor([$r('app.color.text_tertiary')])

        Text($r('app.string.ideapool_expand_back_hint'))
          .fontSize($r('app.float.ideapool_expand_hint_text_size'))
          .fontWeight(500)
          .fontColor($r('app.color.text_tertiary'))

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize($r('app.float.ideapool_expand_hint_icon_size'))
          .fontWeight(600)
          .fontColor([$r('app.color.text_tertiary')])
      }
    }
    .margin({ top: $r('app.float.ideapool_expand_hint_margin_top') })
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .visibility(this.animationProperties.isEnabled && !this.animationProperties.isCollapsingToIcon ? Visibility.Visible : Visibility.None)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        .height('100%')
        .backgroundBlurStyle(this.animationProperties.backgroundOpacity > 0 ? BlurStyle.BACKGROUND_THIN : BlurStyle.NONE)
        .opacity(this.animationProperties.backgroundOpacity)
        .onClick(() => {
          this.collapse();
        })

      if (this.getExpandedIdea() !== null) {
        Column({ space: this.isExpandedContentReady() ? $r('app.float.ideapool_expand_section_gap') : 0 }) {
          this.renderHeader(this.animationProperties.currentIdea!);
          if (this.isExpandedContentReady()) {
            this.renderSummaryCards(this.animationProperties.currentIdea!);
            this.renderInfoCard(this.animationProperties.currentIdea!);
            this.renderActionBar(this.animationProperties.currentIdea!);
          }
          // this.renderCollapseHint();
        }
        .justifyContent(this.animationProperties.isCollapsingToIcon ? FlexAlign.Center : FlexAlign.SpaceEvenly)
        .alignItems(HorizontalAlign.Center)
        .padding(this.animationProperties.isCollapsingToIcon 
          ? { left: 0, right: 0, top: 0, bottom: 0 }
          : (this.animationProperties.isEnabled ? {
            left: this.getCardPadding(),
            right: this.getCardPadding(),
            top: $r('app.float.ideapool_expand_card_padding_top'),
            bottom: $r('app.float.ideapool_expand_card_padding_bottom')
          } : { left: 15, right: 15, top: 15, bottom: 15 }))
        .borderRadius(this.animationProperties.isCollapsingToIcon 
          ? $r('app.float.ideapool_expand_header_icon_container_radius') 
          : (this.animationProperties.isEnabled ? $r('app.float.ideapool_expand_card_radius') : 15))
        .backgroundColor(this.animationProperties.isEnabled 
          ? $r('app.color.bg_card') 
          : (this.animationProperties.currentIdea?.ideaLightState === IdeaLightState.LIT 
              ? $r('app.color.bg_card') 
              : $r('app.color.bg_main')))
        .shadow(this.animationProperties.isEnabled ? this.getExpandCardShadow() : {
          radius: 1,
          color: $r('app.color.ideapool_expand_card_shadow_min'),
          offsetY: 0
        })
        .width(this.animationProperties.isCollapsingToIcon 
          ? (this.animationProperties.expandedWidth > 0 ? this.animationProperties.expandedWidth : 85)
          : (this.animationProperties.changedSize
            ? (this.animationProperties.expandedWidth > 0 ? this.animationProperties.expandedWidth
              : new BreakpointType<string>({ sm: '92%', md: '70%', lg: '45%' }).getValue(this.currentBreakpoint))
            : (this.animationProperties.initialWidth > 0 ? this.animationProperties.initialWidth : '100%')))
        .height(this.animationProperties.isCollapsingToIcon 
          ? (this.animationProperties.expandedHeight > 0 ? this.animationProperties.expandedHeight : 85)
          : (this.animationProperties.changedSize
            ? (this.animationProperties.expandedHeight > 0 ? this.animationProperties.expandedHeight
              : new BreakpointType<string>({ sm: '76%', md: '76%', lg: '76%' }).getValue(this.currentBreakpoint))
            : (this.animationProperties.initialHeight > 0 ? this.animationProperties.initialHeight
              : $r('app.float.ideapool_expand_card_fallback_height'))))
        .translate({ x: this.animationProperties.translateX, y: this.animationProperties.translateY })
        .position({ x: this.animationProperties.positionX, y: this.animationProperties.positionY })
        .scale({ x: this.animationProperties.cardScale, y: this.animationProperties.cardScale })
        .opacity(this.animationProperties.cardOpacity)
        .clip(false)
        .gesture(
          PanGesture(this.panOption)
            .onActionUpdate((event: GestureEvent) => {
              if (event) {
                this.panOffsetX = this.panPositionX + event.offsetX;
                this.panOffsetY = this.panPositionY + event.offsetY;
              }
            })
            .onActionEnd((event: GestureEvent) => {
              this.panPositionX = this.panOffsetX;
              this.panPositionY = this.panOffsetY;
              if (event.offsetY >= 30 || event.offsetY <= -30) {
                this.collapse();
              }
            })
        )
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 150 }),
          undefined
        ))
        // 点击卡片空白区域时收起（参考其他展开页的交互）
        .onClick(() => {
          this.collapse();
        })
      }
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .clip(false)
  }
}
