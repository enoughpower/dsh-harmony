import { ConnectionProfile } from '../model/ConnectionProfile';
import { UrlUtils } from '../common/utils/UrlUtils';

/** 相对时间：今天 / 昨天 / 日期 */
function formatRelative(ts: number): string {
  const now = Date.now();
  const day = 24 * 3600 * 1000;
  const diff = now - ts;
  if (diff < day) return '今天';
  if (diff < 2 * day) return '昨天';
  const d = new Date(ts);
  const mm = d.getMonth() + 1;
  return mm + '月' + d.getDate() + '日';
}

/**
 * 历史连接卡片：点击打开，长按删除。
 */
@Component
export struct ConnectionCard {
  profile: ConnectionProfile = new ConnectionProfile();
  onOpen: (url: string) => void = () => {};
  onRemove: (url: string) => void = () => {};
  /** 是否启用长按删除（首页展示禁用，删除在历史页进行） */
  deleteEnabled: boolean = true;

  build() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(UrlUtils.display(this.profile.url, 30))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
        Text('最近使用：' + formatRelative(this.profile.lastUsedAt))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('打开')
        .height(32)
        .fontSize(13)
        .backgroundColor($r('app.color.primary'))
        .onClick(() => {
          this.onOpen(this.profile.url);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_corner_radius'))
    .gesture(LongPressGesture().onAction(() => {
      if (this.deleteEnabled) {
        this.onRemove(this.profile.url);
      }
    }))
  }
}
