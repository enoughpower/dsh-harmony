import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LatestSessionInfo } from '../utils/PocketApi';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 任务进度通知（实况窗权益不可用，降级为普通通知实时进度）：
 * 任务开始 → 常驻通知；进度变化 → 节流更新；任务完成 → 显示"已完成"后自动移除。
 */
export class ProgressNotify {
  private static readonly NOTIFY_ID: number = 1001;
  private static readonly THROTTLE_MS: number = 30000;
  private static started: boolean = false;
  private static lastUpdateAt: number = 0;

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
      old = old + new Date().toString() + ' PN: ' + msg + '\n';
      if (old.length > 65536) {
        old = old.slice(old.length - 65536);
      }
      const wf = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(wf.fd, old);
      fileIo.closeSync(wf);
    } catch (e) {
    }
  }

  /** 任务开始：发布常驻进度通知 */
  static async start(context: common.Context, s: LatestSessionInfo): Promise<void> {
    try {
      await ProgressNotify.publish(context, s);
      ProgressNotify.started = true;
      ProgressNotify.lastUpdateAt = Date.now();
      ProgressNotify.logDebug(context, 'start: ok');
      hilog.info(DOMAIN, TAG, 'progress notify started');
    } catch (e) {
      const em = (e as Error).message;
      ProgressNotify.logDebug(context, 'start: FAILED ' + em.slice(0, 200));
      hilog.warn(DOMAIN, TAG, 'notify start failed: %{public}s', em);
    }
  }

  /** 进度变化：同 id 更新（节流 30s） */
  static async update(context: common.Context, s: LatestSessionInfo): Promise<void> {
    if (!ProgressNotify.started) {
      return;
    }
    const now = Date.now();
    if (now - ProgressNotify.lastUpdateAt < ProgressNotify.THROTTLE_MS) {
      return;
    }
    try {
      await ProgressNotify.publish(context, s);
      ProgressNotify.lastUpdateAt = now;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'notify update failed: %{public}s', (e as Error).message);
    }
  }

  /** 任务完成：显示"已完成"后自动移除 */
  static async stop(context: common.Context, s: LatestSessionInfo): Promise<void> {
    if (!ProgressNotify.started) {
      return;
    }
    ProgressNotify.started = false;
    try {
      await ProgressNotify.publish(context, s, false);
      setTimeout(() => {
        notificationManager.cancel(ProgressNotify.NOTIFY_ID).catch(() => {
        });
      }, 3000);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'notify stop failed: %{public}s', (e as Error).message);
    }
  }

  private static async publish(context: common.Context, s: LatestSessionInfo, running: boolean = true): Promise<void> {
    const title = s.title.length > 0 ? s.title : 'DSH 任务';
    const text = (running ? '▶ 进行中' : '■ 已完成') + ' · ' + s.turns + ' 轮 · ' + s.steps + ' 步';
    const request: notificationManager.NotificationRequest = {
      'id': ProgressNotify.NOTIFY_ID,
      'content': {
        'notificationContentType': notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        'normal': {
          'title': title,
          'text': text
        }
      }
    };
    try {
      await notificationManager.publish(request);
    } catch (e) {
      const em = (e as Error).message;
      ProgressNotify.logDebug(context, 'publish: FAILED ' + em.slice(0, 200));
      const be = e as BusinessError;
      throw new Error('publish failed code=' + String(be.code) + ' ' + be.message);
    }
  }
}
