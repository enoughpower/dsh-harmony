import { common, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PocketApi, LatestSessionInfo } from '../utils/PocketApi';
import { AppPrefs } from './AppPrefs';
import { AppSessionState } from './AppSessionState';
import { ProgressNotify } from './ProgressNotify';
import { ConnectionStore } from './ConnectionStore';
import { ConnectionProfile } from '../../model/ConnectionProfile';
import { CardSync } from './CardSync';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 任务监听（统一数据源生产者）：
 * - 动态轮询 session.list：有任务 5s，无任务 15s
 * - 变化 → ① 共享状态 AppSessionState ② Preferences 快照 ③ 实况窗（开始/更新/收起） ④ 小组件 updateForm
 * - 保活：后台 startBackgroundRunning(DATA_TRANSFER) + 常驻通知「DSH 任务监听中」
 * - 设置开关 KEY_TASK_MONITOR 控制启停；关闭后不再轮询/实况窗（首页与小组件仅保留主动刷新）
 */
export class TaskMonitor {
  private static readonly POLL_BUSY_MS: number = 5000;
  private static readonly POLL_IDLE_MS: number = 15000;
  private static readonly NOTIFY_ID: number = 2002;

  private static timer: number = -1;
  private static running: boolean = false;
  private static backgrounding: boolean = false;
  private static lastSignature: string = '';
  private static lastSessionId: string = '';
  private static lastRunning: boolean | null = null;
  private static liveStarted: boolean = false;
  private static ctx: common.Context | null = null;
  private static base: string = '';

  /** 启动监听（读开关；开关开才轮询） */
  static async ensure(context: common.Context): Promise<void> {
    try {
      TaskMonitor.logDebug('ensure: begin');
      const enabled = await AppPrefs.getBool(context, AppPrefs.KEY_TASK_MONITOR, true);
      TaskMonitor.logDebug('ensure: enabled=' + String(enabled));
      if (!enabled) {
        TaskMonitor.stop();
        return;
      }
      const list = await new ConnectionStore().loadAll(context);
      TaskMonitor.logDebug('ensure: history=' + list.length);
      if (list.length === 0) {
        TaskMonitor.stop();
        return;
      }
      TaskMonitor.start(context, list[0].url);
    } catch (e) {
      TaskMonitor.logDebug('ensure: FAILED ' + (e as Error).message.slice(0, 160));
      hilog.warn(DOMAIN, TAG, 'ensure failed: %{public}s', (e as Error).message);
    }
  }

  private static start(context: common.Context, base: string): void {
    if (TaskMonitor.running && TaskMonitor.base === base) {
      return;
    }
    TaskMonitor.ctx = context;
    TaskMonitor.base = base.replace(/\/+$/, '');
    TaskMonitor.running = true;
    TaskMonitor.lastSignature = '';
    TaskMonitor.lastSessionId = '';
    TaskMonitor.lastRunning = null;
    TaskMonitor.logDebug('start: base=' + TaskMonitor.base);
    TaskMonitor.poll();
  }

  static stop(): void {
    if (TaskMonitor.timer >= 0) {
      clearInterval(TaskMonitor.timer);
      TaskMonitor.timer = -1;
    }
    TaskMonitor.running = false;
    TaskMonitor.lastSignature = '';
    TaskMonitor.lastRunning = null;
    TaskMonitor.liveStarted = false;
  }

  /** 设置页开关回调 */
  static setEnabled(context: common.Context, base: string, on: boolean): void {
    if (on) {
      TaskMonitor.start(context, base);
    } else {
      TaskMonitor.stop();
    }
  }

  /** 进入后台：申请长时任务保活 + 常驻通知 */
  static async onBackground(context: common.Context): Promise<void> {
    if (!TaskMonitor.running || TaskMonitor.backgrounding) {
      return;
    }
    TaskMonitor.backgrounding = true;
    try {
      TaskMonitor.logDebug('onBackground: requesting');
      const wa = await TaskMonitor.buildWantAgent();
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, wa);
      await TaskMonitor.publishForegroundNotification(context, true);
    } catch (e) {
      TaskMonitor.logDebug('onBackground: FAILED ' + (e as Error).message.slice(0, 160));
      hilog.warn(DOMAIN, TAG, 'start background failed: %{public}s', (e as Error).message);
    }
  }

  /** 回前台：结束长时任务 + 移除常驻通知 */
  static async onForeground(context: common.Context): Promise<void> {
    if (!TaskMonitor.backgrounding) {
      return;
    }
    TaskMonitor.backgrounding = false;
    try {
      TaskMonitor.logDebug('onForeground: stop bg');
      await backgroundTaskManager.stopBackgroundRunning(context);
      await TaskMonitor.publishForegroundNotification(context, false);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stop background failed: %{public}s', (e as Error).message);
    }
  }

  private static async buildWantAgent(): Promise<object> {
    const info: wantAgent.WantAgentInfo = {
      'wants': [{ 'bundleName': 'com.dsh.lite', 'abilityName': 'EntryAbility' }],
      'actionType': wantAgent.OperationType.START_ABILITY,
      'requestCode': 0
    };
    return await wantAgent.getWantAgent(info);
  }

  private static async publishForegroundNotification(context: common.Context, show: boolean): Promise<void> {
    try {
      if (show) {
        const request: notificationManager.NotificationRequest = {
          'id': TaskMonitor.NOTIFY_ID,
          'content': {
            'notificationContentType': notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            'normal': { 'title': 'DSH 任务监听中', 'text': '正在后台监听任务进度，进度变化会通过实况窗通知' }
          }
        };
        await notificationManager.publish(request);
      } else {
        await notificationManager.cancel(TaskMonitor.NOTIFY_ID);
      }
    } catch (e) {
    }
  }

  private static logDebug(msg: string): void {
    try {
      if (TaskMonitor.ctx === null) {
        return;
      }
      const path = TaskMonitor.ctx.filesDir + '/pocket-debug.log';
      let old = '';
      if (fileIo.accessSync(path)) {
        const rf = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE);
        const buf = new ArrayBuffer(16384);
        const n = fileIo.readSync(rf.fd, buf);
        old = n > 0 ? util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf, 0, n)) : '';
        fileIo.closeSync(rf);
      }
      old = old + new Date().toString() + ' TM: ' + msg + '\n';
      if (old.length > 65536) {
        old = old.slice(old.length - 65536);
      }
      const wf = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(wf.fd, old);
      fileIo.closeSync(wf);
    } catch (e) {
    }
  }

  private static schedule(): void {
    if (TaskMonitor.timer >= 0) {
      clearInterval(TaskMonitor.timer);
      TaskMonitor.timer = -1;
    }
    const busy = TaskMonitor.lastRunning === true;
    TaskMonitor.timer = setInterval(() => {
      TaskMonitor.poll();
    }, busy ? TaskMonitor.POLL_BUSY_MS : TaskMonitor.POLL_IDLE_MS);
  }

  private static async poll(): Promise<void> {
    if (!TaskMonitor.running || TaskMonitor.ctx === null) {
      return;
    }
    const ctx = TaskMonitor.ctx;
    try {
      const token = await AppPrefs.getString(ctx, AppPrefs.KEY_POCKET_TOKEN, '');
      if (token.length === 0) {
        TaskMonitor.schedule();
        return;
      }
      const q = await PocketApi.queryWithToken(TaskMonitor.base, token);
      if (q.info === null) {
        TaskMonitor.logDebug('poll: no info (token=' + token.slice(0, 6) + ')');
        TaskMonitor.schedule();
        return;
      }
      const s = q.info;
      const sessionId = s.title; // 标题近似会话标识（无需精确 ID）
      const sig = sessionId + '|' + String(s.running) + '|' + s.turns + '|' + s.steps;
      TaskMonitor.logDebug('poll: running=' + s.running + ' turns=' + s.turns + ' steps=' + s.steps + ' title=' + s.title.slice(0, 20));
      if (TaskMonitor.lastSignature === '') {
        // 首次基线：若已有任务在跑，直接显示实况窗
        TaskMonitor.lastSignature = sig;
        TaskMonitor.lastRunning = s.running;
        if (s.running) {
          TaskMonitor.logDebug('liveview: start (baseline running)');
          await ProgressNotify.start(ctx, s);
          TaskMonitor.liveStarted = true;
        }
        TaskMonitor.schedule();
        return;
      }
      const prevRunning = TaskMonitor.lastRunning;
      const prevTitle = TaskMonitor.lastSignature.split('|')[0];
      const changed = sig !== TaskMonitor.lastSignature;
      TaskMonitor.lastSignature = sig;
      TaskMonitor.lastRunning = s.running;
      TaskMonitor.schedule();
      if (!changed) {
        return;
      }
      // 会话切换（list[0] 换了任务）：先收起旧实况窗
      if (prevTitle !== sessionId && TaskMonitor.liveStarted) {
        TaskMonitor.logDebug('liveview: stop (switch)');
        await ProgressNotify.stop(ctx, s);
        TaskMonitor.liveStarted = false;
      }
      // 状态机：任务开始/完成/进度
      if (prevRunning === false && s.running) {
        TaskMonitor.logDebug('liveview: start');
        await ProgressNotify.start(ctx, s);
        TaskMonitor.liveStarted = true;
      } else if (prevRunning === true && !s.running) {
        TaskMonitor.logDebug('liveview: stop');
        await ProgressNotify.stop(ctx, s);
        TaskMonitor.liveStarted = false;
      } else if (TaskMonitor.liveStarted) {
        TaskMonitor.logDebug('liveview: update');
        await ProgressNotify.update(ctx, s);
      }
      // 数据源：共享状态 + 快照 + 小组件
      await TaskMonitor.commit(ctx, s);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'poll failed: %{public}s', (e as Error).message);
      TaskMonitor.schedule();
    }
  }

  private static async commit(context: common.Context, s: LatestSessionInfo): Promise<void> {
    AppSessionState.update(s);
    try {
      const snap = JSON.stringify({
        'title': s.title,
        'updatedAt': s.updatedAt,
        'running': s.running,
        'turns': s.turns,
        'steps': s.steps
      });
      await AppPrefs.setSessionSnapshot(context, snap);
    } catch (e) {
    }
    try {
      await CardSync.updateFormsFromSnapshot(context);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'form update failed: %{public}s', (e as Error).message);
    }
  }
}
