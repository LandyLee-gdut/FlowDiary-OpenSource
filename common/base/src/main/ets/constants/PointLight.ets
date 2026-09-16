import { hdsEffect } from '@kit.UIDesignKit';

export type PointLightPreset =
  | 'fabTouch'
  | 'buttonTouch'
  | 'cardTouch'
  | 'cardActive'
  | 'selection'
  | 'swipeAction';

export interface PointLightOverrides {
  height?: number;
  intensity?: number;
  bloom?: number;
  color?: ResourceColor;
  illuminatedType?: hdsEffect.PointLightIlluminatedType;
}

export interface PointLightEffectOptions {
  preset: PointLightPreset;
  color: ResourceColor;
  illuminatedType: hdsEffect.PointLightIlluminatedType;
  isActive: boolean;
  isDarkTheme: boolean;
  overrides?: PointLightOverrides;
}

export interface PointLightResolvedProfile {
  color: ResourceColor;
  illuminatedType: hdsEffect.PointLightIlluminatedType;
  height: number;
  intensity: number;
  bloom: number;
}

const DARK_POINT_LIGHT_INTENSITY = 0.68;
const DARK_POINT_LIGHT_BLOOM = 0.26;
const LIGHT_POINT_LIGHT_INTENSITY = 0.98;
const LIGHT_POINT_LIGHT_BLOOM = 0.26;

function resolvePointLightPresetHeight(preset: PointLightPreset): number {
  switch (preset) {
    case 'fabTouch':
      return 120;
    case 'buttonTouch':
      return 120;
    case 'cardTouch':
      return 120;
    case 'cardActive':
      return 150;
    case 'selection':
      return 150;
    case 'swipeAction':
      return 120;
    default:
      return 120;
  }
}

export function resolvePointLightProfile(options: PointLightEffectOptions): PointLightResolvedProfile {
  const overrides: PointLightOverrides = options.overrides ?? {};
  const resolvedColor: ResourceColor = overrides.color ?? options.color;
  const resolvedIlluminatedType: hdsEffect.PointLightIlluminatedType =
    overrides.illuminatedType ?? options.illuminatedType;

  if (!options.isActive) {
    return {
      color: resolvedColor,
      illuminatedType: resolvedIlluminatedType,
      height: 0,
      intensity: 0,
      bloom: 0
    };
  }

  const resolvedHeight: number = overrides.height ?? resolvePointLightPresetHeight(options.preset);
  const resolvedIntensity: number = overrides.intensity ??
    (options.isDarkTheme ? DARK_POINT_LIGHT_INTENSITY : LIGHT_POINT_LIGHT_INTENSITY);
  const resolvedBloom: number = overrides.bloom ??
    (options.isDarkTheme ? DARK_POINT_LIGHT_BLOOM : LIGHT_POINT_LIGHT_BLOOM);

  return {
    color: resolvedColor,
    illuminatedType: resolvedIlluminatedType,
    height: resolvedHeight,
    intensity: resolvedIntensity,
    bloom: resolvedBloom
  };
}

export function buildPointLightEffect(options: PointLightEffectOptions): VisualEffect {
  const resolved: PointLightResolvedProfile = resolvePointLightProfile(options);
  return new hdsEffect.HdsEffectBuilder()
    .pointLight({
      illuminatedType: resolved.illuminatedType,
      options: {
        color: resolved.color,
        height: resolved.height,
        intensity: resolved.intensity,
        bloom: resolved.bloom
      }
    })
    .buildEffect();
}
