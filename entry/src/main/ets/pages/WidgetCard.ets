/**
 * 服务卡片 UI（2x2）：应用名 + 最近连接/会话 + 在线状态。
 * 受限环境：只读 LocalStorage 数据，不引用业务模块。
 */
@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('appName') appName: string = '口袋工作台';
  @LocalStorageProp('lastUrlDisplay') lastUrlDisplay: string = '扫码连接工作台';
  @LocalStorageProp('lastUrl') lastUrl: string = '';
  @LocalStorageProp('online') online: string = 'unknown';
  @LocalStorageProp('lastUsedLabel') lastUsedLabel: string = '';
  @LocalStorageProp('sessionTitle') sessionTitle: string = '';
  @LocalStorageProp('sessionStatus') sessionStatus: string = '';
  @LocalStorageProp('sessionMeta') sessionMeta: string = '';

  @Builder
  StatusLine() {
    Row({ space: 4 }) {
      if (this.online === 'online') {
        Circle({ width: 8, height: 8 })
          .fill('#34C759')
        Text('在线')
          .fontSize(11)
          .fontColor('#34C759')
      } else if (this.online === 'offline') {
        Circle({ width: 8, height: 8 })
          .fill('#A0A4AC')
        Text('离线')
          .fontSize(11)
          .fontColor('#A0A4AC')
      } else {
        Circle({ width: 8, height: 8 })
          .fill('#A0A4AC')
        Text('未检测')
          .fontSize(11)
          .fontColor('#A0A4AC')
      }
      if (this.lastUsedLabel.length > 0) {
        Text('· ' + this.lastUsedLabel)
          .fontSize(11)
          .fontColor('#8A8F99')
      }
    }
    .width('100%')
  }

  private onlineStateText(): string {
    if (this.online === 'online') {
      return '在线';
    }
    if (this.online === 'offline') {
      return '离线';
    }
    return '未检测';
  }

  build() {
    Column({ space: 4 }) {
      Row() {
        Text(this.appName)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
        Blank()
        Image($r('app.media.widget_whale'))
          .width(26)
          .height(26)
          .objectFit(ImageFit.Contain)
      }
      .width('100%')

      if (this.sessionTitle.length > 0) {
        Text(this.sessionTitle)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.sessionStatus)
          .fontSize(10)
          .fontColor('#1A1A1A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.sessionMeta + ' · ' + this.onlineStateText())
          .fontSize(10)
          .fontColor('#8A8F99')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      } else {
        Text(this.lastUrlDisplay)
          .fontSize(12)
          .fontColor('#8A8F99')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        this.StatusLine()
      }

      Blank()

      Button('打开工作台')
        .width('100%')
        .height(28)
        .fontSize(12)
        .backgroundColor('#4D6BFE')
        .fontColor(Color.White)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            bundleName: 'com.dsh.lite',
            abilityName: 'EntryAbility',
            params: {
              'dshUrl': this.lastUrl
            }
          });
        })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F7F8FA')
  }
}
