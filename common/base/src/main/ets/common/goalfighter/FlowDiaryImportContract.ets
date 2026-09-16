/**
 * FlowDiary -> GoalFighter 导入协议（纯逻辑，无 UI / 上下文依赖）。
 *
 * 记录来源使用结构化接口而非 TimeRecord 类，保证本模块可独立单测，
 * TimeRecord 实例满足该接口的结构约束，可直接传入。
 */

export const FLOW_DIARY_IMPORT_VERSION: number = 1;
export const FLOW_DIARY_IMPORT_EVENT_TEXT_MAX_LENGTH: number = 500;
export const FLOW_DIARY_IMPORT_MS_PER_MINUTE: number = 60 * 1000;

export type FlowDiaryImportMode = 'single' | 'batch';

export interface FlowDiaryShareableTimeRecord {
  id: string;
  startTime: number;
  endTime?: number;
  duration?: number;
}

export interface FlowDiaryImportRecord {
  sourceRecordId: string;
  occurredOn: string;
  durationMinutes: number;
  startAt: number;
  endAt: number;
  eventText: string;
}

export interface FlowDiaryImportEnvelope {
  version: number;
  mode: FlowDiaryImportMode;
  requestId: string;
  sourceActivityId: string;
  sourceActivityTitle: string;
  records: FlowDiaryImportRecord[];
}

/**
 * 解析记录的有效时长（毫秒）：优先使用合法的 record.duration，否则回退 endTime - startTime。
 */
export function resolveFlowDiaryRecordDurationMs(record: FlowDiaryShareableTimeRecord): number {
  if (record.duration !== undefined && Number.isFinite(record.duration) && record.duration > 0) {
    return record.duration;
  }
  if (record.endTime !== undefined && Number.isFinite(record.endTime)) {
    return record.endTime - record.startTime;
  }
  return 0;
}

/**
 * 仅满足以下条件的记录允许分享：已结束、结束晚于开始、时长大于 0。
 * 正在计时的 open record（endTime 缺失）会被排除。
 */
export function isShareableFlowDiaryRecord(record: FlowDiaryShareableTimeRecord): boolean {
  if (record.endTime === undefined || !Number.isFinite(record.endTime)) {
    return false;
  }
  if (record.endTime <= record.startTime) {
    return false;
  }
  return resolveFlowDiaryRecordDurationMs(record) > 0;
}

/**
 * 将 startTime（毫秒时间戳）格式化为本地时区 YYYY-MM-DD。
 */
export function formatFlowDiaryOccurredOn(startTime: number): string {
  const date = new Date(startTime);
  const year = date.getFullYear();
  const month = date.getMonth() + 1;
  const day = date.getDate();
  const paddedMonth = month < 10 ? `0${month}` : `${month}`;
  const paddedDay = day < 10 ? `0${day}` : `${day}`;
  return `${year}-${paddedMonth}-${paddedDay}`;
}

/**
 * 毫秒时长转分钟数，不足一分钟按 1 分钟计。
 */
export function toFlowDiaryDurationMinutes(durationMs: number): number {
  if (!Number.isFinite(durationMs) || durationMs <= 0) {
    return 1;
  }
  return Math.max(1, Math.ceil(durationMs / FLOW_DIARY_IMPORT_MS_PER_MINUTE));
}

/**
 * 截断事项标题到协议上限，防止超长 payload。
 */
export function truncateFlowDiaryEventText(eventText: string): string {
  if (eventText.length <= FLOW_DIARY_IMPORT_EVENT_TEXT_MAX_LENGTH) {
    return eventText;
  }
  return eventText.substring(0, FLOW_DIARY_IMPORT_EVENT_TEXT_MAX_LENGTH);
}

/**
 * 将单条 TimeRecord 映射为协议记录；不满足分享条件时返回 null。
 * sourceRecordId 保持原值，不做任何 UUID 转换。
 */
export function buildFlowDiaryImportRecord(record: FlowDiaryShareableTimeRecord,
  eventText: string): FlowDiaryImportRecord | null {
  if (!isShareableFlowDiaryRecord(record)) {
    return null;
  }
  return {
    sourceRecordId: record.id,
    occurredOn: formatFlowDiaryOccurredOn(record.startTime),
    durationMinutes: toFlowDiaryDurationMinutes(resolveFlowDiaryRecordDurationMs(record)),
    startAt: record.startTime,
    endAt: record.endTime as number,
    eventText: truncateFlowDiaryEventText(eventText)
  };
}

/**
 * 构造分享信封：过滤不可分享记录并按 startAt 升序排列。
 * 过滤后为空批次时返回 null，调用方不应继续拉起 GoalFighter。
 */
export function buildFlowDiaryImportEnvelope(mode: FlowDiaryImportMode,
  records: FlowDiaryShareableTimeRecord[], sourceActivityId: string, sourceActivityTitle: string,
  requestId: string): FlowDiaryImportEnvelope | null {
  if (records.length === 0) {
    return null;
  }
  const importRecords: FlowDiaryImportRecord[] = [];
  for (let i = 0; i < records.length; i++) {
    const importRecord = buildFlowDiaryImportRecord(records[i], sourceActivityTitle);
    if (importRecord !== null) {
      importRecords.push(importRecord);
    }
  }
  if (importRecords.length === 0) {
    return null;
  }
  importRecords.sort((left: FlowDiaryImportRecord, right: FlowDiaryImportRecord): number =>
    left.startAt - right.startAt);
  return {
    version: FLOW_DIARY_IMPORT_VERSION,
    mode: mode,
    requestId: requestId,
    sourceActivityId: sourceActivityId,
    sourceActivityTitle: truncateFlowDiaryEventText(sourceActivityTitle),
    records: importRecords
  };
}

/**
 * 每次点击分享生成新的 requestId，仅用于本次传输去重，不能代替 sourceRecordId。
 */
export function generateFlowDiaryImportRequestId(): string {
  return `fdy-${Date.now().toString(36)}-${Math.random().toString(36).substring(2, 10)}`;
}
