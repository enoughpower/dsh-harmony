/**
 * 服务卡片 UI（2x2）：应用名 + 最近连接 + 在线状态 + 最近使用时间。
 * 受限环境：只读 LocalStorage 数据，不引用业务模块。
 */
@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('appName') appName: string = 'DSH Harmony';
  @LocalStorageProp('lastUrlDisplay') lastUrlDisplay: string = '扫码连接 DSH';
  @LocalStorageProp('lastUrl') lastUrl: string = '';
  @LocalStorageProp('online') online: string = 'unknown';
  @LocalStorageProp('lastUsedLabel') lastUsedLabel: string = '';

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

  build() {
    Column({ space: 5 }) {
      Row() {
        Text(this.appName)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
        Blank()
        Text('🐋')
          .fontSize(14)
      }
      .width('100%')

      Text(this.lastUrlDisplay)
        .fontSize(12)
        .fontColor('#8A8F99')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      this.StatusLine()

      Blank()

      Button('打开 DSH')
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
