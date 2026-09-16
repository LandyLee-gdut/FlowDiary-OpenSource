import { IdeaActivity, VibratorUtil } from 'base';
import { createIdeaPoolUserGuideMockData } from '../model/IdeaPoolUserGuideMockData';
import { IdeaCardDemo } from './IdeaCardDemo';
import { curves } from '@kit.ArkUI';
import { BreakpointConstants, BreakpointSystem, BreakpointType } from 'base'
import { AddIdeaBall } from 'ideapool'

const TAG = 'IdeaPoolUserGuide';

type IdeaDemoLayerType = 'left' | 'right' | 'center' | 'back';

interface IdeaDemoStackLayerConfig {
  id: string;
  type: IdeaDemoLayerType;
  offsetY: number;
  offsetX: number;
  scale: number;
  opacity: number;
  motionScale: number;
  floatAngle: number;
  parallaxScale: number;
  floatMotionScale: number;
}

const IDEA_DEMO_STACK_LAYERS: IdeaDemoStackLayerConfig[] = [
  // 1. 左上角 (Top-Left) - 远景
  // 关键调整：大幅向上偏移 (y: -125)，让标题露出来
  {
    id: 'guide-layer-back',
    type: 'back',
    offsetY: -85,    // 原 -60 -> 现 -125 (大幅向上)
    offsetX: -85,     // 原 -55 -> 现 -85 (向左拉开)
    scale: 0.8,       // 稍微再小一点，增加纵深感
    opacity: 0.6,     // 透明度微升，因为现在遮挡少了，可以稍微清楚点
    motionScale: 0.3,
    floatAngle: -6,   // 角度减小一点，看起来不那么乱
    parallaxScale: -0.1,
    floatMotionScale: -0.05
  },

  // 2. 右上角 (Top-Right) - 中远景
  // 关键调整：向上偏移，与左上角形成错落
  {
    id: 'guide-layer-right',
    type: 'right',
    offsetY: -65,    // 原 -70 -> 现 -105
    offsetX: 85,      // 原 55 -> 现 85 (向右拉开)
    scale: 0.86,
    opacity: 0.75,
    motionScale: 0.5,
    floatAngle: 5,
    parallaxScale: 0.05,
    floatMotionScale: 0.03
  },

  // 3. 左下角 (Bottom-Left) - 中近景
  // 关键调整：向下偏移，给上层留空间
  {
    id: 'guide-layer-left',
    type: 'left',
    offsetY: 70,      // 原 60 -> 现 90
    offsetX: -85,     // 原 -75 -> 现 -85
    scale: 0.92,
    opacity: 0.9,
    motionScale: 0.7,
    floatAngle: -3,
    parallaxScale: -0.05,
    floatMotionScale: -0.02
  },

  // 4. 右下角 (Bottom-Right) - 近景焦点
  // 关键调整：作为视觉锚点，位置要稳
  {
    id: 'guide-layer-center',
    type: 'center',
    offsetY: 90,     // 原 70 -> 现 120 (大幅向下)
    offsetX: 85,      // 原 75 -> 现 85
    scale: 1,
    opacity: 1,
    motionScale: 1,
    floatAngle: 2,    // 保持微小的角度
    parallaxScale: 0.1,
    floatMotionScale: 0
  }
];
@Component
export struct IdeaPoolUserGuide {
  onContinue?: () => void;
  @Watch('onActiveStateChanged') @Prop isActive: boolean = false;
  @State ideaItems: IdeaActivity[] = [];
  @State floatOffsetY: number = 0;
  @State floatOffsetX: number = 0;
  @StorageLink('userGuideSheetVisible') @Watch('onGuideSheetVisibilityChanged') userGuideSheetVisible: boolean = false;
  @State private isComponentVisible: boolean = false;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private isFloatRunning: boolean = false;
  private readonly floatAmplitudeY: number = 6;
  private readonly floatAmplitudeX: number = 4;
  private readonly floatFrameDuration: number = 2800;
  private readonly cardHeight: number = 150;
  private readonly cardStackHeight: number = 350;
  private readonly cardStackWidth: string = '90%';
  private readonly sectionSpacing: number = 16;
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;


  aboutToAppear(): void {
    this.breakpointSystem.register();
    this.ideaItems = createIdeaPoolUserGuideMockData();
    this.reconcileFloatingState();
  }

  aboutToDisappear(): void {
    this.breakpointSystem.unregister()
    this.stopFloating();
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
    Column({ space: this.sectionSpacing }) {
      Column({ space: 8 }) {
        Text('「灵感池」页面')
          .fontSize(30)
          .fontColor($r('app.color.warning'))
          .fontWeight(600)
          .transition(TransitionEffect.translate({ y: 300 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1500 }))
        Text('记录你的灵感迸发')
          .fontColor($r('app.color.text_tertiary'))
          .fontSize(14)
          .transition(TransitionEffect.translate({ y: 400 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1500 }))
      }
      .height(50)
      .offset({ y: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 20 })
      .alignItems(HorizontalAlign.Center)

      Column({ space: 20 }) {
        Stack() {
          ForEach(
            IDEA_DEMO_STACK_LAYERS,
            (layer: IdeaDemoStackLayerConfig, index: number) => {
              Column() {
                if (index < this.ideaItems.length) {
                  IdeaCardDemo({ idea: this.ideaItems[index] })
                    .height(this.cardHeight)
                    .width(this.cardHeight)
                }
              }
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.3, y: 0.3 })).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 100 * index }))
              .translate({
                x: layer.offsetX + this.floatOffsetX * layer.motionScale * layer.parallaxScale,
                y: layer.offsetY + this.floatOffsetY * layer.motionScale
              })
              .scale({ x: layer.scale, y: layer.scale })
              .opacity(layer.opacity)
              .rotate({ x: 0, y: 0, z: 1, angle: layer.floatAngle + this.floatOffsetY * layer.floatMotionScale });
            },
            (layer: IdeaDemoStackLayerConfig) => layer.id
          );
        }
      }
      .justifyContent(FlexAlign.Center)
      .width(this.cardStackWidth)
      .height(this.cardStackHeight)
      .margin({ bottom: 30 })

      Column({ space: 8 }) {
        Text('轻触灵感球，添加灵感！')
          .transition(TransitionEffect.translate({ y: 300 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 500 }))
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .fontWeight(500);

        // 模拟添加灵感按钮
        AddIdeaBall()
          .onClick(() => {
            this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
          })
          .margin({
            top: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 10 : 5,
            bottom: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 15 : 5,
          })
          .transition(TransitionEffect.translate({ y: 400 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 600 }))
          .width(50)
          .height(50)

      }
      .height(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 65 : 55)
      .alignItems(HorizontalAlign.Center)
      .margin({
        bottom: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 20,
      })

      Button('继续')
        .transition(TransitionEffect.translate({ y: 500 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 700 }))
        .width('60%')
        .backgroundColor($r('app.color.warning'))
        .fontColor($r('app.color.neutral_100'))
        .padding({ top: 8, right: 24, bottom: 8, left: 24 })
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
    .onVisibleAreaChange([0, 1], (_isExpanding: boolean, currentRatio: number) => {
      const nextVisible = currentRatio > 0;
      if (this.isComponentVisible === nextVisible) {
        return;
      }
      this.isComponentVisible = nextVisible;
      this.reconcileFloatingState();
    })
  }

  private startFloating(): void {
    if (this.isFloatRunning) {
      return;
    }
    this.isFloatRunning = true;
    this.scheduleNextFloat(this.floatAmplitudeY, this.floatAmplitudeX);
  }

  private stopFloating(): void {
    if (!this.isFloatRunning && this.floatOffsetY === 0 && this.floatOffsetX === 0) {
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
        this.floatOffsetX = 0;
      });
      return;
    }
    this.floatOffsetY = 0;
    this.floatOffsetX = 0;
  }

  private scheduleNextFloat(targetOffsetY: number, targetOffsetX: number): void {
    if (!this.isFloatRunning || !this.shouldRunFloating()) return;
    const uiContext = this.getUIContext();
    if (!uiContext) { 
      this.isFloatRunning = false; 
      return; 
    }

    uiContext.animateTo({
      duration: this.floatFrameDuration,
      curve: Curve.EaseInOut,
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        if (!this.isFloatRunning || !this.shouldRunFloating()) return;
        const nextY = targetOffsetY > 0 ? -targetOffsetY : Math.abs(targetOffsetY);
        const nextX = targetOffsetX > 0 ? -targetOffsetX : Math.abs(targetOffsetX);
        this.scheduleNextFloat(nextY, nextX);
      }
    }, () => {
      if (!this.isFloatRunning || !this.shouldRunFloating()) return;
      this.floatOffsetY = targetOffsetY;
      this.floatOffsetX = targetOffsetX;
    });
  }
}
