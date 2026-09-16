import { promptAction } from '@kit.ArkUI'
import {
  AppShadows,
  FilesDirCarrier,
  SandboxMediaCopyResult,
  VibratorUtil,
  pickSingleImageUri,
  relPathToImageUri
} from 'base'
import { IdeaPoolService, DEFAULT_IDEA_USER_ID } from '../model/IdeaPoolService'
import { IdeaCollectionCardEntryViewModel } from '../model/IdeaCollectionCardEntryViewModel'
import { IdeaCollectionCardConstants } from '../constants/IdeaCollectionCardConstants'

@Component
export struct IdeaCollectionCard {
  @ObjectLink entry: IdeaCollectionCardEntryViewModel;
  @StorageLink('isDarkTheme') isDarkTheme: boolean = false;
  @State private coverImageUri: string | null = null;
  @State private isUpdatingCover: boolean = false;
  @Prop isInteractionEnabled: boolean = true;
  @Prop isProgressiveBlurEnabled: boolean = true;
  onOpen?: () => void;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  aboutToAppear(): void {
    this.resolveCoverImage();
  }

  private buildSandboxContext(): FilesDirCarrier {
    try {
      const hostContext = this.getUIContext().getHostContext();
      const filesDir = hostContext?.filesDir;
      if (typeof filesDir === 'string' && filesDir.trim().length > 0) {
        return { filesDir: filesDir };
      }
    } catch (_err) {
      // fall through to empty carrier
    }
    return {};
  }

  private resolveCoverImage(): void {
    const coverPath: string | null = this.entry.collection.coverStyle;
    if (coverPath === null || coverPath.trim().length === 0) {
      this.coverImageUri = null;
      return;
    }
    this.coverImageUri = relPathToImageUri(this.buildSandboxContext(), coverPath);
  }

  private hasCoverImage(): boolean {
    return this.coverImageUri !== null;
  }

  private handleContextMenuAppear(): void {
    void this.vibratorUtil.triggerHaptic('haptic.effect.soft', 'touch');
  }

  private resolveIcon(): string {
    const icon: string | null = this.entry.collection.icon;
    return icon !== null && icon.trim().length > 0 ? icon : '📚';
  }

  private resolveTagColor(): ResourceColor {
    return this.entry.collection.tagColorHex ?? $r('app.color.tag_placeholder_gray');
  }

  private resolveTagLightColor(): ResourceColor {
    return this.entry.collection.tagLightColorHex ?? $r('app.color.bg_card');
  }

  private async handlePickCover(): Promise<void> {
    if (this.isUpdatingCover) {
      return;
    }

    let pickedUri: string | null = null;
    try {
      pickedUri = await pickSingleImageUri({
        isSearchSupported: true,
        isPhotoTakingSupported: true
      });
    } catch (_err) {
      promptAction.openToast({ message: $r('app.string.ideapool_cover_picker_failed'), duration: 1200 });
      return;
    }
    if (pickedUri === null || pickedUri.length === 0) {
      return;
    }

    this.isUpdatingCover = true;
    try {
      const saved: SandboxMediaCopyResult | null = await IdeaPoolService.getInstance().updateIdeaCollectionCover(
        DEFAULT_IDEA_USER_ID,
        this.entry.collection.id,
        pickedUri,
        this.buildSandboxContext()
      );
      if (saved === null) {
        promptAction.openToast({ message: $r('app.string.ideapool_cover_save_failed'), duration: 1200 });
        return;
      }
      this.entry.collection.coverStyle = saved.relPath;
      this.coverImageUri = saved.imageUri;
    } finally {
      this.isUpdatingCover = false;
    }
  }

  private async handleResetCover(): Promise<void> {
    if (this.isUpdatingCover) {
      return;
    }

    this.isUpdatingCover = true;
    try {
      const cleared: boolean = await IdeaPoolService.getInstance().clearIdeaCollectionCover(
        DEFAULT_IDEA_USER_ID,
        this.entry.collection.id,
        this.buildSandboxContext()
      );
      if (!cleared) {
        promptAction.openToast({ message: $r('app.string.ideapool_cover_save_failed'), duration: 1200 });
        return;
      }
      this.entry.collection.coverStyle = null;
      this.coverImageUri = null;
      promptAction.openToast({ message: $r('app.string.ideapool_cover_reset_done'), duration: 1200 });
    } finally {
      this.isUpdatingCover = false;
    }
  }

  @Builder
  private collectionCoverMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.ideapool_collection_menu_change_cover') })
        .onClick(() => {
          void this.handlePickCover();
        })
      MenuItem({ content: $r('app.string.ideapool_collection_menu_reset_cover') })
        .enabled(this.hasCoverImage())
        .onClick(() => {
          void this.handleResetCover();
        })
    }
  }

  private resolveTitleShadow(onGlass: boolean): ShadowOptions {
    return {
      radius: onGlass ? $r('app.float.ideapool_collection_cover_text_shadow_radius') : 0,
      type: ShadowType.BLUR,
      color: $r('app.color.cover_glass_text_shadow'),
      offsetX: 0,
      offsetY: 0
    };
  }

  @Builder
  private collectionTitleBar(onGlass: boolean) {
    Text(this.entry.collection.name)
      .fontWeight(600)
      .fontSize($r('app.float.ideapool_collection_title_size'))
      .fontColor($r('app.color.text_primary'))
      .textShadow(this.resolveTitleShadow(onGlass))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })

    Row({ space: $r('app.float.ideapool_collection_count_row_space') }) {
      Row()
        .width($r('app.float.ideapool_collection_count_dot_size'))
        .height($r('app.float.ideapool_collection_count_dot_size'))
        .borderRadius('50%')
        .backgroundColor(this.resolveTagColor())

      Text($r('app.string.ideapool_collection_idea_count', this.entry.ideaCount))
        .fontColor($r('app.color.text_tertiary'))
        .fontSize($r('app.float.ideapool_collection_count_size'))
        .fontWeight(500)
        .textShadow(this.resolveTitleShadow(onGlass))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private defaultLayout() {
    Column() {
      Text(this.resolveIcon())
        .fontSize($r('app.float.ideapool_collection_legacy_icon_size'))
    }
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: $r('app.float.ideapool_collection_legacy_icon_padding'),
      top: $r('app.float.ideapool_collection_legacy_icon_padding')
    })
    .width('100%')
    .layoutWeight(3)
    .backgroundColor(this.resolveTagLightColor())

    Column() {
      this.collectionTitleBar(false)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(2)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({
      left: $r('app.float.ideapool_collection_legacy_bar_padding_h'),
      right: $r('app.float.ideapool_collection_legacy_bar_padding_h'),
      top: $r('app.float.ideapool_collection_legacy_bar_padding_v'),
      bottom: $r('app.float.ideapool_collection_legacy_bar_padding_v')
    })
    .width('100%')
  }

  @Builder
  private coverLayout() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.coverImageUri)
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.Medium)
        .draggable(false)
        .width('100%')
        .height('100%')
        .scale({
          x: IdeaCollectionCardConstants.COVER_IMAGE_SCALE,
          y: IdeaCollectionCardConstants.COVER_IMAGE_SCALE
        })
        .translate({ y: IdeaCollectionCardConstants.COVER_IMAGE_OFFSET_Y })

      if (this.isProgressiveBlurEnabled) {
        // 渐进式毛玻璃层：同一张封面图的拷贝，模糊度从顶部 0% 渐变到底部 100%
        Image(this.coverImageUri)
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .draggable(false)
          .width('100%')
          .height('100%')
          .scale({
            x: IdeaCollectionCardConstants.COVER_IMAGE_SCALE,
            y: IdeaCollectionCardConstants.COVER_IMAGE_SCALE
          })
          .translate({ y: IdeaCollectionCardConstants.COVER_IMAGE_OFFSET_Y })
          .linearGradientBlur(IdeaCollectionCardConstants.COVER_PROGRESSIVE_BLUR_RADIUS, {
            fractionStops: IdeaCollectionCardConstants.COVER_PROGRESSIVE_BLUR_STOPS,
            direction: GradientDirection.Bottom
          })
      }

      // 渐进罩层：顶部全透明，底部带少量灰色托住文字（浅色主题浅灰 / 深色主题深灰，资源自适应）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [$r('app.color.cover_glass_scrim_start'), 0],
            [$r('app.color.cover_glass_scrim_start'), 0.5],
            [$r('app.color.cover_glass_scrim_end'), 0.85],
            [$r('app.color.cover_glass_scrim_end'), 1]
          ]
        })

      Text(this.resolveIcon())
        .fontSize($r('app.float.ideapool_collection_cover_icon_size'))
        .margin({
          left: $r('app.float.ideapool_collection_legacy_icon_padding'),
          top: $r('app.float.ideapool_collection_legacy_icon_padding')
        })

      Column() {
        Column({ space: $r('app.float.ideapool_collection_cover_bar_gap') }) {
          this.collectionTitleBar(true)
        }
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: $r('app.float.ideapool_collection_cover_bar_padding_h'),
          right: $r('app.float.ideapool_collection_cover_bar_padding_h'),
          top: $r('app.float.ideapool_collection_cover_bar_padding_v'),
          bottom: $r('app.float.ideapool_collection_cover_bar_padding_v')
        })
        .width('100%')
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.coverImageUri !== null) {
        this.coverLayout()
      } else {
        this.defaultLayout()
      }
    }
    .backgroundColor($r('app.color.bg_main'))
    .borderRadius($r('app.float.ideapool_collection_card_radius'))
    .clip(true)
    .shadow(this.isDarkTheme ? AppShadows.LIGHT_SHADOW_DARK : AppShadows.LIGHT_SHADOW)
    .renderGroup(true)
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.isInteractionEnabled ? HitTestMode.Default : HitTestMode.None)
    .clickEffect(this.isInteractionEnabled ? { level: ClickEffectLevel.HEAVY, scale: 0.8 } : null)
    .onClick(() => {
      if (this.isInteractionEnabled && this.onOpen) {
        this.onOpen();
      }
    })
    .bindContextMenu(this.collectionCoverMenu, ResponseType.LongPress, {
      onAppear: () => {
        this.handleContextMenuAppear();
      }
    })
  }
}
