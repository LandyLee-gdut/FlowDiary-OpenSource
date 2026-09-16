// /common/theme/AppShadows.ts
import { AppColors } from './Color';

/**
 * Defines a hierarchical shadow system for the application to create a consistent sense of depth and elevation.
 * Due to ArkTS limitations (one shadow layer per modifier), each shadow is meticulously crafted
 * to simulate realistic lighting for its intended elevation level.
 *
 * Elevation Levels:
 * - LEVEL_0: No shadow. For elements flush with the surface.
 * - LEVEL_1 (Resting): Default shadow for static cards. Subtle and clean.
 * - LEVEL_2 (Interactive): For cards on hover or focus. A slight "lift" effect.
 * - LEVEL_3 (Floating): For primary floating elements like a FAB, indicating highest elevation.
 */
export class AppShadows {

  /**
   * ELEVATION 1: Standard Card Resting Shadow
   * Darker, tighter, and with a more pronounced offset than typical Material Design shadows.
   * This gives the card a sense of weight and substance.
   */
  static readonly ELEVATION_1: ShadowOptions = {
    radius: 12,
    offsetX: 0,
    offsetY: 6,
    color: 'rgba(0, 0, 0, 0.15)' // Noticeably darker and less transparent
  };
  static readonly ELEVATION_1_DARK: ShadowOptions = {
    radius: 12,
    offsetX: 0,
    offsetY: 6,
    color: 'rgba(0, 0, 0, 0.35)' // Higher alpha keeps depth on dark surfaces
  };

  /**
   * ELEVATION 2: Raised Card / Modal Shadow
   * Used for elements that need to feel more prominent, like modals or interactive pop-ups.
   */
  static readonly ELEVATION_2: ShadowOptions = {
    radius: 20,
    offsetX: 0,
    offsetY: 10,
    color: 'rgba(0, 0, 0, 0.20)'
  };
  static readonly ELEVATION_2_DARK: ShadowOptions = {
    radius: 20,
    offsetX: 0,
    offsetY: 10,
    color: 'rgba(0, 0, 0, 0.45)'
  };

  /**
   * ELEVATION 3: Primary Floating Element (e.g., FAB)
   * The deepest and most defined shadow, reserved for the highest-level interactive elements.
   * It's not just a blur; it's a statement of importance.
   */
  static readonly ELEVATION_3: ShadowOptions = {
    radius: 25,
    offsetX: 0,
    offsetY: 12,
    color: 'rgba(0, 0, 0, 0.25)' // A strong, confident shadow
  };
  static readonly ELEVATION_3_DARK: ShadowOptions = {
    radius: 25,
    offsetX: 0,
    offsetY: 12,
    color: 'rgba(0, 0, 0, 0.55)'
  };

  /**
   * LEVEL 0: No shadow. Used to remove shadows or for flat elements.
   */
  static readonly NONE: ShadowOptions = {
    radius: 0,
    offsetX: 0,
    offsetY: 0,
    color: 'transparent'
  };

  /**
   * LEVEL 1: RESTING CARD SHADOW
   * The default shadow for all cards. It's subtle, suggesting the card is slightly raised.
   * Simulates a soft, ambient light.
   */
  static readonly CARD_RESTING: ShadowOptions = {
    radius: 16,
    offsetX: 0,
    offsetY: 4,
    color: 'rgba(31, 35, 38, 0.06)' // A very subtle, neutral dark color
  };
  static readonly CARD_RESTING_DARK: ShadowOptions = {
    radius: 16,
    offsetX: 0,
    offsetY: 4,
    color: 'rgba(0, 0, 0, 0.30)'
  };

  /**
   * LEVEL 2: INTERACTIVE CARD SHADOW (HOVER/PRESS)
   * A more pronounced shadow to indicate interaction. The card appears to lift up.
   * This should be used with an animation for a smooth transition.
   */
  static readonly CARD_INTERACTIVE: ShadowOptions = {
    radius: 24,
    offsetX: 0,
    offsetY: 8,
    color: 'rgba(31, 35, 38, 0.08)' // Slightly darker to enhance the lift effect
  };
  static readonly CARD_INTERACTIVE_DARK: ShadowOptions = {
    radius: 24,
    offsetX: 0,
    offsetY: 8,
    color: 'rgba(0, 0, 0, 0.40)'
  };

  /**
   * LEVEL 3: FLOATING ACTION BUTTON (FAB) SHADOW
   * The strongest shadow, reserved for the highest elevation element like the FAB.
   * It creates a clear separation and sense of importance.
   */
  static readonly FAB: ShadowOptions = {
    radius: 32,
    offsetX: 0,
    offsetY: 12,
    color: 'rgba(0, 99, 230, 0.25)' // Using a shadow color derived from our primary blue adds brand personality
  };
  static readonly FAB_DARK: ShadowOptions = {
    radius: 32,
    offsetX: 0,
    offsetY: 12,
    color: 'rgba(0, 99, 230, 0.40)'
  };

  static readonly LIGHT_SHADOW: ShadowOptions = {
    radius: 20, // 模糊半径大一点
    color: 'rgba(0,0,0,0.05)', // 颜色非常淡
    offsetX: 0,
    offsetY: 4
  }
  static readonly LIGHT_SHADOW_DARK: ShadowOptions = {
    radius: 20,
    color: 'rgba(0, 0, 0, 0.25)',
    offsetX: 0,
    offsetY: 4
  }

  /**
   * (Bonus) A subtle shadow for smaller, less important elements that still need some depth.
   */
  static readonly SUBTLE: ShadowOptions = {
    radius: 8,
    offsetX: 0,
    offsetY: 2,
    color: 'rgba(31, 35, 38, 0.05)'
  };
  static readonly SUBTLE_DARK: ShadowOptions = {
    radius: 8,
    offsetX: 0,
    offsetY: 2,
    color: 'rgba(0, 0, 0, 0.28)'
  };

  static getTagPillShadow(accentColor: string, isDarkTheme: boolean): ShadowOptions {
    const base = isDarkTheme ? AppShadows.CARD_INTERACTIVE_DARK : AppShadows.CARD_RESTING;
    return {
      radius: 30,
      offsetX: 0,
      offsetY: 4,
      color: accentColor ?? base.color
    };
  }
}
