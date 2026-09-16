import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PreferenceKeys, preferencesUtil } from 'base';
import { queryWidgetSessionData } from 'today';

const TAG: string = 'TodayTimerWidgetService';
const WIDGET_STATE_EMPTY: string = 'empty';
const WIDGET_STATE_RUNNING: string = 'running';

export class TodayTimerWidgetData {
  state: string = WIDGET_STATE_EMPTY;
  title: string = '';
  colorHex: string = '';
  elapsedSeconds: number = 0;
  startToken: string = '';
  startTime: number = 0;
}

interface TodayTimerWidgetFormData {
  todayTimerWidgetState: string;
  todayTimerWidgetTitle: string;
  todayTimerWidgetColor: string;
  todayTimerWidgetElapsedSeconds: string;
  todayTimerWidgetStartToken: string;
  todayTimerWidgetStartTime: string;
}

class TodayTimerWidgetServiceImpl {
  async getTodayTimerWidgetData(context: Context): Promise<TodayTimerWidgetData> {
    const data = new TodayTimerWidgetData();
    try {
      // 同进程读投影 runningSessionView 快路径；Form 独立进程走 rdb 最新未结束记录兜底
      const session = await queryWidgetSessionData(context);
      if (session === null || session.recordId === '') {
        return data;
      }

      data.state = WIDGET_STATE_RUNNING;
      data.title = session.title;
      data.colorHex = session.color;
      data.elapsedSeconds = 0;
      data.startToken = session.recordId;
      data.startTime = session.startTime;
      return data;
    } catch (error) {
      hilog.error(0x0000, TAG, `getTodayTimerWidgetData failed: ${JSON.stringify(error)}`);
      return data;
    }
  }

  async registerForm(context: Context, formId: string): Promise<void> {
    if (!formId || formId.length === 0) {
      return;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return;
    }
    const ids = this.loadFormIds();
    if (!ids.includes(formId)) {
      ids.push(formId);
      preferencesUtil.putSync(PreferenceKeys.TODAY_TIMER_WIDGET_FORM_IDS, JSON.stringify(ids));
    }
  }

  async unregisterForm(context: Context, formId: string): Promise<void> {
    if (!formId || formId.length === 0) {
      return;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return;
    }
    const ids = this.loadFormIds().filter((id: string) => id !== formId);
    preferencesUtil.putSync(PreferenceKeys.TODAY_TIMER_WIDGET_FORM_IDS, JSON.stringify(ids));
  }

  async refreshRegisteredForms(context: Context): Promise<void> {
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return;
    }
    const formIds = this.loadFormIds();
    if (formIds.length === 0) {
      return;
    }
    const data = await this.getTodayTimerWidgetData(context);
    for (const formId of formIds) {
      try {
        const formData = this.buildFormData(data);
        const binding = formBindingData.createFormBindingData(formData);
        await formProvider.updateForm(formId, binding);
      } catch (error) {
        hilog.error(0x0000, TAG, `refreshRegisteredForms failed for ${formId}: ${JSON.stringify(error)}`);
      }
    }
  }

  async refreshFormById(context: Context, formId: string): Promise<boolean> {
    if (!formId || formId.length === 0) {
      return false;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return false;
    }
    const ids = this.loadFormIds();
    if (!ids.includes(formId)) {
      return false;
    }
    try {
      const data = await this.getTodayTimerWidgetData(context);
      const formData = this.buildFormData(data);
      const binding = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, binding);
      return true;
    } catch (error) {
      hilog.error(0x0000, TAG, `refreshFormById failed for ${formId}: ${JSON.stringify(error)}`);
      return false;
    }
  }

  async isRegisteredForm(context: Context, formId: string): Promise<boolean> {
    if (!formId || formId.length === 0) {
      return false;
    }
    const ready = await this.ensurePreferencesReady(context);
    if (!ready) {
      return false;
    }
    return this.loadFormIds().includes(formId);
  }

  private buildFormData(data: TodayTimerWidgetData): TodayTimerWidgetFormData {
    const date = new Date(data.startTime);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const startTimeStr = data.startTime > 0 ? `${hours}:${minutes}` : '';

    return {
      todayTimerWidgetState: data.state,
      todayTimerWidgetTitle: data.title,
      todayTimerWidgetColor: data.colorHex,
      todayTimerWidgetElapsedSeconds: data.elapsedSeconds.toString(),
      todayTimerWidgetStartToken: data.startToken,
      todayTimerWidgetStartTime: startTimeStr
    };
  }

  private async ensurePreferencesReady(context: Context): Promise<boolean> {
    if (preferencesUtil.isInitialized()) {
      return true;
    }
    try {
      await preferencesUtil.init(context, 'todayStore', true);
      return preferencesUtil.isInitialized();
    } catch (error) {
      hilog.error(0x0000, TAG, `Failed to initialize preferences for widget refresh: ${JSON.stringify(error)}`);
      return false;
    }
  }

  private loadFormIds(): string[] {
    const raw = preferencesUtil.getSync(PreferenceKeys.TODAY_TIMER_WIDGET_FORM_IDS, '') as string;
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as string[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed.filter((value: string) => typeof value === 'string' && value.length > 0);
    } catch (error) {
      return [];
    }
  }
}

export const todayTimerWidgetService = new TodayTimerWidgetServiceImpl();
