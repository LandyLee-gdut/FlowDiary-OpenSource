import { curves } from '@kit.ArkUI';

export const REFLECT_CHART_SETTINGS_TOGGLE_DURATION: number = 180;
export const REFLECT_CHART_SETTINGS_REORDER_DURATION: number = 240;
export const REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION: NavigationSystemTransitionType =
  NavigationSystemTransitionType.SLIDE_RIGHT;
export const REFLECT_CHART_SETTINGS_HIDDEN_OPACITY: number = 0.56;
export const REFLECT_CHART_SETTINGS_DRAGGING_SCALE: number = 1.04;
export const REFLECT_CHART_SETTINGS_DRAG_SHADOW_RADIUS: number = 40;
export const REFLECT_CHART_SETTINGS_DRAG_SHADOW_LIGHT_COLOR: string = '#33000000';
export const REFLECT_CHART_SETTINGS_DRAG_SHADOW_DARK_COLOR: string = '#66000000';

export function reflectChartSettingsSpringCurve() {
  return curves.springMotion(0.52, 0.84);
}
