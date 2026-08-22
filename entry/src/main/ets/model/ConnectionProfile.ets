/**
 * 连接记录模型：一次扫码/手动输入保存一条。
 * 序列化契约（与 ConnectionStore 共同维护，改动需同步迁移逻辑）：
 * { url, title, addedAt, lastUsedAt }
 */
export class ConnectionProfile {
  url: string = '';
  title: string = '';
  addedAt: number = 0;
  lastUsedAt: number = 0;

  constructor(url: string = '', title: string = '') {
    this.url = url;
    this.title = title.length > 0 ? title : url;
    this.addedAt = Date.now();
    this.lastUsedAt = this.addedAt;
  }

  /** 从 Preferences 反序列化（手动字段读取，避免 ArkTS 对 JSON.parse 的类型陷阱） */
  static fromStored(raw: Record<string, Object>): ConnectionProfile | null {
    const url = raw['url'];
    if (typeof url !== 'string' || url.length === 0) {
      return null;
    }
    const p = new ConnectionProfile();
    p.url = url;
    const title = raw['title'];
    p.title = typeof title === 'string' && title.length > 0 ? title : url;
    const addedAt = raw['addedAt'];
    p.addedAt = typeof addedAt === 'number' ? addedAt : 0;
    const lastUsedAt = raw['lastUsedAt'];
    p.lastUsedAt = typeof lastUsedAt === 'number' ? lastUsedAt : 0;
    return p;
  }

  /** 序列化为可存储结构 */
  toStored(): Record<string, Object> {
    return {
      'url': this.url,
      'title': this.title,
      'addedAt': this.addedAt,
      'lastUsedAt': this.lastUsedAt
    };
  }
}
