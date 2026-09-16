import type { SessionCommands } from '../main/ets/recording/SessionCommands';
import { OpenRecordInfo } from '../main/ets/recording/RecordingSessionTypes';

/** mock 方法名（调用流水用） */
export const MOCK_METHOD_START = 'start';
export const MOCK_METHOD_STOP = 'stop';
export const MOCK_METHOD_QUERY_OPEN = 'queryOpen';
export const MOCK_METHOD_QUERY_NEWEST = 'queryNewest';

/** mock 调用阶段：begin=进入方法；end=成功；error=抛出 */
export const MOCK_STAGE_BEGIN = 'begin';
export const MOCK_STAGE_END = 'end';
export const MOCK_STAGE_ERROR = 'error';

/** 单次 DB 调用流水记录，seq 全局单调递增，用于串行化断言 */
export class MockCall {
  method: string = '';
  itemId: string = '';
  recordId: string = '';
  stage: string = '';
  seq: number = 0;
}

export function buildOpenRecord(itemId: string, recordId: string, startTime: number, title: string, color: string): OpenRecordInfo {
  const info = new OpenRecordInfo();
  info.itemId = itemId;
  info.recordId = recordId;
  info.startTime = startTime;
  info.title = title;
  info.color = color;
  return info;
}

/**
 * SessionCommands 的纯内存 mock（不连真库）。
 * 行为可配置：错误注入（startError 等）、开放记录返回值（openRecordForItem/newestOpenRecord）、
 * 门闩（holdStart/holdStop=true 时对应调用挂起，直到 releaseGates()），用于命令队列串行化验证。
 */
export class MockSessionCommands implements SessionCommands {
  calls: Array<MockCall> = [];
  startError: Error | null = null;
  stopError: Error | null = null;
  queryOpenError: Error | null = null;
  queryNewestError: Error | null = null;
  openRecordForItem: OpenRecordInfo | null = null;
  newestOpenRecord: OpenRecordInfo | null = null;
  nextStartTime: number = 0;
  holdStart: boolean = false;
  holdStop: boolean = false;
  private nextSeq: number = 0;
  private recordIdSeed: number = 0;
  private gates: Array<() => void> = [];

  async startSession(itemId: string): Promise<OpenRecordInfo> {
    this.log(MOCK_METHOD_START, itemId, '', MOCK_STAGE_BEGIN);
    if (this.holdStart) {
      await this.waitForGate();
    }
    if (this.startError !== null) {
      this.log(MOCK_METHOD_START, itemId, '', MOCK_STAGE_ERROR);
      throw this.startError;
    }
    this.recordIdSeed += 1;
    const recordId = `record_${itemId}_${this.recordIdSeed}`;
    const info = buildOpenRecord(itemId, recordId, this.nextStartTime, `title_${itemId}`, '#FF4444');
    this.log(MOCK_METHOD_START, itemId, recordId, MOCK_STAGE_END);
    return info;
  }

  async stopSession(itemId: string, recordId: string): Promise<void> {
    this.log(MOCK_METHOD_STOP, itemId, recordId, MOCK_STAGE_BEGIN);
    if (this.holdStop) {
      await this.waitForGate();
    }
    if (this.stopError !== null) {
      this.log(MOCK_METHOD_STOP, itemId, recordId, MOCK_STAGE_ERROR);
      throw this.stopError;
    }
    this.log(MOCK_METHOD_STOP, itemId, recordId, MOCK_STAGE_END);
  }

  async queryOpenRecord(itemId: string): Promise<OpenRecordInfo | null> {
    this.log(MOCK_METHOD_QUERY_OPEN, itemId, '', MOCK_STAGE_BEGIN);
    if (this.queryOpenError !== null) {
      this.log(MOCK_METHOD_QUERY_OPEN, itemId, '', MOCK_STAGE_ERROR);
      throw this.queryOpenError;
    }
    this.log(MOCK_METHOD_QUERY_OPEN, itemId, '', MOCK_STAGE_END);
    return this.openRecordForItem;
  }

  async queryNewestOpenRecord(): Promise<OpenRecordInfo | null> {
    this.log(MOCK_METHOD_QUERY_NEWEST, '', '', MOCK_STAGE_BEGIN);
    if (this.queryNewestError !== null) {
      this.log(MOCK_METHOD_QUERY_NEWEST, '', '', MOCK_STAGE_ERROR);
      throw this.queryNewestError;
    }
    this.log(MOCK_METHOD_QUERY_NEWEST, '', '', MOCK_STAGE_END);
    return this.newestOpenRecord;
  }

  countCalls(method: string, stage: string): number {
    let count = 0;
    this.calls.forEach((call: MockCall) => {
      if (call.method === method && (stage === '' || call.stage === stage)) {
        count += 1;
      }
    });
    return count;
  }

  findFirst(method: string, stage: string): MockCall | null {
    for (let i = 0; i < this.calls.length; i++) {
      if (this.calls[i].method === method && this.calls[i].stage === stage) {
        return this.calls[i];
      }
    }
    return null;
  }

  /** 全部调用按 seq 拼接为 "method:itemId.stage,..."，用于断言无交错 */
  callSequence(): string {
    const parts: Array<string> = [];
    this.calls.forEach((call: MockCall) => {
      parts.push(`${call.method}:${call.itemId}.${call.stage}`);
    });
    return parts.join(',');
  }

  releaseGates(): void {
    const pending = this.gates;
    this.gates = [];
    pending.forEach((resolve: () => void) => {
      resolve();
    });
  }

  private waitForGate(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      this.gates.push(resolve);
    });
  }

  private log(method: string, itemId: string, recordId: string, stage: string): void {
    this.nextSeq += 1;
    const call = new MockCall();
    call.method = method;
    call.itemId = itemId;
    call.recordId = recordId;
    call.stage = stage;
    call.seq = this.nextSeq;
    this.calls.push(call);
  }
}
