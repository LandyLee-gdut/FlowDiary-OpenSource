/**
 * 通用Sheet标题栏构建器
 * 用于添加/编辑表单的Sheet标题栏
 * 
 * 使用方式：
 * 在组件中定义 @Builder 方法，调用 buildSheetTitleBar 函数：
 * 
 * @Builder
 * titleBuilder() {
 *   buildSheetTitleBar({
 *     title: '添加事项',
 *     actionButtonText: '添加',
 *     onClose: () => { this.isShow = false; },
 *     onSubmit: () => { this.handleSubmit(); }
 *   })
 * }
 */
import { SheetTitleBarConfig } from './ItemFormSheetTypes';

/**
 * Sheet标题栏参数
 */
export interface SheetTitleBarParams {
  /** 标题文字 */
  title: string | Resource;
  /** 操作按钮文字 */
  actionButtonText: string | Resource;
  /** 操作按钮是否禁用 */
  actionButtonDisabled?: boolean;
  /** 操作按钮禁用时的文字 */
  actionButtonDisabledText?: string | Resource;
  /** 关闭回调 */
  onClose: () => void;
  /** 提交回调 */
  onSubmit: () => void | Promise<void>;
}

/**
 * 从配置对象和回调创建标题栏参数
 */
export function createTitleBarParams(
  config: SheetTitleBarConfig,
  onClose: () => void,
  onSubmit: () => void | Promise<void>
): SheetTitleBarParams {
  return {
    title: config.title,
    actionButtonText: config.actionButtonText,
    actionButtonDisabled: config.actionButtonDisabled,
    actionButtonDisabledText: config.actionButtonDisabledText,
    onClose,
    onSubmit
  };
}

/**
 * 通用Sheet标题栏构建器函数
 * 直接在 @Builder 中调用此函数构建标题栏
 */
@Builder
export function buildSheetTitleBar(params: SheetTitleBarParams) {
  Row() {
    // 左侧：关闭按钮 + 标题
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontColor([$r('app.color.text_primary')])
      }
      .height(40)
      .width(40)
      .backgroundColor($r('app.color.neutral_100'))
      .margin({ right: 5 })
      .onClick(() => {
        params.onClose();
      })

      Text(params.title)
        .fontSize(23)
        .fontWeight(700)
        .fontColor($r('app.color.text_primary'))
    }

    // 右侧：操作按钮
    Row() {
      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Text(getActionButtonText(params))
          .fontWeight(700)
          .fontSize(16)
          .fontColor(params.actionButtonDisabled
            ? $r('app.color.text_disabled')
            : $r('app.color.primary'))
      }
      .enabled(!(params.actionButtonDisabled ?? false))
      .border({ width: 2, color: $r('app.color.primary_light') })
      .height(40)
      .width(80)
      .backgroundColor($r('app.color.primary_lighter'))
      .onClick(() => {
        params.onSubmit();
      })
    }
  }
  .width('100%')
  .justifyContent(FlexAlign.SpaceBetween)
}

/**
 * 获取操作按钮文字
 */
function getActionButtonText(params: SheetTitleBarParams): string | Resource {
  if (params.actionButtonDisabled && params.actionButtonDisabledText) {
    return params.actionButtonDisabledText;
  }
  return params.actionButtonText;
}

/**
 * 兼容旧版本的 @Component 组件（保留以便渐进迁移）
 * @deprecated 建议使用 buildSheetTitleBar 函数代替
 */
@Component
export struct SheetTitleBar {
  /** 标题文字 */
  title: string | Resource = '';
  /** 操作按钮文字 */
  actionButtonText: string | Resource = '';
  /** 操作按钮是否禁用 */
  actionButtonDisabled?: boolean;
  /** 操作按钮禁用时的文字 */
  actionButtonDisabledText?: string | Resource;
  /** 关闭回调 */
  onClose: () => void = () => {};
  /** 提交回调 */
  onSubmit: () => void | Promise<void> = () => {};

  build() {
    buildSheetTitleBar({
      title: this.title,
      actionButtonText: this.actionButtonText,
      actionButtonDisabled: this.actionButtonDisabled,
      actionButtonDisabledText: this.actionButtonDisabledText,
      onClose: this.onClose,
      onSubmit: this.onSubmit
    })
  }
}
