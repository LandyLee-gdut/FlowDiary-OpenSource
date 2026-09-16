import { BreakpointConstants } from '../constants/BreakpointConstants';
import { BreakpointType } from '../utils/BreakpointSystem';

const BASE_SHEET_HEIGHT: BreakpointType<number> = new BreakpointType<number>({ sm: 180, md: 180, lg: 180 });
const TAG_HEIGHT_INCREMENT: BreakpointType<number> = new BreakpointType<number>({ sm: 30, md: 30, lg: 30 });
const EMOJI_GRID_HEIGHT: BreakpointType<number> = new BreakpointType<number>({ sm: 160, md: 160, lg: 160 });
const EMOJI_SAFE_AREA_PADDING: BreakpointType<number> = new BreakpointType<number>({ sm: 10, md: 12, lg: 14 });
const SHEET_HEIGHT_RATIO: BreakpointType<number> = new BreakpointType<number>({ sm: 0.92, md: 0.82, lg: 0.72 });

export const DEFAULT_SHEET_HEIGHT: number = calculateSheetHeight(0);

function resolveBreakpoint(breakpoint?: string): string {
  return breakpoint ?? BreakpointConstants.BREAKPOINT_SM;
}

function getTagsPerRow(breakpoint?: string): number {
  switch (breakpoint) {
    case BreakpointConstants.BREAKPOINT_MD:
      return 6;
    case BreakpointConstants.BREAKPOINT_LG:
      return 6;
    case BreakpointConstants.BREAKPOINT_SM:
    default:
      return 5;
  }
}

function getBaseHeight(breakpoint: string): number {
  return BASE_SHEET_HEIGHT.getValue(breakpoint);
}

function getTagIncrement(breakpoint: string): number {
  return TAG_HEIGHT_INCREMENT.getValue(breakpoint);
}

function getEmojiGridHeight(breakpoint: string): number {
  return EMOJI_GRID_HEIGHT.getValue(breakpoint);
}

function getSafeAreaPadding(breakpoint: string): number {
  return EMOJI_SAFE_AREA_PADDING.getValue(breakpoint);
}

function getMaxSheetRatio(breakpoint: string): number {
  return SHEET_HEIGHT_RATIO.getValue(breakpoint);
}

export function calculateSheetHeight(tagCount: number, breakpoint?: string, viewportHeight?: number): number {
  const resolvedBreakpoint = resolveBreakpoint(breakpoint);
  const tagsPerRow = getTagsPerRow(resolvedBreakpoint);
  const safeCount = tagCount > 0 ? tagCount + 1 : 0;
  const occupiedRows = safeCount === 0 ? 0 : Math.ceil(safeCount / tagsPerRow);
  const contentHeight = getBaseHeight(resolvedBreakpoint) + occupiedRows * getTagIncrement(resolvedBreakpoint) +
    getEmojiGridHeight(resolvedBreakpoint) + getSafeAreaPadding(resolvedBreakpoint);

  if (viewportHeight && viewportHeight > 0) {
    const maxAllowed = viewportHeight * getMaxSheetRatio(resolvedBreakpoint);
    return Math.min(contentHeight, maxAllowed);
  }

  return contentHeight;
}
