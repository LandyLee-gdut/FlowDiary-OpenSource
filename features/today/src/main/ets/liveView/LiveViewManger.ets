import { liveViewManager } from '@kit.LiveViewKit';
import { Want, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { recordingSessionStore, TimeRecordUtil } from 'base';

const TAG = 'LiveViewController'
const MAIN_UI_ABILITY_NAME = 'PhoneAbility';
const LIVE_VIEW_ID: number = 123;
const LIVE_VIEW_EVENT_TIMER: string = 'TIMER';
const LIVE_VIEW_STATUS_RUNNING: string = '计时中';
const LIVE_VIEW_STOP_BUTTON: string = '结束记录';
const LIVE_VIEW_STOP_ICON: string = 'liveview_stop.png';
export const LIVE_VIEW_STOP_EVENT: string = 'com.landylee.flowdiary.event.LIVE_VIEW_STOP_TIMER';
const LIVE_VIEW_STOP_ACTION_VALUE: string = 'stopTimer';
const LIVE_VIEW_STOP_REQUEST_CODE: number = 1;
const LIVE_VIEW_CAPSULE_BACKGROUND_COLOR: string = '#FF308977';
export class LiveViewController {
  public async startLiveView(timerTime: number = 0, taskTitle: string = '事项记录中'): Promise<liveViewManager.LiveViewResult> {
    const enabled: boolean = await LiveViewController.isLiveViewEnabled();
    hilog.info(0x0000, TAG, `start requested: enabled=${enabled}, event=${LIVE_VIEW_EVENT_TIMER}, title=${taskTitle}`);
    if (!enabled) {
      throw new Error("Live view is disabled.");
    }
    const defaultView = await LiveViewController.buildDefaultView(timerTime, taskTitle);
    try {
      const result = await liveViewManager.startLiveView(defaultView);
      hilog.info(0x0000, TAG, `start result: ${JSON.stringify(result)}`);
      return result;
    } catch (error) {
      hilog.error(0x0000, TAG, `start failed: ${JSON.stringify(error)}`);
      throw error as Error;
    }
  }

  public async updateLiveViewTimeCrossDay(recordStartTime?: number, taskTitle?: string): Promise<liveViewManager.LiveViewResult> {
    // 校验实况窗开关是否打开
    if (!await LiveViewController.isLiveViewEnabled()) {
      throw new Error('Live view is disabled.');
    }

    const now = Date.now();
    const normalizedStart = typeof recordStartTime === 'number' && recordStartTime > 0
      ? recordStartTime
      : TimeRecordUtil.getDayStart(now);
    const elapsed = Math.max(0, now - normalizedStart);
    const normalizedTitle = taskTitle && taskTitle.trim().length > 0
      ? taskTitle
      : LiveViewController.resolveSessionTitle();

    // 修改实况窗内容
    const defaultView = await LiveViewController.buildDefaultView(elapsed, normalizedTitle);

    // 更新实况窗
    return await liveViewManager.updateLiveView(defaultView);
  }

  /** 会话标题兜底：store 快照优先，无会话时用实况窗默认文案。 */
  private static resolveSessionTitle(): string {
    const session = recordingSessionStore.snapshot();
    if (session !== null && session.title !== '') {
      return session.title;
    }
    return '事项记录中';
  }

  public async stopLiveView(): Promise<liveViewManager.LiveViewResult> {
    // 校验实况窗开关是否打开
    if (!await LiveViewController.isLiveViewEnabled()) {
      throw new Error("Live view is disabled.");
    }
    // 修改实况窗内容
    const defaultView = await LiveViewController.buildDefaultView();
    // 结束实况窗
    try {
      return await liveViewManager.stopLiveView(defaultView);
    } catch (error) {
      // TODO: Implement error handling.
      hilog.error(0x0000, TAG, 'failed to stop live view' + JSON.stringify(error));
      return liveViewManager.stopLiveView(defaultView);
    }
  }

  private static async buildDefaultView(timerTime: number = 0, taskTitle: string = '事项记录中'): Promise<liveViewManager.LiveView> {
    return {
      id: LIVE_VIEW_ID,
      event: LIVE_VIEW_EVENT_TIMER,
      timer: {
        time: timerTime,
        isCountdown: false,
        isPaused: false
      },
      liveViewData: {
        primary: {
          // title: taskTitle,
          title: '${placeholder.timer}',
          content: [
            { text: `计时中：${taskTitle}` },
          ],
          keepTime: 0,
          clickAction: await LiveViewController.buildWantAgent(),
          extensionData: {
            type: liveViewManager.ExtensionType.EXTENSION_TYPE_ICON,
            pic: LIVE_VIEW_STOP_ICON,
            clickAction: await LiveViewController.buildStopWantAgent()
          },
          layoutData: {
            layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_DEFAULT,
            serviceButtons: [{
              name: LIVE_VIEW_STOP_BUTTON,
              clickAction: await LiveViewController.buildStopWantAgent()
            }],
            isServiceButtonsDisplayed: true
          }
        },
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER,
          status: 1,
          time: timerTime,
          content: LIVE_VIEW_STATUS_RUNNING,
          icon: 'img.png',
          backgroundColor: LIVE_VIEW_CAPSULE_BACKGROUND_COLOR
        }
      }
    };
  }

  private static async isLiveViewEnabled(): Promise<boolean> {
    return await liveViewManager.isLiveViewEnabled();
  }

  private static async buildWantAgent(): Promise<Want> {
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: 'com.landylee.flowdiary', // 应用实际bundleName
          abilityName: MAIN_UI_ABILITY_NAME
        } as Want
      ],
      actionType: wantAgent.OperationType.START_ABILITIES,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    const agent = await wantAgent.getWantAgent(wantAgentInfo);
    return agent;
  }

  private static async buildStopWantAgent(): Promise<Want> {
    // 只向存活进程投递停止命令，不拉起 APP 界面。计时长时任务保持进程，
    // Ability 内的统一命令队列会停止 DB 记录、后台任务和实况窗。
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        action: LIVE_VIEW_STOP_EVENT,
        parameters: {
          params: JSON.stringify({
            liveViewAction: LIVE_VIEW_STOP_ACTION_VALUE
          })
        }
      } as Want],
      actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
      requestCode: LIVE_VIEW_STOP_REQUEST_CODE,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return await wantAgent.getWantAgent(wantAgentInfo);
  }
}

export const liveViewController = new LiveViewController();
