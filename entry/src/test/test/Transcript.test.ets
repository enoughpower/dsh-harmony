import { describe, expect, it } from '@ohos/hypium';
import { buildTranscript } from '../../main/ets/common/utils/Transcript';
import { SessionMessage, SessionImage } from '../../main/ets/common/utils/PocketApi';

export default function transcriptTest() {
  describe('Transcript', () => {
    it('builds_role_labels_with_blank_line_separator', 0, () => {
      const msgs: SessionMessage[] = [
        { role: 'user', text: '你好', images: [] },
        { role: 'assistant', text: '# 标题\n正文', images: [] }
      ];
      expect(buildTranscript(msgs)).assertEqual('【我】\n你好\n\n【AI】\n# 标题\n正文');
    });

    it('appends_image_placeholder_after_text', 0, () => {
      const img: SessionImage = { attachmentId: 'a1', mediaType: 'image/jpeg', name: 'x.jpg' };
      const msgs: SessionMessage[] = [
        { role: 'user', text: '看这张图', images: [img] }
      ];
      expect(buildTranscript(msgs)).assertEqual('【我】\n看这张图\n[图片×1]');
    });

    it('uses_placeholder_when_text_empty', 0, () => {
      const img: SessionImage = { attachmentId: 'a1', mediaType: 'image/jpeg', name: 'x.jpg' };
      const msgs: SessionMessage[] = [
        { role: 'user', text: '', images: [img] }
      ];
      expect(buildTranscript(msgs)).assertEqual('【我】\n[图片×1]');
    });

    it('empty_list_yields_empty_string', 0, () => {
      expect(buildTranscript([])).assertEqual('');
    });
  });
}
