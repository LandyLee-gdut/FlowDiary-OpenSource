import { IdeaPoolUserGuide } from "./IdeaPoolUserGuide"
import { TodayUserGuide } from "./TodayUserGuide"
import { BreakpointConstants, BreakpointSystem, BreakpointType, VibratorUtil } from 'base'
import { ReflectUserGuide } from "./ReflectUserGuide";
import { UserGuideEndPage } from "./UserGuideEndPage";

@Component
export struct UserGuideView {
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @StorageLink('userGuideSheetVisible') userGuideSheetVisible: boolean = false;
  @State private currentGuideIndex: number = 0;
  private readonly swiperController: SwiperController = new SwiperController();
  private readonly goToIdeaGuide: () => void = () => this.switchGuidePage(1);
  private readonly goToReflectGuide: () => void = () => this.switchGuidePage(2);
  private readonly goToEndPage: () => void = () => this.switchGuidePage(3);

  aboutToAppear() {
    this.breakpointSystem.register();
    this.userGuideSheetVisible = true;
    this.currentGuideIndex = 0;
    AppStorage.setOrCreate('guideActiveIndex', this.currentGuideIndex);
  }

  aboutToDisappear(): void {
    this.breakpointSystem.unregister()
    this.userGuideSheetVisible = false;
    AppStorage.setOrCreate('guideActiveIndex', 0);
  }

  private switchGuidePage(targetIndex: number): void {
    if (targetIndex === this.currentGuideIndex) {
      return;
    }
    this.currentGuideIndex = targetIndex;
    AppStorage.setOrCreate('guideActiveIndex', targetIndex);
    this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch')
    this.swiperController.changeIndex(targetIndex, SwiperAnimationMode.DEFAULT_ANIMATION)
    // this.swiperController.show(targetIndex);
  }

  build() {
    Column() {
      Swiper(this.swiperController) {
        TodayUserGuide({ onContinue: this.goToIdeaGuide, isActive: this.currentGuideIndex === 0 })

        IdeaPoolUserGuide({ onContinue: this.goToReflectGuide, isActive: this.currentGuideIndex === 1 })

        ReflectUserGuide({ onContinue: this.goToEndPage, isActive: this.currentGuideIndex === 2 })

        UserGuideEndPage()
      }
      .linearGradient({
        direction: GradientDirection.Top,
        colors: [
          [$r('app.color.accent_lighter'), .0],
          [$r('app.color.primary_lighter'), 1],
        ]
      })
      .indicator(false)
      .index(this.currentGuideIndex)
      .onChange((index: number) => {
        this.currentGuideIndex = index;
        AppStorage.setOrCreate('guideActiveIndex', index);
      })
      .height('100%')
      .width('100%')
    }
    .height('100%')
    .width('100%')
  }
}
