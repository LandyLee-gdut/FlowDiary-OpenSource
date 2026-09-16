import { MatterItemModel, MatterItemModelInit } from 'base';
import { MatterStatus } from 'base';
import { TagModel } from '../model/TagModel';
import { todayActivityService } from './TodayActivityService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { tagService } from 'base';

const TAG = 'TodayModel'

function timeToday(hour: number, minute: number): Date {
  const now = new Date();
  now.setHours(hour, minute, 0, 0);
  return now;
}

export function getMockMatterData(): MatterItemModel[] {
  const mockData: MatterItemModelInit[] = [
  // 状态 1: 正在进行中 (RECORDING)
    {
      id: 'activity-001',
      title: "写项目文档",
      label: "工作",
      labelColor: $r('app.color.data_viz_1'),
      status: MatterStatus.RECORDING,
      durationInMilliseconds: 75 * 60 * 1000, // 假设之前已经记录了75分钟
    },
    // 状态 2: 今日已记录，但当前暂停 (PAUSED)
    {
      id: 'activity-002',
      title: "健身房锻炼",
      label: "运动",
      labelColor: $r('app.color.data_viz_5'),
      status: MatterStatus.PAUSED,
      durationInMilliseconds: 60 * 60 * 1000, // 今天总共锻炼了60分钟
    },
    // 状态 3: 纯待办事项 (TODO)
    {
      id: 'activity-003',
      title: "学习 ArkTS 新特性",
      label: "学习",
      labelColor: $r('app.color.data_viz_3'),
      status: MatterStatus.TODO,
      durationInMilliseconds: 0, // 从未开始，时长为0
    },
    // 状态 4: 另一个暂停的事项
    {
      id: 'activity-004',
      title: "回复重要邮件",
      label: "工作",
      labelColor: $r('app.color.data_viz_1'),
      status: MatterStatus.PAUSED,
      durationInMilliseconds: 15 * 60 * 1000,
    },
    // 状态 5: 另一个纯待办事项
    {
      id: 'activity-005',
      title: "规划周末出行",
      label: "生活",
      labelColor: $r('app.color.data_viz_4'),
      status: MatterStatus.TODO,
      durationInMilliseconds: 0,
    },
    // 状态 6: 已归档事项 (ARCHIVED)
    {
      id: 'activity-006',
      title: "完成月度报告",
      label: "工作",
      labelColor: $r('app.color.data_viz_1'),
      status: MatterStatus.ARCHIVED,
      durationInMilliseconds: 120 * 60 * 1000, // 已完成2小时
    },
  ];
  return MatterItemModel.ensureList(mockData);
}
/**
 * Generates a list of mock tags for the application, including both a primary color and a light background color.
 * This data is designed to match the UI style and the database 'tag' table schema.
 *
 * @returns An array of TagModel objects.
 */
export function getMockTagData(): TagModel[] {
  const mockTags: TagModel[] = [
    {
      id: 'tag-001',
      name: '工作',
      color: '#4D94FF',          // matches data_viz_1
      lightColor: '#E6F0FF'      // matches data_viz_1_light
    },
    {
      id: 'tag-003',
      name: '休闲',
      color: '#F5BF3B',          // matches data_viz_2
      lightColor: '#FFE8A0'      // matches data_viz_2_light
    },
    {
      id: 'tag-002',
      name: '学习',
      color: '#4AC9C2',          // matches data_viz_3
      lightColor: '#E0F8F7'      // matches data_viz_3_light
    },
    {
      id: 'tag-006',
      name: '生活',
      color: '#ccb380ff',        // matches data_viz_4
      lightColor: '#F2EBFF'      // matches data_viz_4_light
    },
    {
      id: 'tag-004',
      name: '运动',
      color: '#ccff8a78',        // matches data_viz_5
      lightColor: '#FFEAE7'      // matches data_viz_5_light
    },
    {
      id: 'tag-007',
      name: '副业',
      color: '#66D9A8',          // matches data_viz_6
      lightColor: '#E3F7EF'      // matches data_viz_6_light
    }
  ];

  return mockTags;
}

export function addMatterToList(target: MatterItemModel[], item: MatterItemModel, insertAtFront: boolean = false): void {
  const normalizedItem = MatterItemModel.from(item);
  const existingIndex = target.findIndex(existing => existing.id === normalizedItem.id);
  if (existingIndex >= 0) {
    target.splice(existingIndex, 1);
  }

  if (insertAtFront) {
    target.splice(0, 0, normalizedItem);
  } else {
    target.push(normalizedItem);
  }
}

export function removeMatterFromList(target: MatterItemModel[], id: string): MatterItemModel | null {
  const index = target.findIndex(existing => existing.id === id);
  if (index < 0) {
    return null;
  }
  const removedItem = target[index];
  target.splice(index, 1);
  return removedItem ?? null;
}

/**
 * 生成主页 done 区的稳定投影：其余事项沿用当前可见顺序。
 * 数据库刷新可能返回不同顺序；保留既有顺序可避免无业务意义的列表抖动。
 * 仅当 RECORDING 事项是新进入 done 区（undo -> done 跨组开始、冷启动）时才置于首位；
 * 组内恢复（PAUSED -> RECORDING）保持原位置，不打乱用户的空间记忆。
 */
export function buildPinnedDoneMatterList(
  sourceList: MatterItemModel[],
  currentVisibleList: MatterItemModel[]
): MatterItemModel[] {
  const sourceById: Map<string, MatterItemModel> = new Map();
  let recordingItem: MatterItemModel | null = null;
  const result: MatterItemModel[] = [];

  for (const item of sourceList) {
    sourceById.set(item.id, item);
    if (item.status === MatterStatus.RECORDING) {
      recordingItem = item;
    }
  }

  let pinnedRecordingId: string = '';
  const recording: MatterItemModel | null = recordingItem;
  if (recording !== null) {
    const isNewToDoneGroup: boolean = !currentVisibleList.some(
      (visibleItem: MatterItemModel) => visibleItem.id === recording.id
    );
    if (isNewToDoneGroup) {
      result.push(recording);
      pinnedRecordingId = recording.id;
    }
  }

  for (const visibleItem of currentVisibleList) {
    const updatedItem: MatterItemModel | undefined = sourceById.get(visibleItem.id);
    if (updatedItem !== undefined && updatedItem.id !== pinnedRecordingId) {
      result.push(updatedItem);
      sourceById.delete(updatedItem.id);
    }
  }

  for (const sourceItem of sourceList) {
    if (sourceItem.id !== pinnedRecordingId && sourceById.has(sourceItem.id)) {
      result.push(sourceItem);
      sourceById.delete(sourceItem.id);
    }
  }

  return result;
}

/**
 * 从数据库加载标签数据
 */
export async function loadTagsFromDatabase(): Promise<TagModel[]> {
  try {
    const tagData = await tagService.getAllTagsForUI();
    hilog.info(0x0000, TAG, `Loaded ${tagData.length} tags from database`);
    return tagData;
  } catch (error) {
    hilog.error(0x0000, TAG, `Error loading tags: ${JSON.stringify(error)}`);
  }
  return [];
}
