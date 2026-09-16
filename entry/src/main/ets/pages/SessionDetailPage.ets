import { router } from '@kit.ArkUI';
import { SessionDetailView } from '../components/SessionDetailView';

/**
 * 会话详情独立页（窄屏/手机）：读取路由参数后渲染可复用的 SessionDetailView。
 * 平板宽屏时由 Index 直接内嵌 SessionDetailView 到左栏，不再走本页。
 */
@Entry
@Component
struct SessionDetailPage {
  @State sessionId: string = '';
  @State title: string = '';
  @State objective: string = '';
  @State phase: string = '';
  @State running: boolean = false;
  @State turns: number = 0;
  @State steps: number = 0;
  @State updatedAt: number = 0;
  @State url: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.sessionId = params?.['sessionId'] ?? '';
    this.title = params?.['title'] ?? '';
    this.objective = params?.['objective'] ?? '';
    this.phase = params?.['phase'] ?? '';
    this.running = params?.['running'] === 'true';
    this.turns = parseInt(params?.['turns'] ?? '0', 10);
    this.steps = parseInt(params?.['steps'] ?? '0', 10);
    this.updatedAt = parseInt(params?.['updatedAt'] ?? '0', 10);
    this.url = params?.['url'] ?? '';
  }

  build() {
    Column() {
      SessionDetailView({
        sessionId: this.sessionId,
        title: this.title,
        objective: this.objective,
        phase: this.phase,
        running: this.running,
        turns: this.turns,
        steps: this.steps,
        updatedAt: this.updatedAt,
        baseUrl: this.url
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}