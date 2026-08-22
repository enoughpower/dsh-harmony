import { describe, expect, it } from '@ohos/hypium';
import { UrlUtils } from '../../../main/ets/common/utils/UrlUtils';

export default function urlUtilsTest() {
  describe('UrlUtils', () => {
    it('normalize_plain_ip_with_port', 0, () => {
      const r = UrlUtils.normalize('192.168.1.5:3081');
      expect(r).assertEqual('http://192.168.1.5:3081');
    });

    it('normalize_full_lan_url', 0, () => {
      const r = UrlUtils.normalize('http://192.168.1.5:3081');
      expect(r).assertEqual('http://192.168.1.5:3081');
    });

    it('normalize_https_tunnel', 0, () => {
      const r = UrlUtils.normalize('https://abc.trycloudflare.com');
      expect(r).assertEqual('https://abc.trycloudflare.com');
    });

    it('normalize_keeps_path', 0, () => {
      const r = UrlUtils.normalize('http://192.168.1.5:3081/mobile');
      expect(r).assertEqual('http://192.168.1.5:3081/mobile');
    });

    it('normalize_trim_spaces', 0, () => {
      const r = UrlUtils.normalize('  http://192.168.1.5:3081  ');
      expect(r).assertEqual('http://192.168.1.5:3081');
    });

    it('normalize_empty_rejected', 0, () => {
      expect(UrlUtils.normalize('')).assertNull();
      expect(UrlUtils.normalize('   ')).assertNull();
    });

    it('normalize_non_http_scheme_rejected', 0, () => {
      expect(UrlUtils.normalize('ftp://192.168.1.5:21')).assertNull();
      expect(UrlUtils.normalize('file:///etc/passwd')).assertNull();
      expect(UrlUtils.normalize('javascript:alert(1)')).assertNull();
    });

    it('normalize_bad_host_rejected', 0, () => {
      expect(UrlUtils.normalize('http://has space/')).assertNull();
      expect(UrlUtils.normalize('http://')).assertNull();
      expect(UrlUtils.normalize('http://#frag')).assertNull();
    });

    it('normalize_host_with_dash', 0, () => {
      const r = UrlUtils.normalize('my-dsh.local:3081');
      expect(r).assertEqual('http://my-dsh.local:3081');
    });

    it('isHttpUrl_basic', 0, () => {
      expect(UrlUtils.isHttpUrl('http://a.b')).assertTrue();
      expect(UrlUtils.isHttpUrl('https://a.b')).assertTrue();
      expect(UrlUtils.isHttpUrl('ftp://a.b')).assertFalse();
      expect(UrlUtils.isHttpUrl('')).assertFalse();
    });

    it('display_truncates_and_strips_scheme', 0, () => {
      const long = 'http://' + 'a'.repeat(100) + '.example.com';
      const d = UrlUtils.display(long, 20);
      expect(d.length).assertLTE(21);
      expect(d.startsWith('http://')).assertFalse();
    });
  });
}
