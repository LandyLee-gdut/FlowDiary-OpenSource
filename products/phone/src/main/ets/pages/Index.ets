import { SymbolGlyphModifier } from '@kit.ArkUI';
import { Today } from 'today';
import { Reflect }from 'reflect';
import { IdeaPool } from 'ideapool'
import { ConfigurationConstant } from '@kit.AbilityKit';
import { VibratorUtil, BreakpointConstants, BreakpointType, AppShadows, buildFlowLightEffect, COLOR_MODE_VERSION_KEY } from 'base';
import { PreferenceKeys, preferencesUtil } from 'base';
import { HdsTabs, HdsTabsController, HdsNavigationAttribute, HdsTabsAttribute, HdsNavigation,
  hdsEffect, hdsMaterial, HdsTabsFloatingStyle, HdsBarWidthRangeOptions, HdsTabsBackgroundStyle } from '@kit.UIDesignKit';
import { UserGuideView } from '../component/UserGuideView';

@Entry
@Component
struct Index {
  private static readonly REFLECT_TAB_INDEX: number = 0;
  private static readonly TODAY_TAB_INDEX: number = 1;
  private static readonly IDEAPOOL_TAB_INDEX: number = 2;
  private tabsController: HdsTabsController = new HdsTabsController();
  @Provide('pageInfos') pageInfos: NavPathStack = new NavPathStack();
  @StorageLink('savedTabIndex') @Watch('onSavedTabIndexChange') savedTabIndex: number = 1;
  // 使用 @Watch 来监听 widgetTargetTabIndex 变化，用于从卡片跳转
  @StorageLink('widgetTargetTabIndex') @Watch('onWidgetTargetTabIndexChange') widgetTargetTabIndex: number = -1;
  @State symbolModifier1: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.calendar')).fontSize(28);
  @State symbolModifier1Selected: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.calendar')).fontSize(28);
  @State symbolModifier2: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.sun_max')).fontSize(28);
  @State symbolModifier2Selected: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.sun_max')).fontSize(28);
  @State symbolModifier3: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.face_smiling')).fontSize(28);
  @State symbolModifier3Selected: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.face_smiling')).fontSize(28);
  @StorageProp('currentColorMode') @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 版本号在系统资源真正切换之后才会递增，保证流光 shader 用新色板重建
  @StorageProp(COLOR_MODE_VERSION_KEY) @Watch('onColorModeVersionChange') private colorModeVersion: number = 0;
  @StorageProp(BreakpointConstants.CURRENT_BREAKPOINT) @Watch('onBreakpointChange') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @StorageLink('showUserGuide') @Watch('onShowUserGuideChange') showUserGuide: boolean = false;
  @State guideSheetPresented: boolean = false;
  @StorageLink('activeMainTabIndex') @Watch('onActiveMainTabIndexChange') activeMainTabIndex: number = 1;
  @StorageLink('userGuideSheetVisible') @Watch('onUserGuideSheetVisibleChange') userGuideSheetVisible: boolean = false;
  @StorageLink('useFloatingActionBar') useFloatingActionBar: boolean = false;
  @State private shaderController: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  @State private isFlowEffectMounted: boolean = true;
  private flowEffectRemountToken: number = 0;
  private isPageActive: boolean = false;
  private guideSheetHostReady: boolean = false;
  private vibrator = VibratorUtil.getInstance();

  aboutToAppear() {
    this.isPageActive = true;
    console.info(`[Index] aboutToAppear: widgetTargetTabIndex=${this.widgetTargetTabIndex}, savedTabIndex=${this.savedTabIndex}`);
    // 检查是否有来自卡片的跳转请求（冷启动场景）
    if (this.widgetTargetTabIndex >= 0) {
      console.info(`[Index] Cold start: setting savedTabIndex to ${this.widgetTargetTabIndex}`);
      this.savedTabIndex = this.widgetTargetTabIndex;
      this.activeMainTabIndex = this.widgetTargetTabIndex;
      // 清除标记
      AppStorage.setOrCreate('widgetTargetTabIndex', -1);
    }
    this.syncColorModeState();
    this.recreateFlowEffect();
    this.activeMainTabIndex = this.savedTabIndex;
    this.guideSheetHostReady = false;
    this.userGuideSheetVisible = false;
    this.guideSheetPresented = false;
    this.syncPageVisibility('aboutToAppear');
    this.showUserGuide = this.readPersistedShowUserGuide();
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.flowEffectRemountToken += 1;
    this.guideSheetHostReady = false;
  }

  onColorModeChange(): void {
    // Preserve current tab index during color mode change
    // savedTabIndex 通过双向绑定自动保持同步，无需手动赋值
    this.syncColorModeState();
    if (this.isPageActive) {
      this.recreateFlowEffect();
    }
  }

  private onColorModeVersionChange(): void {
    this.onColorModeChange();
  }

  /**
   * 监听 savedTabIndex 变化
   * 用于同步页签索引
   */
  onSavedTabIndexChange(): void {
    // 此方法主要用于保持状态同步，实际页签切换由 HdsTabs 的双向绑定完成
    this.activeMainTabIndex = this.savedTabIndex;
    this.syncPageVisibility('saved_tab_changed');
  }

  /**
   * 监听 widgetTargetTabIndex 变化（由卡片 router 参数触发）
   * 用于热启动时切换到目标页签
   */
  onWidgetTargetTabIndexChange(): void {
    console.info(`[Index] onWidgetTargetTabIndexChange: widgetTargetTabIndex=${this.widgetTargetTabIndex}`);
    if (this.widgetTargetTabIndex >= 0) {
      console.info(`[Index] Hot start: switching to tab ${this.widgetTargetTabIndex}`);
      const targetIndex = this.widgetTargetTabIndex;
      // 先清除标记（直接修改 @StorageLink 变量即可，不要再次触发 AppStorage.setOrCreate）
      this.widgetTargetTabIndex = -1;
      // 更新 savedTabIndex 并切换页签
      this.savedTabIndex = targetIndex;
      this.activeMainTabIndex = targetIndex;
      this.syncPageVisibility('widget_target_tab_changed');
      // 延迟执行 changeIndex，确保 UI 已准备好
      setTimeout(() => {
        this.tabsController.changeIndex(targetIndex);
        console.info(`[Index] changeIndex called with ${targetIndex}`);
      }, 50);
    }
  }

  onShowUserGuideChange(): void {
    if (this.showUserGuide) {
      this.presentGuideSheetWhenHostReady('show_user_guide_changed');
    } else {
      this.guideSheetPresented = false;
      this.userGuideSheetVisible = false;
      this.syncPageVisibility('show_user_guide_changed');
    }
  }

  private onGuideSheetHostAppear(): void {
    this.guideSheetHostReady = true;
    this.presentGuideSheetWhenHostReady('navigation_host_appear');
  }

  onActiveMainTabIndexChange(): void {
    this.syncPageVisibility('active_tab_changed');
  }

  onBreakpointChange(): void {
  }

  onUserGuideSheetVisibleChange(): void {
    this.syncPageVisibility('guide_sheet_visibility_changed');
  }

  private readPersistedShowUserGuide(): boolean {
    try {
      const prefStore = preferencesUtil.getPreferences();
      if (prefStore && prefStore.hasSync(PreferenceKeys.SHOW_USER_GUIDE)) {
        const persisted = prefStore.getSync(PreferenceKeys.SHOW_USER_GUIDE, true) as boolean;
        return !!persisted;
      }
    } catch (err) {
      console.info('[Index] Failed to read showUserGuide preference', err);
    }
    return true;
  }

  private presentGuideSheetWhenHostReady(source: string): void {
    if (!this.showUserGuide || !this.guideSheetHostReady || this.guideSheetPresented) {
      return;
    }
    console.info(`[Index] presenting guide sheet after host readiness (${source})`);
    this.guideSheetPresented = true;
  }

  private syncPageVisibility(source: string): void {
    const guideVisible = this.userGuideSheetVisible;
    const reflectVisible = !guideVisible && this.activeMainTabIndex === Index.REFLECT_TAB_INDEX;
    const todayVisible = !guideVisible && this.activeMainTabIndex === Index.TODAY_TAB_INDEX;
    const ideaPoolVisible = !guideVisible && this.activeMainTabIndex === Index.IDEAPOOL_TAB_INDEX;
    AppStorage.setOrCreate('reflectPageVisible', reflectVisible);
    AppStorage.setOrCreate('todayPageVisible', todayVisible);
    AppStorage.setOrCreate('ideaPoolPageVisible', ideaPoolVisible);
    if (guideVisible) {
      AppStorage.setOrCreate('todayPageVisible', false);
      AppStorage.setOrCreate('reflectPageVisible', false);
      AppStorage.setOrCreate('ideaPoolPageVisible', false);
    }
    console.info(`[Index] visibility sync(${source}): tab=${this.activeMainTabIndex}, guideVisible=${guideVisible}, reflect=${reflectVisible}, today=${todayVisible}, idea=${ideaPoolVisible}`);
  }

  private syncColorModeState(): void {
    this.rebuildTabIcons();
  }

  private recreateFlowEffect(): void {
    this.flowEffectRemountToken += 1;
    const remountToken: number = this.flowEffectRemountToken;
    this.shaderController = new hdsEffect.ShaderEffectController();
    this.isFlowEffectMounted = false;
    setTimeout((): void => {
      if (this.isPageActive && remountToken === this.flowEffectRemountToken) {
        this.isFlowEffectMounted = true;
      }
    }, 0);
  }

  private rebuildTabIcons(): void {
    this.symbolModifier1 = this.createTabIcon($r('sys.symbol.calendar'), false);
    this.symbolModifier1Selected = this.createTabIcon($r('sys.symbol.calendar'), true);
    this.symbolModifier2 = this.createTabIcon($r('sys.symbol.sun_max'), false);
    this.symbolModifier2Selected = this.createTabIcon($r('sys.symbol.sun_max'), true);
    this.symbolModifier3 = this.createTabIcon($r('sys.symbol.face_smiling'), false);
    this.symbolModifier3Selected = this.createTabIcon($r('sys.symbol.face_smiling'), true);
  }

  private createTabIcon(symbol: Resource, selected: boolean): SymbolGlyphModifier {
    const modifier = new SymbolGlyphModifier(symbol).fontSize(28);
    return modifier.fontColor(selected ?  [$r('app.color.primary')] : [$r('app.color.tab_icon_inactive')]);
  }

  private getTabBarPosition(): BarPosition {
    if (this.shouldUseFloatingTabs()) {
      return BarPosition.End;
    }
    return new BreakpointType<BarPosition>({
      sm: BarPosition.End,
      md: BarPosition.End,
      lg: BarPosition.Start
    }).getValue(this.currentBreakpoint);
  }

  private shouldUseFloatingTabs(): boolean {
    return this.useFloatingActionBar;
  }

  private isVerticalTabs(): boolean {
    return !this.shouldUseFloatingTabs() && this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG;
  }

  private getTabBarHeight(): Length {
    if (this.isVerticalTabs()) {
      return '100%';
    }
    return this.shouldUseFloatingTabs() ? 56 : 100;
  }

  private shouldOverlapTabBar(): boolean {
    return this.shouldUseFloatingTabs() || this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_LG;
  }

  private getFloatingBarWidth(): HdsBarWidthRangeOptions {
    if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_MD) {
      return {
        smallWidth: 380,
        mediumWidth: 380,
        largeWidth: 380
      };
    }
    if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_LG) {
      return {
        smallWidth: 480,
        mediumWidth: 480,
        largeWidth: 480
      };
    }
    return {
      smallWidth: 280,
      mediumWidth: 380,
      largeWidth: 480
    };
  }

  private getDefaultBarBackgroundStyle(): HdsTabsBackgroundStyle {
    return {
      maskColor: $r('app.color.tab_bar_mask'),
      maskHeight: new BreakpointType<number>({
        sm: 75,
        md: 92,
        lg: 75
      }).getValue(this.currentBreakpoint)
    };
  }

  private buildFloatingTabsStyle(): HdsTabsFloatingStyle | undefined {
    if (!this.shouldUseFloatingTabs()) {
      console.info(`[Index][floatBar] disabled breakpoint=${this.currentBreakpoint}, useFloatingActionBar=${this.useFloatingActionBar}`);
      return undefined;
    }
    console.info(`[Index][floatBar] tabOnly build breakpoint=${this.currentBreakpoint}, activeTab=${this.activeMainTabIndex}`);
    return {
      barWidth: this.getFloatingBarWidth(),
      barBottomMargin: 28,
      gradientMask: { maskColor: $r('app.color.accent_lighter'), maskHeight: 92 },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
      },
      lightColor: $r('app.color.primary_light'),
      adaptToHandedness: false
    };
  }

  @Builder
  userGuideBuilder() {
    UserGuideView()
  }

  @Builder
  private renderMainTabsContent() {
    TabContent() {
      Reflect()
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .tabBar(new BottomTabBarStyle({normal: this.symbolModifier1, selected: this.symbolModifier1Selected}, '回顾'))

    TabContent() {
      Today()
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .tabBar(new BottomTabBarStyle({ normal: this.symbolModifier2, selected: this.symbolModifier2Selected }, '今日'))

    TabContent() {
      IdeaPool()
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .tabBar(new BottomTabBarStyle({ normal: this.symbolModifier3, selected: this.symbolModifier3Selected }, '灵感池'))
  }

  private buildGuideSheetOptions(): SheetOptions {
    return {
      detents: [SheetSize.LARGE, undefined, undefined],
      blurStyle: BlurStyle.Thick,
      preferType: new BreakpointType<SheetType>({ sm: SheetType.BOTTOM, md: SheetType.CENTER, lg: SheetType.CENTER}).getValue(this.currentBreakpoint),
      showClose: false,
      enableOutsideInteractive: false,
      onWillAppear: () => {
        this.userGuideSheetVisible = true;
        this.syncPageVisibility('guide_sheet_on_will_appear');
      },
      onAppear: () => {
        this.userGuideSheetVisible = true;
        this.syncPageVisibility('guide_sheet_on_appear');
      },
      onDisappear: () => {
        this.userGuideSheetVisible = false;
        this.syncPageVisibility('guide_sheet_on_disappear');
      },
      onWillDismiss: (action: DismissSheetAction) => {
        if (this.showUserGuide && action.reason === DismissReason.SLIDE_DOWN) {
          return;
        }
      }
    };
  }

  build() {
    Navigation(this.pageInfos) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.isFlowEffectMounted) {
          Column()
            .width('100%')
            .height('100%')
            .visualEffect(buildFlowLightEffect(this.shaderController))
            .expandSafeArea(
              [SafeAreaType.SYSTEM],
              [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
            )
        }

        if (canIUse("SystemCapability.UIDesign.HDSComponent.Core")) {
          HdsTabs({
            controller: this.tabsController,
            index: this.savedTabIndex
          }) {
            this.renderMainTabsContent()
          }
          .barHeight(this.getTabBarHeight())
          .barFloatingStyle(this.buildFloatingTabsStyle())
          .animationDuration(250)
          .onChange(async (index: number) => {
            this.savedTabIndex = index;
            this.activeMainTabIndex = index;
            this.syncPageVisibility('tabs_on_change');
            await this.vibrator.triggerPattern('haptic.pattern.crispHard', 'touch');
          })
          .width('100%')
          .height('100%')
          .scrollable(false)
          .barMode(BarMode.Fixed)
          .barBackgroundStyle(this.getDefaultBarBackgroundStyle())
          .barPosition(this.getTabBarPosition())
          .vertical(this.isVerticalTabs())
          .barOverlap(this.shouldOverlapTabBar())
        }
      }
      .width('100%')
      .height('100%')
    }
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], this.currentBreakpoint == BreakpointConstants.BREAKPOINT_LG ?
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.START, LayoutSafeAreaEdge.END, LayoutSafeAreaEdge.BOTTOM] :
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.START, LayoutSafeAreaEdge.END, LayoutSafeAreaEdge.BOTTOM])
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
    .hideTitleBar(true)
    .hideBackButton(true)
    .hideToolBar(true)
    .mode(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? NavigationMode.Auto : NavigationMode.Stack)
    .bindSheet($$this.guideSheetPresented, this.userGuideBuilder(), this.buildGuideSheetOptions())
    .onAppear(() => {
      this.onGuideSheetHostAppear();
    })
  }
}
