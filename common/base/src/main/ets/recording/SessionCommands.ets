import { OpenRecordInfo } from './RecordingSessionTypes';

/**
 * DB 命令接口（Phase 2 由 today 侧 TodaySessionCommands 实现，适配 TodayActivityService）。
 *
 * 错误约定：所有方法在 DB 失败时 throw，由 store 统一捕获并映射为 DB_ERROR；
 * 返回值不承载失败语义（queryOpenRecord 返回 null 仅表示"无未结束记录"）。
 */
export interface SessionCommands {
  /**
   * 开始一条新计时记录（app 启动时由 today 侧注册实现）。
   * 实现需复用 TodayActivityService 的幂等/事务/activity-lock 语义。
   * 成功返回未结束记录信息（recordId + DB 落库的 startTime）。
   */
  startSession(itemId: string): Promise<OpenRecordInfo>;

  /** 结束指定记录。DB 失败 throw；成功无返回值。 */
  stopSession(itemId: string, recordId: string): Promise<void>;

  /**
   * 查询指定 item 的未结束记录（adoptOpenRecord 用）。
   * 无未结束记录返回 null；DB 失败 throw。
   */
  queryOpenRecord(itemId: string): Promise<OpenRecordInfo | null>;

  /**
   * 全局查询最新一条未结束记录（restoreFromDb 用）。
   * 实现可顺带对账 activity 状态（RECORDING/PAUSED 与记录一致化）。
   * 无未结束记录返回 null；DB 失败 throw。
   */
  queryNewestOpenRecord(): Promise<OpenRecordInfo | null>;
}
