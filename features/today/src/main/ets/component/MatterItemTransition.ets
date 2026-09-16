/**
 * MatterItem 展开动画过渡组件
 * 实现一镜到底共享元素动效
 */
import { UIContext, curves, componentUtils, NodeController, BuilderNode, FrameNode } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { VibratorUtil, MatterItemModel, BreakpointConstants, AppShadows, BreakpointType } from 'base';
import { MatterItem } from './MatterItem';

const TAG = 'MatterItemTrans';
const ANIMATION_CURVE = curves.springMotion(0.45, 0.75);
const ANIMATION_DURATION = 150;
const BACKGROUND_ANIMATION_DURATION = 100;

class __InternalValue__ {
  flag: boolean = false;
}

interface MatterItemNodeData {
  item: MatterItemModel;
  expanded: boolean;
  isDarkTheme: boolean;
}

@Builder
function MatterItemNodeBuilder(data: MatterItemNodeData) {
  MatterItem({
    item: data.item,
    expanded: data.expanded,
    isDarkThemeProp: data.isDarkTheme
  })
    .width('100%')
    .height('100%')
}

/**
 * 可跨容器迁移的 MatterItem 节点（共享元素一镜到底）
 */
export class MatterItemNode extends NodeController {
  private node: BuilderNode<MatterItemNodeData[]> | null = null;
  private isRemove: __InternalValue__ = new __InternalValue__();
  private data: MatterItemNodeData | null = null;
  private uiContext: UIContext | null = null;
  private callback: Function | undefined = undefined;
  private isDarkTheme: boolean = false;

  makeNode(_: UIContext): FrameNode | null {
    if (this.isRemove.flag === true) {
      return null;
    }
    return this.node?.getFrameNode() ?? null;
  }

  init(
    uiContext: UIContext,
    item: MatterItemModel,
    expanded: boolean,
    isDarkTheme: boolean
  ): void {
    if (this.node !== null) {
      return;
    }
    this.uiContext = uiContext;
    this.isDarkTheme = isDarkTheme;
    this.node = new BuilderNode(uiContext);
    this.data = { item, expanded, isDarkTheme: this.isDarkTheme };
    this.node.build(wrapBuilder<MatterItemNodeData[]>(MatterItemNodeBuilder), this.data);
  }

  update(
    item: MatterItemModel,
    expanded: boolean,
    isDarkTheme?: boolean
  ): void {
    if (this.node !== null) {
      if (isDarkTheme !== undefined) {
        this.isDarkTheme = isDarkTheme;
      }
      this.data = { item, expanded, isDarkTheme: this.isDarkTheme };
      this.node.update(this.data);
    }
  }

  setCallback(callback: Function | undefined): void {
    this.callback = callback;
  }

  callCallback(): void {
    if (this.callback !== undefined) {
      this.callback();
    }
  }

  onRemove(): void {
    this.isRemove.flag = true;
    this.rebuild();
    this.isRemove.flag = false;
  }

  /**
   * 刷新节点UI
   * 用于响应数据变化或配置变化（如深色模式切换）
   * 需要销毁旧节点并创建新节点，以使资源引用重新解析
   */
  refreshNode(isDarkTheme?: boolean): void {
    if (this.node !== null && this.data !== null && this.uiContext !== null) {
      if (isDarkTheme !== undefined) {
        this.isDarkTheme = isDarkTheme;
      }
      const rebuiltData: MatterItemNodeData = {
        item: this.data.item,
        expanded: this.data.expanded,
        isDarkTheme: this.isDarkTheme
      };
      // 先让旧节点下树
      this.isRemove.flag = true;
      this.rebuild();
      this.isRemove.flag = false;

      // 销毁旧的 BuilderNode
      this.node.dispose();

      // 创建新的 BuilderNode，使 $r(...) 资源引用重新解析
      this.node = new BuilderNode(this.uiContext);
      this.data = rebuiltData;
      this.node.build(wrapBuilder<MatterItemNodeData[]>(MatterItemNodeBuilder), this.data);

      // 触发 NodeController 重建以显示新节点
      this.rebuild();
    }
  }
}

let gMatterItemNodeMap: Map<string, MatterItemNode> = new Map();

export const createMatterItemNode = (
  uiContext: UIContext,
  item: MatterItemModel,
  expanded: boolean,
  isDarkTheme: boolean
): MatterItemNode => {
  const existing = gMatterItemNodeMap.get(item.id);
  if (existing) {
    existing.update(item, expanded, isDarkTheme);
    return existing;
  }

  const node = new MatterItemNode();
  node.init(uiContext, item, expanded, isDarkTheme);
  gMatterItemNodeMap.set(item.id, node);
  return node;
}

export const getMatterItemNode = (itemId: string): MatterItemNode | undefined => {
  return gMatterItemNodeMap.get(itemId);
}

export const refreshAllMatterItemNodes = (isDarkTheme?: boolean): void => {
  gMatterItemNodeMap.forEach((node, itemId) => {
    hilog.info(0x0000, TAG, `refreshAllMatterItemNodes refreshing node ${itemId} with isDarkTheme=${isDarkTheme}`);
    node.refreshNode(isDarkTheme);
  });
}

/**
 * 矩形信息类
 */
class RectInfo {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  width: number = 0;
  height: number = 0;
}

/**
 * 展开动画属性类
 */
@Observed
export class MatterItemExpandAnimationProperties {
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
  public currentExpandingItemId: string = '';
  public currentExpandingItem: MatterItemModel | null = null;

  private calculatedTranslateX: number = 0;
  private calculatedTranslateY: number = 0;
  private readonly expandedWidthPercent = new BreakpointType<number>({ sm: 0.92, md: 0.70, lg: 0.45 });
  private readonly expandedHeightPercent = new BreakpointType<number>({ sm: 0.76, md: 0.76, lg: 0.76 });
  private readonly expandedMaxWidth = new BreakpointType<number>({ sm: 10000, md: 520, lg: 480 });
  private readonly expandedMinHeight: number = 420;
  private readonly expandedVerticalPadding: number = 24;
  private readonly rootKey: string = 'todayRootStack';
  private uiContext: UIContext;

  constructor(uiContext: UIContext) {
    this.uiContext = uiContext;
  }

  public expandAnimation(cardKey: string, item: MatterItemModel): void {
    if (this.isExpandPageShow) {
      hilog.info(0x0000, TAG, 'expandAnimation ignored, already expanded');
      return;
    }
    if (!this.calculateData(cardKey)) {
      hilog.warn(0x0000, TAG, 'expandAnimation aborted due to invalid rects');
      return;
    }

    this.currentExpandingItemId = item.id;
    this.currentExpandingItem = item;

    hilog.info(0x0000, TAG,
      `expandAnimation start id=${item.id} pos=(${this.positionX},${this.positionY}) size=(${this.initialWidth},${this.initialHeight}) translate=(${this.calculatedTranslateX},${this.calculatedTranslateY})`);

    this.isExpandPageShow = true;

    // 背景动画
    this.uiContext?.animateTo({
      curve: ANIMATION_CURVE,
      duration: BACKGROUND_ANIMATION_DURATION
    }, () => {
      this.backgroundOpacity = 1;
    });

    // 卡片展开动画
    this.uiContext?.animateTo({
      curve: ANIMATION_CURVE,
      duration: ANIMATION_DURATION
    }, () => {
      this.translateX = this.calculatedTranslateX;
      this.translateY = this.calculatedTranslateY;
      this.changedSize = true;
    });
  }

  public collapseAnimation(onFinish: () => void): void {
    hilog.info(0x0000, TAG, 'collapseAnimation start');
    this.refreshCollapseTargetPosition();

    // 背景动画
    this.uiContext?.animateTo({
      curve: ANIMATION_CURVE,
      duration: BACKGROUND_ANIMATION_DURATION
    }, () => {
      this.backgroundOpacity = 0;
    });

    // 卡片收起动画
    this.uiContext?.animateTo({
      curve: ANIMATION_CURVE,
      duration: ANIMATION_DURATION,
      onFinish: () => {
        hilog.info(0x0000, TAG, 'collapseAnimation onFinish');
        // Follow Stack-transition spec: migrate back first, then reset animation state.
        onFinish();
        this.translateX = 0;
        this.translateY = 0;
        this.changedSize = false;
        this.isExpandPageShow = false;
        this.isEnabled = true;
        this.currentExpandingItemId = '';
        this.currentExpandingItem = null;
      }
    }, () => {
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

    const bp = AppStorage.get<string>(BreakpointConstants.CURRENT_BREAKPOINT) ?? BreakpointConstants.BREAKPOINT_SM;

    let expandedWidth = rootWidth * this.expandedWidthPercent.getValue(bp);
    expandedWidth = Math.min(expandedWidth, this.expandedMaxWidth.getValue(bp));

    const maxExpandedHeight = Math.max(rootHeight - this.expandedVerticalPadding * 2, 0);
    let expandedHeight = rootHeight * this.expandedHeightPercent.getValue(bp);
    expandedHeight = Math.min(expandedHeight, maxExpandedHeight);
    expandedHeight = Math.max(expandedHeight, this.expandedMinHeight);
    this.expandedWidth = expandedWidth;
    this.expandedHeight = expandedHeight;

    const targetX = (rootWidth - expandedWidth) / 2;
    const targetY = (rootHeight - expandedHeight) / 2;

    this.calculatedTranslateX = targetX - this.positionX;
    this.calculatedTranslateY = targetY - this.positionY;

    hilog.info(0x0000, TAG,
      `calculateData cardPos=(${this.positionX},${this.positionY}) rootSize=(${rootWidth},${rootHeight}) targetPos=(${targetX},${targetY}) translate=(${this.calculatedTranslateX},${this.calculatedTranslateY})`);
    return true;
  }

  // 重新测量折叠态目标位置，防止展开期间布局变化导致回位漂移
  private refreshCollapseTargetPosition(): void {
    if (!this.currentExpandingItemId) {
      return;
    }
    const currentAbsX = this.positionX + this.translateX;
    const currentAbsY = this.positionY + this.translateY;
    if (!this.calculateData(getMatterItemCardKey(this.currentExpandingItemId))) {
      return;
    }
    // 保持当前视觉位置不跳变，再将动画目标指向最新位置
    this.translateX = currentAbsX - this.positionX;
    this.translateY = currentAbsY - this.positionY;
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

  /**
   * 触发展开动画的入口方法
   * @param cardKey 卡片的唯一标识键
   * @param item 要展开的 MatterItemModel
   */
  public triggerExpand(cardKey: string, item: MatterItemModel): void {
    void VibratorUtil.getInstance().triggerHaptic('haptic.effect.soft', 'touch');
    this.expandAnimation(cardKey, item);
  }

  /**
   * 触发收起动画
   */
  public triggerCollapse(onFinish: () => void): void {
    void VibratorUtil.getInstance().triggerHaptic('haptic.effect.soft', 'touch');
    this.collapseAnimation(onFinish);
  }
}

/**
 * MatterItem 展开页面组件
 * 覆盖层方式实现展开动效
 */
@Component
export struct MatterItemExpandPage {
  @ObjectLink animationProperties: MatterItemExpandAnimationProperties;
  @StorageProp(BreakpointConstants.CURRENT_BREAKPOINT) currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @StorageLink('isDarkTheme') @Watch('onThemeChanged') isDarkTheme: boolean = false;
  @State private nodeController: MatterItemNode | undefined = undefined;
  @State panOffsetX: number = 0;
  @State panOffsetY: number = 0;
  @State panPositionX: number = 0;
  @State panPositionY: number = 0;

  aboutToAppear(): void {
    const itemId = this.animationProperties.currentExpandingItemId;
    this.nodeController = itemId ? getMatterItemNode(itemId) : undefined;
    if (this.nodeController !== undefined && this.animationProperties.currentExpandingItem !== null) {
      this.nodeController.update(this.animationProperties.currentExpandingItem, true, this.isDarkTheme);
    }
    hilog.info(0x0000, TAG, `MatterItemExpandPage aboutToAppear nodeReady=${this.nodeController !== undefined} itemId=${itemId}`);
  }

  /**
   * 响应深色模式变化
   * 重新从 Map 获取 nodeController（因为 refreshNode 可能重建了节点）
   * 然后更新节点数据并刷新
   */
  private onThemeChanged(): void {
    const itemId = this.animationProperties.currentExpandingItemId;
    if (!itemId) {
      return;
    }
    hilog.info(0x0000, TAG, `MatterItemExpandPage onThemeChanged isDarkTheme=${this.isDarkTheme} itemId=${itemId}`);
    // 重新从 Map 获取最新的 nodeController 引用
    this.nodeController = getMatterItemNode(itemId);
    if (this.nodeController !== undefined && this.animationProperties.currentExpandingItem !== null) {
      this.nodeController.update(this.animationProperties.currentExpandingItem, true, this.isDarkTheme);
      this.nodeController.refreshNode(this.isDarkTheme);
    }
  }
  private panOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.Up | PanDirection.Down });


  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 背景模糊遮罩层 - 全屏可点击关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundBlurStyle(this.animationProperties.backgroundOpacity > 0 ? BlurStyle.BACKGROUND_THIN : BlurStyle.NONE)
        .onClick(() => {
          hilog.info(0x0000, TAG, 'Background clicked, triggering collapse');
          this.collapse();
        })

      // 动画展开的卡片容器
      if (this.nodeController !== undefined && this.animationProperties.currentExpandingItem !== null) {
        Stack({ alignContent: Alignment.TopEnd }) {
          NodeContainer(this.nodeController)
            .width('100%')
            .height('100%')

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontWeight(500)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(40)
          .height(40)
          .margin({ top: 20, right: 12 })
          .backgroundColor($r('app.color.neutral_100'))
          .shadow(AppShadows.CARD_RESTING)
          .onClick(() => {
            hilog.info(0x0000, TAG, 'Close button clicked');
            this.collapse();
          })
          .visibility(this.animationProperties.changedSize ? Visibility.Visible : Visibility.Hidden)
        }
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
        .width(this.animationProperties.changedSize
          ? (this.animationProperties.expandedWidth > 0 ? this.animationProperties.expandedWidth :
          new BreakpointType<string>({ sm: '92%', md: '70%', lg: '45%' }).getValue(this.currentBreakpoint))
          : (this.animationProperties.initialWidth > 0 ? this.animationProperties.initialWidth : '100%'))
        .height(this.animationProperties.changedSize
          ? (this.animationProperties.expandedHeight > 0 ? this.animationProperties.expandedHeight :
          new BreakpointType<string>({ sm: '76%', md: '76%', lg: '76%' }).getValue(this.currentBreakpoint))
          : (this.animationProperties.initialHeight > 0 ? this.animationProperties.initialHeight : 100))
        .translate({ x: this.animationProperties.translateX, y: this.animationProperties.translateY })
        .position({ x: this.animationProperties.positionX, y: this.animationProperties.positionY })
        .clip(false)
        // 兜底吸收点击，避免点击穿透触发背景关闭（同时不影响子组件交互）
        .onClick(() => {})
      }

    }
    .width('100%')
    .height('100%')
    .clip(false)
  }

  private collapse(): void {
    if (!this.animationProperties.isExpandPageShow) {
      hilog.info(0x0000, TAG, `collapse ignored: isExpandPageShow=${this.animationProperties.isExpandPageShow}`);
      return;
    }
    hilog.info(0x0000, TAG, 'MatterItemExpandPage collapse triggered');
    if (this.nodeController !== undefined && this.animationProperties.currentExpandingItem !== null) {
      this.nodeController.update(this.animationProperties.currentExpandingItem, false, this.isDarkTheme);
    }
    this.animationProperties.triggerCollapse(() => {
      if (this.nodeController !== undefined) {
        // Follow stack-transition guide: callback first to rebind list node, then remove from overlay.
        this.nodeController.callCallback();
        this.nodeController.onRemove();
      }
    });
  }
}

/**
 * 获取卡片唯一标识键
 */
export function getMatterItemCardKey(itemId: string): string {
  return `matterItemCard_${itemId}`;
}

/**
 * 折叠态卡片容器（NodeContainer + 长按触发展开）
 */
@Component
export struct MatterItemCard {
  @Watch('onItemLinkChanged') @ObjectLink item: MatterItemModel;
  @ObjectLink animationProperties: MatterItemExpandAnimationProperties;
  @Prop enableExpand: boolean = true;  // 是否允许长按展开，默认为 true
  @Prop @Watch('onThemeChange') isDarkTheme: boolean = false;
  @State private nodeController: MatterItemNode | undefined = undefined;

  aboutToAppear(): void {
    this.ensureNode(false);
  }

  private ensureNode(expanded: boolean): void {
    const uiContext = this.getUIContext();
    if (!uiContext) {
      return;
    }
    this.nodeController = createMatterItemNode(uiContext, this.item, expanded, this.isDarkTheme);
    this.nodeController?.setCallback(this.resetNode.bind(this));
  }

  private onItemLinkChanged(): void {
    const shouldBeExpanded = this.animationProperties.isExpandPageShow &&
      this.animationProperties.currentExpandingItemId === this.item.id;
    if (shouldBeExpanded) {
      this.animationProperties.currentExpandingItem = this.item;
    }
    if (this.nodeController === undefined) {
      this.ensureNode(shouldBeExpanded);
      return;
    }
    this.nodeController.update(this.item, shouldBeExpanded, this.isDarkTheme);
  }

  /**
   * 响应深色模式变化
   * 更新节点数据并刷新 UI
   */
  private onThemeChange(): void {
    hilog.info(0x0000, TAG, `MatterItemCard onThemeChange isDarkTheme=${this.isDarkTheme} itemId=${this.item.id}`);
    if (this.nodeController !== undefined) {
      const shouldBeExpanded = this.animationProperties.isExpandPageShow &&
        this.animationProperties.currentExpandingItemId === this.item.id;
      this.nodeController.update(this.item, shouldBeExpanded, this.isDarkTheme);
      this.nodeController.refreshNode(this.isDarkTheme);
    }
  }

  private resetNode(): void {
    this.nodeController = getMatterItemNode(this.item.id);
    if (this.nodeController !== undefined) {
      this.nodeController.update(this.item, false, this.isDarkTheme);
    }
    hilog.info(0x0000, TAG, `MatterItemCard resetNode itemId=${this.item.id}`);
  }

  build() {
    Stack() {
      NodeContainer(this.nodeController)
    }
    .width('100%')
    .height('100%')
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          // 如果不允许展开，直接返回
          if (!this.enableExpand) {
            hilog.info(0x0000, TAG, `MatterItemCard longPress ignored (expand disabled) itemId=${this.item.id}`);
            return;
          }
          if (this.animationProperties.isExpandPageShow) {
            return;
          }
          hilog.info(0x0000, TAG, `MatterItemCard longPress expand itemId=${this.item.id}`);
          if (this.nodeController !== undefined) {
            this.nodeController.onRemove();
          }
          this.animationProperties.triggerExpand(getMatterItemCardKey(this.item.id), this.item);
        })
    )
  }
}
