import { TagModel } from '../model/TagItem';
import { EmojiItem } from '../EmojiUtil';
import { IdeaCollectionFormContent } from './IdeaCollectionFormContent';

@Component
export struct IdeaCollectionUpsertSheetContent {
  @Link name: string;
  @Link summaryText: string;
  @Link selectedTagIndex: number;
  @Link selectedEmojiChar: string;
  @Prop tagData: TagModel[] = [];
  @Prop emojis: EmojiItem[] = [];
  @Prop isDarkTheme: boolean = false;

  @Prop headerLabel: ResourceStr = '';
  @Prop namePlaceholder: ResourceStr = '';
  @Prop descLabel: ResourceStr = '';
  @Prop descPlaceholder: ResourceStr = '';
  @Prop tagLabel: ResourceStr = '';
  @Prop emojiLabel: ResourceStr = '';
  @Prop defaultEmoji: ResourceStr = '';
  @Prop enableTagSelectionScale: boolean = true;
  @Prop confirmText: ResourceStr = $r('app.string.common_confirm');
  @Prop confirmDisabled: boolean = false;
  @Prop confirmDisabledText: ResourceStr = '';
  onClose?: () => void;
  onConfirm?: () => void | Promise<void>;

  build() {
    IdeaCollectionFormContent({
      name: this.name,
      summaryText: this.summaryText,
      selectedTagIndex: this.selectedTagIndex,
      selectedEmojiChar: this.selectedEmojiChar,
      tagData: this.tagData,
      emojis: this.emojis,
      isDarkTheme: this.isDarkTheme,
      headerLabel: this.headerLabel,
      namePlaceholder: this.namePlaceholder,
      descLabel: this.descLabel,
      descPlaceholder: this.descPlaceholder,
      tagLabel: this.tagLabel,
      emojiLabel: this.emojiLabel,
      defaultEmoji: this.defaultEmoji,
      enableTagSelectionScale: this.enableTagSelectionScale,
      confirmText: this.confirmText,
      confirmDisabled: this.confirmDisabled,
      confirmDisabledText: this.confirmDisabledText,
      onClose: this.onClose,
      onConfirm: this.onConfirm
    });
  }
}
