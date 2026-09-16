import { BusinessError } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'HoldingHandService';

export class HoldingHandService {
  private refCount: number = 0;
  private subscribed: boolean = false;
  private callback?: Callback<motion.HoldingHandStatus>;

  start(): void {
    this.refCount += 1;
    if (this.subscribed) {
      return;
    }
    this.subscribe();
  }

  stop(): void {
    if (this.refCount > 0) {
      this.refCount -= 1;
    }
    if (this.refCount > 0) {
      return;
    }
    this.unsubscribe();
  }

  resetStatus(): void {
    AppStorage.setOrCreate('holdingHandStatus', motion.HoldingHandStatus.UNKNOWN_STATUS);
  }

  private subscribe(): void {
    this.callback = (status: motion.HoldingHandStatus) => {
      AppStorage.setOrCreate('holdingHandStatus', status);
      hilog.info(0x0000, TAG, `holdingHands event: status=${status}`);
    };
    try {
      motion.on('holdingHandChanged', this.callback);
      this.subscribed = true;
      hilog.info(0x0000, TAG, 'holdingHands subscribed');
    } catch (error) {
      const err = error as BusinessError;
      this.subscribed = false;
      this.resetStatus();
      hilog.error(0x0000, TAG, `holdingHands subscribe failed: code=${err.code}`);
    }
  }

  private unsubscribe(): void {
    if (!this.subscribed) {
      return;
    }
    try {
      motion.off('holdingHandChanged', this.callback);
      this.subscribed = false;
      hilog.info(0x0000, TAG, 'holdingHands unsubscribed');
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `holdingHands unsubscribe failed: code=${err.code}`);
    }
  }
}

export const holdingHandService: HoldingHandService = new HoldingHandService();
