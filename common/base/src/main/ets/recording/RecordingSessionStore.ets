import { RecordingPhase, SessionSnapshot, StartResult, StopResult, OpenRecordInfo } from './RecordingSessionTypes';
import type { SessionChangeCallback, TickCallback, Unsubscribe, SessionProjectionWriter } from './RecordingSessionTypes';
import type { SessionCommands } from './SessionCommands';

/**
 * 计时会话唯一状态机所有者（全局单 store 单写者）。
 *
 * 命令执行顺序（单一函数内，docs/plans/recording-session-store-refactor-plan.md §3.2）：
 * 入队 → 取队首 → 调用注入的 DB 命令 → 更新自身快照 → 发变更事件 → 出队 → 执行下一条。
 * 所有命令（start/stop/adopt/restore）共用一个队列，按全局串行化，不按 activity 加锁。
 *
 * 状态机：
 * Idle ──start──▶ Starting ──db ok──▶ Running ──stop──▶ Stopping ──db ok──▶ Idle
 * Starting db 失败 → 回 Idle（清快照，不发事件）；
 * Stopping db 失败 → 快照保持 Running（副作用不回滚真相）。
 * adoptOpenRecord / restoreFromDb 以 DB 查询结果覆写内存态（唯一允许"无命令改状态"的入口）。
 *
 * 框架无关：不得 import ArkUI / hilog 之外的 OHOS UI 能力；AppStorage 投影通过
 * setProjection 注入的 writer 完成（store 仍是唯一调用方，保证单写）。
 */
export class RecordingSessionStore {
  private readonly commands: SessionCommands;
  private readonly nowProvider: () => number;
  private readonly tickIntervalMs: number;

  private currentSnapshot: SessionSnapshot | null = null;
  private queue: Array<() => Promise<void>> = [];
  private draining: boolean = false;
  private restoreDone: boolean = false;
  private foreground: boolean = true;
  private tickerId: number = -1;
  private projection: SessionProjectionWriter | null = null;
  private sessionListeners: Array<SessionChangeCallback> = [];
  private tickListeners: Array<TickCallback> = [];

  constructor(commands: SessionCommands, nowProvider: () => number = (): number => Date.now(), tickIntervalMs: number = 1000) {
    this.commands = commands;
    this.nowProvider = nowProvider;
    this.tickIntervalMs = tickIntervalMs;
  }

  /** 当前快照（防御性副本）；Idle 时返回 null。 */
  snapshot(): SessionSnapshot | null {
    if (this.currentSnapshot === null) {
      return null;
    }
    return this.copySnapshot(this.currentSnapshot);
  }

  /** running 时 = floor((now - startTime) / 1000)；非 running 为 0。与组件无关。 */
  elapsedSeconds(): number {
    const snapshot = this.currentSnapshot;
    if (snapshot === null || snapshot.phase !== RecordingPhase.RUNNING) {
      return 0;
    }
    const elapsedMs = Math.max(0, this.nowProvider() - snapshot.startTime);
    return Math.floor(elapsedMs / 1000);
  }

  start(itemId: string): Promise<StartResult> {
    return this.enqueue((): Promise<StartResult> => this.performStart(itemId));
  }

  stop(itemId: string): Promise<StopResult> {
    return this.enqueue((): Promise<StopResult> => this.performStop(itemId));
  }

  /** ideapool 建完记录后调用：以 DB 查询结果覆写该 item 的内存态。 */
  adoptOpenRecord(itemId: string): Promise<void> {
    return this.enqueue((): Promise<void> => this.performAdopt(itemId));
  }

  /** 冷启动唯一恢复入口，只允许调用一次（查询失败可重试）。 */
  restoreFromDb(): Promise<void> {
    return this.enqueue((): Promise<void> => this.performRestore());
  }

  onSessionChange(callback: SessionChangeCallback): Unsubscribe {
    this.sessionListeners.push(callback);
    return (): void => {
      const index = this.sessionListeners.indexOf(callback);
      if (index >= 0) {
        this.sessionListeners.splice(index, 1);
      }
    };
  }

  onTick(callback: TickCallback): Unsubscribe {
    this.tickListeners.push(callback);
    return (): void => {
      const index = this.tickListeners.indexOf(callback);
      if (index >= 0) {
        this.tickListeners.splice(index, 1);
      }
    };
  }

  /** 前后台切换：前台启动 ticker（Running 时每 tick 派发 onTick），后台停走。 */
  setForeground(active: boolean): void {
    this.foreground = active;
    if (active) {
      const snapshot = this.currentSnapshot;
      if (snapshot !== null && snapshot.phase === RecordingPhase.RUNNING) {
        this.startTicker();
        // 回前台立即投影一次，秒数显示不等第一个 tick（Phase 3 验收：后台回来立即正确）
        this.project(this.copySnapshot(snapshot));
      }
    } else {
      this.stopTicker();
    }
  }

  /** 注册投影写入器后立即投影当前态；writer 异常被吞掉，不影响 store。 */
  setProjection(writer: SessionProjectionWriter): void {
    this.projection = writer;
    this.project(this.currentSnapshot);
  }

  private enqueue<T>(work: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
      const task = async (): Promise<void> => {
        try {
          resolve(await work());
        } catch (error) {
          reject(error instanceof Error ? error : new Error(JSON.stringify(error)));
        }
      };
      this.queue.push(task);
      this.drain();
    });
  }

  private drain(): void {
    if (this.draining || this.queue.length === 0) {
      return;
    }
    this.draining = true;
    const next = this.queue.shift();
    if (next === undefined) {
      this.draining = false;
      return;
    }
    next().then((): void => {
      this.draining = false;
      this.drain();
    }).catch((): void => {
      this.draining = false;
      this.drain();
    });
  }

  private async performStart(itemId: string): Promise<StartResult> {
    const current = this.currentSnapshot;
    if (current !== null && current.phase === RecordingPhase.RUNNING) {
      // 幂等规则：同 item 重复 start 为 no-op；其他 item 被拒
      return current.itemId === itemId ? StartResult.SUCCESS : StartResult.BLOCKED_RUNNING;
    }

    const pending = new SessionSnapshot();
    pending.itemId = itemId;
    pending.phase = RecordingPhase.STARTING;
    this.currentSnapshot = pending;

    let info: OpenRecordInfo;
    try {
      info = await this.commands.startSession(itemId);
    } catch (error) {
      // db fail：回 Idle，不发事件
      this.currentSnapshot = null;
      return StartResult.DB_ERROR;
    }

    const snapshot = new SessionSnapshot();
    snapshot.itemId = info.itemId;
    snapshot.recordId = info.recordId;
    snapshot.startTime = info.startTime;
    snapshot.title = info.title;
    snapshot.color = info.color;
    snapshot.phase = RecordingPhase.RUNNING;
    this.currentSnapshot = snapshot;
    this.emitSessionChange(snapshot);
    this.ensureTickerRunning();
    return StartResult.SUCCESS;
  }

  private async performStop(itemId: string): Promise<StopResult> {
    const current = this.currentSnapshot;
    if (current === null || current.phase !== RecordingPhase.RUNNING || current.itemId !== itemId) {
      return StopResult.NOT_RUNNING;
    }

    current.phase = RecordingPhase.STOPPING;
    try {
      await this.commands.stopSession(current.itemId, current.recordId);
    } catch (error) {
      // 副作用不回滚真相：DB 停止失败时快照保持 Running
      current.phase = RecordingPhase.RUNNING;
      return StopResult.DB_ERROR;
    }

    this.currentSnapshot = null;
    this.stopTickerIfIdle();
    this.emitSessionChange(null);
    return StopResult.SUCCESS;
  }

  private async performAdopt(itemId: string): Promise<void> {
    let info: OpenRecordInfo | null = null;
    try {
      info = await this.commands.queryOpenRecord(itemId);
    } catch (error) {
      // 查询失败：保持当前内存态
      return;
    }
    this.applyOpenRecord(info, itemId);
  }

  private async performRestore(): Promise<void> {
    if (this.restoreDone) {
      return;
    }
    let info: OpenRecordInfo | null = null;
    try {
      info = await this.commands.queryNewestOpenRecord();
    } catch (error) {
      // 首次恢复失败不置位，允许后续重试
      return;
    }
    this.restoreDone = true;
    this.applyOpenRecord(info, '');
  }

  /**
   * 以 DB 查询结果覆写内存态。
   * scopedItemId 非空时（adopt 语义）：查询结果为空只清同名 item 的会话，
   * 不影响其他 item 的运行会话；为空时（restore 语义）无条件覆写。
   */
  private applyOpenRecord(info: OpenRecordInfo | null, scopedItemId: string): void {
    if (info === null) {
      if (scopedItemId !== '' && this.currentSnapshot !== null && this.currentSnapshot.itemId !== scopedItemId) {
        return;
      }
      this.currentSnapshot = null;
      this.stopTickerIfIdle();
      this.emitSessionChange(null);
      return;
    }

    const snapshot = new SessionSnapshot();
    snapshot.itemId = info.itemId;
    snapshot.recordId = info.recordId;
    snapshot.startTime = info.startTime;
    snapshot.title = info.title;
    snapshot.color = info.color;
    snapshot.phase = RecordingPhase.RUNNING;
    this.currentSnapshot = snapshot;
    this.ensureTickerRunning();
    this.emitSessionChange(snapshot);
  }

  private emitSessionChange(snapshot: SessionSnapshot | null): void {
    this.project(snapshot);
    const listeners = this.sessionListeners.slice();
    listeners.forEach((callback: SessionChangeCallback) => {
      try {
        callback(snapshot);
      } catch (error) {
        // 监听器异常不回滚 store 状态
      }
    });
  }

  private project(snapshot: SessionSnapshot | null): void {
    if (this.projection !== null) {
      try {
        this.projection(snapshot, this.elapsedSeconds());
      } catch (error) {
        // 投影失败不影响真相
      }
    }
  }

  private ensureTickerRunning(): void {
    if (this.foreground) {
      this.startTicker();
    }
  }

  private startTicker(): void {
    if (this.tickerId >= 0) {
      return;
    }
    this.tickerId = setInterval((): void => {
      this.handleTick();
    }, this.tickIntervalMs);
  }

  private stopTicker(): void {
    if (this.tickerId >= 0) {
      clearInterval(this.tickerId);
      this.tickerId = -1;
    }
  }

  private stopTickerIfIdle(): void {
    if (this.currentSnapshot === null) {
      this.stopTicker();
    }
  }

  private handleTick(): void {
    const snapshot = this.currentSnapshot;
    if (snapshot === null || snapshot.phase !== RecordingPhase.RUNNING) {
      this.stopTicker();
      return;
    }
    const now = this.nowProvider();
    this.project(this.copySnapshot(snapshot));
    const listeners = this.tickListeners.slice();
    listeners.forEach((callback: TickCallback) => {
      try {
        callback(now);
      } catch (error) {
        // onTick 效应异常不回滚 store 状态
      }
    });
  }

  private copySnapshot(source: SessionSnapshot): SessionSnapshot {
    const copy = new SessionSnapshot();
    copy.itemId = source.itemId;
    copy.recordId = source.recordId;
    copy.startTime = source.startTime;
    copy.title = source.title;
    copy.color = source.color;
    copy.phase = source.phase;
    return copy;
  }
}

/**
 * 延迟注册的命令代理：单例在 base 创建时命令尚未可用（today 在 app 启动时注册）。
 * 未注册时调用任何命令按 DB 失败处理。
 */
class DeferredSessionCommands implements SessionCommands {
  private inner: SessionCommands | null = null;

  register(commands: SessionCommands): void {
    this.inner = commands;
  }

  private requireCommands(): SessionCommands {
    if (this.inner === null) {
      throw new Error('SessionCommands not registered (today side must call registerSessionCommands on startup)');
    }
    return this.inner;
  }

  async startSession(itemId: string): Promise<OpenRecordInfo> {
    return this.requireCommands().startSession(itemId);
  }

  async stopSession(itemId: string, recordId: string): Promise<void> {
    await this.requireCommands().stopSession(itemId, recordId);
  }

  async queryOpenRecord(itemId: string): Promise<OpenRecordInfo | null> {
    return this.requireCommands().queryOpenRecord(itemId);
  }

  async queryNewestOpenRecord(): Promise<OpenRecordInfo | null> {
    return this.requireCommands().queryNewestOpenRecord();
  }
}

const deferredCommands: DeferredSessionCommands = new DeferredSessionCommands();

/** 进程级单例：RDB 未结束 time_record 的唯一内存所有者。 */
export const recordingSessionStore: RecordingSessionStore = new RecordingSessionStore(deferredCommands);

/** today 侧启动时注册真实 DB 命令实现。 */
export function registerSessionCommands(commands: SessionCommands): void {
  deferredCommands.register(commands);
}
