import { recordingSessionStore, registerSessionCommands, SessionSnapshot } from 'base';
import type { SessionProjectionWriter } from 'base';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TodaySessionCommands } from './TodaySessionCommands';
import { MatterItemStateManager } from '../utils/MatterItemStateManager';

const TAG: string = 'RecordingSessionBoot';

/**
 * 会话快照身份键：recordId + phase。同一身份内的 ticker 投影只刷新秒数，
 * 不重复覆盖 runningSessionView（避免每秒触发 @Watch 对账）。
 */
let lastProjectedKey: string = '';
let sessionTickEffectRegistered: boolean = false;

/** runningSessionView 投影副本（store 内部快照是活对象，phase 会原地变更，必须写副本）。 */
function buildSessionView(snapshot: SessionSnapshot): SessionSnapshot {
  const view = new SessionSnapshot();
  view.itemId = snapshot.itemId;
  view.recordId = snapshot.recordId;
  view.startTime = snapshot.startTime;
  view.title = snapshot.title;
  view.color = snapshot.color;
  view.phase = snapshot.phase;
  return view;
}

/**
 * 终态投影（Phase 4-6）：只写 runningSessionView（会话视图副本）+ sessionElapsedSeconds（每 tick 秒数）。
 * legacy 运行键（isRunning/currentRunningItemId/currentRecordId/Title/Color/labelColor/
 * initCountUpTime/restartBackgroundTask）的全部消费方已在 Phase 4-1..4-5 迁移到 store/视图。
 */
function projectSessionKeys(snapshot: SessionSnapshot | null, elapsedSeconds: number): void {
  if (snapshot === null) {
    lastProjectedKey = '';
    AppStorage.setOrCreate('runningSessionView', null);
    AppStorage.setOrCreate('sessionElapsedSeconds', 0);
    return;
  }

  const snapshotKey = `${snapshot.recordId}:${snapshot.phase}`;
  if (snapshotKey !== lastProjectedKey) {
    lastProjectedKey = snapshotKey;
    AppStorage.setOrCreate('runningSessionView', buildSessionView(snapshot));
  }
  AppStorage.setOrCreate('sessionElapsedSeconds', elapsedSeconds);
}

/** 进程级 store 的 tick 副作用只注册一次，避免 UIAbility 同进程重建时重复执行。 */
function registerSessionTickEffect(): void {
  if (sessionTickEffectRegistered) {
    return;
  }
  sessionTickEffectRegistered = true;
  recordingSessionStore.onTick((nowMs: number): void => {
    MatterItemStateManager.getInstance().handleSessionTick(nowMs);
  });
}

/**
 * app 启动装配（PhoneAbility.onCreate 调用，须在 RDBStoreUtil.init 之后）：
 * 注册 today 侧 DB 命令 + store → AppStorage 投影 + ticker 效应。
 *
 * Phase 2c 后：start/stop/恢复链路全部经 recordingSessionStore，本投影是运行态
 * 的唯一写者。Phase 4-6 后：投影只写 runningSessionView + sessionElapsedSeconds 两键。
 * Phase 3 后：ticker 效果（自动停止到点检查 + 跨天拆分）挂 onTick，在此注册一次，
 * 原 MatterItem TextTimer.onTimer 里的检查删除。
 */
export function setupRecordingSession(): void {
  registerSessionCommands(new TodaySessionCommands());
  const writer: SessionProjectionWriter = (snapshot: SessionSnapshot | null, elapsedSeconds: number): void => {
    projectSessionKeys(snapshot, elapsedSeconds);
  };
  recordingSessionStore.setProjection(writer);
  registerSessionTickEffect();
  hilog.info(0x0000, TAG, 'recording session boot completed (commands registered, projection + tick effects attached)');
}
