#!/usr/bin/env node
/**
 * DSH Harmony 电脑端推送服务（方案 B：独立进程，不改 dsh-pocket）
 *
 * 推送策略（仅三场景推送，其他一律不推）：
 *  1. 会话结束 → 推送汇报（完成/已结束 + 目标 + 轮/步统计）
 *  2. 异常/长时间无响应 → updatedAt 停滞超阈值且连续无响应 >5 次，推送 ⏰ 提醒
 *  3. 会话中途收集信息 → events.mux 事件流（打开即回放 pending question + 实时推送）
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
const SENDER = process.env.SENDER || 'test';
const TEST_NICK = process.env.TEST_NICK || '';
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

// ---- 华为 Push API V3（SENDER=huawei，HarmonyOS NEXT 5.x+ 必须）----
// 鉴权: 服务账号密钥(API Console 下载的 JSON) → PS256 签名 JWT → Authorization: Bearer <jwt>
// 端点: POST https://push-api.cloud.huawei.com/v3/<projectId>/messages:send (push-type: 0 = 通知消息)
let jwtCache = { token: '', expiresAt: 0 };
const { createSign } = await import('node:crypto');

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
    padding: 1 /* RSA_PKCS1_PSS_PADDING */,
    saltLength: 32 /* RSA_PSS_SALTLEN_DIGEST */,
  }).toString('base64url'), expiresAt: now + 3600 };
  return jwtCache.token;
}

async function huaweiSend(title, body) {
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
      target: { token: pushTokens },
      pushOptions: { testMessage: true },
    }),
  });
  const data = await res.json();
  console.log('[push] send ->', res.status, JSON.stringify(data).slice(0, 200));
}

// ---- 临时异常测试渠道（SENDER=test） ----
async function testSend(title, body) {
  if (!TEST_NICK) { console.log('[push] 测试渠道昵称未配置，跳过'); return; }
  console.log('[push] send [' + String(title).slice(0, 24) + '] ' + String(body).slice(0, 40).replace(/\s+/g, ' '));
  const params = { title: String(title).slice(0, 80), msg: String(body).slice(0, 500) };
  const res = await fetch('https://api.chuckfang.com/' + TEST_NICK, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params),
  });
  const data = await res.json();
  console.log('[push] test send ->', JSON.stringify(data).slice(0, 160));
}

/** 发送节流队列：串行且 ≥3.1s 间隔（测试渠道限流 3 秒 1 条） */
const sendQueue = [];
let sending = false;
function sendCase(title, body) {
  sendQueue.push({ title, body });
  drainQueue();
}
function drainQueue() {
  if (sending || sendQueue.length === 0) return;
  const item = sendQueue.shift();
  sending = true;
  const doSend = SENDER === 'huawei' ? huaweiSend : testSend;
  doSend(item.title, item.body).catch(() => {}).finally(() => {
    sending = false;
    setTimeout(drainQueue, 3100);
  });
}

// ---- dsh-pocket 会话轮询（仅三场景） ----
let dshToken = '';
const runningMap = new Map();   // sessionId -> true（曾运行）
const stallMap = new Map();     // sessionId -> {count, notified}
const sessionMeta = new Map();  // sessionId -> {title, objective}
let baseline = false;
const POLL_MS = 5000;
const STALL_MS = 120 * 1000;
const STALL_LIMIT = 5;

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
    const j = await res.json();
    const items = j.result?.value?.items || [];
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
        stallMap.delete(sid);
        const phase = s.goal?.goal?.phase || '';
        const done = (phase === 'complete');
        const summary = await sessionSummary(sid);
        const head = done ? '✅ 任务完成' : '⚠️ 会话已结束';
        await sendCase(title, summary ? head + '：' + summary : head);
      } else if (it.running) {
        runningMap.set(sid, true);
        // 场景2·超时：运行中但 updatedAt 停滞（连续 >5 次无响应）
        const stallMs = it.updatedAt ? Date.now() - Number(it.updatedAt) : 0;
        let st = stallMap.get(sid) || { count: 0, notified: false };
        if (stallMs > STALL_MS) {
          st.count += 1;
          if (st.count > STALL_LIMIT && !st.notified) {
            st.notified = true;
            await sendCase(title, '⏰ 长时间无响应 · 已超过 ' + Math.round(stallMs / 1000) + 's（可能异常/卡住）');
          }
        } else {
          st.count = 0;
        }
        stallMap.set(sid, st);
      }
    }
    baseline = true;
  } catch (e) {
    console.log('[poll] err', e.message);
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

// ---- 事件流订阅（场景3：会话中途收集信息） ----
let wsRetry = 0;
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
        sendCase(meta.title || 'DSH 任务', '📩 需要你提供信息：' + String.fromCharCode(10) + qText.slice(0, 200));
      } else if (frame.type === 'approval/requested') {
        const meta = sessionMeta.get(frame.sessionId) || {};
        sendCase(meta.title || 'DSH 任务', '🛂 需要你批准：' + String(frame.toolName || '工具调用') +
          (frame.reason ? String.fromCharCode(10) + frame.reason : ''));
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
    res.end(JSON.stringify({ status: 'online', sender: SENDER, tokens: pushTokens.length, mux: wsRetry < 5 }));
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
  res.writeHead(404); res.end('{}');
});

server.listen(3082, () => {
  console.log('DSH push-notify on :3082');
  console.log(APP_ID ? '[push] AGC configured' : '[push] 未配置 PUSH_APP_ID/SECRET（请在 AGC 开通后设置）');
  poll();
});
