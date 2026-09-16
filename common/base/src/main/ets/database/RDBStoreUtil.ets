/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { TodayActivityItem } from '../common/model/TodayActivityItem';
import { RDBSQL } from '../constants/RDBSQL';
import { TagItem } from '../common/model/TagItem';
import { AppColors } from '../constants/Color';
import { TimeRecord } from '../common/model/TimeRecord';
import { MatterStatus, IdeaType, IdeaLightState } from '../common/model/MatterStatus';
import {
  IdeaActivity,
  SortEntry,
  IdeaSummary,
  IdeaLightSummary,
  IdeaCollectionPatch,
  IdeaCategoryPatch,
  IdeaCollectionSummary,
  IdeaCategorySummary,
  IdeaCollection,
  IdeaCategory
} from '../common/model/IdeaPoolModels';
import { TimeRecordUtil } from '../common/TimeRecordUtil';
import { TimeRecordWithContext, DayAggregation, TagPaletteMap, FocusDateBoundsRow } from './ReviewAggregationTypes';
import fs from '@ohos.file.fs';

const TAG: string = 'RDBStoreUtil';
const DB_VERSION = 1; // 数据库版本号

/**
 * The RDBStoreUtil provides methods to initialize the RDBStore and manage
 * all database operations for the FlowDiary application, using the best practice async/await pattern.
 */
export enum TimeRecordCalendarSyncStatus {
  PENDING = 0,
  SYNCED = 1,
  FAILED = 2
}

export enum TimeRecordCalendarPendingAction {
  NONE = 0,
  UPSERT = 1,
  DELETE = 2
}

export interface TimeRecordCalendarMapItem {
  timeRecordId: string;
  calendarId: number;
  calendarEventId?: number;
  syncStatus: TimeRecordCalendarSyncStatus;
  pendingAction: TimeRecordCalendarPendingAction;
  lastErrorCode?: number;
  lastSyncedAt?: number;
  createdAt: number;
  updatedAt: number;
}

export interface TimeRecordCalendarMapUpsertInput {
  timeRecordId: string;
  calendarId: number;
  calendarEventId?: number;
  syncStatus: TimeRecordCalendarSyncStatus;
  pendingAction: TimeRecordCalendarPendingAction;
  lastErrorCode?: number;
  lastSyncedAt?: number;
}

interface CalendarDaySummaryRow {
  dayStartMs: number;
  totalDurationMs: number;
  recordCount: number;
}

interface AggregateEntry {
  totalDurationMs: number;
  recordCount: number;
}

interface ActiveOpenRecord {
  activityId: string;
  recordId: string;
  startTime: number;
}

interface RdbPredicatesWithInMethod {
  in?: (field: string, values: string[]) => relationalStore.RdbPredicates;
}


interface ReplaceActivityCoverMediaResult {
  ok: boolean;
  oldPaths: string[];
}


export class RDBStoreUtil {
  private static instance: RDBStoreUtil | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;
  private context: Context | null = null;
  private isInitialized: boolean = false;

  private mapRowToTimeRecord(resultSet: relationalStore.ResultSet): TimeRecord {
    const idIndex = resultSet.getColumnIndex('id');
    const activityIdIndex = resultSet.getColumnIndex('activity_id');
    const startTimeIndex = resultSet.getColumnIndex('start_time');
    const endTime = this.readOptionalLong(resultSet, 'end_time');
    const duration = this.readOptionalLong(resultSet, 'duration_milliseconds');

    return new TimeRecord(
      resultSet.getString(idIndex),
      resultSet.getString(activityIdIndex),
      resultSet.getLong(startTimeIndex),
      endTime,
      duration
    );
  }

  private mapRowToTimeRecordCalendarMap(resultSet: relationalStore.ResultSet): TimeRecordCalendarMapItem {
    const calendarEventId: number | undefined = this.readOptionalLong(resultSet, 'calendar_event_id');
    const lastErrorCode: number | undefined = this.readOptionalLong(resultSet, 'last_error_code');
    const lastSyncedAt: number | undefined = this.readOptionalLong(resultSet, 'last_synced_at');

    return {
      timeRecordId: resultSet.getString(resultSet.getColumnIndex('time_record_id')),
      calendarId: resultSet.getLong(resultSet.getColumnIndex('calendar_id')),
      calendarEventId,
      syncStatus: resultSet.getLong(resultSet.getColumnIndex('sync_status')) as TimeRecordCalendarSyncStatus,
      pendingAction: resultSet.getLong(resultSet.getColumnIndex('pending_action')) as TimeRecordCalendarPendingAction,
      lastErrorCode,
      lastSyncedAt,
      createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
      updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
    };
  }

  private readOptionalLong(resultSet: relationalStore.ResultSet, columnName: string): number | undefined {
    const columnIndex = resultSet.getColumnIndex(columnName);
    if (columnIndex < 0 || resultSet.isColumnNull(columnIndex)) {
      return undefined;
    }
    return resultSet.getLong(columnIndex);
  }

  private readOptionalString(resultSet: relationalStore.ResultSet, columnName: string): string | null {
    const columnIndex = resultSet.getColumnIndex(columnName);
    if (columnIndex < 0 || resultSet.isColumnNull(columnIndex)) {
      return null;
    }
    return resultSet.getString(columnIndex);
  }

  private mapRowToIdeaActivity(resultSet: relationalStore.ResultSet): IdeaActivity {
    const id = resultSet.getString(resultSet.getColumnIndex('id'));
    const name = resultSet.getString(resultSet.getColumnIndex('name'));
    const statusValue = resultSet.getLong(resultSet.getColumnIndex('status'));
    const ideaTypeValue = this.readOptionalLong(resultSet, 'idea_type');
    const ideaLightStateValue = this.readOptionalLong(resultSet, 'idea_light_state');
    const ideaLightCountValue = this.readOptionalLong(resultSet, 'idea_light_count');
    const tagId = this.readOptionalString(resultSet, 'tag_id');
    const tagName = this.readOptionalString(resultSet, 'tag_name');
    const tagColorHex = this.readOptionalString(resultSet, 'tag_color_hex');
    const tagLightColorHex = this.readOptionalString(resultSet, 'tag_light_color_hex');
    const createdAt = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    const updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'));

    let displayOrder: number | null = null;
    const displayOrderIndex = resultSet.getColumnIndex('display_order');
    if (displayOrderIndex >= 0 && !resultSet.isColumnNull(displayOrderIndex)) {
      const orderValue = resultSet.getLong(displayOrderIndex);
      displayOrder = orderValue === 999999 ? null : orderValue;
    }

    const resolvedIdeaType: IdeaType =
      ideaTypeValue === undefined ? IdeaType.UNKNOWN : (ideaTypeValue as IdeaType);
    const resolvedLightState: IdeaLightState =
      ideaLightStateValue === undefined ? IdeaLightState.UNLIT : (ideaLightStateValue as IdeaLightState);
    const resolvedLightCount: number = ideaLightCountValue === undefined ? 0 : ideaLightCountValue;

    return new IdeaActivity(
      id,
      name,
      statusValue as MatterStatus,
      tagId,
      tagName,
      tagColorHex,
      tagLightColorHex,
      createdAt,
      updatedAt,
      displayOrder,
      resolvedIdeaType,
      resolvedLightState,
      resolvedLightCount
    );
  }

  private mapRowToIdeaCollection(resultSet: relationalStore.ResultSet): IdeaCollection {
    const id = resultSet.getString(resultSet.getColumnIndex('id'));
    const name = resultSet.getString(resultSet.getColumnIndex('name'));
    const icon = this.readOptionalString(resultSet, 'icon');
    const tagId = this.readOptionalString(resultSet, 'tag_id');
    const tagName = this.readOptionalString(resultSet, 'tag_name');
    const tagColorHex = this.readOptionalString(resultSet, 'tag_color_hex');
    const tagLightColorHex = this.readOptionalString(resultSet, 'tag_light_color_hex');
    const coverStyle = this.readOptionalString(resultSet, 'cover_style');
    const summaryText = this.readOptionalString(resultSet, 'summary_text');
    const displayOrderValue = this.readOptionalLong(resultSet, 'display_order');
    const createdAt = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    const updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
    const displayOrder = displayOrderValue === undefined ? 0 : displayOrderValue;

    return new IdeaCollection(
      id,
      name,
      icon,
      tagId,
      tagName,
      tagColorHex,
      tagLightColorHex,
      coverStyle,
      summaryText,
      displayOrder,
      createdAt,
      updatedAt
    );
  }

  private mapRowToIdeaCategory(resultSet: relationalStore.ResultSet): IdeaCategory {
    const id = resultSet.getString(resultSet.getColumnIndex('id'));
    const name = resultSet.getString(resultSet.getColumnIndex('name'));
    const color = resultSet.getString(resultSet.getColumnIndex('color'));
    const lightColor = resultSet.getString(resultSet.getColumnIndex('light_color'));
    const icon = this.readOptionalString(resultSet, 'icon');
    const createdAt = resultSet.getLong(resultSet.getColumnIndex('created_at'));
    const updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'));

    return new IdeaCategory(id, name, color, lightColor, icon, createdAt, updatedAt);
  }

  private mapRowToSortEntry(resultSet: relationalStore.ResultSet): SortEntry {
    const activityId = resultSet.getString(resultSet.getColumnIndex('activity_id'));
    const displayOrder = resultSet.getLong(resultSet.getColumnIndex('display_order'));
    return new SortEntry(activityId, displayOrder);
  }

  private getSortQueryForTable(tableName: string): string {
    if (tableName === 'idea_pool_sort_config') {
      return RDBSQL.QUERY_IDEA_POOL_SORT_ENTRIES_SQL;
    }
    if (tableName === 'today_list_sort_config') {
      return RDBSQL.QUERY_TODAY_LIST_SORT_ENTRIES_SQL;
    }
    throw new Error(`Unsupported sort config table: ${tableName}`);
  }

  // 私有构造方法
  private constructor(context: Context) {
    this.context = context;
  }

  /**
   * 初始化单例实例，必须在应用启动时调用
   * @param context 应用上下文
   */
  public static init(context: Context): void {
    if (!RDBStoreUtil.instance) {
      RDBStoreUtil.instance = new RDBStoreUtil(context);
      hilog.info(0x0000, TAG, 'RDBStoreUtil initialized with context');
    }
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): RDBStoreUtil {
    if (!RDBStoreUtil.instance) {
      throw new Error('RDBStoreUtil not initialized. Call RDBStoreUtil.init(context) first.');
    }
    return RDBStoreUtil.instance;
  }

  /**
   * Expose the underlying RdbStore for distributed helpers.
   */
  public getRdbStore(): relationalStore.RdbStore | null {
    return this.rdbStore;
  }

  /**
   * 初始化数据库
   */
  async initRDB(): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    if (!this.context) {
      throw new Error('Context is not available');
    }

    try {
      const STORE_CONFIG: relationalStore.StoreConfig = {
        name: 'Objective.db',
        securityLevel: relationalStore.SecurityLevel.S3
      };

      // 获取RdbStore - 使用Promise包装回调方式
      this.rdbStore = await new Promise<relationalStore.RdbStore>((resolve, reject) => {
        relationalStore.getRdbStore(this.context!, STORE_CONFIG, (err: BusinessError, rdbStore: relationalStore.RdbStore) => {
          if (err) {
            hilog.error(0x0000, TAG, `Get RdbStore failed, code is ${err.code}, message is ${err.message}`);
            reject(err);
            return;
          }
          hilog.info(0x0000, TAG, 'Get RdbStore successfully.');
          resolve(rdbStore);
        });
      });

      // Enable foreign keys
      await this.rdbStore.executeSql(RDBSQL.ENABLE_FOREIGN_KEYS_SQL);

      // 创建表
      await this.createTables();


      // Align schema expectations, including status migrations
      await this.alignActivityStatusSchema();
      await this.alignTimeRecordSchema();
      await this.alignTimeRecordCalendarMapSchema();
      await this.alignSortConfigSchema();
      await this.alignActivityMediaSchema();
      await this.alignIdeaPoolSchema();

      // 初始化标签数据
      await this.initTagTable();

      this.isInitialized = true;
      hilog.info(0x0000, TAG, 'Database initialized successfully.');
    } catch (err) {
      const businessError = err as BusinessError;
      hilog.error(0x0000, TAG, `Initialize RDB failed, code is ${businessError.code}, message is ${businessError.message}`);
    }
  }

  /**
   * 创建所有表
   */
  private async createTables(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    try {
      await this.rdbStore.executeSql(RDBSQL.CREATE_TAG_TABLE_SQL);
      hilog.info(0x0000, TAG, 'Create tag table successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_ACTIVITY_TABLE_SQL);
      hilog.info(0x0000, TAG, 'Create activity table successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_ACTIVITY_TAG_ID_SQL);
      hilog.info(0x0000, TAG, 'Create activity table index successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_ACTIVITY_STATUS_SQL);
      hilog.info(0x0000, TAG, 'Create activity table index successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_TIME_RECORD_TABLE_SQL);
      hilog.info(0x0000, TAG, 'Create time record table successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_TIME_RECORD_ACTIVITY_ID_SQL);
      hilog.info(0x0000, TAG, 'Create time record table index successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_TIME_RECORD_START_TIME_SQL);
      hilog.info(0x0000, TAG, 'Create time record table index successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_TIME_RECORD_CALENDAR_MAP_TABLE_SQL);
      hilog.info(0x0000, TAG, 'Create time record calendar map table successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_TIME_RECORD_CALENDAR_MAP_SYNC_STATUS_SQL);
      hilog.info(0x0000, TAG, 'Create time record calendar map sync-status index successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_TIME_RECORD_CALENDAR_MAP_EVENT_ID_SQL);
      hilog.info(0x0000, TAG, 'Create time record calendar map event-id index successfully.');


      await this.rdbStore.executeSql(RDBSQL.CREATE_ACTIVITY_DIARY_TABLE_SQL);
      hilog.info(0x0000, TAG, 'Create activity diary table successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_ACTIVITY_MEDIA_TABLE_SQL);
      hilog.info(0x0000, TAG, 'Create activity media table successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_ACTIVITY_DIARY_ACTIVITY_ID_SQL);
      hilog.info(0x0000, TAG, 'Create activity diary table index successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_ACTIVITY_MEDIA_ACTIVITY_ID_SQL);
      hilog.info(0x0000, TAG, 'Create activity media table index successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_ACTIVITY_MEDIA_CONTENT_HASH_SQL);
      hilog.info(0x0000, TAG, 'Create activity media content hash index successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_IDEA_POOL_SORT_CONFIG_TABLE_SQL);
      hilog.info(0x0000, TAG, 'Create idea pool sort table successfully.');

      await this.rdbStore.executeSql(RDBSQL.CREATE_TODAY_LIST_SORT_CONFIG_TABLE_SQL);
      hilog.info(0x0000, TAG, 'Create time today list sort table successfully.');

      // IdeaPool Light Collections (V1.5)
      await this.rdbStore.executeSql(RDBSQL.CREATE_IDEA_COLLECTION_TABLE_SQL);
      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_IDEA_COLLECTION_TAG_ID_SQL);
      
      await this.rdbStore.executeSql(RDBSQL.CREATE_IDEA_COLLECTION_ITEM_TABLE_SQL);
      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_IDEA_COLLECTION_ITEM_COLLECTION_ID_SQL);
      await this.rdbStore.executeSql(RDBSQL.CREATE_UNIQUE_INDEX_ON_IDEA_COLLECTION_ITEM_ACTIVITY_ID_SQL);
      
      await this.rdbStore.executeSql(RDBSQL.CREATE_IDEA_CATEGORY_TABLE_SQL);
      
      await this.rdbStore.executeSql(RDBSQL.CREATE_IDEA_CATEGORY_ITEM_TABLE_SQL);
      await this.rdbStore.executeSql(RDBSQL.CREATE_INDEX_ON_IDEA_CATEGORY_ITEM_CATEGORY_ID_SQL);
      await this.rdbStore.executeSql(RDBSQL.CREATE_UNIQUE_INDEX_ON_IDEA_CATEGORY_ITEM_ACTIVITY_ID_SQL);
      
      hilog.info(0x0000, TAG, 'Create IdeaPool Light Collections tables successfully.');

    } catch (err) {
      const businessError = err as BusinessError;
      hilog.error(0x0000, TAG, `Create tables failed, code is ${businessError.code}, message is ${businessError.message}`);
    }
  }

  /**
   * Run post-table-creation migrations to ensure schema alignment.
   */
  private async alignActivityStatusSchema(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    try {
      await this.rdbStore.executeSql(RDBSQL.MIGRATE_ARCHIVED_STATUS_SQL);
      hilog.info(0x0000, TAG, 'Activity status alignment migration executed.');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Activity status alignment migration failed, code: ${error.code}, message: ${error.message}`);
    }
  }

  private async alignTimeRecordSchema(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const tryExecute = async (sql: string, name: string): Promise<void> => {
      try {
        await this.rdbStore!.executeSql(sql);
        hilog.info(0x0000, TAG, `Time record schema migration executed: ${name}`);
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(0x0000, TAG,
          `Time record schema migration skipped/failed (${name}), code=${error.code}, message=${error.message}`);
      }
    };

    await tryExecute(RDBSQL.MIGRATE_TIME_RECORD_ADD_CREATED_AT_SQL, 'add_created_at');
    await tryExecute(RDBSQL.MIGRATE_TIME_RECORD_ADD_UPDATED_AT_SQL, 'add_updated_at');
    await tryExecute(RDBSQL.MIGRATE_TIME_RECORD_BACKFILL_CREATED_AT_SQL, 'backfill_created_at');
    await tryExecute(RDBSQL.MIGRATE_TIME_RECORD_BACKFILL_UPDATED_AT_SQL, 'backfill_updated_at');
  }

  private async alignTimeRecordCalendarMapSchema(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const tryExecute = async (sql: string, name: string): Promise<void> => {
      try {
        await this.rdbStore!.executeSql(sql);
        hilog.info(0x0000, TAG, `Time record calendar map schema migration executed: ${name}`);
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(0x0000, TAG,
          `Time record calendar map schema migration skipped/failed (${name}), code=${error.code}, message=${error.message}`);
      }
    };

    await tryExecute(RDBSQL.CREATE_TIME_RECORD_CALENDAR_MAP_TABLE_SQL, 'create_table_if_missing');
    await tryExecute(RDBSQL.MIGRATE_TIME_RECORD_CALENDAR_MAP_ADD_PENDING_ACTION_SQL, 'add_pending_action');
    await tryExecute(RDBSQL.MIGRATE_TIME_RECORD_CALENDAR_MAP_ADD_LAST_ERROR_CODE_SQL, 'add_last_error_code');
    await tryExecute(RDBSQL.MIGRATE_TIME_RECORD_CALENDAR_MAP_ADD_LAST_SYNCED_AT_SQL, 'add_last_synced_at');
    await tryExecute(RDBSQL.CREATE_INDEX_ON_TIME_RECORD_CALENDAR_MAP_SYNC_STATUS_SQL, 'idx_sync_status');
    await tryExecute(RDBSQL.CREATE_INDEX_ON_TIME_RECORD_CALENDAR_MAP_EVENT_ID_SQL, 'idx_event_id');
  }

  private async alignActivityMediaSchema(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const tryExecute = async (sql: string, name: string): Promise<void> => {
      try {
        await this.rdbStore!.executeSql(sql);
        hilog.info(0x0000, TAG, `Activity media schema migration executed: ${name}`);
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(0x0000, TAG,
          `Activity media schema migration skipped/failed (${name}), code=${error.code}, message=${error.message}`);
      }
    };

    await tryExecute(RDBSQL.MIGRATE_ACTIVITY_MEDIA_ADD_CONTENT_HASH_SQL, 'activity_media_add_content_hash');
    await tryExecute(RDBSQL.CREATE_INDEX_ON_ACTIVITY_MEDIA_CONTENT_HASH_SQL, 'activity_media_content_hash_index');
  }

  private async alignSortConfigSchema(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const tryExecute = async (sql: string, name: string): Promise<void> => {
      try {
        await this.rdbStore!.executeSql(sql);
        hilog.info(0x0000, TAG, `Sort config schema migration executed: ${name}`);
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(0x0000, TAG,
          `Sort config schema migration skipped/failed (${name}), code=${error.code}, message=${error.message}`);
      }
    };

    await tryExecute(RDBSQL.MIGRATE_IDEA_POOL_SORT_CONFIG_ADD_CREATED_AT_SQL, 'idea_pool_add_created_at');
    await tryExecute(RDBSQL.MIGRATE_IDEA_POOL_SORT_CONFIG_ADD_UPDATED_AT_SQL, 'idea_pool_add_updated_at');
    await tryExecute(RDBSQL.MIGRATE_IDEA_POOL_SORT_CONFIG_BACKFILL_CREATED_AT_SQL, 'idea_pool_backfill_created_at');
    await tryExecute(RDBSQL.MIGRATE_IDEA_POOL_SORT_CONFIG_BACKFILL_UPDATED_AT_SQL, 'idea_pool_backfill_updated_at');

    await tryExecute(RDBSQL.MIGRATE_TODAY_LIST_SORT_CONFIG_ADD_CREATED_AT_SQL, 'today_list_add_created_at');
    await tryExecute(RDBSQL.MIGRATE_TODAY_LIST_SORT_CONFIG_ADD_UPDATED_AT_SQL, 'today_list_add_updated_at');
    await tryExecute(RDBSQL.MIGRATE_TODAY_LIST_SORT_CONFIG_BACKFILL_CREATED_AT_SQL, 'today_list_backfill_created_at');
    await tryExecute(RDBSQL.MIGRATE_TODAY_LIST_SORT_CONFIG_BACKFILL_UPDATED_AT_SQL, 'today_list_backfill_updated_at');
  }

  private async alignIdeaPoolSchema(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const tryExecute = async (sql: string, name: string): Promise<void> => {
      try {
        await this.rdbStore!.executeSql(sql);
        hilog.info(0x0000, TAG, `Idea pool schema migration executed: ${name}`);
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(0x0000, TAG,
          `Idea pool schema migration skipped/failed (${name}), code=${error.code}, message=${error.message}`);
      }
    };

    // 1. Add new columns to activity table
    await tryExecute(RDBSQL.MIGRATE_ACTIVITY_ADD_IDEA_TYPE_SQL, 'add_idea_type');
    await tryExecute(RDBSQL.MIGRATE_ACTIVITY_ADD_IDEA_LIGHT_STATE_SQL, 'add_idea_light_state');
    await tryExecute(RDBSQL.MIGRATE_ACTIVITY_ADD_IDEA_LIGHT_COUNT_SQL, 'add_idea_light_count');

    // 2. Add indexes
    await tryExecute(RDBSQL.CREATE_INDEX_ON_ACTIVITY_IDEA_TYPE_SQL, 'idx_activity_idea_type');
    await tryExecute(RDBSQL.CREATE_INDEX_ON_ACTIVITY_IDEA_LIGHT_STATE_SQL, 'idx_activity_idea_light_state');

    // 3. Backfill data (idempotent updates)
    // Status=3 (IDEA_POOL) -> IdeaType=1 (IDEA_POOL)
    await tryExecute(RDBSQL.MIGRATE_ACTIVITY_BACKFILL_IDEA_TYPE_IDEA_POOL_SQL, 'backfill_idea_pool');

    // Everything else (idea_type=0) -> IdeaType=2 (TODAY_ONLY)
    await tryExecute(RDBSQL.MIGRATE_ACTIVITY_BACKFILL_IDEA_TYPE_TODAY_ONLY_SQL, 'backfill_today_only');
  }

  /**
   * 初始化标签表数据
   */
  private async initTagTable(): Promise<void> {
    if (!this.rdbStore) {
      console.error('RDB store is not initialized');
      return;
    }

    try {
      // 检查是否已有数据
      const resultSet = await this.rdbStore.querySql(RDBSQL.COUNT_TAGS_SQL);
      let count = 0;

      if (resultSet.goToFirstRow()) {
        count = resultSet.getValue(resultSet.getColumnIndex('count')) as number;
      }
      resultSet.close();

      // 如果没有数据，则初始化
      if (count === 0) {
        hilog.info(0x0000, TAG, 'Initializing default data for tag table...');
        const now = Date.now();
        const valueBuckets: relationalStore.ValuesBucket[] = [
          {
            'id': 'tag-001',
            'name': '工作',
            'color': AppColors.DATA_VIZ_1,          // 主色 (用于文字)
            'light_color': AppColors.DATA_VIZ_1_LIGHT,  // 背景色
            'created_at': now,
            'updated_at': now
          },
          {
            'id': 'tag-002',
            'name': '学习',
            'color': AppColors.DATA_VIZ_3,          // 主色 (用于文字)
            'light_color': AppColors.DATA_VIZ_3_LIGHT,  // 背景色
            'created_at': now,
            'updated_at': now
          },
          {
            'id': 'tag-003',
            'name': '休闲',
            'color': AppColors.DATA_VIZ_2,          // 主色 (用于文字)
            'light_color': AppColors.DATA_VIZ_2_LIGHT,  // 背景色
            'created_at': now,
            'updated_at': now
          },
          {
            'id': 'tag-004',
            'name': '运动',
            'color': AppColors.DATA_VIZ_5,          // 主色 (用于文字)
            'light_color': AppColors.DATA_VIZ_5_LIGHT,  // 背景色
            'created_at': now,
            'updated_at': now
          },
          {
            'id': 'tag-006',
            'name': '生活',
            'color': AppColors.DATA_VIZ_4,
            'light_color': AppColors.DATA_VIZ_4_LIGHT,
            'created_at': now,
            'updated_at': now
          },
          {
            'id': 'tag-007',
            'name': '副业',
            'color': AppColors.DATA_VIZ_6,
            'light_color': AppColors.DATA_VIZ_6_LIGHT,
            'created_at': now,
            'updated_at': now
          },
        ];

        // 使用事务批量插入
        await this.rdbStore.beginTransaction();
        try {
          const insertNum = await this.rdbStore.batchInsert('tag', valueBuckets);
          hilog.info(0x0000, TAG, `Batch insert tags successful, inserted ${insertNum} records.`);
          await this.rdbStore.commit();
        } catch (err) {
          await this.rdbStore.rollBack();
        }
      }
    } catch (err) {
      const businessError = err as BusinessError;
      hilog.error(0x0000, TAG, `Init tag table failed, code is ${businessError.code}, message is ${businessError.message}`);
    }
  }

  /**
   * 查询今日活动
   */
  async queryAllTodayActivities(): Promise<TodayActivityItem[]> {
    await this.ensureInitialized();

    try {
      // 获取今日的开始时间（0点）
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const todayStart = today.getTime();

      const params = [todayStart, todayStart, todayStart, todayStart];
      const resultSet = await this.rdbStore!.querySql(RDBSQL.QUERY_TODAY_ACTIVITIES_SQL, params);
      const activitySet: TodayActivityItem[] = [];

      try {
        while (resultSet.goToNextRow()) {
          const id = resultSet.getValue(resultSet.getColumnIndex('id')) as string;
          const name = resultSet.getValue(resultSet.getColumnIndex('name')) as string;
          const status = resultSet.getValue(resultSet.getColumnIndex('status')) as number;
          const tagName = resultSet.getValue(resultSet.getColumnIndex('tag_name')) as string | null;
          const tagColorHex = resultSet.getValue(resultSet.getColumnIndex('tag_color_hex')) as string | null;
          const displayOrder = resultSet.getValue(resultSet.getColumnIndex('display_order')) as number | null;

          activitySet.push(new TodayActivityItem(id, name, status, tagName, tagColorHex, displayOrder));
        }

        return activitySet;
      } finally {
        resultSet.close();
      }
    } catch (err) {
      const businessError = err as BusinessError;
      hilog.error(0x0000, TAG, `Query today activities failed, code is ${businessError.code}, message is ${businessError.message}`);
    }
    return []
  }

  /**
   * 根据ID查询单个活动
   * @param activityId 活动ID
   * @returns 活动对象或null
   */
  async queryActivityById(activityId: string): Promise<TodayActivityItem | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const sql = RDBSQL.QUERY_ACTIVITY_BY_ID_SQL;

    try {
      const resultSet = await this.rdbStore.querySql(sql, [activityId]);

      if (resultSet.goToFirstRow()) {
        const activity: TodayActivityItem = new TodayActivityItem(
          resultSet.getString(resultSet.getColumnIndex('id')),
          resultSet.getString(resultSet.getColumnIndex('name')),
          resultSet.getLong(resultSet.getColumnIndex('status')),
          resultSet.getString(resultSet.getColumnIndex('tag_name')),
          resultSet.getString(resultSet.getColumnIndex('tag_color_hex')),
          resultSet.getLong(resultSet.getColumnIndex('display_order'))
        );
        resultSet.close();
        return activity;
      } else {
        resultSet.close();
        hilog.warn(0x0000, 'RDBStoreUtil', `未找到ID为 ${activityId} 的活动`);
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, 'RDBStoreUtil', `根据ID查询活动失败: ${err.message}`);
    }
    return null;
  }

  /**
   * 查询所有标签
   */
  async queryAllTags(): Promise<TagItem[]> {
    await this.ensureInitialized();

    try {
      const resultSet = await this.rdbStore!.querySql(RDBSQL.QUERY_ALL_TAGS_SQL);
      const tagSet: TagItem[] = [];

      try {
        while (resultSet.goToNextRow()) {
          const id = resultSet.getValue(resultSet.getColumnIndex('id')) as string;
          const name = resultSet.getValue(resultSet.getColumnIndex('name')) as string;
          const color = resultSet.getValue(resultSet.getColumnIndex('color')) as string;
          const lightColor = resultSet.getValue(resultSet.getColumnIndex('light_color')) as string;
          const createdAt = resultSet.getValue(resultSet.getColumnIndex('created_at')) as number;
          const updatedAt = resultSet.getValue(resultSet.getColumnIndex('updated_at')) as number;
          tagSet.push(new TagItem(id, name, color, lightColor, createdAt, updatedAt));
        }
        return tagSet;
      } finally {
        resultSet.close();
      }
    } catch (err) {
      const businessError = err as BusinessError;
      hilog.error(0x0000, TAG, `Query all tags failed, code is ${businessError.code}, message is ${businessError.message}`);
    }
    return []
  }

  /**
   * Insert a new tag into the database.
   * @param tagItem The tag item to insert
   * @returns Promise with the inserted row ID
   */
  async insertTag(tagItem: TagItem): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const existingTags: TagItem[] = await this.queryAllTags();
    const duplicatedName: boolean = existingTags.some((item: TagItem) => item.name === tagItem.name);
    if (duplicatedName) {
      hilog.warn(0x0000, TAG, `Tag insert blocked due to duplicate name: ${tagItem.name}`);
      return -1;
    }

    const tagData: relationalStore.ValuesBucket = {
      'id': tagItem.id,
      'name': tagItem.name,
      'color': tagItem.color,
      'light_color': tagItem.lightColor,
      'created_at': tagItem.createdAt,
      'updated_at': tagItem.updatedAt
    };

    try {
      const rowId = await this.rdbStore.insert('tag', tagData,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      hilog.info(0x0000, TAG, `Tag insert successful, rowId = ${rowId}`);
      return rowId;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Tag insert failed, code: ${error.code}, message: ${error.message}`);
    }
    return -1;
  }

  /**
   * Delete a tag record and detach it from related activities.
   * @param tagId The tag ID to delete
   * @returns Whether the tag was deleted successfully
   */
  async deleteTag(tagId: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!tagId || tagId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid tag ID provided for deletion: empty or null');
      return false;
    }

    const normalizedTagId: string = tagId.trim();
    try {
      hilog.info(0x0000, TAG, `Deleting tag with ID: ${normalizedTagId}`);

      await this.rdbStore.beginTransaction();

      const activityValues: relationalStore.ValuesBucket = {
        'tag_id': null,
        'updated_at': Date.now()
      };
      const activityPredicates = new relationalStore.RdbPredicates('activity');
      activityPredicates.equalTo('tag_id', normalizedTagId);
      const detachedActivityRows = await this.rdbStore.update(
        activityValues,
        activityPredicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );

      const collectionValues: relationalStore.ValuesBucket = {
        'tag_id': null,
        'updated_at': Date.now()
      };
      const collectionPredicates = new relationalStore.RdbPredicates('idea_collection');
      collectionPredicates.equalTo('tag_id', normalizedTagId);
      const detachedCollectionRows = await this.rdbStore.update(
        collectionValues,
        collectionPredicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );

      const tagPredicates = new relationalStore.RdbPredicates('tag');
      tagPredicates.equalTo('id', normalizedTagId);
      const deleteResult = await this.rdbStore.delete(tagPredicates);

      if (deleteResult > 0) {
        await this.rdbStore.commit();
        hilog.info(0x0000, TAG,
          `Tag deleted successfully, ID: ${normalizedTagId}, detachedActivityRows=${detachedActivityRows}, detachedCollectionRows=${detachedCollectionRows}`);
        return true;
      } else {
        await this.rdbStore.rollBack();
        hilog.warn(0x0000, TAG, `No tag found with ID: ${normalizedTagId} for deletion`);
        return false;
      }
    } catch (err) {
      try {
        await this.rdbStore.rollBack();
      } catch (rollbackError) {
        const rollbackBusinessError = rollbackError as BusinessError;
        hilog.warn(0x0000, TAG,
          `Tag deletion rollback failed, code: ${rollbackBusinessError.code}, message: ${rollbackBusinessError.message}`);
      }
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Tag deletion failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  /**
   * Update an existing tag.
   * @param tagId Tag ID
   * @param name Tag name
   * @param color Tag color
   * @param lightColor Tag light color
   * @param updatedAt Updated timestamp
   * @returns Whether the tag was updated successfully
   */
  async updateTag(
    tagId: string,
    name: string,
    color: string,
    lightColor: string,
    updatedAt: number = Date.now()
  ): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!tagId || tagId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid tag ID provided for update: empty or null');
      return false;
    }

    const values: relationalStore.ValuesBucket = {
      'name': name,
      'color': color,
      'light_color': lightColor,
      'updated_at': updatedAt
    };
    const predicates = new relationalStore.RdbPredicates('tag');
    predicates.equalTo('id', tagId);

    try {
      const updatedRows = await this.rdbStore.update(values, predicates);
      if (updatedRows > 0) {
        hilog.info(0x0000, TAG, `Tag update successful, id=${tagId}, rows=${updatedRows}`);
        return true;
      }
      hilog.warn(0x0000, TAG, `Tag update skipped, no matched row for id=${tagId}`);
      return false;
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.error(0x0000, TAG, `Tag update failed, code: ${businessError.code}, message: ${businessError.message}`);
      return false;
    }
  }

  /**
   * Insert a new activity into the database.
   * @param id Activity ID
   * @param name Activity name
   * @param tagId Associated tag ID (optional)
   * @param status Activity status (see MatterStatus enum values)
   * @returns Promise with the inserted row ID
   */
  async insertActivity(
    id: string,
    name: string,
    tagId: string | null,
    status: number,
    suppressSyncPush: boolean = false,
    ideaType?: IdeaType
  ): Promise<number> {

    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const currentTime = Date.now();
    const resolvedIdeaType: IdeaType =
      ideaType !== undefined
        ? ideaType
        : (status === MatterStatus.IDEA_POOL ? IdeaType.IDEA_POOL : IdeaType.TODAY_ONLY);
    const activityData: relationalStore.ValuesBucket = {
      'id': id,
      'name': name,
      'tag_id': tagId,
      'status': status,
      'idea_type': resolvedIdeaType,
      'idea_light_state': IdeaLightState.UNLIT,
      'idea_light_count': 0,
      'created_at': currentTime,
      'updated_at': currentTime
    };

    try {
      const rowId = await this.rdbStore.insert('activity', activityData,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      hilog.info(0x0000, TAG, `Activity insert successful, rowId = ${rowId}`);

      // 根据状态插入排序配置
      await this.insertSortConfig(id, status);
      if (!suppressSyncPush) {
        const tablesToSync: string[] = ['activity'];
        if (status >= MatterStatus.TODO && status <= MatterStatus.PAUSED) {
          tablesToSync.push('today_list_sort_config');
        } else if (status === MatterStatus.IDEA_POOL) {
          tablesToSync.push('idea_pool_sort_config');
        }
      }

      return rowId;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Activity insert failed, code: ${error.code}, message: ${error.message}`);
    }
    return -1;
  }

  /**
   * Insert sort configuration for the activity based on its status.
   * @param activityId Activity ID
   * @param status Activity status
   */
  private async insertSortConfig(activityId: string, status: number): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    try {
      const now: number = Date.now();
      // 获取当前最大的display_order
      let maxOrderQuery: string;
      let tableName: string;

      // All today activities (status TODO, RECORDING, PAUSED) go into today_list_sort_config
      if (status >= MatterStatus.TODO && status <= MatterStatus.PAUSED) {
        tableName = 'today_list_sort_config';
        maxOrderQuery = RDBSQL.QUERY_MAX_TODAY_LIST_ORDER_SQL;
      } else if (status === MatterStatus.IDEA_POOL) {
        tableName = 'idea_pool_sort_config';
        maxOrderQuery = RDBSQL.QUERY_MAX_IDEA_POOL_ORDER_SQL;
      } else {
        return; // 其他状态不需要排序配置
      }

      const resultSet = await this.rdbStore.querySql(maxOrderQuery);
      let nextOrder = 1;

      if (resultSet.goToFirstRow()) {
        const maxOrder = resultSet.getLong(resultSet.getColumnIndex('max_order'));
        nextOrder = maxOrder + 1;
      }
      resultSet.close();

      // 插入排序配置
      const sortData: relationalStore.ValuesBucket = {
        'activity_id': activityId,
        'display_order': nextOrder,
        'created_at': now,
        'updated_at': now
      };

      await this.rdbStore.insert(tableName, sortData,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

      hilog.info(0x0000, TAG, `Sort config insert successful for activity ${activityId}`);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Sort config insert failed, code: ${error.code}, message: ${error.message}`);
    }
  }

  private async deleteSortEntriesInternal(tableName: string, activityIds: string[]): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (activityIds.length === 0) {
      return 0;
    }

    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(tableName);
      const predicateWithIn: RdbPredicatesWithInMethod = predicates as RdbPredicatesWithInMethod;
      const hasInMethod: boolean = typeof predicateWithIn.in === 'function';
      if (hasInMethod && predicateWithIn.in) {
        predicateWithIn.in('activity_id', activityIds);
        return await this.rdbStore.delete(predicates);
      }

      const placeholders: string = activityIds.map(() => '?').join(', ');
      const sql: string = `DELETE FROM ${tableName} WHERE activity_id IN (${placeholders})`;
      await this.rdbStore.executeSql(sql, activityIds);
      return activityIds.length;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed to delete sort entries from ${tableName}, code: ${error.code}, message: ${error.message}`);
    }
    return -1;
  }

  private async querySortEntries(tableName: string): Promise<SortEntry[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const sql = this.getSortQueryForTable(tableName);
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(sql);
      const entries: SortEntry[] = [];
      while (resultSet.goToNextRow()) {
        entries.push(this.mapRowToSortEntry(resultSet));
      }
      return entries;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed to query sort entries from ${tableName}, code: ${error.code}, message: ${error.message}`);
      return [];
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  private async updateSortOrderInternal(tableName: string, orderedIds: string[]): Promise<SortEntry[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const existingEntries = await this.querySortEntries(tableName);
    const orderedSet = new Set(orderedIds);
    const idsToDelete = existingEntries
      .map(entry => entry.activityId)
      .filter(activityId => !orderedSet.has(activityId));

    await this.rdbStore.beginTransaction();
    try {
      const now: number = Date.now();
      if (idsToDelete.length > 0) {
        await this.deleteSortEntriesInternal(tableName, idsToDelete);
      }

      const updatedEntries: SortEntry[] = [];

      if (orderedIds.length > 0) {
        let displayOrder = 1;
        for (const activityId of orderedIds) {
          const values: relationalStore.ValuesBucket = {
            'display_order': displayOrder,
            'updated_at': now
          };
          const predicates = new relationalStore.RdbPredicates(tableName);
          predicates.equalTo('activity_id', activityId);

          const affectedRows = await this.rdbStore.update(
            values,
            predicates,
            relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
          );

          if (affectedRows === 0) {
            values['activity_id'] = activityId;
            values['created_at'] = now;
            await this.rdbStore.insert(
              tableName,
              values,
              relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
            );
          }

          updatedEntries.push(new SortEntry(activityId, displayOrder));
          displayOrder++;
        }

      }

      await this.rdbStore.commit();
      return updatedEntries;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed to update sort order for ${tableName}, code: ${error.code}, message: ${error.message}`);
      try {
        await this.rdbStore.rollBack();
      } catch (rollbackError) {
        const rollbackBusinessError = rollbackError as BusinessError;
        hilog.error(0x0000, TAG,
          `Rollback failed during sort order update for ${tableName}, code: ${rollbackBusinessError.code}, message: ${rollbackBusinessError.message}`);
      }
    }
    return [];
  }

  /**
   * Generate a unique ID for new records.
   * @returns A unique string ID
   */
  static generateUniqueId(): string {
    return `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Create a new TagItem with generated ID and timestamps.
   * @param name Tag name
   * @param color Tag color
   * @param lightColor Tag light color
   * @returns New TagItem instance
   */
  static createNewTag(name: string, color: string, lightColor: string): TagItem {
    const currentTime = Date.now();
    return new TagItem(
      RDBStoreUtil.generateUniqueId(),
      name,
      color,
      lightColor,
      currentTime,
      currentTime
    );
  }

  // 在现有的 RDBStoreUtil 类中添加以下方法

  /**
   * 查询所有活动（不限状态）
   * @returns 所有活动的列表
   */
  async queryAllActivities(): Promise<TodayActivityItem[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const sql = RDBSQL.QUERY_ALL_ACTIVITIES_SQL;

    try {
      const resultSet = await this.rdbStore.querySql(sql);
      const activities: TodayActivityItem[] = [];

      while (resultSet.goToNextRow()) {
        const activity: TodayActivityItem = new TodayActivityItem(
          resultSet.getString(resultSet.getColumnIndex('id')),
          resultSet.getString(resultSet.getColumnIndex('name')),
          resultSet.getLong(resultSet.getColumnIndex('status')),
          resultSet.getString(resultSet.getColumnIndex('tag_name')),
          resultSet.getString(resultSet.getColumnIndex('tag_color_hex')),
          resultSet.getLong(resultSet.getColumnIndex('display_order'))
        );
        activities.push(activity);
      }

      resultSet.close();
      hilog.info(0x0000, 'RDBStoreUtil', `查询到 ${activities.length} 个活动`);
      return activities;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, 'RDBStoreUtil', `查询所有活动失败: ${err.message}`);
    }
    return []
  }

  /**
   * 根据状态查询活动
   * @param status 活动状态
   * @returns 符合指定状态的活动列表
   */
  async queryActivitiesByStatus(status: number): Promise<TodayActivityItem[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const sql = RDBSQL.QUERY_ACTIVITIES_BY_STATUS_SQL;

    try {
      const resultSet = await this.rdbStore.querySql(sql, [status]);
      const activities: TodayActivityItem[] = [];

      while (resultSet.goToNextRow()) {
        const activity: TodayActivityItem = new TodayActivityItem(
          resultSet.getString(resultSet.getColumnIndex('id')),
          resultSet.getString(resultSet.getColumnIndex('name')),
          resultSet.getLong(resultSet.getColumnIndex('status')),
          resultSet.getString(resultSet.getColumnIndex('tag_name')),
          resultSet.getString(resultSet.getColumnIndex('tag_color_hex')),
          resultSet.getLong(resultSet.getColumnIndex('display_order'))
        );
        activities.push(activity);
      }

      resultSet.close();
      hilog.info(0x0000, TAG, `查询到 ${activities.length} 个状态为 ${status} 的活动`);
      return activities;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `根据状态查询活动失败, code: ${err.code}, message: ${err.message}`);
    }
    return [];
  }

  async queryIdeaPoolActivities(): Promise<IdeaActivity[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_IDEA_POOL_ACTIVITIES_SQL);
      const activities: IdeaActivity[] = [];
      while (resultSet.goToNextRow()) {
        activities.push(this.mapRowToIdeaActivity(resultSet));
      }
      return activities;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询Idea Pool活动失败, code: ${err.code}, message: ${err.message}`);
      return [];
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  async queryIdeaCollectionActivities(collectionId: string): Promise<IdeaActivity[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const trimmedId: string = collectionId !== undefined && collectionId !== null ? collectionId.trim() : '';
    if (trimmedId.length === 0) {
      return [];
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_IDEA_COLLECTION_ACTIVITIES_SQL, [trimmedId]);
      const activities: IdeaActivity[] = [];
      while (resultSet.goToNextRow()) {
        activities.push(this.mapRowToIdeaActivity(resultSet));
      }
      return activities;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询Idea Collection活动失败, code: ${err.code}, message: ${err.message}`);
      return [];
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  async queryIdeaCollectionIdByActivityId(activityId: string): Promise<string | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const trimmedId: string = activityId !== undefined && activityId !== null ? activityId.trim() : '';
    if (trimmedId.length === 0) {
      return null;
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_IDEA_COLLECTION_ID_BY_ACTIVITY_SQL, [trimmedId]);
      if (resultSet.goToNextRow()) {
        return resultSet.getString(resultSet.getColumnIndex('collection_id'));
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG,
        `Query collection id by activity failed: code=${err.code}, message=${err.message}`);
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
    return null;
  }

  async queryIdeaCollections(): Promise<IdeaCollection[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_IDEA_COLLECTIONS_SQL);
      const collections: IdeaCollection[] = [];
      while (resultSet.goToNextRow()) {
        collections.push(this.mapRowToIdeaCollection(resultSet));
      }
      return collections;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询Idea Collection失败, code: ${err.code}, message: ${err.message}`);
      return [];
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  async queryIdeaCategories(): Promise<IdeaCategory[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_IDEA_CATEGORIES_SQL);
      const categories: IdeaCategory[] = [];
      while (resultSet.goToNextRow()) {
        categories.push(this.mapRowToIdeaCategory(resultSet));
      }
      return categories;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询Idea Category失败, code: ${err.code}, message: ${err.message}`);
      return [];
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  async queryIdeaCollectionSummaries(): Promise<IdeaCollectionSummary[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_IDEA_COLLECTION_LIGHT_COUNTS_SQL);
      const summaries: IdeaCollectionSummary[] = [];
      while (resultSet.goToNextRow()) {
        const collectionId = resultSet.getString(resultSet.getColumnIndex('collection_id'));
        const totalCount = this.readOptionalLong(resultSet, 'total_count') ?? 0;
        const litCount = this.readOptionalLong(resultSet, 'lit_count') ?? 0;
        const unlitCount = this.readOptionalLong(resultSet, 'unlit_count') ?? 0;
        summaries.push({ collectionId, totalCount, litCount, unlitCount });
      }
      return summaries;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询Idea Collection统计失败, code: ${err.code}, message: ${err.message}`);
      return [];
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  async queryIdeaCategorySummaries(): Promise<IdeaCategorySummary[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_IDEA_CATEGORY_LIGHT_COUNTS_SQL);
      const summaries: IdeaCategorySummary[] = [];
      while (resultSet.goToNextRow()) {
        const categoryId = resultSet.getString(resultSet.getColumnIndex('category_id'));
        const totalCount = this.readOptionalLong(resultSet, 'total_count') ?? 0;
        const litCount = this.readOptionalLong(resultSet, 'lit_count') ?? 0;
        const unlitCount = this.readOptionalLong(resultSet, 'unlit_count') ?? 0;
        summaries.push({ categoryId, totalCount, litCount, unlitCount });
      }
      return summaries;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询Idea Category统计失败, code: ${err.code}, message: ${err.message}`);
      return [];
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  async queryIdeaPoolGlobalSummary(): Promise<IdeaLightSummary> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    let resultSet: relationalStore.ResultSet | null = null;
    const emptySummary: IdeaLightSummary = { totalCount: 0, litCount: 0, unlitCount: 0 };
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_IDEA_POOL_LIGHT_COUNTS_SQL);
      if (!resultSet.goToFirstRow()) {
        return emptySummary;
      }
      const totalCount = this.readOptionalLong(resultSet, 'total_count') ?? 0;
      const litCount = this.readOptionalLong(resultSet, 'lit_count') ?? 0;
      const unlitCount = this.readOptionalLong(resultSet, 'unlit_count') ?? 0;
      return { totalCount, litCount, unlitCount };
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询IdeaPool统计失败, code: ${err.code}, message: ${err.message}`);
      return emptySummary;
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  async insertIdeaCollection(
    id: string,
    name: string,
    icon: string | null,
    tagId: string | null,
    coverStyle: string | null,
    summaryText: string | null,
    displayOrder: number
  ): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!id || id.trim().length === 0 || !name || name.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid IdeaCollection payload: id/name missing');
      return -1;
    }

    const now = Date.now();
    const collectionData: relationalStore.ValuesBucket = {
      'id': id,
      'name': name.trim(),
      'icon': icon,
      'tag_id': tagId,
      'cover_style': coverStyle,
      'summary_text': summaryText,
      'display_order': displayOrder,
      'created_at': now,
      'updated_at': now
    };

    try {
      const rowId = await this.rdbStore.insert('idea_collection', collectionData,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (rowId > 0) {
      }
      return rowId;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaCollection insert failed, code: ${error.code}, message: ${error.message}`);
      return -1;
    }
  }

  async updateIdeaCollection(id: string, patch: IdeaCollectionPatch): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!id || id.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid IdeaCollection id for update');
      return false;
    }

    const valueBucket: relationalStore.ValuesBucket = {
      'updated_at': Date.now()
    };
    let hasUpdate = false;

    if (patch.name !== undefined) {
      const trimmedName = patch.name.trim();
      if (trimmedName.length > 0) {
        valueBucket['name'] = trimmedName;
        hasUpdate = true;
      }
    }
    if (patch.icon !== undefined) {
      valueBucket['icon'] = patch.icon;
      hasUpdate = true;
    }
    if (patch.tagId !== undefined) {
      valueBucket['tag_id'] = patch.tagId;
      hasUpdate = true;
    }
    if (patch.coverStyle !== undefined) {
      valueBucket['cover_style'] = patch.coverStyle;
      hasUpdate = true;
    }
    if (patch.summaryText !== undefined) {
      valueBucket['summary_text'] = patch.summaryText;
      hasUpdate = true;
    }
    if (patch.displayOrder !== undefined) {
      valueBucket['display_order'] = patch.displayOrder;
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return false;
    }

    try {
      const predicates = new relationalStore.RdbPredicates('idea_collection');
      predicates.equalTo('id', id);
      const updateResult = await this.rdbStore.update(valueBucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (updateResult > 0) {
        return true;
      }
      return false;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaCollection update failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async updateIdeaCollectionSortOrder(orderedIds: string[]): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    await this.rdbStore.beginTransaction();
    try {
      const now: number = Date.now();
      for (let index: number = 0; index < orderedIds.length; index += 1) {
        const collectionId: string = orderedIds[index];
        const values: relationalStore.ValuesBucket = {
          'display_order': index + 1,
          'updated_at': now
        };
        const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('idea_collection');
        predicates.equalTo('id', collectionId);
        const affectedRows: number = await this.rdbStore.update(values, predicates);
        if (affectedRows !== 1) {
          throw new Error(`Failed to update IdeaCollection order: id=${collectionId}`);
        }
      }
      await this.rdbStore.commit();
      return true;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(0x0000, TAG,
        `IdeaCollection reorder failed, code: ${error.code}, message: ${error.message}`);
      try {
        await this.rdbStore.rollBack();
      } catch (rollbackErr) {
        const rollbackError: BusinessError = rollbackErr as BusinessError;
        hilog.error(0x0000, TAG,
          `IdeaCollection reorder rollback failed, code: ${rollbackError.code}, message: ${rollbackError.message}`);
      }
      return false;
    }
  }

  async deleteIdeaCollection(id: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!id || id.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid IdeaCollection id for delete');
      return false;
    }

    try {
      const predicates = new relationalStore.RdbPredicates('idea_collection');
      predicates.equalTo('id', id);
      const deleteResult = await this.rdbStore.delete(predicates);
      if (deleteResult > 0) {
        return true;
      }
      return false;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaCollection delete failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async insertIdeaCategory(
    id: string,
    name: string,
    color: string,
    lightColor: string,
    icon: string | null
  ): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!id || id.trim().length === 0 || !name || name.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid IdeaCategory payload: id/name missing');
      return -1;
    }

    const now = Date.now();
    const categoryData: relationalStore.ValuesBucket = {
      'id': id,
      'name': name.trim(),
      'color': color,
      'light_color': lightColor,
      'icon': icon,
      'created_at': now,
      'updated_at': now
    };

    try {
      const rowId = await this.rdbStore.insert('idea_category', categoryData,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (rowId > 0) {
      }
      return rowId;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaCategory insert failed, code: ${error.code}, message: ${error.message}`);
      return -1;
    }
  }

  async updateIdeaCategory(id: string, patch: IdeaCategoryPatch): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!id || id.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid IdeaCategory id for update');
      return false;
    }

    const valueBucket: relationalStore.ValuesBucket = {
      'updated_at': Date.now()
    };
    let hasUpdate = false;

    if (patch.name !== undefined) {
      const trimmedName = patch.name.trim();
      if (trimmedName.length > 0) {
        valueBucket['name'] = trimmedName;
        hasUpdate = true;
      }
    }
    if (patch.color !== undefined) {
      valueBucket['color'] = patch.color;
      hasUpdate = true;
    }
    if (patch.lightColor !== undefined) {
      valueBucket['light_color'] = patch.lightColor;
      hasUpdate = true;
    }
    if (patch.icon !== undefined) {
      valueBucket['icon'] = patch.icon;
      hasUpdate = true;
    }

    if (!hasUpdate) {
      return false;
    }

    try {
      const predicates = new relationalStore.RdbPredicates('idea_category');
      predicates.equalTo('id', id);
      const updateResult = await this.rdbStore.update(valueBucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (updateResult > 0) {
        return true;
      }
      return false;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaCategory update failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async deleteIdeaCategory(id: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!id || id.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid IdeaCategory id for delete');
      return false;
    }

    try {
      const predicates = new relationalStore.RdbPredicates('idea_category');
      predicates.equalTo('id', id);
      const deleteResult = await this.rdbStore.delete(predicates);
      if (deleteResult > 0) {
        return true;
      }
      return false;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaCategory delete failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async upsertIdeaCollectionItem(
    activityId: string,
    collectionId: string,
    displayOrder: number = 0
  ): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const trimmedActivityId: string = activityId !== undefined && activityId !== null ? activityId.trim() : '';
    const trimmedCollectionId: string = collectionId !== undefined && collectionId !== null ? collectionId.trim() : '';
    if (trimmedActivityId.length === 0 || trimmedCollectionId.length === 0) {
      hilog.error(0x0000, TAG, `IdeaCollection invalid payload: activityId=${trimmedActivityId}, collectionId=${trimmedCollectionId}`);
      return false;
    }

    const now = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'id': RDBStoreUtil.generateUniqueId(),
      'collection_id': trimmedCollectionId,
      'activity_id': trimmedActivityId,
      'display_order': displayOrder,
      'created_at': now,
      'updated_at': now
    };

    try {
      hilog.info(0x0000, TAG,
        `IdeaCollection upsert item: activityId=${trimmedActivityId}, collectionId=${trimmedCollectionId}, displayOrder=${displayOrder}`);
      await this.rdbStore.insert('idea_collection_item', bucket,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `IdeaCollectionItem upsert failed: activityId=${trimmedActivityId}, collectionId=${trimmedCollectionId}, displayOrder=${displayOrder}, code=${error.code}, message=${error.message}`);
      return false;
    }
  }

  async clearIdeaCollectionItem(activityId: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid activityId for collection clear');
      return false;
    }

    try {
      const predicates = new relationalStore.RdbPredicates('idea_collection_item');
      predicates.equalTo('activity_id', activityId);
      const deleteResult = await this.rdbStore.delete(predicates);
      if (deleteResult > 0) {
      }
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaCollectionItem clear failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async upsertIdeaCategoryItem(activityId: string, categoryId: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!activityId || activityId.trim().length === 0 || !categoryId || categoryId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid category assignment payload');
      return false;
    }

    const now = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'id': RDBStoreUtil.generateUniqueId(),
      'category_id': categoryId,
      'activity_id': activityId,
      'created_at': now,
      'updated_at': now
    };

    try {
      await this.rdbStore.insert('idea_category_item', bucket,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaCategoryItem upsert failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async clearIdeaCategoryItem(activityId: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid activityId for category clear');
      return false;
    }

    try {
      const predicates = new relationalStore.RdbPredicates('idea_category_item');
      predicates.equalTo('activity_id', activityId);
      const deleteResult = await this.rdbStore.delete(predicates);
      if (deleteResult > 0) {
      }
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaCategoryItem clear failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async updateIdeaType(activityId: string, ideaType: IdeaType): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid activityId for idea_type update');
      return false;
    }

    try {
      const bucket: relationalStore.ValuesBucket = {
        'idea_type': ideaType,
        'updated_at': Date.now()
      };
      const predicates = new relationalStore.RdbPredicates('activity');
      predicates.equalTo('id', activityId);
      const updateResult = await this.rdbStore.update(bucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (updateResult > 0) {
        return true;
      }
      return false;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `IdeaType update failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async updateIdeaLightState(activityId: string, lightState: IdeaLightState): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid activityId for light_state update');
      return false;
    }

    try {
      const bucket: relationalStore.ValuesBucket = {
        'idea_light_state': lightState,
        'updated_at': Date.now()
      };
      const predicates = new relationalStore.RdbPredicates('activity');
      predicates.equalTo('id', activityId);
      const updateResult = await this.rdbStore.update(bucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (updateResult > 0) {
        return true;
      }
      return false;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Idea light_state update failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async resetIdeaLightStateAndCount(activityId: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid activityId for light reset');
      return false;
    }

    try {
      const bucket: relationalStore.ValuesBucket = {
        'idea_light_state': IdeaLightState.UNLIT,
        'idea_light_count': 0,
        'updated_at': Date.now()
      };
      const predicates = new relationalStore.RdbPredicates('activity');
      predicates.equalTo('id', activityId);
      const updateResult = await this.rdbStore.update(bucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (updateResult > 0) {
        return true;
      }
      return false;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Idea light reset failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async incrementIdeaLightCountAndSetLit(activityId: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid activityId for light_count increment');
      return false;
    }

    try {
      await this.rdbStore.executeSql(
        'UPDATE activity SET idea_light_count = idea_light_count + 1, idea_light_state = 1, updated_at = ? WHERE id = ?',
        [Date.now(), activityId]
      );
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Idea light_count increment failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async removeIdeaFromIdeaPool(activityId: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!activityId || activityId.trim().length === 0) {
      hilog.error(0x0000, TAG, 'Invalid activityId for IdeaPool removal');
      return false;
    }

    const now = Date.now();
    try {
      await this.rdbStore.beginTransaction();

      const activityBucket: relationalStore.ValuesBucket = {
        'idea_type': IdeaType.TODAY_ONLY,
        'updated_at': now
      };
      const activityPredicates = new relationalStore.RdbPredicates('activity');
      activityPredicates.equalTo('id', activityId);
      const updateResult = await this.rdbStore.update(activityBucket, activityPredicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      if (updateResult === 0) {
        await this.rdbStore.rollBack();
        return false;
      }

      const collectionPredicates = new relationalStore.RdbPredicates('idea_collection_item');
      collectionPredicates.equalTo('activity_id', activityId);
      await this.rdbStore.delete(collectionPredicates);

      const categoryPredicates = new relationalStore.RdbPredicates('idea_category_item');
      categoryPredicates.equalTo('activity_id', activityId);
      await this.rdbStore.delete(categoryPredicates);

      const sortPredicates = new relationalStore.RdbPredicates('idea_pool_sort_config');
      sortPredicates.equalTo('activity_id', activityId);
      await this.rdbStore.delete(sortPredicates);

      await this.rdbStore.commit();
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Remove from IdeaPool failed, code: ${error.code}, message: ${error.message}`);
      try {
        await this.rdbStore.rollBack();
      } catch (rollbackErr) {
        const rollbackError = rollbackErr as BusinessError;
        hilog.error(0x0000, TAG,
          `Rollback failed after IdeaPool removal error, code: ${rollbackError.code}, message: ${rollbackError.message}`);
      }
      return false;
    }
  }

  async queryIdeaPoolSortEntries(): Promise<SortEntry[]> {
    return this.querySortEntries('idea_pool_sort_config');
  }

  async queryTodayListSortEntries(): Promise<SortEntry[]> {
    return this.querySortEntries('today_list_sort_config');
  }

  async updateIdeaPoolSortOrder(orderedIds: string[]): Promise<SortEntry[]> {
    const result = await this.updateSortOrderInternal('idea_pool_sort_config', orderedIds);
    if (result.length > 0) {
    }
    return result;
  }

  async updateTodayListSortOrder(orderedIds: string[]): Promise<SortEntry[]> {
    const result = await this.updateSortOrderInternal('today_list_sort_config', orderedIds);
    if (result.length > 0) {
    }
    return result;
  }

  async resequenceIdeaPoolOrder(): Promise<SortEntry[]> {
    const currentEntries = await this.queryIdeaPoolSortEntries();
    const orderedIds = currentEntries.map(entry => entry.activityId);
    return this.updateIdeaPoolSortOrder(orderedIds);
  }

  async deleteIdeaPoolSortEntries(activityIds: string[]): Promise<number> {
    return this.deleteSortEntriesInternal('idea_pool_sort_config', activityIds);
  }

  async deleteTodayListSortEntries(activityIds: string[]): Promise<number> {
    return this.deleteSortEntriesInternal('today_list_sort_config', activityIds);
  }

  async getIdeaSummary(activityId: string): Promise<IdeaSummary | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_IDEA_SUMMARY_SQL, [activityId]);
      if (!resultSet.goToFirstRow()) {
        return null;
      }

      const latestRecordMs = this.readOptionalLong(resultSet, 'latest_record_timestamp');
      return {
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        tagId: this.readOptionalString(resultSet, 'tag_id'),
        tagName: this.readOptionalString(resultSet, 'tag_name'),
        tagColorHex: this.readOptionalString(resultSet, 'tag_color_hex'),
        tagLightColorHex: this.readOptionalString(resultSet, 'tag_light_color_hex'),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at')),
        latestRecordTimestamp: latestRecordMs === undefined ? null : latestRecordMs
      };
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询Idea Pool摘要失败, code: ${err.code}, message: ${err.message}`);
      return null;
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  /**
   * 根据ID查询标签
   * @param tagId 标签ID
   * @returns 标签对象或null
   */
  async queryTagById(tagId: string): Promise<TagItem |  null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const sql = RDBSQL.QUERY_TAG_BY_ID_SQL;

    try {
      const resultSet = await this.rdbStore.querySql(sql, [tagId]);

      if (resultSet.goToFirstRow()) {
        const tag = new TagItem(
          resultSet.getString(resultSet.getColumnIndex('id')),
          resultSet.getString(resultSet.getColumnIndex('name')),
          resultSet.getString(resultSet.getColumnIndex('color')),
          resultSet.getString(resultSet.getColumnIndex('light_color')),
          resultSet.getLong(resultSet.getColumnIndex('created_at')),
          resultSet.getLong(resultSet.getColumnIndex('updated_at'))
        );
        resultSet.close();
        return tag;
      } else {
        resultSet.close();
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, 'RDBStoreUtil', `根据ID查询标签失败: ${err.message}`);
    }
    return null;
  }

  /**
   * 根据活动ID查询对应的标签ID
   * @param activityId 活动ID
   * @returns 标签ID或null（如果活动没有标签）
   */
  async queryTagIdByActivityId(activityId: string): Promise<string | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 验证活动ID是否有效
    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid activity ID provided: empty or null');
      return null;
    }

    const sql = RDBSQL.QUERY_TAG_ID_BY_ACTIVITY_ID_SQL;

    try {
      const resultSet = await this.rdbStore.querySql(sql, [activityId]);

      if (resultSet.goToFirstRow()) {
        const tagId = resultSet.getString(resultSet.getColumnIndex('tag_id'));
        resultSet.close();
        return tagId;
      } else {
        resultSet.close();
        hilog.warn(0x0000, TAG, `No activity found with ID: ${activityId}`);
        return null;
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `Error querying tag ID by activity ID ${activityId}: ${err.message}`);
      return null;
    }
  }

  /**
   * 更新活动的标签
   * @param activityId 活动ID
   * @param tagId 新的标签ID（可以为null表示移除标签）
   * @returns 是否成功更新
   */
  async updateActivityTag(activityId: string, tagId: string | null): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 验证活动ID是否有效
    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid activity ID provided for tag update: empty or null');
      return false;
    }

    try {
      hilog.info(0x0000, TAG, `Updating tag for activity ${activityId} to tag ${tagId}`);

      const valueBucket: relationalStore.ValuesBucket = {
        'tag_id': tagId,
        'updated_at': Date.now()
      };

      let predicates = new relationalStore.RdbPredicates('activity');
      predicates.equalTo('id', activityId);

      const updateResult = await this.rdbStore.update(valueBucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

      if (updateResult > 0) {
        hilog.info(0x0000, TAG, `Successfully updated tag for activity ${activityId}`);
        return true;
      } else {
        hilog.warn(0x0000, TAG, `No rows affected when updating tag for activity ${activityId} - activity may not exist`);
        return false;
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Failed to update activity tag, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  /**
   * 更新活动的名称和标签
   * @param activityId 活动ID
   * @param name 新的活动名称
   * @param tagId 新的标签ID（可以为null表示移除标签）
   * @returns 是否成功更新
   */
  async updateActivityNameAndTag(activityId: string, name: string, tagId: string | null): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 验证活动ID是否有效
    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid activity ID provided for name and tag update: empty or null');
      return false;
    }

    // 验证活动名称是否有效
    if (!name || name.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid activity name provided for update: empty or null');
      return false;
    }

    try {
      hilog.info(0x0000, TAG, `Updating name and tag for activity ${activityId} to name: ${name}, tag: ${tagId}`);

      const valueBucket: relationalStore.ValuesBucket = {
        'name': name.trim(),
        'tag_id': tagId,
        'updated_at': Date.now()
      };

      let predicates = new relationalStore.RdbPredicates('activity');
      predicates.equalTo('id', activityId);

      const updateResult = await this.rdbStore.update(valueBucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

      if (updateResult > 0) {
        hilog.info(0x0000, TAG, `Successfully updated name and tag for activity ${activityId}`);
        return true;
      } else {
        hilog.warn(0x0000, TAG, `No rows affected when updating name and tag for activity ${activityId} - activity may not exist`);
        return false;
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Failed to update activity name and tag, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  /**
   * 确保数据库已初始化
   */
  private async ensureInitialized(): Promise<void> {
    if (!this.isInitialized) {
      await this.initRDB();
    }
  }

  /**
   * Query all open time records (no end_time) ordered by most recent start.
   */
  async queryActiveOpenRecords(): Promise<ActiveOpenRecord[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    const results: ActiveOpenRecord[] = [];
    try {
      const rs = await this.rdbStore.querySql(
        'SELECT tr.id AS record_id, tr.activity_id AS activity_id, tr.start_time AS start_time ' +
          'FROM time_record tr ' +
          'JOIN activity a ON a.id = tr.activity_id ' +
          'WHERE tr.end_time IS NULL OR tr.end_time <= 0 ' +
          'ORDER BY tr.start_time DESC'
      );
      try {
        while (rs.goToNextRow()) {
          results.push({
            recordId: rs.getString(rs.getColumnIndex('record_id')),
            activityId: rs.getString(rs.getColumnIndex('activity_id')),
            startTime: rs.getLong(rs.getColumnIndex('start_time'))
          });
        }
      } finally {
        rs.close();
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `queryActiveOpenRecords failed code=${error.code}, message=${error.message}`);
    }
    return results;
  }

  /**
   * 插入时间记录
   * @param activityId 活动ID
   * @param startTime 开始时间（时间戳，毫秒）
   * @param endTime 结束时间（时间戳，毫秒），可选
   * @param duration 持续时间（毫秒）
   * @returns Promise with the inserted record ID
   */
  async insertTimeRecord(
    activityId: string,
    startTime: number,
    endTime?: number,
    duration?: number
  ): Promise<string> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const recordId = RDBStoreUtil.generateUniqueId();
    const now = Date.now();
    const recordData: relationalStore.ValuesBucket = {
      'id': recordId,
      'activity_id': activityId,
      'start_time': startTime,
      'end_time': endTime || null,
      'duration_milliseconds': duration || null,
      'created_at': now,
      'updated_at': now
    };

    const maxAttempts = 3;
    const baseDelayMs = 60 + Math.floor(Math.random() * 40); // small jitter to avoid thundering herd

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        const rowId = await this.rdbStore.insert('time_record', recordData,
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        hilog.info(0x0000, TAG, `Time record insert successful (attempt ${attempt}), rowId = ${rowId}, record ID${recordId}`);
        // Do not push for active recording start; only push when the record is completed (has endTime).
        if (typeof endTime === 'number' && endTime > 0) {
        }
        return recordId;
      } catch (err) {
        const error = err as BusinessError;
        const message = `Time record insert failed (attempt ${attempt}/${maxAttempts}), code: ${error.code}, message: ${error.message}`;

        // Retry on likely transient lock/busy conditions; otherwise fail fast.
        const lowerMsg = (error.message || '').toLowerCase();
        const isBusy = [14800050, 14800052, 14800061].includes(error.code) // common RDB busy/locked codes
          || lowerMsg.includes('locked')
          || lowerMsg.includes('busy')
          || lowerMsg.includes('concurrent');

        if (!isBusy || attempt === maxAttempts) {
          hilog.error(0x0000, TAG, message);
          return '';
        }

        hilog.warn(0x0000, TAG, `${message} -> will retry after backoff`);
        await new Promise<void>(resolve => setTimeout(resolve, baseDelayMs * attempt));
      }
    }
    return '';
  }


  /**
   * 查询活动的今日总时长（毫秒）
   * @param activityId 活动ID
   * @returns 今日总时长（毫秒）
   */
  async queryTodayTotalDuration(activityId: string): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 获取今日的开始时间（0点）
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStart = today.getTime();

    const sql = RDBSQL.QUERY_TODAY_TOTAL_DURATION_SQL;

    try {
      const resultSet = await this.rdbStore.querySql(sql, [activityId, todayStart]);

      if (resultSet.goToFirstRow()) {
        const totalDuration = resultSet.getLong(resultSet.getColumnIndex('total_duration'));
        resultSet.close();
        return totalDuration;
      } else {
        resultSet.close();
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询今日总时长失败: ${err.message}`);
    }
    return 0;
  }

  /**
   * 更新活动的状态
   * @param activityId 活动ID
   * @param status 新状态
   * @returns 是否成功更新
   */
  async updateActivityStatus(activityId: string, status: number): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    try {
      hilog.info(0x0000, TAG, `Attempting to update activity ${activityId} status to ${status}`);
      await this.rdbStore.beginTransaction();

      const valueBucket: relationalStore.ValuesBucket = {
        'status': status,
        'updated_at': Date.now()
      };

      let predicates = new relationalStore.RdbPredicates('activity');
      predicates.equalTo('id', activityId);

      const updateResult = await this.rdbStore.update(valueBucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

      hilog.info(0x0000, TAG, `Activity status update result: ${updateResult} rows affected`);

      if (updateResult === 0) {
        hilog.warn(0x0000, TAG,
          `No rows affected when updating activity ${activityId} status to ${status} - activity may not exist`);
        await this.rdbStore.rollBack();
        return false;
      }

      if (status === MatterStatus.ARCHIVED) {
        await this.deleteTodayListSortEntries([activityId]);
        await this.deleteIdeaPoolSortEntries([activityId]);
      }

      await this.rdbStore.commit();
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Activity status update failed, code: ${error.code}, message: ${error.message}`);
      try {
        if (this.rdbStore) {
          await this.rdbStore.rollBack();
        }
      } catch (rollbackError) {
        const rollbackBusinessError = rollbackError as BusinessError;
        hilog.error(0x0000, TAG,
          `Rollback failed after status update error, code: ${rollbackBusinessError.code}, message: ${rollbackBusinessError.message}`);
      }
      return false;
    }
  }

  /**
   * 统计所有活动的今日总时长
   * @returns 所有活动的今日总时长（毫秒）
   */
  async queryAllTodayTotalDuration(): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 获取今日的开始时间（0点）
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStart = today.getTime();

    const sql = RDBSQL.QUERY_ALL_TODAY_TOTAL_DURATION_SQL;

    try {
      const resultSet = await this.rdbStore.querySql(sql, [todayStart]);

      if (resultSet.goToFirstRow()) {
        const totalDuration = resultSet.getLong(resultSet.getColumnIndex('total_duration'));
        resultSet.close();
        return totalDuration;
      } else {
        resultSet.close();
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询所有活动今日总时长失败: ${err.message}`);
    }
    return 0;
  }

  /**
   * 更新时间记录的结束时间和持续时间
   * @param recordId 时间记录ID
   * @param endTime 结束时间（时间戳，毫秒）
   * @param duration 持续时间（毫秒）
   * @returns 更新的行数
   */
  async updateTimeRecord(recordId: string, endTime: number, duration: number): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    try {
      const valueBucket: relationalStore.ValuesBucket = {
        'end_time': endTime,
        'duration_milliseconds': duration,
        'updated_at': Date.now()
      };

      let predicates = new relationalStore.RdbPredicates('time_record');
      predicates.equalTo('id', recordId);

      const updateResult = await this.rdbStore.update(valueBucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

      hilog.info(0x0000, TAG, `Time record update successful, updated ${updateResult} rows`);
      if (updateResult > 0) {
      }
      return updateResult;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Time record update failed, code: ${error.code}, message: ${error.message}`);
      return 0;
    }
  }

  /**
   * 更新时间记录的开始时间
   * @param recordId 时间记录ID
   * @param startTime 新的开始时间（时间戳，毫秒）
   * @returns 是否成功更新
   */
  async updateTimeRecordStartTime(recordId: string, startTime: number): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    try {
      // 首先获取当前的时间记录
      const currentRecord = await this.queryTimeRecordById(recordId);
      if (!currentRecord) {
        hilog.error(0x0000, TAG, `Time record not found for ID: ${recordId}`);
        return false;
      }

      // 计算新的持续时间（如果记录有结束时间）
      let newDuration = currentRecord.duration as number;
      if (currentRecord.endTime) {
        newDuration = currentRecord.endTime - startTime;
        if (newDuration < 0) {
          hilog.error(0x0000, TAG, `Invalid duration calculated: ${newDuration}ms for record ${recordId}`);
          return false;
        }
      }

      const valueBucket: relationalStore.ValuesBucket = {
        'start_time': startTime,
        'duration_milliseconds': newDuration,
        'updated_at': Date.now()
      };

      let predicates = new relationalStore.RdbPredicates('time_record');
      predicates.equalTo('id', recordId);

      const updateResult = await this.rdbStore.update(valueBucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

      hilog.info(0x0000, TAG, `Time record start time update successful, updated ${updateResult} rows`);
      if (updateResult > 0 && currentRecord.endTime) {
      }
      return updateResult > 0;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Time record start time update failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  /**
   * 更新时间记录的开始时间、结束时间和持续时间
   * @param recordId 时间记录ID
   * @param startTime 新的开始时间（时间戳，毫秒）
   * @param endTime 新的结束时间（时间戳，毫秒）
   * @param duration 新的持续时间（毫秒），可选
   * @returns 是否成功更新
   */
  async updateTimeRecordStartEndTime(recordId: string, startTime: number, endTime: number, duration?: number): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    try {
      // 首先获取当前的时间记录
      const currentRecord = await this.queryTimeRecordById(recordId);
      if (!currentRecord) {
        hilog.error(0x0000, TAG, `Time record not found for ID: ${recordId}`);
        return false;
      }

      // 计算新的持续时间
      let newDuration = currentRecord.duration as number;

      if (endTime && startTime) {
        // 如果同时提供了开始和结束时间，则重新计算持续时间
        newDuration = endTime - startTime;
        if (newDuration < 0) {
          hilog.error(0x0000, TAG, `Invalid duration calculated: ${newDuration}ms for record ${recordId}`);
          return false;
        }
      } else if (duration !== undefined) {
        // 如果提供了duration参数，使用提供的值
        newDuration = duration;
      }

      const valueBucket: relationalStore.ValuesBucket = {
        'start_time': startTime,
        'end_time': endTime,
        'duration_milliseconds': newDuration,
        'updated_at': Date.now()
      };

      let predicates = new relationalStore.RdbPredicates('time_record');
      predicates.equalTo('id', recordId);

      const updateResult = await this.rdbStore.update(valueBucket, predicates,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

      hilog.info(0x0000, TAG, `Time record update successful, updated ${updateResult} rows`);
      if (updateResult > 0 && endTime) {
      }
      return updateResult > 0;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Time record update failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  /**
   * 查询指定活动的最新时间记录
   * @param activityId 活动ID
   * @param recordId 可选的时间记录ID，如果提供则直接查询该记录
   * @returns 最新的时间记录对象，如果没有则返回null
   */
  async queryLatestTimeRecord(activityId: string, recordId?: string): Promise<TimeRecord | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 如果提供了记录ID，优先使用记录ID查询
    if (recordId && recordId.trim() !== '') {
      try {
        const record = await this.queryTimeRecordById(recordId);
        if (record) {
          // 验证记录是否属于指定的活动
          if (record.activityId === activityId) {
            return record;
          } else {
            hilog.warn(0x0000, TAG, `Record ID ${recordId} does not belong to activity ${activityId}, falling back to activity-based query`);
          }
        } else {
          hilog.warn(0x0000, TAG, `Record with ID ${recordId} not found, falling back to activity-based query`);
        }
      } catch (error) {
        const err = error as BusinessError;
        hilog.error(0x0000, TAG, `Error querying record by ID ${recordId}: ${err.message}, falling back to activity-based query`);
      }
    }

    // 回退到原有的基于活动ID的查询逻辑
    const sql = RDBSQL.QUERY_LATEST_TIME_RECORD_SQL;

    try {
      const resultSet = await this.rdbStore.querySql(sql, [activityId]);

      if (resultSet.goToFirstRow()) {
        const record = this.mapRowToTimeRecord(resultSet);
        resultSet.close();
        return record;
      } else {
        resultSet.close();
        return null;
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询最新时间记录失败: ${err.message}`);
      return null;
    }
  }

  /**
   * 根据ID查询时间记录
   * @param recordId 时间记录ID
   * @returns 时间记录对象，如果没有则返回null
   */
  async queryTimeRecordById(recordId: string): Promise<TimeRecord | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 验证记录ID是否有效
    if (!recordId || recordId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid record ID provided: empty or null');
      return null;
    }

    const sql = RDBSQL.QUERY_TIME_RECORD_BY_ID_SQL;

    try {
      const resultSet = await this.rdbStore.querySql(sql, [recordId]);

      if (resultSet.goToFirstRow()) {
        const record = this.mapRowToTimeRecord(resultSet);
        resultSet.close();

        // 验证记录数据的完整性
        if (!record.id || !record.activityId || !record.startTime) {
          hilog.error(0x0000, TAG, `Invalid time record data for ID ${recordId}: missing required fields`);
          return null;
        }

        return record;
      } else {
        resultSet.close();
        hilog.warn(0x0000, TAG, `No time record found with ID: ${recordId}`);
        return null;
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `Error querying time record with ID ${recordId}: ${err.message}`);
      return null;
    }
  }

  async queryTimeRecordCalendarMapByRecordId(recordId: string): Promise<TimeRecordCalendarMapItem | null> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      return null;
    }

    try {
      const resultSet = await this.rdbStore.querySql(
        RDBSQL.QUERY_TIME_RECORD_CALENDAR_MAP_BY_RECORD_ID_SQL,
        [normalizedRecordId]
      );
      try {
        if (!resultSet.goToFirstRow()) {
          return null;
        }
        return this.mapRowToTimeRecordCalendarMap(resultSet);
      } finally {
        resultSet.close();
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed querying time_record_calendar_map by recordId=${normalizedRecordId}, code=${error.code}, message=${error.message}`);
      return null;
    }
  }

  async queryTimeRecordCalendarMapsByRecordIds(recordIds: string[]): Promise<TimeRecordCalendarMapItem[]> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const normalizedRecordIds: string[] = recordIds
      .map((recordId: string) => recordId.trim())
      .filter((recordId: string) => recordId.length > 0);
    if (normalizedRecordIds.length === 0) {
      return [];
    }

    const placeholders: string = normalizedRecordIds.map(() => '?').join(', ');
    const sql: string = `${RDBSQL.QUERY_TIME_RECORD_CALENDAR_MAP_BY_RECORD_IDS_SQL_PREFIX}(${placeholders})`;

    try {
      const resultSet = await this.rdbStore.querySql(sql, normalizedRecordIds);
      const mappings: TimeRecordCalendarMapItem[] = [];
      try {
        while (resultSet.goToNextRow()) {
          mappings.push(this.mapRowToTimeRecordCalendarMap(resultSet));
        }
      } finally {
        resultSet.close();
      }
      return mappings;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed querying time_record_calendar_map by recordIds, code=${error.code}, message=${error.message}`);
      return [];
    }
  }

  async queryTimeRecordCalendarMapsBySyncStatus(
    statuses: TimeRecordCalendarSyncStatus[]
  ): Promise<TimeRecordCalendarMapItem[]> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (statuses.length === 0) {
      return [];
    }

    const placeholders: string = statuses.map(() => '?').join(', ');
    const sql: string = `${RDBSQL.QUERY_TIME_RECORD_CALENDAR_MAP_BY_SYNC_STATUS_SQL_PREFIX}(${placeholders})`;

    try {
      const resultSet = await this.rdbStore.querySql(sql, statuses);
      const mappings: TimeRecordCalendarMapItem[] = [];
      try {
        while (resultSet.goToNextRow()) {
          mappings.push(this.mapRowToTimeRecordCalendarMap(resultSet));
        }
      } finally {
        resultSet.close();
      }
      return mappings;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed querying time_record_calendar_map by sync status, code=${error.code}, message=${error.message}`);
      return [];
    }
  }

  async upsertTimeRecordCalendarMap(input: TimeRecordCalendarMapUpsertInput): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const normalizedRecordId: string = input.timeRecordId.trim();
    if (!normalizedRecordId) {
      hilog.warn(0x0000, TAG, 'Skip upsert time_record_calendar_map: empty timeRecordId');
      return false;
    }

    const existing: TimeRecordCalendarMapItem | null = await this.queryTimeRecordCalendarMapByRecordId(normalizedRecordId);
    const now: number = Date.now();
    const createdAt: number = existing ? existing.createdAt : now;

    const values: relationalStore.ValuesBucket = {
      'time_record_id': normalizedRecordId,
      'calendar_id': input.calendarId,
      'calendar_event_id': typeof input.calendarEventId === 'number' ? input.calendarEventId : null,
      'sync_status': input.syncStatus,
      'pending_action': input.pendingAction,
      'last_error_code': typeof input.lastErrorCode === 'number' ? input.lastErrorCode : null,
      'last_synced_at': typeof input.lastSyncedAt === 'number' ? input.lastSyncedAt : null,
      'created_at': createdAt,
      'updated_at': now
    };

    try {
      await this.rdbStore.insert(
        'time_record_calendar_map',
        values,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed upserting time_record_calendar_map for recordId=${normalizedRecordId}, code=${error.code}, message=${error.message}`);
      return false;
    }
  }

  async deleteTimeRecordCalendarMapByRecordId(recordId: string): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const normalizedRecordId: string = recordId.trim();
    if (!normalizedRecordId) {
      return true;
    }

    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('time_record_calendar_map');
      predicates.equalTo('time_record_id', normalizedRecordId);
      await this.rdbStore.delete(predicates);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed deleting time_record_calendar_map for recordId=${normalizedRecordId}, code=${error.code}, message=${error.message}`);
      return false;
    }
  }

  async deleteTimeRecordCalendarMapsByRecordIds(recordIds: string[]): Promise<number> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const normalizedRecordIds: string[] = recordIds
      .map((recordId: string) => recordId.trim())
      .filter((recordId: string) => recordId.length > 0);
    if (normalizedRecordIds.length === 0) {
      return 0;
    }

    try {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('time_record_calendar_map');
      const predicateWithIn: RdbPredicatesWithInMethod = predicates as RdbPredicatesWithInMethod;
      const hasInMethod: boolean = typeof predicateWithIn.in === 'function';
      if (hasInMethod && predicateWithIn.in) {
        predicateWithIn.in('time_record_id', normalizedRecordIds);
        return await this.rdbStore.delete(predicates);
      }

      const placeholders: string = normalizedRecordIds.map(() => '?').join(', ');
      const sql: string = `DELETE FROM time_record_calendar_map WHERE time_record_id IN (${placeholders})`;
      await this.rdbStore.executeSql(sql, normalizedRecordIds);
      return normalizedRecordIds.length;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed deleting time_record_calendar_map by recordIds, code=${error.code}, message=${error.message}`);
      return -1;
    }
  }

  /**
   * 开始事务
   */
  async beginTransaction(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    await this.rdbStore.beginTransaction();
    hilog.info(0x0000, TAG, 'Transaction started');
  }

  /**
   * 提交事务
   */
  async commit(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    await this.rdbStore.commit();
    hilog.info(0x0000, TAG, 'Transaction committed');
  }

  /**
   * Execute raw SQL with optional parameters.
   */
  async executeSql(sql: string, params: Array<string | number | boolean | null> = []): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    return this.rdbStore.executeSql(sql, params);
  }

  /**
   * 回滚事务
   */
  async rollBack(): Promise<void> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    await this.rdbStore.rollBack();
    hilog.info(0x0000, TAG, 'Transaction rolled back');
  }

  /**
   * 删除时间记录
   * @param recordId 时间记录ID
   * @returns 是否成功删除
   */
  async deleteTimeRecord(recordId: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 验证记录ID是否有效
    if (!recordId || recordId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid record ID provided for deletion: empty or null');
      return false;
    }

    try {
      let predicates = new relationalStore.RdbPredicates('time_record');
      predicates.equalTo('id', recordId);

      const deleteResult = await this.rdbStore.delete(predicates);

      if (deleteResult > 0) {
        hilog.info(0x0000, TAG, `Time record deleted successfully, record ID: ${recordId}`);
        return true;
      } else {
        hilog.warn(0x0000, TAG, `No time record found with ID: ${recordId} for deletion`);
        return false;
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Time record deletion failed, code: ${error.code}, message: ${error.message}`);
      return false;
    }
  }

  async queryActivityCoverMediaLocalPath(activityId: string): Promise<string | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'PhotoPick queryActivityCoverMediaLocalPath failed: activityId is empty.');
      return null;
    }

    try {
      hilog.info(0x0000, TAG, `PhotoPick queryActivityCoverMediaLocalPath start activityId=${activityId}`);
      const rs = await this.rdbStore.querySql(RDBSQL.QUERY_ACTIVITY_COVER_MEDIA_BY_ACTIVITY_ID_SQL, [activityId]);
      try {
        if (!rs.goToFirstRow()) {
          hilog.info(0x0000, TAG, `PhotoPick queryActivityCoverMediaLocalPath no rows activityId=${activityId}`);
          return null;
        }
        const localPath = rs.getString(rs.getColumnIndex('local_path'));
        hilog.info(0x0000, TAG, `PhotoPick queryActivityCoverMediaLocalPath ok activityId=${activityId} localPath=${localPath}`);
        return localPath;
      } finally {
        rs.close();
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `PhotoPick queryActivityCoverMediaLocalPath exception activityId=${activityId}, code=${error.code}, message=${error.message}`);
      return null;
    }
  }

  async queryActivityDiary(activityId: string): Promise<string | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'queryActivityDiary failed: activityId is empty.');
      return null;
    }

    try {
      const rs = await this.rdbStore.querySql(RDBSQL.QUERY_ACTIVITY_DIARY_SQL, [activityId]);
      try {
        if (!rs.goToFirstRow()) {
          return null;
        }
        const textIndex = rs.getColumnIndex('text');
        return rs.isColumnNull(textIndex) ? '' : rs.getString(textIndex);
      } finally {
        rs.close();
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `queryActivityDiary exception activityId=${activityId}, code=${error.code}, message=${error.message}`);
      return null;
    }
  }

  async queryActivityMediaPaths(activityId: string): Promise<string[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid activity ID provided for media paths query: empty or null');
      return [];
    }

    try {
      const rs = await this.rdbStore.querySql(RDBSQL.QUERY_ACTIVITY_MEDIA_PATHS_BY_ACTIVITY_ID_SQL, [activityId]);
      const paths: string[] = [];
      try {
        while (rs.goToNextRow()) {
          paths.push(rs.getString(rs.getColumnIndex('local_path')));
        }
      } finally {
        rs.close();
      }
      return paths;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `Failed to query activity media paths for ${activityId}, code=${error.code}, message=${error.message}`);
      return [];
    }
  }

  async queryMediaLocalPathByHash(contentHash: string): Promise<string | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    if (!contentHash || contentHash.trim() === '') {
      return null;
    }

    try {
      const rs = await this.rdbStore.querySql(RDBSQL.QUERY_ACTIVITY_MEDIA_PATH_BY_HASH_SQL, [contentHash]);
      try {
        if (!rs.goToFirstRow()) {
          return null;
        }
        return rs.getString(rs.getColumnIndex('local_path'));
      } finally {
        rs.close();
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(0x0000, TAG,
        `Failed to query media path by hash, code=${error.code}, message=${error.message}`);
      return null;
    }
  }

  async queryMediaPathReferenceCount(localPath: string): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    if (!localPath || localPath.trim() === '') {
      return 0;
    }

    try {
      const rs = await this.rdbStore.querySql(RDBSQL.QUERY_ACTIVITY_MEDIA_REFCOUNT_BY_PATH_SQL, [localPath]);
      try {
        if (!rs.goToFirstRow()) {
          return 0;
        }
        const refCount = this.readOptionalLong(rs, 'ref_count');
        return refCount ? Number(refCount) : 0;
      } finally {
        rs.close();
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(0x0000, TAG,
        `Failed to query media ref count for ${localPath}, code=${error.code}, message=${error.message}`);
      return -1;
    }
  }

  private normalizeStoredMediaPath(ctx: common.UIAbilityContext, storedPath: string): string {
    if (storedPath.startsWith('/')) {
      return storedPath;
    }
    return `${ctx.filesDir}/${storedPath}`;
  }

  private async cleanupStoredMediaFilesBestEffort(storedPaths: string[]): Promise<void> {
    if (!this.context) {
      return;
    }
    const ctx = this.context as common.UIAbilityContext;
    const uniquePaths = Array.from(new Set(storedPaths));
    for (const storedPath of uniquePaths) {
      if (!storedPath || storedPath.trim().length === 0) {
        continue;
      }
      const remainingCount = await this.queryMediaPathReferenceCount(storedPath);
      if (remainingCount !== 0) {
        continue;
      }
      const absPath = this.normalizeStoredMediaPath(ctx, storedPath);
      try {
        fs.unlinkSync(absPath);
      } catch (err) {
        const error = err as BusinessError;
        hilog.warn(0x0000, TAG,
          `Failed to delete media file for cleanup: ${storedPath}, code=${error.code}, message=${error.message}`);
      }
    }
  }

  async replaceActivityCoverMedia(
    activityId: string,
    localPath: string,
    mimeType: string,
    byteSize: number = 0,
    width: number = 0,
    height: number = 0,
    contentHash: string | null = null
  ): Promise<ReplaceActivityCoverMediaResult> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'PhotoPick replaceActivityCoverMedia failed: activityId is empty.');
      return { ok: false, oldPaths: [] };
    }
    if (!localPath || localPath.trim() === '') {
      hilog.error(0x0000, TAG, 'PhotoPick replaceActivityCoverMedia failed: localPath is empty.');
      return { ok: false, oldPaths: [] };
    }
    if (!mimeType || mimeType.trim() === '') {
      hilog.error(0x0000, TAG, 'PhotoPick replaceActivityCoverMedia failed: mimeType is empty.');
      return { ok: false, oldPaths: [] };
    }

    const oldPaths: string[] = [];
    const now = Date.now();
    try {
      hilog.info(0x0000, TAG,
        `PhotoPick replaceActivityCoverMedia start activityId=${activityId} localPath=${localPath} mimeType=${mimeType} byteSize=${byteSize}`);
      const oldRs = await this.rdbStore.querySql(
        'SELECT local_path FROM activity_media WHERE activity_id = ? AND is_cover = 1',
        [activityId]
      );
      try {
        while (oldRs.goToNextRow()) {
          oldPaths.push(oldRs.getString(oldRs.getColumnIndex('local_path')));
        }
      } finally {
        oldRs.close();
      }
      hilog.info(0x0000, TAG,
        `PhotoPick replaceActivityCoverMedia oldPathsCount=${oldPaths.length} activityId=${activityId}`);

      await this.rdbStore.beginTransaction();

      const deletePredicates = new relationalStore.RdbPredicates('activity_media');
      deletePredicates.equalTo('activity_id', activityId);
      deletePredicates.equalTo('is_cover', 1);
      const deleted = await this.rdbStore.delete(deletePredicates);
      hilog.info(0x0000, TAG, `PhotoPick replaceActivityCoverMedia deletedCoverRows=${deleted} activityId=${activityId}`);

      const mediaId = RDBStoreUtil.generateUniqueId();
      await this.rdbStore.insert('activity_media', {
        id: mediaId,
        activity_id: activityId,
        local_path: localPath,
        content_hash: contentHash,
        mime_type: mimeType,
        width,
        height,
        byte_size: byteSize,
        display_order: 0,
        is_cover: 1,
        created_at: now,
        updated_at: now
      }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

      await this.rdbStore.commit();

      hilog.info(0x0000, TAG,
        `PhotoPick replaceActivityCoverMedia committed activityId=${activityId} mediaId=${mediaId} localPath=${localPath}`);
      return { ok: true, oldPaths };
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG,
        `PhotoPick replaceActivityCoverMedia exception activityId=${activityId}, code=${error.code}, message=${error.message}`);
      try {
        await this.rdbStore.rollBack();
      } catch (rollbackErr) {
        const rollbackError = rollbackErr as BusinessError;
        hilog.error(0x0000, TAG,
          `PhotoPick replaceActivityCoverMedia rollback failed activityId=${activityId}, code=${rollbackError.code}, message=${rollbackError.message}`);
      }
      return { ok: false, oldPaths: [] };
    }
  }

  /**
   * 删除活动及其相关记录
   * @param activityId 活动ID
   * @returns 是否成功删除
   */
  async deleteActivity(activityId: string): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 验证活动ID是否有效
    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid activity ID provided for deletion: empty or null');
      return false;
    }

    const mediaPathsForCleanup = await this.queryActivityMediaPaths(activityId);
    try {
      // 开始事务
      await this.rdbStore.beginTransaction();
      hilog.info(0x0000, TAG, `Starting transaction to delete activity ${activityId}`);

      // 1. 删除活动记录
      let activityPredicates = new relationalStore.RdbPredicates('activity');
      activityPredicates.equalTo('id', activityId);

      const activityDeleteResult = await this.rdbStore.delete(activityPredicates);

      if (activityDeleteResult === 0) {
        hilog.warn(0x0000, TAG, `No activity found with ID: ${activityId} for deletion`);
        await this.rdbStore.rollBack();
        return false;
      }

      hilog.info(0x0000, TAG, `Activity deleted successfully, ID: ${activityId}`);

      // 2. 删除相关的时间记录（虽然数据库有ON DELETE CASCADE，但显式删除更安全）
      let timeRecordPredicates = new relationalStore.RdbPredicates('time_record');
      timeRecordPredicates.equalTo('activity_id', activityId);

      const timeRecordDeleteResult = await this.rdbStore.delete(timeRecordPredicates);
      hilog.info(0x0000, TAG, `Time records deleted successfully, count: ${timeRecordDeleteResult}`);

      // 2.1 删除日记文本
      let diaryPredicates = new relationalStore.RdbPredicates('activity_diary');
      diaryPredicates.equalTo('activity_id', activityId);
      const diaryDeleteResult = await this.rdbStore.delete(diaryPredicates);
      hilog.info(0x0000, TAG, `Activity diary deleted successfully, count: ${diaryDeleteResult}`);

      // 2.2 删除媒体元数据
      let mediaPredicates = new relationalStore.RdbPredicates('activity_media');
      mediaPredicates.equalTo('activity_id', activityId);
      const mediaDeleteResult = await this.rdbStore.delete(mediaPredicates);
      hilog.info(0x0000, TAG, `Activity media deleted successfully, count: ${mediaDeleteResult}`);

      // 3. 删除今日列表排序配置
      let todaySortPredicates = new relationalStore.RdbPredicates('today_list_sort_config');
      todaySortPredicates.equalTo('activity_id', activityId);

      const todaySortDeleteResult = await this.rdbStore.delete(todaySortPredicates);
      hilog.info(0x0000, TAG, `Today list sort config deleted successfully, count: ${todaySortDeleteResult}`);

      // 4. 删除想法池排序配置
      let ideaSortPredicates = new relationalStore.RdbPredicates('idea_pool_sort_config');
      ideaSortPredicates.equalTo('activity_id', activityId);

      const ideaSortDeleteResult = await this.rdbStore.delete(ideaSortPredicates);
      hilog.info(0x0000, TAG, `Idea pool sort config deleted successfully, count: ${ideaSortDeleteResult}`);

      // 提交事务
      await this.rdbStore.commit();
      hilog.info(0x0000, TAG, `Transaction committed successfully for activity ${activityId} deletion`);

      await this.cleanupStoredMediaFilesBestEffort(mediaPathsForCleanup);

      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0x0000, TAG, `Activity deletion failed, code: ${error.code}, message: ${error.message}`);

      // 回滚事务
      try {
        if (this.rdbStore) {
          await this.rdbStore.rollBack();
          hilog.info(0x0000, TAG, 'Transaction rolled back due to error');
        }
      } catch (rollbackErr) {
        const rollbackError = rollbackErr as BusinessError;
        hilog.error(0x0000, TAG, `Transaction rollback failed, code: ${rollbackError.code}, message: ${rollbackError.message}`);
      }

      return false;
    }
  }
  /**
   * 查询指定活动对应的所有时间记录
   * @param activityId 活动ID
   * @returns 该活动对应的所有时间记录数组
   */
  async queryTimeRecordsByActivityId(activityId: string): Promise<TimeRecord[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 验证活动ID是否有效
    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid activity ID provided: empty or null');
      return [];
    }

    try {
      const resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_TIME_RECORDS_BY_ACTIVITY_ID_SQL, [activityId]);
      const timeRecords: TimeRecord[] = [];

      while (resultSet.goToNextRow()) {
        const record = this.mapRowToTimeRecord(resultSet);
        timeRecords.push(record);
      }

      resultSet.close();
      hilog.info(0x0000, TAG, `查询到活动 ${activityId} 的 ${timeRecords.length} 个时间记录`);
      return timeRecords;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询活动 ${activityId} 的时间记录失败: ${err.message}`);
    }
    return [];
  }

  /**
   * 查询指定活动的所有未结束时间记录（open records）
   * @param activityId 活动ID
   * @returns 未结束时间记录数组，按 start_time DESC 排序
   */
  async queryOpenTimeRecordsByActivityId(activityId: string): Promise<TimeRecord[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (!activityId || activityId.trim() === '') {
      hilog.error(0x0000, TAG, 'Invalid activity ID provided for open record query: empty or null');
      return [];
    }

    try {
      const resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_OPEN_TIME_RECORDS_BY_ACTIVITY_ID_SQL, [activityId]);
      const timeRecords: TimeRecord[] = [];

      while (resultSet.goToNextRow()) {
        const record: TimeRecord = this.mapRowToTimeRecord(resultSet);
        timeRecords.push(record);
      }

      resultSet.close();
      hilog.info(0x0000, TAG, `查询到活动 ${activityId} 的 ${timeRecords.length} 个未结束时间记录`);
      return timeRecords;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询活动 ${activityId} 的未结束时间记录失败: ${err.message}`);
    }
    return [];
  }

  /**
   * 查询非今天的事项（状态为TODO、RECORDING或PAUSED但创建时间不是今天的事项）
   * @returns 非今天的事项列表
   */
  async queryNonTodayActivities(): Promise<TodayActivityItem[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    // 获取今日的开始时间（0点）
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStart = today.getTime();

    const sql = RDBSQL.QUERY_NON_TODAY_ACTIVITIES_SQL;
    const params = [todayStart, todayStart, todayStart, todayStart];

    try {
      const resultSet = await this.rdbStore.querySql(sql, params);
      const activities: TodayActivityItem[] = [];

      while (resultSet.goToNextRow()) {
        const activity: TodayActivityItem = new TodayActivityItem(
          resultSet.getString(resultSet.getColumnIndex('id')),
          resultSet.getString(resultSet.getColumnIndex('name')),
          resultSet.getLong(resultSet.getColumnIndex('status')),
          resultSet.getString(resultSet.getColumnIndex('tag_name')),
          resultSet.getString(resultSet.getColumnIndex('tag_color_hex')),
          resultSet.getLong(resultSet.getColumnIndex('display_order'))
        );
        activities.push(activity);
      }

      resultSet.close();
      hilog.info(0x0000, TAG, `查询到 ${activities.length} 个非今天的事项`);
      return activities;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `查询非今天事项失败: ${err.message}`);
    }
    return [];
  }

  async recoverArchivedActivitiesWithTodayRecords(): Promise<number> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStart = today.getTime();

    const params = [MatterStatus.ARCHIVED, todayStart, todayStart, todayStart];

    try {
      const resultSet = await this.rdbStore.querySql(
        RDBSQL.QUERY_ARCHIVED_ACTIVITIES_WITH_TODAY_RECORDS_SQL,
        params
      );

      const activityIds: string[] = [];
      while (resultSet.goToNextRow()) {
        activityIds.push(resultSet.getString(resultSet.getColumnIndex('id')));
      }
      resultSet.close();

      if (activityIds.length === 0) {
        hilog.info(0x0000, TAG, 'No archived activities require recovery.');
        return 0;
      }

      await this.rdbStore.beginTransaction();
      try {
        for (const activityId of activityIds) {
          const valueBucket: relationalStore.ValuesBucket = {
            'status': MatterStatus.PAUSED,
            'updated_at': Date.now()
          };

          const predicates = new relationalStore.RdbPredicates('activity');
          predicates.equalTo('id', activityId);
          await this.rdbStore.update(valueBucket, predicates, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }

        await this.rdbStore.commit();
        hilog.info(0x0000, TAG, `Recovered ${activityIds.length} archived activities with today records.`);
        return activityIds.length;
      } catch (transactionError) {
        await this.rdbStore.rollBack();
        hilog.error(0x0000, TAG, `Failed to recover archived activities: ${JSON.stringify(transactionError)}`);
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `Error recovering archived activities: ${err.message}`);
    }

    return 0;
  }

  /**
   * 批量更新事项状态为ARCHIVED
   * @param activityIds 需要更新状态的事项ID数组
   * @returns 是否成功更新
   */
  async batchArchiveActivities(activityIds: string[]): Promise<boolean> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    if (activityIds.length === 0) {
      hilog.info(0x0000, TAG, '没有需要归档的事项');
      return true;
    }

    try {
      // 开始事务
      await this.rdbStore.beginTransaction();

      // 构建IN子句的参数占位符
      const placeholders = activityIds.map(() => '?').join(',');

      // 更新事项状态为ARCHIVED
      const updateSql = `${RDBSQL.BATCH_ARCHIVE_ACTIVITIES_SQL_PREFIX}${MatterStatus.ARCHIVED}, updated_at = ? WHERE id IN (${placeholders})`;

      // 构建参数数组：当前时间戳 + 所有事项ID
      const params: Array<number | string> = [Date.now()];
      activityIds.forEach((id: string) => params.push(id));

      const updateResult = await this.rdbStore.executeSql(updateSql, params);

      await this.deleteSortEntriesInternal('today_list_sort_config', activityIds);
      await this.deleteSortEntriesInternal('idea_pool_sort_config', activityIds);

      // 提交事务
      await this.rdbStore.commit();

      hilog.info(0x0000, TAG, `成功将 ${activityIds.length} 个事项归档为ARCHIVED状态`);
      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `批量归档事项失败: ${err.message}`);

      // 回滚事务
      try {
        if (this.rdbStore) {
          await this.rdbStore.rollBack();
          hilog.info(0x0000, TAG, '事务已回滚');
        }
      } catch (rollbackErr) {
        const rollbackError = rollbackErr as BusinessError;
        hilog.error(0x0000, TAG, `事务回滚失败: ${rollbackError.message}`);
      }

      return false;
    }
  }

  /**
   * 将非今天的事项归档为ARCHIVED状态
   * @returns 是否成功归档
   */
  async archiveNonTodayActivities(): Promise<boolean> {
    try {
      hilog.info(0x0000, TAG, '开始归档非今天的事项...');

      // 查询所有非今天的事项
      const nonTodayActivities = await this.queryNonTodayActivities();

      if (nonTodayActivities.length === 0) {
        hilog.info(0x0000, TAG, '没有需要归档的非今天事项');
        return true;
      }

      hilog.info(0x0000, TAG, `找到 ${nonTodayActivities.length} 个需要归档的非今天事项`);

      // 提取所有事项ID
      const activityIds = nonTodayActivities.map(activity => activity.id);

      // 批量更新事项状态为ARCHIVED
      const success = await this.batchArchiveActivities(activityIds);

      if (success) {
        hilog.info(0x0000, TAG, `成功归档 ${nonTodayActivities.length} 个非今天事项`);
      } else {
        hilog.error(0x0000, TAG, '归档非今天事项失败');
      }

      return success;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(0x0000, TAG, `归档非今天事项时发生错误: ${err.message}`);
      return false;
    }
  }

  async queryCalendarDaySummaries(startMs: number, endMs: number): Promise<CalendarDaySummaryRow[]> {
    if (startMs >= endMs) {
      return [];
    }

    await this.initRDB();
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_TIME_RECORDS_IN_RANGE_SQL, [startMs, endMs]);
      const aggregates: Map<number, AggregateEntry> = new Map();

      if (resultSet.goToFirstRow()) {
        const startIndex = resultSet.getColumnIndex('start_time');
        const endIndex = resultSet.getColumnIndex('end_time');
        const durationIndex = resultSet.getColumnIndex('duration_milliseconds');

        do {
          const startTimeMs = resultSet.getLong(startIndex);
          const bucketStart = TimeRecordUtil.getDayStart(startTimeMs);

          let durationMs: number | undefined = undefined;
          if (durationIndex >= 0 && !resultSet.isColumnNull(durationIndex)) {
            durationMs = resultSet.getLong(durationIndex);
          }

          if (durationMs === undefined && endIndex >= 0 && !resultSet.isColumnNull(endIndex)) {
            const endTimeMs = resultSet.getLong(endIndex);
            durationMs = Math.max(0, endTimeMs - startTimeMs);
          }

          if (durationMs === undefined) {
            durationMs = 0;
          }

          let aggregateEntry: AggregateEntry | undefined = aggregates.get(bucketStart);
          if (!aggregateEntry) {
            const newEntry: AggregateEntry = { totalDurationMs: 0, recordCount: 0 };
            aggregates.set(bucketStart, newEntry);
            aggregateEntry = newEntry;
          }
          aggregateEntry.totalDurationMs += durationMs;
          aggregateEntry.recordCount += 1;
        } while (resultSet.goToNextRow());
      }

      const rows: CalendarDaySummaryRow[] = [];
      const iterator = aggregates.entries();
      let nextValue = iterator.next();
      while (!nextValue.done) {
        const mapEntry = nextValue.value;
        const dayStartMs = mapEntry[0];
        const aggregateEntry = mapEntry[1];
        const summaryRow: CalendarDaySummaryRow = {
          dayStartMs,
          totalDurationMs: aggregateEntry.totalDurationMs,
          recordCount: aggregateEntry.recordCount
        };
        rows.push(summaryRow);
        nextValue = iterator.next();
      }
      rows.sort((rowA: CalendarDaySummaryRow, rowB: CalendarDaySummaryRow) => rowA.dayStartMs - rowB.dayStartMs);
      return rows;
    } finally {
      if (resultSet) {
        resultSet.close();
      }
    }
  }

  /**
   * Blueprint scope: returns raw time records with activity and tag metadata for review analytics.
   *
   * The eventual implementation should rely on a windowed query joining `time_record`, `activity`,
   * and `tag`, clamping open-ended records with the caller's range and `Date.now()` to guarantee
   * deterministic durations for aggregation.
   */
  async queryTimeRecordsWithActivityAndTag(startMs: number, endMs: number): Promise<TimeRecordWithContext[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    hilog.debug(0x0000, TAG, `Querying time records with context for range: [${startMs}, ${endMs}]`);

    try {
      const sql = RDBSQL.QUERY_TIME_RECORDS_WITH_CONTEXT_SQL;
      const resultSet = await this.rdbStore.querySql(sql, [startMs, endMs]);

      const records: TimeRecordWithContext[] = [];

      if (resultSet.goToFirstRow()) {
        do {
          const record: TimeRecordWithContext = {
            recordId: resultSet.getString(resultSet.getColumnIndex('record_id')),
            activityId: resultSet.getString(resultSet.getColumnIndex('activity_id')),
            activityName: resultSet.getString(resultSet.getColumnIndex('activity_name')),
            startTimeMs: resultSet.getLong(resultSet.getColumnIndex('start_time')),
            endTimeMs: resultSet.isColumnNull(resultSet.getColumnIndex('end_time'))
              ? null
              : resultSet.getLong(resultSet.getColumnIndex('end_time')),
            durationMs: resultSet.isColumnNull(resultSet.getColumnIndex('duration_milliseconds'))
              ? null
              : resultSet.getLong(resultSet.getColumnIndex('duration_milliseconds')),
            tagId: resultSet.isColumnNull(resultSet.getColumnIndex('tag_id'))
              ? null
              : resultSet.getString(resultSet.getColumnIndex('tag_id')),
            tagName: resultSet.isColumnNull(resultSet.getColumnIndex('tag_name'))
              ? null
              : resultSet.getString(resultSet.getColumnIndex('tag_name')),
            tagColorHex: resultSet.isColumnNull(resultSet.getColumnIndex('tag_color_hex'))
              ? null
              : resultSet.getString(resultSet.getColumnIndex('tag_color_hex')),
            tagLightColorHex: resultSet.isColumnNull(resultSet.getColumnIndex('tag_light_color_hex'))
              ? null
              : resultSet.getString(resultSet.getColumnIndex('tag_light_color_hex'))
          };
          records.push(record);
        } while (resultSet.goToNextRow());
      }

      resultSet.close();
      hilog.debug(0x0000, TAG, `Found ${records.length} time records with context`);
      return records;
    } catch (error) {
      hilog.error(0x0000, TAG, `Error querying time records with context: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /**
   * Blueprint scope: groups record durations by local day and tag to feed calendar / weekly charts.
   *
   * Actual implementation should materialize results via SQL (CTEs recommended) that respect
   * cross-midnight splits performed in the service layer and reuse the same clamping rules
   * described above. The returned rows should be ordered by date ascending for deterministic merges.
   */
  async queryAggregatedDurationsByDay(startMs: number, endMs: number): Promise<DayAggregation[]> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    hilog.info(0x0000, TAG, `queryAggregatedDurationsByDay stub range: [${startMs}, ${endMs})`);
    return [];
  }

  /**
   * Blueprint scope: discovers the earliest and latest record timestamps to constrain navigation.
   *
   * A dedicated SQL view should compute MIN(start_time) and MAX(COALESCE(end_time, start_time)) to
   * capture both completed and in-flight records. `latestRecordMs` must never exceed `Date.now()`.
   */
  async queryFocusDateBounds(): Promise<FocusDateBoundsRow> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    const now = Date.now();
    const resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_FOCUS_DATE_BOUNDS_SQL);

    let earliestRecordMs: number | null = null;
    let latestRecordMs: number | null = null;

    if (resultSet.goToFirstRow()) {
      const earliestIndex = resultSet.getColumnIndex('earliest_record_ms');
      const latestIndex = resultSet.getColumnIndex('latest_record_ms');
      if (earliestIndex >= 0 && !resultSet.isColumnNull(earliestIndex)) {
        earliestRecordMs = resultSet.getLong(earliestIndex);
      }
      if (latestIndex >= 0 && !resultSet.isColumnNull(latestIndex)) {
        latestRecordMs = resultSet.getLong(latestIndex);
      }
    }

    resultSet.close();

    let resolvedLatest = latestRecordMs ?? now;
    if (resolvedLatest > now) {
      resolvedLatest = now;
    }

    hilog.info(0x0000, TAG,
      `queryFocusDateBounds resolved earliest=${earliestRecordMs ?? -1} latest=${resolvedLatest}`);
    return { earliestRecordMs, latestRecordMs: resolvedLatest };
  }

  async queryLatestTimeRecordStartBefore(cutoffMs: number): Promise<number | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    const resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_LATEST_TIME_RECORD_START_BEFORE_SQL, [cutoffMs]);
    let value: number | null = null;
    if (resultSet.goToFirstRow()) {
      const index = resultSet.getColumnIndex('record_ts');
      if (index >= 0 && !resultSet.isColumnNull(index)) {
        value = resultSet.getLong(index);
      }
    }
    resultSet.close();
    return value;
  }

  async queryEarliestTimeRecordStartAfter(cutoffMs: number): Promise<number | null> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }
    const resultSet = await this.rdbStore.querySql(RDBSQL.QUERY_EARLIEST_TIME_RECORD_START_AFTER_SQL, [cutoffMs]);
    let value: number | null = null;
    if (resultSet.goToFirstRow()) {
      const index = resultSet.getColumnIndex('record_ts');
      if (index >= 0 && !resultSet.isColumnNull(index)) {
        value = resultSet.getLong(index);
      }
    }
    resultSet.close();
    return value;
  }

  /**
   * Blueprint scope: batch loads palette metadata for all tag ids referenced in review summaries.
   *
   * Implementation should SELECT name/color/light_color from `tag` using an IN clause with fallback
   * defaults where tags have been deleted. Service callers will merge these entries with aggregation
   * outputs to retain consistent coloring across modules.
   */
  async queryTagPalette(tagIds: string[]): Promise<TagPaletteMap> {
    if (!this.rdbStore) {
      throw new Error('RDB store is not initialized');
    }

    hilog.info(0x0000, TAG, `queryTagPalette stub for ${tagIds.length} tag ids`);
    return {};
  }
}

// 导出类，而不是实例
export default RDBStoreUtil;
