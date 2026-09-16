import { IdeaCollection, TagItem } from 'base';

export function buildDefaultIdeaPoolSeedCollections(tags: TagItem[]): IdeaCollection[] {
  const now: number = Date.now();
  const resolvedTags: TagItem[] = Array.isArray(tags) ? tags : [];

  const tagA: TagItem | null = resolvedTags.length > 0 ? resolvedTags[0] : null;
  const tagB: TagItem | null = resolvedTags.length > 1 ? resolvedTags[1] : null;
  const tagC: TagItem | null = resolvedTags.length > 2 ? resolvedTags[2] : null;

  const collections: IdeaCollection[] = [
    new IdeaCollection(
      'collection-city-walk',
      '城市漫步路线',
      '🚶',
      tagA?.id ?? null,
      tagA?.name ?? null,
      tagA?.color ?? null,
      tagA?.lightColor ?? null,
      null,
      null,
      1,
      now,
      now
    ),
    new IdeaCollection(
      'collection-weekend-kitchen',
      '周末厨房实验',
      '🍳',
      tagB?.id ?? null,
      tagB?.name ?? null,
      tagB?.color ?? null,
      tagB?.lightColor ?? null,
      null,
      null,
      2,
      now,
      now
    ),
    new IdeaCollection(
      'collection-2026-learning',
      '2026学习计划',
      '📚',
      tagC?.id ?? null,
      tagC?.name ?? null,
      tagC?.color ?? null,
      tagC?.lightColor ?? null,
      null,
      null,
      3,
      now,
      now
    )
  ];

  return collections;
}
