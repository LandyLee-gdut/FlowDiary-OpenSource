import display from '@ohos.display';
import deviceInfo from '@ohos.deviceInfo';

const DESIGN_WIDTH_VP: number = 375;
const DEVICE_WIDTH_PX: number = display.getDefaultDisplaySync().width;

/**
 * Converts a design-time vp measurement to a runtime vp value that respects the
 * current device width. This mirrors the calculation used by the mini-calendar
 * reference implementation so sizing stays consistent across phones and tablets.
 */
export function responsiveVp(originSize: number): number {
  if (deviceInfo.deviceType !== 'tablet') {
    return px2vp(DEVICE_WIDTH_PX) / DESIGN_WIDTH_VP * originSize;
  }
  return originSize;
}

export const vp2vp = responsiveVp;
