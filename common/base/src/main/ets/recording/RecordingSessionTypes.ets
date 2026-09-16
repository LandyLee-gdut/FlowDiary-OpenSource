/**
 * 计时会话契约类型（recording-session-store refactor，Phase 1 契约先行）。
 *
 * 约束（见 docs/plans/recording-session-store-refactor-plan.md §7.2）：
 * 本目录所有代码必须框架无关——不得 import ArkUI 组件、不得 import 今日业务类，
 * 保证可用 hypium 做纯逻辑单测（common/base/src/test/RecordingSessionStore.test.ets）。
 */

/**
 * 会话状态机：
 * Idle ──start(itemId)──▶ Starting ──db ok──▶ Running ──stop()──▶ Stopping ──db ok──▶ Idle
 * db fail：Starting 回 Idle；Stopping 保持 Running（副作用不回滚真相）。
 */
export enum RecordingPhase {
  IDLE = 0,
  STARTING = 1,
  RUNNING = 2,
  STOPPING = 3
}

/** start() 命令结果 */
export enum StartResult {
  SUCCESS = 0,
  /** 已有其他会话在运行（Running/Starting 期间 start 其他 item），当前会话不受影响 */
  BLOCKED_RUNNING = 1,
  DB_ERROR = 2
}

/** stop() 命令结果 */
export enum StopResult {
  SUCCESS = 0,
  /** 无运行会话或 itemId 与运行会话不符；no-op，不触发 DB 与事件 */
  NOT_RUNNING = 1,
  /** DB 停止失败；快照保持 Running */
  DB_ERROR = 2
}

/**
 * 一条未结束 time_record 的内存投影。
 * startTime 为毫秒时间戳；title/color 供 UI 投影（runningSessionView）使用。
 */
export class OpenRecordInfo {
  itemId: string = '';
  recordId: string = '';
  startTime: number = 0;
  title: string = '';
  color: string = '';
}

/**
 * store 对外快照。Idle 时 store.snapshot() 返回 null。
 * phase 仅为展示索引，永远不反向决定 DB 真相。
 */
export class SessionSnapshot {
  itemId: string = '';
  recordId: string = '';
  startTime: number = 0;
  title: string = '';
  color: string = '';
  phase: RecordingPhase = RecordingPhase.IDLE;
}

/** 事件发布顺序契约：回调触发时 store.snapshot() 必须已更新为新值（快照先于事件）。 */
export type SessionChangeCallback = (snapshot: SessionSnapshot | null) => void;

/** ticker 回调；nowMs 为注入时钟的当前值，供自动停止/跨天检查使用。 */
export type TickCallback = (nowMs: number) => void;

/**
 * 投影写入器：store 单写 AppStorage 的唯一通道（today 侧注册实现）。
 * 每次快照变更与每个 tick 调用；writer 异常不得影响 store 状态。
 */
export type SessionProjectionWriter = (snapshot: SessionSnapshot | null, elapsedSeconds: number) => void;

/** 订阅注销函数 */
export type Unsubscribe = () => void;
