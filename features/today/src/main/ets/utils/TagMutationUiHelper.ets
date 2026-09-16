import { MatterItemModel } from 'base';

const DEFAULT_NO_TAG_LABEL: string = '无标签';

export interface MatterListPatchInput {
  doneMatterData: MatterItemModel[];
  unDoMatterData: MatterItemModel[];
  matterData: MatterItemModel[];
  matterDataRevision: number;
}

export interface MatterListPatchResult {
  doneMatterData: MatterItemModel[];
  unDoMatterData: MatterItemModel[];
  matterData: MatterItemModel[];
  matterDataRevision: number;
  mutated: boolean;
}

interface MappedMatterListResult {
  items: MatterItemModel[];
  mutated: boolean;
}

function mapMatterListByLabel(
  source: MatterItemModel[],
  fromLabel: string,
  toLabel: string,
  toColor: ResourceColor
): MappedMatterListResult {
  if (!fromLabel || fromLabel.length === 0) {
    return { items: source, mutated: false };
  }

  let mutated: boolean = false;
  const mapped: MatterItemModel[] = source.map((item: MatterItemModel) => {
    if (item.label !== fromLabel) {
      return item;
    }
    mutated = true;
    const nextItem: MatterItemModel = item.clone();
    nextItem.label = toLabel;
    nextItem.labelColor = toColor;
    return nextItem;
  });

  return {
    items: mutated ? mapped : source,
    mutated
  };
}

export function patchMatterListsAfterTagDeletion(
  input: MatterListPatchInput,
  deletedTagName: string,
  fallbackColor: ResourceColor
): MatterListPatchResult {
  const done = mapMatterListByLabel(input.doneMatterData, deletedTagName, DEFAULT_NO_TAG_LABEL, fallbackColor);
  const undo = mapMatterListByLabel(input.unDoMatterData, deletedTagName, DEFAULT_NO_TAG_LABEL, fallbackColor);
  const all = mapMatterListByLabel(input.matterData, deletedTagName, DEFAULT_NO_TAG_LABEL, fallbackColor);
  const mutated: boolean = done.mutated || undo.mutated || all.mutated;

  return {
    doneMatterData: done.items,
    unDoMatterData: undo.items,
    matterData: all.items,
    matterDataRevision: mutated ? input.matterDataRevision + 1 : input.matterDataRevision,
    mutated
  };
}

export function patchMatterListsAfterTagUpdate(
  input: MatterListPatchInput,
  previousTagName: string,
  nextTagName: string,
  nextTagColor: ResourceColor
): MatterListPatchResult {
  const done = mapMatterListByLabel(input.doneMatterData, previousTagName, nextTagName, nextTagColor);
  const undo = mapMatterListByLabel(input.unDoMatterData, previousTagName, nextTagName, nextTagColor);
  const all = mapMatterListByLabel(input.matterData, previousTagName, nextTagName, nextTagColor);
  const mutated: boolean = done.mutated || undo.mutated || all.mutated;

  return {
    doneMatterData: done.items,
    unDoMatterData: undo.items,
    matterData: all.items,
    matterDataRevision: mutated ? input.matterDataRevision + 1 : input.matterDataRevision,
    mutated
  };
}

export function resolveSelectedTagIndexAfterDeletion(currentIndex: number, deletedIndex: number): number {
  if (currentIndex === deletedIndex) {
    return -1;
  }
  if (currentIndex > deletedIndex) {
    return currentIndex - 1;
  }
  return currentIndex;
}
