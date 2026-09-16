import {
  AppShadows,
  BreakpointConstants,
  BreakpointType,
  FilesDirCarrier,
  pickSingleImageUri,
  RDBStoreUtil,
  TimeRecordUtil,
  relPathToImageUri,
  resolveStoredPath,
  ColorConversion,
  ImageCacheUtils,
  ColorModeUtil,
  COLOR_MODE_STORAGE_KEY
} from 'base';
import { reflectFlowCardService, ReflectFlowCardItem } from '../model/ReflectFlowCardService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { curves, promptAction } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';

const TAG = 'ReflectFlowCard';
const EXPAND_ANIMATION_CURVE = curves.springMotion(0.45, 0.75);
const EXPAND_ANIMATION_DURATION = 200;
const EXPANDED_CARD_RADIUS = 20;

interface TimeSegment {
  emoji: string;
  label: string;
}

@Component
export struct ReflectFlowCard {
  @Prop @Watch('onItemChanged') item: ReflectFlowCardItem;
  @StorageProp(BreakpointConstants.CURRENT_BREAKPOINT) currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @StorageProp(COLOR_MODE_STORAGE_KEY) @Watch('onColorModeChange') currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State isDarkTheme: boolean = false;

  @State comment: string = '';
  @State coverImageUri: string | null = null;
  @State coverImageLocalPath: string | null = null;
  @State isSavingCoverImage: boolean = false;
  @State applyCardGradient: boolean = false;
  @State applyCardBackground: boolean = false;
  @State cardGradientColors: Array<[string | ResourceColor, number]> = [];
  @State commentDirty: boolean = false;
  @State isSavingComment: boolean = false;

  private imageCacheUtils: ImageCacheUtils | null = null;
  private colorProcessingToken: number = 0;
  private lastSavedComment: string = '';
  private lastSavedActivityId: string = '';
  private commentLoaded: boolean = false;
  private lastProcessedCoverPath: string | null = null;
  private lastProcessedColorMode: number = -1;

  private syncColorModeState(): void {
    this.isDarkTheme = ColorModeUtil.isDarkMode(this.currentColorMode);
  }

  private onColorModeChange(): void {
    this.syncColorModeState();
    this.updateCardVisualStates();
    this.resetBackgroundState();
    void this.processCoverImageForBackground(true);
  }

  private onItemChanged(): void {
    if (!this.item) {
      return;
    }

    if (this.lastSavedActivityId && this.lastSavedActivityId !== this.item.activityId) {
      this.commentLoaded = false;
      this.comment = '';
      this.commentDirty = false;
      this.lastSavedComment = '';
      this.lastSavedActivityId = '';
      this.coverImageUri = null;
      this.coverImageLocalPath = null;
      this.resetBackgroundState();
    }

    this.updateCardVisualStates();
    void this.loadCommentIfNeeded();
    void this.refreshCoverImageBackground();
  }

  async aboutToAppear(): Promise<void> {
    this.syncColorModeState();
    this.updateCardVisualStates();
    this.resetBackgroundState();

    const abilityCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (abilityCtx) {
      this.imageCacheUtils = new ImageCacheUtils(abilityCtx);
    }

    await this.loadComment();
    await this.refreshCoverImageBackground();
  }

  aboutToDisappear(): void {
    void this.promptSaveDialog();
    this.resetBackgroundState();
  }

  private updateCardVisualStates(): void {
    let gradient: Array<[string | ResourceColor, number]> = [];
    let applyGradient = false;
    let applyBackground = false;

    if (this.isDarkTheme) {
      gradient = [];
      applyGradient = false;
      applyBackground = true;
    } else {
      gradient = [
        [$r('app.color.day_review_loading_gradient_start'), 0],
        [$r('app.color.neutral_100'), 0.4],
        [$r('app.color.day_review_loading_gradient_end'), 1],
      ];
      applyGradient = true;
      applyBackground = true;
    }

    this.cardGradientColors = gradient;
    this.applyCardGradient = applyGradient;
    this.applyCardBackground = applyBackground;
  }

  private getCardBaseBackground(): string | ResourceColor {
    if (this.isDarkTheme) {
      return $r('app.color.matter_card_fill');
    }
    return $r('app.color.bg_card');
  }

  private async saveCommentNow(): Promise<void> {
    if (!this.item?.activityId) {
      return;
    }
    if (this.isSavingComment || !this.commentDirty) {
      return;
    }
    this.isSavingComment = true;
    try {
      const currentText = this.comment ?? '';
      const success = await reflectFlowCardService.saveActivityDiary(this.item.activityId, currentText);
      if (success) {
        this.lastSavedActivityId = this.item.activityId;
        this.lastSavedComment = currentText;
        this.commentDirty = false;
        hilog.info(0x0000, TAG, `saveComment success: activityId=${this.item.activityId}, textLength=${currentText.length}`);
        promptAction.openToast({ message: '评论已保存', duration: 1200 });
      } else {
        hilog.error(0x0000, TAG, `saveComment failed: activityId=${this.item.activityId}`);
        promptAction.openToast({ message: '保存失败，请重试', duration: 1200 });
      }
    } finally {
      this.isSavingComment = false;
    }
  }

  private async loadComment(): Promise<void> {
    if (!this.item?.activityId) {
      return;
    }
    if (this.commentLoaded) {
      return;
    }
    const text = await reflectFlowCardService.queryActivityDiary(this.item.activityId);
    this.comment = text;
    this.lastSavedActivityId = this.item.activityId;
    this.lastSavedComment = text;
    this.commentLoaded = true;
    this.commentDirty = false;
    hilog.info(0x0000, TAG, `loadComment success activityId=${this.item.activityId} textLength=${text.length}`);
  }

  private async loadCommentIfNeeded(): Promise<void> {
    if (this.commentLoaded) {
      return;
    }
    await this.loadComment();
  }

  private updateCommentState(value: string): void {
    this.comment = value;
    this.commentDirty = value !== this.lastSavedComment;
  }

  private promptSaveDialog(): void {
    if (!this.commentDirty) {
      return;
    }
    const uiContext = this.getUIContext();
    uiContext.showAlertDialog({
      title: '保存评论',
      message: '有未保存的评论，是否现在保存？',
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '稍后',
        action: () => {
          hilog.info(0x0000, TAG, 'User chose not to save comment yet');
        }
      },
      secondaryButton: {
        value: '保存',
        style: DialogButtonStyle.HIGHLIGHT,
        action: () => {
          void this.saveCommentNow();
        }
      },
      onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
        if (dismissDialogAction.reason === DismissReason.PRESS_BACK
          || dismissDialogAction.reason === DismissReason.TOUCH_OUTSIDE) {
          dismissDialogAction.dismiss();
        }
      }
    });
  }

  private get sandboxContext(): FilesDirCarrier {
    let abilityCtx: common.UIAbilityContext | null = null;
    try {
      abilityCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const filesDir = abilityCtx?.filesDir;
      if (typeof filesDir === 'string' && filesDir.trim().length > 0) {
        hilog.info(0x0000, TAG, 'PhotoPick get context ' + filesDir);
        return { filesDir };
      }
    } catch (_err) {
      abilityCtx = null;
    }

    hilog.error(0x0000, TAG, 'PhotoPick sandboxContext failed to resolve filesDir from UIAbilityContext host context');
    return {};
  }

  private async loadCoverImage(): Promise<void> {
    if (!this.item?.activityId) {
      return;
    }
    try {
      hilog.info(0x0000, TAG, `PhotoPick loadCoverImage start activityId=${this.item.activityId}`);
      const localPath = await RDBStoreUtil.getInstance().queryActivityCoverMediaLocalPath(this.item.activityId);
      hilog.info(0x0000, TAG,
        `PhotoPick loadCoverImage queried localPath=${localPath ?? 'null'} activityId=${this.item.activityId}`);
      this.coverImageLocalPath = localPath;
      if (!localPath) {
        this.coverImageUri = null;
        return;
      }
      const coverUri = relPathToImageUri(this.sandboxContext, localPath);
      this.coverImageUri = coverUri;
      hilog.info(0x0000, TAG,
        `PhotoPick loadCoverImage resolved imageUri=${coverUri ?? 'null'} relPath=${localPath} activityId=${this.item.activityId}`);
    } catch (error) {
      hilog.error(0x0000, TAG, `PhotoPick loadCoverImage failed activityId=${this.item.activityId}: ${JSON.stringify(error)}`);
      this.coverImageUri = null;
      this.coverImageLocalPath = null;
    }
  }

  private async refreshCoverImageBackground(): Promise<void> {
    await this.loadCoverImage();
    await this.processCoverImageForBackground(true);
  }

  private resetBackgroundState(): void {
    this.lastProcessedCoverPath = null;
    this.lastProcessedColorMode = this.currentColorMode;
  }

  private async processCoverImageForBackground(skipLoad: boolean = false): Promise<void> {
    if (!skipLoad) {
      await this.loadCoverImage();
    }

    if (!this.coverImageLocalPath) {
      this.lastProcessedCoverPath = null;
      this.lastProcessedColorMode = this.currentColorMode;
      return;
    }

    if (this.coverImageLocalPath === this.lastProcessedCoverPath
      && this.currentColorMode === this.lastProcessedColorMode ) {
      return;
    }

    const currentToken = ++this.colorProcessingToken;

    try {
      hilog.info(0x0000, TAG,
        `ColorProcess processCoverImageForBackground start activityId=${this.item.activityId} relPath=${this.coverImageLocalPath}`);

      const sandboxPath = resolveStoredPath(this.sandboxContext, this.coverImageLocalPath);

      if (!sandboxPath || sandboxPath.trim().length === 0) {
        hilog.warn(0x0000, TAG,
          `ColorProcess processCoverImageForBackground no sandbox path activityId=${this.item.activityId} relPath=${this.coverImageLocalPath}`);
        this.lastProcessedCoverPath = null;
        this.lastProcessedColorMode = this.currentColorMode;
        return;
      }

      if (this.imageCacheUtils && !this.imageCacheUtils.imageExists(sandboxPath)) {
        hilog.warn(0x0000, TAG,
          `ColorProcess processCoverImageForBackground sandbox image not found activityId=${this.item.activityId} path=${sandboxPath}`);
        this.lastProcessedCoverPath = null;
        this.lastProcessedColorMode = this.currentColorMode;
        return;
      }

      const imageSource = image.createImageSource(sandboxPath);
      const pixelMap = await imageSource.createPixelMap();

      if (!pixelMap) {
        hilog.warn(0x0000, TAG,
          `ColorProcess processCoverImageForBackground failed to create pixelMap activityId=${this.item.activityId}`);
        this.lastProcessedCoverPath = null;
        this.lastProcessedColorMode = this.currentColorMode;
        return;
      }

      if (currentToken !== this.colorProcessingToken) {
        hilog.info(0x0000, TAG,
          `ColorProcess processCoverImageForBackground cancelled by newer request activityId=${this.item.activityId}`);
        pixelMap.release();
        return;
      }

      // const colorPicker = await effectKit.createColorPicker(pixelMap, [0, 0, 1, 1]);

      if (currentToken !== this.colorProcessingToken) {
        hilog.info(0x0000, TAG,
          `ColorProcess processCoverImageForBackground color picker cancelled activityId=${this.item.activityId}`);
        pixelMap.release();
        return;
      }

      // const color = colorPicker.getAverageColor();
      // const colorArr = ColorConversion.dealColor(color.red, color.green, color.blue);
      // this.blurColor = `rgba(${colorArr[0]}, ${colorArr[1]}, ${colorArr[2]}, 0.3)`;
      this.lastProcessedCoverPath = this.coverImageLocalPath;
      this.lastProcessedColorMode = this.currentColorMode;
      pixelMap.release();
    } catch (error) {
      hilog.error(0x0000, TAG,
        `ColorProcess processCoverImageForBackground failed activityId=${this.item.activityId}: ${JSON.stringify(error)}`);
      this.lastProcessedCoverPath = null;
      this.lastProcessedColorMode = this.currentColorMode;
    }
  }

  private async openPhotoPicker(): Promise<void> {
    if (this.isSavingCoverImage) {
      hilog.warn(0x0000, TAG, `PhotoPick openPhotoPicker ignored: already saving activityId=${this.item.activityId}`);
      return;
    }

    hilog.info(0x0000, TAG, `PhotoPick openPhotoPicker activityId=${this.item.activityId}`);

    let pickedUri: string | null = null;
    try {
      pickedUri = await pickSingleImageUri({
        isSearchSupported: true,
        isPhotoTakingSupported: true
      });
    } catch (error) {
      hilog.error(0x0000, TAG, `PhotoPick openPhotoPicker failed: ${JSON.stringify(error)}`);
      promptAction.openToast({ message: '打开相册失败', duration: 1200 });
      return;
    }

    if (!pickedUri) {
      hilog.info(0x0000, TAG, `PhotoPick openPhotoPicker cancelled activityId=${this.item.activityId}`);
      return;
    }

    this.isSavingCoverImage = true;
    try {
      hilog.info(0x0000, TAG, `PhotoPick save cover start activityId=${this.item.activityId} uri=${pickedUri}`);
      const result = await reflectFlowCardService.replaceActivityCoverImage(this.item.activityId, pickedUri, this.sandboxContext);
      if (!result) {
        hilog.error(0x0000, TAG,
          `PhotoPick save cover failed: replaceActivityCoverImage returned null activityId=${this.item.activityId}`);
        promptAction.openToast({ message: '保存图片失败', duration: 1200 });
        return;
      }
      this.coverImageLocalPath = result.relPath;
      this.coverImageUri = result.imageUri;
      void this.processCoverImageForBackground();
    } finally {
      this.isSavingCoverImage = false;
    }
  }

  @Builder
  private buildReviewActionBar() {
    Row({ space: 12 }) {
      // TODO: 分享功能待后续版本开放权限
      // this.buildReviewActionButton($r('sys.symbol.share'), () => {
      //   promptAction.openToast({ message: '分享功能即将上线', duration: 800 });
      // });

      Button({ stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.save'))
          .fontSize(20)
          .fontWeight(600)
          .fontColor([this.commentDirty && !this.isSavingComment ? $r('app.color.primary') : $r('app.color.text_disabled')]);
      }
      .type(ButtonType.Circle)
      .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_INTERACTIVE)
      .backgroundColor(this.commentDirty && !this.isSavingComment
        ? $r('app.color.matter_card_secondary_button_bg')
        : $r('app.color.neutral_200'))
      .onClick(() => {
        if (this.isSavingComment) {
          return;
        }
        if (!this.commentDirty) {
          promptAction.openToast({ message: $r('app.string.reflect_comment_no_save'), duration: 1200 });
          return;
        }
        void this.saveCommentNow();
      })
      .height(40)
      .width(40)
      .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_INTERACTIVE)

      // TODO: 删除功能待后续版本开放权限
      // this.buildReviewActionButton($r('sys.symbol.trash'), () => {
      //   promptAction.openToast({ message: '删除功能即将上线', duration: 800 });
      // });
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }

  @Builder
  private buildReviewActionButton(
    label: Resource,
    onClick: () => void,
    backgroundColor?: string | ResourceColor,
    fontColor?: ResourceColor[]
  ) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(label as Resource)
        .fontSize(20)
        .fontWeight(600)
        .fontColor(fontColor ?? [$r('app.color.text_primary')]);
    }
    .onClick(onClick)
    .width(40)
    .height(40)
    .backgroundColor(backgroundColor ?? $r('app.color.neutral_200'))
    // .backgroundBlurStyle(BlurStyle.BACKGROUND_REGULAR)
    .shadow(this.isDarkTheme ? AppShadows.CARD_RESTING_DARK : AppShadows.CARD_INTERACTIVE)
  }

  @Builder
  private buildMetaTitleRow() {

    Row() {
      Row() {
        Text(this.getTitleRowText())
          .fontSize(13)
          .fontWeight(500)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION });
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.bg_main'))
      .borderRadius(14)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center);
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .width('100%');
  }

  build() {
    Column({ space: 24 }) {
      Row() {
        Column({ space: 8 }) {
          this.buildMetaTitleRow();

          Text(this.item.title)
            .fontWeight(700)
            .fontSize(this.getTitleFontSize())
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .margin({ top: this.getTitleTopMargin() })
            .fontColor($r('app.color.neutral_800'))
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION });

          Text(TimeRecordUtil.formatDuration(this.item.durationInMilliseconds))
            .fontSize(this.getDurationFontSize())
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION });

          Row({ space: 8 }) {
            Row()
              .width(7)
              .height(7)
              .borderRadius('50%')
              .backgroundColor(this.item.labelColor)
              .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION });
            Text(this.item.label)
              .fontSize(12)
              .fontWeight(500)
              .fontColor($r('app.color.text_secondary'))
              .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION });
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.bg_main'))
          .borderRadius(14)
          .alignItems(VerticalAlign.Center)
          .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION });

          if (this.item.timeRangeLabel) {
            Row() {
              Text(this.item.timeRangeLabel)
                .fontSize(14)
                .fontWeight(500)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .animation({ curve: EXPAND_ANIMATION_CURVE, duration: EXPAND_ANIMATION_DURATION });
            }
            .margin({ top: 8 })
            .width('100%')
            .justifyContent(FlexAlign.Center);
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.SpaceBetween)
        .flexGrow(1)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Top)
      .padding({ top: 20 });

      Column() {
        Stack({ alignContent: Alignment.Center }) {
          if (this.coverImageUri) {
            Image(this.coverImageUri)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover);
          }
          if (!this.coverImageUri) {
            Row() {
              Text('添加图片')
                .fontSize(14)
                .fontWeight(500)
                .fontColor($r('app.color.text_disabled'));
            }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(12)
            .backgroundColor(Color.Transparent)
            .align(Alignment.Center);
          }
        }
        .width('100%')
        .height('75%')
        .backgroundColor($r('app.color.neutral_100'))
        .borderRadius(16)
        .clip(true)
        .onClick(() => {
          void this.openPhotoPicker();
        });

        Column() {
          TextArea({ placeholder: '记录此刻的感受...', text: this.comment })
            .placeholderFont({
              weight: 500,
              size: 16,
            })
            .onAppear(() => {
              hilog.info(0x0000, TAG,
                `TextArea onAppear activityId=${this.item.activityId} commentLoaded=${this.commentLoaded} commentLength=${this.comment.length}`);
            })
            .onChange((value: string) => {
              this.updateCommentState(value);
            })
            // .onEditChange((isEditing: boolean) => {
            //   if (!isEditing) {
            //     this.promptSaveDialog();
            //   }
            // })
            .maxLines(4)
            .placeholderColor($r('app.color.text_tertiary'))
            .fontSize(16)
            .fontWeight(500)
            .fontColor($r('app.color.neutral_800'))
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.bg_card'))
            .width('100%')
            .height('100%');
        }
        .padding({ top: 5 })
        .width('100%')
        .height('25%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(16);
      }
      .rotate({
        angle: 3,
        centerX: '50%',
        centerY: '50%'
      })
      .padding(10)
      .width('90%')
      .height(280)
      .borderRadius(26)
      .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : {
        radius: 50,
        offsetX: 0,
        offsetY: 8,
        color: 'rgba(31, 35, 38, 0.2)'
      })
      .backgroundColor(this.getCardBaseBackground())

      this.buildReviewActionBar();
    }
    .clickEffect({ level: ClickEffectLevel.HEAVY, scale: 1 })
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: this.getCardPadding(), right: this.getCardPadding(), top: 24, bottom: 32 })
    .borderRadius(EXPANDED_CARD_RADIUS)
    .backgroundColor(this.getCardBaseBackground())
    .backgroundImage(this.coverImageUri)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .backgroundImageSize(ImageSize.Cover)
    .shadow(this.isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_INTERACTIVE);
  }

  private getCardPadding(): number {
    return new BreakpointType<number>({
      sm: 14,
      md: 16,
      lg: 20
    }).getValue(this.currentBreakpoint);
  }

  private getTitleFontSize(): number {
    return new BreakpointType<number>({
      sm: 28,
      md: 30,
      lg: 32
    }).getValue(this.currentBreakpoint);
  }

  private getTitleTopMargin(): number {
    return new BreakpointType<number>({
      sm: 12,
      md: 15,
      lg: 18
    }).getValue(this.currentBreakpoint);
  }

  private getDurationFontSize(): number {
    return new BreakpointType<number>({
      sm: 48,
      md: 55,
      lg: 60
    }).getValue(this.currentBreakpoint);
  }

  private formatMonthDay(timestamp: number): string {
    if (!timestamp || timestamp <= 0) {
      return '';
    }
    const date = new Date(timestamp);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    return `${month}月${day}日`;
  }

  private getTimeSegment(timestamp: number): TimeSegment {
    const date = new Date(timestamp);
    const minutes = date.getHours() * 60 + date.getMinutes();

    // 午夜: 00:00 - 04:59
    if (minutes >= 0 && minutes < 5 * 60) {
      return { emoji: '🌙', label: '午夜' } as TimeSegment;
    }
    // 清晨: 05:00 - 08:59
    if (minutes >= 5 * 60 && minutes < 9 * 60) {
      return { emoji: '🌅', label: '清晨' } as TimeSegment;
    }
    // 上午: 09:00 - 11:29
    if (minutes >= 9 * 60 && minutes < (11 * 60 + 30)) {
      return { emoji: '🌤️', label: '上午' } as TimeSegment;
    }
    // 中午: 11:30 - 13:29
    if (minutes >= (11 * 60 + 30) && minutes < (13 * 60 + 30)) {
      return { emoji: '🌞', label: '中午' } as TimeSegment;
    }
    // 下午: 13:30 - 17:59
    if (minutes >= (13 * 60 + 30) && minutes < 18 * 60) {
      return { emoji: '🍃', label: '下午' } as TimeSegment;
    }
    // 晚上: 18:00 - 23:59
    return { emoji: '🌙', label: '晚上' } as TimeSegment;
  }

  private getTitleRowText(): string {
    const ts = this.item?.latestStartTimeMs ?? 0;
    const dateLabel = this.formatMonthDay(ts);
    const segment: TimeSegment | null = ts > 0 ? this.getTimeSegment(ts) : null;
    const timeLabel = ts > 0 ? TimeRecordUtil.formatToHHmm(ts) : '';

    const parts: string[] = [];
    if (dateLabel) {
      parts.push(dateLabel);
    }
    if (segment) {
      parts.push(`${segment.emoji} ${segment.label}`);
    }
    if (timeLabel) {
      parts.push(timeLabel);
    }
    return parts.join(' · ');
  }
}
