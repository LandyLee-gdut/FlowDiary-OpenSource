import { VoiceInputState } from '../model/VoiceInputController';
import { VoiceInputBarConstants } from '../constants/VoiceInputBarConstants';
import { curves } from '@kit.ArkUI';

export class VoiceInputOverlayParams {
  voiceState: VoiceInputState;
  interimText: string;
  viewportWidth: number;
  viewportHeight: number;
  barWidth: number;
  barBottomMargin: number;
  visible: boolean;

  constructor(voiceState: VoiceInputState, interimText: string, viewportWidth: number, viewportHeight: number,
    barWidth: number, barBottomMargin: number, visible: boolean) {
    this.voiceState = voiceState;
    this.interimText = interimText;
    this.viewportWidth = viewportWidth;
    this.viewportHeight = viewportHeight;
    this.barWidth = barWidth;
    this.barBottomMargin = barBottomMargin;
    this.visible = visible;
  }
}

@Component
export struct VoiceInputBar {
  @Prop voiceState: VoiceInputState = VoiceInputState.IDLE;
  @Prop interimText: string = '';
  @Prop barWidth: number = 0;
  @Prop barBottomMargin: number = 0;
  @Prop visible: boolean = false;

  private resolveStatusText(): Resource {
    if (this.voiceState === VoiceInputState.REQUESTING_PERMISSION) {
      return $r('app.string.today_voice_input_status_permission');
    }
    if (this.voiceState === VoiceInputState.FINALIZING) {
      return $r('app.string.today_voice_input_status_finalizing');
    }
    return $r('app.string.today_voice_input_status_listening');
  }

  private hasInterimText(): boolean {
    return this.interimText.trim().length > 0;
  }

  build() {
    if (this.visible) {
      // 清亮渐进毛玻璃胶囊：backdropBlur 真实背景模糊（16vp，清透不浑浊）
      // + 金→蓝渐进罩层（背景同色系的高饱和版，半透明透出模糊后的背景）
      Column() {
        Text(this.hasInterimText() ? this.interimText : this.resolveStatusText())
          .width('100%')
          .fontSize($r('app.float.today_voice_input_bar_text_font_size'))
          .fontColor($r('app.color.today_voice_input_bar_text'))
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .padding({
            left: $r('app.float.today_voice_input_bar_padding_h'),
            right: $r('app.float.today_voice_input_bar_padding_h'),
            top: $r('app.float.today_voice_input_bar_padding_v'),
            bottom: $r('app.float.today_voice_input_bar_padding_v')
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
      }
      .width(this.barWidth)
      .justifyContent(FlexAlign.Center)
      .shadow({
        radius: $r('app.float.today_voice_input_bar_shadow_radius'),
        color: $r('app.color.today_add_ball_shadow'),
        offsetX: 0,
        offsetY: $r('app.float.today_voice_input_bar_shadow_offset_y')
      })
      .borderRadius($r('app.float.today_voice_input_bar_border_radius'))
      .clip(true)
      .backdropBlur(VoiceInputBarConstants.BACKDROP_BLUR_RADIUS)
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [
          [$r('app.color.today_voice_glass_gold'), 0],
          [$r('app.color.today_voice_glass_blue'), 1]
        ]
      })
      .constraintSize({
        minHeight: $r('app.float.today_voice_input_bar_min_height')
      })
      .margin({ bottom: this.barBottomMargin })
      .animation({ duration: 250, curve: Curve.EaseOut })
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.5, y: 0.5 }))
        .animation({ curve: curves.springMotion(0.4, 0.7), duration: 250 }))
    }
  }
}

@Builder
export function buildVoiceInputOverlay(params: VoiceInputOverlayParams) {
  Column() {
    VoiceInputBar({
      voiceState: params.voiceState,
      interimText: params.interimText,
      barWidth: params.barWidth,
      barBottomMargin: params.barBottomMargin,
      visible: params.visible
    })
  }
  .width(params.viewportWidth)
  .height(params.viewportHeight)
  .justifyContent(FlexAlign.End)
  .alignItems(HorizontalAlign.Center)
  .hitTestBehavior(HitTestMode.Transparent)
}
