const SHORTCUT_FULL_PERCENT: string = '100%';
const FORM_DIMENSION_1X2: string = '1*2';
const STORAGE_DIMENSION_KEY: string = 'formDimension';
const STORAGE_BINDING_KEY: string = 'todayShortcutBinding';
const ROUTER_ABILITY_NAME: string = 'PhoneAbility';
const ROUTER_TARGET_TODAY: string = 'today';

interface TodayShortcutBindingPayload {
  activityName?: string;
  tagId?: string;
  tagName?: string;
  tagColor?: string;
  tagLightColor?: string;
  autoStart?: boolean;
}

const shortcutStorage: LocalStorage = new LocalStorage();

@Entry(shortcutStorage)
@Component
struct ShortCutCard {
  @LocalStorageProp(STORAGE_DIMENSION_KEY) @Watch('handleDimensionChange')
  private formDimension: string = FORM_DIMENSION_1X2;
  @LocalStorageProp(STORAGE_BINDING_KEY) @Watch('handleBindingChange')
  private bindingRaw: string = '';

  @State private isCompact: boolean = true;
  @State private hasBinding: boolean = false;
  @State private activityName: string = '';
  @State private tagId: string = '';
  @State private tagName: string = '';
  @State private tagColor: ResourceColor = $r('app.color.text_secondary');
  @State private tagLightColor: ResourceColor = $r('app.color.primary_container');
  @State private autoStart: boolean = false;

  aboutToAppear(): void {
    this.applyDimension(this.formDimension);
    this.applyBinding(this.bindingRaw);
  }

  private handleDimensionChange(): void {
    this.applyDimension(this.formDimension);
  }

  private handleBindingChange(): void {
    this.applyBinding(this.bindingRaw);
  }

  private applyDimension(dimension: string): void {
    this.isCompact = dimension === FORM_DIMENSION_1X2;
  }

  private applyBinding(raw: string): void {
    const parsed = this.parseBinding(raw);
    if (!parsed) {
      this.hasBinding = false;
      this.activityName = '';
      this.tagId = '';
      this.tagName = '';
      this.tagColor = $r('app.color.text_secondary');
      this.tagLightColor = $r('app.color.primary_container');
      this.autoStart = false;
      return;
    }

    this.hasBinding = true;
    this.activityName = parsed.activityName ?? '';
    this.tagId = parsed.tagId ?? '';
    this.tagName = parsed.tagName ?? '';
    this.tagColor = parsed.tagColor && parsed.tagColor.length > 0
      ? parsed.tagColor
      : $r('app.color.text_secondary');
    this.tagLightColor = parsed.tagLightColor && parsed.tagLightColor.length > 0
      ? parsed.tagLightColor
      : $r('app.color.primary_container');
    this.autoStart = !!parsed.autoStart;
  }

  private parseBinding(raw: string): TodayShortcutBindingPayload | null {
    if (!raw || raw.length === 0) {
      return null;
    }
    try {
      const parsed = JSON.parse(raw) as TodayShortcutBindingPayload;
      if (!parsed || typeof parsed !== 'object') {
        return null;
      }
      const activityName = parsed.activityName && parsed.activityName.length > 0 ? parsed.activityName.trim() : '';
      if (activityName.length === 0) {
        return null;
      }
      return {
        activityName: activityName,
        tagId: parsed.tagId ? parsed.tagId : '',
        tagName: parsed.tagName ? parsed.tagName : '',
        tagColor: parsed.tagColor ? parsed.tagColor : '',
        tagLightColor: parsed.tagLightColor ? parsed.tagLightColor : '',
        autoStart: !!parsed.autoStart
      };
    } catch (error) {
      return null;
    }
  }

  private resolveDisplayTitle(): ResourceStr {
    if (!this.hasBinding || this.activityName.length === 0) {
      return $r('app.string.shortcut_widget_title_fallback');
    }
    return this.activityName;
  }

  private resolveDisplayTagName(): ResourceStr {
    if (!this.hasBinding) {
      return $r('app.string.shortcut_widget_default_tag');
    }
    if (!this.tagName || this.tagName.length === 0) {
      return $r('app.string.shortcut_widget_default_tag');
    }
    return this.tagName;
  }

  private resolveActionHint(): ResourceStr {
    return this.autoStart
      ? $r('app.string.shortcut_widget_action_hint_autostart')
      : $r('app.string.shortcut_widget_action_hint');
  }

  private resolveActionBadgeText(): ResourceStr {
    return this.autoStart
      ? $r('app.string.shortcut_widget_action_badge_autostart')
      : $r('app.string.shortcut_widget_action_badge_fill');
  }

  private resolveTitleMaxLines(): number {
    return this.isCompact ? 1 : 2;
  }

  private handleCardClick(): void {
    if (this.hasBinding) {
      postCardAction(this, {
        action: 'router',
        abilityName: ROUTER_ABILITY_NAME,
        params: {
          target: ROUTER_TARGET_TODAY,
          openAddSheet: true,
          shortcutActivityName: this.activityName,
          shortcutTagId: this.tagId,
          shortcutAutoStart: this.autoStart
        }
      });
      return;
    }

    postCardAction(this, {
      action: 'router',
      abilityName: ROUTER_ABILITY_NAME,
      params: {
        target: ROUTER_TARGET_TODAY,
        openAddSheet: true
      }
    });
  }

  @Builder
  private HeaderLabel(): void {
    Row({ space: 4 }) { // Reduced gap
      Text('快捷启动') // Hardcoded for alignment as requested, or keep resource if sure
        .fontSize(14) // Smaller header text
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .letterSpacing(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private BoundStateBadge(): void {
    Row() {
      Text('已绑定')
        .fontSize(10)
        .fontColor($r('app.color.primary')) // Gray text
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .padding({ left: 6, right: 6, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.primary_lighter')) // Gray background
    .borderRadius(10);
  }

  @Builder
  private QuickStartBadge(): void {
    Row() {
      Text('直接开始')
        .fontSize(12)
        .fontColor($r('app.color.primary')) // Blue text
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
  }

  @Builder
  private TagRow(): void {
    Row() {
      // Tag Label with Dot
      Row({ space: 4 }) {
        Column()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.tagColor);
        
        Text(this.resolveDisplayTagName())
          .fontSize(12)
          .fontColor(this.tagColor)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .margin({right: 5})

      // Action Badge
      this.QuickStartBadge();
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private HeaderRow(): void {
    Row() {
      this.HeaderLabel();

      if (this.hasBinding) {
        this.BoundStateBadge();
      }
    }
    .width(SHORTCUT_FULL_PERCENT)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center); // Center vertically
  }

  @Builder
  private EmptyContent(): void {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24) // Larger Plus icon
          .fontWeight(FontWeight.Bold)
          .fontColor([$r('app.color.primary')]);
      }
      .backgroundColor($r('app.color.primary_lighter'))
      .borderRadius('50%')
      .padding(5)
      .margin({bottom: 10})
      // Title
      Text('暂无绑定事项')
        .fontSize(this.isCompact ? 16 : 18)
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 8 })

      // Subtitle
      Column({ space: 2 }) {
        Text('长按卡片进入编辑')
          .textAlign(TextAlign.Center)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Text('绑定常用事项后可快速新增')
          .textAlign(TextAlign.Center)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Center);
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(SHORTCUT_FULL_PERCENT);
  }

  @Builder
  private BoundContent(): void {
    Column() {
      // Main Title Area
      Column({ space: 8 }) {
        Text(this.resolveDisplayTitle())
          .fontSize(22) // Larger Title
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(this.resolveTitleMaxLines())
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Column() {
        this.TagRow()
        // Bottom Hint
        Text('点击后迅速记录该事项')
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary')) // Lighter gray
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(HorizontalAlign.Start)
    .width(SHORTCUT_FULL_PERCENT)
    .layoutWeight(1)
    .justifyContent(FlexAlign.SpaceBetween);
  }

  build() {
    Column() {

      if (this.hasBinding) {
        this.HeaderRow();
      }

      if (this.hasBinding) {
        this.BoundContent();
      } else {
        this.EmptyContent();
      }
    }
    .width(SHORTCUT_FULL_PERCENT)
    .height(SHORTCUT_FULL_PERCENT)
    .padding(this.isCompact
      ? $r('app.float.shortcut_widget_padding_compact')
      : $r('app.float.shortcut_widget_padding'))
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .borderRadius($r('app.float.shortcut_widget_corner_radius'))
    .linearGradient({
      direction: GradientDirection.RightTop,
      colors: [
        [$r('app.color.accent_lighter'), 0],
        [$r('app.color.primary_lighter'), 1]
      ]
    })
    .onClick(() => {
      this.handleCardClick();
    })
  }
}
