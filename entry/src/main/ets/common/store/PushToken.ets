import { pushService } from '@kit.PushKit';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ConnectionStore } from './ConnectionStore';

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

  /** 启动时：取 token → 上报给电脑端推送器 */
  static async ensureAndReport(context: common.Context): Promise<void> {
    try {
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

  /** 上报 token：找最近连接，POST /api/push.token 给电脑端推送器 */
  private static async report(context: common.Context, token: string): Promise<void> {
    const list = await new ConnectionStore().loadAll(context);
    if (list.length === 0) {
      return;
    }
    const base = list[0].url.replace(/\/+$/, '');
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
      const resp: http.HttpResponse = await req.request(base + '/api/push.token', options);
      hilog.info(DOMAIN, TAG, 'push.token report code=%{public}d', resp.responseCode);
    } catch (e) {
      const be = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'push.token report failed %{public}s', be.message);
    } finally {
      req.destroy();
    }
  }
}
