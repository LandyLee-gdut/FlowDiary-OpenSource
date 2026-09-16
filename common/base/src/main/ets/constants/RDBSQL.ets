/**
 * SQL constants for RDB store operations.
 */
export class RDBSQL {
  /**
   * The sql to enable foreign key constraints.
   */
  static readonly ENABLE_FOREIGN_KEYS_SQL: string = 'PRAGMA foreign_keys = ON;';

  // --- Table: tag ---

  /**
   * The sql of creating the tag table.
   */
  static readonly CREATE_TAG_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS tag (' +
      'id TEXT PRIMARY KEY, ' +
      'name TEXT NOT NULL UNIQUE, ' +
      'color TEXT NOT NULL, ' +          // 主色 (用于文字)
      'light_color TEXT NOT NULL, ' +    // 背景色
      'created_at INTEGER NOT NULL, ' +
      'updated_at INTEGER NOT NULL' +
      ');';

  // --- Table: activity ---

  /**
   * The sql of creating the activity table.
   */
  static readonly CREATE_ACTIVITY_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS activity (' +
    'id TEXT PRIMARY KEY, ' +
    'name TEXT NOT NULL, ' +
    'tag_id TEXT, ' +
    'status INTEGER NOT NULL, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (tag_id) REFERENCES tag(id) ON DELETE SET NULL' +
    ');';

  /**
   * The sql of creating an index on the status column of the activity table.
   */
  static readonly CREATE_INDEX_ON_ACTIVITY_STATUS_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_activity_status ON activity(status);';

  /**
   * The sql of creating an index on the tag_id column of the activity table.
   */
  static readonly CREATE_INDEX_ON_ACTIVITY_TAG_ID_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_activity_tag_id ON activity(tag_id);';

  // --- Table: time_record ---

  /**
   * The sql of creating the time_record table.
   */
  static readonly CREATE_TIME_RECORD_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS time_record (' +
    'id TEXT PRIMARY KEY, ' +
    'activity_id TEXT NOT NULL, ' +
    'start_time INTEGER NOT NULL, ' +
    'end_time INTEGER, ' +
    'duration_milliseconds INTEGER, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (activity_id) REFERENCES activity(id) ON DELETE CASCADE' +
    ');';

  static readonly MIGRATE_TIME_RECORD_ADD_CREATED_AT_SQL: string =
    'ALTER TABLE time_record ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;';

  static readonly MIGRATE_TIME_RECORD_ADD_UPDATED_AT_SQL: string =
    'ALTER TABLE time_record ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;';

  static readonly MIGRATE_TIME_RECORD_BACKFILL_CREATED_AT_SQL: string =
    'UPDATE time_record SET created_at = start_time WHERE created_at = 0;';

  static readonly MIGRATE_TIME_RECORD_BACKFILL_UPDATED_AT_SQL: string =
    'UPDATE time_record SET updated_at = COALESCE(end_time, start_time) WHERE updated_at = 0;';

  /**
   * The sql of creating an index on the activity_id column of the time_record table.
   */
  static readonly CREATE_INDEX_ON_TIME_RECORD_ACTIVITY_ID_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_time_record_activity_id ON time_record(activity_id);';

  /**
   * The sql of creating an index on the start_time column of the time_record table.
   */
  static readonly CREATE_INDEX_ON_TIME_RECORD_START_TIME_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_time_record_start_time ON time_record(start_time);';

  // --- Table: time_record_calendar_map (local-only) ---

  static readonly CREATE_TIME_RECORD_CALENDAR_MAP_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS time_record_calendar_map (' +
    'time_record_id TEXT PRIMARY KEY, ' +
    'calendar_id INTEGER NOT NULL DEFAULT 0, ' +
    'calendar_event_id INTEGER, ' +
    'sync_status INTEGER NOT NULL DEFAULT 0, ' +
    'pending_action INTEGER NOT NULL DEFAULT 0, ' +
    'last_error_code INTEGER, ' +
    'last_synced_at INTEGER, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (time_record_id) REFERENCES time_record(id) ON DELETE CASCADE' +
    ');';

  static readonly CREATE_INDEX_ON_TIME_RECORD_CALENDAR_MAP_SYNC_STATUS_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_tr_calendar_map_sync_status ON time_record_calendar_map(sync_status);';

  static readonly CREATE_INDEX_ON_TIME_RECORD_CALENDAR_MAP_EVENT_ID_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_tr_calendar_map_event_id ON time_record_calendar_map(calendar_event_id);';

  static readonly MIGRATE_TIME_RECORD_CALENDAR_MAP_ADD_PENDING_ACTION_SQL: string =
    'ALTER TABLE time_record_calendar_map ADD COLUMN pending_action INTEGER NOT NULL DEFAULT 0;';

  static readonly MIGRATE_TIME_RECORD_CALENDAR_MAP_ADD_LAST_ERROR_CODE_SQL: string =
    'ALTER TABLE time_record_calendar_map ADD COLUMN last_error_code INTEGER;';

  static readonly MIGRATE_TIME_RECORD_CALENDAR_MAP_ADD_LAST_SYNCED_AT_SQL: string =
    'ALTER TABLE time_record_calendar_map ADD COLUMN last_synced_at INTEGER;';

  // --- Table: activity_diary (Immersive Flow Card V1.2) ---

  static readonly CREATE_ACTIVITY_DIARY_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS activity_diary (' +
    'id TEXT PRIMARY KEY, ' +
    'activity_id TEXT NOT NULL UNIQUE, ' +
    'text TEXT NOT NULL DEFAULT \'\', ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (activity_id) REFERENCES activity(id) ON DELETE CASCADE' +
    ');';

  // --- Table: activity_media (Immersive Flow Card V1.2) ---

  static readonly CREATE_ACTIVITY_MEDIA_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS activity_media (' +
    'id TEXT PRIMARY KEY, ' +
    'activity_id TEXT NOT NULL, ' +
    'local_path TEXT NOT NULL, ' + // store relPath under filesDir (never store picker URI)
    'content_hash TEXT, ' +
    'mime_type TEXT NOT NULL, ' +
    'width INTEGER NOT NULL DEFAULT 0, ' +
    'height INTEGER NOT NULL DEFAULT 0, ' +
    'byte_size INTEGER NOT NULL DEFAULT 0, ' +
    'display_order INTEGER NOT NULL DEFAULT 0, ' +
    'is_cover INTEGER NOT NULL DEFAULT 1, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (activity_id) REFERENCES activity(id) ON DELETE CASCADE' +
    ');';

  static readonly CREATE_INDEX_ON_ACTIVITY_DIARY_ACTIVITY_ID_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_activity_diary_activity_id ON activity_diary(activity_id);';

  static readonly CREATE_INDEX_ON_ACTIVITY_MEDIA_ACTIVITY_ID_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_activity_media_activity_id ON activity_media(activity_id);';

  static readonly CREATE_INDEX_ON_ACTIVITY_MEDIA_CONTENT_HASH_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_activity_media_content_hash ON activity_media(content_hash);';

  static readonly MIGRATE_ACTIVITY_MEDIA_ADD_CONTENT_HASH_SQL: string =
    'ALTER TABLE activity_media ADD COLUMN content_hash TEXT;';

  // --- Table: idea_pool_sort_config ---

  /**
   * The sql of creating the idea_pool_sort_config table.
   */
  static readonly CREATE_IDEA_POOL_SORT_CONFIG_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS idea_pool_sort_config (' +
    'activity_id TEXT PRIMARY KEY, ' +
    'display_order INTEGER NOT NULL, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (activity_id) REFERENCES activity(id) ON DELETE CASCADE' +
    ');';

  static readonly MIGRATE_IDEA_POOL_SORT_CONFIG_ADD_CREATED_AT_SQL: string =
    'ALTER TABLE idea_pool_sort_config ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;';

  static readonly MIGRATE_IDEA_POOL_SORT_CONFIG_ADD_UPDATED_AT_SQL: string =
    'ALTER TABLE idea_pool_sort_config ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;';

  static readonly MIGRATE_IDEA_POOL_SORT_CONFIG_BACKFILL_CREATED_AT_SQL: string =
    'UPDATE idea_pool_sort_config ' +
    'SET created_at = COALESCE((SELECT created_at FROM activity WHERE activity.id = idea_pool_sort_config.activity_id), 0) ' +
    'WHERE created_at = 0;';

  static readonly MIGRATE_IDEA_POOL_SORT_CONFIG_BACKFILL_UPDATED_AT_SQL: string =
    'UPDATE idea_pool_sort_config ' +
    'SET updated_at = COALESCE((SELECT updated_at FROM activity WHERE activity.id = idea_pool_sort_config.activity_id), 0) ' +
    'WHERE updated_at = 0;';

  /**
   * The sql of creating an index on the display_order column of the idea_pool_sort_config table.
   */
  static readonly CREATE_INDEX_ON_IDEA_POOL_SORT_ORDER_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_idea_pool_sort_order ON idea_pool_sort_config(display_order);';

  // --- Table: today_list_sort_config ---

  /**
   * The sql of creating the today_list_sort_config table.
   */
  static readonly CREATE_TODAY_LIST_SORT_CONFIG_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS today_list_sort_config (' +
    'activity_id TEXT PRIMARY KEY, ' +
    'display_order INTEGER NOT NULL, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (activity_id) REFERENCES activity(id) ON DELETE CASCADE' +
    ');';

  static readonly MIGRATE_TODAY_LIST_SORT_CONFIG_ADD_CREATED_AT_SQL: string =
    'ALTER TABLE today_list_sort_config ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;';

  static readonly MIGRATE_TODAY_LIST_SORT_CONFIG_ADD_UPDATED_AT_SQL: string =
    'ALTER TABLE today_list_sort_config ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;';

  static readonly MIGRATE_TODAY_LIST_SORT_CONFIG_BACKFILL_CREATED_AT_SQL: string =
    'UPDATE today_list_sort_config ' +
    'SET created_at = COALESCE((SELECT created_at FROM activity WHERE activity.id = today_list_sort_config.activity_id), 0) ' +
    'WHERE created_at = 0;';

  static readonly MIGRATE_TODAY_LIST_SORT_CONFIG_BACKFILL_UPDATED_AT_SQL: string =
    'UPDATE today_list_sort_config ' +
    'SET updated_at = COALESCE((SELECT updated_at FROM activity WHERE activity.id = today_list_sort_config.activity_id), 0) ' +
    'WHERE updated_at = 0;';

  /**
   * The sql of creating an index on the display_order column of the today_list_sort_config table.
   */
  static readonly CREATE_INDEX_ON_TODAY_LIST_SORT_ORDER_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_today_list_sort_order ON today_list_sort_config(display_order);';

  // --- Queries: Immersive Flow Card (diary/media) ---

  static readonly QUERY_ACTIVITY_COVER_MEDIA_BY_ACTIVITY_ID_SQL: string =
    'SELECT local_path ' +
    'FROM activity_media ' +
    'WHERE activity_id = ? AND is_cover = 1 ' +
    'ORDER BY updated_at DESC ' +
    'LIMIT 1;';

  static readonly QUERY_ACTIVITY_DIARY_SQL: string =
    'SELECT text ' +
    'FROM activity_diary ' +
    'WHERE activity_id = ? ' +
    'LIMIT 1;';

  static readonly QUERY_ACTIVITY_MEDIA_PATHS_BY_ACTIVITY_ID_SQL: string =
    'SELECT local_path ' +
    'FROM activity_media ' +
    'WHERE activity_id = ?;';

  static readonly QUERY_ACTIVITY_MEDIA_PATH_BY_HASH_SQL: string =
    'SELECT local_path ' +
    'FROM activity_media ' +
    'WHERE content_hash = ? ' +
    'ORDER BY updated_at DESC ' +
    'LIMIT 1;';

  static readonly QUERY_ACTIVITY_MEDIA_REFCOUNT_BY_PATH_SQL: string =
    'SELECT COUNT(1) AS ref_count ' +
    'FROM activity_media ' +
    'WHERE local_path = ?;';

  // --- Table: frequent_item_config ---

  /**
   * The sql of creating the frequent_item_config table.
   */
  static readonly CREATE_FREQUENT_ITEM_CONFIG_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS frequent_item_config (' +
    'activity_id TEXT PRIMARY KEY, ' +
    'display_order INTEGER NOT NULL, ' +
    'FOREIGN KEY (activity_id) REFERENCES activity(id) ON DELETE CASCADE' +
    ');';

  /**
   * The sql of creating an index on the display_order column of the frequent_item_config table.
   */
  static readonly CREATE_INDEX_ON_FREQUENT_ITEM_SORT_ORDER_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_frequent_item_sort_order ON frequent_item_config(display_order);';

  // --- Table: idea_collection ---

  static readonly CREATE_IDEA_COLLECTION_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS idea_collection (' +
    'id TEXT PRIMARY KEY, ' +
    'name TEXT NOT NULL, ' +
    'icon TEXT, ' +
    'tag_id TEXT, ' +
    'cover_style TEXT, ' +
    'summary_text TEXT, ' +
    'display_order INTEGER NOT NULL DEFAULT 0, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (tag_id) REFERENCES tag(id) ON DELETE SET NULL' +
    ');';

  static readonly CREATE_INDEX_ON_IDEA_COLLECTION_TAG_ID_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_idea_collection_tag_id ON idea_collection(tag_id);';

  // --- Table: idea_collection_item ---

  static readonly CREATE_IDEA_COLLECTION_ITEM_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS idea_collection_item (' +
    'id TEXT PRIMARY KEY, ' +
    'collection_id TEXT NOT NULL, ' +
    'activity_id TEXT NOT NULL, ' +
    'display_order INTEGER NOT NULL DEFAULT 0, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (collection_id) REFERENCES idea_collection(id) ON DELETE CASCADE, ' +
    'FOREIGN KEY (activity_id) REFERENCES activity(id) ON DELETE CASCADE' +
    ');';

  static readonly CREATE_INDEX_ON_IDEA_COLLECTION_ITEM_COLLECTION_ID_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_idea_collection_item_collection_id ON idea_collection_item(collection_id);';

  // Unique index to enforce one collection per idea
  static readonly CREATE_UNIQUE_INDEX_ON_IDEA_COLLECTION_ITEM_ACTIVITY_ID_SQL: string =
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_idea_collection_item_activity_id ON idea_collection_item(activity_id);';

  // --- Table: idea_category ---

  static readonly CREATE_IDEA_CATEGORY_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS idea_category (' +
    'id TEXT PRIMARY KEY, ' +
    'name TEXT NOT NULL, ' +
    'color TEXT NOT NULL, ' +
    'light_color TEXT NOT NULL, ' +
    'icon TEXT, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL' +
    ');';

  // --- Table: idea_category_item ---

  static readonly CREATE_IDEA_CATEGORY_ITEM_TABLE_SQL: string =
    'CREATE TABLE IF NOT EXISTS idea_category_item (' +
    'id TEXT PRIMARY KEY, ' +
    'category_id TEXT NOT NULL, ' +
    'activity_id TEXT NOT NULL, ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL, ' +
    'FOREIGN KEY (category_id) REFERENCES idea_category(id) ON DELETE CASCADE, ' +
    'FOREIGN KEY (activity_id) REFERENCES activity(id) ON DELETE CASCADE' +
    ');';

  static readonly CREATE_INDEX_ON_IDEA_CATEGORY_ITEM_CATEGORY_ID_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_idea_category_item_category_id ON idea_category_item(category_id);';

  // Unique index to enforce one category per idea
  static readonly CREATE_UNIQUE_INDEX_ON_IDEA_CATEGORY_ITEM_ACTIVITY_ID_SQL: string =
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_idea_category_item_activity_id ON idea_category_item(activity_id);';

  // --- Activity Table Migrations (IdeaPool Light Collections) ---

  static readonly MIGRATE_ACTIVITY_ADD_IDEA_TYPE_SQL: string =
    'ALTER TABLE activity ADD COLUMN idea_type INTEGER NOT NULL DEFAULT 0;';

  static readonly MIGRATE_ACTIVITY_ADD_IDEA_LIGHT_STATE_SQL: string =
    'ALTER TABLE activity ADD COLUMN idea_light_state INTEGER NOT NULL DEFAULT 0;';

  static readonly MIGRATE_ACTIVITY_ADD_IDEA_LIGHT_COUNT_SQL: string =
    'ALTER TABLE activity ADD COLUMN idea_light_count INTEGER NOT NULL DEFAULT 0;';

  static readonly CREATE_INDEX_ON_ACTIVITY_IDEA_TYPE_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_activity_idea_type ON activity(idea_type);';

  static readonly CREATE_INDEX_ON_ACTIVITY_IDEA_LIGHT_STATE_SQL: string =
    'CREATE INDEX IF NOT EXISTS idx_activity_idea_light_state ON activity(idea_light_state);';

  // Backfill: status=3 (IDEA_POOL) -> idea_type=1 (IDEA_POOL)
  static readonly MIGRATE_ACTIVITY_BACKFILL_IDEA_TYPE_IDEA_POOL_SQL: string =
    'UPDATE activity SET idea_type = 1 WHERE status = 3;';

  // Backfill: all others (status != 3) -> idea_type=2 (TODAY_ONLY)
  // Note: DEFAULT is 0, so we update where default persists or explicitly all non-3
  static readonly MIGRATE_ACTIVITY_BACKFILL_IDEA_TYPE_TODAY_ONLY_SQL: string =
    'UPDATE activity SET idea_type = 2 WHERE idea_type = 0;';

  // (在 RDBSQL 类的内部)

  /**
   * The sql to query all activities for the "Today List".
   * It joins activity, tag, and sorting tables to get all necessary display information,
   * ordered by the user-defined display order.
   * We use LEFT JOIN for the tag to ensure activities without a tag are also included.
   * 
   * CARRY-OVER LOGIC:
   * - TODO (status=0) items persist across days - they will always show up until completed
   * - RECORDING (status=1) and PAUSED (status=2) items require either:
   *   a) Creation date is today OR
   *   b) Has time records associated with today
   */
  static readonly QUERY_TODAY_ACTIVITIES_SQL: string =
    'SELECT ' +
      '  a.id, ' +
      '  a.name, ' +
      '  a.status, ' +
      '  t.name AS tag_name, ' +
      '  t.color AS tag_color_hex, ' +
      '  COALESCE(s.display_order, 999999) AS display_order ' +
      'FROM ' +
      '  activity AS a ' +
      'LEFT JOIN ' +
      '  today_list_sort_config AS s ON a.id = s.activity_id ' +
      'LEFT JOIN ' +
      '  tag AS t ON a.tag_id = t.id ' +
      'WHERE ' +
      '  a.status IN (0, 1, 2) ' + // status = 0,1,2 means TODO, RECORDING, PAUSED (not ARCHIVED)
      '  AND ( ' +
      '    a.status = 0 OR ' + // TODO items always appear (carry-over across days)
      '    a.created_at >= ? OR ' + // Created today
      '    EXISTS ( ' + // Or has time records from today
      '      SELECT 1 FROM time_record AS tr ' +
      '      WHERE tr.activity_id = a.id ' +
      '        AND ( ' +
      '          tr.start_time >= ? OR ' +
      '          (tr.end_time IS NOT NULL AND tr.end_time > ?) OR ' +
      '          (tr.end_time IS NULL AND tr.start_time < ?) ' +
      '        ) ' +
      '    ) ' +
      '  ) ' +
      'ORDER BY ' +
      '  a.updated_at DESC, ' +
      '  display_order ASC, ' +
      '  a.id ASC;';

  /**
   * The sql to query all Idea Pool activities with tag metadata and sort order.
   */
  static readonly QUERY_IDEA_POOL_ACTIVITIES_SQL: string =
    'SELECT ' +
      '  a.id, ' +
      '  a.name, ' +
      '  a.status, ' +
      '  a.idea_type, ' +
      '  a.idea_light_state, ' +
      '  a.idea_light_count, ' +
      '  a.tag_id, ' +
      '  a.created_at, ' +
      '  a.updated_at, ' +
      '  t.name AS tag_name, ' +
      '  t.color AS tag_color_hex, ' +
      '  t.light_color AS tag_light_color_hex, ' +
      '  COALESCE(s.display_order, 999999) AS display_order ' +
    'FROM ' +
      '  activity AS a ' +
    'LEFT JOIN ' +
      '  idea_pool_sort_config AS s ON a.id = s.activity_id ' +
    'LEFT JOIN ' +
      '  tag AS t ON a.tag_id = t.id ' +
    'WHERE ' +
      '  a.idea_type = 1 ' +
    'ORDER BY ' +
      '  display_order ASC, ' +
      '  a.created_at ASC;';

  /**
   * The sql to query Idea Collections with tag colors for UI rendering.
   */
  static readonly QUERY_IDEA_COLLECTIONS_SQL: string =
    'SELECT ' +
      '  c.id, ' +
      '  c.name, ' +
      '  c.icon, ' +
      '  c.tag_id, ' +
      '  c.cover_style, ' +
      '  c.summary_text, ' +
      '  c.display_order, ' +
      '  c.created_at, ' +
      '  c.updated_at, ' +
      '  t.name AS tag_name, ' +
      '  t.color AS tag_color_hex, ' +
      '  t.light_color AS tag_light_color_hex ' +
    'FROM ' +
      '  idea_collection AS c ' +
    'LEFT JOIN ' +
      '  tag AS t ON c.tag_id = t.id ' +
    'ORDER BY ' +
      '  c.display_order ASC, ' +
      '  c.created_at ASC;';

  /**
   * The sql to query Idea Categories.
   */
  static readonly QUERY_IDEA_CATEGORIES_SQL: string =
    'SELECT ' +
      '  id, ' +
      '  name, ' +
      '  color, ' +
      '  light_color, ' +
      '  icon, ' +
      '  created_at, ' +
      '  updated_at ' +
    'FROM ' +
      '  idea_category ' +
    'ORDER BY ' +
      '  created_at ASC;';

  /**
   * The sql to aggregate Idea Collection light counts.
   */
  static readonly QUERY_IDEA_COLLECTION_LIGHT_COUNTS_SQL: string =
    'SELECT ' +
      '  i.collection_id AS collection_id, ' +
      '  COUNT(i.activity_id) AS total_count, ' +
      '  SUM(CASE WHEN a.idea_light_state = 1 THEN 1 ELSE 0 END) AS lit_count, ' +
      '  SUM(CASE WHEN a.idea_light_state = 0 THEN 1 ELSE 0 END) AS unlit_count ' +
    'FROM ' +
      '  idea_collection_item AS i ' +
    'JOIN ' +
      '  activity AS a ON a.id = i.activity_id ' +
    'WHERE ' +
      '  a.idea_type = 1 ' +
    'GROUP BY ' +
      '  i.collection_id;';

  /**
   * The sql to query Idea Pool activities within a specific collection (ordered by collection item order).
   */
  static readonly QUERY_IDEA_COLLECTION_ACTIVITIES_SQL: string =
    'SELECT ' +
      '  a.id, ' +
      '  a.name, ' +
      '  a.status, ' +
      '  a.idea_type, ' +
      '  a.idea_light_state, ' +
      '  a.idea_light_count, ' +
      '  a.tag_id, ' +
      '  a.created_at, ' +
      '  a.updated_at, ' +
      '  t.name AS tag_name, ' +
      '  t.color AS tag_color_hex, ' +
      '  t.light_color AS tag_light_color_hex, ' +
      '  COALESCE(i.display_order, 999999) AS display_order ' +
    'FROM ' +
      '  idea_collection_item AS i ' +
    'JOIN ' +
      '  activity AS a ON a.id = i.activity_id ' +
    'LEFT JOIN ' +
      '  tag AS t ON a.tag_id = t.id ' +
    'WHERE ' +
      '  a.idea_type = 1 AND i.collection_id = ? ' +
    'ORDER BY ' +
      '  display_order ASC, ' +
      '  a.created_at ASC;';

  /**
   * The sql to query the collection id of a specific idea activity.
   */
  static readonly QUERY_IDEA_COLLECTION_ID_BY_ACTIVITY_SQL: string =
    'SELECT collection_id FROM idea_collection_item WHERE activity_id = ? LIMIT 1;';

  /**
   * The sql to aggregate Idea Category light counts.
   */
  static readonly QUERY_IDEA_CATEGORY_LIGHT_COUNTS_SQL: string =
    'SELECT ' +
      '  i.category_id AS category_id, ' +
      '  COUNT(i.activity_id) AS total_count, ' +
      '  SUM(CASE WHEN a.idea_light_state = 1 THEN 1 ELSE 0 END) AS lit_count, ' +
      '  SUM(CASE WHEN a.idea_light_state = 0 THEN 1 ELSE 0 END) AS unlit_count ' +
    'FROM ' +
      '  idea_category_item AS i ' +
    'JOIN ' +
      '  activity AS a ON a.id = i.activity_id ' +
    'WHERE ' +
      '  a.idea_type = 1 ' +
    'GROUP BY ' +
      '  i.category_id;';

  /**
   * The sql to aggregate global Idea Pool light counts.
   */
  static readonly QUERY_IDEA_POOL_LIGHT_COUNTS_SQL: string =
    'SELECT ' +
      '  COUNT(a.id) AS total_count, ' +
      '  SUM(CASE WHEN a.idea_light_state = 1 THEN 1 ELSE 0 END) AS lit_count, ' +
      '  SUM(CASE WHEN a.idea_light_state = 0 THEN 1 ELSE 0 END) AS unlit_count ' +
    'FROM ' +
      '  activity AS a ' +
    'WHERE ' +
      '  a.idea_type = 1;';

    /**
     * The sql to query all tags, ordered by creation time.
     */
    static readonly QUERY_ALL_TAGS_SQL: string =
      'SELECT ' +
        '  id, ' +
        '  name, ' +
        '  color, ' +
        '  light_color, ' +
        '  created_at, ' +
        '  updated_at ' +
        'FROM ' +
        '  tag ' +
        'ORDER BY ' +
        '  created_at ASC;';

  // --- INSERT SQL Statements ---
  /**
   * The sql to insert a new tag.
   */
  static readonly INSERT_TAG_SQL: string =
    'INSERT INTO tag (id, name, color, light_color, created_at, updated_at) ' +
      'VALUES (?, ?, ?, ?, ?, ?);';

  /**
   * The sql to insert a new activity.
   */
  static readonly INSERT_ACTIVITY_SQL: string =
    'INSERT INTO activity (id, name, tag_id, status, created_at, updated_at) ' +
      'VALUES (?, ?, ?, ?, ?, ?);';

  /**
   * The sql to insert into today_list_sort_config.
   */
  static readonly INSERT_TODAY_LIST_SORT_CONFIG_SQL: string =
    'INSERT INTO today_list_sort_config (activity_id, display_order) ' +
      'VALUES (?, ?);';

  /**
   * The sql to insert into idea_pool_sort_config.
   */
  static readonly INSERT_IDEA_POOL_SORT_CONFIG_SQL: string =
    'INSERT INTO idea_pool_sort_config (activity_id, display_order) ' +
      'VALUES (?, ?);';

  /**
   * The sql to query all time records for a specific activity.
   */
  static readonly QUERY_TIME_RECORDS_BY_ACTIVITY_ID_SQL: string =
    'SELECT ' +
      '  id, ' +
      '  activity_id, ' +
      '  start_time, ' +
      '  end_time, ' +
      '  duration_milliseconds ' +
    'FROM ' +
      '  time_record ' +
    'WHERE ' +
      '  activity_id = ? ' +
    'ORDER BY ' +
      '  start_time DESC;';

  /**
   * The sql to query open time records (end_time IS NULL or <= 0) for a specific activity.
   */
  static readonly QUERY_OPEN_TIME_RECORDS_BY_ACTIVITY_ID_SQL: string =
    'SELECT ' +
      '  id, ' +
      '  activity_id, ' +
      '  start_time, ' +
      '  end_time, ' +
      '  duration_milliseconds ' +
    'FROM ' +
      '  time_record ' +
    'WHERE ' +
      '  activity_id = ? ' +
      '  AND (end_time IS NULL OR end_time <= 0) ' +
    'ORDER BY ' +
      '  start_time DESC;';

  /**
   * The sql to query time records within a time range.
   */
  static readonly QUERY_TIME_RECORDS_IN_RANGE_SQL: string =
    'SELECT ' +
      '  start_time, ' +
      '  end_time, ' +
      '  duration_milliseconds ' +
    'FROM ' +
      '  time_record ' +
    'WHERE ' +
      '  start_time >= ? ' +
      '  AND start_time < ? ' +
    'ORDER BY start_time ASC;';

  /**
   * The sql to count tags.
   */
  static readonly COUNT_TAGS_SQL: string = 'SELECT COUNT(*) as count FROM tag';

  /**
   * The sql to query activity by ID.
   */
  static readonly QUERY_ACTIVITY_BY_ID_SQL: string =
    'SELECT ' +
    '  a.id, ' +
    '  a.name, ' +
    '  a.status, ' +
    '  t.name AS tag_name, ' +
    '  t.color AS tag_color_hex, ' +
    '  0 AS display_order ' + // 默认排序
    'FROM ' +
    '  activity AS a ' +
    'LEFT JOIN ' +
    '  tag AS t ON a.tag_id = t.id ' +
    'WHERE ' +
    '  a.id = ? ' +
    'LIMIT 1;';

  /**
   * The sql to build an Idea Pool activity summary with latest record timestamp.
   */
  static readonly QUERY_IDEA_SUMMARY_SQL: string =
    'SELECT ' +
      '  a.id, ' +
      '  a.name, ' +
      '  a.tag_id, ' +
      '  a.created_at, ' +
      '  a.updated_at, ' +
      '  t.name AS tag_name, ' +
      '  t.color AS tag_color_hex, ' +
      '  t.light_color AS tag_light_color_hex, ' +
      '  MAX(COALESCE(tr.end_time, tr.start_time)) AS latest_record_timestamp ' +
    'FROM ' +
      '  activity AS a ' +
    'LEFT JOIN ' +
      '  tag AS t ON a.tag_id = t.id ' +
    'LEFT JOIN ' +
      '  time_record AS tr ON tr.activity_id = a.id ' +
    'WHERE ' +
      '  a.id = ? ' +
    'GROUP BY ' +
      '  a.id;';

  /**
   * The sql to query all activities.
   */
  static readonly QUERY_ALL_ACTIVITIES_SQL: string =
    'SELECT ' +
    '  a.id, ' +
    '  a.name, ' +
    '  a.status, ' +
    '  t.name AS tag_name, ' +
    '  t.color AS tag_color_hex, ' +
    '  0 AS display_order ' + // 默认排序
    'FROM ' +
    '  activity AS a ' +
    'LEFT JOIN ' +
    '  tag AS t ON a.tag_id = t.id ' +
    'ORDER BY ' +
    '  a.created_at DESC;';

  /**
   * The sql to query activities by status.
   */
  static readonly QUERY_ACTIVITIES_BY_STATUS_SQL: string =
    'SELECT ' +
    '  a.id, ' +
    '  a.name, ' +
    '  a.status, ' +
    '  t.name AS tag_name, ' +
    '  t.color AS tag_color_hex, ' +
    '  COALESCE(s.display_order, 999999) AS display_order ' +
    'FROM ' +
    '  activity AS a ' +
    'LEFT JOIN ' +
    '  today_list_sort_config AS s ON a.id = s.activity_id ' +
    'LEFT JOIN ' +
    '  tag AS t ON a.tag_id = t.id ' +
    'WHERE ' +
    '  a.status = ? ' +
    'ORDER BY ' +
    '  display_order ASC;';

  /**
   * The sql to query tag by ID.
   */
  static readonly QUERY_TAG_BY_ID_SQL: string = 'SELECT id, name, color, light_color, created_at, updated_at FROM tag WHERE id = ?';

  /**
   * The sql to query today total duration for an activity.
   */
  static readonly QUERY_TODAY_TOTAL_DURATION_SQL: string =
    'SELECT COALESCE(SUM(duration_milliseconds), 0) as total_duration ' +
    'FROM time_record ' +
    'WHERE activity_id = ? AND start_time >= ?';

  /**
   * The sql to query all today total duration.
   */
  static readonly QUERY_ALL_TODAY_TOTAL_DURATION_SQL: string =
    'SELECT COALESCE(SUM(duration_milliseconds), 0) as total_duration ' +
    'FROM time_record ' +
    'WHERE start_time >= ?';

  /**
   * The sql to query latest time record for an activity.
   */
  static readonly QUERY_LATEST_TIME_RECORD_SQL: string =
    'SELECT id, activity_id, start_time, end_time, duration_milliseconds ' +
    'FROM time_record ' +
    'WHERE activity_id = ? AND end_time IS NULL ' +
    'ORDER BY start_time DESC ' +
    'LIMIT 1';

  /**
   * The sql to query earliest and latest record timestamps across all records.
   */
  static readonly QUERY_FOCUS_DATE_BOUNDS_SQL: string =
    'SELECT ' +
      'MIN(start_time) AS earliest_record_ms, ' +
      'MAX(COALESCE(end_time, start_time)) AS latest_record_ms ' +
    'FROM time_record';

  /**
   * The sql to query the latest record start time strictly before a cutoff.
   */
  static readonly QUERY_LATEST_TIME_RECORD_START_BEFORE_SQL: string =
    'SELECT MAX(start_time) AS record_ts ' +
    'FROM time_record ' +
    'WHERE start_time < ?';

  /**
   * The sql to query the earliest record start time strictly after a cutoff.
   */
  static readonly QUERY_EARLIEST_TIME_RECORD_START_AFTER_SQL: string =
    'SELECT MIN(start_time) AS record_ts ' +
    'FROM time_record ' +
    'WHERE start_time > ?';

  /**
   * The sql to query time record by ID.
   */
  static readonly QUERY_TIME_RECORD_BY_ID_SQL: string =
    'SELECT id, activity_id, start_time, end_time, duration_milliseconds ' +
    'FROM time_record ' +
    'WHERE id = ?';

  static readonly QUERY_TIME_RECORD_CALENDAR_MAP_BY_RECORD_ID_SQL: string =
    'SELECT ' +
    '  time_record_id, ' +
    '  calendar_id, ' +
    '  calendar_event_id, ' +
    '  sync_status, ' +
    '  pending_action, ' +
    '  last_error_code, ' +
    '  last_synced_at, ' +
    '  created_at, ' +
    '  updated_at ' +
    'FROM time_record_calendar_map ' +
    'WHERE time_record_id = ? ' +
    'LIMIT 1;';

  static readonly QUERY_TIME_RECORD_CALENDAR_MAP_BY_RECORD_IDS_SQL_PREFIX: string =
    'SELECT ' +
    '  time_record_id, ' +
    '  calendar_id, ' +
    '  calendar_event_id, ' +
    '  sync_status, ' +
    '  pending_action, ' +
    '  last_error_code, ' +
    '  last_synced_at, ' +
    '  created_at, ' +
    '  updated_at ' +
    'FROM time_record_calendar_map ' +
    'WHERE time_record_id IN ';

  static readonly QUERY_TIME_RECORD_CALENDAR_MAP_BY_SYNC_STATUS_SQL_PREFIX: string =
    'SELECT ' +
    '  time_record_id, ' +
    '  calendar_id, ' +
    '  calendar_event_id, ' +
    '  sync_status, ' +
    '  pending_action, ' +
    '  last_error_code, ' +
    '  last_synced_at, ' +
    '  created_at, ' +
    '  updated_at ' +
    'FROM time_record_calendar_map ' +
    'WHERE sync_status IN ';

  /**
   * The sql to query non-today activities.
   * 
   * IMPORTANT: Excludes TODO items (status=0) from auto-archive to support carry-over behavior.
   * TODO items should persist across days until marked as completed or manually archived.
   */
  static readonly QUERY_NON_TODAY_ACTIVITIES_SQL: string =
    'SELECT ' +
      '  a.id, ' +
      '  a.name, ' +
      '  a.status, ' +
    '  t.name AS tag_name, ' +
    '  t.color AS tag_color_hex, ' +
    '  0 AS display_order ' + // 默认排序
    'FROM ' +
    '  activity AS a ' +
    'LEFT JOIN ' +
    '  tag AS t ON a.tag_id = t.id ' +
    'WHERE ' +
    '  a.status IN (1, 2) ' + // Only RECORDING and PAUSED (exclude TODO=0 to allow carry-over)
    '  AND a.created_at < ? ' + // 只包含创建时间在今天之前的事项
    '  AND NOT EXISTS ( ' + // 如果今天仍有时间记录则不归档
    '    SELECT 1 FROM time_record AS tr ' +
    '    WHERE tr.activity_id = a.id ' +
    '      AND ( ' +
    '        tr.start_time >= ? OR ' +
    '        (tr.end_time IS NOT NULL AND tr.end_time > ?) OR ' +
    '        (tr.end_time IS NULL AND tr.start_time < ?) ' +
    '      ) ' +
      '  ) ' +
    'ORDER BY ' +
      '  a.created_at ASC;';

  static readonly QUERY_ARCHIVED_ACTIVITIES_WITH_TODAY_RECORDS_SQL: string =
    'SELECT DISTINCT a.id ' +
    'FROM activity AS a ' +
    'JOIN time_record AS tr ON tr.activity_id = a.id ' +
    'WHERE a.status = ? ' +
    '  AND ( ' +
    '    tr.start_time >= ? OR ' +
    '    (tr.end_time IS NOT NULL AND tr.end_time > ?) OR ' +
    '    (tr.end_time IS NULL AND tr.start_time < ?) ' +
    '  );';

  /**
   * The sql to get max display order for today list sort config.
   */
  static readonly QUERY_MAX_TODAY_LIST_ORDER_SQL: string = 'SELECT MAX(display_order) as max_order FROM today_list_sort_config';

  /**
   * The sql to get max display order for idea pool sort config.
   */
  static readonly QUERY_MAX_IDEA_POOL_ORDER_SQL: string = 'SELECT MAX(display_order) as max_order FROM idea_pool_sort_config';

  /**
   * The sql to fetch ordered idea pool sort config entries.
   */
  static readonly QUERY_IDEA_POOL_SORT_ENTRIES_SQL: string =
    'SELECT activity_id, display_order FROM idea_pool_sort_config ORDER BY display_order ASC;';

  /**
   * The sql to fetch ordered today list sort config entries.
   */
  static readonly QUERY_TODAY_LIST_SORT_ENTRIES_SQL: string =
    'SELECT activity_id, display_order FROM today_list_sort_config ORDER BY display_order ASC;';

  /**
   * The sql to batch archive activities.
   */
  static readonly BATCH_ARCHIVE_ACTIVITIES_SQL_PREFIX: string = 'UPDATE activity SET status = ';

  /**
   * The sql to migrate archived activities to the new ARCHIVED status value.
   */
  static readonly MIGRATE_ARCHIVED_STATUS_SQL: string =
    'UPDATE activity ' +
    '  SET status = 4 ' +
    'WHERE ' +
    '  status = 3 ' +
    '  AND id NOT IN (SELECT activity_id FROM idea_pool_sort_config);';

  /**
   * The sql to query tag_id by activity_id.
   */
  static readonly QUERY_TAG_ID_BY_ACTIVITY_ID_SQL: string = 'SELECT tag_id FROM activity WHERE id = ?';

  /**
   * The sql to update activity tag_id.
   */
  static readonly UPDATE_ACTIVITY_TAG_ID_SQL: string = 'UPDATE activity SET tag_id = ?, updated_at = ? WHERE id = ?';

  /**
   * The sql to update activity name and tag_id.
   */
  static readonly UPDATE_ACTIVITY_NAME_AND_TAG_ID_SQL: string = 'UPDATE activity SET name = ?, tag_id = ?, updated_at = ? WHERE id = ?';

  /**
   * The sql to query time records with activity and tag information for a date range.
   */
  static readonly QUERY_TIME_RECORDS_WITH_CONTEXT_SQL: string =
    'SELECT ' +
      'tr.id as record_id, ' +
      'tr.activity_id, ' +
      'a.name as activity_name, ' +
      'tr.start_time, ' +
      'tr.end_time, ' +
      'tr.duration_milliseconds, ' +
      't.id as tag_id, ' +
      't.name as tag_name, ' +
      't.color as tag_color_hex, ' +
      't.light_color as tag_light_color_hex ' +
    'FROM time_record tr ' +
      'LEFT JOIN activity a ON tr.activity_id = a.id ' +
      'LEFT JOIN tag t ON a.tag_id = t.id ' +
    'WHERE tr.start_time >= ? AND tr.start_time <= ? ' +
    'ORDER BY tr.start_time ASC';
}
