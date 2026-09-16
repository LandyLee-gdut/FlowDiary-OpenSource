import { ReflectFlowCardItem } from './ReflectFlowCardService';

export class ReflectFlowCardDataSource implements IDataSource {
  private dataArray: ReflectFlowCardItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.dataArray.length;
  }

  getData(index: number): ReflectFlowCardItem {
    return this.dataArray[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  setItems(items: ReflectFlowCardItem[]): void {
    this.dataArray = items.slice();
    this.notifyDataReload();
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}
