import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  RDBStoreUtil,
  MatterStatus,
  IdeaType,
  IdeaLightState,
  IdeaActivity,
  SortEntry,
  IdeaPoolState,
  IdeaPoolPreferences,
  DEFAULT_IDEA_POOL_PREFERENCES,
  MoveResult,
  TagItem,
  IdeaCollection,
  IdeaCategory,
  IdeaLightSummary,
  IdeaCollectionPatch,
  IdeaCategoryPatch,
  IdeaCollectionSummary,
  IdeaCategorySummary,
  FilesDirCarrier,
  SandboxMediaCopyResult,
  savePickerUriToSandboxFiles,
  deleteStoredFileBestEffort
} from 'base';

const TAG: string = 'IdeaPoolService';
const IDEA_COLLECTION_COVER_DIR: string = 'collection_covers';

export const DEFAULT_IDEA_USER_ID: string = 'default_user';

interface CreateIdeaPayload {
  name: string;
  tagId?: string | null;
}

interface CreateIdeaCollectionPayload {
  name: string;
  icon?: string | null;
  tagId?: string | null;
  coverStyle?: string | null;
  summaryText?: string | null;
  displayOrder?: number;
}

interface CreateIdeaCategoryPayload {
  name: string;
  color: string;
  lightColor: string;
  icon?: string | null;
}


interface DeleteIdeasResult {
  deletedIds: string[];
  timestamp: number;
}

interface BulkIdsPayload {
  ids: string[];
}

interface UpdateIdeaPatch {
  name?: string;
  tagId?: string | null;
  status?: MatterStatus;
}

export interface AddIdeaToTodayResult {
  createdActivityId: string;
  timestamp: number;
  todayOrder: SortEntry[];
  status: MatterStatus;
}

export interface IdeaCollectionCardEntry {
  id: string;
  collection: IdeaCollection;
  ideaCount: number;
}

export interface IdeaCollectionDetailPayload {
  collection: IdeaCollection | null;
  activities: IdeaActivity[];
  summary: IdeaCollectionSummary | null;
}

export class IdeaPoolService {
  private static instance: IdeaPoolService | null = null;
  private rdbStoreUtil: RDBStoreUtil;

  private constructor(context: Context) {
    this.rdbStoreUtil = RDBStoreUtil.getInstance();
  }

  static deriveIdeaLightSummary(activities: IdeaActivity[]): IdeaLightSummary {
    let litCount: number = 0;
    let unlitCount: number = 0;
    for (let index: number = 0; index < activities.length; index += 1) {
      const activity: IdeaActivity = activities[index];
      if (activity.ideaLightState === IdeaLightState.LIT) {
        litCount += 1;
      } else {
        unlitCount += 1;
      }
    }
    return {
      totalCount: litCount + unlitCount,
      litCount: litCount,
      unlitCount: unlitCount
    };
  }

  static buildIdeaCollectionCardEntries(
    collections: IdeaCollection[] | undefined,
    summaries: IdeaCollectionSummary[] | undefined
  ): IdeaCollectionCardEntry[] {
    const resolvedCollections: IdeaCollection[] = Array.isArray(collections) ? collections : [];
    const summaryMap: Map<string, IdeaCollectionSummary> = new Map<string, IdeaCollectionSummary>();
    if (Array.isArray(summaries)) {
      for (let index: number = 0; index < summaries.length; index += 1) {
        const summary: IdeaCollectionSummary = summaries[index];
        summaryMap.set(summary.collectionId, summary);
      }
    }

    const entries: IdeaCollectionCardEntry[] = resolvedCollections.map((collection: IdeaCollection): IdeaCollectionCardEntry => {
      const summary: IdeaCollectionSummary | undefined = summaryMap.get(collection.id);
      const count: number = summary ? summary.totalCount : 0;
      const entry: IdeaCollectionCardEntry = {
        id: collection.id,
        collection: collection,
        ideaCount: count
      };
      return entry;
    });

    entries.sort((left: IdeaCollectionCardEntry, right: IdeaCollectionCardEntry) => {
      const orderDelta: number = left.collection.displayOrder - right.collection.displayOrder;
      if (orderDelta !== 0) {
        return orderDelta;
      }
      return left.collection.createdAt - right.collection.createdAt;
    });

    return entries;
  }

  async fetchIdeaCollectionCardEntries(userId: string): Promise<IdeaCollectionCardEntry[]> {
    hilog.info(0x0000, TAG, 'Fetching Idea Pool collection cards for user ' + userId);
    const collections: IdeaCollection[] = await this.rdbStoreUtil.queryIdeaCollections();
    const summaries: IdeaCollectionSummary[] = await this.rdbStoreUtil.queryIdeaCollectionSummaries();
    return IdeaPoolService.buildIdeaCollectionCardEntries(collections, summaries);
  }

  async fetchIdeaPoolGlobalSummary(userId: string): Promise<IdeaLightSummary> {
    hilog.info(0x0000, TAG, 'Fetching Idea Pool global summary for user ' + userId);
    return await this.rdbStoreUtil.queryIdeaPoolGlobalSummary();
  }

  async fetchIdeaCollectionDetail(userId: string, collectionId: string): Promise<IdeaCollectionDetailPayload> {
    const trimmedId: string = collectionId !== undefined && collectionId !== null ? collectionId.trim() : '';
    const emptyPayload: IdeaCollectionDetailPayload = {
      collection: null,
      activities: [],
      summary: null
    };
    if (trimmedId.length === 0) {
      return emptyPayload;
    }

    const collections: IdeaCollection[] = await this.rdbStoreUtil.queryIdeaCollections();
    let targetCollection: IdeaCollection | null = null;
    for (let index: number = 0; index < collections.length; index += 1) {
      const collection: IdeaCollection = collections[index];
      if (collection.id === trimmedId) {
        targetCollection = collection;
        break;
      }
    }

    const activities: IdeaActivity[] = await this.rdbStoreUtil.queryIdeaCollectionActivities(trimmedId);
    const summaries: IdeaCollectionSummary[] = await this.rdbStoreUtil.queryIdeaCollectionSummaries();
    let targetSummary: IdeaCollectionSummary | null = null;
    for (let index: number = 0; index < summaries.length; index += 1) {
      const summary: IdeaCollectionSummary = summaries[index];
      if (summary.collectionId === trimmedId) {
        targetSummary = summary;
        break;
      }
    }

    return {
      collection: targetCollection,
      activities: activities,
      summary: targetSummary
    };
  }

  async resolveCollectionIdByActivity(activityId: string): Promise<string | null> {
    return await this.rdbStoreUtil.queryIdeaCollectionIdByActivityId(activityId);
  }

  static async init(context: Context): Promise<void> {
    if (IdeaPoolService.instance === null) {
      const service: IdeaPoolService = new IdeaPoolService(context);
      IdeaPoolService.instance = service;
    }
  }

  static getInstance(): IdeaPoolService {
    if (IdeaPoolService.instance === null) {
      throw new Error('IdeaPoolService not initialized. Call IdeaPoolService.init(context) first.');
    }
    return IdeaPoolService.instance;
  }

  private normalizeIdList(ids: string[]): string[] {
    const uniqueIds: string[] = [];
    const seen: Record<string, boolean> = {};
    for (let index: number = 0; index < ids.length; index += 1) {
      const rawId: string = ids[index];
      let trimmedId: string = '';
      if (rawId !== undefined && rawId !== null) {
        trimmedId = rawId.trim();
      }
      if (trimmedId.length === 0) {
        continue;
      }
      if (!seen[trimmedId]) {
        uniqueIds.push(trimmedId);
        seen[trimmedId] = true;
      }
    }
    return uniqueIds;
  }

  async fetchIdeaPool(userId: string): Promise<IdeaPoolState> {
    hilog.info(0x0000, TAG, 'Fetching Idea Pool state for user ' + userId);
    const activities: IdeaActivity[] = await this.rdbStoreUtil.queryIdeaPoolActivities();
    const tags: TagItem[] = await this.rdbStoreUtil.queryAllTags();
    const ideaPoolOrder: SortEntry[] = await this.rdbStoreUtil.queryIdeaPoolSortEntries();
    const todayOrder: SortEntry[] = await this.rdbStoreUtil.queryTodayListSortEntries();
    const collections: IdeaCollection[] = await this.rdbStoreUtil.queryIdeaCollections();
    const categories: IdeaCategory[] = await this.rdbStoreUtil.queryIdeaCategories();
    const collectionSummaries: IdeaCollectionSummary[] = await this.rdbStoreUtil.queryIdeaCollectionSummaries();
    const categorySummaries: IdeaCategorySummary[] = await this.rdbStoreUtil.queryIdeaCategorySummaries();
    const globalSummary: IdeaLightSummary = await this.rdbStoreUtil.queryIdeaPoolGlobalSummary();
    const preferences: IdeaPoolPreferences = {
      viewMode: DEFAULT_IDEA_POOL_PREFERENCES.viewMode,
      enableDragPrototype: DEFAULT_IDEA_POOL_PREFERENCES.enableDragPrototype,
      lastBulkSelection: []
    };
    return {
      activities: activities,
      tags: tags,
      ideaPoolOrder: ideaPoolOrder,
      todayOrder: todayOrder,
      preferences: preferences,
      collections: collections,
      categories: categories,
      collectionSummaries: collectionSummaries,
      categorySummaries: categorySummaries,
      globalSummary: globalSummary
    };
  }

  async reorderIdeas(userId: string, orderedIds: string[]): Promise<SortEntry[]> {
    return await this.rdbStoreUtil.updateIdeaPoolSortOrder(orderedIds);
  }

  async createIdea(userId: string, payload: CreateIdeaPayload): Promise<IdeaActivity | null> {
    const trimmedName: string = payload.name !== undefined && payload.name !== null ? payload.name.trim() : '';
    if (trimmedName.length === 0) {
      hilog.warn(0x0000, TAG, 'Cannot create idea with empty name');
      return null;
    }

    let resolvedTagId: string | null = null;
    if (payload.tagId !== undefined && payload.tagId !== null) {
      const trimmedTag: string = payload.tagId.trim();
      if (trimmedTag.length > 0) {
        resolvedTagId = trimmedTag;
      }
    }

    const activityId: string = RDBStoreUtil.generateUniqueId();
    let transactionStarted: boolean = false;

    try {
      await this.rdbStoreUtil.beginTransaction();
      transactionStarted = true;
      const rowId: number = await this.rdbStoreUtil.insertActivity(
        activityId,
        trimmedName,
        resolvedTagId,
        MatterStatus.IDEA_POOL,
        false
      );
      if (rowId < 0) {
        hilog.error(0x0000, TAG, 'Failed to insert idea into database');
        await this.rdbStoreUtil.rollBack();
        transactionStarted = false;
        return null;
      }

      await this.rdbStoreUtil.commit();
      transactionStarted = false;

      const activities: IdeaActivity[] = await this.rdbStoreUtil.queryIdeaPoolActivities();
      for (let index: number = 0; index < activities.length; index += 1) {
        const activity: IdeaActivity = activities[index];
        if (activity.id === activityId) {
          return activity;
        }
      }

      return null;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(0x0000, TAG, 'Error creating idea: code=' + err.code + ', message=' + err.message);
      if (transactionStarted) {
        await this.rdbStoreUtil.rollBack();
      }
      return null;
    }
  }

  async updateIdea(
    userId: string,
    id: string,
    patch: UpdateIdeaPatch
  ): Promise<IdeaActivity | null> {
    const trimmedName: string | undefined =
      patch.name !== undefined && patch.name !== null ? patch.name.trim() : undefined;
    let resolvedTagId: string | null = null;
    let tagUpdateRequested: boolean = false;

    if (patch.tagId !== undefined) {
      tagUpdateRequested = true;
      if (patch.tagId === null) {
        resolvedTagId = null;
      } else {
        const trimmedTag: string = patch.tagId.trim();
        resolvedTagId = trimmedTag.length > 0 ? trimmedTag : null;
      }
    } else if (trimmedName !== undefined) {
      resolvedTagId = await this.rdbStoreUtil.queryTagIdByActivityId(id);
    }

    let transactionStarted: boolean = false;

    try {
      if (trimmedName !== undefined || tagUpdateRequested) {
        await this.rdbStoreUtil.beginTransaction();
        transactionStarted = true;

        if (trimmedName !== undefined) {
          if (trimmedName.length === 0) {
            hilog.warn(0x0000, TAG, 'Skipping name update because trimmed value is empty');
          } else {
            await this.rdbStoreUtil.updateActivityNameAndTag(id, trimmedName, resolvedTagId);
          }
        } else if (tagUpdateRequested) {
          await this.rdbStoreUtil.updateActivityTag(id, resolvedTagId);
        }

        await this.rdbStoreUtil.commit();
        transactionStarted = false;
      }
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(0x0000, TAG, 'Failed to update idea metadata: code=' + err.code + ', message=' + err.message);
      if (transactionStarted) {
        await this.rdbStoreUtil.rollBack();
      }
      return null;
    }

    if (patch.status !== undefined) {
      if (patch.status === MatterStatus.IDEA_POOL) {
        await this.rdbStoreUtil.updateActivityStatus(id, MatterStatus.IDEA_POOL);
        await this.rdbStoreUtil.updateIdeaType(id, IdeaType.IDEA_POOL);
      } else if (patch.status === MatterStatus.ARCHIVED) {
        await this.rdbStoreUtil.updateActivityStatus(id, MatterStatus.ARCHIVED);
      } else if (
        patch.status === MatterStatus.TODO ||
        patch.status === MatterStatus.RECORDING ||
        patch.status === MatterStatus.PAUSED
      ) {
        const moveResult: MoveResult = await this.moveIdeasToToday(userId, { ids: [id] });
        if (patch.status !== MatterStatus.TODO) {
          await this.rdbStoreUtil.updateActivityStatus(id, patch.status);
        }
        if (moveResult.movedIds.length > 0) {
          return null;
        }
      }
    }

    const activities: IdeaActivity[] = await this.rdbStoreUtil.queryIdeaPoolActivities();
    for (let index: number = 0; index < activities.length; index += 1) {
      const activity: IdeaActivity = activities[index];
      if (activity.id === id) {
        return activity;
      }
    }
    return null;
  }

  async createIdeaCollection(userId: string, payload: CreateIdeaCollectionPayload): Promise<IdeaCollection | null> {
    const trimmedName: string = payload.name !== undefined && payload.name !== null ? payload.name.trim() : '';
    if (trimmedName.length === 0) {
      hilog.warn(0x0000, TAG, 'Cannot create collection with empty name');
      return null;
    }

    const collectionId: string = RDBStoreUtil.generateUniqueId();
    const displayOrder: number = payload.displayOrder !== undefined ? payload.displayOrder : 0;
    const rowId: number = await this.rdbStoreUtil.insertIdeaCollection(
      collectionId,
      trimmedName,
      payload.icon !== undefined ? payload.icon : null,
      payload.tagId !== undefined ? payload.tagId : null,
      payload.coverStyle !== undefined ? payload.coverStyle : null,
      payload.summaryText !== undefined ? payload.summaryText : null,
      displayOrder
    );
    if (rowId < 0) {
      return null;
    }

    const collections: IdeaCollection[] = await this.rdbStoreUtil.queryIdeaCollections();
    for (let index: number = 0; index < collections.length; index += 1) {
      const collection: IdeaCollection = collections[index];
      if (collection.id === collectionId) {
        return collection;
      }
    }
    return null;
  }

  async updateIdeaCollection(
    userId: string,
    id: string,
    patch: IdeaCollectionPatch
  ): Promise<IdeaCollection | null> {
    const updated: boolean = await this.rdbStoreUtil.updateIdeaCollection(id, patch);
    if (!updated) {
      return null;
    }
    const collections: IdeaCollection[] = await this.rdbStoreUtil.queryIdeaCollections();
    for (let index: number = 0; index < collections.length; index += 1) {
      const collection: IdeaCollection = collections[index];
      if (collection.id === id) {
        return collection;
      }
    }
    return null;
  }

  async reorderIdeaCollections(userId: string, orderedIds: string[]): Promise<boolean> {
    return await this.rdbStoreUtil.updateIdeaCollectionSortOrder(orderedIds);
  }

  async deleteIdeaCollection(userId: string, id: string): Promise<boolean> {
    return await this.rdbStoreUtil.deleteIdeaCollection(id);
  }

  /**
   * 更新合集封面：压缩选中的图片存入沙箱 collection_covers 目录，
   * 将返回的 relPath 写入 cover_style 列，并清理旧封面文件。
   */
  async updateIdeaCollectionCover(
    userId: string,
    collectionId: string,
    pickerUri: string,
    ctx: FilesDirCarrier
  ): Promise<SandboxMediaCopyResult | null> {
    const detail: IdeaCollectionDetailPayload = await this.fetchIdeaCollectionDetail(userId, collectionId);
    const oldCoverPath: string | null = detail.collection !== null ? detail.collection.coverStyle : null;

    let saved: SandboxMediaCopyResult;
    try {
      saved = await savePickerUriToSandboxFiles(ctx, pickerUri, IDEA_COLLECTION_COVER_DIR);
    } catch (err) {
      const errMsg: string = err instanceof Error ? err.message : String(err);
      hilog.error(0x0000, TAG, `updateIdeaCollectionCover save failed: ${errMsg}`);
      return null;
    }

    const updated: IdeaCollection | null =
      await this.updateIdeaCollection(userId, collectionId, { coverStyle: saved.relPath });
    if (updated === null) {
      deleteStoredFileBestEffort(ctx, saved.relPath);
      return null;
    }

    if (oldCoverPath !== null && oldCoverPath.length > 0 && oldCoverPath !== saved.relPath) {
      deleteStoredFileBestEffort(ctx, oldCoverPath);
    }
    return saved;
  }

  /**
   * 清除合集封面：cover_style 置空并删除对应沙箱文件。
   */
  async clearIdeaCollectionCover(userId: string, collectionId: string, ctx: FilesDirCarrier): Promise<boolean> {
    const detail: IdeaCollectionDetailPayload = await this.fetchIdeaCollectionDetail(userId, collectionId);
    const oldCoverPath: string | null = detail.collection !== null ? detail.collection.coverStyle : null;

    const updated: IdeaCollection | null =
      await this.updateIdeaCollection(userId, collectionId, { coverStyle: null });
    if (updated === null) {
      return false;
    }

    if (oldCoverPath !== null && oldCoverPath.length > 0) {
      deleteStoredFileBestEffort(ctx, oldCoverPath);
    }
    return true;
  }

  async assignIdeaToCollection(
    userId: string,
    activityId: string,
    collectionId: string,
    displayOrder: number = 0
  ): Promise<boolean> {
    const trimmedActivityId: string = activityId !== undefined && activityId !== null ? activityId.trim() : '';
    const trimmedCollectionId: string = collectionId !== undefined && collectionId !== null ? collectionId.trim() : '';
    hilog.info(0x0000, TAG,
      `IdeaCollection assignIdeaToCollection: activityId=${trimmedActivityId}, collectionId=${trimmedCollectionId}, displayOrder=${displayOrder}`);
    return await this.rdbStoreUtil.upsertIdeaCollectionItem(trimmedActivityId, trimmedCollectionId, displayOrder);
  }

  async clearIdeaCollectionAssignment(userId: string, activityId: string): Promise<boolean> {
    return await this.rdbStoreUtil.clearIdeaCollectionItem(activityId);
  }

  async createIdeaCategory(userId: string, payload: CreateIdeaCategoryPayload): Promise<IdeaCategory | null> {
    const trimmedName: string = payload.name !== undefined && payload.name !== null ? payload.name.trim() : '';
    if (trimmedName.length === 0) {
      hilog.warn(0x0000, TAG, 'Cannot create category with empty name');
      return null;
    }

    const categoryId: string = RDBStoreUtil.generateUniqueId();
    const rowId: number = await this.rdbStoreUtil.insertIdeaCategory(
      categoryId,
      trimmedName,
      payload.color,
      payload.lightColor,
      payload.icon !== undefined ? payload.icon : null
    );
    if (rowId < 0) {
      return null;
    }

    const categories: IdeaCategory[] = await this.rdbStoreUtil.queryIdeaCategories();
    for (let index: number = 0; index < categories.length; index += 1) {
      const category: IdeaCategory = categories[index];
      if (category.id === categoryId) {
        return category;
      }
    }
    return null;
  }

  async updateIdeaCategory(
    userId: string,
    id: string,
    patch: IdeaCategoryPatch
  ): Promise<IdeaCategory | null> {
    const updated: boolean = await this.rdbStoreUtil.updateIdeaCategory(id, patch);
    if (!updated) {
      return null;
    }
    const categories: IdeaCategory[] = await this.rdbStoreUtil.queryIdeaCategories();
    for (let index: number = 0; index < categories.length; index += 1) {
      const category: IdeaCategory = categories[index];
      if (category.id === id) {
        return category;
      }
    }
    return null;
  }

  async deleteIdeaCategory(userId: string, id: string): Promise<boolean> {
    return await this.rdbStoreUtil.deleteIdeaCategory(id);
  }

  async assignIdeaToCategory(userId: string, activityId: string, categoryId: string): Promise<boolean> {
    return await this.rdbStoreUtil.upsertIdeaCategoryItem(activityId, categoryId);
  }

  async clearIdeaCategoryAssignment(userId: string, activityId: string): Promise<boolean> {
    return await this.rdbStoreUtil.clearIdeaCategoryItem(activityId);
  }

  async rollbackIdeaToUnlit(userId: string, activityId: string): Promise<boolean> {
    return await this.rdbStoreUtil.resetIdeaLightStateAndCount(activityId);
  }

  async removeIdeaFromIdeaPool(userId: string, activityId: string): Promise<boolean> {
    return await this.rdbStoreUtil.removeIdeaFromIdeaPool(activityId);
  }

  async deleteIdeas(userId: string, payload: BulkIdsPayload): Promise<DeleteIdeasResult> {
    const ids: string[] = this.normalizeIdList(payload.ids);
    if (ids.length === 0) {
      const timestamp: number = Date.now();
      const emptyResult: DeleteIdeasResult = { deletedIds: [], timestamp: timestamp };
      return emptyResult;
    }

    const deletedIds: string[] = [];

    for (let index: number = 0; index < ids.length; index += 1) {
      const id: string = ids[index];
      const removed: boolean = await this.rdbStoreUtil.removeIdeaFromIdeaPool(id);
      if (removed) {
        deletedIds.push(id);
      }
    }

    const completionTimestamp: number = Date.now();
    const result: DeleteIdeasResult = {
      deletedIds: deletedIds,
      timestamp: completionTimestamp
    };
    return result;
  }

  async moveIdeasToToday(
    userId: string,
    payload: BulkIdsPayload
  ): Promise<MoveResult> {
    const ids: string[] = this.normalizeIdList(payload.ids);
    const timestamp: number = Date.now();

    if (ids.length === 0) {
      const ideaPoolOrderEmpty: SortEntry[] = await this.rdbStoreUtil.queryIdeaPoolSortEntries();
      const todayOrderEmpty: SortEntry[] = await this.rdbStoreUtil.queryTodayListSortEntries();
      const emptyResult: MoveResult = {
        movedIds: [],
        targetStatus: MatterStatus.TODO,
        ideaPoolOrder: ideaPoolOrderEmpty,
        todayOrder: todayOrderEmpty,
        timestamp: timestamp
      };
      return emptyResult;
    }

    const ideaPoolOrderBefore: SortEntry[] = await this.rdbStoreUtil.queryIdeaPoolSortEntries();

    const todayOrderBefore: SortEntry[] = await this.rdbStoreUtil.queryTodayListSortEntries();
    const newTodayOrderIds: string[] = [];
    for (let index: number = 0; index < todayOrderBefore.length; index += 1) {
      const entry: SortEntry = todayOrderBefore[index];
      if (ids.indexOf(entry.activityId) === -1) {
        newTodayOrderIds.push(entry.activityId);
      }
    }
    for (let index: number = 0; index < ids.length; index += 1) {
      const idValue: string = ids[index];
      newTodayOrderIds.push(idValue);
    }

    const updatedTodayOrder: SortEntry[] = await this.rdbStoreUtil.updateTodayListSortOrder(newTodayOrderIds);

    for (let index: number = 0; index < ids.length; index += 1) {
      const idValue: string = ids[index];
      const statusUpdated = await this.rdbStoreUtil.updateActivityStatus(idValue, MatterStatus.TODO);
      if (statusUpdated) {
        await this.rdbStoreUtil.incrementIdeaLightCountAndSetLit(idValue);
      }
    }

    const result: MoveResult = {
      movedIds: ids,
      targetStatus: MatterStatus.TODO,
      ideaPoolOrder: ideaPoolOrderBefore,
      todayOrder: updatedTodayOrder,
      timestamp: timestamp
    };
    return result;
  }

  /**
   * Create a brand-new Today activity from an Idea Pool item.
   * - The idea stays in Idea Pool (idea_type=IDEA_POOL)
   * - Each "add to Today" creates a unique activity id so multiple adds do not conflict
   * - The idea's light count is incremented and marked as lit
   */
  async addIdeaToToday(
    userId: string,
    idea: IdeaActivity,
    autoRecord: boolean = false
  ): Promise<AddIdeaToTodayResult | null> {
    const trimmedIdeaId: string = idea?.id ? idea.id.trim() : '';
    const trimmedName: string = idea?.name ? idea.name.trim() : '';
    if (trimmedIdeaId.length === 0 || trimmedName.length === 0) {
      hilog.warn(0x0000, TAG, 'Cannot add idea to Today: missing id or name');
      return null;
    }

    const timestamp: number = Date.now();
    const createdActivityId: string = RDBStoreUtil.generateUniqueId();
    let targetStatus: MatterStatus = MatterStatus.TODO;
    if (autoRecord) {
      try {
        const activeRecords = await this.rdbStoreUtil.queryActiveOpenRecords();
        if (activeRecords.length === 0) {
          targetStatus = MatterStatus.RECORDING;
        } else {
          hilog.warn(0x0000, TAG,
            `Auto-record disabled for idea ${trimmedIdeaId} because another activity is recording.`);
        }
      } catch (error) {
        hilog.error(0x0000, TAG,
          `Failed to check active recordings before auto-record: ${JSON.stringify(error)}`);
      }
    }

    try {
      const rowId: number = await this.rdbStoreUtil.insertActivity(
        createdActivityId,
        trimmedName,
        idea.tagId ?? null,
        targetStatus,
        false,
        IdeaType.TODAY_ONLY
      );

      if (rowId < 0) {
        hilog.error(0x0000, TAG, `Failed to insert Today activity for idea ${trimmedIdeaId}`);
        return null;
      }

      if (targetStatus === MatterStatus.RECORDING) {
        try {
          await this.rdbStoreUtil.insertTimeRecord(createdActivityId, timestamp);
        } catch (error) {
          hilog.error(0x0000, TAG,
            `Failed to create time record for idea ${trimmedIdeaId}: ${JSON.stringify(error)}`);
          const reverted = await this.rdbStoreUtil.updateActivityStatus(createdActivityId, MatterStatus.TODO);
          if (!reverted) {
            hilog.warn(0x0000, TAG, `Failed to revert activity ${createdActivityId} to TODO after record failure.`);
          }
          targetStatus = MatterStatus.TODO;
        }
      }

      const litUpdated: boolean = await this.rdbStoreUtil.incrementIdeaLightCountAndSetLit(trimmedIdeaId);
      if (!litUpdated) {
        hilog.warn(0x0000, TAG, `Inserted Today activity ${createdActivityId} but failed to update idea light state for ${trimmedIdeaId}`);
      }

      const todayOrder: SortEntry[] = await this.rdbStoreUtil.queryTodayListSortEntries();
      return {
        createdActivityId,
        timestamp,
        todayOrder,
        status: targetStatus
      };
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(0x0000, TAG, 'Failed to add idea to Today: code=' + err.code + ', message=' + err.message);
      return null;
    }
  }
}

export async function initIdeaPoolService(context: Context): Promise<IdeaPoolService> {
  await IdeaPoolService.init(context);
  return IdeaPoolService.getInstance();
}
