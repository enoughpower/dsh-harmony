#!/usr/bin/env node
/**
 * DSH Harmony 电脑端推送服务（方案 B：独立进程，不改 dsh-pocket）
 *
 * 推送策略（仅两场景推送，其他一律不推）：
 *  1. 会话结束 → 推送汇报（完成/已结束 + 目标 + 轮/步统计）
 *  2. 会话中途收集信息 → events.mux 事件流（打开即回放 pending question + 实时推送）
 *
 * 发送通道：SENDER=test（默认，临时异常测试渠道）| huawei（华为 AGC，需手机 push token）
 * 发送节流：串行队列 + 3.1s 间隔（测试通道限流 3 秒 1 条）
 *
 * 运行：node --env-file=.env tools/push-notify/push-notify.js
 * 环境变量：SENDER / TEST_NICK / PUSH_APP_ID / PUSH_APP_SECRET / DSH_BASE / DSH_PIN
 */
import { createServer } from 'node:http';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const APP_ID = process.env.PUSH_APP_ID || '';
const APP_SECRET = process.env.PUSH_APP_SECRET || '';
// 临时异常测试渠道（SENDER=test）；SENDER=huawei 用华为 AGC 自有推送
const SENDER = 'huawei';
const DSH_BASE = (process.env.DSH_BASE || 'http://127.0.0.1:3081').replace(/\/+$/, '');
const DSH_PIN = process.env.DSH_PIN || '11111111';

const TOKEN_FILE = new URL('./tokens.json', import.meta.url).pathname;
let pushTokens = loadTokens();

function loadTokens() {
  if (existsSync(TOKEN_FILE)) {
    try { return JSON.parse(readFileSync(TOKEN_FILE, 'utf8')); } catch { }
  }
  return [];
}
function saveTokens() { writeFileSync(TOKEN_FILE, JSON.stringify(pushTokens, null, 2)); }

// ---- 推送开关（App 通过 /api/push.settings 下发，持久化 settings.json） ----
const SETTINGS_FILE = new URL('./settings.json', import.meta.url).pathname;
let pushSettings = loadSettings();
function loadSettings() {
  const def = { pushEnabled: true, sessionEnd: true, interact: true, balance: true, balanceThreshold: Number(process.env.BALANCE_THRESHOLD || 5) };
  if (existsSync(SETTINGS_FILE)) {
    try {
      const saved = JSON.parse(readFileSync(SETTINGS_FILE, 'utf8'));
      return { ...def, ...saved };
    } catch { }
  }
  return def;
}
function saveSettings() { writeFileSync(SETTINGS_FILE, JSON.stringify(pushSettings, null, 2)); }

// ---- 华为 Push API V3（SENDER=huawei，HarmonyOS NEXT 5.x+ 必须）----
// 鉴权: 服务账号密钥(API Console 下载的 JSON) → PS256 签名 JWT → Authorization: Bearer <jwt>
// 端点: POST https://push-api.cloud.huawei.com/v3/<projectId>/messages:send (push-type: 0 = 通知消息)
let jwtCache = { token: '', expiresAt: 0 };
const { createSign, constants } = await import('node:crypto');

function b64url(s) { return Buffer.from(s).toString('base64url'); }

async function huaweiJwt() {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache.token && jwtCache.expiresAt > now + 300) return jwtCache.token;
  const keyFile = process.env.PUSH_KEY_FILE || '';
  if (!keyFile) return '';
  const key = JSON.parse(readFileSync(keyFile, 'utf8'));
  const header = b64url(JSON.stringify({ kid: key.key_id, typ: 'JWT', alg: 'PS256' }));
  const payload = b64url(JSON.stringify({
    aud: 'https://oauth-login.cloud.huawei.com/oauth2/v3/token',
    iss: key.sub_account,
    exp: now + 3600,
    iat: now,
  }));
  const sig = createSign('RSA-SHA256');
  sig.update(header + '.' + payload);
  sig.end();
  jwtCache = { token: header + '.' + payload + '.' + sig.sign({
    key: key.private_key,
    padding: constants.RSA_PKCS1_PSS_PADDING,
    saltLength: constants.RSA_PSS_SALTLEN_DIGEST,
  }).toString('base64url'), expiresAt: now + 3600 };
  return jwtCache.token;
}

async function huaweiSend(title, body, sessionId) {
  const keyFile = process.env.PUSH_KEY_FILE || '';
  if (!keyFile) { console.log('[push] 未配置 PUSH_KEY_FILE(V3 服务账号密钥), 跳过发送'); return; }
  if (pushTokens.length === 0) { console.log('[push] 无手机 token，跳过'); return; }
  const jwt = await huaweiJwt();
  if (!jwt) { console.log('[push] 生成 JWT 失败'); return; }
  const key = JSON.parse(readFileSync(keyFile, 'utf8'));
  const projectId = key.project_id;
  const res = await fetch('https://push-api.cloud.huawei.com/v3/' + projectId + '/messages:send', {
    method: 'POST',
    headers: { 'authorization': 'Bearer ' + jwt, 'content-type': 'application/json', 'push-type': '0' },
    body: JSON.stringify({
      payload: {
        notification: {
          title, body,
          // 自分类权益(AGC 审核通过, 2026-08-25): 工作事项提醒 → WORK
          // 资讯营销类消息必须改用 MARKETING(受频次限制); 未获批场景不可冒充服务/通讯类
          category: 'WORK',
          clickAction: { actionType: 0 },
        },
      },
      // 通知点击深链：App 从 data 读 sessionId + dshUrl 直达该会话详情页
      data: { dshUrl: DSH_BASE, sessionId: String(sessionId || '') },
      target: { token: pushTokens },
      pushOptions: { testMessage: false },
    }),
  });
  const data = await res.json();
  // 稳定性：鉴权失败 → 强制刷新 JWT；无效/过期 token → 清空(下次 App 启动会重新上报)
  if (res.status === 401 || res.status === 403) {
    jwtCache = { token: '', expiresAt: 0 };
  }
  const code = Number(data?.code || 0);
  if (code && [80300007, 80300002, 80300003].includes(code)) {
    const before = pushTokens.length;
    pushTokens = [];
    saveTokens();
    console.log('[push] cleared invalid tokens, before=' + before);
  }
  console.log('[push] send ->', res.status, JSON.stringify(data).slice(0, 200));
}

/** 发送节流队列：串行且 ≥3.1s 间隔（测试渠道限流 3 秒 1 条）；另加 per-session 冷却避免刷屏 */
const sendQueue = [];
let sending = false;
const cooldown = new Map();   // sessionId -> lastSentAt
const COOLDOWN_MS = 12000;
function sendCase(title, body, sessionId, type) {
  // 推送开关：总开关关->全不发；对应场景关->跳过
  if (!pushSettings.pushEnabled) { console.log('[push] push disabled by settings'); return; }
  if (type === 'end' && !pushSettings.sessionEnd) { console.log('[push] session-end disabled'); return; }
  if (type === 'interact' && !pushSettings.interact) { console.log('[push] interact disabled'); return; }
  const key = String(sessionId || '');
  const now = Date.now();
  if (key) {
    const last = cooldown.get(key) || 0;
    if (now - last < COOLDOWN_MS) {
      console.log('[push] throttled session', key);
      return;
    }
    cooldown.set(key, now);
  }
  sendQueue.push({ title, body, sessionId });
  drainQueue();
}
function drainQueue() {
  if (sending || sendQueue.length === 0) return;
  const item = sendQueue.shift();
  sending = true;
  huaweiSend(item.title, item.body, item.sessionId).catch(() => {}).finally(() => {
    sending = false;
    setTimeout(drainQueue, 3100);
  });
}

// ---- dsh-pocket 会话轮询（仅三场景） ----
let dshToken = '';
const runningMap = new Map();   // sessionId -> true（曾运行）
const sessionMeta = new Map();  // sessionId -> {title, objective}
let baseline = false;
let pollFailCount = 0;
const POLL_MS = 5000;

/** token 失效(harness 重启/过期) → 清空,下次 poll 重新登录 */
function invalidateToken() {
  if (dshToken !== '') {
    dshToken = '';
    console.log('[poll] token invalidated, will re-login');
  }
}

async function ensureDshToken() {
  if (dshToken) return dshToken;
  // 登录表单字段名为 token（PIN 值）；成功后 Set-Cookie: dsh_pocket_token
  const res = await fetch(DSH_BASE + '/pocket-login', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ token: DSH_PIN }),
    redirect: 'manual',
  });
  const setCookie = res.headers.get('set-cookie') || '';
  const m = setCookie.match(/dsh_pocket_token=([^;]+)/);
  if (m) {
    dshToken = m[1];
    console.log('[poll] dsh token OK');
    connectEventsHost();
  } else {
    console.log('[poll] login status=' + res.status);
  }
  return dshToken;
}

async function poll() {
  try {
    const token = await ensureDshToken();
    if (!token) { console.log('[poll] 无 dsh token'); return; }
    const res = await fetch(DSH_BASE + '/api/session.list?token=' + encodeURIComponent(token), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'client-request', rpcId: 'push-' + Date.now(), method: 'session.list', payload: {} }),
    });
    // token 失效(harness 重启/过期)：清空重登,避免一直 poll 失败
    if (res.status === 401 || res.status === 403) {
      console.log('[poll] session.list auth failed ' + res.status + ', re-login');
      pollFailCount = 0;
      invalidateToken();
      return;
    }
    const j = await res.json();
    pollFailCount = 0;
    const items = j.result?.value?.items || [];
    lastPollAt = Date.now();
    if (items.length === 0) return;

    for (const it of items) {
      const sid = it.sessionId;
      const s = it.projections?.values || {};
      const title = (s.title || 'DSH 任务').slice(0, 40);
      sessionMeta.set(sid, { title, objective: String(s.goal?.goal?.objective || '').slice(0, 60) });

      if (!baseline) {
        if (it.running) runningMap.set(sid, true);
        continue;
      }

      // 场景1/2·结束：曾运行 -> 现在不运行，推送汇报
      if (runningMap.has(sid) && !it.running) {
        runningMap.delete(sid);
        const phase = s.goal?.goal?.phase || '';
        const done = (phase === 'complete');
        const summary = await sessionSummary(sid);
        const head = done ? '✅ 任务完成' : '⚠️ 会话已结束';
        const goal = String(s.goal?.goal?.objective || '').slice(0, 40);
        const meta = goal ? ' · ' + goal : '';
        await sendCase(title + meta, summary ? head + '：' + summary : head, sid, 'end');
      } else if (it.running) {
        runningMap.set(sid, true);
      }
    }
    baseline = true;
  } catch (e) {
    console.log('[poll] err', e.message);
    pollFailCount += 1;
    if (pollFailCount >= 3) {
      console.log('[poll] repeated failures, force re-login');
      pollFailCount = 0;
      invalidateToken();
    }
  } finally {
    setTimeout(poll, POLL_MS);
  }
}

// ---- 会话总结（结束汇报一句话） ----
async function sessionSummary(sid) {
  try {
    const res = await fetch(DSH_BASE + '/api/session.history?token=' + encodeURIComponent(dshToken), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'client-request', rpcId: 'h-' + Date.now(), method: 'session.history', payload: { sessionId: sid, maxMessages: 20 } }),
    });
    const j = await res.json();
    const events = j?.result?.value?.events || [];
    for (let i = events.length - 1; i >= 0; i--) {
      const e = events[i]?.event;
      if (e && (e.type === 'assistant/message' || e.type === 'message')) {
        const m = e.data?.message || e.message || {};
        if (m.role === 'assistant') {
          const parts = Array.isArray(m.content) ? m.content : [];
          const text = parts.filter((p) => p && p.type === 'text')
            .map((p) => String(p.text || '')).join(' ').trim();
          if (text) return cleanSummary(text);
        }
      }
    }
  } catch (e) { }
  return '';
}
function cleanSummary(t) {
  // 去代码块/多余空白 → 单行截断 80
  let s = String(t).replace(/```[sS]*?```/g, ' ').replace(/\s+/g, ' ').trim();
  if (s.length > 80) s = s.slice(0, 80) + '…';
  return s;
}

// ---- DeepSeek 余额（每 5 分钟查一次 + 低于阈值告警推送） ----
const BALANCE_INTERVAL = 5 * 60 * 1000;
let lastBalance = null;            // {currency,total,available,fetchedAt}
let balanceLowNotified = false;
async function getDeepseekKey() {
  if (process.env.DEEPSEEK_API_KEY) return process.env.DEEPSEEK_API_KEY;
  try {
    const f = (process.env.HOME || process.env.USERPROFILE || '') + '/.dsh/.credentials.yaml';
    if (existsSync(f)) {
      const t = readFileSync(f, 'utf8');
      const m = t.match(/^\s*DEEPSEEK_API_KEY:\s*([^\r\n]+)/m);
      if (m && m[1]) return m[1].trim().replace(/^["']|["']$/g, '');
    }
  } catch { }
  return '';
}
async function refreshBalance() {
  try {
    const key = await getDeepseekKey();
    if (!key) { console.log('[balance] no deepseek key'); return; }
    const res = await fetch('https://api.deepseek.com/user/balance', {
      headers: { 'Authorization': 'Bearer ' + key },
    });
    if (res.status !== 200) { console.log('[balance] HTTP ' + res.status); return; }
    const j = await res.json();
    const info = (j.balance_infos || [])[0];
    lastBalance = {
      currency: info?.currency || '',
      total: info?.total_balance || '0',
      available: !!j.is_available,
      fetchedAt: Date.now(),
    };
    const total = Number(lastBalance.total) || 0;
    if (!pushSettings.balance) {
      console.log('[balance] disabled by settings');
      return;
    }
    const threshold = Number(pushSettings.balanceThreshold) || 5;
    if (total < threshold && !balanceLowNotified) {
      balanceLowNotified = true;
      sendCase('💰 DeepSeek 余额不足', '当前余额 ' + lastBalance.total + ' ' + lastBalance.currency
        + '，已低于 ' + threshold + '，请及时充值（避免任务中断）', '', 'balance');
    } else if (total >= threshold) {
      balanceLowNotified = false;
    }
    console.log('[balance] updated', JSON.stringify(lastBalance));
  } catch (e) {
    console.log('[balance] err', e.message);
  }
}

// ---- 事件流订阅（场景3：会话中途收集信息） ----
let wsRetry = 0;
const sentQuestions = new Set();   // 已提醒的问题/批准，防重连回放重复推
const startedAt = Date.now();
let lastPollAt = 0;
function connectEventsHost() {
  const u = new URL(DSH_BASE);
  const wsUrl = 'ws://' + u.host + '/api/events.mux?token=' + encodeURIComponent(dshToken);
  const ws = new WebSocket(wsUrl);
  ws.onopen = () => { console.log('[evt] events.mux connected'); wsRetry = 0; };
  ws.onmessage = (ev) => {
    try {
      const raw = typeof ev.data === 'string' ? ev.data : String(ev.data);
      const msg = JSON.parse(raw);
      const frame = msg?.payload && typeof msg.payload === 'object' ? msg.payload : msg;
      if (!frame || typeof frame !== 'object') return;
      if (frame.type === 'question/requested') {
        const meta = sessionMeta.get(frame.sessionId) || {};
        const q = (frame.questions || [])[0];
        const qText = q ? (q.question || q.header || '请回复') : '请回复';
        // 问题去重：同一会话的同一问题(重连回放/replay)不重复推
        const qKey = String(frame.sessionId || '') + ':' + qText;
        if (sentQuestions.has(qKey)) return;
        sentQuestions.add(qKey);
        sendCase(meta.title || 'DSH 任务', '📩 需要你提供信息：' + String.fromCharCode(10) + qText.slice(0, 200), frame.sessionId, 'interact');
      } else if (frame.type === 'approval/requested') {
        const meta = sessionMeta.get(frame.sessionId) || {};
        const aKey = String(frame.sessionId || '') + ':' + String(frame.approvalId || '');
        if (sentQuestions.has(aKey)) return;
        sentQuestions.add(aKey);
        sendCase(meta.title || 'DSH 任务', '🛂 需要你批准：' + String(frame.toolName || '工具调用') +
          (frame.reason ? String.fromCharCode(10) + frame.reason : ''), frame.sessionId, 'interact');
      }
    } catch (e) {
      console.log('[evt] parse err', e.message);
    }
  };
  ws.onclose = () => {
    console.log('[evt] closed, retry=' + wsRetry);
    if (wsRetry < 5) { wsRetry++; setTimeout(connectEventsHost, 5000 * wsRetry); }
  };
  ws.onerror = () => { console.log('[evt] error'); };
}

// ---- HTTP: 收手机 token / 状态查询 ----
const server = createServer((req, res) => {
  if (req.url === '/api/status') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      status: 'online', sender: SENDER,
      tokens: pushTokens.length, mux: wsRetry < 5,
      queued: sendQueue.length,
      uptime: Math.round((Date.now() - startedAt) / 1000),
      lastPoll: lastPollAt,
      settings: pushSettings,
    }));
    return;
  }
  if (req.url === '/api/push.settings' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      try {
        const j = JSON.parse(body);
        const p = (j && j.payload) || {};
        if (typeof p.pushEnabled === 'boolean') pushSettings.pushEnabled = p.pushEnabled;
        if (typeof p.sessionEnd === 'boolean') pushSettings.sessionEnd = p.sessionEnd;
        if (typeof p.interact === 'boolean') pushSettings.interact = p.interact;
        if (typeof p.balance === 'boolean') pushSettings.balance = p.balance;
        if (typeof p.threshold === 'number') pushSettings.balanceThreshold = p.threshold;
        saveSettings();
        console.log('[api] push.settings ->', JSON.stringify(pushSettings));
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ ok: true, settings: pushSettings }));
      } catch (e) {
        res.writeHead(400); res.end('{}');
      }
    });
    return;
  }
  if (req.url === '/api/push.token' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      try {
        const j = JSON.parse(body);
        const token = j.payload?.token;
        if (token) {
          if (!pushTokens.includes(token)) pushTokens.push(token);
          saveTokens();
          console.log('[api] push.token stored, total=' + pushTokens.length);
        }
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch (e) {
        res.writeHead(400); res.end('{}');
      }
    });
    return;
  }
  if (req.url === '/api/balance') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: lastBalance !== null, balance: lastBalance, threshold: pushSettings.balanceThreshold }));
    return;
  }
  res.writeHead(404); res.end('{}');
});

server.listen(3082, () => {
  console.log('DSH push-notify on :3082');
  console.log(APP_ID ? '[push] AGC configured' : '[push] 未配置 PUSH_APP_ID/SECRET（请在 AGC 开通后设置）');
  poll();
  // 余额：启动即查一次，之后每 5 分钟刷新
  refreshBalance();
  setInterval(refreshBalance, BALANCE_INTERVAL);
});
