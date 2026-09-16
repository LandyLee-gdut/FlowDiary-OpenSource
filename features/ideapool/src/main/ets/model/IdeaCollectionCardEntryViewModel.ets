import { IdeaCollection } from 'base';

@Observed
export class IdeaCollectionCardEntryViewModel {
  id: string;
  collection: IdeaCollection;
  ideaCount: number;

  constructor(id: string, collection: IdeaCollection, ideaCount: number) {
    this.id = id;
    this.collection = collection;
    this.ideaCount = ideaCount;
  }
}

