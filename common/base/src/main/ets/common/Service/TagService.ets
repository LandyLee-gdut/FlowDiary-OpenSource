import { hilog } from '@kit.PerformanceAnalysisKit';
import { TagModel, TagItem } from '../model/TagItem';
import { ColorUtil } from '../ColorUtil';
import { RDBStoreUtil } from '../../database/RDBStoreUtil'

const TAG: string = 'TagService';
const TAG_COLOR_REGEX: RegExp = /^#[0-9A-Fa-f]{6}$/;

export type TagMutationReason =
  'DUPLICATE_NAME' |
  'INVALID_NAME' |
  'INVALID_COLOR' |
  'NOT_FOUND' |
  'UNKNOWN';

export interface TagMutationResult {
  success: boolean;
  reason: TagMutationReason;
}

export interface TagCreateResult extends TagMutationResult {
  tagId?: string;
}

/**
 * Provides business logic for managing Tags.
 * This service layer sits between the UI/ViewModel and the data access layer (RDBStoreUtil).
 */
export class TagService {

  /**
   * 创建一个新标签。
   * @param name 标签名称
   * @param color 标签颜色（十六进制格式，如 '#4D94FF'）
   * @returns 创建结果；成功时包含 tagId，失败时包含具体 reason。
   */
  async createNewTag(name: string, color: string): Promise<TagCreateResult> {
    // 基础校验
    if (!name || name.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法创建名称为空的标签。');
      return { success: false, reason: 'INVALID_NAME' };
    }

    // 规范化颜色
    const normalizedColor = ColorUtil.normalizeHexColor(color);

    if (!normalizedColor || !normalizedColor.match(/^#[0-9A-Fa-f]{6}$/)) {
      hilog.error(0x0000, TAG, '颜色格式无效，应为六位十六进制格式（如 #4D94FF）。Input: ' + color);
      return { success: false, reason: 'INVALID_COLOR' };
    }

    hilog.info(0x0000, TAG, `尝试创建新标签: '${name}'，颜色为: ${normalizedColor}`);

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const normalizedName: string = name.trim();
      const allTags: TagItem[] = await rdbStoreUtil.queryAllTags();
      const hasDuplicateName: boolean = allTags.some((item: TagItem) => item.name === normalizedName);
      if (hasDuplicateName) {
        hilog.warn(0x0000, TAG, `创建标签失败，名称重复: ${normalizedName}`);
        return { success: false, reason: 'DUPLICATE_NAME' };
      }

      // 生成唯一ID和时间戳
      const tagId = this.generateUniqueId();
      const currentTime = Date.now();

      // 自动生成浅色版本
      const lightColor = ColorUtil.generateLighterColor(normalizedColor, 0.95, undefined);
      hilog.info(0x0000, TAG, 'tag service, new tag color is: ' + lightColor)
      // 创建 TagItem 对象
      const newTag = new TagItem(
        tagId,
        normalizedName,
        normalizedColor,
        lightColor,
        currentTime,
        currentTime
      );

      // 插入数据库
      const rowId = await rdbStoreUtil.insertTag(newTag);

      if (rowId > 0) {
        hilog.info(0x0000, TAG, `成功创建新标签，ID为: ${tagId}`);
        return { success: true, reason: 'UNKNOWN', tagId: tagId };
      } else {
        const latestTags: TagItem[] = await rdbStoreUtil.queryAllTags();
        const duplicateAfterInsert: boolean = latestTags.some((item: TagItem) => item.name === normalizedName);
        if (duplicateAfterInsert) {
          hilog.warn(0x0000, TAG, `创建标签失败，名称重复: ${normalizedName}`);
          return { success: false, reason: 'DUPLICATE_NAME' };
        }
        hilog.error(0x0000, TAG, '创建新标签失败，返回的 rowId 无效。');
        return { success: false, reason: 'UNKNOWN' };
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `创建标签时发生意外错误: ${JSON.stringify(error)}`);
      return { success: false, reason: 'UNKNOWN' };
    }
  }

  async updateTag(tagId: string, name: string, color: string): Promise<TagMutationResult> {
    if (!tagId || tagId.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法更新ID为空的标签。');
      return { success: false, reason: 'NOT_FOUND' };
    }

    const normalizedName = name.trim();
    if (normalizedName.length === 0 || normalizedName.length > 2) {
      hilog.error(0x0000, TAG, `标签名称无效: ${name}`);
      return { success: false, reason: 'INVALID_NAME' };
    }

    const normalizedColor = ColorUtil.normalizeHexColor(color);
    if (!TAG_COLOR_REGEX.test(normalizedColor)) {
      hilog.error(0x0000, TAG, `标签颜色无效，应为六位十六进制格式。Input: ${color}`);
      return { success: false, reason: 'INVALID_COLOR' };
    }

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const existingTag = await rdbStoreUtil.queryTagById(tagId);
      if (!existingTag) {
        return { success: false, reason: 'NOT_FOUND' };
      }

      const hasNameChanged = existingTag.name !== normalizedName;
      if (hasNameChanged) {
        const allTags = await rdbStoreUtil.queryAllTags();
        const hasDuplicateName = allTags.some((item: TagItem) => item.id !== tagId && item.name === normalizedName);
        if (hasDuplicateName) {
          hilog.warn(0x0000, TAG, `更新标签失败，名称重复: ${normalizedName}`);
          return { success: false, reason: 'DUPLICATE_NAME' };
        }
      }

      const lightColor = ColorUtil.generateLighterColor(normalizedColor, 0.95, undefined);
      const updated = await rdbStoreUtil.updateTag(tagId, normalizedName, normalizedColor, lightColor, Date.now());
      if (!updated) {
        return { success: false, reason: 'UNKNOWN' };
      }

      hilog.info(0x0000, TAG, `标签更新成功: ${tagId}`);
      return { success: true, reason: 'UNKNOWN' };
    } catch (error) {
      hilog.error(0x0000, TAG, `更新标签时发生错误: ${JSON.stringify(error)}`);
      return { success: false, reason: 'UNKNOWN' };
    }
  }

  /**
   * Fetches all tags from the database and maps them to the TagModel required by the UI.
   * @returns A promise that resolves to an array of TagModel objects.
   */
  async getAllTagsForUI(): Promise<TagModel[]> {
    hilog.info(0x0000, TAG, 'Fetching and preparing tag models for the UI.');

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();

      // 步骤 1: 从数据访问层获取原始的数据库模型 (TagItem)
      const tagItems: TagItem[] = await rdbStoreUtil.queryAllTags();

      if (!tagItems || tagItems.length === 0) {
        hilog.info(0x0000, TAG, 'No tags found in the database.');
        return [];
      }

      // 步骤 2: 【核心映射逻辑】将数据库模型 (TagItem) 映射到视图模型 (TagModel)
      const tagModels: TagModel[] = tagItems.map(item => {
        const tagModel: TagModel = {
          id: item.id,
          name: item.name,
          color: item.color,
          lightColor: item.lightColor
        };
        return tagModel;
      });

      hilog.info(0x0000, TAG, `Successfully prepared ${tagModels.length} tag models.`);
      return tagModels;
    } catch (error) {
      hilog.error(0x0000, TAG, `获取标签时发生错误: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /**
   * 获取所有原始标签数据
   * @returns 所有 TagItem 的列表
   */
  async getAllTags(): Promise<TagItem[]> {
    hilog.info(0x0000, TAG, 'Fetching all tags from database.');

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const tags = await rdbStoreUtil.queryAllTags();

      hilog.info(0x0000, TAG, `Successfully fetched ${tags.length} tags.`);
      return tags;
    } catch (error) {
      hilog.error(0x0000, TAG, `获取所有标签时发生错误: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /**
   * 根据ID查找标签
   * @param tagId 标签ID
   * @returns 标签对象或null
   */
  async getTagById(tagId: string): Promise<TagItem | null> {
    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      return await rdbStoreUtil.queryTagById(tagId);
    } catch (error) {
      hilog.error(0x0000, TAG, `根据ID查找标签时发生错误: ${JSON.stringify(error)}`);
      return null;
    }
  }

  /**
   * 删除指定的标签，并将引用该标签的事项恢复为无标签状态。
   * @param tagId 标签ID
   * @returns 是否删除成功
   */
  async deleteTag(tagId: string): Promise<boolean> {
    hilog.info(0x0000, TAG, `[deleteTag] start, tagId=${tagId}`);
    if (!tagId || tagId.trim().length === 0) {
      hilog.error(0x0000, TAG, '无法删除ID为空的标签。');
      return false;
    }

    try {
      const rdbStoreUtil = RDBStoreUtil.getInstance();
      const existingTag = await rdbStoreUtil.queryTagById(tagId.trim());
      if (!existingTag) {
        hilog.warn(0x0000, TAG, `[deleteTag] tag not found before deletion, tagId=${tagId}`);
      } else {
        hilog.info(0x0000, TAG, `[deleteTag] found tag before deletion, id=${existingTag.id}, name=${existingTag.name}`);
      }
      const deleted = await rdbStoreUtil.deleteTag(tagId.trim());

      if (deleted) {
        hilog.info(0x0000, TAG, `标签删除成功，ID为: ${tagId}`);
      } else {
        hilog.warn(0x0000, TAG, `删除标签失败，未找到ID为 ${tagId} 的标签`);
      }

      return deleted;
    } catch (error) {
      hilog.error(0x0000, TAG, `删除标签时发生错误: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 生成唯一ID
   */
  private generateUniqueId(): string {
    return `tag_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * 根据预定义调色板获取推荐颜色
   * @returns 推荐的颜色列表
   */
  public getRecommendedColors(): string[] {
    return [
      '#66D9A8', // 春绿色
      '#EF4444', // 活力红
      '#8B5CF6', // 紫水晶
      '#06B6D4', // 青色
      '#F97316', // 橘色
      '#EC4899', // 品红
      '#84CC16'  // 酸橙绿
    ];
  }
}

// 导出单例，方便在整个应用中统一调用
export const tagService = new TagService();
