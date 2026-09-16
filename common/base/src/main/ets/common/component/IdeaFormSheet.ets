import { TagModel } from '../model/TagItem';
import { ItemFormContent } from './ItemFormContent';
import { buildSheetTitleBar } from './SheetTitleBar';
import { ItemFormSheetConfig } from './ItemFormSheetTypes';
import { IdeaCollection } from '../model/IdeaPoolModels';

@Component
export struct IdeaFormTitleBar {
  @Require @Prop config: ItemFormSheetConfig;
  @Prop isSaving: boolean = false;
  @Prop savingText?: string | Resource;
  @Prop actionDisabled: boolean = false;
  onClose: () => void = () => {};
  onSubmit: () => void | Promise<void> = () => {};

  build() {
    Column() {
      buildSheetTitleBar({
        title: this.config.titleBar.title,
        actionButtonText: this.isSaving && this.savingText
          ? this.savingText
          : this.config.titleBar.actionButtonText,
        actionButtonDisabled: this.actionDisabled || this.isSaving,
        actionButtonDisabledText: this.config.titleBar.actionButtonDisabledText,
        onClose: this.onClose,
        onSubmit: this.onSubmit
      });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/**
 * 通用灵感表单内容组件（添加/编辑共用）
 */
@Component
export struct IdeaFormSheet {
  @Require @Prop config: ItemFormSheetConfig;
  @Link tagData: TagModel[];
  @Link inputName: string;
  @Link selectedTagIndex: number;
  @Link directStartEnabled: boolean;
  @Link isEditingTag: boolean;
  @Link tagShakeAngle: number;
  @Link selectedEmoji: string;
  @Prop isDarkTheme: boolean = false;
  @Prop showCollectionPicker: boolean = false;
  @Prop collectionPickerLabel: ResourceStr = '';
  @Prop collections: IdeaCollection[] = [];
  @Prop selectedCollectionId: string | null = null;
  @Prop showCollectionLooseOption: boolean = true;
  @Prop showActionButtons: boolean = false;
  @Prop confirmButtonText: ResourceStr = '';
  @Prop confirmButtonDisabled: boolean = false;
  @Prop confirmButtonDisabledText: ResourceStr = '';
  onCollectionSelectionChange?: (collectionId: string | null) => void;
  onCreateTag?: () => void;
  onDeleteTag?: (tag: TagModel, index: number) => void;
  onToggleTagEditing?: (isEditing: boolean) => void;
  onClose?: () => void;
  onSubmit?: () => void | Promise<void>;

  build() {
    ItemFormContent({
      config: this.config,
      tagData: this.tagData,
      inputName: this.inputName,
      selectedTagIndex: this.selectedTagIndex,
      directStartEnabled: this.directStartEnabled,
      isEditingTag: this.isEditingTag,
      tagShakeAngle: this.tagShakeAngle,
      selectedEmoji: this.selectedEmoji,
      isDarkTheme: this.isDarkTheme,
      showCollectionPicker: this.showCollectionPicker,
      collectionPickerLabel: this.collectionPickerLabel,
      collections: this.collections,
      selectedCollectionId: this.selectedCollectionId,
      showCollectionLooseOption: this.showCollectionLooseOption,
      showActionButtons: this.showActionButtons,
      confirmButtonText: this.confirmButtonText,
      confirmButtonDisabled: this.confirmButtonDisabled,
      confirmButtonDisabledText: this.confirmButtonDisabledText,
      onClose: this.onClose,
      onConfirm: this.onSubmit,
      onCollectionSelectionChange: this.onCollectionSelectionChange,
      onCreateTag: this.onCreateTag,
      onDeleteTag: this.onDeleteTag,
      onToggleTagEditing: this.onToggleTagEditing
    })
  }
}
