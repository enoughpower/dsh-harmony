
/**
 * Markdown.ets —— 轻量 Markdown 解析器（ArkTS strict 安全）。
 * 把 md 文本解析为「块」+「行内样式」，供 ArkUI 用 Text/Span 渲染。
 * 支持：标题(#/##/###)、段落、代码块(```)、有序/无序列表、引用(>)、分隔线(---)、
 * 表格(| 表头 | 表头 |  + 分隔行 + | 行 |)，
 * 行内样式：**加粗** *斜体* `行内代码` [链接](url) 。
 */

export interface MdBlock {
  kind: string;        // 'heading' | 'para' | 'code' | 'list' | 'quote' | 'hr' | 'table'
  level: number;       // 标题级别 1..3
  ordered: boolean;    // 是否有序列表
  text: string;        // heading/para/quote 的原文
  items: string[];     // list 项
  lang: string;        // 代码块语言
  rows: string[][];    // 表格行（含表头行）；kind==='table' 时使用
}

export interface MdInlineNode {
  text: string;
  bold: boolean;
  italic: boolean;
  code: boolean;
  link: string;
}

function makeBlock(kind: string, text: string, level: number, ordered: boolean,
  items: string[], lang: string): MdBlock {
  const arr: string[] = [];
  for (const it of items) {
    arr.push(it);
  }
  return {
    kind: kind, level: level, ordered: ordered, text: text, items: arr, lang: lang, rows: []
  };
}

function makeInline(text: string, bold: boolean, italic: boolean, code: boolean, link: string): MdInlineNode {
  return { text: text, bold: bold, italic: italic, code: code, link: link };
}

function headingLevel(s: string): number {
  let n = 0;
  while (n < s.length && s.charCodeAt(n) === 35) { // '#'
    n++;
  }
  if (n > 0 && n <= 3 && n < s.length && s.charAt(n) === ' ') {
    return n;
  }
  return 0;
}

function isListStart(s: string): boolean {
  if (s.length === 0) {
    return false;
  }
  const c0: string = s.charAt(0);
  if (c0 === '-' || c0 === '*' || c0 === '+') {
    return s.length > 1 && s.charAt(1) === ' ';
  }
  if (c0 >= '0' && c0 <= '9') {
    let i = 0;
    while (i < s.length && s.charCodeAt(i) >= 48 && s.charCodeAt(i) <= 57) {
      i++;
    }
    if (i < s.length && (s.charAt(i) === '.' || s.charAt(i) === ')') && i + 1 < s.length && s.charAt(i + 1) === ' ') {
      return true;
    }
  }
  return false;
}

function isHr(s: string): boolean {
  // --- 或 *** 或 ___
  if (s.length < 3) {
    return false;
  }
  const c0: string = s.charAt(0);
  if (c0 !== '-' && c0 !== '*' && c0 !== '_') {
    return false;
  }
  for (let i = 1; i < s.length; i++) {
    if (s.charAt(i) !== c0) {
      return false;
    }
  }
  return true;
}

function isBlockStart(s: string): boolean {
  return headingLevel(s) > 0 || s.startsWith('```') || isListStart(s) || s.startsWith('>') || isHr(s) || isTableRow(s);
}

/** 拆一行表格为单元格数组（忽略行内代码里的 |）。 */
function tableCells(s: string): string[] {
  let t = s.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|')) t = t.substring(0, t.length - 1);
  const cells: string[] = [];
  let start = 0;
  let inCode = false;
  for (let k = 0; k <= t.length; k++) {
    const ch: string = k < t.length ? t.charAt(k) : '|';
    if (ch === '`') inCode = !inCode;
    if (ch === '|' && !inCode) {
      cells.push(t.substring(start, k).trim());
      start = k + 1;
    }
  }
  return cells;
}

/** 是否为表格行：以 | 开头以 | 结尾且含第二个 |。 */
function isTableRow(s: string): boolean {
  const t = s.trim();
  if (t.length < 3 || t.charAt(0) !== '|' || t.charAt(t.length - 1) !== '|') {
    return false;
  }
  return t.indexOf('|', 1) >= 0;
}

/** 是否为表格分隔行（| --- | --- | 之类）。 */
function isTableSep(s: string): boolean {
  const cells = tableCells(s);
  if (cells.length === 0) return false;
  for (const c of cells) {
    if (!/^:?-+:?$/.test(c)) return false;
  }
  return true;
}

function makeTableBlock(rows: string[][]): MdBlock {
  const out: string[][] = [];
  for (const r of rows) {
    const rr: string[] = [];
    for (const c of r) rr.push(c);
    out.push(rr);
  }
  const b: MdBlock = makeBlock('table', '', 0, false, [], '');
  b.rows = out;
  return b;
}

/** 按行解析为块序列。 */
export function parseMarkdown(md: string): MdBlock[] {
  const blocks: MdBlock[] = [];
  const lines = md.split('\n');
  const n = lines.length;
  let i = 0;
  while (i < n) {
    const raw = lines[i];
    const t = raw.trim();
    if (t.length === 0) {
      i++;
      continue;
    }
    // 代码块
    if (t.startsWith('```')) {
      const lang = t.substring(3).trim();
      const codeLines: string[] = [];
      i++;
      while (i < n && !lines[i].trim().startsWith('```')) {
        codeLines.push(lines[i]);
        i++;
      }
      i++; // 跳过结束
      blocks.push(makeBlock('code', codeLines.join('\n'), 0, false, [], lang));
      continue;
    }
    // 标题
    const hl = headingLevel(raw);
    if (hl > 0) {
      const text = raw.substring(hl).trim().replace(/^#+/, '').trim();
      blocks.push(makeBlock('heading', text, hl, false, [], ''));
      i++;
      continue;
    }
    // 分隔线
    if (isHr(t)) {
      blocks.push(makeBlock('hr', '', 0, false, [], ''));
      i++;
      continue;
    }
    // 引用
    if (t.startsWith('>')) {
      const q: string[] = [];
      while (i < n && lines[i].trim().startsWith('>')) {
        q.push(lines[i].trim().replace(/^>\s?/, ''));
        i++;
      }
      blocks.push(makeBlock('quote', q.join(' ').replace(/\s+/g, ' '), 0, false, [], ''));
      continue;
    }
    // 列表
    if (isListStart(t)) {
      const ordered = /^[0-9]+[.)]\s/.test(t);
      const items: string[] = [];
      while (i < n && isListStart(lines[i].trim())) {
        const lt = lines[i].trim();
        const item = lt.replace(/^[-*+]\s+/, '').replace(/^[0-9]+[.)]\s+/, '');
        items.push(item);
        i++;
      }
      blocks.push(makeBlock('list', '', 0, ordered, items, ''));
      continue;
    }
    // 表格：表头行 + 分隔行
    if (isTableRow(t) && i + 1 < n && isTableSep(lines[i + 1])) {
      const rows: string[][] = [];
      rows.push(tableCells(raw));
      i++;
      i++;
      while (i < n && isTableRow(lines[i])) {
        rows.push(tableCells(lines[i]));
        i++;
      }
      blocks.push(makeTableBlock(rows));
      continue;
    }
    // 段落：累积到空行或新的块标记
    const para: string[] = [];
    while (i < n) {
      const cl = lines[i];
      const ct = cl.trim();
      if (ct.length === 0 || isBlockStart(ct)) {
        break;
      }
      para.push(cl);
      i++;
    }
    blocks.push(makeBlock('para', para.join(' ').replace(/\s+/g, ' '), 0, false, [], ''));
  }
  return blocks;
}

/** 解析行内样式：**加粗** *斜体* `代码` [链接](url) 。 */
export function parseInline(text: string): MdInlineNode[] {
  const nodes: MdInlineNode[] = [];
  const buf: string[] = [];
  const flush = (): void => {
    if (buf.length > 0) {
      nodes.push(makeInline(buf.join(''), false, false, false, ''));
      buf.length = 0;
    }
  };
  let i = 0;
  const len = text.length;
  while (i < len) {
    const ch = text.charAt(i);
    // 行内代码 `...`
    if (ch.charCodeAt(0) === 96) {
      const end = text.indexOf('`', i + 1);
      if (end > i) {
        flush();
        nodes.push(makeInline(text.substring(i + 1, end), false, false, true, ''));
        i = end + 1;
        continue;
      }
    }
    // 加粗 **...**
    if (ch === '*' && i + 1 < len && text.charAt(i + 1) === '*') {
      const end = text.indexOf('**', i + 2);
      if (end > i) {
        flush();
        nodes.push(makeInline(text.substring(i + 2, end), true, false, false, ''));
        i = end + 2;
        continue;
      }
    }
    // 链接 [label](url)
    if (ch === '[') {
      const close = text.indexOf('](', i);
      if (close > i) {
        const paren = text.indexOf(')', close + 2);
        if (paren > close) {
          flush();
          const label = text.substring(i + 1, close);
          const url = text.substring(close + 2, paren);
          nodes.push(makeInline(label, false, false, false, url));
          i = paren + 1;
          continue;
        }
      }
    }
    // 斜体 *...*
    if (ch === '*') {
      const end = text.indexOf('*', i + 1);
      if (end > i) {
        flush();
        nodes.push(makeInline(text.substring(i + 1, end), false, true, false, ''));
        i = end + 1;
        continue;
      }
    }
    buf.push(ch);
    i++;
  }
  flush();
  return nodes;
}
