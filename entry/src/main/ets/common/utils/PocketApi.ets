import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

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
  sessionId: string;
  title: string;
  updatedAt: number;
  running: boolean;
  turns: number;
  steps: number;
  phase: string;
  objective: string;
}

/** 任务列表项（session.list 全量投影） */
export interface TaskInfo {
  sessionId: string;
  title: string;
  updatedAt: number;
  running: boolean;
  /** goal 阶段：active / paused / complete / '' */
  phase: string;
  turns: number;
  steps: number;
  objective: string;
}

export interface TaskListResult {
  tasks: TaskInfo[];
  error: string;
  token: string;
}

export interface ControlResult {
  ok: boolean;
  error: string;
}

export interface SessionImage {
  attachmentId: string;
  mediaType: string;
  name: string;
}

export interface SessionMessage {
  role: string;
  text: string;
  images: SessionImage[];
}

interface FoldedMsg {
  text: string;
  images: SessionImage[];
}

export interface SessionHistoryResult {
  messages: SessionMessage[];
  error: string;
}

export interface AttachmentResult {
  ok: boolean;
  data: string;
  mediaType: string;
  error: string;
}

export interface PromptContentPart {
  type: string;
  text?: string;
  mediaType?: string;
  data?: string;
  name?: string;
}

interface HistoryMsgAttachment {
  attachmentId?: string;
  mediaType?: string;
  name?: string;
}
interface HistoryMsgTextPart {
  type?: string;
  text?: string;
  attachment?: HistoryMsgAttachment;
}
interface HistoryRecordDataMsg {
  role?: string;
  content?: HistoryMsgTextPart[] | string;
}
interface HistoryRecordData {
  role?: string;
  content?: HistoryMsgTextPart[] | string;
  message?: HistoryRecordDataMsg;
}
interface HistoryRecordEvent {
  type?: string;
  data?: HistoryRecordData;
}
interface HistoryRecord {
  type?: string;
  event?: HistoryRecordEvent;
}

export interface SearchResult {
  sessionId: string;
  snippet: string;
}

export interface SearchResultSet {
  results: SearchResult[];
  error: string;
}

interface SearchItemValue {
  sessionId?: string;
  snippet?: string;
}

/** session.list 响应结构（仅声明用到的字段） */
interface SessionStats {
  turns?: number;
  steps?: number;
}

interface SessionGoalInner {
  phase?: string;
  objective?: string;
}
interface SessionGoal {
  goal?: SessionGoalInner;
}
interface ProjectionValues {
  title?: string;
  sessionStats?: SessionStats;
  goal?: SessionGoal;
}

interface Projections {
  values?: ProjectionValues;
}

interface SessionItem {
  sessionId?: string;
  updatedAt?: number;
  running?: boolean;
  blank?: boolean;
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

/** session/search 响应 */
interface SearchValue {
  items?: SearchItemValue[];
}
interface SearchResultBody {
  value?: SearchValue;
}
interface SearchResultWire {
  result?: SearchResultBody;
}

/** session/page 响应（历史记录） */
interface PageValue {
  records?: HistoryRecord[];
}
interface PageResultBody {
  ok?: boolean;
  value?: PageValue;
}
interface PageResultWire {
  result?: PageResultBody;
}

/** session/attachment 响应 */
interface AttachmentMeta {
  mediaType?: string;
}
interface AttachmentBody {
  data?: string;
  attachment?: AttachmentMeta;
}
interface AttachmentResultBody {
  ok?: boolean;
  value?: AttachmentBody;
}
interface AttachmentResultWire {
  result?: AttachmentResultBody;
}

/** client-request RPC 消息体 */
interface ClientRequestMsg {
  type: string;
  rpcId: string;
  method: string;
  payload: Record<string, Object>;
}

/**
 * dsh-pocket HTTP 通道封装。
 *
 * 适配新版 dsh web / dsh-pocket（typert gateway + issue #77 会话 cookie）：
 *   - 代理层（dsh-pocket PIN）：以 ?token=<明文 PIN> 认证；
 *   - DSH web 层（issue #77）：转发 ArkWeb 已登录的 dsh-auth-* 会话 cookie；
 *   - RPC：POST /api/<namespace>/<method>（斜杠）+ payload:{args:{...}}。
 */
/** 鉴权参数：tokenQuery=明文 PIN；cookie=dsh-auth-* 会话 cookie */
interface AuthParam {
  tokenQuery: string;
  cookie: string;
}

/** RPC 调用结果 */
interface RpcResult {
  code: number;
  text: string;
}

/** DSH 会话地址（session/page 等用） */
interface SessionAddress {
  kind: string;
  sessionId: string;
}

export class PocketApi {
  /** 进程内缓存的期望令牌（旧哈希模型，新版不再使用；保留向下兼容） */
  private static expectedToken: string = '';

  /** 组装请求鉴权：tokenQuery=明文 PIN（过代理层）；cookie=dsh-auth-*（过 DSH web 层） */
  private static auth(base: string, pin: string): AuthParam {
    const b = base.replace(/\/+$/, '');
    let cookie = '';
    try {
      const ck = webview.WebCookieManager.fetchCookieSync(b);
      const keep: string[] = [];
      for (const part of ck.split(';')) {
        const p = part.trim();
        if (p.length > 0 && p.startsWith('dsh-auth-')) {
          keep.push(p);
        }
      }
      cookie = keep.join('; ');
    } catch (e) {
    }
    return { tokenQuery: encodeURIComponent(pin), cookie };
  }

  /** 供详情页 WS 复用：读取 ArkWeb 里已登录的 dsh-auth-* 会话 cookie（DSH web issue #77）。 */
  static getDshAuthCookie(base: string): string {
    return PocketApi.auth(base, '').cookie;
  }

  /** 发起一次新协议 RPC：POST /api/<endpoint>?token=... 携带 dsh-auth cookie。 */
  private static async rpc(
    base: string,
    pin: string,
    endpoint: string,
    rpcId: string,
    field: string,
    args: Record<string, Object>,
    readTimeout: number = 12000,
  ): Promise<RpcResult> {
    const b = base.replace(/\/+$/, '');
    const auth = PocketApi.auth(b, pin);
    const request = http.createHttp();
    const argsWrap: Record<string, Object> = {};
    argsWrap[field] = args;
    const body: ClientRequestMsg = {
      'type': 'client-request',
      'rpcId': rpcId,
      'method': endpoint,
      'payload': { 'args': argsWrap }
    };
    try {
      const header: Record<string, string> = { 'Content-Type': 'application/json' };
      if (auth.cookie.length > 0) {
        header['Cookie'] = auth.cookie;
      }
      const resp = await request.request(b + '/api/' + endpoint + '?token=' + auth.tokenQuery, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        connectTimeout: 8000,
        readTimeout: readTimeout
      });
      try {
        request.destroy();
      } catch (e) {
      }
      return { code: resp.responseCode ?? 0, text: String(resp.result ?? '') };
    } catch (e) {
      try {
        request.destroy();
      } catch (e2) {
      }
      const em = e as BusinessError;
      return { code: em.code ?? -1, text: '请求异常: ' + (em.message ?? '').slice(0, 60) };
    }
  }

  /** 查询最新会话摘要。基于 ArkWeb 已登录会话（dsh-auth cookie）+ 明文 PIN。 */
  static async latestSession(base: string, pin: string): Promise<SessionQueryResult> {
    const b = base.replace(/\/+$/, '');
    return PocketApi.querySession(b, pin);
  }

  /** 获取可用的 dsh-pocket 认证（供 WS 订阅等场景复用）：返回明文 PIN。 */
  static async getToken(base: string, pin: string): Promise<string> {
    return pin;
  }

  /** 按 sessionId 获取单个会话最新 TaskInfo。 */
  static async getSession(base: string, pin: string, sessionId: string): Promise<TaskInfo | null> {
    const r = await PocketApi.listSessions(base, pin);
    for (const t of r.tasks) {
      if (t.sessionId === sessionId) {
        return t;
      }
    }
    return null;
  }

  /** 查询会话任务列表（session/list 全量项转 TaskInfo） */
  static async listSessions(base: string, pin: string): Promise<TaskListResult> {
    const b = base.replace(/\/+$/, '');
    return PocketApi.queryList(b, pin);
  }

  /** 带 PIN 查询最新会话（服务卡片等外部场景直接使用：走明文 PIN + dsh-auth cookie） */
  static async queryWithToken(base: string, pin: string): Promise<SessionQueryResult> {
    return PocketApi.querySession(base.replace(/\/+$/, ''), pin);
  }

  private static async queryList(b: string, pin: string): Promise<TaskListResult> {
    const r = await PocketApi.rpc(b, pin, 'session/list', 'dsh-harmony-tasklist', '_request', {}, 12000);
    if (r.code !== 200) {
      return { tasks: [], error: '服务返回 HTTP ' + String(r.code) + (r.text.startsWith('请求异常') ? ' ' + r.text : ''), token: pin };
    }
    if (r.text.startsWith('请求异常')) {
      return { tasks: [], error: r.text, token: pin };
    }
    try {
      const parsed = JSON.parse(r.text) as SessionListResult;
      const items = parsed.result?.value?.items ?? [];
      const tasks: TaskInfo[] = [];
      for (const it of items) {
        if (it.blank === true) continue;
        const stats = it.projections?.values?.sessionStats;
        tasks.push({
          sessionId: it.sessionId ?? '',
          title: it.projections?.values?.title ?? '',
          updatedAt: it.updatedAt ?? 0,
          running: it.running === true,
          phase: it.projections?.values?.goal?.goal?.phase ?? '',
          turns: stats?.turns ?? 0,
          steps: stats?.steps ?? 0,
          objective: it.projections?.values?.goal?.goal?.objective ?? ''
        });
      }
      return { tasks, error: '', token: pin };
    } catch (e) {
      return { tasks: [], error: '解析异常: ' + (e as Error).message.slice(0, 60), token: pin };
    }
  }

  /** 搜索会话（session/search）。 */
  static async searchSessions(base: string, pin: string, query: string): Promise<SearchResultSet> {
    const b = base.replace(/\/+$/, '');
    const r = await PocketApi.rpc(b, pin, 'session/search', 'dsh-harmony-search', 'request', { 'query': query }, 12000);
    if (r.code !== 200) {
      return { results: [], error: '服务返回 HTTP ' + String(r.code) + (r.text.startsWith('请求异常') ? ' ' + r.text : '') };
    }
    if (r.text.startsWith('请求异常')) {
      return { results: [], error: r.text };
    }
    try {
      const parsed = JSON.parse(r.text) as SearchResultWire;
      const items = parsed.result?.value?.items ?? [];
      const results: SearchResult[] = [];
      for (const it of items) {
        results.push({ sessionId: it.sessionId ?? '', snippet: it.snippet ?? '' });
      }
      return { results, error: '' };
    } catch (e) {
      return { results: [], error: '解析异常: ' + (e as Error).message.slice(0, 60) };
    }
  }

  /** 拉取会话历史(最近消息，用于详情页进度/摘要)。走 session/page 新协议。 */
  static async sessionHistory(base: string, pin: string, sessionId: string, maxMessages: number = 20): Promise<SessionHistoryResult> {
    const b = base.replace(/\/+$/, '');
    const addr: SessionAddress = { 'kind': 'session', 'sessionId': sessionId };
    const args: Record<string, Object> = {
      'address': addr,
      'throughSeq': 9007199254740991,
      'maxMessages': maxMessages
    };
    let r = await PocketApi.rpc(b, pin, 'session/page', 'dsh-harmony-hist', 'request', args, 12000);
    if (r.code === 200) {
      const m = r.text.match(/past cursor (\d+)/);
      if (m !== null && m.length > 1) {
        args['throughSeq'] = Number(m[1]);
        r = await PocketApi.rpc(b, pin, 'session/page', 'dsh-harmony-hist', 'request', args, 12000);
      }
    }
    if (r.code !== 200) {
      return { messages: [], error: '服务返回 HTTP ' + String(r.code) + (r.text.startsWith('请求异常') ? ' ' + r.text : '') };
    }
    if (r.text.startsWith('请求异常')) {
      return { messages: [], error: r.text };
    }
    try {
      const parsed = JSON.parse(r.text) as PageResultWire;
      const records = parsed.result?.value?.records ?? [];
      const messages: SessionMessage[] = [];
      const fold = (content: HistoryMsgTextPart[] | string | undefined): FoldedMsg => {
        let contentText = '';
        const images: SessionImage[] = [];
        if (typeof content === 'string') {
          contentText = content;
        } else if (Array.isArray(content)) {
          const parts: string[] = [];
          for (const p of content) {
            if (p !== undefined && p.type === 'text' && typeof p.text === 'string') {
              parts.push(p.text);
            } else if (p !== undefined && p.type === 'image' && p.attachment !== undefined) {
              const att = p.attachment;
              const aid = att.attachmentId ?? '';
              if (aid.length > 0) {
                images.push({ 'attachmentId': aid, 'mediaType': att.mediaType ?? '', 'name': att.name ?? '' });
              }
            }
          }
          contentText = parts.join(' ').trim();
        }
        return { text: contentText, images: images };
      };
      for (const rec of records) {
        const ev = rec.event;
        if (ev === undefined) continue;
        if (ev.type !== 'user/message' && ev.type !== 'assistant/message') continue;
        const data = ev.data;
        if (data === undefined) continue;
        let role = data.role ?? '';
        let content: HistoryMsgTextPart[] | string | undefined = data.content;
        if (ev.type === 'assistant/message' && data.message !== undefined) {
          role = data.message.role ?? role;
          content = data.message.content;
        }
        const h = fold(content);
        if (h.text.length > 0 || h.images.length > 0) {
          messages.push({ role: role, text: h.text, images: h.images });
        }
      }
      return { messages, error: '' };
    } catch (e) {
      return { messages: [], error: '解析异常: ' + (e as Error).message.slice(0, 60) };
    }
  }

  /** 向会话发送一条文本消息（session/prompt）。 */
  static async promptSession(base: string, pin: string, sessionId: string, content: PromptContentPart[]): Promise<ControlResult> {
    const b = base.replace(/\/+$/, '');
    const requestId = 'dsh-harmony-' + util.generateRandomUUID();
    const args: Record<string, Object> = {
      'requestId': requestId,
      'sessionId': sessionId,
      'mode': 'queue',
      'content': content
    };
    const r = await PocketApi.rpc(b, pin, 'session/prompt', 'dsh-harmony-prompt', 'request', args, 20000);
    if (r.code === 200) {
      return { ok: true, error: '' };
    }
    return { ok: false, error: '服务返回 HTTP ' + String(r.code) + (r.text.startsWith('请求异常') ? ' ' + r.text : '') };
  }

  /** 按 attachmentId 拉取消息中的图片（session/attachment），返回 base64 data。 */
  static async fetchSessionAttachment(base: string, pin: string, sessionId: string, attachmentId: string): Promise<AttachmentResult> {
    const b = base.replace(/\/+$/, '');
    const args: Record<string, Object> = {
      'sessionId': sessionId,
      'attachmentId': attachmentId
    };
    const r = await PocketApi.rpc(b, pin, 'session/attachment', 'dsh-harmony-attachment', 'request', args, 30000);
    if (r.code !== 200) {
      return { ok: false, data: '', mediaType: '', error: '服务返回 HTTP ' + String(r.code) + (r.text.startsWith('请求异常') ? ' ' + r.text : '') };
    }
    if (r.text.startsWith('请求异常')) {
      return { ok: false, data: '', mediaType: '', error: r.text };
    }
    try {
      const parsed = JSON.parse(r.text) as AttachmentResultWire;
      const inner = parsed.result?.value;
      const d = inner?.data;
      const media = inner?.attachment?.mediaType;
      const dataStr = typeof d === 'string' ? d : '';
      return { ok: dataStr.length > 0, data: dataStr, mediaType: typeof media === 'string' ? media : '', error: dataStr.length > 0 ? '' : '图片数据为空' };
    } catch (e) {
      return { ok: false, data: '', mediaType: '', error: '解析异常: ' + (e as Error).message.slice(0, 60) };
    }
  }

  /** 会话控制（session/cancel；goal.* 在新协议下需 agent+ref，App 暂不支持）。 */
  static async controlSession(base: string, pin: string, method: string, sessionId: string): Promise<ControlResult> {
    const b = base.replace(/\/+$/, '');
    if (method.startsWith('session.')) {
      const endpoint = method.replace(/\./g, '/');
      const args: Record<string, Object> = { 'sessionId': sessionId };
      const r = await PocketApi.rpc(b, pin, endpoint, 'dsh-harmony-ctrl', 'request', args, 12000);
      if (r.code === 200) {
        return { ok: true, error: '' };
      }
      return { ok: false, error: '服务返回 HTTP ' + String(r.code) + (r.text.startsWith('请求异常') ? ' ' + r.text : '') };
    }
    return { ok: false, error: 'goal 控制在新协议下需要 goal id/agent，暂不支持' };
  }

  private static async querySession(b: string, pin: string): Promise<SessionQueryResult> {
    const r = await PocketApi.rpc(b, pin, 'session/list', 'dsh-harmony-session', '_request', {}, 12000);
    if (r.code !== 200) {
      hilog.warn(DOMAIN, TAG, 'session/list http %{public}d', r.code);
      return { info: null, error: '服务返回 HTTP ' + String(r.code) + (r.text.startsWith('请求异常') ? ' ' + r.text : ''), token: pin };
    }
    if (r.text.startsWith('请求异常')) {
      return { info: null, error: r.text, token: pin };
    }
    try {
      const parsed = JSON.parse(r.text) as SessionListResult;
      const items = parsed.result?.value?.items ?? [];
      if (items.length === 0) {
        return { info: null, error: '无会话数据', token: pin };
      }
      return { info: PocketApi.project(items[0]), error: '', token: pin };
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'session/list failed: %{public}s', (e as Error).message);
      return { info: null, error: '请求异常: ' + (e as Error).message.slice(0, 60), token: pin };
    }
  }

  /** 提取最新会话的轻量字段（items 已按 updatedAt 降序） */
  private static project(item: SessionItem): LatestSessionInfo {
    const stats = item.projections?.values?.sessionStats;
    return {
      sessionId: item.sessionId ?? '',
      title: item.projections?.values?.title ?? '',
      updatedAt: item.updatedAt ?? 0,
      running: item.running === true,
      turns: stats?.turns ?? 0,
      steps: stats?.steps ?? 0,
      phase: item.projections?.values?.goal?.goal?.phase ?? '',
      objective: item.projections?.values?.goal?.goal?.objective ?? ''
    };
  }
}
