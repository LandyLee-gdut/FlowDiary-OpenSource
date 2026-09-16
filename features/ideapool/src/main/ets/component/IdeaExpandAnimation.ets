/**
 * 一镜到底动画属性类
 * 封装灵感卡片展开/收起的动画控制逻辑
 */
import { componentUtils, curves, UIContext } from '@kit.ArkUI';
import { BreakpointConstants, BreakpointType, IdeaActivity } from 'base';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'IdeaCardExpand';

/**
 * 收起动画类型
 */
export enum CollapseAnimationType {
  NORMAL = 'normal',      // 普通收起
  DELETE = 'delete',      // 删除
  ROLLBACK = 'rollback'   // 回退
}

/**
 * 矩形信息
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
 * 一镜到底动画属性类
 */
@Observed
export class IdeaExpandAnimationProperties {
  // 展开页面是否显示
  public isExpandPageShow: boolean = false;
  // 控制组件是否响应点击事件
  public isEnabled: boolean = true;
  // 当前展开的灵感
  public currentIdea: IdeaActivity | null = null;
  // 当前展开灵感的ID
  public curIdeaId: string = '';
  // 当前展开灵感所属的光影集 ID
  public currentCollectionId: string | null = null;
  // 位移动画属性
  public translateX: number = 0;
  public translateY: number = 0;
  // 展开卡片的初始位置
  public positionX: number = 0;
  public positionY: number = 0;
  // 初始宽度和高度
  public initialWidth: number = 0;
  public initialHeight: number = 0;
  // 是否已经改变尺寸（展开状态）
  public changedSize: boolean = false;
  // 相对时间基准
  public relativeTimeBaseline: number = Date.now();
  // 背景模糊不透明度（用于动画）
  public backgroundOpacity: number = 0;
  public expandedWidth: number = 0;
  public expandedHeight: number = 0;
  public rootStackWidth: number = 0;
  public rootStackHeight: number = 0;
  // 位置修正（用于处理某些页面布局导致的坐标偏移）
  public positionCorrectionY: number = 0;
  // 是否正在执行删除/回退的缩小到icon动画
  public isCollapsingToIcon: boolean = false;
  // 当前收起动画的类型
  public collapseAnimationType: CollapseAnimationType = CollapseAnimationType.NORMAL;
  // 缩放和透明度动画属性
  public cardScale: number = 1.0;
  public cardOpacity: number = 1.0;

  // 计算后的位移量
  private calculatedTranslateX: number = 0;
  private calculatedTranslateY: number = 0;
  // 展开后卡片的目标尺寸（与 MatterItem 保持一致）
  private readonly expandedWidthPercent: BreakpointType<number> =
    new BreakpointType<number>({ sm: 0.92, md: 0.70, lg: 0.45 });
  private readonly expandedHeightPercent: BreakpointType<number> =
    new BreakpointType<number>({ sm: 0.76, md: 0.76, lg: 0.76 });
  private readonly expandedMaxWidth: BreakpointType<number> =
    new BreakpointType<number>({ sm: 10000, md: 520, lg: 480 });
  private readonly expandedMinHeight: number = 420;
  private readonly expandedVerticalPadding: number = 24;
  private uiContext: UIContext;

  constructor(uiContext: UIContext) {
    this.uiContext = uiContext;
  }

  /**
   * 触发展开动画
   */
  public expandAnimation(idea: IdeaActivity, relativeTimeBaseline: number): void {
    if (this.isExpandPageShow) {
      hilog.info(0x0000, TAG, `expandAnimation ignored, already expanded for idea: ${idea.id}`);
      return;
    }
    // 计算折叠态卡片相对父组件的位置
    if (!this.calculateData(idea.id)) {
      hilog.warn(0x0000, TAG, `expandAnimation aborted due to invalid rects for idea: ${idea.id}`);
      return;
    }
    // 记录展开的灵感信息
    this.currentIdea = idea;
    this.curIdeaId = idea.id;
    this.currentCollectionId = null;
    this.relativeTimeBaseline = relativeTimeBaseline;

    hilog.info(0x0000, TAG, `expandAnimation called for idea: ${idea.id}, ${idea.name}`);

    hilog.info(0x0000, TAG, `Position calculated: posX=${this.positionX}, posY=${this.positionY}, width=${this.initialWidth}, height=${this.initialHeight}`);

    // 展开态卡片上树
    this.isExpandPageShow = true;

    hilog.info(0x0000, TAG, `isExpandPageShow set to true`);

    // 卡片展开的属性动画 - 使用轻快的弹簧曲线，短duration更干脆
    this.uiContext?.animateTo({
      curve: curves.springMotion(0.35, 0.9),
      duration: 80
    }, () => {
      this.translateX = this.calculatedTranslateX;
      this.translateY = this.calculatedTranslateY;
      this.changedSize = true;
      hilog.info(0x0000, TAG, `Animation applied: translateX=${this.translateX}, translateY=${this.translateY}, changedSize=${this.changedSize}`);
    });

    // 背景模糊动画
    this.uiContext?.animateTo({
      curve: curves.springMotion(0.35, 0.9),
      duration: 60
    }, () => {
      this.backgroundOpacity = 1;
    });
  }

  /**
   * 重置所有动画状态
   * 用于动画完成后清理，确保下次展开时状态正确
   */
  private resetAllStates(): void {
    this.isExpandPageShow = false;
    this.isEnabled = true;
    this.isCollapsingToIcon = false;
    this.collapseAnimationType = CollapseAnimationType.NORMAL;
    this.currentIdea = null;
    this.curIdeaId = '';
    this.currentCollectionId = null;
    this.translateX = 0;
    this.translateY = 0;
    this.positionX = 0;
    this.positionY = 0;
    this.initialWidth = 0;
    this.initialHeight = 0;
    this.changedSize = false;
    this.backgroundOpacity = 0;
    this.expandedWidth = 0;
    this.expandedHeight = 0;
    this.rootStackWidth = 0;
    this.rootStackHeight = 0;
    this.positionCorrectionY = 0;
    this.calculatedTranslateX = 0;
    this.calculatedTranslateY = 0;
    this.cardScale = 1.0;
    this.cardOpacity = 1.0;
  }

  /**
   * 触发收起动画
   * @param onFinish 动画完成回调
   * @param animationType 动画类型：普通收起/删除/回退
   */
  public collapseAnimation(onFinish: () => void, animationType: CollapseAnimationType = CollapseAnimationType.NORMAL): void {
    this.collapseAnimationType = animationType;

    // 背景模糊消失动画
    this.uiContext?.animateTo({
      curve: curves.springMotion(0.35, 0.9),
      duration: 60
    }, () => {
      this.backgroundOpacity = 0;
    });

    if (animationType === CollapseAnimationType.DELETE || animationType === CollapseAnimationType.ROLLBACK) {
      // 删除/回退动画：两阶段Q弹动画
      // 立即开始：旋转 + 缩小到icon → 透明度渐变（保持居中）
      this.isCollapsingToIcon = true;
      
      // 第一阶段：旋转 + 移动到中心 + 缩小到icon大小（220ms，立即开始缩小）
      this.uiContext?.animateTo({
        curve: curves.springMotion(0.35, 0.8),
        duration: 220,
        onFinish: () => {
          // 第二阶段：透明度渐变（保持尺寸和位置不变，居中淡出，150ms）
          this.uiContext?.animateTo({
            curve: Curve.EaseInOut,
            duration: 150,
            onFinish: () => {
              onFinish();
              // 重置所有状态，确保下次展开时不会有残留状态导致漂移
              this.resetAllStates();
            }
          }, () => {
            // 只改变透明度，保持尺寸和位置不变（居中淡出）
            this.cardOpacity = 0;
          });
        }
      }, () => {
        this.isEnabled = false;
        // 缩小到icon的尺寸（52vp）
        const iconSize: number = 52;
        this.expandedWidth = iconSize;
        this.expandedHeight = iconSize;
        // 移动到屏幕中心
        this.translateX = (this.rootStackWidth - iconSize) / 2 - this.positionX;
        this.translateY = (this.rootStackHeight - iconSize) / 2 - this.positionY;
      });
    } else {
      // 普通收起动画：回到原位
      this.uiContext?.animateTo({
        curve: curves.springMotion(0.35, 0.9),
        duration: 80,
        onFinish: () => {
          this.uiContext?.animateTo({
            curve: Curve.EaseInOut,
            duration: 120,
            onFinish: () => {
              onFinish();
              // 重置所有状态，确保下次展开时不会有残留状态导致漂移
              this.resetAllStates();
            }
          }, () => {
            this.cardOpacity = 0;
          });
        }
      }, () => {
        // 卡片从展开态回到折叠态
        this.isEnabled = false;
        this.translateX = 0;
        this.translateY = this.positionCorrectionY;
        this.changedSize = false;
      });
    }
  }

  /**
   * 计算动画参数
   * 展开后卡片居中显示
   */
  private calculateData(ideaId: string): boolean {
    const clickedCardInfo = this.getRectInfoById(this.uiContext, `ideaCard_${ideaId}`);
    const rootStackInfo = this.getRectInfoById(this.uiContext, 'ideaPoolRootStack');
    if (clickedCardInfo === null || rootStackInfo === null) {
      return false;
    }

    // 计算展开态卡片的初始位置（相对于rootStack）
    this.positionX = this.uiContext.px2vp(clickedCardInfo.left - rootStackInfo.left);
    this.positionY = this.uiContext.px2vp(clickedCardInfo.top - rootStackInfo.top);
    this.initialWidth = this.uiContext.px2vp(clickedCardInfo.width);
    this.initialHeight = this.uiContext.px2vp(clickedCardInfo.height);

    // rootStack的尺寸（vp）
    const rootStackWidth = this.uiContext.px2vp(rootStackInfo.width);
    const rootStackHeight = this.uiContext.px2vp(rootStackInfo.height);
    this.rootStackWidth = rootStackWidth;
    this.rootStackHeight = rootStackHeight;

    const currentBreakpoint = AppStorage.get<string>(BreakpointConstants.CURRENT_BREAKPOINT)
      ?? BreakpointConstants.BREAKPOINT_SM;
    // 展开后卡片的目标尺寸（vp）
    let expandedWidth = rootStackWidth * this.expandedWidthPercent.getValue(currentBreakpoint);
    expandedWidth = Math.min(expandedWidth, this.expandedMaxWidth.getValue(currentBreakpoint));

    const maxExpandedHeight = Math.max(rootStackHeight - this.expandedVerticalPadding * 2, 0);
    let expandedHeight = rootStackHeight * this.expandedHeightPercent.getValue(currentBreakpoint);
    expandedHeight = Math.min(expandedHeight, maxExpandedHeight);
    expandedHeight = Math.max(expandedHeight, this.expandedMinHeight);
    this.expandedWidth = expandedWidth;
    this.expandedHeight = expandedHeight;

    // 计算展开后卡片的目标位置（居中）
    const targetX = (rootStackWidth - expandedWidth) / 2;
    const targetY = (rootStackHeight - expandedHeight) / 2;

    // 计算需要位移的距离：从卡片当前位置移动到目标居中位置
    this.calculatedTranslateX = targetX - this.positionX;
    this.calculatedTranslateY = targetY - this.positionY;

    hilog.info(0x0000, TAG, `calculateData: cardPos=(${this.positionX}, ${this.positionY}), rootSize=(${rootStackWidth}, ${rootStackHeight})`);
    hilog.info(0x0000, TAG, `calculateData: expandedSize=(${expandedWidth}, ${expandedHeight}), targetPos=(${targetX}, ${targetY})`);
    hilog.info(0x0000, TAG, `calculateData: calculatedTranslate=(${this.calculatedTranslateX}, ${this.calculatedTranslateY})`);
    return true;
  }

  /**
   * 根据组件的id获取组件的位置信息
   */
  private getRectInfoById(context: UIContext, id: string): RectInfo | null {
    const componentInfo: componentUtils.ComponentInfo = context.getComponentUtils().getRectangleById(id);

    if (!componentInfo) {
      // 如果获取不到组件信息，返回默认值
      hilog.warn(0x0000, TAG, `getRectangleById failed for id=${id}`);
      return null;
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
      return null;
    }
    return rstRect;
  }
}
