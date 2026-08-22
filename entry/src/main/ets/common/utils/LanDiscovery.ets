import { connection, http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/** 发现的局域网 DSH 服务 */
export interface DiscoveredService {
  url: string;
  host: string;
}

/** 本机 IPv4 网段信息 */
export interface SubnetInfo {
  network: string;
  prefix: number;
  localIp: string;
}

/**
 * 局域网自动发现：扫描本机网段的 3081 端口，探测 dsh-pocket 代理特征。
 * 无需服务端配合（dsh-pocket 零改动）：dsh-pocket 对 GET / 返回"DSH Pocket"登录页。
 */
export class LanDiscovery {
  /** dsh-pocket PIN 页特征串 */
  static readonly DSH_SIGNATURE: string = 'DSH Pocket';

  /**
   * 获取本机 IPv4 网段信息。
   * @returns { network: 192.168.5 形式的前缀段, prefix: 前缀长度, localIp }
   */
  static async localIpv4Subnet(): Promise<SubnetInfo | null> {
    try {
      const netHandle = await connection.getDefaultNet();
      const props = await connection.getConnectionProperties(netHandle);
      const links = props.linkAddresses ?? [];
      for (const link of links) {
        const addr = link.address;
        if (addr && addr.family === 1 && typeof addr.address === 'string' &&
          addr.address.length > 0 && !addr.address.startsWith('127.')) {
          const parts = addr.address.split('.');
          if (parts.length === 4) {
            return {
              network: parts[0] + '.' + parts[1] + '.' + parts[2],
              prefix: link.prefixLength ?? 24,
              localIp: addr.address
            };
          }
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'get subnet failed: %{public}s', (e as Error).message);
    }
    return null;
  }

  /**
   * 并发扫描网段 1-254 的 3081 端口，返回匹配 dsh-pocket 特征的服务列表。
   * @param timeoutMs 单次探测超时（默认 700ms）
   */
  static async discover(timeoutMs: number = 700): Promise<DiscoveredService[]> {
    const subnet = await LanDiscovery.localIpv4Subnet();
    if (subnet === null) {
      hilog.warn(DOMAIN, TAG, 'no ipv4 subnet, skip discover');
      return [];
    }
    const base = subnet.network;
    const finalTimeout = subnet.prefix >= 16 ? 600 : timeoutMs; // 非/24 网段适当降超时
    const found: DiscoveredService[] = [];
    const batchSize = 24;
    for (let off = 1; off <= 254; off += batchSize) {
      const batch: number[] = [];
      for (let i = off; i <= Math.min(off + batchSize - 1, 254); i++) {
        batch.push(i);
      }
      const batchResults = await Promise.all(
        batch.map((h: number) => LanDiscovery.probe('http://' + base + '.' + h + ':3081', finalTimeout))
      );
      for (const r of batchResults) {
        if (r !== null) {
          found.push(r);
        }
      }
    }
    if (found.length > 0) {
      hilog.info(DOMAIN, TAG, 'discovered %{public}d service(s)', found.length);
    }
    return found;
  }

  /**
   * 弱探测：目标是否在线（3081 端口可发 HTTP 即在线，不校验特征串）。
   * 用于卡片"在线/离线"状态。
   */
  static async isOnline(url: string, timeoutMs: number = 1200): Promise<boolean> {
    const request = http.createHttp();
    try {
      const resp = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        header: {
          'Accept': '*/*',
          'User-Agent': 'DSH-Harmony/1.3'
        }
      });
      const code = resp.responseCode ?? 0;
      // 200/401/403/404 均视为服务在线；5xx/连接失败视为异常
      return code > 0 && code < 500;
    } catch (e) {
      return false;
    } finally {
      try {
        request.destroy();
      } catch (e) {
      }
    }
  }

  /** 探测单个地址：GET 根路径，响应含 "DSH Pocket" 即命中 */
  private static async probe(url: string, timeoutMs: number): Promise<DiscoveredService | null> {
    const request = http.createHttp();
    try {
      const resp = await request.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        header: {
          'Accept': '*/*',
          'User-Agent': 'DSH-Harmony/1.2'
        }
      });
      let body = '';
      const result = resp.result;
      if (typeof result === 'string') {
        body = result;
      } else if (result instanceof ArrayBuffer) {
        const decoder = new util.TextDecoder('utf-8');
        body = decoder.decodeToString(new Uint8Array(result));
      }
      const hit = body.includes(LanDiscovery.DSH_SIGNATURE);
      hilog.debug(DOMAIN, TAG, 'probe %{public}s code=%{public}d hit=%{public}s', url,
        resp.responseCode ?? 0, hit);
      if (hit) {
        return { url: url, host: url.replace(/^https?:\/\//, '') };
      }
      return null;
    } catch (e) {
      // 连接失败/超时：忽略（该主机无服务）
      return null;
    } finally {
      try {
        request.destroy();
      } catch (e) {
        // 忽略销毁异常
      }
    }
  }
}
