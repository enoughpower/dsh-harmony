/**
 * 手动输入连接地址对话框。
 * 兼容输入：http://192.168.1.5:3081 / 192.168.1.5:3081 / https://xxx.trycloudflare.com
 */
@CustomDialog
export struct UrlInputDialog {
  controller: CustomDialogController;
  @State input: string = '';
  onConfirm: (url: string) => void = () => {};

  build() {
    Column({ space: 16 }) {
      Text('手动输入连接地址')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      TextInput({ placeholder: 'http://192.168.1.5:3081', text: this.input })
        .height(44)
        .fontSize(15)
        .onChange((value: string) => {
          this.input = value;
        })

      Text('提示：填 dsh-pocket 设置页显示的地址，或你的公网隧道地址')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_surface'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.controller.close();
          })
        Button('连接')
          .layoutWeight(1)
          .backgroundColor($r('app.color.primary'))
          .onClick(() => {
            this.onConfirm(this.input);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
  }
}
