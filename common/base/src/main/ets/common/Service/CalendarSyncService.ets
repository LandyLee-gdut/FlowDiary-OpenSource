import { common } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  RDBStoreUtil,
  TimeRecordCalendarMapItem,
  TimeRecordCalendarMapUpsertInput,
  TimeRecordCalendarPendingAction,
  TimeRecordCalendarSyncStatus
} from '../../database/RDBStoreUtil';
import { TimeRecord } from '../model/TimeRecord';

const TAG: string = 'CalendarSyncService';
const DEFAULT_EVENT_TITLE: string = '未命名事项';
const EVENT_DESCRIPTION_SOURCE: string = '来自FlowDiary 流光';
const EVENT_MISSING_ERROR_CODE: number = 115004;
const IDENTIFIER_SEARCH_PADDING_MS: number = 24 * 60 * 60 * 1000;

export interface CalendarBootstrapResult {
  total: number;
  success: number;
}

export class CalendarSyncService {
  async upsertByTimeRecord(recordId: string): Promise<boolean> {
    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      return false;
    }

    const rdbStoreUtil: RDBStoreUtil = RDBStoreUtil.getInstance();
    const mapping: TimeRecordCalendarMapItem | null =
      await rdbStoreUtil.queryTimeRecordCalendarMapByRecordId(normalizedRecordId);

    const record: TimeRecord | null = await rdbStoreUtil.queryTimeRecordById(normalizedRecordId);
    if (!record) {
      await rdbStoreUtil.deleteTimeRecordCalendarMapByRecordId(normalizedRecordId);
      this.logSync('upsert', normalizedRecordId, this.toLogEventId(mapping?.calendarEventId), 'record_missing_cleanup', 0, false);
      return true;
    }

    if (!this.isClosedRecord(record)) {
      this.logSync('upsert', normalizedRecordId, this.toLogEventId(mapping?.calendarEventId), 'skip_open_record', 0, false);
      return false;
    }

    let targetEventId: number | undefined = mapping?.calendarEventId;
    let resolvedCalendarId: number = mapping ? mapping.calendarId : 0;

    await this.persistMapping({
      timeRecordId: normalizedRecordId,
      calendarId: resolvedCalendarId,
      calendarEventId: targetEventId,
      syncStatus: TimeRecordCalendarSyncStatus.PENDING,
      pendingAction: TimeRecordCalendarPendingAction.UPSERT
    });

    try {
      const calendar: calendarManager.Calendar = await this.getDefaultCalendar();
      const eventTemplate: calendarManager.Event = await this.buildEventForRecord(record);
      resolvedCalendarId = calendar.id;

      if (typeof targetEventId === 'number' && targetEventId > 0) {
        const updateEvent: calendarManager.Event = {
          type: eventTemplate.type,
          title: eventTemplate.title,
          description: eventTemplate.description,
          identifier: eventTemplate.identifier,
          startTime: eventTemplate.startTime,
          endTime: eventTemplate.endTime,
          id: targetEventId
        };

        try {
          await calendar.updateEvent(updateEvent);
          await this.persistSyncedMapping(normalizedRecordId, calendar.id, targetEventId);
          this.logSync('upsert', normalizedRecordId, targetEventId, 'updated', 0, false);
          return true;
        } catch (err) {
          const updateError = err as BusinessError;
          const updateErrorCode: number = this.resolveErrorCode(updateError);
          if (updateErrorCode !== EVENT_MISSING_ERROR_CODE) {
            await this.persistMapping({
              timeRecordId: normalizedRecordId,
              calendarId: resolvedCalendarId,
              calendarEventId: targetEventId,
              syncStatus: TimeRecordCalendarSyncStatus.FAILED,
              pendingAction: TimeRecordCalendarPendingAction.UPSERT,
              lastErrorCode: updateErrorCode
            });
            this.logSync('upsert', normalizedRecordId, this.toLogEventId(targetEventId), 'failed', updateErrorCode, true);
            return false;
          }
          this.logSync('upsert', normalizedRecordId, targetEventId, 'event_missing_recreate', updateErrorCode, false);
        }
      }

      const matchedEventId: number | null = await this.findExistingEventIdByIdentifier(
        calendar,
        eventTemplate.identifier,
        eventTemplate.startTime,
        eventTemplate.endTime
      );
      if (typeof matchedEventId === 'number' && matchedEventId > 0) {
        const relinkEvent: calendarManager.Event = {
          type: eventTemplate.type,
          title: eventTemplate.title,
          description: eventTemplate.description,
          identifier: eventTemplate.identifier,
          startTime: eventTemplate.startTime,
          endTime: eventTemplate.endTime,
          id: matchedEventId
        };
        await calendar.updateEvent(relinkEvent);
        await this.persistSyncedMapping(normalizedRecordId, calendar.id, matchedEventId);
        this.logSync('upsert', normalizedRecordId, matchedEventId, 'relinked_by_identifier', 0, false);
        return true;
      }

      targetEventId = await calendar.addEvent(eventTemplate);
      await this.persistSyncedMapping(normalizedRecordId, calendar.id, targetEventId);
      this.logSync('upsert', normalizedRecordId, targetEventId, 'created', 0, false);
      return true;
    } catch (err) {
      const businessError = err as BusinessError;
      const errorCode: number = this.resolveErrorCode(businessError);
      await this.persistMapping({
        timeRecordId: normalizedRecordId,
        calendarId: resolvedCalendarId,
        calendarEventId: targetEventId,
        syncStatus: TimeRecordCalendarSyncStatus.FAILED,
        pendingAction: TimeRecordCalendarPendingAction.UPSERT,
        lastErrorCode: errorCode
      });
      this.logSync('upsert', normalizedRecordId, this.toLogEventId(targetEventId), 'failed', errorCode, true);
      return false;
    }
  }

  async deleteByTimeRecord(recordId: string): Promise<boolean> {
    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      return false;
    }

    const rdbStoreUtil: RDBStoreUtil = RDBStoreUtil.getInstance();
    const mapping: TimeRecordCalendarMapItem | null =
      await rdbStoreUtil.queryTimeRecordCalendarMapByRecordId(normalizedRecordId);

    if (!mapping) {
      this.logSync('delete', normalizedRecordId, 0, 'mapping_missing_skip', 0, false);
      return true;
    }

    await this.persistMapping({
      timeRecordId: normalizedRecordId,
      calendarId: mapping.calendarId,
      calendarEventId: mapping.calendarEventId,
      syncStatus: TimeRecordCalendarSyncStatus.PENDING,
      pendingAction: TimeRecordCalendarPendingAction.DELETE
    });

    if (typeof mapping.calendarEventId !== 'number' || mapping.calendarEventId <= 0) {
      await rdbStoreUtil.deleteTimeRecordCalendarMapByRecordId(normalizedRecordId);
      this.logSync('delete', normalizedRecordId, 0, 'mapping_without_event_deleted', 0, false);
      return true;
    }

    try {
      const calendar: calendarManager.Calendar = await this.getDefaultCalendar();
      await calendar.deleteEvent(mapping.calendarEventId);
      await rdbStoreUtil.deleteTimeRecordCalendarMapByRecordId(normalizedRecordId);
      this.logSync('delete', normalizedRecordId, mapping.calendarEventId, 'deleted', 0, false);
      return true;
    } catch (err) {
      const businessError = err as BusinessError;
      const errorCode: number = this.resolveErrorCode(businessError);
      if (errorCode === EVENT_MISSING_ERROR_CODE) {
        await rdbStoreUtil.deleteTimeRecordCalendarMapByRecordId(normalizedRecordId);
        this.logSync('delete', normalizedRecordId, mapping.calendarEventId, 'already_deleted_cleanup', errorCode, false);
        return true;
      }

      await this.persistMapping({
        timeRecordId: normalizedRecordId,
        calendarId: mapping.calendarId,
        calendarEventId: mapping.calendarEventId,
        syncStatus: TimeRecordCalendarSyncStatus.FAILED,
        pendingAction: TimeRecordCalendarPendingAction.DELETE,
        lastErrorCode: errorCode
      });
      this.logSync('delete', normalizedRecordId, mapping.calendarEventId, 'failed', errorCode, true);
      return false;
    }
  }

  async deleteByTimeRecords(recordIds: string[]): Promise<boolean> {
    const normalizedRecordIds: string[] = this.normalizeRecordIds(recordIds);
    if (normalizedRecordIds.length === 0) {
      return true;
    }

    const rdbStoreUtil: RDBStoreUtil = RDBStoreUtil.getInstance();
    const mappings: TimeRecordCalendarMapItem[] =
      await rdbStoreUtil.queryTimeRecordCalendarMapsByRecordIds(normalizedRecordIds);

    if (mappings.length === 0) {
      return true;
    }

    for (const mapping of mappings) {
      await this.persistMapping({
        timeRecordId: mapping.timeRecordId,
        calendarId: mapping.calendarId,
        calendarEventId: mapping.calendarEventId,
        syncStatus: TimeRecordCalendarSyncStatus.PENDING,
        pendingAction: TimeRecordCalendarPendingAction.DELETE
      });
    }

    const eventIds: number[] = mappings
      .map((mapping: TimeRecordCalendarMapItem) => mapping.calendarEventId)
      .filter((eventId: number | undefined) => typeof eventId === 'number' && eventId > 0) as number[];

    try {
      if (eventIds.length > 0) {
        const calendar: calendarManager.Calendar = await this.getDefaultCalendar();
        if (eventIds.length === 1) {
          await calendar.deleteEvent(eventIds[0]);
        } else {
          await calendar.deleteEvents(eventIds);
        }
      }

      const deleteCount: number = await rdbStoreUtil.deleteTimeRecordCalendarMapsByRecordIds(
        mappings.map((mapping: TimeRecordCalendarMapItem) => mapping.timeRecordId)
      );
      const result: boolean = deleteCount >= 0;
      this.logSync('delete_batch', normalizedRecordIds.join(','), eventIds.length, result ? 'deleted' : 'mapping_delete_failed', 0,
        !result);
      return result;
    } catch (err) {
      const businessError = err as BusinessError;
      const errorCode: number = this.resolveErrorCode(businessError);
      this.logSync('delete_batch', normalizedRecordIds.join(','), eventIds.length, 'batch_failed_fallback', errorCode, true);

      let allSuccess: boolean = true;
      for (const mapping of mappings) {
        const success: boolean = await this.deleteByTimeRecord(mapping.timeRecordId);
        if (!success) {
          allSuccess = false;
        }
      }
      return allSuccess;
    }
  }

  async reconcilePending(): Promise<number> {
    const rdbStoreUtil: RDBStoreUtil = RDBStoreUtil.getInstance();
    const pendingRows: TimeRecordCalendarMapItem[] = await rdbStoreUtil.queryTimeRecordCalendarMapsBySyncStatus([
      TimeRecordCalendarSyncStatus.PENDING,
      TimeRecordCalendarSyncStatus.FAILED
    ]);

    let successCount: number = 0;
    for (const row of pendingRows) {
      let success: boolean;
      if (row.pendingAction === TimeRecordCalendarPendingAction.DELETE) {
        success = await this.deleteByTimeRecord(row.timeRecordId);
      } else {
        success = await this.upsertByTimeRecord(row.timeRecordId);
      }

      if (success) {
        successCount += 1;
      }
    }

    this.logSync('reconcile', `rows=${pendingRows.length}`, successCount, 'completed', 0, false);
    return successCount;
  }

  async bootstrapClosedRecords(startMs: number, endMs: number): Promise<CalendarBootstrapResult> {
    const safeStartMs: number = Math.max(0, startMs);
    const safeEndMs: number = Math.max(safeStartMs, endMs);
    const rdbStoreUtil: RDBStoreUtil = RDBStoreUtil.getInstance();
    const records = await rdbStoreUtil.queryTimeRecordsWithActivityAndTag(safeStartMs, safeEndMs);
    const closedRecordIds: string[] = this.normalizeRecordIds(
      records
        .filter(record => typeof record.endTimeMs === 'number' && record.endTimeMs > record.startTimeMs)
        .map(record => record.recordId)
    );

    let successCount: number = 0;
    for (const recordId of closedRecordIds) {
      const success: boolean = await this.upsertByTimeRecord(recordId);
      if (success) {
        successCount += 1;
      }
    }

    this.logSync('bootstrap', `${safeStartMs}-${safeEndMs}`, successCount, `total=${closedRecordIds.length}`, 0, false);
    return {
      total: closedRecordIds.length,
      success: successCount
    };
  }

  async cleanupAllMappedEvents(): Promise<boolean> {
    const rdbStoreUtil: RDBStoreUtil = RDBStoreUtil.getInstance();
    const mappings: TimeRecordCalendarMapItem[] = await rdbStoreUtil.queryTimeRecordCalendarMapsBySyncStatus([
      TimeRecordCalendarSyncStatus.PENDING,
      TimeRecordCalendarSyncStatus.SYNCED,
      TimeRecordCalendarSyncStatus.FAILED
    ]);
    const mappedRecordIds: string[] = this.normalizeRecordIds(
      mappings.map((mapping: TimeRecordCalendarMapItem) => mapping.timeRecordId)
    );
    if (mappedRecordIds.length === 0) {
      return true;
    }
    return this.deleteByTimeRecords(mappedRecordIds);
  }

  async rebuildMissingMappings(startMs: number, endMs: number, maxRecords?: number): Promise<CalendarBootstrapResult> {
    const safeStartMs: number = Math.max(0, startMs);
    const safeEndMs: number = Math.max(safeStartMs, endMs);
    const rdbStoreUtil: RDBStoreUtil = RDBStoreUtil.getInstance();
    const records = await rdbStoreUtil.queryTimeRecordsWithActivityAndTag(safeStartMs, safeEndMs);
    const closedRecordIds: string[] = this.normalizeRecordIds(
      records
        .filter((record) => typeof record.endTimeMs === 'number' && record.endTimeMs > record.startTimeMs)
        .map((record) => record.recordId)
    );
    if (closedRecordIds.length === 0) {
      return { total: 0, success: 0 };
    }

    const existingMappings: TimeRecordCalendarMapItem[] =
      await rdbStoreUtil.queryTimeRecordCalendarMapsByRecordIds(closedRecordIds);
    const mappingByRecordId: Map<string, TimeRecordCalendarMapItem> = new Map();
    existingMappings.forEach((mapping: TimeRecordCalendarMapItem) => {
      mappingByRecordId.set(mapping.timeRecordId, mapping);
    });

    const missingRecordIds: string[] = closedRecordIds.filter((recordId: string) => {
      const mapping: TimeRecordCalendarMapItem | undefined = mappingByRecordId.get(recordId);
      if (!mapping) {
        return true;
      }
      return !(typeof mapping.calendarEventId === 'number' && mapping.calendarEventId > 0);
    });
    const hasMaxRecords: boolean = typeof maxRecords === 'number' && maxRecords > 0;
    const targetRecordIds: string[] = hasMaxRecords ? missingRecordIds.slice(0, maxRecords) : missingRecordIds;

    let successCount: number = 0;
    for (const recordId of targetRecordIds) {
      const success: boolean = await this.upsertByTimeRecord(recordId);
      if (success) {
        successCount += 1;
      }
    }

    this.logSync('rebuild_missing', `${safeStartMs}-${safeEndMs}`, successCount, `total=${targetRecordIds.length}`, 0, false);
    return {
      total: targetRecordIds.length,
      success: successCount
    };
  }

  async resyncMappedEventCopy(): Promise<CalendarBootstrapResult> {
    const rdbStoreUtil: RDBStoreUtil = RDBStoreUtil.getInstance();
    const mappings: TimeRecordCalendarMapItem[] = await rdbStoreUtil.queryTimeRecordCalendarMapsBySyncStatus([
      TimeRecordCalendarSyncStatus.PENDING,
      TimeRecordCalendarSyncStatus.SYNCED,
      TimeRecordCalendarSyncStatus.FAILED
    ]);
    const mappedRecordIds: string[] = this.normalizeRecordIds(
      mappings
        .filter((mapping: TimeRecordCalendarMapItem) => typeof mapping.calendarEventId === 'number' && mapping.calendarEventId > 0)
        .map((mapping: TimeRecordCalendarMapItem) => mapping.timeRecordId)
    );
    if (mappedRecordIds.length === 0) {
      this.logSync('resync_copy', 'none', 0, 'mapping_empty_skip', 0, false);
      return { total: 0, success: 0 };
    }

    let successCount: number = 0;
    for (const recordId of mappedRecordIds) {
      const success: boolean = await this.upsertByTimeRecord(recordId);
      if (success) {
        successCount += 1;
      }
    }

    this.logSync('resync_copy', `rows=${mappedRecordIds.length}`, successCount, 'completed', 0, false);
    return {
      total: mappedRecordIds.length,
      success: successCount
    };
  }

  private async buildEventForRecord(record: TimeRecord): Promise<calendarManager.Event> {
    const title: string = await this.resolveActivityTitle(record.activityId);
    const endTime: number = record.endTime as number;
    return {
      type: calendarManager.EventType.NORMAL,
      title,
      description: this.buildEventDescription(record),
      identifier: `flowdiary:${record.id}`,
      startTime: record.startTime,
      endTime
    };
  }

  private async resolveActivityTitle(activityId: string): Promise<string> {
    const activity = await RDBStoreUtil.getInstance().queryActivityById(activityId);
    if (activity && activity.name.trim().length > 0) {
      return activity.name;
    }
    return DEFAULT_EVENT_TITLE;
  }

  private buildEventDescription(record: TimeRecord): string {
    const durationMs: number = this.resolveDurationMs(record);
    return `${EVENT_DESCRIPTION_SOURCE} · 时长 ${this.formatDurationForDescription(durationMs)}`;
  }

  private resolveDurationMs(record: TimeRecord): number {
    if (typeof record.duration === 'number' && record.duration > 0) {
      return record.duration;
    }
    if (typeof record.endTime === 'number' && record.endTime > record.startTime) {
      return record.endTime - record.startTime;
    }
    return 0;
  }

  private formatDurationForDescription(durationMs: number): string {
    if (durationMs <= 0) {
      return '0分钟';
    }
    const totalMinutes: number = Math.floor(durationMs / (60 * 1000));
    const safeMinutes: number = Math.max(1, totalMinutes);
    const hours: number = Math.floor(safeMinutes / 60);
    const minutes: number = safeMinutes % 60;
    if (hours > 0 && minutes > 0) {
      return `${hours}小时${minutes}分钟`;
    }
    if (hours > 0) {
      return `${hours}小时`;
    }
    return `${minutes}分钟`;
  }

  private isClosedRecord(record: TimeRecord): boolean {
    return typeof record.endTime === 'number' && record.endTime > record.startTime;
  }

  private async getDefaultCalendar(): Promise<calendarManager.Calendar> {
    const context: common.UIAbilityContext = this.resolveAbilityContext();
    const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
    return manager.getCalendar();
  }

  private resolveAbilityContext(): common.UIAbilityContext {
    const storedContext = AppStorage.get('context') as common.UIAbilityContext;
    if (storedContext && typeof storedContext.filesDir === 'string' && storedContext.filesDir.length > 0) {
      return storedContext;
    }
    throw new Error('CalendarSyncService UIAbilityContext unavailable in AppStorage(context).');
  }

  private normalizeRecordIds(recordIds: string[]): string[] {
    const normalized: string[] = [];
    const seen: Set<string> = new Set();

    recordIds.forEach((recordId: string) => {
      const value: string = recordId.trim();
      if (!value || seen.has(value)) {
        return;
      }
      seen.add(value);
      normalized.push(value);
    });

    return normalized;
  }

  private async findExistingEventIdByIdentifier(
    calendar: calendarManager.Calendar,
    identifier?: string,
    startTime?: number,
    endTime?: number
  ): Promise<number | null> {
    const normalizedIdentifier: string = typeof identifier === 'string' ? identifier.trim() : '';
    if (!normalizedIdentifier) {
      return null;
    }

    const safeStartTime: number = typeof startTime === 'number' && Number.isFinite(startTime) ? Math.max(0, startTime) : 0;
    const safeEndTime: number = typeof endTime === 'number' && Number.isFinite(endTime)
      ? Math.max(safeStartTime, endTime)
      : safeStartTime;
    const queryStart: number = Math.max(0, safeStartTime - IDENTIFIER_SEARCH_PADDING_MS);
    const queryEnd: number = safeEndTime + IDENTIFIER_SEARCH_PADDING_MS;

    try {
      const filter: calendarManager.EventFilter = calendarManager.EventFilter.filterByTime(queryStart, queryEnd);
      const events: calendarManager.Event[] = await calendar.getEvents(filter, ['id', 'identifier', 'startTime', 'endTime']);
      for (const event of events) {
        if (event.identifier !== normalizedIdentifier) {
          continue;
        }
        if (typeof event.id === 'number' && event.id > 0) {
          return event.id;
        }
      }
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      this.logSync('identifier_lookup', normalizedIdentifier, 0, 'failed', this.resolveErrorCode(err), true);
    }
    return null;
  }

  private async persistSyncedMapping(recordId: string, calendarId: number, eventId: number): Promise<void> {
    await this.persistMapping({
      timeRecordId: recordId,
      calendarId,
      calendarEventId: eventId,
      syncStatus: TimeRecordCalendarSyncStatus.SYNCED,
      pendingAction: TimeRecordCalendarPendingAction.NONE,
      lastSyncedAt: Date.now()
    });
  }

  private async persistMapping(input: TimeRecordCalendarMapUpsertInput): Promise<void> {
    await RDBStoreUtil.getInstance().upsertTimeRecordCalendarMap(input);
  }

  private toLogEventId(eventId?: number): number {
    return typeof eventId === 'number' ? eventId : 0;
  }

  private resolveErrorCode(error: BusinessError): number {
    if (typeof error.code === 'number') {
      return error.code;
    }
    return -1;
  }

  private logSync(
    action: string,
    recordId: string,
    eventId: number,
    result: string,
    errorCode: number,
    isError: boolean
  ): void {
    const message: string =
      `recordId=${recordId} eventId=${eventId} action=${action} result=${result} errorCode=${errorCode}`;
    if (isError) {
      hilog.error(0x0000, TAG, message);
      return;
    }
    hilog.info(0x0000, TAG, message);
  }
}

export const calendarSyncService: CalendarSyncService = new CalendarSyncService();
