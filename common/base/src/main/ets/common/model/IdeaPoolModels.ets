import { MatterStatus, IdeaType, IdeaLightState } from './MatterStatus';
import { TagItem } from './TagItem';

/**
 * Activity representation tailored for Idea Pool flows.
 */
@Observed
export class IdeaActivity {
  id: string;
  name: string;
  status: MatterStatus;
  ideaType: IdeaType;
  ideaLightState: IdeaLightState;
  ideaLightCount: number;
  tagId: string | null;
  tagName: string | null;
  tagColorHex: string | null;
  tagLightColorHex: string | null;
  createdAt: number;
  updatedAt: number;
  displayOrder: number | null;

  constructor(
    id: string,
    name: string,
    status: MatterStatus,
    tagId: string | null,
    tagName: string | null,
    tagColorHex: string | null,
    tagLightColorHex: string | null,
    createdAt: number,
    updatedAt: number,
    displayOrder: number | null,
    ideaType: IdeaType = IdeaType.UNKNOWN,
    ideaLightState: IdeaLightState = IdeaLightState.UNLIT,
    ideaLightCount: number = 0
  ) {
    this.id = id;
    this.name = name;
    this.status = status;
    this.ideaType = ideaType;
    this.ideaLightState = ideaLightState;
    this.ideaLightCount = ideaLightCount;
    this.tagId = tagId;
    this.tagName = tagName;
    this.tagColorHex = tagColorHex;
    this.tagLightColorHex = tagLightColorHex;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.displayOrder = displayOrder;
  }
}

/**
 * Sort configuration entry shared between Idea Pool and Today lists.
 */
@Observed
export class SortEntry {
  activityId: string;
  displayOrder: number;

  constructor(activityId: string, displayOrder: number) {
    this.activityId = activityId;
    this.displayOrder = displayOrder;
  }
}

export type IdeaPoolViewMode = 'list' | 'grid';

export interface IdeaPoolPreferences {
  viewMode: IdeaPoolViewMode;
  enableDragPrototype: boolean;
  lastBulkSelection: string[];
}

export const DEFAULT_IDEA_POOL_PREFERENCES: IdeaPoolPreferences = {
  viewMode: 'list',
  enableDragPrototype: false,
  lastBulkSelection: []
};

export interface IdeaPoolState {
  activities: IdeaActivity[];
  tags: TagItem[];
  ideaPoolOrder: SortEntry[];
  todayOrder: SortEntry[];
  preferences: IdeaPoolPreferences;
  collections?: IdeaCollection[];
  categories?: IdeaCategory[];
  collectionSummaries?: IdeaCollectionSummary[];
  categorySummaries?: IdeaCategorySummary[];
  globalSummary?: IdeaLightSummary | null;
}

export interface IdeaSummary {
  id: string;
  name: string;
  tagId: string | null;
  tagName: string | null;
  tagColorHex: string | null;
  tagLightColorHex: string | null;
  createdAt: number;
  updatedAt: number;
  latestRecordTimestamp: number | null;
}

export interface IdeaLightSummary {
  totalCount: number;
  litCount: number;
  unlitCount: number;
}

export interface IdeaCollectionPatch {
  name?: string;
  icon?: string | null;
  tagId?: string | null;
  coverStyle?: string | null;
  summaryText?: string | null;
  displayOrder?: number;
}

export interface IdeaCategoryPatch {
  name?: string;
  color?: string;
  lightColor?: string;
  icon?: string | null;
}

export interface IdeaCollectionSummary extends IdeaLightSummary {
  collectionId: string;
}

export interface IdeaCategorySummary extends IdeaLightSummary {
  categoryId: string;
}

@Observed
export class IdeaCollection {
  id: string;
  name: string;
  icon: string | null;
  tagId: string | null;
  tagName: string | null;
  tagColorHex: string | null;
  tagLightColorHex: string | null;
  coverStyle: string | null;
  summaryText: string | null;
  displayOrder: number;
  createdAt: number;
  updatedAt: number;

  constructor(
    id: string,
    name: string,
    icon: string | null,
    tagId: string | null,
    tagName: string | null,
    tagColorHex: string | null,
    tagLightColorHex: string | null,
    coverStyle: string | null,
    summaryText: string | null,
    displayOrder: number,
    createdAt: number,
    updatedAt: number
  ) {
    this.id = id;
    this.name = name;
    this.icon = icon;
    this.tagId = tagId;
    this.tagName = tagName;
    this.tagColorHex = tagColorHex;
    this.tagLightColorHex = tagLightColorHex;
    this.coverStyle = coverStyle;
    this.summaryText = summaryText;
    this.displayOrder = displayOrder;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }
}

export class IdeaCategory {
  id: string;
  name: string;
  color: string;
  lightColor: string;
  icon: string | null;
  createdAt: number;
  updatedAt: number;

  constructor(
    id: string,
    name: string,
    color: string,
    lightColor: string,
    icon: string | null,
    createdAt: number,
    updatedAt: number
  ) {
    this.id = id;
    this.name = name;
    this.color = color;
    this.lightColor = lightColor;
    this.icon = icon;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }
}

export interface MoveResult {
  movedIds: string[];
  targetStatus: MatterStatus;
  ideaPoolOrder: SortEntry[];
  todayOrder: SortEntry[];
  timestamp: number;
}
