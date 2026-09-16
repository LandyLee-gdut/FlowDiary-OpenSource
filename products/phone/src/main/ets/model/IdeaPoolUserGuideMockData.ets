import { IdeaActivity, MatterStatus, IdeaType, IdeaLightState } from 'base';

/**
 * 创建灵感池引导页面的模拟数据
 */
export function createIdeaPoolUserGuideMockData(): IdeaActivity[] {
  const ideas: IdeaActivity[] = [];

  // 创意想法1
  ideas.push(new IdeaActivity(
    'idea_demo_1',
    '设计一款健康追踪应用',
    MatterStatus.IDEA_POOL,
    'tag_1',
    '技术',
    '#FF6B6B',
    '#FFE5E5',
    Date.now() - 86400000, // 昨天创建
    Date.now(),
    0,
    IdeaType.IDEA_POOL,
    IdeaLightState.UNLIT,
    0
  ));

  // 创意想法2
  ideas.push(new IdeaActivity(
    'idea_demo_2',
    '学习新的编程语言 Rust',
    MatterStatus.IDEA_POOL,
    'tag_2',
    '学习',
    '#4ECDC4',
    '#E5F9F7',
    Date.now() - 172800000, // 前天创建
    Date.now(),
    1,
    IdeaType.IDEA_POOL,
    IdeaLightState.UNLIT,
    0
  ));

  // 创意想法3
  ideas.push(new IdeaActivity(
    'idea_demo_3',
    '参加技术分享会',
    MatterStatus.IDEA_POOL,
    'tag_3',
    '社交',
    '#45B7D1',
    '#E5F4F8',
    Date.now() - 259200000, // 3天前创建
    Date.now(),
    2,
    IdeaType.IDEA_POOL,
    IdeaLightState.UNLIT,
    0
  ));

  // 创意想法4
  ideas.push(new IdeaActivity(
    'idea_demo_4',
    '写一篇关于AI的文章',
    MatterStatus.IDEA_POOL,
    'tag_4',
    '写作',
    '#96CEB4',
    '#E8F5E8',
    Date.now() - 345600000, // 4天前创建
    Date.now(),
    3,
    IdeaType.IDEA_POOL,
    IdeaLightState.UNLIT,
    0
  ));

  return ideas;
}
