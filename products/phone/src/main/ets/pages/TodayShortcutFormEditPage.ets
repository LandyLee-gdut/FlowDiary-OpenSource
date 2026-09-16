import { curves, promptAction } from '@kit.ArkUI';
import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppShadows, EmojiItem, EmojiUtil, RDBStoreUtil, TagModel, tagService } from 'base';
import { TodayShortcutBindingData, todayShortcutWidgetService } from '../shortcut/model/TodayShortcutWidgetService';

const TAG: string = 'TodayShortcutFormEditPage';
const DOMAIN: number = 0x0000;
const FORM_DIMENSION_1X2: string = '1*2';
const FORM_DIMENSION_2X2: string = '2*2';
const STORAGE_FORM_ID: string = 'formId';
const STORAGE_FORM_DIMENSION: string = 'formDimension';
const FULL_PERCENT: string = '100%';

@Entry
@Component
struct TodayShortcutFormEditPage {
  private localStorage = this.getUIContext().getSharedLocalStorage();
  private formId: string = '';
  @State private formDimension: string = FORM_DIMENSION_2X2;
  @State private inputActivityName: string = '';
  @State private selectedTagIndex: number = -1;
  @State private isToggleOn: boolean = false;
  @State private tagData: TagModel[] = [];
  @State private emojiData: EmojiItem[] = EmojiUtil.getAll();

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'today shortcut edit page aboutToAppear');
    void this.initializeEditor();
  }

  private async initializeEditor(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'today shortcut edit page initialize start');
    this.readFormMetadata();
    await this.ensureDatabaseReady();
    await this.loadTags();
    await this.loadCurrentBinding();
    hilog.info(DOMAIN, TAG,
      `today shortcut edit page initialize done, formId=${this.formId}, formDimension=${this.formDimension}, tagCount=${this.tagData.length}`);
  }

  private readFormMetadata(): void {
    const storedFormId = this.localStorage?.get<string>(STORAGE_FORM_ID);
    if (storedFormId && storedFormId.length > 0) {
      this.formId = storedFormId;
    }
    const storedDimension = this.localStorage?.get<string>(STORAGE_FORM_DIMENSION);
    this.formDimension = storedDimension === FORM_DIMENSION_1X2 ? FORM_DIMENSION_1X2 : FORM_DIMENSION_2X2;
    hilog.info(DOMAIN, TAG,
      `today shortcut edit page read metadata, storedFormId=${storedFormId ?? ''}, resolvedFormId=${this.formId}, storedDimension=${storedDimension ?? ''}, resolvedDimension=${this.formDimension}`);
  }

  private getHostContext(): Context | null {
    const context = this.getUIContext().getHostContext() as Context | undefined;
    if (!context) {
      hilog.error(DOMAIN, TAG, 'today shortcut edit page host context is null');
      return null;
    }
    hilog.info(DOMAIN, TAG, 'today shortcut edit page host context resolved');
    return context;
  }

  private async ensureDatabaseReady(): Promise<void> {
    const context = this.getHostContext();
    if (!context) {
      hilog.info(DOMAIN, TAG, 'today shortcut edit page skip db init because host context is null');
      return;
    }
    hilog.info(DOMAIN, TAG, 'today shortcut edit page init db start');
    try {
      RDBStoreUtil.init(context);
      await RDBStoreUtil.getInstance().initRDB();
      hilog.info(DOMAIN, TAG, 'today shortcut edit page init db success');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `today shortcut edit page init db failed: ${JSON.stringify(error)}`);
    }
  }

  private async loadTags(): Promise<void> {
    try {
      this.tagData = await tagService.getAllTagsForUI();
      hilog.info(DOMAIN, TAG, `today shortcut edit page load tags success, count=${this.tagData.length}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `today shortcut edit page load tags failed: ${JSON.stringify(error)}`);
      this.tagData = [];
    }
  }

  private async loadCurrentBinding(): Promise<void> {
    hilog.info(DOMAIN, TAG, `today shortcut edit page load current binding start, formId=${this.formId}`);
    const context = this.getHostContext();
    if (!context || !this.formId || this.formId.length === 0) {
      hilog.info(DOMAIN, TAG,
        `today shortcut edit page reset because context/formId invalid, hasContext=${!!context}, formId=${this.formId}`);
      this.resetEditorState();
      return;
    }
    const binding = await todayShortcutWidgetService.getBinding(context, this.formId);
    if (!binding) {
      hilog.info(DOMAIN, TAG, `today shortcut edit page no existing binding for formId=${this.formId}`);
      this.resetEditorState();
      return;
    }
    this.inputActivityName = binding.activityName;
    this.isToggleOn = binding.autoStart;
    this.selectedTagIndex = this.resolveTagIndex(binding.tagId, binding.tagName);
    hilog.info(DOMAIN, TAG,
      `today shortcut edit page binding loaded, activityNameLength=${this.inputActivityName.length}, selectedTagIndex=${this.selectedTagIndex}, autoStart=${this.isToggleOn}`);
  }

  private resetEditorState(): void {
    this.inputActivityName = '';
    this.selectedTagIndex = -1;
    this.isToggleOn = false;
    hilog.info(DOMAIN, TAG, 'today shortcut edit page reset editor state');
  }

  private resolveTagIndex(tagId: string, tagName: string): number {
    if (tagId && tagId.length > 0) {
      const indexById = this.tagData.findIndex((tag: TagModel) => tag.id === tagId);
      if (indexById >= 0) {
        return indexById;
      }
    }
    if (tagName && tagName.length > 0) {
      const indexByName = this.tagData.findIndex((tag: TagModel) => tag.name === tagName);
      if (indexByName >= 0) {
        return indexByName;
      }
    }
    return -1;
  }

  private buildBindingData(): TodayShortcutBindingData {
    const binding = new TodayShortcutBindingData();
    binding.activityName = this.inputActivityName.trim();
    if (this.selectedTagIndex >= 0 && this.selectedTagIndex < this.tagData.length) {
      const selectedTag = this.tagData[this.selectedTagIndex];
      binding.tagId = selectedTag.id;
      binding.tagName = selectedTag.name;
      binding.tagColor = selectedTag.color;
      binding.tagLightColor = selectedTag.lightColor;
    }
    binding.autoStart = this.isToggleOn;
    return binding;
  }

  private isSaveDisabled(): boolean {
    if (!this.inputActivityName) {
      return true;
    }
    return this.inputActivityName.trim().length === 0;
  }

  private hasSelectedTag(): boolean {
    return this.selectedTagIndex >= 0 && this.selectedTagIndex < this.tagData.length;
  }

  private resolvePreviewTitle(): ResourceStr {
    if (this.inputActivityName && this.inputActivityName.trim().length > 0) {
      return this.inputActivityName.trim();
    }
    return $r('app.string.shortcut_widget_title_fallback');
  }

  private resolvePreviewTagName(): ResourceStr {
    if (!this.hasSelectedTag()) {
      return $r('app.string.shortcut_widget_default_tag');
    }
    return this.tagData[this.selectedTagIndex].name;
  }

  private resolvePreviewTagColor(): ResourceColor {
    if (!this.hasSelectedTag()) {
      return $r('app.color.text_secondary');
    }
    return this.tagData[this.selectedTagIndex].color;
  }

  private resolvePreviewTagLightColor(): ResourceColor {
    if (!this.hasSelectedTag()) {
      return $r('app.color.primary_container');
    }
    return this.tagData[this.selectedTagIndex].lightColor;
  }

  private hasPreviewBinding(): boolean {
    return !this.isSaveDisabled();
  }

  private resolvePreviewActionText(): ResourceStr {
    return '点击后迅速记录该事项'
  }

  private resolvePreviewActionBadgeText(): ResourceStr {
    return this.isToggleOn
      ? $r('app.string.shortcut_widget_action_badge_autostart')
      : $r('app.string.shortcut_widget_action_badge_fill');
  }

  private resolvePreviewTitleMaxLines(): number {
    return this.isCompactPreview() ? 1 : 2;
  }

  private resolveDimensionLabel(): ResourceStr {
    return this.isCompactPreview() ? $r('app.string.shortcut_edit_size_1x2') : $r('app.string.shortcut_edit_size_2x2');
  }

  private isCompactPreview(): boolean {
    return this.formDimension === FORM_DIMENSION_1X2;
  }

  private handleTagClick(index: number): void {
    this.dismissTextInputFocus('tag_click');
    if (this.selectedTagIndex === index) {
      this.selectedTagIndex = -1;
      return;
    }
    this.selectedTagIndex = index;
  }

  private isSelectedTag(index: number): boolean {
    return this.selectedTagIndex === index;
  }

  private dismissTextInputFocus(source: string): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
      hilog.info(DOMAIN, TAG, `today shortcut edit page clear text input focus, source=${source}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG,
        `today shortcut edit page clear text input focus failed, source=${source}, error=${JSON.stringify(error)}`);
    }
  }

  private async handleSaveBinding(): Promise<void> {
    hilog.info(DOMAIN, TAG,
      `today shortcut save click, formId=${this.formId}, formDimension=${this.formDimension}, inputLength=${this.inputActivityName.length}, selectedTagIndex=${this.selectedTagIndex}, autoStart=${this.isToggleOn}`);
    if (this.isSaveDisabled()) {
      hilog.info(DOMAIN, TAG, 'today shortcut save blocked by validation (empty activity name)');
      promptAction.openToast({
        message: $r('app.string.shortcut_edit_page_validation'),
        duration: 1200
      }).catch(() => {
        hilog.error(DOMAIN, TAG, 'today shortcut failed to show validation toast');
      });
      return;
    }

    const context = this.getHostContext();
    if (!context || !this.formId || this.formId.length === 0) {
      hilog.error(DOMAIN, TAG,
        `today shortcut save aborted due invalid context/formId, hasContext=${!!context}, formId=${this.formId}`);
      promptAction.openToast({
        message: $r('app.string.shortcut_edit_page_save_failed'),
        duration: 1200
      }).catch(() => {
        hilog.error(DOMAIN, TAG, 'today shortcut failed to show save failed toast');
      });
      return;
    }

    try {
      const binding = this.buildBindingData();
      hilog.info(DOMAIN, TAG,
        `today shortcut save prepared binding, activityNameLength=${binding.activityName.length}, tagId=${binding.tagId}, autoStart=${binding.autoStart}`);
      const saved = await todayShortcutWidgetService.saveBinding(context, this.formId, binding, this.formDimension);
      hilog.info(DOMAIN, TAG, `today shortcut save binding result, saved=${saved}, formId=${this.formId}`);
      if (!saved) {
        promptAction.openToast({
          message: $r('app.string.shortcut_edit_page_save_failed'),
          duration: 1200
        }).catch(() => {
          hilog.error(DOMAIN, TAG, 'today shortcut failed to show save failed toast');
        });
        return;
      }
      const refreshed = await todayShortcutWidgetService.refreshFormById(context, this.formId, this.formDimension);
      hilog.info(DOMAIN, TAG, `today shortcut refresh form result, refreshed=${refreshed}, formId=${this.formId}`);
      promptAction.openToast({
        message: $r('app.string.shortcut_edit_page_save_success'),
        duration: 1200
      }).catch(() => {
        hilog.error(DOMAIN, TAG, 'today shortcut failed to show save success toast');
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, `today shortcut save binding failed with exception: ${JSON.stringify(error)}`);
      promptAction.openToast({
        message: $r('app.string.shortcut_edit_page_save_failed'),
        duration: 1200
      }).catch(() => {
        hilog.error(DOMAIN, TAG, 'today shortcut failed to show save failed toast');
      });
    }
  }

  private appendEmojiToItemName(emojiChar: string): void {
    this.dismissTextInputFocus('emoji_click');
    this.inputActivityName = `${this.inputActivityName}${emojiChar}`;
    hilog.info(DOMAIN, TAG,
      `today shortcut edit page append emoji, emoji=${emojiChar}, inputLength=${this.inputActivityName.length}`);
  }

  // --- UI Components ---

  @Builder
  private TagChipExpanded(tag: TagModel, index: number): void {
    Column() {
      // Circle Color Indicator
      Column()
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.isSelectedTag(index) ? tag.color : tag.lightColor)
        .border({
          width: this.isSelectedTag(index) ? 3 : 0,
          color: $r('app.color.bg_card')
        })
        .shadow(this.isSelectedTag(index) ? {
          radius: 8,
          color: tag.color,
        } : undefined)
        .animation({ curve: curves.springMotion(0.35, 0.6), duration: 200 })

      // Tag Name
      Text(tag.name)
        .fontSize(12)
        .fontColor(this.isSelectedTag(index) ? tag.color : $r('app.color.text_tertiary'))
        .fontWeight(this.isSelectedTag(index) ? FontWeight.Bold : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.handleTagClick(index);
    })
    .margin({ right: 16 })
  }

  @Builder
  private PreviewHeaderLabel(): void {
    Row() {
      Text($r('app.string.shortcut_widget_header_label'))
        .fontSize($r('app.float.shortcut_widget_header_font_size'))
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Medium)
        .letterSpacing(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private PreviewBoundStateBadge(): void {
    Row() {
      Text($r('app.string.shortcut_widget_bound_badge'))
        .fontSize($r('app.float.shortcut_widget_header_badge_font_size'))
        .fontColor($r('app.color.primary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .padding({
      left: $r('app.float.shortcut_widget_header_badge_padding_horizontal'),
      right: $r('app.float.shortcut_widget_header_badge_padding_horizontal'),
      top: $r('app.float.shortcut_widget_header_badge_padding_vertical'),
      bottom: $r('app.float.shortcut_widget_header_badge_padding_vertical')
    })
    .backgroundColor($r('app.color.primary_lighter'))
    .borderRadius($r('app.float.shortcut_widget_header_badge_radius'))
  }

  @Builder
  private PreviewActionBadge(): void {
    Row() {
      Text(this.resolvePreviewActionBadgeText())
        .fontSize(12)
        .fontColor($r('app.color.primary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
  }

  @Builder
  private PreviewTagRow(): void {
    Row({ space: 5 }) {
      Row({ space: $r('app.float.shortcut_widget_label_gap') }) {
        Column()
          .width($r('app.float.shortcut_widget_status_dot_size'))
          .height($r('app.float.shortcut_widget_status_dot_size'))
          .borderRadius($r('app.float.shortcut_widget_status_dot_radius'))
          .backgroundColor(this.resolvePreviewTagColor());

        Text(this.resolvePreviewTagName())
          .fontSize($r('app.float.shortcut_widget_tag_font_size'))
          .fontColor(this.resolvePreviewTagColor())
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .letterSpacing(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }

      this.PreviewActionBadge();
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private PreviewHeaderRow(): void {
    Row() {
      this.PreviewHeaderLabel();
      this.PreviewBoundStateBadge();
    }
    .width(FULL_PERCENT)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private PreviewEmptyContent(): void {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize($r('app.float.shortcut_widget_plus_icon_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor([$r('app.color.primary')]);
      }
      .backgroundColor($r('app.color.primary_container'))
      .borderRadius('50%')
      .padding($r('app.float.shortcut_widget_badge_padding_vertical'))
      .margin({ bottom: $r('app.float.shortcut_widget_text_gap') })

      Text($r('app.string.shortcut_widget_empty_hint'))
        .fontSize(this.isCompactPreview()
          ? $r('app.float.shortcut_widget_title_compact_font_size')
          : $r('app.float.shortcut_widget_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: $r('app.float.shortcut_widget_label_gap') })

      Column({ space: $r('app.float.shortcut_widget_label_gap') }) {
        Text($r('app.string.shortcut_widget_empty_subtitle_line_1'))
          .textAlign(TextAlign.Center)
          .fontSize($r('app.float.shortcut_widget_hint_secondary_font_size'))
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Text($r('app.string.shortcut_widget_empty_subtitle_line_2'))
          .textAlign(TextAlign.Center)
          .fontSize($r('app.float.shortcut_widget_hint_secondary_font_size'))
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(FULL_PERCENT)
  }

  @Builder
  private PreviewBoundContent(): void {
    Column() {
      Column({ space: $r('app.float.shortcut_widget_text_gap') }) {
        Text(this.resolvePreviewTitle())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(this.resolvePreviewTitleMaxLines())
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Column() {
        this.PreviewTagRow();
        Text(this.resolvePreviewActionText())
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 5 });
      }
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(HorizontalAlign.Start)
    .width(FULL_PERCENT)
    .layoutWeight(1)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private PreviewCard(): void {
    Column() {
      if (this.hasPreviewBinding()) {
        this.PreviewHeaderRow();
      }

      if (this.hasPreviewBinding()) {
        this.PreviewBoundContent();
      } else {
        this.PreviewEmptyContent();
      }
    }
    .width(150)
    .height(150)
    .padding(this.isCompactPreview()
      ? $r('app.float.shortcut_widget_padding_compact')
      : $r('app.float.shortcut_widget_padding'))
    .borderRadius($r('app.float.shortcut_widget_corner_radius'))
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .shadow({
      radius: 45,
      color: 'rgba(0, 0, 0, 0.2)'
    })
    .linearGradient({
      direction: GradientDirection.RightTop,
      colors: [
        [$r('app.color.accent_lighter'), 0],
        [$r('app.color.primary_lighter'), 1]
      ]
    })
  }

  @Builder
  private PreviewSection(): void {
    Column({ space: $r('app.float.shortcut_edit_section_gap') }) {
      // Column({ space: $r('app.float.shortcut_widget_label_gap') }) {
      //   Text($r('app.string.shortcut_edit_page_title'))
      //     .fontSize($r('app.float.shortcut_edit_entry_title_font_size'))
      //     .fontWeight(FontWeight.Bold)
      //     .fontColor($r('app.color.text_primary'));
      //
      //   Text(this.resolveDimensionLabel())
      //     .fontSize($r('app.float.shortcut_edit_preview_title_font_size'))
      //     .fontWeight(FontWeight.Medium)
      //     .fontColor($r('app.color.text_secondary'));
      // }
      // .width(FULL_PERCENT)
      // .alignItems(HorizontalAlign.Start)
      // .padding($r('app.float.shortcut_edit_page_padding'))
      // .backgroundColor($r('app.color.primary_container'))
      // .borderRadius($r('app.float.shortcut_edit_field_radius'))

      Text($r('app.string.shortcut_edit_preview_title'))
        .width(FULL_PERCENT)
        .fontWeight(FontWeight.Bold)
        .fontSize(26)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Start)
        .margin({bottom: 30, top: 5})
        .onClick(() => {
          this.dismissTextInputFocus('preview_title_click');
        })

      this.PreviewCard();
    }
    .width(FULL_PERCENT)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .layoutWeight(1)
    .padding({
      top: $r('app.float.shortcut_edit_page_padding'),
      left: $r('app.float.shortcut_edit_page_padding'),
      right: $r('app.float.shortcut_edit_page_padding')
    })
    .onClick(() => {
      this.dismissTextInputFocus('preview_section_click');
    })
  }

  @Builder
  private InputGroup(): void {
    Column() {
      // Title Input Row
      Row() {
        Text($r('app.string.item_name'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Start)

        TextInput({ text: $$this.inputActivityName, placeholder: $r('app.string.shortcut_edit_name_placeholder') })
          .caretColor($r('app.color.primary'))
          .textAlign(TextAlign.End)
          .placeholderFont({ size: 16 })
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .height(48)
          .padding({right:0})
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Divider()
        .color($r('app.color.neutral_200'))
        .strokeWidth(1)
        .padding({ left: 0, right: 0 })

      // Auto Start Toggle Row
      Row() {
        Column({ space: 4 }) {
          Text($r('app.string.start_directly'))
             .fontSize(16)
             .fontWeight(FontWeight.Medium)
             .fontColor($r('app.color.text_primary'))

          Text($r('app.string.shortcut_edit_autostart_hint'))
             .fontSize(12)
             .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.isToggleOn })
          .selectedColor($r('app.color.primary'))
          .onChange((isOn: boolean) => {
            this.dismissTextInputFocus('toggle_change');
            this.isToggleOn = isOn;
          })
      }
      .width('100%')
      .height(60)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
  }

  @Builder
  private ThemeColorSection(): void {
    Column({ space: 12 }) {
      Text($r('app.string.tag')) // Adjust string if needed, reusing "tag"
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .onClick(() => {
          this.dismissTextInputFocus('tag_title_click');
        })

      List() {
        ForEach(
          this.tagData,
          (tag: TagModel, index: number) => {
            ListItem() {
              this.TagChipExpanded(tag, index);
            }
            .padding(5)
          },
          (tag: TagModel) => tag.id
        )
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(80)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private EmojiSection(): void {
    Column({ space: 12 }) {
      Text($r('app.string.shortcut_edit_emoji_title'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .fontWeight(FontWeight.Medium)
        .width('100%')

      List() {
        ForEach(
          this.emojiData,
          (emoji: EmojiItem) => {
            ListItem() {
              Column() {
                Text(emoji.char)
                  .fontSize(18)
              }
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor($r('app.color.neutral_100'))
              .border({
                width: 1,
                color: $r('app.color.neutral_200')
              })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.appendEmojiToItemName(emoji.char);
              })
            }
            .padding(4)
          },
          (emoji: EmojiItem) => emoji.char
        )
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(48)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private EditorPanel(): void {
    Column() {
      // Handle Bar (Visual cue for bottom sheet)
      Row()
        .width(40)
        .height(4)
        .backgroundColor($r('app.color.neutral_300'))
        .borderRadius(2)
        .margin({ top: 12, bottom: 20 })
        .alignSelf(ItemAlign.Center)

      Column({ space: 12 }) {
        this.InputGroup();
        this.ThemeColorSection();
        this.EmojiSection();
      }
      .width('100%')
      .layoutWeight(1)

      // Save Button
      Button($r('app.string.shortcut_edit_page_save'))
        .width('100%')
        .height(50)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .enabled(!this.isSaveDisabled())
        .fontColor($r('app.color.text_on_primary')) // Assumed white
        .backgroundColor(this.isSaveDisabled() ? $r('app.color.neutral_300') : $r('app.color.primary'))
        .borderRadius(25)
        .shadow(this.isSaveDisabled() ? AppShadows.NONE : AppShadows.ELEVATION_1)
        .onClick(() => {
          this.dismissTextInputFocus('save_click');
          void this.handleSaveBinding();
        })
        .margin({ bottom: 5 })

    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
    .width('100%')
    .height('60%') // Occupy bottom portion
    .backgroundColor($r('app.color.bg_page')) // Slightly different from preview bg?
    .borderRadius({ topLeft: 24, topRight: 24 })
    .padding({ left: 24, right: 24, bottom: 24 })
    .shadow({
       radius: 60,
       color: 'rgba(0,0,0,0.1)',
       offsetY: -10
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // Background
      Column()
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])

        .backgroundColor($r('app.color.panel_bg')) // Use main background

      // Main Content
      Column() {
        this.PreviewSection();
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])

      .width('100%')
      .height('100%')

      // Editor Panel (Bottom Sheet style)
      this.EditorPanel()

    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])

  }
}
