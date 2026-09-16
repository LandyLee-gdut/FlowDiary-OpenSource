import { Want, bundleManager, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { FlowDiaryImportEnvelope } from './FlowDiaryImportContract';

const TAG = 'GoalFighterShare';
const GOAL_FIGHTER_TOAST_DURATION_MS: number = 1500;

export const GOAL_FIGHTER_BUNDLE_NAME: string = 'com.landylee.goalfighter';
export const GOAL_FIGHTER_ABILITY_NAME: string = 'EntryAbility';
export const GOAL_FIGHTER_IMPORT_URI: string = 'goalfighter://effort/import?v=1';
export const GOAL_FIGHTER_IMPORT_PAYLOAD_KEY: string = 'flowDiaryImportPayload';

export type GoalFighterShareOutcome = 'started' | 'notInstalled' | 'empty' | 'failed';

export interface GoalFighterShareResult {
  outcome: GoalFighterShareOutcome;
}

/**
 * FlowDiary -> GoalFighter 分享统一入口。
 * startAbility 成功仅代表 GoalFighter 被拉起，不代表用户已保存，FlowDiary 侧不落任何"已导入"标记。
 */
export class GoalFighterShareService {
  async share(context: common.UIAbilityContext, envelope: FlowDiaryImportEnvelope):
    Promise<GoalFighterShareResult> {
    if (envelope.records.length === 0) {
      hilog.warn(0x0000, TAG, 'empty envelope rejected, skip starting GoalFighter');
      return { outcome: 'empty' };
    }
    if (!this.isGoalFighterAvailable()) {
      this.showToast($r('app.string.goalfighter_not_installed_toast'));
      return { outcome: 'notInstalled' };
    }
    const payload: string = JSON.stringify(envelope);
    const wantParameters: Record<string, Object> = {};
    wantParameters[GOAL_FIGHTER_IMPORT_PAYLOAD_KEY] = payload;
    const want: Want = {
      bundleName: GOAL_FIGHTER_BUNDLE_NAME,
      abilityName: GOAL_FIGHTER_ABILITY_NAME,
      action: 'ohos.want.action.viewData',
      uri: GOAL_FIGHTER_IMPORT_URI,
      parameters: wantParameters
    };
    try {
      await context.startAbility(want);
    } catch (error) {
      const businessError = error as BusinessError;
      // 禁止把完整 payload 输出到 hilog，仅记录错误码与记录条数
      hilog.error(0x0000, TAG,
        `startAbility failed, code=${businessError.code}, records=${envelope.records.length}`);
      this.showToast($r('app.string.goalfighter_open_failed_toast'));
      return { outcome: 'failed' };
    }
    hilog.info(0x0000, TAG, `goalFighter started, mode=${envelope.mode}, records=${envelope.records.length}`);
    this.showToast($r('app.string.goalfighter_opening_toast'));
    return { outcome: 'started' };
  }

  /**
   * 判断当前设备是否存在可处理 GoalFighter 导入协议的应用。
   * 页面用该结果控制分享入口；异常时按不可用处理，避免展示不可执行的操作。
   */
  isGoalFighterAvailable(): boolean {
    try {
      return bundleManager.canOpenLink(GOAL_FIGHTER_IMPORT_URI);
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(0x0000, TAG, `canOpenLink threw, code=${businessError.code}, treat as not installed`);
      return false;
    }
  }

  private showToast(message: ResourceStr): void {
    promptAction.openToast({
      message: message,
      duration: GOAL_FIGHTER_TOAST_DURATION_MS
    }).catch(() => {
      hilog.error(0x0000, TAG, 'openToast failed');
    });
  }
}

export const goalFighterShareService: GoalFighterShareService = new GoalFighterShareService();
