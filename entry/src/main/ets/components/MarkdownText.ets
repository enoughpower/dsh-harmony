
import { parseMarkdown, parseInline, MdBlock, MdInlineNode } from '../common/utils/Markdown';

/**
 * MarkdownText —— 将一段 Markdown 渲染为 ArkUI 富文本。
 * 用于「对话」里的用户/AI 消息气泡，支持标题/段落/代码块/列表/引用/分隔线，
 * 以及行内 **加粗** *斜体* `代码` [链接](url)。
 */
@Component
export struct MarkdownText {
  @Prop text: string = '';
  @StorageLink('osThemeIsDark') osThemeIsDark: boolean = false;

  private codeBg(): string {
    return this.osThemeIsDark ? '#232B38' : '#E6EEFF';
  }
  private codeText(): string {
    return this.osThemeIsDark ? '#7CC7FF' : '#0A84FF';
  }
  private codeBlockBg(): string {
    return this.osThemeIsDark ? '#1B212B' : '#F1F4FA';
  }
  private codeBlockText(): string {
    return this.osThemeIsDark ? '#C3C9D6' : '#1B2B4B';
  }
  private bgStyle(code: boolean): TextBackgroundStyle {
    if (code) {
      return { color: this.codeBg(), radius: 4 };
    }
    return { color: '#00000000', radius: 0 };
  }

  @Builder
  Inline(t: string) {
    ForEach(parseInline(t), (n: MdInlineNode) => {
      Span(n.text)
        .fontSize(13)
        .fontColor(n.code ? this.codeText() : $r('app.color.text_primary'))
        .fontWeight(n.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(n.italic ? FontStyle.Italic : FontStyle.Normal)
        .textBackgroundStyle(this.bgStyle(n.code))
    }, (n: MdInlineNode) => n.text + '|' + (n.bold ? 'b' : '') + (n.italic ? 'i' : '') + (n.code ? 'c' : '') + (n.link ? 'l' : ''))
  }

  @Builder
  Block(b: MdBlock) {
    if (b.kind === 'heading') {
      Text(b.text)
        .fontSize(b.level === 1 ? 18 : (b.level === 2 ? 16 : 15))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    } else if (b.kind === 'para') {
      Text() { this.Inline(b.text) }
        .width('100%')
    } else if (b.kind === 'code') {
      Column() {
        Text(b.text)
          .fontSize(12)
          .fontColor(this.codeBlockText())
          .fontFamily('monospace')
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.codeBlockBg())
      .borderRadius(8)
      .alignItems(HorizontalAlign.Start)
    } else if (b.kind === 'list') {
      Column({ space: 4 }) {
        ForEach(b.items, (it: string, idx: number) => {
          Row({ space: 6 }) {
            Text(b.ordered ? (idx + 1) + '.' : '•')
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(FontWeight.Bold)
            Text() { this.Inline(it) }
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (it: string, idx: number) => it + idx)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (b.kind === 'table') {
      Column({ space: 0 }) {
        ForEach(b.rows, (row: string[], ri: number) => {
          Row() {
            ForEach(row, (cell: string, ci: number) => {
              Text() { this.Inline(cell) }
                .layoutWeight(1)
                .fontSize(12)
                .fontWeight(ri === 0 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor($r('app.color.text_primary'))
                .padding({ left: 6, right: 6, top: 5, bottom: 5 })
                .borderWidth({ right: ci < row.length - 1 ? 1 : 0, bottom: ri < b.rows.length - 1 ? 1 : 0 })
                .borderColor(this.osThemeIsDark ? '#3A414C' : '#E2E5EC')
            }, (cell: string, ci: number) => 'c' + ci)
          }
          .width('100%')
        }, (row: string[], ri: number) => 'r' + ri)
      }
      .width('100%')
      .borderWidth(1)
      .borderColor(this.osThemeIsDark ? '#3A414C' : '#E2E5EC')
      .borderRadius(6)
      .clip(true)
    } else if (b.kind === 'quote') {
      Text() { this.Inline(b.text) }
        .fontColor($r('app.color.text_secondary'))
        .borderWidth({ left: 3 })
        .borderColor({ left: this.osThemeIsDark ? '#3A414C' : '#C9CDD6' })
        .padding({ left: 8 })
        .width('100%')
    } else if (b.kind === 'hr') {
      Divider().strokeWidth(1).color(this.osThemeIsDark ? '#2A2F38' : '#E5E8EF').margin({ top: 4, bottom: 4 })
    }
  }

  build() {
    Column({ space: 6 }) {
      ForEach(parseMarkdown(this.text), (b: MdBlock) => {
        this.Block(b)
      }, (b: MdBlock) => b.kind + b.text.slice(0, 20) + b.items.length)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
