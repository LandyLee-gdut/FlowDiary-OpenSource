import { vibrator } from "@kit.SensorServiceKit";
import { hilog } from "@kit.PerformanceAnalysisKit";
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'VibratorUtil'

export type CustomPatternId =
  | 'haptic.pattern.softPlus'
  | 'haptic.pattern.crispHard'
  | 'haptic.pattern.focusPulse'
  | 'haptic.pattern.sceneSuccess'
  | 'haptic.pattern.alertCascade';

export class VibratorUtil {
  private static instance: VibratorUtil | null = null;
  private readonly defaultPresetEffectId: string = 'haptic.notice.success';
  private readonly fallbackVibrationDuration: number = 40;
  private readonly defaultVibrationUsage: vibrator.Usage = 'touch';
  private supportsPresetHaptic: boolean = false;
  private vibrationInFlight: boolean = false;
  private readonly hapticEffectsToPrefetch: Array<string> = [
    'haptic.notice.success',
    'haptic.notice.fail',
    'haptic.effect.soft',
    'haptic.effect.hard',
    'haptic.effect.sharp'
  ];
  private readonly hapticFallbackMap: Map<string, number> = new Map([
    ['haptic.notice.fail', 70],
    ['haptic.effect.soft', 25],
    ['haptic.effect.sharp', 50]
  ]);
  private readonly effectSupportCache: Map<string, boolean> = new Map();
  private readonly customPatterns: Map<CustomPatternId, vibrator.VibratorPattern> = new Map();
  private initializationPromise: Promise<void> | null = null;
  private isInitialized: boolean = false;

  private constructor() {
    this.buildCustomPatterns();
  }

  public static getInstance(): VibratorUtil {
    if (!VibratorUtil.instance) {
      VibratorUtil.instance = new VibratorUtil();
    }
    return VibratorUtil.instance;
  }

  public async initialize(): Promise<void> {
    await this.ensureInitialized();
  }

  public async triggerHaptic(effectId?: string, usage?: vibrator.Usage): Promise<void> {
    await this.ensureInitialized();
    await this.performTrigger(effectId, usage);
  }

  public async triggerPattern(patternId: CustomPatternId, usage?: vibrator.Usage): Promise<void> {
    await this.ensureInitialized();
    await this.performPatternTrigger(patternId, usage);
  }

  public getAvailableCustomPatterns(): Array<CustomPatternId> {
    return Array.from(this.customPatterns.keys());
  }

  public async stopAllHaptics(): Promise<void> {
    try {
      await vibrator.stopVibration();
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(0x0000, TAG, `Failed to stop vibration: ${JSON.stringify({ code: businessError?.code, message: businessError?.message })}`);
    }
  }

  private async ensureInitialized(): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    if (!this.initializationPromise) {
      this.initializationPromise = this.initVibrationSupportInternal()
        .catch((error: BusinessError) => {
          hilog.warn(0x0000, TAG, `Vibration initialization failed: ${JSON.stringify(error)}`);
        })
        .finally(() => {
          this.initializationPromise = null;
        });
    }

    await this.initializationPromise;
  }

  private async initVibrationSupportInternal(): Promise<void> {
    this.supportsPresetHaptic = await this.ensureEffectSupport(this.defaultPresetEffectId);

    await Promise.all(
      this.hapticEffectsToPrefetch
        .filter(effect => effect !== this.defaultPresetEffectId)
        .map(effect => this.ensureEffectSupport(effect))
    );

    this.isInitialized = true;
  }

  private async ensureEffectSupport(effectId: string): Promise<boolean> {
    if (!effectId) {
      return false;
    }

    if (this.effectSupportCache.has(effectId)) {
      return this.effectSupportCache.get(effectId) as boolean;
    }

    try {
      const supported = await vibrator.isSupportEffect(effectId);
      this.effectSupportCache.set(effectId, supported);
      hilog.info(0x0000, TAG, `Haptic effect ${effectId} supported: ${supported}`);
      return supported;
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(0x0000, TAG, `Failed to query haptic support for ${effectId}: ${JSON.stringify({ code: businessError?.code, message: businessError?.message })}`);
      this.effectSupportCache.set(effectId, false);
      return false;
    }
  }

  private async performTrigger(effectId?: string, usage?: vibrator.Usage): Promise<void> {
    if (this.vibrationInFlight) {
      return;
    }

    const vibrationUsage: vibrator.Usage = usage ?? this.defaultVibrationUsage;
    this.vibrationInFlight = true;

    try {
      const targetEffectId = effectId ?? this.defaultPresetEffectId;
      const supportsPreset = await this.ensureEffectSupport(targetEffectId);

      if (supportsPreset) {
        await vibrator.startVibration({
          type: 'preset',
          effectId: targetEffectId,
          count: 1
        }, {
          usage: vibrationUsage
        });
      } else {
        await vibrator.startVibration({
          type: 'time',
          duration: this.hapticFallbackMap.get(targetEffectId) ?? this.fallbackVibrationDuration
        }, {
          usage: vibrationUsage
        });
      }
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(0x0000, TAG, `Haptic trigger failed: ${JSON.stringify({ code: businessError?.code, message: businessError?.message })}`);
    } finally {
      this.vibrationInFlight = false;
    }
  }

  private async performPatternTrigger(patternId: CustomPatternId, usage?: vibrator.Usage): Promise<void> {
    if (this.vibrationInFlight) {
      return;
    }

    const pattern = this.customPatterns.get(patternId);
    if (!pattern) {
      hilog.warn(0x0000, TAG, `Requested pattern ${patternId} not found`);
      return;
    }

    const vibrationUsage: vibrator.Usage = usage ?? this.defaultVibrationUsage;
    this.vibrationInFlight = true;

    try {
      await vibrator.startVibration({
        type: 'pattern',
        pattern
      }, {
        usage: vibrationUsage
      });
      hilog.info(0x0000, TAG, `Triggered custom pattern ${patternId}`);
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(0x0000, TAG, `Pattern trigger failed for ${patternId}: ${JSON.stringify({ code: businessError?.code, message: businessError?.message })}`);
    } finally {
      this.vibrationInFlight = false;
    }
  }

  private buildCustomPatterns(): void {
    if (this.customPatterns.size > 0) {
      return;
    }

    this.customPatterns.set('haptic.pattern.softPlus', this.createSoftPlusPattern());
    this.customPatterns.set('haptic.pattern.crispHard', this.createCrispHardPattern());
    this.customPatterns.set('haptic.pattern.focusPulse', this.createFocusPulsePattern());
    this.customPatterns.set('haptic.pattern.sceneSuccess', this.createSceneSuccessPattern());
    this.customPatterns.set('haptic.pattern.alertCascade', this.createAlertCascadePattern());
  }

  private createSoftPlusPattern(): vibrator.VibratorPattern {
    const builder = new vibrator.VibratorPatternBuilder();
    builder.addContinuousEvent(0, 220, { intensity: 52, frequency: 38 });
    return builder.build();
  }

  private createCrispHardPattern(): vibrator.VibratorPattern {
    const builder = new vibrator.VibratorPatternBuilder();
    builder.addTransientEvent(0, { intensity: 48, frequency: 55 });
    return builder.build();
  }

  private createFocusPulsePattern(): vibrator.VibratorPattern {
    const builder = new vibrator.VibratorPatternBuilder();
    builder.addContinuousEvent(0, 260, { intensity: 40, frequency: 32 });
    return builder.build();
  }

  private createSceneSuccessPattern(): vibrator.VibratorPattern {
    const builder = new vibrator.VibratorPatternBuilder();
    builder.addTransientEvent(0, { intensity: 78, frequency: 62 });
    return builder.build();
  }

  private createAlertCascadePattern(): vibrator.VibratorPattern {
    const builder = new vibrator.VibratorPatternBuilder();
    builder.addContinuousEvent(0, 300, { intensity: 85, frequency: 72 });
    return builder.build();
  }

}
