import { hdsEffect } from '@kit.UIDesignKit';

const FLOW_SOURCE_COLORS: ResourceColor[] = [
  $r('app.color.flow_background_top'),
  $r('app.color.flow_blue_soft'),
  $r('app.color.flow_yellow_soft'),
  $r('app.color.flow_blue_mist')
];

const FLOW_TARGET_COLORS: ResourceColor[] = [
  $r('app.color.flow_background_bottom'),
  $r('app.color.flow_blue_light'),
  $r('app.color.flow_yellow_light'),
  $r('app.color.flow_yellow_mist')
];

export interface FlowLightColors {
  colorSource: ResourceColor[];
  colorTarget: ResourceColor[];
}

export function buildFlowLightEffect(
  controller: hdsEffect.ShaderEffectController,
  colors?: FlowLightColors
): VisualEffect {
  const colorSource: ResourceColor[] = colors?.colorSource ?? FLOW_SOURCE_COLORS;
  const colorTarget: ResourceColor[] = colors?.colorTarget ?? FLOW_TARGET_COLORS;
  return new hdsEffect.HdsEffectBuilder()
    .shaderEffect({
      effectType: hdsEffect.EffectType.UV_BACKGROUND_FLOW_LIGHT,
      controller: controller,
      animation: {
        duration: 3000,
        iterations: -1,
        autoPlay: true,
        curve: Curve.Linear,
        expectedFrameRateRange: {
          expected: hdsEffect.FrameRateType.FRAME_RATE_30,
          min: hdsEffect.FrameRateType.FRAME_RATE_15,
          max: hdsEffect.FrameRateType.FRAME_RATE_30
        }
      },
      params: {
        colorSource: colorSource,
        colorTarget: colorTarget
      }
    })
    .buildEffect();
}
