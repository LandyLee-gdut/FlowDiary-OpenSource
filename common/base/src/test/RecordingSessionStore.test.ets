import { describe, it, expect } from '@ohos/hypium';
import { RecordingSessionStore } from '../main/ets/recording/RecordingSessionStore';
import { RecordingPhase, StartResult, StopResult, SessionSnapshot } from '../main/ets/recording/RecordingSessionTypes';
import {
  MockSessionCommands,
  buildOpenRecord,
  MOCK_METHOD_START,
  MOCK_METHOD_STOP,
  MOCK_METHOD_QUERY_NEWEST,
  MOCK_STAGE_BEGIN
} from './MockSessionCommands';

/** 可注入的假时钟：store 的 elapsedSeconds 必须只依赖 startTime 与该时钟，与组件无关 */
export class FakeClock {
  nowMs: number = 0;

  now(): number {
    return this.nowMs;
  }

  advance(deltaMs: number): void {
    this.nowMs += deltaMs;
  }
}

/** 每个用例独立的 mock + 时钟 + store 组合，避免用例间状态泄漏 */
export class StoreFixture {
  mock: MockSessionCommands = new MockSessionCommands();
  clock: FakeClock = new FakeClock();
  store: RecordingSessionStore;

  constructor() {
    this.store = new RecordingSessionStore(this.mock, (): number => this.clock.nowMs);
  }
}

/** 吸收 reject，把命令结果归一为 null 供断言（红态=桩抛出→null） */
async function settleStart(promise: Promise<StartResult>): Promise<StartResult | null> {
  try {
    return await promise;
  } catch (error) {
    return null;
  }
}

async function settleStop(promise: Promise<StopResult>): Promise<StopResult | null> {
  try {
    return await promise;
  } catch (error) {
    return null;
  }
}

/**
 * 等待某命令真正进入 DB 门闩（begin 已记录）。
 * 队列任务的启动在微任务层被延迟，调用方不得假设 enqueue 后同步进入 mock。
 */
async function waitForMockBegin(mock: MockSessionCommands, method: string): Promise<void> {
  for (let attempt = 0; attempt < 200; attempt++) {
    if (mock.findFirst(method, MOCK_STAGE_BEGIN) !== null) {
      return;
    }
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 1);
    });
  }
}

/**
 * 计时会话状态机契约测试（Phase 1 红 → Phase 2 绿）。
 * 对应 docs/plans/recording-session-store-refactor-plan.md §4 Phase 1 用例表。
 */
export default function recordingSessionStoreSpec() {
  describe('RecordingSessionStoreSpec', () => {
    it('start_idle_success_updatesSnapshotAndEmitsAfter', 0, async () => {
      const fx = new StoreFixture();
      fx.mock.nextStartTime = 10000;
      const events: Array<SessionSnapshot | null> = [];
      const snapshotsAtEvent: Array<SessionSnapshot | null> = [];
      fx.store.onSessionChange((snapshot: SessionSnapshot | null) => {
        events.push(snapshot);
        snapshotsAtEvent.push(fx.store.snapshot());
      });

      const result = await fx.store.start('A');
      expect(result).assertEqual(StartResult.SUCCESS);
      expect(fx.mock.countCalls(MOCK_METHOD_START, MOCK_STAGE_BEGIN)).assertEqual(1);

      const snapshot = fx.store.snapshot();
      expect(snapshot !== null).assertTrue();
      if (snapshot !== null) {
        expect(snapshot.phase).assertEqual(RecordingPhase.RUNNING);
        expect(snapshot.itemId).assertEqual('A');
        expect(snapshot.recordId).assertEqual('record_A_1');
        expect(snapshot.startTime).assertEqual(10000);
        expect(snapshot.title).assertEqual('title_A');
      }

      // 事件发布顺序契约：回调触发时 snapshot() 必须已是 Running
      expect(events.length).assertEqual(1);
      const atEvent = snapshotsAtEvent.length > 0 ? snapshotsAtEvent[0] : null;
      expect(atEvent !== null).assertTrue();
      if (atEvent !== null) {
        expect(atEvent.phase).assertEqual(RecordingPhase.RUNNING);
      }
    });

    it('start_dbFailure_returnsToIdleWithoutEvent', 0, async () => {
      const fx = new StoreFixture();
      fx.mock.startError = new Error('db down');
      let eventCount = 0;
      fx.store.onSessionChange((snapshot: SessionSnapshot | null) => {
        eventCount += 1;
      });

      const result = await fx.store.start('A');
      expect(result).assertEqual(StartResult.DB_ERROR);
      expect(fx.store.snapshot()).assertNull();
      expect(eventCount).assertEqual(0);
      expect(fx.mock.countCalls(MOCK_METHOD_STOP, MOCK_STAGE_BEGIN)).assertEqual(0);

      // 回 Idle：修复 DB 后可再次成功 start
      fx.mock.startError = null;
      fx.mock.nextStartTime = 20000;
      const retry = await fx.store.start('A');
      expect(retry).assertEqual(StartResult.SUCCESS);
      const retrySnapshot = fx.store.snapshot();
      expect(retrySnapshot !== null).assertTrue();
    });

    it('start_sameItemWhileRunning_isIdempotent', 0, async () => {
      const fx = new StoreFixture();
      await fx.store.start('A');

      let eventCount = 0;
      fx.store.onSessionChange((snapshot: SessionSnapshot | null) => {
        eventCount += 1;
      });
      const again = await fx.store.start('A');
      expect(again).assertEqual(StartResult.SUCCESS);
      expect(fx.mock.countCalls(MOCK_METHOD_START, MOCK_STAGE_BEGIN)).assertEqual(1);
      expect(eventCount).assertEqual(0);

      const snapshot = fx.store.snapshot();
      expect(snapshot !== null).assertTrue();
      if (snapshot !== null) {
        expect(snapshot.recordId).assertEqual('record_A_1');
        expect(snapshot.phase).assertEqual(RecordingPhase.RUNNING);
      }
    });

    it('start_otherItemWhileRunning_blocked', 0, async () => {
      const fx = new StoreFixture();
      await fx.store.start('A');

      const result = await fx.store.start('B');
      expect(result).assertEqual(StartResult.BLOCKED_RUNNING);
      expect(fx.mock.countCalls(MOCK_METHOD_START, MOCK_STAGE_BEGIN)).assertEqual(1);

      const snapshot = fx.store.snapshot();
      expect(snapshot !== null).assertTrue();
      if (snapshot !== null) {
        expect(snapshot.itemId).assertEqual('A');
        expect(snapshot.recordId).assertEqual('record_A_1');
        expect(snapshot.phase).assertEqual(RecordingPhase.RUNNING);
      }
    });

    it('stop_success_clearsSnapshotAndEmitsAfter', 0, async () => {
      const fx = new StoreFixture();
      await fx.store.start('A');

      const events: Array<SessionSnapshot | null> = [];
      const snapshotsAtEvent: Array<SessionSnapshot | null> = [];
      fx.store.onSessionChange((snapshot: SessionSnapshot | null) => {
        events.push(snapshot);
        snapshotsAtEvent.push(fx.store.snapshot());
      });

      const result = await fx.store.stop('A');
      expect(result).assertEqual(StopResult.SUCCESS);
      expect(fx.mock.countCalls(MOCK_METHOD_STOP, MOCK_STAGE_BEGIN)).assertEqual(1);

      const stopBegin = fx.mock.findFirst(MOCK_METHOD_STOP, MOCK_STAGE_BEGIN);
      expect(stopBegin !== null).assertTrue();
      if (stopBegin !== null) {
        expect(stopBegin.itemId).assertEqual('A');
        expect(stopBegin.recordId).assertEqual('record_A_1');
      }

      expect(fx.store.snapshot()).assertNull();
      expect(events.length).assertEqual(1);
      expect(events[0] === null).assertTrue();
      expect(snapshotsAtEvent.length).assertEqual(1);
      expect(snapshotsAtEvent[0] === null).assertTrue();
    });

    it('stop_dbFailure_keepsRunningSnapshot', 0, async () => {
      const fx = new StoreFixture();
      await fx.store.start('A');
      fx.mock.stopError = new Error('db down');

      let eventCount = 0;
      fx.store.onSessionChange((snapshot: SessionSnapshot | null) => {
        eventCount += 1;
      });

      const result = await fx.store.stop('A');
      expect(result).assertEqual(StopResult.DB_ERROR);

      // 副作用不回滚真相：DB 停止失败时快照保持 Running
      const snapshot = fx.store.snapshot();
      expect(snapshot !== null).assertTrue();
      if (snapshot !== null) {
        expect(snapshot.phase).assertEqual(RecordingPhase.RUNNING);
        expect(snapshot.recordId).assertEqual('record_A_1');
      }
      expect(eventCount).assertEqual(0);
    });

    it('commandQueue_startThenStop_serialized', 0, async () => {
      const fx = new StoreFixture();
      fx.mock.nextStartTime = 1000;
      fx.mock.holdStart = true;

      const startPromise = fx.store.start('B');
      await waitForMockBegin(fx.mock, MOCK_METHOD_START);
      const stopPromise = fx.store.stop('B');

      // start 挂起期间（Starting），stop 不得进入 DB
      expect(fx.mock.countCalls(MOCK_METHOD_STOP, MOCK_STAGE_BEGIN)).assertEqual(0);

      fx.mock.releaseGates();
      const startResult = await settleStart(startPromise);
      const stopResult = await settleStop(stopPromise);
      expect(startResult).assertEqual(StartResult.SUCCESS);
      expect(stopResult).assertEqual(StopResult.SUCCESS);

      expect(fx.mock.callSequence()).assertEqual(
        'start:B.begin,start:B.end,stop:B.begin,stop:B.end'
      );
      expect(fx.store.snapshot()).assertNull();
    });

    it('commandQueue_stopThenStart_serialized', 0, async () => {
      const fx = new StoreFixture();
      await fx.store.start('A');

      fx.mock.holdStop = true;
      const stopPromise = fx.store.stop('A');
      await waitForMockBegin(fx.mock, MOCK_METHOD_STOP);
      // Stopping 期间任何 start 排队而非拒绝
      const startPromise = fx.store.start('B');

      expect(fx.mock.countCalls(MOCK_METHOD_START, MOCK_STAGE_BEGIN)).assertEqual(1);

      fx.mock.releaseGates();
      const stopResult = await settleStop(stopPromise);
      const startResult = await settleStart(startPromise);
      expect(stopResult).assertEqual(StopResult.SUCCESS);
      expect(startResult).assertEqual(StartResult.SUCCESS);

      expect(fx.mock.callSequence()).assertEqual(
        'start:A.begin,start:A.end,stop:A.begin,stop:A.end,start:B.begin,start:B.end'
      );

      const snapshot = fx.store.snapshot();
      expect(snapshot !== null).assertTrue();
      if (snapshot !== null) {
        expect(snapshot.itemId).assertEqual('B');
        expect(snapshot.phase).assertEqual(RecordingPhase.RUNNING);
      }
    });

    it('adoptOpenRecord_overwritesFromDb', 0, async () => {
      const fx = new StoreFixture();
      fx.mock.openRecordForItem = buildOpenRecord('X', 'rec_X', 5000, 'title_X', '#00FF00');
      let eventCount = 0;
      fx.store.onSessionChange((snapshot: SessionSnapshot | null) => {
        eventCount += 1;
      });

      // 有记录 → Running，且不触发 start/stop 命令
      await fx.store.adoptOpenRecord('X');
      const snapshot = fx.store.snapshot();
      expect(snapshot !== null).assertTrue();
      if (snapshot !== null) {
        expect(snapshot.phase).assertEqual(RecordingPhase.RUNNING);
        expect(snapshot.itemId).assertEqual('X');
        expect(snapshot.recordId).assertEqual('rec_X');
        expect(snapshot.startTime).assertEqual(5000);
      }
      expect(fx.mock.countCalls(MOCK_METHOD_START, MOCK_STAGE_BEGIN)).assertEqual(0);
      expect(fx.mock.countCalls(MOCK_METHOD_STOP, MOCK_STAGE_BEGIN)).assertEqual(0);
      expect(eventCount).assertEqual(1);

      // 无记录 → Idle
      fx.mock.openRecordForItem = null;
      await fx.store.adoptOpenRecord('X');
      expect(fx.store.snapshot()).assertNull();
      expect(eventCount).assertEqual(2);
    });

    it('restoreFromDb_runsOnlyOnce', 0, async () => {
      const fx = new StoreFixture();
      fx.mock.newestOpenRecord = buildOpenRecord('A', 'rec_A', 1234, 'title_A', '#FF4444');
      await fx.store.restoreFromDb();
      const first = fx.store.snapshot();
      expect(first !== null).assertTrue();
      if (first !== null) {
        expect(first.recordId).assertEqual('rec_A');
        expect(first.phase).assertEqual(RecordingPhase.RUNNING);
      }

      // 二次调用 no-op：不再查询 DB，也不覆写已有内存态
      fx.mock.newestOpenRecord = buildOpenRecord('B', 'rec_B', 5678, 'title_B', '#FF4444');
      await fx.store.restoreFromDb();
      expect(fx.mock.countCalls(MOCK_METHOD_QUERY_NEWEST, MOCK_STAGE_BEGIN)).assertEqual(1);
      const second = fx.store.snapshot();
      expect(second !== null).assertTrue();
      if (second !== null) {
        expect(second.recordId).assertEqual('rec_A');
      }
    });

    it('elapsedSeconds_derivedFromInjectedClock', 0, async () => {
      const fx = new StoreFixture();
      fx.clock.nowMs = 100000;
      fx.mock.nextStartTime = 100000;
      await fx.store.start('A');
      expect(fx.store.elapsedSeconds()).assertEqual(0);

      fx.clock.advance(1500);
      expect(fx.store.elapsedSeconds()).assertEqual(1);
      fx.clock.advance(499);
      expect(fx.store.elapsedSeconds()).assertEqual(1);
      fx.clock.advance(2);
      expect(fx.store.elapsedSeconds()).assertEqual(2);

      // 停止后归零
      await fx.store.stop('A');
      expect(fx.store.elapsedSeconds()).assertEqual(0);

      // adopt 场景：startTime 早于当前时钟也能正确派生
      fx.mock.openRecordForItem = buildOpenRecord('Y', 'rec_Y', fx.clock.nowMs - 2500, 'title_Y', '#FF4444');
      await fx.store.adoptOpenRecord('Y');
      expect(fx.store.elapsedSeconds()).assertEqual(2);
    });

    it('stop_whenIdle_isNoop', 0, async () => {
      const fx = new StoreFixture();
      let eventCount = 0;
      fx.store.onSessionChange((snapshot: SessionSnapshot | null) => {
        eventCount += 1;
      });

      const result = await fx.store.stop('A');
      expect(result).assertEqual(StopResult.NOT_RUNNING);
      expect(fx.mock.countCalls(MOCK_METHOD_STOP, MOCK_STAGE_BEGIN)).assertEqual(0);
      expect(fx.store.snapshot()).assertNull();
      expect(eventCount).assertEqual(0);
    });
  });
}
