import { SessionMessage } from './PocketApi';

/**
 * Transcript —— 会话消息转纯文本。
 * 供会话详情页「复制全部」写入系统剪贴板；纯逻辑无 UI 依赖，便于单测。
 */

/** 消息角色标签：assistant -> AI，其余（user）-> 我。 */
function roleLabel(role: string): string {
  return role === 'assistant' ? 'AI' : '我';
}

/**
 * 把消息列表拼成可读纯文本：每条为「【角色】\n内容」，消息间空行分隔。
 * 消息含图片时在正文末尾追加「[图片×N]」占位（图片二进制不入剪贴板）。
 */
export function buildTranscript(messages: SessionMessage[]): string {
  const parts: string[] = [];
  for (const m of messages) {
    let body: string = m.text;
    if (m.images.length > 0) {
      const tag: string = '[图片×' + m.images.length + ']';
      body = body.length > 0 ? body + '\n' + tag : tag;
    }
    parts.push('【' + roleLabel(m.role) + '】\n' + body);
  }
  return parts.join('\n\n');
}
