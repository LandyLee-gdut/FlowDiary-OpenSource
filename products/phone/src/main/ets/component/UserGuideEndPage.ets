import { BreakpointConstants, BreakpointSystem, BreakpointType, VibratorUtil, PreferenceKeys, preferencesUtil } from 'base'
import { curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Component
export struct UserGuideEndPage {
  @StorageLink('showUserGuide') showUserGuide: boolean = false;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  
  aboutToAppear(): void {
    this.breakpointSystem.register();
  }

  aboutToDisappear(): void {
    this.breakpointSystem.unregister()
  }

  /**
   * 处理开始按钮点击事件
   * 包含触觉反馈和回调执行
   */
  private handleStartClick(): void {
    // 触觉反馈
    this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');

    this.showUserGuide = false;
    // Persist the user's choice so the guide won't show again
    try {
      const prefStore = preferencesUtil.getPreferences();
      if (prefStore) {
        prefStore.putSync(PreferenceKeys.SHOW_USER_GUIDE, false);
        if (preferencesUtil.requiresManualFlush()) {
          preferencesUtil.flush();
        }
        hilog.info(0x0000, 'UserGuideEndPage', '[UserGuide] Persisted showUserGuide=false');
      }
    } catch (err) {
      hilog.warn(0x0000, 'UserGuideEndPage', `Failed to persist showUserGuide preference: ${JSON.stringify(err)}`);
    }
  }

  build() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text('「FlowDiary 流光」')
          .fontSize(30)
          .fontColor($r('app.color.primary'))
          .fontWeight(600)
          .transition(TransitionEffect.translate({ y: 260 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1400 }))
        Text('欢迎使用')
          .fontColor($r('app.color.text_tertiary'))
          .fontSize(16)
          .transition(TransitionEffect.translate({ y: 320 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1400 }))
      }
      .height(50)
      .offset({ y: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 20 })
      .alignItems(HorizontalAlign.Center)

      Column() {
        Image($r('app.media.startIcon'))
          .width(120)
          .height(120)
          .objectFit(ImageFit.Contain)
          .transition(TransitionEffect.translate({ y: 350 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1500 }))

        Text('*我们会在事项记录时使用数据传输接口以保证流光在后台运行')
          .fontColor($r('app.color.text_tertiary'))
          .fontSize(14)
          .width('80%')
          .margin({ top: 30,  bottom: 5 })
          .textAlign(TextAlign.Center)
          .transition(TransitionEffect.translate({ y: 320 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1400 }))

        Text('请您放心，您的所有数据都在本地存储，没有任何数据向外部传输')
          .fontColor($r('app.color.text_tertiary'))
          .fontSize(14)
          .width('80%')
          .textAlign(TextAlign.Center)
          .transition(TransitionEffect.translate({ y: 320 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1400 }))
      }
      .height(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 350 : 150)
      .justifyContent(FlexAlign.Center)
      .width('90%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 30, bottom: 30})

      Column({ space: 8 }) {
      }
      .justifyContent(FlexAlign.End)
      .height(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 65 : 55)
      .alignItems(HorizontalAlign.Center)
      .margin({
        bottom: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 20,
      })

      Button('开始使用')
        .onClick(() => {
          this.handleStartClick();
        })
        .backgroundColor($r('app.color.primary'))
        .transition(TransitionEffect.translate({ y: 500 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 200 }))
        .width('60%')
        .fontColor($r('app.color.neutral_100'))
        .padding({ top: 8, right: 24, bottom: 8, left: 24 })
        // .margin({ top: 30 })
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
