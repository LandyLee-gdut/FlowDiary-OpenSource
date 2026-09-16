/**
 * 通用表单Sheet的类型定义和配置接口
 * 用于添加/编辑灵感、事项、快捷项等场景的统一配置
 */
import { TagModel } from '../model/TagItem';
import { EmojiItem } from '../EmojiUtil';

/**
 * Sheet操作模式
 */
export enum SheetMode {
  ADD = 'add',
  EDIT = 'edit'
}

/**
 * Sheet标题栏配置
 */
export interface SheetTitleBarConfig {
  /** 标题文字 */
  title: string | Resource;
  /** 操作按钮文字 */
  actionButtonText: string | Resource;
  /** 操作按钮是否禁用 */
  actionButtonDisabled?: boolean;
  /** 操作按钮禁用时的文字 */
  actionButtonDisabledText?: string | Resource;
}

/**
 * 名称输入区配置
 */
export interface NameInputConfig {
  /** 输入框标签文字 */
  label: string | Resource;
  /** 占位符文字 */
  placeholder: string | Resource;
  /** 是否显示"直接开始"toggle */
  showDirectStartToggle?: boolean;
  /** "直接开始"toggle的标签文字 */
  directStartLabel?: string | Resource;
}

/**
 * 标签选择区配置
 */
export interface TagSelectorConfig {
  /** 标签区标题 */
  label?: string | Resource;
  /** 是否显示编辑提示（如 "(长按编辑)"） */
  showEditHint?: boolean;
  /** 编辑提示文字 */
  editHintText?: string | Resource;
  /** 是否允许长按编辑（删除标签） */
  enableLongPressEdit?: boolean;
  /** 是否显示"新建"标签按钮 */
  showCreateButton?: boolean;
  /** "新建"按钮的回调 */
  onCreateTag?: () => void;
  /** 删除标签的回调 */
  onDeleteTag?: (tag: TagModel, index: number) => void;
}

/**
 * 表情/图标选择区配置
 */
export interface EmojiSelectorConfig {
  /** 是否显示表情选择区 */
  show?: boolean;
  /** 表情区标题 */
  label?: string | Resource;
  /** 副标题/提示 */
  hint?: string | Resource;
  /** 当前选中的emoji（用于编辑模式高亮显示） */
  selectedEmoji?: string;
  /** 选中emoji后是否追加到名称输入框 */
  appendToInput?: boolean;
}

/**
 * 通用表单Sheet完整配置
 */
export interface ItemFormSheetConfig {
  /** Sheet操作模式 */
  mode: SheetMode;
  /** 标题栏配置 */
  titleBar: SheetTitleBarConfig;
  /** 名称输入配置 */
  nameInput: NameInputConfig;
  /** 标签选择配置 */
  tagSelector?: TagSelectorConfig;
  /** 表情选择配置 */
  emojiSelector?: EmojiSelectorConfig;
}

/**
 * Sheet表单状态（双向绑定数据）
 */
export interface ItemFormState {
  /** 名称输入值 */
  inputName: string;
  /** 当前选中的标签索引，-1表示未选中 */
  selectedTagIndex: number;
  /** 直接开始toggle状态 */
  directStartEnabled?: boolean;
  /** 当前选中的emoji（用于编辑模式） */
  selectedEmoji?: string;
  /** 是否处于标签编辑模式 */
  isEditingTag?: boolean;
  /** 标签抖动角度（用于编辑动画） */
  tagShakeAngle?: number;
}

/**
 * Sheet回调事件
 */
export interface ItemFormSheetCallbacks {
  /** 关闭Sheet */
  onClose: () => void;
  /** 提交操作（添加/保存） */
  onSubmit: () => void | Promise<void>;
  /** 名称输入变化 */
  onNameChange?: (value: string) => void;
  /** 标签选择变化 */
  onTagSelect?: (index: number, tag: TagModel | null) => void;
  /** 表情选择 */
  onEmojiSelect?: (emoji: EmojiItem) => void;
  /** 直接开始toggle变化 */
  onDirectStartChange?: (enabled: boolean) => void;
}

/**
 * 预设配置工厂 - 用于快速创建常用配置
 */
export class ItemFormSheetPresets {
  /**
   * 创建"添加灵感"配置
   */
  static createAddIdeaConfig(): ItemFormSheetConfig {
    return {
      mode: SheetMode.ADD,
      titleBar: {
        title: '添加灵感',
        actionButtonText: '添加'
      },
      nameInput: {
        label: ' 事项名称',
        placeholder: '赶紧记录下来吧！',
        showDirectStartToggle: false
      },
      tagSelector: {
        label: ' 标签',
        showEditHint: true,
        editHintText: '(长按编辑)',
        enableLongPressEdit: true,
        showCreateButton: true
      },
      emojiSelector: {
        show: true,
        label: $r('app.string.icon'),
        hint: $r('app.string.add_a_emoji'),
        appendToInput: true
      }
    };
  }

  /**
   * 创建"编辑灵感"配置
   */
  static createEditIdeaConfig(): ItemFormSheetConfig {
    return {
      mode: SheetMode.EDIT,
      titleBar: {
        title: '编辑灵感',
        actionButtonText: '保存'
      },
      nameInput: {
        label: ' 灵感名称',
        placeholder: '赶紧记录下来吧！',
        showDirectStartToggle: false
      },
      tagSelector: {
        label: ' 标签',
        showEditHint: false,
        enableLongPressEdit: false,
        showCreateButton: false
      },
      emojiSelector: {
        show: true,
        label: $r('app.string.icon'),
        appendToInput: true
      }
    };
  }

  /**
   * 创建"添加事项"配置
   */
  static createAddMatterConfig(): ItemFormSheetConfig {
    return {
      mode: SheetMode.ADD,
      titleBar: {
        title: $r('app.string.add_today_activity'),
        actionButtonText: $r('app.string.add')
      },
      nameInput: {
        label: $r('app.string.item_name'),
        placeholder: $r('app.string.come_and_record_2'),
        showDirectStartToggle: true,
        directStartLabel: $r('app.string.start_directly')
      },
      tagSelector: {
        label: $r('app.string.tag'),
        showEditHint: true,
        editHintText: $r('app.string.long_press_edit'),
        enableLongPressEdit: true,
        showCreateButton: true
      },
      emojiSelector: {
        show: true,
        label: $r('app.string.icon'),
        hint: $r('app.string.add_a_emoji'),
        appendToInput: true
      }
    };
  }

  /**
   * 创建"编辑快捷事项"配置
   */
  static createEditSwissKnifeConfig(): ItemFormSheetConfig {
    return {
      mode: SheetMode.EDIT,
      titleBar: {
        title: '编辑快捷事项',
        actionButtonText: '保存'
      },
      nameInput: {
        label: '快捷项名称',
        placeholder: '请输入快捷项名称',
        showDirectStartToggle: false
      },
      tagSelector: {
        label: ' 标签',
        showEditHint: false,
        enableLongPressEdit: false,
        showCreateButton: false
      },
      emojiSelector: {
        show: true,
        label: ' 图标',
        appendToInput: false
      }
    };
  }

  /**
   * 创建"编辑事项"配置
   */
  static createEditMatterConfig(): ItemFormSheetConfig {
    return {
      mode: SheetMode.EDIT,
      titleBar: {
        title: '编辑今日事项',
        actionButtonText: '保存'
      },
      nameInput: {
        label: $r('app.string.item_name'),
        placeholder: $r('app.string.come_and_record'),
        showDirectStartToggle: false
      },
      tagSelector: {
        label: ' 标签',
        showEditHint: false,
        enableLongPressEdit: false,
        showCreateButton: false
      },
      emojiSelector: {
        show: true,
        label: $r('app.string.icon'),
        appendToInput: true
      }
    };
  }
}

