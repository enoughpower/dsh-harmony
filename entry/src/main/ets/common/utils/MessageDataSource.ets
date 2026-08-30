
import { SessionMessage } from './PocketApi';

/**
 * MessageDataSource —— LazyForEach 数据源。
 * 只在可见区域附近构建 ListItem,滚动更流畅;内容变化时用 update() 通知重载。
 */
export class MessageDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private messages: SessionMessage[] = [];

  totalCount(): number {
    return this.messages.length;
  }

  getData(index: number): SessionMessage {
    return this.messages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  /** 整体替换消息并通知 LazyForEach 重载。 */
  update(list: SessionMessage[]): void {
    const arr: SessionMessage[] = [];
    for (const m of list) {
      arr.push(m);
    }
    this.messages = arr;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }
}
