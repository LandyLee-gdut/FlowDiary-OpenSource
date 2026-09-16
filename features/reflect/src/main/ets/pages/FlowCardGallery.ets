import dayjs from 'dayjs';
import {
  buildFlowLightEffect,
  COLOR_MODE_STORAGE_KEY,
  COLOR_MODE_VERSION_KEY,
  StorageKeys,
  VibratorUtil,
} from 'base';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ReflectFlowCard } from '../component/ReflectFlowCard';
import { curves, display, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { FlowCardGallerySelection, FlowCardGalleryTimelinePayload } from '../model/FlowCardGalleryController';
import { FlowCardGalleryController } from '../model/FlowCardGalleryController';
import type { ReflectFlowCardItem } from '../model/ReflectFlowCardService';
import { BreakpointConstants, BreakpointType, BreakpointSystem } from 'base';
import { window } from '@kit.ArkUI';
import {
  hdsEffect,
  hdsMaterial,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';

const TAG = 'ReflectFlowCardGallery';

@Builder
export function ReflectFlowCardGalleryBuilder(name: string, param?: Object) {
  ReflectFlowCardGallery();
}

@Component
struct FlowCardCarouselWide {
  @Link currentIndex: number;
  @Prop items: ReflectFlowCardItem[];
  @Prop itemCount: number;
  @Prop layout: GalleryLayoutConfig;
  boundaryHandler?: (direction: number) => void;
  private swiperController: SwiperController = new SwiperController();

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Swiper(this.swiperController) {
        ForEach(this.items, (item: ReflectFlowCardItem) => {
          Row() {
            ReflectFlowCard({ item })
              .width(this.layout.cardMaxWidth)
              .height('100%')
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }, (item: ReflectFlowCardItem) => `${item.activityId}_${item.latestStartTimeMs}`)
      }
      .displayCount(this.layout.displayCount)
      .itemSpace(this.layout.cardGap)
      .loop(false)
      .indicator(false)
      .index($$this.currentIndex)
      .prevMargin(this.layout.prevMargin)
      .nextMargin(this.layout.nextMargin)
      .duration(400)
      .curve(curves.springMotion())
      .onGestureSwipe((index, event) => {
        const currentOffset = event.currentOffset;
        const boundaryThreshold = 50;
        if (this.currentIndex === 0 && currentOffset > boundaryThreshold) {
          this.boundaryHandler?.(-1);
        } else if (this.currentIndex >= this.itemCount - this.layout.displayCount && currentOffset < -boundaryThreshold) {
          this.boundaryHandler?.(1);
        }
      })
      .width('100%')
      .height('100%')

      if (this.layout.showNavButtons) {
        Row() {
          if (this.currentIndex > 0) {
            this.NavButton($r('sys.symbol.chevron_left'), () => {
              this.currentIndex--;
            })
          }
          Blank()
          if (this.currentIndex < this.itemCount - this.layout.displayCount) {
            this.NavButton($r('sys.symbol.chevron_right'), () => {
              this.currentIndex++;
            })
          }
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  NavButton(icon: Resource, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(44)
    .height(44)
    .backgroundColor($r('app.color.neutral_100'))
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
    .onClick(() => action())
  }
}

interface GalleryLayoutConfig {
  displayCount: number;
  cardGap: number;
  prevMargin: number | string;
  nextMargin: number | string;
  cardMaxWidth: string | number;
  showNavButtons: boolean;
}

@Component
struct FlowCardStackSwiper {
  @Link @Watch('onIndexChange') currentIndex: number;
  @Prop items: ReflectFlowCardItem[];
  @Prop @Watch('handleItemCountChange') itemCount: number;
  boundaryHandler?: (direction: number) => void;
  // 卡缩放度列表
  @State private cardsScale: number[] = [];
  // 卡旋转角度列表
  @State private cardsAngle: number[] = [];
  // 卡Z轴层级列表
  @State private cardsZIndex: number[] = [];
  // 卡高度百分比列表
  @State private cardsHeight: string[] = [];
  // 屏幕宽度
  private displayWidth: number = 0;
  // Swiper 两侧的偏移量 - Reduced to allow cards to stack more visibly
  private swiperMargin: number = 24;
  private maxScale = 1.0;
  private minScale = 0.85; // Increased depth contrast
  private maxAngle = 3;
  private selectedHeight = '88%'; // Selected card is shorter
  private unselectedHeight = '95%'; // Side cards are taller
  private lastBoundaryTriggerAtMs: number = 0;

  aboutToAppear(): void {
    const displayData: display.Display = display.getDefaultDisplaySync();
    this.displayWidth = px2vp(displayData.width);
    this.handleItemCountChange();
  }

  private handleItemCountChange(): void {
    if (this.cardsScale.length !== this.itemCount) {
      this.cardsScale = [];
      this.cardsAngle = [];
      this.cardsZIndex = [];
      this.cardsHeight = [];
      for (let i = 0; i < this.itemCount; i++) {
        this.cardsScale.push(i === this.currentIndex ? this.maxScale : this.minScale);
        this.cardsZIndex.push(i === this.currentIndex ? 2 : 1);
        this.cardsHeight.push(i === this.currentIndex ? this.selectedHeight : this.unselectedHeight);
        
        if (i < this.currentIndex) {
            this.cardsAngle.push(-this.maxAngle);
        } else if (i > this.currentIndex) {
            this.cardsAngle.push(this.maxAngle);
        } else {
            this.cardsAngle.push(0);
        }
      }
    }
  }

  private onIndexChange() {
    for(let i=0; i<this.cardsScale.length; i++) {
      if (i === this.currentIndex) {
        this.cardsScale[i] = this.maxScale;
        this.cardsAngle[i] = 0;
        this.cardsZIndex[i] = 2;
        this.cardsHeight[i] = this.selectedHeight;
      } else {
        this.cardsScale[i] = this.minScale;
        this.cardsZIndex[i] = 1;
        this.cardsHeight[i] = this.unselectedHeight;
        if (i < this.currentIndex) {
            this.cardsAngle[i] = -this.maxAngle;
        } else if (i > this.currentIndex) {
            this.cardsAngle[i] = this.maxAngle;
        }
      }
    }
  }

  isIndexValid(index: number): boolean {
    return index >= 0 && index < this.itemCount;
  }

  build() {
    Column() {
      Swiper() {
        ForEach(this.items, (item: ReflectFlowCardItem, index: number) => {
            Row() {
              ReflectFlowCard({ item })
                .width('100%')
                .height('95%')
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .height(this.cardsHeight[index]) // Dynamic height
            .scale({ x: this.cardsScale[index], y: this.cardsScale[index] })
            .rotate({ 
                z: 1, 
                angle: this.cardsAngle[index], 
                centerX: '50%', 
                centerY: '50%' 
            })
            .zIndex(this.cardsZIndex[index]) // Dynamic layering
            .animation({
              curve: curves.responsiveSpringMotion(0.35, 0.7)
            })
        }, (item: ReflectFlowCardItem) => `${item.activityId}_${item.latestStartTimeMs}`)
      }
      // .margin({ top: 10 })
      .loop(false)
      .indicator(false)
      .index($$this.currentIndex)
      .prevMargin(this.swiperMargin)
      .nextMargin(this.swiperMargin)
      .duration(400)
      .curve(curves.springMotion())
      .onAnimationStart((index, targetIndex) => {
        if (this.isIndexValid(targetIndex)) {
            this.cardsScale[targetIndex] = this.maxScale;
            this.cardsAngle[targetIndex] = 0;
            this.cardsZIndex[targetIndex] = 2;
            this.cardsHeight[targetIndex] = this.selectedHeight;
        }
        
        // Reset others
        this.cardsScale.forEach((_, i) => {
            if (i !== targetIndex) {
                this.cardsScale[i] = this.minScale;
                this.cardsZIndex[i] = 1;
                this.cardsHeight[i] = this.unselectedHeight;
                if (i < targetIndex) {
                    this.cardsAngle[i] = -this.maxAngle;
                } else if (i > targetIndex) {
                    this.cardsAngle[i] = this.maxAngle;
                }
            }
        })
      })
      .onGestureSwipe((index, event) => {
        const currentOffset = event.currentOffset;
        const totalScanDistance = this.displayWidth * 0.8;
        const now = Date.now();
        const boundaryThreshold = this.displayWidth * 0.18;

        if (now - this.lastBoundaryTriggerAtMs > 800) {
          if (this.currentIndex === 0 && currentOffset > boundaryThreshold) {
            this.lastBoundaryTriggerAtMs = now;
            this.boundaryHandler?.(-1);
          } else if (this.currentIndex === this.itemCount - 1 && currentOffset < -boundaryThreshold) {
            this.lastBoundaryTriggerAtMs = now;
            this.boundaryHandler?.(1);
          }
        }

        if (currentOffset < 0) {
          // Swiping Left (Next)
          const ratio = Math.min(Math.abs(currentOffset) / totalScanDistance, 1);

          if (this.isIndexValid(this.currentIndex + 1)) {
             const targetScale = this.minScale + (this.maxScale - this.minScale) * ratio * 1.2;
             this.cardsScale[this.currentIndex + 1] = Math.min(targetScale, this.maxScale);
             this.cardsAngle[this.currentIndex + 1] = this.maxAngle - (this.maxAngle * ratio);
             this.cardsZIndex[this.currentIndex + 1] = ratio > 0.5 ? 2 : 1; // Elevation switch
             const currentHeightVal = 95 - (7 * ratio); // 95% down to 88%
             this.cardsHeight[this.currentIndex + 1] = `${currentHeightVal}%`;
          }

          if (this.isIndexValid(this.currentIndex)) {
             const targetScale = this.maxScale - (this.maxScale - this.minScale) * ratio * 1.2;
             this.cardsScale[this.currentIndex] = Math.max(targetScale, this.minScale);
             this.cardsAngle[this.currentIndex] = -this.maxAngle * ratio;
             this.cardsZIndex[this.currentIndex] = ratio > 0.5 ? 1 : 2;
             const currentHeightVal = 88 + (7 * ratio); // 88% up to 95%
             this.cardsHeight[this.currentIndex] = `${currentHeightVal}%`;
          }
          
          if (this.isIndexValid(this.currentIndex - 1)) {
            this.cardsScale[this.currentIndex - 1] = this.minScale;
            this.cardsAngle[this.currentIndex - 1] = -this.maxAngle;
            this.cardsZIndex[this.currentIndex - 1] = 1;
            this.cardsHeight[this.currentIndex - 1] = this.unselectedHeight;
          }

        } else {
          // Swiping Right (Prev)
          const ratio = Math.min(Math.abs(currentOffset) / totalScanDistance, 1);

          if (this.isIndexValid(this.currentIndex - 1)) {
             const targetScale = this.minScale + (this.maxScale - this.minScale) * ratio * 1.2;
             this.cardsScale[this.currentIndex - 1] = Math.min(targetScale, this.maxScale);
             this.cardsAngle[this.currentIndex - 1] = -this.maxAngle + (this.maxAngle * ratio);
             this.cardsZIndex[this.currentIndex - 1] = ratio > 0.5 ? 2 : 1;
             const currentHeightVal = 95 - (7 * ratio);
             this.cardsHeight[this.currentIndex - 1] = `${currentHeightVal}%`;
          }

          if (this.isIndexValid(this.currentIndex)) {
             const targetScale = this.maxScale - (this.maxScale - this.minScale) * ratio * 1.2;
             this.cardsScale[this.currentIndex] = Math.max(targetScale, this.minScale);
             this.cardsAngle[this.currentIndex] = this.maxAngle * ratio;
             this.cardsZIndex[this.currentIndex] = ratio > 0.5 ? 1 : 2;
             const currentHeightVal = 88 + (7 * ratio);
             this.cardsHeight[this.currentIndex] = `${currentHeightVal}%`;
          }

          if (this.isIndexValid(index + 1)) {
             this.cardsScale[index + 1] = this.minScale;
             this.cardsAngle[index + 1] = this.maxAngle;
             this.cardsZIndex[index + 1] = 1;
             this.cardsHeight[index + 1] = this.unselectedHeight;
          }
        }
      })
      .height("100%")
      .width("100%")
    }
    .width("100%")
    .height("100%")
    .justifyContent(FlexAlign.Center)
  }
}


@Component
export struct ReflectFlowCardGallery {
  @StorageLink(StorageKeys.SELECTED_DATE) @Watch('handleSelectionChange') selectedDate: number = dayjs().date();
  @StorageLink(StorageKeys.SELECTED_MONTH) @Watch('handleSelectionChange') selectedMonth: number = dayjs().month() + 1;
  @StorageLink(StorageKeys.SELECTED_YEAR) @Watch('handleSelectionChange') selectedYear: number = dayjs().year();
  @State private itemCount: number = 0;
  @State private items: ReflectFlowCardItem[] = [];
  @State private isLoading: boolean = false;
  @State private dateLabel: string = '';
  @State @Watch('handleIndexChange') private currentIndex: number = 0;
  @State delay: boolean = true;
  @State private shaderController: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  @State private isFlowEffectMounted: boolean = true;
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange')
  private currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 版本号在系统资源真正切换之后才会递增，保证流光 shader 用新色板重建
  @StorageProp(COLOR_MODE_VERSION_KEY) @Watch('onColorModeVersionChange')
  private colorModeVersion: number = 0;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private controller: FlowCardGalleryController | null = null;
  private suppressSelectionChangeCount: number = 0;
  private flowEffectRemountToken: number = 0;
  private isPageActive: boolean = false;

  pageInfos: NavPathStack = new NavPathStack();
  @StorageProp(BreakpointConstants.CURRENT_BREAKPOINT) currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @State private galleryWidthVp: number = 0;
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  private windowSizeListener = (size: window.Size) => {
    this.galleryWidthVp = px2vp(size.width);
  }

  private getLayoutConfig(): GalleryLayoutConfig {
    return new BreakpointType<GalleryLayoutConfig>({
      sm: {
        displayCount: 1,
        cardGap: 0,
        prevMargin: 24,
        nextMargin: 24,
        cardMaxWidth: '100%',
        showNavButtons: false
      },
      md: {
        displayCount: 2,
        cardGap: 12,
        prevMargin: 24,
        nextMargin: 24,
        cardMaxWidth: '100%',
        showNavButtons: true
      },
      lg: {
        displayCount: 3,
        cardGap: 16,
        prevMargin: 32,
        nextMargin: 32,
        cardMaxWidth: '100%',
        showNavButtons: true
      }
    }).getValue(this.currentBreakpoint);
  }

  aboutToAppear(): void {
    this.isPageActive = true;
    this.recreateFlowEffect();
    hilog.info(0x0000, TAG, 'galleryDay pageAppear');
    if (this.controller === null) {
      this.controller = new FlowCardGalleryController({
        setLoading: (loading: boolean) => {
          this.isLoading = loading;
        },
        applyTimeline: (payload: FlowCardGalleryTimelinePayload) => {
          this.items = payload.items;
          this.itemCount = payload.itemCount;
          this.currentIndex = payload.currentIndex;
          this.updateDateLabelFromSelection();
        },
        onNoMoreData: (direction: number) => {
          const message = direction < 0 ? '没有更早的数据了' : '没有更新的数据了';
          promptAction.openToast({ message, duration: 1200 });
        }
      });
    }
    void this.controller.initialize(this.getSelection(), { showLoading: true });
    this.breakpointSystem.register();
    window.getLastWindow(getContext(this)).then((win) => {
      this.galleryWidthVp = px2vp(win.getWindowProperties().windowRect.width);
      win.on('windowSizeChange', this.windowSizeListener);
    });
    setTimeout(() => {
      this.delay = false;
    }, 150)
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.flowEffectRemountToken += 1;
    this.controller?.dispose();
    this.breakpointSystem.unregister();
    window.getLastWindow(getContext(this)).then((win) => {
      win.off('windowSizeChange', this.windowSizeListener);
    });
  }

  private onColorModeChange(): void {
    this.recreateFlowEffect();
  }

  private onColorModeVersionChange(): void {
    this.onColorModeChange();
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

  private handleSelectionChange(): void {
    if (this.suppressSelectionChangeCount > 0) {
      this.suppressSelectionChangeCount -= 1;
      return;
    }
    this.controller?.scheduleJump(this.getSelection(), { showLoading: true });
  }

  private handleIndexChange(): void {
    const controller = this.controller;
    if (!controller) {
      return;
    }
    this.vibratorUtil.triggerHaptic('haptic.effect.sharp');
    controller.setCurrentIndex(this.currentIndex);
    this.updateDateLabelFromSelection();

    const selection = controller.getSelectionForIndex(this.currentIndex);
    if (selection) {
      this.syncSelectionSilently(selection);
      this.updateDateLabelFromSelection();
    }
  }

  private getSelection(): FlowCardGallerySelection {
    return {
      year: this.selectedYear,
      month: this.selectedMonth,
      day: this.selectedDate
    };
  }

  private updateDateLabelFromSelection(): void {
    const selection = this.getSelection();
    const dayString = `${selection.year}-${selection.month.toString().padStart(2, '0')}-${selection.day.toString().padStart(2, '0')}`;
    this.dateLabel = FlowCardGalleryController.formatDateLabel(dayjs(dayString).valueOf());
  }

  private setSelectionAndJump(selection: FlowCardGallerySelection): void {
    if (!this.controller) {
      return;
    }
    this.suppressSelectionChangeCount = 3;
    this.selectedYear = selection.year;
    this.selectedMonth = selection.month;
    this.selectedDate = selection.day;
    this.updateDateLabelFromSelection();
    this.controller.scheduleJump(selection, { showLoading: true });
  }

  private syncSelectionSilently(selection: FlowCardGallerySelection): void {
    if (
      selection.year === this.selectedYear
      && selection.month === this.selectedMonth
      && selection.day === this.selectedDate
    ) {
      return;
    }
    this.suppressSelectionChangeCount = 3;
    this.selectedYear = selection.year;
    this.selectedMonth = selection.month;
    this.selectedDate = selection.day;
  }

  private handleDayBoundary(direction: number): void {
    if (!this.controller) {
      return;
    }
    if (this.itemCount === 0) {
      const current = this.getSelection();
      const dayString = `${current.year}-${current.month.toString().padStart(2, '0')}-${current.day.toString().padStart(2, '0')}`;
      const next = dayjs(dayString).add(direction, 'day');
      this.setSelectionAndJump({
        year: next.year(),
        month: next.month() + 1,
        day: next.date()
      });
      return;
    }
    void this.controller.jumpToAdjacentDay(direction);
  }

  @Builder
  CircleIconButton(icon: Resource, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(icon)
        .fontColor([$r('app.color.text_primary')])
        .fontWeight(FontWeight.Bold)
    }
    .height(40)
    .width(40)
    .backgroundColor($r('app.color.neutral_100'))
    .onClick(() => {
      action();
    })
  }

  build(): void {
    if (canIUse('SystemCapability.UIDesign.HDSComponent.Core')) {
      HdsNavDestination() {
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

        if (this.delay) {
          Column() {
            Blank()
              .height($r('app.float.immersive_nav_top_spacer_height'))
              .width('100%')

            Column() {
              LoadingProgress()
                .width('30%')
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .layoutWeight(1)

            Blank()
              .height($r('app.float.immersive_nav_bottom_spacer_height'))
              .width('100%')
          }
          .width('100%')
          .height('100%')
        } else {
          Column() {
            Blank()
              .height($r('app.float.immersive_nav_top_spacer_height'))
              .width('100%')

            GridRow({
              columns: {
                sm: BreakpointConstants.COLUMN_SM,
                md: BreakpointConstants.COLUMN_MD,
                lg: BreakpointConstants.COLUMN_LG
              },
              breakpoints: { value: BreakpointConstants.BREAKPOINT_VALUE }
            }) {
              GridCol({
                span: {
                  sm: BreakpointConstants.SPAN_SM,
                  md: BreakpointConstants.COLUMN_MD,
                  lg: BreakpointConstants.COLUMN_LG
                },
                offset: 0
              }) {
                Stack() {
                  if (this.isLoading) {
                    Column({ space: 12 }) {
                      LoadingProgress()
                        .width(48)
                        .height(48);
                      Text('加载中...')
                        .fontSize(14)
                        .fontWeight(500)
                        .fontColor($r('app.color.text_secondary'));
                    }
                    .width('100%')
                    .height('100%')
                    .alignItems(HorizontalAlign.Center)
                    .justifyContent(FlexAlign.Center);
                  } else if (this.itemCount === 0) {
                    Column({ space: 12 }) {
                      Image($r('app.media.no_act_yet'))
                        .width(125)
                        .height(125);
                      Text($r('app.string.no_record'))
                        .fontSize(16)
                        .fontWeight(600)
                        .fontColor($r('app.color.text_disabled'));
                    }
                    .width('100%')
                    .height('100%')
                    .alignItems(HorizontalAlign.Center)
                    .justifyContent(FlexAlign.Center)
                    .padding({ left: 12, right: 12 })
                    .transition(
                      TransitionEffect.asymmetric(
                        TransitionEffect.scale({ x: 0.5, y: 0.5 })
                          .animation({ curve: curves.springMotion(), duration: 250 }),
                        undefined
                      )
                    )
                    .gesture(
                      PanGesture({ direction: PanDirection.Horizontal })
                        .onActionEnd((event: GestureEvent) => {
                          const threshold = 50;
                          if (Math.abs(event.offsetX) < threshold) {
                            hilog.info(0x0000, TAG,
                              `galleryDay emptyState swipe ignored offsetX=${event.offsetX.toFixed(1)} isLoading=${this.isLoading}`);
                            return;
                          }
                          const direction = event.offsetX > 0 ? -1 : 1;
                          hilog.info(0x0000, TAG,
                            `galleryDay emptyState swipe offsetX=${event.offsetX.toFixed(1)} dir=${direction}`);
                          this.handleDayBoundary(direction);
                        })
                    );
                  } else {
                    Column() {
                      if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM) {
                        FlowCardStackSwiper({
                          items: this.items,
                          itemCount: this.itemCount,
                          currentIndex: this.currentIndex,
                          boundaryHandler: (direction: number): void => {
                            void this.controller?.requestLoadMore(direction);
                          }
                        })
                          .width('100%')
                          .height('100%');
                      } else {
                        FlowCardCarouselWide({
                          items: this.items,
                          itemCount: this.itemCount,
                          currentIndex: this.currentIndex,
                          layout: this.getLayoutConfig(),
                          boundaryHandler: (direction: number): void => {
                            void this.controller?.requestLoadMore(direction);
                          }
                        })
                          .width('100%')
                          .height('100%');
                      }
                    }
                    .width('100%')
                    .height('100%');
                  }
                }
                .width('100%')
                .height('100%');
              }
              .height('100%')
            }
            .width('100%')
            .layoutWeight(1)

            Blank()
              .height($r('app.float.immersive_nav_bottom_spacer_height'))
              .width('100%')
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM, SafeAreaEdge.TOP])
        }
        }
        .width('100%')
        .height('100%')
      }
      .onReady(async (context: NavDestinationContext) => {
        this.pageInfos = context.pathStack;
      })
      .titleBar({
        content: {
          title: {
            mainTitle: '回顾画廊'
          }
        },
        style: {
          scrollEffectOpts: {
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.GENTLE
          }
        }
      })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .hideToolBar(true)
      .hideBackButton(false)
      .ignoreLayoutSafeArea(
        [LayoutSafeAreaType.SYSTEM],
        [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]
      )
      .expandSafeArea(
        [SafeAreaType.SYSTEM],
        [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
      )
      .backgroundColor($r('app.color.bg_main'))
      .width('100%')
      .height('100%');
    }
  }
}
