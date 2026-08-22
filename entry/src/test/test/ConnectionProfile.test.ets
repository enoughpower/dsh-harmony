import { describe, expect, it } from '@ohos/hypium';
import { ConnectionProfile } from '../../../main/ets/model/ConnectionProfile';

export default function connectionProfileTest() {
  describe('ConnectionProfile', () => {
    it('constructor_fills_title_from_url', 0, () => {
      const p = new ConnectionProfile('http://192.168.1.5:3081');
      expect(p.url).assertEqual('http://192.168.1.5:3081');
      expect(p.title).assertEqual('http://192.168.1.5:3081');
      expect(p.addedAt > 0).assertTrue();
      expect(p.lastUsedAt).assertEqual(p.addedAt);
    });

    it('toStored_roundtrip', 0, () => {
      const p = new ConnectionProfile('https://abc.trycloudflare.com', '我的 DSH');
      const stored = p.toStored();
      const back = ConnectionProfile.fromStored(stored);
      expect(back).assertNotNull();
      if (back !== null) {
        expect(back.url).assertEqual('https://abc.trycloudflare.com');
        expect(back.title).assertEqual('我的 DSH');
        expect(back.addedAt).assertEqual(p.addedAt);
        expect(back.lastUsedAt).assertEqual(p.lastUsedAt);
      }
    });

    it('fromStored_invalid_returns_null', 0, () => {
      expect(ConnectionProfile.fromStored({ 'url': '' })).assertNull();
      expect(ConnectionProfile.fromStored({})).assertNull();
      expect(ConnectionProfile.fromStored({ 'url': 123 })).assertNull();
    });

    it('fromStored_missing_optional_fields', 0, () => {
      const p = ConnectionProfile.fromStored({ 'url': 'http://x:1' });
      expect(p).assertNotNull();
      if (p !== null) {
        expect(p.title).assertEqual('http://x:1');
        expect(p.addedAt).assertEqual(0);
        expect(p.lastUsedAt).assertEqual(0);
      }
    });
  });
}
