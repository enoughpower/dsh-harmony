@Entry
@Component
export struct Index {
  build() {
    Column() {
      Text('DSH Harmony Test Shell')
        .fontSize(14)
        .fontColor('#8A8F99')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
