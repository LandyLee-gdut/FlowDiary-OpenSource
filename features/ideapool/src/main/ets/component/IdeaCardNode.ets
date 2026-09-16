/**
 * @deprecated Use IdeaExpandPage with the new IdeaCard UI instead of this legacy transition.
 * 跨容器迁移能力 - 用于实现灵感卡片一镜到底动画
 * 基于官方文档的 PostNode 实现
 */
import { UIContext, NodeController, BuilderNode, FrameNode, curves } from '@kit.ArkUI';
import { IdeaActivity, TimeRecordUtil, AppShadows, buildPointLightEffect } from 'base';
import { hdsEffect } from '@kit.UIDesignKit';

// 动画常量 - 干脆利落
const ANIMATION_DURATION = 80;
const ANIMATION_CURVE = curves.springMotion(0.35, 0.9);

/**
 * 灵感卡片数据
 */
@Observed
class IdeaCardData {
  idea: IdeaActivity | null = null;
  isExpand: boolean = false;
  relativeTimeBaseline: number = Date.now();
  isDarkTheme: boolean = false;
  editButtonPressed: boolean = false;
  moveButtonPressed: boolean = false;
  onEditTouch: ((event: TouchEvent) => void) | null = null;
  onMoveTouch: ((event: TouchEvent) => void) | null = null;
  // 按钮回调
  onEdit: (() => void) | null = null;
  onMoveToToday: (() => void) | null = null;
}

/**
 * 灵感卡片Builder - 保持原IdeaCard样式
 * 折叠态：完整显示标题、标签、创建时间
 * 展开态：显示更多详细信息
 */
@Builder
function IdeaCardBuilder(data: IdeaCardData) {
  Column() {
    // 上方名称和编辑按钮区域
    Row() {
      Text(data.idea?.name ?? '')
        .fontSize(data.isExpand ? 18 : 16)
        .fontWeight(700)
        .fontColor(data.idea?.ideaLightState === 1 ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
        .width(data.isExpand ? '85%' : '75%')
        .maxLines(data.isExpand ? 4 : 3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .animation({ curve: ANIMATION_CURVE, duration: ANIMATION_DURATION })
        .geometryTransition(`ideaCard_title_${data.idea?.id}`, { follow: true })
      // 编辑按钮 - 在IdeaCardBuilder中渲染，随卡片一起迁移
      Button() {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(16)
          .fontWeight(400)
          .fontColor([data.idea?.ideaLightState === 1 ? $r('app.color.text_tertiary') : $r('app.color.neutral_300')])
      }
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.5 })
      .shadow({ color: $r('app.color.accent_lighter'), radius: 10 })
      .padding(5)
      .backgroundColor(data.idea?.ideaLightState === 1 ? $r('app.color.bg_main') : $r('app.color.neutral_100'))
      .visualEffect(buildPointLightEffect({
        preset: 'buttonTouch',
        color: $r('app.color.immersive_glow_primary'),
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
        isActive: data.editButtonPressed,
        isDarkTheme: data.isDarkTheme,
        overrides: {
          height: 240
        }
      }))
      .onTouch(data.onEditTouch ?? undefined)
      .geometryTransition(`ideaCard_editBtn_${data.idea?.id}`, { follow: true })
      .animation({ curve: ANIMATION_CURVE, duration: ANIMATION_DURATION })
      .onClick(() => {
        if (data.onEdit) {
          data.onEdit();
        }
      })
    }
    .height(data.isExpand ? undefined : 50)
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    // .margin({ bottom: data.isExpand ? 20 : 40 })
    .animation({ curve: ANIMATION_CURVE, duration: ANIMATION_DURATION })

    // 展开后显示更多信息
    if (data.isExpand) {
      Column({ space: 8 }) {
        // 创建时间（完整显示）
        Row() {
          Text('创建时间：')
            .fontSize(13)
            .fontWeight(500)
            .fontColor($r('app.color.text_secondary'))
          Text(TimeRecordUtil.formatToYYYYMMDD(data.idea?.createdAt ?? 0))
            .fontSize(13)
            .fontWeight(500)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .transition(TransitionEffect.OPACITY.animation({ curve: ANIMATION_CURVE, duration: ANIMATION_DURATION }))

        // 更新时间
        Row() {
          Text('更新时间：')
            .fontSize(13)
            .fontWeight(500)
            .fontColor($r('app.color.text_secondary'))
          Text(TimeRecordUtil.formatToYYYYMMDD(data.idea?.updatedAt ?? 0))
            .fontSize(13)
            .fontWeight(500)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .transition(TransitionEffect.OPACITY.animation({ curve: ANIMATION_CURVE, duration: ANIMATION_DURATION }))
      }
      .width('100%')
      .margin({ bottom: 10 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 }))
          .animation({ curve: ANIMATION_CURVE, duration: ANIMATION_DURATION, delay: 30 }),
        TransitionEffect.OPACITY.animation({ curve: ANIMATION_CURVE, duration: 60 })
      ))
    }

    // 底部：标签和时间（与原IdeaCard布局一致）
    Column() {
      // 标签行
      Row() {
        Row()
          .width(8)
          .height(8)
          .borderRadius('50%')
          .margin({ right: 5 })
          .backgroundColor(data.idea?.tagColorHex ?? $r('app.color.tag_placeholder_gray'))
          .geometryTransition(`ideaCard_tagDot_${data.idea?.id}`, { follow: true })
        Text(data.idea?.tagName ?? '无标签')
          .fontSize(data.isExpand ? 13 : 11)
          .fontWeight(data.isExpand ? 500 : 400)
          .fontColor($r('app.color.text_tertiary'))
          .geometryTransition(`ideaCard_tagName_${data.idea?.id}`, { follow: true })
          .animation({ curve: ANIMATION_CURVE, duration: ANIMATION_DURATION })
      }
      .offset({ y: 10 })
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .geometryTransition(`ideaCard_tagRow_${data.idea?.id}`, { follow: true })

      // 创建时间行（原布局：时间文字 + 移动到今天按钮，SpaceBetween）
      Row() {
        Text(`创建:${TimeRecordUtil.formatRelativeTime(data.idea?.createdAt ?? 0, data.relativeTimeBaseline)}`)
          .fontSize(data.isExpand ? 13 : 11)
          .fontWeight(500)
          .fontColor($r('app.color.text_disabled'))
          .geometryTransition(`ideaCard_createTime_${data.idea?.id}`, { follow: true })
          .animation({ curve: ANIMATION_CURVE, duration: ANIMATION_DURATION })
        // 移动到今天按钮 - 在IdeaCardBuilder中渲染，随卡片一起迁移
        Button() {
          Row() {
            SymbolGlyph($r('sys.symbol.sun_max'))
              .fontSize(16)
              .fontWeight(700)
              .fontColor([data.idea?.ideaLightState === 1 ? $r('app.color.neutral_100') : $r('app.color.text_tertiary')])
          }
        }
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.5 })
        .shadow({ color: data.idea?.ideaLightState === 1 ? $r('app.color.warning') : Color.Transparent, radius: data.idea?.ideaLightState === 1 ? 15 : 0 })
        .padding(5)
        .backgroundColor(data.idea?.ideaLightState === 1 ? $r('app.color.accent') : $r('app.color.bg_main'))
        .border({
          width: data.idea?.ideaLightState === 1 ? 0 : 1,
          color: data.idea?.ideaLightState === 1 ? Color.Transparent : $r('app.color.neutral_300')
        })
        .visualEffect(buildPointLightEffect({
          preset: 'buttonTouch',
          color: $r('app.color.immersive_glow_warning'),
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
          isActive: data.moveButtonPressed,
          isDarkTheme: data.isDarkTheme,
          overrides: {
            height: 240
          }
        }))
        .onTouch(data.onMoveTouch ?? undefined)
        .geometryTransition(`ideaCard_moveBtn_${data.idea?.id}`, { follow: true })
        .animation({ curve: ANIMATION_CURVE, duration: ANIMATION_DURATION })
        .onClick(() => {
          if (data.onMoveToToday) {
            data.onMoveToToday();
          }
        })
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .geometryTransition(`ideaCard_footer_${data.idea?.id}`, { follow: true })
  }
  .borderRadius(data.isExpand ? 20 : 15)
  .shadow(data.idea?.ideaLightState === 1 ? {
    radius: 35,
    color: $r('app.color.warning_light'),
    offsetX: 0,
    offsetY: 0,
  } : (data.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE))
  .padding({ left: 15, right: 15, top: 15, bottom: 15 })
  .justifyContent(FlexAlign.SpaceBetween)
  .backgroundColor(data.idea?.ideaLightState === 1 ? $r('app.color.bg_card') : $r('app.color.bg_main'))
  .visualEffect(buildPointLightEffect({
    preset: 'cardTouch',
    color: $r('app.color.immersive_glow_warning'),
    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
    isActive: false,
    isDarkTheme: data.isDarkTheme
  }))
  .width('100%')
  .height('100%')
  .geometryTransition(`ideaCard_container_${data.idea?.id}`, { follow: true })
  .animation({ curve: curves.springMotion(0.6, 0.6), duration: 350 })
}

class __InternalValue__ {
  flag: boolean = false;
}

/**
 * 灵感卡片节点控制器
 * 用于实现跨容器迁移
 */
/** @deprecated Use IdeaExpandPage with the new IdeaCard UI instead. */
export class IdeaCardNode extends NodeController {
  private node: BuilderNode<IdeaCardData[]> | null = null;
  private isRemove: __InternalValue__ = new __InternalValue__();
  private callback: Function | undefined = undefined;
  private data: IdeaCardData | null = null;
  private uiContext: UIContext | null = null;
  private isDarkTheme: boolean = false;
  private editButtonPressed: boolean = false;
  private moveButtonPressed: boolean = false;
  private readonly onEditTouchHandler: (event: TouchEvent) => void = (event: TouchEvent) => {
    if (event.type === TouchType.Down) {
      this.editButtonPressed = true;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.editButtonPressed = false;
    }
    this.updateLightEffects();
  };
  private readonly onMoveTouchHandler: (event: TouchEvent) => void = (event: TouchEvent) => {
    if (event.type === TouchType.Down) {
      this.moveButtonPressed = true;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.moveButtonPressed = false;
    }
    this.updateLightEffects();
  };

  private updateLightEffects(): void {
    if (this.node === null || this.data === null) {
      return;
    }
    this.data.isDarkTheme = this.isDarkTheme;
    this.data.editButtonPressed = this.editButtonPressed;
    this.data.moveButtonPressed = this.moveButtonPressed;
    this.node.update(this.data);
  }

  makeNode(uiContext: UIContext): FrameNode | null {
    if (this.isRemove.flag === true) {
      return null;
    }
    if (this.node !== null) {
      return this.node.getFrameNode();
    }
    return null;
  }

  init(uiContext: UIContext, idea: IdeaActivity, isExpand: boolean, relativeTimeBaseline: number, isDarkTheme: boolean,
       onEdit?: () => void, onMoveToToday?: () => void) {
    if (this.node !== null) {
      return;
    }
    // 保存 UIContext 引用，用于后续刷新
    this.uiContext = uiContext;
    this.isDarkTheme = isDarkTheme;
    // 创建节点
    const createdNode: BuilderNode<IdeaCardData[]> = new BuilderNode<IdeaCardData[]>(uiContext);
    this.node = createdNode;
    // 创建离线组件
    this.data = {
      idea: idea,
      isExpand: isExpand,
      relativeTimeBaseline: relativeTimeBaseline,
      isDarkTheme: this.isDarkTheme,
      editButtonPressed: this.editButtonPressed,
      moveButtonPressed: this.moveButtonPressed,
      onEditTouch: this.onEditTouchHandler,
      onMoveTouch: this.onMoveTouchHandler,
      onEdit: onEdit ?? null,
      onMoveToToday: onMoveToToday ?? null
    };
    createdNode.build(wrapBuilder<IdeaCardData[]>(IdeaCardBuilder), this.data);
  }

  update(idea: IdeaActivity, isExpand: boolean, relativeTimeBaseline: number, isDarkTheme: boolean,
         onEdit?: () => void, onMoveToToday?: () => void) {
    if (this.node !== null) {
      this.isDarkTheme = isDarkTheme;
      // 调用update进行更新
      this.data = {
        idea: idea,
        isExpand: isExpand,
        relativeTimeBaseline: relativeTimeBaseline,
        isDarkTheme: this.isDarkTheme,
        editButtonPressed: this.editButtonPressed,
        moveButtonPressed: this.moveButtonPressed,
        onEditTouch: this.onEditTouchHandler,
        onMoveTouch: this.onMoveTouchHandler,
        onEdit: onEdit ?? null,
        onMoveToToday: onMoveToToday ?? null
      };
      this.node.update(this.data);
    }
  }

  setCallback(callback: Function | undefined) {
    this.callback = callback;
  }

  callCallback() {
    if (this.callback !== undefined) {
      this.callback();
    }
  }

  onRemove() {
    this.isRemove.flag = true;
    // 组件迁移出节点时触发重建
    this.rebuild();
    this.isRemove.flag = false;
  }

  /**
   * 刷新节点UI
   * 用于响应数据变化或配置变化（如深色模式切换）
   * 需要销毁旧节点并创建新节点，以使资源引用重新解析
   */
  refreshNode() {
    if (this.node !== null && this.data !== null && this.uiContext !== null) {
      // 先让旧节点下树
      this.isRemove.flag = true;
      this.rebuild();
      this.isRemove.flag = false;

      // 销毁旧的 BuilderNode
      this.node.dispose();

      // 创建新的 BuilderNode，使 $r(...) 资源引用重新解析
      const rebuiltNode: BuilderNode<IdeaCardData[]> = new BuilderNode<IdeaCardData[]>(this.uiContext);
      this.node = rebuiltNode;
      this.data.isDarkTheme = this.isDarkTheme;
      this.data.editButtonPressed = this.editButtonPressed;
      this.data.moveButtonPressed = this.moveButtonPressed;
      this.data.onEditTouch = this.onEditTouchHandler;
      this.data.onMoveTouch = this.onMoveTouchHandler;
      rebuiltNode.build(wrapBuilder<IdeaCardData[]>(IdeaCardBuilder), this.data);

      // 触发 NodeController 重建以显示新节点
      this.rebuild();
    }
  }
}

// 存储所有灵感卡片节点的Map
const gIdeaCardNodeMap: Map<string, IdeaCardNode | undefined> = new Map();

/**
 * 创建灵感卡片节点
 */
export const createIdeaCardNode = (
  uiContext: UIContext,
  idea: IdeaActivity,
  isExpand: boolean,
  relativeTimeBaseline: number,
  isDarkTheme: boolean,
  onEdit?: () => void,
  onMoveToToday?: () => void
): IdeaCardNode | undefined => {
  const node = new IdeaCardNode();
  node.init(uiContext, idea, isExpand, relativeTimeBaseline, isDarkTheme, onEdit, onMoveToToday);
  gIdeaCardNodeMap.set(idea.id, node);
  return node;
};

/**
 * 获取灵感卡片节点
 */
export const getIdeaCardNode = (id: string): IdeaCardNode | undefined => {
  if (!gIdeaCardNodeMap.has(id)) {
    return undefined;
  }
  return gIdeaCardNodeMap.get(id);
};

/**
 * 删除灵感卡片节点
 */
export const deleteIdeaCardNode = (id: string) => {
  gIdeaCardNodeMap.delete(id);
};

/**
 * 清空所有灵感卡片节点
 */
export const clearAllIdeaCardNodes = () => {
  gIdeaCardNodeMap.clear();
};

/**
 * 刷新所有灵感卡片节点
 * 用于响应配置变化（如深色模式切换）
 */
export const refreshAllIdeaCardNodes = () => {
  gIdeaCardNodeMap.forEach((node) => {
    if (node) {
      node.refreshNode();
    }
  });
};
