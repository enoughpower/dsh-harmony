import { router } from '@kit.ArkUI';

/**
 * 沉浸光感返回按钮（二级页面默认导航）。
 * 样式：半透明光感底 + 毛玻璃 + 轻阴影，点击返回上一页。
 */
@Component
export struct BackButton {
  build() {
    Button() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor($r('app.color.floating_surface'))
    .backdropBlur(24)
    .shadow({
      radius: 8,
      color: '#1F000000',
      offsetY: 1
    })
    .stateEffect(false)
    .onClick(() => {
      router.back();
    })
  }
}
