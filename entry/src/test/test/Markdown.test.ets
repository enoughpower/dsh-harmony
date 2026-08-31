import { describe, expect, it } from '@ohos/hypium';
import { parseMarkdown, MdBlock } from '../../main/ets/common/utils/Markdown';

export default function markdownTest() {
  describe('Markdown', () => {
    it('parse_table_rows', 0, () => {
      const blocks: MdBlock[] = parseMarkdown('| 序号 | 平方 |\n|---|---|\n| 1 | 1 |\n| 2 | 4 |');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('table');
      expect(blocks[0].rows.length).assertEqual(3);
      expect(blocks[0].rows[0][0]).assertEqual('序号');
      expect(blocks[0].rows[0][1]).assertEqual('平方');
      expect(blocks[0].rows[1][0]).assertEqual('1');
      expect(blocks[0].rows[1][1]).assertEqual('1');
      expect(blocks[0].rows[2][0]).assertEqual('2');
      expect(blocks[0].rows[2][1]).assertEqual('4');
    });

    it('parse_pipe_para_not_table', 0, () => {
      const blocks: MdBlock[] = parseMarkdown('colA | colB');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].kind).assertEqual('para');
    });

    it('parse_heading_then_table', 0, () => {
      const blocks: MdBlock[] = parseMarkdown('# 标题\n\n| A | B |\n|---|---|\n| 1 | 2 |');
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].kind).assertEqual('heading');
      expect(blocks[1].kind).assertEqual('table');
      expect(blocks[1].rows[0][0]).assertEqual('A');
      expect(blocks[1].rows[1][1]).assertEqual('2');
    });
  });
}
