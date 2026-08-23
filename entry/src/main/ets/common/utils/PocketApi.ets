import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/** 登录结果（含失败细节，便于界面诊断显示） */
interface LoginResult {
  ok: boolean;
  token: string;
  detail: string;
}

/** 会话查询结果（含失败原因，便于界面诊断显示） */
export interface SessionQueryResult {
  info: LatestSessionInfo | null;
  error: string;
  /** 成功时的访问令牌（供服务卡片等其它场景复用） */
  token: string;
}

/** 最新会话摘要（DSH session.list items[0] 的轻量投影） */
export interface LatestSessionInfo {
  title: string;
  updatedAt: number;
  running: boolean;
  turns: number;
  steps: number;
}

/** session.list 响应结构（仅声明用到的字段） */
interface SessionStats {
  turns?: number;
  steps?: number;
}

interface ProjectionValues {
  title?: string;
  sessionStats?: SessionStats;
}

interface Projections {
  values?: ProjectionValues;
}

interface SessionItem {
  sessionId?: string;
  updatedAt?: number;
  running?: boolean;
  projections?: Projections;
}

interface SessionListValue {
  items?: SessionItem[];
}

interface SessionListResultInner {
  ok?: boolean;
  value?: SessionListValue;
}

interface SessionListResult {
  result?: SessionListResultInner;
}

/** client-request RPC 消息体 */
interface ClientRequestMsg {
  type: string;
  rpcId: string;
  method: string;
  payload: Record<string, string>;
}

/**
 * dsh-pocket HTTP 通道封装：LAN PIN 登录 + DSH RPC 调用。
 * 认证走 /pocket-login 拿到的「期望令牌」（sha256(token:sessionKey)），
 * 后续请求以 ?token= 查询参数携带（与网页 Cookie 等价，App 免 cookie jar）。
 */
export class PocketApi {
  /** 进程内缓存的期望令牌（30 天有效；dsh-pocket 重启后失效，届时重新登录） */
  private static expectedToken: string = '';

  /**
   * LAN PIN 登录，返回期望令牌（失败返回空串）。
   * 成功时 Set-Cookie: dsh_pocket_token=<期望令牌>；也可用于 ?token= 参数。
   */
  private static async login(base: string, pin: string): Promise<LoginResult> {
    if (PocketApi.expectedToken.length > 0) {
      const ok: LoginResult = { ok: true, token: PocketApi.expectedToken, detail: '' };
      return ok;
    }
    const b = base.replace(/\/+$/, '');
    const request = http.createHttp();
    try {
      // maxRedirects=0：关闭自动跟随，保留 302 的 Set-Cookie（含期望令牌）
      const loginOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/x-www-form-urlencoded' },
        extraData: 'token=' + encodeURIComponent(pin),
        maxRedirects: 0,
        connectTimeout: 8000,
        readTimeout: 8000
      };
      const resp = await request.request(b + '/pocket-login', loginOptions);
      const value = PocketApi.extractToken(resp);
      if (value.length > 0) {
        PocketApi.expectedToken = value;
        hilog.info(DOMAIN, TAG, 'pocket login ok');
        const ok: LoginResult = { ok: true, token: value, detail: '' };
        return ok;
      }
      hilog.warn(DOMAIN, TAG, 'pocket login: token not found, code=%{public}d', resp.responseCode ?? 0);
      const bad: LoginResult = { ok: false, token: '', detail: 'no-token code=' + String(resp.responseCode ?? 0) };
      return bad;
    } catch (e) {
      const em = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'pocket login failed: code=%{public}d msg=%{public}s', em.code, em.message);
      const bad: LoginResult = { ok: false, token: '', detail: 'code=' + String(em.code ?? -1) + ' ' + (em.message ?? '').slice(0, 80) };
      return bad;
    } finally {
      try {
        request.destroy();
      } catch (e) {
      }
    }
  }

  /** 从响应提取期望令牌：优先 cookies，兜底 set-cookie 头 */
  private static extractToken(resp: http.HttpResponse): string {
    const cookies = resp.cookies ?? [];
    for (const c of cookies) {
      if (c.startsWith('dsh_pocket_token=')) {
        const v = c.substring('dsh_pocket_token='.length).split(';')[0].trim();
        if (v.length > 0) {
          return v;
        }
      }
    }
    try {
      const header = resp.header as Record<string, string>;
      const raw = header['set-cookie'] ?? '';
      const m = raw.match(/dsh_pocket_token=([^;]+)/);
      if (m !== null && m.length > 1) {
        return m[1].trim();
      }
    } catch (e) {
    }
    return '';
  }

  /**
   * 查询最新会话摘要。
   * @param base dsh-pocket 地址（如 http://192.168.5.13:3081）
   * @param pin LAN PIN（默认 11111111）
   * @returns 最新会话信息；失败返回 null
   */
  static async latestSession(base: string, pin: string): Promise<SessionQueryResult> {
    const b = base.replace(/\/+$/, '');
    // 主路：读取 Web 组件的登录 Cookie（手机网页登录过 dsh-pocket 即有）
    let token = '';
    try {
      const ck = webview.WebCookieManager.fetchCookieSync(b);
      const m = ck.match(/dsh_pocket_token=([^;]+)/);
      if (m !== null && m.length > 1) {
        token = m[1].trim();
      }
    } catch (e) {
    }
    if (token.length === 0) {
      // 兜底：PIN 登录（302 重定向受 http 库限制时输出 detail 供排查）
      const login = await PocketApi.login(b, pin);
      if (!login.ok || login.token.length === 0) {
        return { info: null, error: '未登录且登录失败: ' + login.detail + '（请先打开连接网页并输入 PIN）', token: '' };
      }
      token = login.token;
    }
    return PocketApi.querySession(b, token);
  }

  /** 带令牌查询最新会话（服务卡片等外部场景直接使用已保存令牌） */
  static async queryWithToken(base: string, token: string): Promise<SessionQueryResult> {
    return PocketApi.querySession(base.replace(/\/+$/, ''), token);
  }

  private static async querySession(b: string, token: string): Promise<SessionQueryResult> {
    const request = http.createHttp();
    const body: ClientRequestMsg = {
      'type': 'client-request',
      'rpcId': 'dsh-harmony-session',
      'method': 'session.list',
      'payload': {}
    };
    try {
      const resp = await request.request(b + '/api/session.list?token=' + encodeURIComponent(token), {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify(body),
        connectTimeout: 8000,
        readTimeout: 12000
      });
      if (resp.responseCode !== 200) {
        if (resp.responseCode === 401 || resp.responseCode === 403) {
          // 令牌失效：下次重登
          PocketApi.expectedToken = '';
        }
        hilog.warn(DOMAIN, TAG, 'session.list http %{public}d', resp.responseCode ?? 0);
        return { info: null, error: '服务返回 HTTP ' + String(resp.responseCode ?? 0), token: token };
      }
      const text = String(resp.result ?? '');
      const parsed = JSON.parse(text) as SessionListResult;
      const items = parsed.result?.value?.items ?? [];
      if (items.length === 0) {
        return { info: null, error: '无会话数据', token: token };
      }
      return { info: PocketApi.project(items[0]), error: '', token: token };
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'session.list failed: %{public}s', (e as Error).message);
      return { info: null, error: '请求异常: ' + (e as Error).message.slice(0, 60), token: token };
    } finally {
      try {
        request.destroy();
      } catch (e) {
      }
    }
  }

  /** 提取最新会话的轻量字段（items 已按 updatedAt 降序） */
  private static project(item: SessionItem): LatestSessionInfo {
    const stats = item.projections?.values?.sessionStats;
    return {
      title: item.projections?.values?.title ?? '',
      updatedAt: item.updatedAt ?? 0,
      running: item.running === true,
      turns: stats?.turns ?? 0,
      steps: stats?.steps ?? 0
    };
  }
}
