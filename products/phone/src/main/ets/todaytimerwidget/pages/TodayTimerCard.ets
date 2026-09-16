const timerStorage: LocalStorage = new LocalStorage();

const TODAY_TIMER_FULL_PERCENT: string = '100%';
const STORAGE_STATE_KEY: string = 'todayTimerWidgetState';
const STORAGE_TITLE_KEY: string = 'todayTimerWidgetTitle';
const STORAGE_COLOR_KEY: string = 'todayTimerWidgetColor';
const STORAGE_START_TIME_KEY: string = 'todayTimerWidgetStartTime';
const TODAY_TIMER_ROUTER_ABILITY_NAME: string = 'PhoneAbility';
const TODAY_TIMER_ROUTER_TARGET_TODAY: string = 'today';
const VIEW_STATE_EMPTY: string = 'empty';
const VIEW_STATE_RUNNING: string = 'running';

enum TodayTimerViewState {
  EMPTY = 0,
  RUNNING = 1
}

@Entry(timerStorage)
@Component
struct TodayTimerCard {
  @LocalStorageProp(STORAGE_STATE_KEY) @Watch('handleStateChange')
  private stateRaw: string = '';
  @LocalStorageProp(STORAGE_TITLE_KEY) @Watch('handleTitleChange')
  private titleRaw: string = '';
  @LocalStorageProp(STORAGE_COLOR_KEY) @Watch('handleColorChange')
  private colorRaw: string = '';
  @LocalStorageProp(STORAGE_START_TIME_KEY) @Watch('handleStartTimeChange')
  private startTimeRaw: string = '';

  @State private viewState: TodayTimerViewState = TodayTimerViewState.EMPTY;
  @State private runningItemTitle: ResourceStr = $r('app.string.today_timer_widget_empty_title');
  @State private themeColor: ResourceColor = $r('app.color.primary');
  @State private startTimeLabel: string = '';

  aboutToAppear(): void {
    this.applyState(this.stateRaw);
    this.applyTitle(this.titleRaw);
    this.applyColor(this.colorRaw);
    this.applyStartTime(this.startTimeRaw);
  }

  private handleStateChange(): void {
    this.applyState(this.stateRaw);
  }

  private handleTitleChange(): void {
    this.applyTitle(this.titleRaw);
  }

  private handleColorChange(): void {
    this.applyColor(this.colorRaw);
  }

  private handleStartTimeChange(): void {
    this.applyStartTime(this.startTimeRaw);
  }

  private applyState(raw: string): void {
    this.viewState = raw === VIEW_STATE_RUNNING ? TodayTimerViewState.RUNNING : TodayTimerViewState.EMPTY;
  }

  private applyTitle(raw: string): void {
    const safeTitle: ResourceStr = raw && raw.length > 0
      ? raw
      : $r('app.string.today_timer_widget_default_title');
    this.runningItemTitle = safeTitle;
  }

  private applyColor(raw: string): void {
    if (raw && raw.length > 0) {
      this.themeColor = raw;
      return;
    }
    this.themeColor = $r('app.color.primary');
  }

  private applyStartTime(raw: string): void {
    this.startTimeLabel = raw;
  }

  private handleCardClick(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: TODAY_TIMER_ROUTER_ABILITY_NAME,
      params: {
        target: TODAY_TIMER_ROUTER_TARGET_TODAY
      }
    });
  }

  private handlePauseClick(): void {
    postCardAction(this, {
      action: 'call',
      abilityName: TODAY_TIMER_ROUTER_ABILITY_NAME,
      params: {
        method: 'stopTimer'
      }
    });
  }

  @Builder
  private EmptyContent(): void {
    Column({ space: $r('app.float.today_timer_widget_empty_gap') }) {
      Column()
        .width($r('app.float.today_timer_widget_empty_icon_size'))
        .height($r('app.float.today_timer_widget_empty_icon_size'))
        .borderRadius($r('app.float.today_timer_widget_empty_icon_radius'))
        .backgroundColor($r('app.color.neutral_200'))
        .opacity($r('app.float.today_timer_widget_empty_icon_opacity'))

      Text($r('app.string.today_timer_widget_empty_title'))
        .fontSize($r('app.float.today_timer_widget_empty_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width(TODAY_TIMER_FULL_PERCENT)
    .height(TODAY_TIMER_FULL_PERCENT)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private RunningContent(): void {
    Column() {
      // Top: In Progress Indicator
      Row({ space: 6 }) {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.themeColor)
        
        Text('进行中')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Medium)
      }
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 4 })

      if (this.startTimeLabel) {
        Text(`开始于 ${this.startTimeLabel}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .fontWeight(FontWeight.Regular)
      }


      // Middle: Title
      Text(this.runningItemTitle)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(28)
        .textAlign(TextAlign.Center)
        .layoutWeight(1) // Push content to center vertically if needed, or use flex grow
        .width('100%')
        .margin({ bottom: 5 })

      // Bottom: Start Time & Pause Button
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          // Pause Icon
          // Using a simple shape or image if SymbolGlyph not available in widget
          // SymbolGlyph is API 11+, assuming available or use fallback
          // Widgets support limited components.
          // Drawing a pause icon using Stack/Row/Column or Image.
          // Let's use two bars for pause if no image
          SymbolGlyph($r('sys.symbol.pause'))
            .fontSize(18)
            .fontColor([Color.White])
            .fontWeight(700)
        }
        .width(30)
        .height(30)
        .backgroundColor($r('app.color.error')) // Warning/Error color for stop/pause
        .onClick(() => {
          this.handlePauseClick();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width(TODAY_TIMER_FULL_PERCENT)
    .height(TODAY_TIMER_FULL_PERCENT)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Background Glow
      Column()
        .width($r('app.float.today_timer_widget_glow_size'))
        .height($r('app.float.today_timer_widget_glow_size'))
        .borderRadius($r('app.float.today_timer_widget_glow_radius'))
        .backgroundColor(this.themeColor)
        .opacity($r('app.float.today_timer_widget_glow_opacity'))
        .align(Alignment.TopEnd)
        .offset({
          x: $r('app.float.today_timer_widget_glow_offset_x'),
          y: $r('app.float.today_timer_widget_glow_offset_y')
        })

      if (this.viewState === TodayTimerViewState.EMPTY) {
        this.EmptyContent();
      } else {
        this.RunningContent();
      }
    }
    .width(TODAY_TIMER_FULL_PERCENT)
    .height(TODAY_TIMER_FULL_PERCENT)
    .padding($r('app.float.today_timer_widget_padding'))
    .backgroundColor($r('app.color.bg_card'))
    .onClick(() => {
      this.handleCardClick();
    })
  }
}
