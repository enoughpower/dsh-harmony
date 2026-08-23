/**
 * URL 工具：扫码结果 / 手动输入的规范化与校验。
 * 设计要点：
 *  - dsh-pocket 二维码内容为纯 URL（局域网 http://IP:3081 或公网 https://xxx.trycloudflare.com）。
 *  - 兼容用户手输不带协议（如 192.168.1.5:3081）的情况，自动补 http://。
 *  - 只放行 http/https，其余协议一律拒绝。
 */
export class UrlUtils {
  private static readonly SCHEME_RE: RegExp = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//;
  private static readonly HTTP_RE: RegExp = /^https?:\/\//i;
  /**
   * host 形态：域名 / IPv4 / IPv6（[::1]）/ localhost，可带端口。
   * 注意：字符类含 [ ]，用 RegExp 构造器避免 ArkTS 字面量解析差异。
   */
  private static readonly HOST_RE: RegExp = new RegExp('^[a-zA-Z0-9.\\-:\\[\\]]+$');

  /**
   * 规范化 URL。
   * @param raw 扫码或输入的原串
   * @returns 规范化后的 http(s) URL；非法输入返回 null
   */
  static normalize(raw: string): string | null {
    const s = (raw ?? '').trim();
    if (s.length === 0 || s.length > 2048) {
      return null;
    }
    let url = s;
    if (!UrlUtils.SCHEME_RE.test(url)) {
      url = 'http://' + url;
    }
    if (!UrlUtils.HTTP_RE.test(url)) {
      return null;
    }
    const rest = url.replace(UrlUtils.HTTP_RE, '');
    const host = rest.split('/')[0];
    if (host.length === 0 || host.includes(' ') || host.includes('#')) {
      return null;
    }
    if (!UrlUtils.HOST_RE.test(host)) {
      return null;
    }
    // 丢弃可能夹带的控制字符
    const cleaned = url.replace(/[\u0000-\u001f]/g, '');
    return cleaned;
  }

  /** 是否 http/https URL（不校验可达性） */
  static isHttpUrl(raw: string): boolean {
    return UrlUtils.HTTP_RE.test((raw ?? '').trim());
  }

  /** 提取主机名（不含协议与端口，如 192.168.5.13 / example.com） */
  static hostOf(raw: string): string {
    const s = (raw ?? '').replace(UrlUtils.HTTP_RE, '');
    return s.split(':')[0].split('/')[0].split('?')[0];
  }

  /** 展示用摘要：去掉协议前缀，超长截断 */
  static display(raw: string, maxLen: number = 40): string {
    const s = (raw ?? '').replace(UrlUtils.HTTP_RE, '');
    return s.length > maxLen ? s.slice(0, maxLen) + '…' : s;
  }
}
