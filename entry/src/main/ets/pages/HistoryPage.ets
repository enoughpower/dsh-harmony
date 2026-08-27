import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ConnectionProfile } from '../model/ConnectionProfile';
import { ConnectionStore } from '../common/store/ConnectionStore';
import { CardSync } from '../common/store/CardSync';
import { UrlUtils } from '../common/utils/UrlUtils';
import { BackButton } from '../components/BackButton';
import { WindowBar } from '../common/utils/WindowBar';

/**
 * 连接历史页：按 IP 去重、时间倒序，列表左滑删除，点击直达连接。
 */
@Entry
@Component
struct HistoryPage {
  @State entries: ConnectionProfile[] = [];
  /** 状态栏高度（沉浸式内容留白，不挡状态栏） */
  @State statusBarH: number = 28;
  @State bottomBarH: number = 0;
  private store: ConnectionStore = new ConnectionStore();

  aboutToAppear(): void {
    this.reload();
  }

  onPageShow(): void {
    this.reload();
    // 实测状态栏高度（沉浸式由 EntryAbility 全局设置）
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowBar.statusBarHeight(ctx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.statusBarH = h > 0 ? h : this.statusBarH;
    });
    WindowBar.bottomBarHeight(ctx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.bottomBarH = h > 0 ? h : this.bottomBarH;
    });
  }

  private reload(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.loadDistinctByIp(ctx).then((list: ConnectionProfile[]) => {
      this.entries = list;
    }).catch(() => {
      this.entries = [];
    });
  }

  private open(url: string): void {
    const normalized = UrlUtils.normalize(url);
    if (normalized === null) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.upsert(ctx, new ConnectionProfile(normalized, UrlUtils.display(normalized, 32))).catch(() => {
    });
    router.pushUrl({ url: 'pages/WebShell', params: { 'url': normalized } });
  }

  private remove(profile: ConnectionProfile): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.remove(ctx, profile.url).then(() => {
      this.reload();
      promptAction.showToast({ message: '已删除 ' + UrlUtils.hostOf(profile.url) });
    }).catch(() => {
    });
  }

  @Builder
  DeleteAction(item: ConnectionProfile) {
    Button('删除')
      .height(56)
      .width(76)
      .fontSize(14)
      .fontColor('#FFFFFF')
      .backgroundColor('#E5484D')
      .onClick(() => {
        this.remove(item);
      })
  }

  @Builder
  Header() {
    Row({ space: 12 }) {
      BackButton()
      Column({ space: 2 }) {
        Text('连接历史')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('按 IP 去重 · 最近使用倒序')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  build() {
    Column() {
      this.Main()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  Main() {
    Column({ space: 16 }) {
      this.Header()

      if (this.entries.length === 0) {
        Column({ space: 8 }) {
          Text('还没有连接记录')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('扫码连接或设置页扫描局域网后，地址会出现在这里')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 80, bottom: 80 })
      } else {
        List({ space: 12 }) {
          ForEach(this.entries, (item: ConnectionProfile) => {
            ListItem() {
              Row() {
                Column({ space: 4 }) {
                  Text(UrlUtils.hostOf(item.url))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.url + ' · ' + CardSync.relativeLabel(item.lastUsedAt))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text('打开')
                  .fontSize(13)
                  .fontColor($r('app.color.primary'))
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius($r('app.float.card_corner_radius'))
              .onClick(() => {
                this.open(item.url);
              })
            }
            .swipeAction({
              end: this.DeleteAction(item)
            })
          }, (item: ConnectionProfile) => item.url)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: this.statusBarH + 16, bottom: this.bottomBarH + 28 })
    .backgroundColor($r('app.color.page_background'))
  }
}
