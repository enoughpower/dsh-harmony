import { pushService } from '@kit.PushKit';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ConnectionStore } from './ConnectionStore';
import { AppPrefs } from './AppPrefs';
import { UrlUtils } from '../utils/UrlUtils';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/** push.token 请求体 */
interface PushTokenRpc {
  'type': string;
  'rpcId': string;
  'method': string;
  'payload': PushTokenPayload;
}
interface PushTokenPayload {
  'token': string;
}
interface PushSettingsPayload {
  'pushEnabled': boolean;
  'sessionEnd': boolean;
  'interact': boolean;
}

/**
 * Push Kit 推送 Token：
 * ① 启动时用 pushService.getToken() 获取设备推送令牌
 * ② 上报给电脑端推送器（独立 Node 服务，见 tools/push-notify/）
 * 前置：应用需在 AGC 开通推送服务（否则 getToken 报 1000900012）
 */
export class PushToken {
  /** 从 AGC 开通推送后调用，取得 token */
  static async getToken(): Promise<string> {
    return await pushService.getToken();
  }

  /** 写调试日志（getToken 诊断用） */
  private static logDebug(context: common.Context, msg: string): void {
    try {
      const path = context.filesDir + '/pocket-debug.log';
      let old = '';
      if (fileIo.accessSync(path)) {
        const rf = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE);
        const buf = new ArrayBuffer(16384);
        const n = fileIo.readSync(rf.fd, buf);
        old = n > 0 ? util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf, 0, n)) : '';
        fileIo.closeSync(rf);
      }
      old = old + new Date().toString() + ' PT: ' + msg + '\n';
      if (old.length > 65536) {
        old = old.slice(old.length - 65536);
      }
      const wf = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(wf.fd, old);
      fileIo.closeSync(wf);
    } catch (e) {
    }
  }

  /** 启动时：同步推送开关 → 取 token → 上报给电脑端推送器（总开关关则不上报 token） */
  static async ensureAndReport(context: common.Context): Promise<void> {
    try {
      await PushToken.reportSettings(context);
      const enabled = await AppPrefs.getBool(context, AppPrefs.KEY_PUSH_ENABLED, true);
      if (!enabled) {
        PushToken.logDebug(context, 'push disabled (master off), skip token report');
        return;
      }
      const token = await PushToken.getToken();
      PushToken.logDebug(context, 'getToken ok len=' + token.length);
      hilog.info(DOMAIN, TAG, 'push token obtained len=%{public}d', token.length);
      await PushToken.report(context, token);
    } catch (e) {
      const be = e as BusinessError;
      // 1000900012 = 推送未激活（未在 AGC 开通）；1000900010 = 应用身份非法（指纹/应用配置）
      PushToken.logDebug(context, 'getToken FAILED code=' + be.code + ' msg=' + be.message.slice(0, 120));
      hilog.warn(DOMAIN, TAG, 'getToken failed code=%{public}d msg=%{public}s', be.code, be.message);
    }
  }

  /** 同步推送开关到电脑端推送器：POST /api/push.settings。 */
  static async reportSettings(context: common.Context): Promise<void> {
    try {
      const store = new ConnectionStore();
      const list = await store.loadAll(context);
      if (list.length === 0) {
        return;
      }
      if (UrlUtils.isTunnelHost(list[0].url)) {
        return;
      }
      const host = store.pushHostOf(list);
      const reportBase = host.length > 0 ? 'http://' + host + ':3082' : list[0].url.replace(/\/+$/, '');
      const enabled = await AppPrefs.getBool(context, AppPrefs.KEY_PUSH_ENABLED, true);
      const sessionEnd = await AppPrefs.getBool(context, AppPrefs.KEY_PUSH_SESSION_END, true);
      const interact = await AppPrefs.getBool(context, AppPrefs.KEY_PUSH_INTERACT, true);
      const payload: PushSettingsPayload = { 'pushEnabled': enabled, 'sessionEnd': sessionEnd, 'interact': interact };
      const body = JSON.stringify({ 'type': 'client-request', 'rpcId': 'push-settings-' + Date.now(), 'method': 'push.settings', 'payload': payload });
      const req = http.createHttp();
      try {
        const options: http.HttpRequestOptions = {
          'method': http.RequestMethod.POST,
          'header': { 'Content-Type': 'application/json' },
          'extraData': body,
          'connectTimeout': 5000,
          'readTimeout': 5000
        };
        const resp: http.HttpResponse = await req.request(reportBase + '/api/push.settings', options);
        hilog.info(DOMAIN, TAG, 'push.settings report code=%{public}d', resp.responseCode);
      } catch (e) {
        const be = e as BusinessError;
        hilog.warn(DOMAIN, TAG, 'push.settings report failed %{public}s', be.message);
      } finally {
        req.destroy();
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'push.settings prep failed %{public}s', (e as Error).message);
    }
  }

  /** 上报 token：找最近连接，POST /api/push.token 给电脑端推送器 */
  private static async report(context: common.Context, token: string): Promise<void> {
    const store = new ConnectionStore();
    const list = await store.loadAll(context);
    if (list.length === 0) {
      return;
    }
    // 隧道连接：3082 不在公网/隧道暴露，上报必然失败，直接跳过（token 早已在 LAN 连接时上报并保存在电脑端）
    if (UrlUtils.isTunnelHost(list[0].url)) {
      return;
    }
    // 优先保 LAN 连接：用内网 IP 主机上报（pushHostOf 取最近的内网 IP；无内网时回退最近连接主机）
    const host = store.pushHostOf(list);
    const reportBase = host.length > 0 ? 'http://' + host + ':3082' : list[0].url.replace(/\/+$/, '');
    const rpc: PushTokenRpc = {
      'type': 'client-request',
      'rpcId': 'push-token-' + Date.now(),
      'method': 'push.token',
      'payload': { 'token': token }
    };
    const body = JSON.stringify(rpc);
    const req = http.createHttp();
    try {
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      const options: http.HttpRequestOptions = {
        'method': http.RequestMethod.POST,
        'header': headers,
        'extraData': body,
        'connectTimeout': 5000,
        'readTimeout': 5000
      };
      const resp: http.HttpResponse = await req.request(reportBase + '/api/push.token', options);
      hilog.info(DOMAIN, TAG, 'push.token report code=%{public}d', resp.responseCode);
    } catch (e) {
      const be = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'push.token report failed %{public}s', be.message);
    } finally {
      req.destroy();
    }
  }
}
