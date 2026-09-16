import { MatterItemModel } from 'base';
import { AddNewBall } from 'today'
import { createTodayUserGuideMatterItems } from '../model/TodayUserGuideMockData';
import { MatterItemDemo } from './MatterItemDemo';
import { curves, UIContext, promptAction } from '@kit.ArkUI';
import { FanOverlayParams, FanItemVO, toFanItemVOs, Point, DEFAULT_START_ANGLE, DEFAULT_SWEEP_ANGLE, buildFanOverlay, computeFanLayout, computeActiveFanIndex, computeLegacyFanLayout, computeLegacyRenderOffsets, computeFanItemViewPositions, FanItem, fanItemService } from 'today';
import { VibratorUtil } from 'base';
import { tagService, TagModel } from 'base';
import { BreakpointConstants } from 'base';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { JSON } from '@kit.ArkTS';

const TAG = 'TodayUserGuide';

type MatterDemoLayerType = 'recording' | 'paused' | 'todo';

interface MatterDemoStackLayerConfig {
  id: string;
  type: MatterDemoLayerType;
  offsetY: number;
  offsetX: number;
  scale: number;
  opacity: number;
  motionScale: number;
  tiltAngle: number;
  parallaxScale: number;
  tiltMotionScale: number;
}

interface ButtonPadding {
  left: number;
  right: number;
  top: number;
  bottom: number;
}

const MATTER_DEMO_STACK_LAYERS: MatterDemoStackLayerConfig[] = [
  { id: 'guide-layer-todo', type: 'todo', offsetY: 48, offsetX: -10, scale: 0.92, opacity: 0.7, motionScale: 0.4, tiltAngle: -4, parallaxScale: -0.3, tiltMotionScale: -0.08 },
  { id: 'guide-layer-paused', type: 'paused', offsetY: 24, offsetX: -4, scale: 0.96, opacity: 0.85, motionScale: 0.7, tiltAngle: -2, parallaxScale: -0.15, tiltMotionScale: -0.05 },
  { id: 'guide-layer-recording', type: 'recording', offsetY: 0, offsetX: 0, scale: 1, opacity: 1, motionScale: 1, tiltAngle: 0, parallaxScale: 0.1, tiltMotionScale: 0.02 }
];

interface GeneratedTypeLiteralInterface_1 {
  start: number;
  sweep: number;
}

@Component
export struct TodayUserGuide {
  onContinue?: () => void;
  @Watch('onActiveStateChanged') @Prop isActive: boolean = false;
  @State todoItem: MatterItemModel = new MatterItemModel();
  @State recordingItem: MatterItemModel = new MatterItemModel();
  @State pausedItem: MatterItemModel = new MatterItemModel();
  @State floatOffsetY: number = 0;
  @StorageLink('userGuideSheetVisible') @Watch('onGuideSheetVisibilityChanged') userGuideSheetVisible: boolean = false;
  @State private isComponentVisible: boolean = false;
  
  // 长按相关状态变量
  private longPressActive: boolean = false
  private lastLongPressAt: number = 0  // ms 时间戳
  private readonly LONG_PRESS_MS = 400
  private readonly TAP_GUARD_MS = 200  // 长按收尾后这段时间内禁止触发 tap
  
  // Pan 手势相关状态变量
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State positionX: number = 0;
  @State positionY: number = 0;
  private lastPosX: number = 0;
  private lastPosY: number = 0;
  
  // 扇形菜单相关状态
  @StorageLink('swissKnifeActiveIndex') swissKnifeActiveIndex: number = -1;
  @State swissKnifeItems: FanItemVO[] = [];
  @State tagData: TagModel[] = [];
  @State swissKnifeCenter: Point | null = null;
  @State swissKnifeLayoutPoints: Point[] = [];
  private pendingSwissKnifeIndex: number = -1; // 保存当前 Hover 的选中项，用于 Pan 结束时读取
  @State showLocalOverlay: boolean = false;
  @State fanOverlayParams: FanOverlayParams | null = null;
  
  // 直接开始相关
  @State isToggleOn: boolean = false;
  @State directStartEnabled: boolean = false;
  @State isShow: boolean = false;
  @State sheetHeight: number = 0;
  
  // 配置常量
  private readonly fanRadius: number = 140;
  private readonly fanInnerRadius: number = 48;
  private readonly fanOuterRadius: number = 220;
  private readonly addNewBallSize: number = 50;
  
  // 其他工具类
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private panOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.All});
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  private isFloatRunning: boolean = false;
  private readonly sectionSpacing: number = 16;
  private readonly headingSpacing: number = 8;
  private readonly cardHeight: number = 100;
  private readonly cardStackHeight: number = 350;
  private readonly cardStackWidth: string = '90%';
  private readonly ctaSectionSpacing: number = 8;
  private readonly ctaButtonPadding: ButtonPadding = {
    left: 24,
    right: 24,
    top: 8,
    bottom: 8
  };
  private readonly floatAmplitude: number = 8;
  private readonly floatFrameDuration: number = 2400;

  aboutToAppear(): void {
    const items: MatterItemModel[] = createTodayUserGuideMatterItems();
    if (items.length >= 3) {
      this.recordingItem = items[0];
      this.pausedItem = items[1];
      this.todoItem = items[2];
    }
    this.reconcileFloatingState();
    
    // 加载瑞士军刀项目和标签数据
    this.loadSwissKnifeItemsFromPreferences();
    this.loadTagsFromDatabase();
    
    // 加载偏好设置
    this.loadDirectStartPreference();
  }

  aboutToDisappear(): void {
    this.stopFloating();
    this.closeSwissKnife();
  }

  private onActiveStateChanged(): void {
    this.reconcileFloatingState();
  }

  private onGuideSheetVisibilityChanged(): void {
    this.reconcileFloatingState();
  }

  private shouldRunFloating(): boolean {
    return this.isActive && this.userGuideSheetVisible && this.isComponentVisible;
  }

  private reconcileFloatingState(): void {
    if (this.shouldRunFloating()) {
      this.startFloating();
      return;
    }
    this.stopFloating();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: this.sectionSpacing }) {
        Column({ space: this.headingSpacing }) {
          Text('「今日」页面')
            .fontSize(30)
            .fontColor($r('app.color.primary'))
            .fontWeight(600)
            .transition(TransitionEffect.translate({ y: 300}).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1500 }))
          Text('待办、暂停、进行中，三种状态一键切换')
            .fontColor($r('app.color.text_tertiary'))
            .fontSize(14)
            .transition(TransitionEffect.translate({ y: 400}).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1500 }))
        }
        .height(50)
        .offset({ y: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 20 })
        .alignItems(HorizontalAlign.Center)


        Column({ space: 20 }) {
          ForEach(
            MATTER_DEMO_STACK_LAYERS,
            (layer: MatterDemoStackLayerConfig, index: number) => {
              Column() {
                MatterItemDemo({ item: this.resolveLayerItem(layer.type) })
                  .height(this.cardHeight)
                  .width('100%')
              }
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.3, y: 0.3})).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 100 * index}))
              .translate({
                x: layer.offsetX + this.floatOffsetY * layer.motionScale * layer.parallaxScale,
                y: layer.offsetY + this.floatOffsetY * layer.motionScale
              })
              .scale({ x: layer.scale, y: layer.scale })
              .opacity(layer.opacity)
              .rotate({ x: 0, y: 0, z: 1, angle: layer.tiltAngle + this.floatOffsetY * layer.tiltMotionScale });
            },
            (layer: MatterDemoStackLayerConfig) => layer.id
          );
        }
        .justifyContent(FlexAlign.Center)
        .width(this.cardStackWidth)
        .height(this.cardStackHeight)
        .margin({bottom: 30})

        Column({ space: this.ctaSectionSpacing }) {

          Text('轻按或长按灵感球，开始记录！')
            .transition(TransitionEffect.translate({ y: 300}).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 500 }))
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
            .fontWeight(500);

          AddNewBall()
            .transition(TransitionEffect.translate({ y: 400}).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 600 }))
            .width(this.addNewBallSize)
            .height(this.addNewBallSize)
            .margin({
              top: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 10 : 5,
              bottom: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 15 : 5,
            })
            .gesture(
              GestureGroup(GestureMode.Exclusive,
                GestureGroup(
                  GestureMode.Parallel,
                  LongPressGesture({ duration: 400 })
                    .onAction((event) => {
                      // 新增：进入长按态并记录时间
                      this.longPressActive = true
                      this.lastLongPressAt = Date.now()

                      // 下面保持你的原逻辑不变
                      const finger = event?.fingerList ? event.fingerList[0] : undefined;
                      if (!finger) {
                        return;
                      }
                      if (typeof finger.globalX !== 'number' || typeof finger.globalY !== 'number') {
                        return;
                      }
                      const halfSize: number = this.addNewBallSize / 2;
                      const localX: number = typeof finger.localX === 'number' ? finger.localX : halfSize;
                      const localY: number = typeof finger.localY === 'number' ? finger.localY : halfSize;
                      const center: Point = {
                        x: finger.globalX - localX + halfSize,
                        y: finger.globalY - localY + halfSize
                      };
                      this.openSwissKnife(center);
                    })
                    .onActionEnd(() => {
                      this.finalizeSwissKnifeSelection();
                    }),
                  PanGesture()
                    .onActionStart((event: GestureEvent) => {
                      console.info('Pan start');
                      // 记录起始位置（你的原逻辑）
                      if (event && event.fingerList && event.fingerList[0]) {
                        const finger = event.fingerList[0];
                        if (typeof finger.globalX === 'number' && typeof finger.globalY === 'number') {
                          this.lastPosX = finger.globalX;
                          this.lastPosY = finger.globalY;
                        }
                      }
                    })
                    // 当该手势被触发时，根据回调获得拖动的距离，修改该组件的位移距离从而实现组件的移动（你的原逻辑）
                    .onActionUpdate((event: GestureEvent) => {
                      if (event) {
                        this.offsetX = (this.positionX + event.offsetX);
                        this.offsetY = this.positionY + event.offsetY;

                        if (this.showLocalOverlay && event.fingerList && event.fingerList[0]) {
                          const finger = event.fingerList[0];
                          if (typeof finger.globalX === 'number' && typeof finger.globalY === 'number') {
                            // 直接使用成员变量计算选中索引
                            const newIndex = this.computeActiveIndexFromGlobalPosition(
                              finger.globalX,
                              finger.globalY
                            );

                            this.pendingSwissKnifeIndex = newIndex;

                            // 更新 StorageLink（只在索引变化时更新）
                            if (newIndex !== this.swissKnifeActiveIndex) {
                              this.swissKnifeActiveIndex =
                                newIndex; // mirror AppStorage immediately for same-frame reads
                              AppStorage.setOrCreate('swissKnifeActiveIndex', newIndex);
                              this.vibratorUtil.triggerHaptic('haptic.effect.sharp')
                            }
                          }
                        }
                      }
                    })
                    .onActionEnd(() => {
                      // 你的原逻辑
                      this.positionX = this.offsetX;
                      this.positionY = this.offsetY;
                      this.finalizeSwissKnifeSelection();
                    })
                    .onActionCancel(() => {
                      this.finalizeSwissKnifeSelection();
                    })
                ),
                TapGesture({ count: 1, fingers: 1 })
                  .onAction(() => {
                    // 新增：Tap 防抖与互斥兜底（不触碰你的后续逻辑）
                    if (this.longPressActive) {
                      return
                    }
                    if (Date.now() - this.lastLongPressAt < this.TAP_GUARD_MS) {
                      return
                    }

                    // 下面保持你的原逻辑不变
                    this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
                    this.isToggleOn = this.directStartEnabled;
                    hilog.info(0x0000, TAG,
                      `[Today] AddNewBall onClick -> directStartEnabled=${this.directStartEnabled}, isToggleOn=${this.isToggleOn}`);
                    this.isShow = true;
                    this.refreshSheetHeight();
                  })
              ),
            )
        }
        .height(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 65 : 55)
        .alignItems(HorizontalAlign.Center)
        .margin({
          bottom: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 20,
        })

        Button('继续')
          .transition(TransitionEffect.translate({ y: 500 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 700 }))
          .width('60%')
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.neutral_100'))
          .padding(this.ctaButtonPadding)
          .margin({ top: 30 })
          .onClick(() => {
            if (this.onContinue) {
              this.onContinue();
            }
          })
      }
      .zIndex(1)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')

      // 本地渲染的扇形菜单，避免跨弹层 z-order 竞争
      this.renderLocalOverlay();
    }
    .width('100%')
    .height('100%')
    .onVisibleAreaChange([0, 1], (_isExpanding: boolean, currentRatio: number) => {
      const nextVisible = currentRatio > 0;
      if (this.isComponentVisible === nextVisible) {
        return;
      }
      this.isComponentVisible = nextVisible;
      this.reconcileFloatingState();
    })
  }

  @Builder
  private renderLocalOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showLocalOverlay && this.fanOverlayParams) {
        // 半透明遮罩，点击收起扇形菜单
        Column() {
        }
        // .width('100%')
        // .height('100%')
        // .backgroundColor('#66000000')
        .onClick(() => {
          this.closeSwissKnife();
        });
        // 扇形菜单内容
        Stack({ alignContent: (this.fanOverlayParams as FanOverlayParams).stackAlignment }) {
          buildFanOverlay(this.fanOverlayParams as FanOverlayParams);
        }
        .width('100%')
        .height('100%')
      } else {
        Column()
      }
    }
    .zIndex(100)
  }

  private resolveLayerItem(type: MatterDemoLayerType): MatterItemModel {
    if (type === 'recording') {
      return this.recordingItem;
    }
    if (type === 'paused') {
      return this.pausedItem;
    }
    return this.todoItem;
  }

  private startFloating(): void {
    if (this.isFloatRunning) {
      return;
    }
    this.isFloatRunning = true;
    this.scheduleNextFloat(this.floatAmplitude);
  }

  private stopFloating(): void {
    if (!this.isFloatRunning && this.floatOffsetY === 0) {
      return;
    }
    this.isFloatRunning = false;
    this.resetFloatPosition();
  }

  private resetFloatPosition(): void {
    const uiContext: UIContext | undefined = this.getUIContext();
    if (uiContext) {
      uiContext.animateTo({ duration: 150 }, () => {
        this.floatOffsetY = 0;
      });
      return;
    }
    this.floatOffsetY = 0;
  }

  private scheduleNextFloat(targetOffset: number): void {
    if (!this.isFloatRunning || !this.shouldRunFloating()) return;
    const uiContext = this.getUIContext();
    if (!uiContext) { this.isFloatRunning = false; return; }

    uiContext.animateTo({
      duration: 2000,
      curve: Curve.EaseInOut,
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        if (!this.isFloatRunning || !this.shouldRunFloating()) return;
        const next = targetOffset > 0 ? -targetOffset : Math.abs(targetOffset);
        this.scheduleNextFloat(next);
      }
    }, () => {
      if (!this.isFloatRunning || !this.shouldRunFloating()) return;
      this.floatOffsetY = targetOffset;
    });
  }

  // ========== 扇形菜单相关方法 ==========

  private rebuildSwissKnifeItemVOs(): void {
    this.swissKnifeItems = toFanItemVOs(this.swissKnifeItems, this.tagData);
  }

  private loadSwissKnifeItemsFromPreferences(): void {
    try {
      const items: FanItem[] = fanItemService.getAllFanItems();
      this.swissKnifeItems = toFanItemVOs(items, this.tagData);
      hilog.info(0x0000, TAG, `[TodayUserGuide] Loaded ${this.swissKnifeItems.length} swiss knife items`);
    } catch (error) {
      hilog.error(0x0000, TAG, `[TodayUserGuide] Error loading swiss knife items: ${JSON.stringify(error)}`);
      this.swissKnifeItems = [];
    }
  }

  async loadTagsFromDatabase(): Promise<void> {
    try {
      this.tagData = await tagService.getAllTagsForUI();
      hilog.info(0x0000, TAG, `[TodayUserGuide] Loaded ${this.tagData.length} tags from database`);
      this.rebuildSwissKnifeItemVOs();
    } catch (error) {
      hilog.error(0x0000, TAG, `[TodayUserGuide] Error loading tags: ${JSON.stringify(error)}`);
    }
  }

  private loadDirectStartPreference(): void {
    hilog.info(0x0000, TAG, `[TodayUserGuide] Loading directStart preference`);
    try {
      // 这里可以加载用户的偏好设置，暂时设为默认值
      this.directStartEnabled = false;
      this.isToggleOn = false;
      hilog.info(0x0000, TAG, `[TodayUserGuide] directStart state loaded. directStartEnabled=${this.directStartEnabled}, isToggleOn=${this.isToggleOn}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `[TodayUserGuide] error in loading directStart state: ${JSON.stringify(error)}`)
      this.directStartEnabled = false;
      this.isToggleOn = false;
    }
  }

  private refreshSheetHeight(): void {
    // 简单的计算，可以根据需要调整
    this.sheetHeight = 400;
  }

  // 根据全局坐标计算激活的扇形索引（使用成员变量，不依赖参数）
  private computeActiveIndexFromGlobalPosition(globalX: number, globalY: number): number {
    const itemCount: number = this.swissKnifeItems.length;
    const center: Point | null = this.swissKnifeCenter;
    const layoutPoints: Point[] = this.swissKnifeLayoutPoints;
    const globalPoint: Point = { x: globalX, y: globalY };

    return computeActiveFanIndex(
      globalPoint,
      center,
      layoutPoints,
      itemCount,
      this.fanInnerRadius,
      this.fanOuterRadius
    );
  }

  private getFanAngles(): GeneratedTypeLiteralInterface_1 {
    // 引导页统一使用小屏角度，居中向上展开
    return {
      start: DEFAULT_START_ANGLE,
      sweep: DEFAULT_SWEEP_ANGLE
    };
  }

  private openSwissKnife(center: Point): void {
    if (this.swissKnifeItems.length === 0) {
      hilog.warn(0x0000, TAG, `[TodayUserGuide] No swiss knife items to show`);
      return;
    }

    this.closeSwissKnife();
    this.pendingSwissKnifeIndex = -1;
    const fanAngles = this.getFanAngles();
    const start = fanAngles.start;
    const sweep = fanAngles.sweep;
    // 引导页统一使用小屏布局，避免 Breakpoint 差异
    const layoutPoints: Point[] = computeLegacyFanLayout(center, this.swissKnifeItems.length);
    
    // 保存 overlay 配置信息，用于 PanGesture 中计算选中索引
    this.swissKnifeCenter = center;
    this.swissKnifeLayoutPoints = layoutPoints;
    
    const params: FanOverlayParams = new FanOverlayParams(
      center,
      start,
      sweep,
      this.fanRadius,
      this.fanInnerRadius,
      this.fanOuterRadius,
      this.swissKnifeItems,
      layoutPoints,
      computeLegacyRenderOffsets(this.swissKnifeItems.length),
      Alignment.Bottom,
      this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 175 : 50,
      false,
      (item: FanItemVO) => this.handleSwissKnifePick(item),
      () => this.closeSwissKnife()
    );

    this.fanOverlayParams = params;
    this.showLocalOverlay = true;
    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
    hilog.info(0x0000, TAG, `[TodayUserGuide] Swiss knife overlay opened at center: (${center.x}, ${center.y})`);
  }

  private closeSwissKnife(): void {
    this.showLocalOverlay = false;
    this.fanOverlayParams = null;
    this.swissKnifeCenter = null;
    this.swissKnifeLayoutPoints = [];
    this.pendingSwissKnifeIndex = -1;
    // 重置选中索引
    AppStorage.setOrCreate('swissKnifeActiveIndex', -1);
    
    hilog.info(0x0000, TAG, `[TodayUserGuide] Swiss knife overlay closed`);
  }

  private finalizeSwissKnifeSelection(): void {
    const selectedIndex: number = this.pendingSwissKnifeIndex >= 0
      ? this.pendingSwissKnifeIndex
      : this.swissKnifeActiveIndex;
    hilog.info(0x0000, TAG, `[TodayUserGuide] finalizeSwissKnifeSelection -> pending=${this.pendingSwissKnifeIndex}, storage=${this.swissKnifeActiveIndex}, selected=${selectedIndex}`);
    if (selectedIndex >= 0 && selectedIndex < this.swissKnifeItems.length) {
      const selectedItem: FanItemVO | undefined = this.swissKnifeItems[selectedIndex];
      if (selectedItem) {
        this.handleSwissKnifePick(selectedItem);
      }
    }
    this.closeSwissKnife();
    this.longPressActive = false;
    this.lastLongPressAt = Date.now();
    this.pendingSwissKnifeIndex = -1;
  }

  private handleSwissKnifePick(item: FanItemVO): void {
    hilog.info(0x0000, TAG, `[TodayUserGuide] Swiss knife item picked: ${item.label}`);
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    
    // 在演示版本中，我们只显示一个提示
    promptAction.openToast({
      message: `选中了: ${item.label}`,
      duration: 1500
    })
  }
}
