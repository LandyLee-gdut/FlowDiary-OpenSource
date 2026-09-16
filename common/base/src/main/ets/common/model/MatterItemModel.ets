import { MatterStatus } from './MatterStatus';

export interface MatterItemModelInit {
  id: string;
  title: string;
  label: string;
  labelColor: ResourceColor;
  status: MatterStatus;
  durationInMilliseconds: number;
}

/**
 * 为今日清单UI定制的视图模型 (View Model)。
 * 它聚合了来自 activity, tag, time_record 表的信息，并通过 @Observed
 * 装饰实现响应式更新。
 */
@Observed
export class MatterItemModel {
  id: string = '';
  title: string = '';
  label: string = '';
  labelColor: ResourceColor = '#808080';
  status: MatterStatus = MatterStatus.TODO;
  durationInMilliseconds: number = 0;

  constructor(init?: MatterItemModelInit) {
    if (init) {
      this.apply(init);
    }
  }

  apply(update: Partial<MatterItemModelInit>): void {
    if (update.id !== undefined) {
      this.id = update.id;
    }
    if (update.title !== undefined) {
      this.title = update.title;
    }
    if (update.label !== undefined) {
      this.label = update.label;
    }
    if (update.labelColor !== undefined) {
      this.labelColor = update.labelColor;
    }
    if (update.status !== undefined) {
      this.status = update.status;
    }
    if (update.durationInMilliseconds !== undefined) {
      this.durationInMilliseconds = update.durationInMilliseconds;
    }
  }

  clone(): MatterItemModel {
    return new MatterItemModel({
      id: this.id,
      title: this.title,
      label: this.label,
      labelColor: this.labelColor,
      status: this.status,
      durationInMilliseconds: this.durationInMilliseconds
    });
  }

  static from(source: MatterItemModel | MatterItemModelInit): MatterItemModel {
    if (source instanceof MatterItemModel) {
      return source;
    }
    return new MatterItemModel(source);
  }

  static ensureList(items: Array<MatterItemModel | MatterItemModelInit>): MatterItemModel[] {
    let requiresNormalization = false;
    for (let i = 0; i < items.length; i++) {
      if (!(items[i] instanceof MatterItemModel)) {
        requiresNormalization = true;
        break;
      }
    }

    if (!requiresNormalization) {
      return items as MatterItemModel[];
    }

    const normalized: MatterItemModel[] = [];
    for (let i = 0; i < items.length; i++) {
      normalized.push(MatterItemModel.from(items[i]));
    }
    return normalized;
  }
}
