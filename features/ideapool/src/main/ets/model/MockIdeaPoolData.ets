import {
  IdeaPoolState,
  IdeaActivity,
  IdeaCollection,
  IdeaCollectionSummary,
  SortEntry,
  DEFAULT_IDEA_POOL_PREFERENCES,
  MatterStatus,
  IdeaType,
  IdeaLightState,
  TagItem,
  AppColors
} from 'base';

/**
 * Provide deterministic mock data so the Idea Pool UI can render without a backing database.
 */
export function getMockIdeaPoolState(): IdeaPoolState {
  const createdAtBase = Date.now() - 1000 * 60 * 60 * 24;

  const twoDaysAgo = createdAtBase - 1000 * 60 * 60 * 24;
  const fiveHoursAgo = Date.now() - 1000 * 60 * 60 * 5;
  const yesterday = Date.now() - 1000 * 60 * 60 * 24;

  const tags: TagItem[] = [
    new TagItem('tag-inspiration', 'Inspiration', AppColors.DATA_VIZ_1, AppColors.DATA_VIZ_1_LIGHT, createdAtBase, createdAtBase),
    new TagItem('tag-learning', 'Learning', AppColors.DATA_VIZ_3, AppColors.DATA_VIZ_3_LIGHT, createdAtBase, createdAtBase),
    new TagItem('tag-health', 'Health', AppColors.DATA_VIZ_6, AppColors.DATA_VIZ_6_LIGHT, createdAtBase, createdAtBase),
    new TagItem('tag-wellness', 'Wellness', AppColors.DATA_VIZ_5, AppColors.DATA_VIZ_5_LIGHT, createdAtBase, createdAtBase),
    new TagItem('tag-fun', 'Play', AppColors.DATA_VIZ_9, AppColors.DATA_VIZ_9_LIGHT, createdAtBase, createdAtBase)
  ];

  const activities: IdeaActivity[] = [
    new IdeaActivity(
      'idea-journey-map',
      'Draw customer journey map for onboarding',
      MatterStatus.IDEA_POOL,
      tags[0].id,
      tags[0].name,
      tags[0].color,
      tags[0].lightColor,
      createdAtBase,
      createdAtBase + 1000 * 60 * 30,
      1,
      IdeaType.IDEA_POOL,
      IdeaLightState.UNLIT,
      0
    ),
    new IdeaActivity(
      'idea-sprint-retro',
      'Plan async sprint retro template',
      MatterStatus.IDEA_POOL,
      tags[1].id,
      tags[1].name,
      tags[1].color,
      tags[1].lightColor,
      createdAtBase + 1000 * 60 * 60 * 6,
      createdAtBase + 1000 * 60 * 60 * 8,
      2,
      IdeaType.IDEA_POOL,
      IdeaLightState.UNLIT,
      0
    ),
    new IdeaActivity(
      'idea-walking-club',
      'Start lunchtime walking club',
      MatterStatus.IDEA_POOL,
      tags[2].id,
      tags[2].name,
      tags[2].color,
      tags[2].lightColor,
      createdAtBase + 1000 * 60 * 60 * 12,
      createdAtBase + 1000 * 60 * 60 * 13,
      3,
      IdeaType.IDEA_POOL,
      IdeaLightState.UNLIT,
      0
    ),
    new IdeaActivity(
      'idea-respiratory-break',
      'Design 5-minute breathing reset for teams',
      MatterStatus.IDEA_POOL,
      tags[3].id,
      tags[3].name,
      tags[3].color,
      tags[3].lightColor,
      twoDaysAgo,
      yesterday,
      4,
      IdeaType.IDEA_POOL,
      IdeaLightState.UNLIT,
      0
    ),
    new IdeaActivity(
      'idea-hobby-swap',
      'Host hobby swap night with prototypes',
      MatterStatus.IDEA_POOL,
      tags[4].id,
      tags[4].name,
      tags[4].color,
      tags[4].lightColor,
      yesterday,
      fiveHoursAgo,
      5,
      IdeaType.IDEA_POOL,
      IdeaLightState.UNLIT,
      0
    )
  ];

  const ideaPoolOrder: SortEntry[] = activities.map((activity, index) => new SortEntry(activity.id, index + 1));

  const collections: IdeaCollection[] = [
    new IdeaCollection(
      'collection-city-walk',
      '城市漫步路线',
      '🚶',
      tags[0].id,
      tags[0].name,
      tags[0].color,
      tags[0].lightColor,
      null,
      null,
      1,
      createdAtBase,
      createdAtBase
    ),
    new IdeaCollection(
      'collection-weekend-kitchen',
      '周末厨房实验',
      '🍳',
      tags[1].id,
      tags[1].name,
      tags[1].color,
      tags[1].lightColor,
      null,
      null,
      2,
      createdAtBase,
      createdAtBase
    ),
    new IdeaCollection(
      'collection-2024-learning',
      '2024学习计划',
      '📚',
      tags[2].id,
      tags[2].name,
      tags[2].color,
      tags[2].lightColor,
      null,
      null,
      3,
      createdAtBase,
      createdAtBase
    )
  ];

  const collectionSummaries: IdeaCollectionSummary[] = collections.map((collection: IdeaCollection): IdeaCollectionSummary => {
    const summary: IdeaCollectionSummary = {
      collectionId: collection.id,
      totalCount: 0,
      litCount: 0,
      unlitCount: 0
    };
    return summary;
  });

  return {
    activities,
    tags,
    ideaPoolOrder,
    todayOrder: [],
    preferences: {
      viewMode: DEFAULT_IDEA_POOL_PREFERENCES.viewMode,
      enableDragPrototype: DEFAULT_IDEA_POOL_PREFERENCES.enableDragPrototype,
      lastBulkSelection: DEFAULT_IDEA_POOL_PREFERENCES.lastBulkSelection.slice()
    },
    collections,
    collectionSummaries
  };
}
