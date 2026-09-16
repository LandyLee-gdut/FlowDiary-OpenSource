import { UIContext, curves, componentUtils, NodeController, BuilderNode, FrameNode } from '@kit.ArkUI';
import { DayTimeline } from './DayTimeline';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VibratorUtil, buildPointLightEffect, ColorModeUtil, COLOR_MODE_STORAGE_KEY } from 'base';
import { hdsEffect } from '@kit.UIDesignKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ReflectVisualEffectConstants } from '../constants/ReflectVisualEffectConstants';

const TIMELINE_CARD_BASE_HEIGHT: number = 125;
const TAG = 'TimeLineTrans';
const ANIMATION_CURVE = curves.springMotion(0.45, 0.75);
const ANIMATION_DURATION = 150;
const BACKGROUND_ANIMATION_DURATION = 100;

class RectInfo {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  width: number = 0;
  height: number = 0;
}

class TimelineNodeData {
  expanded: boolean = false;
}

@Builder
function TimelineNodeBuilder(data: TimelineNodeData) {
  DayTimeline({ expanded: data.expanded })
    .width('100%')
    .height('100%')
}

class __InternalValue__ {
  flag: boolean = false;
}

export class TimelineNode extends NodeController {
  private node: BuilderNode<TimelineNodeData[]> | null = null;
  private isRemove: __InternalValue__ = new __InternalValue__();
  private data: TimelineNodeData | null = null;
  private uiContext: UIContext | null = null;
  private callback: Function | undefined = undefined;

  makeNode(uiContext: UIContext): FrameNode | null {
    if (this.isRemove.flag === true) {
      return null;
    }
    if (this.node !== null) {
      return this.node.getFrameNode();
    }
    return null;
  }

  init(uiContext: UIContext, expanded: boolean): void {
    if (this.node !== null) {
      return;
    }
    this.uiContext = uiContext;
    this.node = new BuilderNode(uiContext);
    this.data = { expanded: expanded };
    this.node.build(wrapBuilder<TimelineNodeData[]>(TimelineNodeBuilder), this.data);
  }

  update(expanded: boolean): void {
    if (this.node !== null) {
      this.data = { expanded: expanded };
      this.node.update(this.data);
    }
  }

  onRemove(): void {
    hilog.info(0x0000, TAG, 'TimeLineTrans: TimelineNode onRemove');
    this.isRemove.flag = true;
    this.rebuild();
    this.isRemove.flag = false;
  }

  setCallback(callback: Function | undefined): void {
    this.callback = callback;
  }

  callCallback(): void {
    if (this.callback !== undefined) {
      this.callback();
    }
  }

  refreshNode(): void {
    if (this.node !== null && this.data !== null && this.uiContext !== null) {
      hilog.info(0x0000, TAG, 'TimeLineTrans: TimelineNode refreshNode');
      this.isRemove.flag = true;
      this.rebuild();
      this.isRemove.flag = false;

      this.node.dispose();
      this.node = new BuilderNode(this.uiContext);
      this.node.build(wrapBuilder<TimelineNodeData[]>(TimelineNodeBuilder), this.data);
      this.rebuild();
    }
  }
}

let gTimelineNode: TimelineNode | undefined = undefined;

export const createTimelineNode = (uiContext: UIContext, expanded: boolean): TimelineNode | undefined => {
  if (gTimelineNode !== undefined) {
    hilog.info(0x0000, TAG, 'TimeLineTrans: createTimelineNode reused');
    return gTimelineNode;
  }
  const node = new TimelineNode();
  node.init(uiContext, expanded);
  gTimelineNode = node;
  hilog.info(0x0000, TAG, 'TimeLineTrans: createTimelineNode created');
  return node;
}

export const getTimelineNode = (): TimelineNode | undefined => {
  return gTimelineNode;
}

export const refreshTimelineNode = (): void => {
  if (gTimelineNode !== undefined) {
    gTimelineNode.refreshNode();
  }
}

@Observed
export class TimelineExpandAnimationProperties {
  public isExpandPageShow: boolean = false;
  public isEnabled: boolean = true;
  public translateX: number = 0;
  public translateY: number = 0;
  public positionX: number = 0;
  public positionY: number = 0;
  public initialWidth: number = 0;
  public initialHeight: number = 0;
  public changedSize: boolean = false;
  public backgroundOpacity: number = 0;
  public expandedWidth: number = 0;
  public expandedHeight: number = 0;

  private calculatedTranslateX: number = 0;
  private calculatedTranslateY: number = 0;
  private readonly expandedWidthPercent: number = 0.92;
  private readonly expandedHeightPercent: number = 0.76;
  private readonly expandedMinHeight: number = 320;
  private readonly expandedVerticalPadding: number = 24;
  private readonly rootKey: string = 'reflectTimelineRootStack';
  private readonly cardKey: string = 'timelineCard';
  private uiContext: UIContext;

  constructor(uiContext: UIContext) {
    this.uiContext = uiContext;
  }

  public expandAnimation(): void {
    if (this.isExpandPageShow) {
      hilog.info(0x0000, TAG, 'TimeLineTrans: expandAnimation ignored, already expanded');
      return;
    }
    if (!this.calculateData(this.cardKey)) {
      hilog.warn(0x0000, TAG, 'expandAnimation aborted due to invalid rects');
      return;
    }
    hilog.info(0x0000, TAG, `TimeLineTrans: expandAnimation start pos=(${this.positionX},${this.positionY}) size=(${this.initialWidth},${this.initialHeight}) translate=(${this.calculatedTranslateX},${this.calculatedTranslateY})`);
    this.isExpandPageShow = true;

    this.uiContext?.animateTo({
      curve: ANIMATION_CURVE,
      duration: ANIMATION_DURATION
    }, () => {
      this.translateX = this.calculatedTranslateX;
      this.translateY = this.calculatedTranslateY;
      this.changedSize = true;
    });

    this.uiContext?.animateTo({
      curve: ANIMATION_CURVE,
      duration: BACKGROUND_ANIMATION_DURATION
    }, () => {
      this.backgroundOpacity = 1;
    });
  }

  public collapseAnimation(onFinish: () => void): void {
    hilog.info(0x0000, TAG, 'TimeLineTrans: collapseAnimation start');
    this.uiContext?.animateTo({
      curve: ANIMATION_CURVE,
      duration: BACKGROUND_ANIMATION_DURATION
    }, () => {
      this.backgroundOpacity = 0;
    });

    this.uiContext?.animateTo({
      curve: ANIMATION_CURVE,
      duration: ANIMATION_DURATION,
      onFinish: () => {
        hilog.info(0x0000, TAG, 'TimeLineTrans: collapseAnimation onFinish');
        onFinish();
        this.translateX = 0;
        this.translateY = 0;
        this.isExpandPageShow = false;
        this.isEnabled = true;
      }
    }, () => {
      // Align with Idea card: allow interrupt by animating from current translate back to 0.
      this.isEnabled = false;
      this.translateX = 0;
      this.translateY = 0;
      this.changedSize = false;
    });
  }

  private calculateData(cardKey: string): boolean {
    const clickedInfo = this.getRectInfoById(this.uiContext, cardKey);
    const rootInfo = this.getRectInfoById(this.uiContext, this.rootKey);
    if (clickedInfo === undefined || rootInfo === undefined) {
      return false;
    }

    this.positionX = this.uiContext.px2vp(clickedInfo.left - rootInfo.left);
    this.positionY = this.uiContext.px2vp(clickedInfo.top - rootInfo.top);
    this.initialWidth = this.uiContext.px2vp(clickedInfo.width);
    this.initialHeight = this.uiContext.px2vp(clickedInfo.height);

    const rootWidth = this.uiContext.px2vp(rootInfo.width);
    const rootHeight = this.uiContext.px2vp(rootInfo.height);

    const expandedWidth = rootWidth * this.expandedWidthPercent;
    const maxExpandedHeight = Math.max(rootHeight - this.expandedVerticalPadding * 2, 0);
    let expandedHeight = rootHeight * this.expandedHeightPercent;
    expandedHeight = Math.min(expandedHeight, maxExpandedHeight);
    expandedHeight = Math.max(expandedHeight, this.expandedMinHeight);
    this.expandedWidth = expandedWidth;
    this.expandedHeight = expandedHeight;
    
    const targetX = (rootWidth - expandedWidth) / 2;
    const targetY = (rootHeight - expandedHeight) / 2;

    this.calculatedTranslateX = targetX - this.positionX;
    this.calculatedTranslateY = targetY - this.positionY;
    hilog.info(0x0000, TAG, `TimeLineTrans: calculateData cardPos=(${this.positionX},${this.positionY}) rootSize=(${rootWidth},${rootHeight}) targetPos=(${targetX},${targetY}) translate=(${this.calculatedTranslateX},${this.calculatedTranslateY})`);
    return true;
  }

  private getRectInfoById(context: UIContext, id: string): RectInfo | undefined {
    const componentInfo: componentUtils.ComponentInfo = context.getComponentUtils().getRectangleById(id);
    if (!componentInfo) {
      hilog.error(0x0000, TAG, `getRectangleById failed for id=${id}`);
      return undefined;
    }

    const rstRect: RectInfo = new RectInfo();
    const widthScaleGap = componentInfo.size.width * (1 - componentInfo.scale.x) / 2;
    const heightScaleGap = componentInfo.size.height * (1 - componentInfo.scale.y) / 2;
    rstRect.left = componentInfo.translate.x + componentInfo.windowOffset.x + widthScaleGap;
    rstRect.top = componentInfo.translate.y + componentInfo.windowOffset.y + heightScaleGap;
    rstRect.right = componentInfo.translate.x + componentInfo.windowOffset.x + componentInfo.size.width - widthScaleGap;
    rstRect.bottom = componentInfo.translate.y + componentInfo.windowOffset.y + componentInfo.size.height - heightScaleGap;
    rstRect.width = rstRect.right - rstRect.left;
    rstRect.height = rstRect.bottom - rstRect.top;
    if (rstRect.width <= 0 || rstRect.height <= 0) {
      hilog.warn(0x0000, TAG, `invalid rect size for id=${id}, width=${rstRect.width}, height=${rstRect.height}`);
      return undefined;
    }
    return rstRect;
  }
}

@Component
export struct TimelineCard {
  @ObjectLink animationProperties: TimelineExpandAnimationProperties;
  private readonly cardKey: string = 'timelineCard';
  @State private nodeController: TimelineNode | undefined = undefined;
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State private isDarkTheme: boolean = false;
  @State private isTimelinePressed: boolean = false;

  aboutToAppear(): void {
    this.syncColorModeState();
    if (this.nodeController !== undefined) {
      return;
    }
    const uiContext = this.getUIContext();
    if (uiContext) {
      this.nodeController = createTimelineNode(uiContext, false);
      if (this.nodeController !== undefined) {
        this.nodeController.setCallback(this.resetNode.bind(this));
      }
      hilog.info(0x0000, TAG, `TimeLineTrans: TimelineCard aboutToAppear nodeReady=${this.nodeController !== undefined}`);
    }
  }

  private onColorModeChange(): void {
    this.syncColorModeState();
  }

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private handleLongPress(): void {
    if (this.animationProperties.isExpandPageShow) {
      return;
    }
    hilog.info(0x0000, TAG, 'TimeLineTrans: TimelineCard longPress expand');
    this.isTimelinePressed = false;
    void VibratorUtil.getInstance().triggerHaptic('haptic.effect.soft', 'touch');
    if (this.nodeController !== undefined) {
      this.nodeController.onRemove();
    }
    this.animationProperties.expandAnimation();
  }

  private handleTimelineTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.isTimelinePressed = true;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isTimelinePressed = false;
    }
  }

  private resetNode(): void {
    this.nodeController = getTimelineNode();
    if (this.nodeController !== undefined) {
      this.nodeController.update(false);
    }
    hilog.info(0x0000, TAG, 'TimeLineTrans: TimelineCard resetNode');
  }

  build() {
    Stack() {
      NodeContainer(this.nodeController)
    }
    .width('100%')
    .height(TIMELINE_CARD_BASE_HEIGHT)
    .key(this.cardKey)
    .visualEffect(buildPointLightEffect({
      preset: 'cardTouch',
      color: $r('app.color.immersive_glow_primary'),
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      isActive: this.isTimelinePressed,
      isDarkTheme: this.isDarkTheme
    }))
    .onTouch((event: TouchEvent) => {
      this.handleTimelineTouch(event);
    })
    .gesture(
      LongPressGesture({
        repeat: false,
        duration: ReflectVisualEffectConstants.TIMELINE_LONG_PRESS_DURATION_MS
      })
        .onAction(() => {
          this.handleLongPress();
        })
    )
  }
}

@Component
export struct TimelineExpandPage {
  @ObjectLink animationProperties: TimelineExpandAnimationProperties;
  @State private nodeController: TimelineNode | undefined = undefined;

  aboutToAppear(): void {
    this.nodeController = getTimelineNode();
    if (this.nodeController !== undefined) {
      this.nodeController.update(true);
    }
    hilog.info(0x0000, TAG, `TimeLineTrans: TimelineExpandPage aboutToAppear nodeReady=${this.nodeController !== undefined}`);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundBlurStyle(this.animationProperties.backgroundOpacity > 0 ? BlurStyle.BACKGROUND_THIN : BlurStyle.NONE)
        .opacity(this.animationProperties.backgroundOpacity)
        .animation({ curve: ANIMATION_CURVE, duration: BACKGROUND_ANIMATION_DURATION })
        .onClick(() => this.collapse())

      // Animated expanding background card containing both timeline and chart.
      Stack({ alignContent: Alignment.Center}) {
        NodeContainer(this.nodeController)
      }
      .width(this.animationProperties.changedSize
        ? (this.animationProperties.expandedWidth > 0 ? this.animationProperties.expandedWidth : '92%')
        : (this.animationProperties.initialWidth > 0 ? this.animationProperties.initialWidth : '100%'))
      .height(this.animationProperties.changedSize
        ? (this.animationProperties.expandedHeight > 0 ? this.animationProperties.expandedHeight : '76%')
        : (this.animationProperties.initialHeight > 0 ? this.animationProperties.initialHeight : TIMELINE_CARD_BASE_HEIGHT))
      .translate({ x: this.animationProperties.translateX, y: this.animationProperties.translateY })
      .position({ x: this.animationProperties.positionX, y: this.animationProperties.positionY })
      .clip(false)
      .onClick(() => this.collapse())
    }
    .width('100%')
    .height('100%')
    .clip(false)
  }

  private collapse(): void {
    if (!this.animationProperties.isExpandPageShow) {
      return;
    }
    hilog.info(0x0000, TAG, 'TimeLineTrans: TimelineExpandPage collapse click');
    if (this.nodeController !== undefined) {
      this.nodeController.update(false);
    }
    this.animationProperties.collapseAnimation(() => {
      if (this.nodeController !== undefined) {
        hilog.info(0x0000, TAG, 'TimeLineTrans: TimelineExpandPage collapse onFinish callback');
        // Follow IdeaCard pattern: callback first to trigger base rebuild, then remove.
        this.nodeController.callCallback();
        this.nodeController.onRemove();
      }
    });
  }
}
