import { speechRecognizer } from '@kit.CoreSpeechKit';
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG: string = 'VoiceInputController';
const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const FINALIZE_TIMEOUT_MS: number = 2000;
const SPEECH_RECOGNIZER_SYSCAP: string = 'SystemCapability.AI.SpeechRecognizer';

export enum VoiceInputState {
  IDLE,
  REQUESTING_PERMISSION,
  LISTENING,
  FINALIZING,
  COMPLETED,
  CANCELLED,
  ERROR
}

export enum VoiceInputNotice {
  NONE,
  UNSUPPORTED,
  PERMISSION_DENIED,
  PERMISSION_GRANTED_RETRY,
  NO_SPEECH,
  RECOGNITION_FAILED
}

export interface VoiceInputCallbacks {
  onStateChanged: (state: VoiceInputState) => void;
  onInterimText: (text: string) => void;
  onFinalText: (text: string) => void;
  onNotice: (notice: VoiceInputNotice) => void;
}

export class VoiceInputController {
  private readonly callbacks: VoiceInputCallbacks;
  private state: VoiceInputState = VoiceInputState.IDLE;
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private sessionId: string = '';
  private sessionCounter: number = 0;
  private interimText: string = '';
  private finalText: string = '';
  private finalizeTimer: number | null = null;
  private sessionSettled: boolean = false;

  constructor(callbacks: VoiceInputCallbacks) {
    this.callbacks = callbacks;
  }

  public getState(): VoiceInputState {
    return this.state;
  }

  public isActive(): boolean {
    return this.state === VoiceInputState.LISTENING || this.state === VoiceInputState.FINALIZING;
  }

  public async start(context: common.UIAbilityContext): Promise<void> {
    if (this.state !== VoiceInputState.IDLE) {
      hilog.warn(0x0000, TAG, `start ignored, state=${this.state}`);
      return;
    }
    if (!canIUse(SPEECH_RECOGNIZER_SYSCAP)) {
      hilog.warn(0x0000, TAG, 'speech recognizer syscap unavailable');
      this.callbacks.onNotice(VoiceInputNotice.UNSUPPORTED);
      return;
    }
    const granted: boolean = await this.isMicrophoneGranted(context);
    if (!granted) {
      await this.requestMicrophonePermission(context);
      return;
    }
    await this.beginListening();
  }

  public stopAndFinalize(): void {
    if (this.state !== VoiceInputState.LISTENING || !this.engine) {
      return;
    }
    this.setState(VoiceInputState.FINALIZING);
    try {
      this.engine.finish(this.sessionId);
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `finish failed, code=${err.code}`);
      this.settleSession();
    }
    this.scheduleFinalizeTimeout();
  }

  public cancel(): void {
    if (this.state === VoiceInputState.IDLE) {
      return;
    }
    this.clearFinalizeTimer();
    if (this.engine) {
      try {
        this.engine.cancel(this.sessionId);
      } catch (error) {
        const err = error as BusinessError;
        hilog.warn(0x0000, TAG, `cancel failed, code=${err.code}`);
      }
    }
    this.disposeEngine();
    this.interimText = '';
    this.finalText = '';
    this.sessionSettled = true;
    this.setState(VoiceInputState.CANCELLED);
    this.setState(VoiceInputState.IDLE);
  }

  public release(): void {
    this.clearFinalizeTimer();
    this.disposeEngine();
    this.interimText = '';
    this.finalText = '';
    this.sessionSettled = true;
    this.setState(VoiceInputState.IDLE);
  }

  private async isMicrophoneGranted(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const bundleInfo: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const status: abilityAccessCtrl.GrantStatus =
        await atManager.checkAccessToken(bundleInfo.appInfo.accessTokenId, MICROPHONE_PERMISSION);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `permission check failed, code=${err.code}`);
      return false;
    }
  }

  private async requestMicrophonePermission(context: common.UIAbilityContext): Promise<void> {
    this.setState(VoiceInputState.REQUESTING_PERMISSION);
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, [MICROPHONE_PERMISSION]);
      const granted: boolean = result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      this.setState(VoiceInputState.IDLE);
      if (granted) {
        hilog.info(0x0000, TAG, 'microphone permission granted, ask user to retry');
        this.callbacks.onNotice(VoiceInputNotice.PERMISSION_GRANTED_RETRY);
      } else {
        hilog.warn(0x0000, TAG, 'microphone permission denied');
        this.callbacks.onNotice(VoiceInputNotice.PERMISSION_DENIED);
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `permission request failed, code=${err.code}`);
      this.setState(VoiceInputState.IDLE);
      this.callbacks.onNotice(VoiceInputNotice.PERMISSION_DENIED);
    }
  }

  private async beginListening(): Promise<void> {
    this.interimText = '';
    this.finalText = '';
    this.sessionSettled = false;
    this.sessionCounter += 1;
    this.sessionId = `voice_input_${Date.now()}_${this.sessionCounter}`;

    let engine: speechRecognizer.SpeechRecognitionEngine;
    try {
      engine = await speechRecognizer.createEngine({
        language: 'zh-CN',
        online: 1,
        extraParams: { 'locate': 'CN', 'recognizerMode': 'short' }
      });
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `createEngine failed, code=${err.code}`);
      this.setState(VoiceInputState.ERROR);
      this.callbacks.onNotice(VoiceInputNotice.RECOGNITION_FAILED);
      this.setState(VoiceInputState.IDLE);
      return;
    }
    if (this.sessionSettled) {
      try {
        engine.shutdown();
      } catch (_ignored) {
      }
      return;
    }
    this.engine = engine;
    engine.setListener({
      onStart: (sessionId: string, eventMessage: string): void => this.handleSessionStart(sessionId),
      onEvent: (sessionId: string, eventCode: number, eventMessage: string): void => {
        hilog.info(0x0000, TAG, `recognition event, code=${eventCode}`);
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void =>
        this.handleSessionResult(sessionId, result),
      onComplete: (sessionId: string, eventMessage: string): void => this.handleSessionComplete(sessionId),
      onError: (sessionId: string, errorCode: number, errorMessage: string): void =>
        this.handleSessionError(sessionId, errorCode)
    });
    try {
      engine.startListening({
        sessionId: this.sessionId,
        audioInfo: {
          audioType: 'pcm',
          sampleRate: 16000,
          soundChannel: 1,
          sampleBit: 16
        },
        extraParams: {
          'recognitionMode': 0,
          'vadBegin': 2000,
          'vadEnd': 3000,
          'maxAudioDuration': 20000
        }
      });
      this.setState(VoiceInputState.LISTENING);
      this.callbacks.onInterimText('');
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `startListening failed, code=${err.code}`);
      this.disposeEngine();
      this.setState(VoiceInputState.ERROR);
      this.callbacks.onNotice(VoiceInputNotice.RECOGNITION_FAILED);
      this.setState(VoiceInputState.IDLE);
    }
  }

  private handleSessionStart(sessionId: string): void {
    if (!this.isCurrentSession(sessionId)) {
      return;
    }
    hilog.info(0x0000, TAG, 'recognition started');
  }

  private handleSessionResult(sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void {
    if (!this.isCurrentSession(sessionId)) {
      return;
    }
    if (result.isFinal) {
      this.finalText = result.result;
      hilog.info(0x0000, TAG, `final result received, length=${result.result.length}`);
      if (this.state === VoiceInputState.FINALIZING) {
        this.settleSession();
      }
      return;
    }
    this.interimText = result.result;
    hilog.info(0x0000, TAG, `interim result, length=${result.result.length}`);
    this.callbacks.onInterimText(result.result);
  }

  private handleSessionComplete(sessionId: string): void {
    if (!this.isCurrentSession(sessionId)) {
      return;
    }
    this.settleSession();
  }

  private handleSessionError(sessionId: string, errorCode: number): void {
    if (!this.isCurrentSession(sessionId)) {
      return;
    }
    hilog.error(0x0000, TAG, `recognition error, code=${errorCode}`);
    this.clearFinalizeTimer();
    this.disposeEngine();
    this.interimText = '';
    this.finalText = '';
    this.sessionSettled = true;
    this.setState(VoiceInputState.ERROR);
    this.callbacks.onNotice(VoiceInputNotice.RECOGNITION_FAILED);
    this.setState(VoiceInputState.IDLE);
  }

  private settleSession(): void {
    if (this.sessionSettled) {
      return;
    }
    this.sessionSettled = true;
    this.clearFinalizeTimer();
    this.disposeEngine();
    const trimmed: string = this.finalText.trim();
    this.interimText = '';
    if (trimmed.length === 0) {
      hilog.info(0x0000, TAG, 'session settled with empty text');
      this.setState(VoiceInputState.CANCELLED);
      this.callbacks.onNotice(VoiceInputNotice.NO_SPEECH);
      this.setState(VoiceInputState.IDLE);
      return;
    }
    this.setState(VoiceInputState.COMPLETED);
    this.callbacks.onFinalText(trimmed);
    this.setState(VoiceInputState.IDLE);
  }

  private scheduleFinalizeTimeout(): void {
    this.clearFinalizeTimer();
    this.finalizeTimer = setTimeout(() => {
      this.finalizeTimer = null;
      hilog.warn(0x0000, TAG, `finalize timeout after ${FINALIZE_TIMEOUT_MS}ms`);
      this.settleSession();
    }, FINALIZE_TIMEOUT_MS);
  }

  private clearFinalizeTimer(): void {
    if (this.finalizeTimer !== null) {
      clearTimeout(this.finalizeTimer);
      this.finalizeTimer = null;
    }
  }

  private disposeEngine(): void {
    const engine: speechRecognizer.SpeechRecognitionEngine | null = this.engine;
    this.engine = null;
    if (!engine) {
      return;
    }
    try {
      engine.shutdown();
    } catch (error) {
      const err = error as BusinessError;
      hilog.warn(0x0000, TAG, `engine shutdown failed, code=${err.code}`);
    }
  }

  private isCurrentSession(sessionId: string): boolean {
    return !this.sessionSettled && sessionId === this.sessionId;
  }

  private setState(next: VoiceInputState): void {
    if (this.state === next) {
      return;
    }
    this.state = next;
    this.callbacks.onStateChanged(next);
  }
}
