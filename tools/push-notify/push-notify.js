#!/usr/bin/env node
/**
 * DSH Harmony 电脑端推送服务（方案 B：独立进程，不改 dsh-pocket）
 *
 * 功能：
 *  1. 接收手机 App 上报的 Push Token（POST /api/push.token）
 *  2. 轮询 dsh-pocket 的 session.list，检测任务进度变化
 *  3. 任务 开始/进度/完成 时，调华为 Push REST API 推送到手机
 *
 * 前置（AGC）：
 *   - 华为 AGC 创建应用（bundleName: com.dsh.lite），开通推送服务
 *   - 拿到 AppID / AppSecret → 写入配置或环境变量
 *   - 手机 App 已集成 Push Kit 并上报 token（见 entry/.../PushToken.ets）
 *
 * 运行：node tools/push-notify/push-notify.js
 * 环境变量：PUSH_APP_ID / PUSH_APP_SECRET / DSH_BASE / DSH_PIN / DSH_TOKEN
 */
import { createServer } from 'node:http';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const APP_ID = process.env.PUSH_APP_ID || '';
const APP_SECRET = process.env.PUSH_APP_SECRET || '';
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

// ---- 华为 Push API ----
let accessTokenCache = { token: '', expiresAt: 0 };

async function huaweiAccessToken() {
  const now = Date.now();
  if (accessTokenCache.token && accessTokenCache.expiresAt > now + 60_000) return accessTokenCache.token;
  const res = await fetch('https://oauth-login.cloud.huawei.com/oauth2/v3/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: APP_ID,
      client_secret: APP_SECRET,
    }),
  });
  const data = await res.json();
  accessTokenCache = { token: data.access_token || '', expiresAt: now + (data.expires_in || 3600) * 1000 };
  return accessTokenCache.token;
}

async function huaweiSend(title, body) {
  if (!APP_ID || !APP_SECRET) { console.log('[push] AGC 未配置 AppID/Secret，跳过发送'); return; }
  if (pushTokens.length === 0) { console.log('[push] 无手机 token，跳过'); return; }
  const token = await huaweiAccessToken();
  if (!token) { console.log('[push] 获取 access_token 失败'); return; }
  const res = await fetch('https://push-api.cloud.huawei.com/v1/' + APP_ID + '/messages:send', {
    method: 'POST',
    headers: { 'authorization': 'Bearer ' + token, 'content-type': 'application/json' },
    body: JSON.stringify({
      validate_only: false,
      message: {
        notification: { title, body },
        android: { notification: { title, body, click_action: { type: 3 } } },
        token: pushTokens,
      },
    }),
  });
  const data = await res.json();
  console.log('[push] send ->', res.status, JSON.stringify(data).slice(0, 200));
}

// ---- dsh-pocket 会话轮询 ----
let dshToken = '';
let lastSig = '';
let lastRunning = null;
const POLL_BUSY = 5000, POLL_IDLE = 15000;

async function ensureDshToken() {
  if (dshToken) return dshToken;
  const res = await fetch(DSH_BASE + '/pocket-login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ pin: DSH_PIN }),
    redirect: 'manual',
  });
  if (res.status === 302 || res.status === 200) {
    const setCookie = res.headers.get('set-cookie') || '';
    const m = setCookie.match(/dsh_pocket_token=([^;]+)/);
    if (m) dshToken = m[1];
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
    const it = items[0];
    if (!it) return;
    const s = it.projections?.values || {};
    const sig = it.sessionId + '|' + it.running + '|' + (s.sessionStats?.turns || 0);
    if (lastSig === '') { lastSig = sig; lastRunning = it.running; return; }
    const prevRunning = lastRunning;
    const changed = sig !== lastSig;
    lastSig = sig; lastRunning = it.running;
    if (!changed) return;
    const title = (s.title || 'DSH 任务').slice(0, 40);
    const meta = (s.sessionStats ? (s.sessionStats.turns || 0) + ' 轮 · ' + (s.sessionStats.steps || 0) + ' 步' : '');
    if (prevRunning === false && it.running) await huaweiSend(title, '▶ 进行中 · ' + meta);
    else if (prevRunning === true && !it.running) await huaweiSend(title, '■ 已完成 · ' + meta);
    else await huaweiSend(title, '▶ 进行中 · ' + meta);
  } catch (e) {
    console.log('[poll] err', e.message);
  } finally {
    setTimeout(poll, (lastRunning === true ? POLL_BUSY : POLL_IDLE));
  }
}

// ---- HTTP: 收手机 token ----
const server = createServer((req, res) => {
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
