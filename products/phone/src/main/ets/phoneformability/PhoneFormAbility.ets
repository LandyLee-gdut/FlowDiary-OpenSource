import { formBindingData, formProvider, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IdeaSnapshotWidgetData, ideaSnapshotWidgetService } from '../ideasnapshot/model/IdeaSnapshotWidgetService';
import { ReflectTodayWidgetData, reflectTodayWidgetService } from '../reflecttoday/model/ReflectTodayWidgetService';
import { TodayShortcutWidgetData, todayShortcutWidgetService } from '../shortcut/model/TodayShortcutWidgetService';
import { TagDistributionWidgetData, tagDistributionWidgetService } from '../tagdistribution/model/TagDistributionWidgetService';
import { TodayOverviewWidgetData, todayOverviewWidgetService } from '../todayoverview/model/TodayOverviewWidgetService';
import { TodayRecordWidgetData, todayRecordWidgetService } from '../todayrecordwidget/model/TodayRecordWidgetService';
import { TodayTimerWidgetData, todayTimerWidgetService } from '../todaytimerwidget/model/TodayTimerWidgetService';

const TAG: string = 'PhoneFormAbility';

class TodayRecordWidgetFormData {
  formDimension: string = '';
  todayRecordWidgetItems: string = '';
  todayRecordWidgetTotalDuration: string = '';
}

class TodayOverviewWidgetFormData {
  formDimension: string = '';
  todayOverviewTotalDuration: string = '';
  todayOverviewItemCount: string = '';
}

class TodayTimerWidgetFormData {
  todayTimerWidgetState: string = '';
  todayTimerWidgetTitle: string = '';
  todayTimerWidgetColor: string = '';
  todayTimerWidgetElapsedSeconds: string = '';
  todayTimerWidgetStartToken: string = '';
  todayTimerWidgetStartTime: string = '';
}

class IdeaSnapshotWidgetFormData {
  formDimension: string = '';
  ideaSnapshotUnlitCount: string = '';
  ideaSnapshotLatestTitle: string = '';
}

class TagDistributionWidgetFormData {
  formDimension: string = '';
  tagDistributionWidgetItems: string = '';
}

class ReflectTodayWidgetFormData {
  formDimension: string = '';
  reflectTodayWidgetSegments: string = '';
  reflectTodayWidgetTotalDuration: string = '';
}

class TodayShortcutWidgetFormData {
  formDimension: string = '';
  todayShortcutBinding: string = '';
}

const FORM_DIMENSION_1X2: string = '1*2';
const FORM_DIMENSION_2X2: string = '2*2';
const FORM_DIMENSION_2X4: string = '2*4';
const FORM_NAME_TODAY_RECORD: string = 'todayRecordWidget';
const FORM_NAME_TODAY_OVERVIEW: string = 'TodayOverview';
const FORM_NAME_TODAY_TIMER: string = 'TodayTimer';
const FORM_NAME_IDEA_SNAPSHOT: string = 'IdeaSnapshot';
const FORM_NAME_TAG_DISTRIBUTION: string = 'TagDistribution';
const FORM_NAME_REFLECT_TODAY: string = 'ReflectToday';
const FORM_NAME_SHORTCUT: string = 'ShortCut';

export default class PhoneFormAbility extends FormExtensionAbility {
  private formDimensions: Map<string, string> = new Map();
  private formTypes: Map<string, string> = new Map();

  onAddForm(want: Want): formBindingData.FormBindingData {
    // Called to return a FormBindingData object.
    const formName = this.resolveFormName(want);
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string | undefined;
    const dimensionParam = want.parameters?.[formInfo.FormParam.DIMENSION_KEY] as number | undefined;
    const dimension = this.resolveDimension(dimensionParam);
    if (formName === FORM_NAME_TODAY_TIMER) {
      const formData = this.buildTodayTimerFormData(null);
      if (formId && formId.length > 0) {
        this.formTypes.set(formId, formName);
        void todayTimerWidgetService.registerForm(this.context, formId);
        this.refreshTodayTimerFormData(formId);
      }
      return formBindingData.createFormBindingData(formData);
    }
    if (formName === FORM_NAME_TODAY_OVERVIEW) {
      const formData = this.buildTodayOverviewFormData(dimension, null);
      if (formId && formId.length > 0) {
        this.formTypes.set(formId, formName);
        this.formDimensions.set(formId, dimension);
        void todayOverviewWidgetService.registerForm(this.context, formId, dimension);
        this.refreshOverviewFormData(formId, dimension);
      }
      return formBindingData.createFormBindingData(formData);
    }
    if (formName === FORM_NAME_IDEA_SNAPSHOT) {
      const formData = this.buildIdeaSnapshotFormData(dimension, null);
      if (formId && formId.length > 0) {
        this.formTypes.set(formId, formName);
        this.formDimensions.set(formId, dimension);
        void ideaSnapshotWidgetService.registerForm(this.context, formId, dimension);
        this.refreshIdeaSnapshotFormData(formId, dimension);
      }
      return formBindingData.createFormBindingData(formData);
    }
    if (formName === FORM_NAME_TAG_DISTRIBUTION) {
      const formData = this.buildTagDistributionFormData(dimension, null);
      if (formId && formId.length > 0) {
        this.formTypes.set(formId, formName);
        this.formDimensions.set(formId, dimension);
        void tagDistributionWidgetService.registerForm(this.context, formId, dimension);
        this.refreshTagDistributionFormData(formId, dimension);
      }
      return formBindingData.createFormBindingData(formData);
    }
    if (formName === FORM_NAME_REFLECT_TODAY) {
      const formData = this.buildReflectTodayFormData(dimension, null);
      if (formId && formId.length > 0) {
        this.formTypes.set(formId, formName);
        this.formDimensions.set(formId, dimension);
        void reflectTodayWidgetService.registerForm(this.context, formId, dimension);
        this.refreshReflectTodayFormData(formId, dimension);
      }
      return formBindingData.createFormBindingData(formData);
    }
    if (formName === FORM_NAME_SHORTCUT) {
      const formData = this.buildTodayShortcutFormData(dimension, null);
      if (formId && formId.length > 0) {
        this.formTypes.set(formId, formName);
        this.formDimensions.set(formId, dimension);
        void todayShortcutWidgetService.registerForm(this.context, formId, dimension);
        this.refreshTodayShortcutFormData(formId, dimension);
      }
      return formBindingData.createFormBindingData(formData);
    }
    const formData = this.buildTodayRecordFormData(dimension, null);
    if (formId && formId.length > 0) {
      this.formTypes.set(formId, FORM_NAME_TODAY_RECORD);
      this.formDimensions.set(formId, dimension);
      void todayRecordWidgetService.registerForm(this.context, formId, dimension);
      this.refreshTodayRecordFormData(formId, dimension);
    }
    return formBindingData.createFormBindingData(formData);
  }

  onCastToNormalForm(formId: string): void {
    // Called when the form provider is notified that a temporary form is successfully
    // converted to a normal form.
  }

  async onUpdateForm(formId: string) {
    // Called to notify the form provider to update a specified form.
    await this.handleFormRefresh(formId);
  }

  async onFormEvent(formId: string, message: string) {
    // Called when a specified message event defined by the form provider is triggered.
    hilog.info(0x0000, TAG, `onFormEvent formId: ${formId}, message: ${message}`);
    await this.handleFormRefresh(formId);
  }

  onRemoveForm(formId: string): void {
    // Called to notify the form provider that a specified form has been destroyed.
    const formType = this.formTypes.get(formId);
    this.formTypes.delete(formId);
    this.formDimensions.delete(formId);
    if (formType === FORM_NAME_TODAY_TIMER) {
      void todayTimerWidgetService.unregisterForm(this.context, formId);
      return;
    }
    if (formType === FORM_NAME_TODAY_OVERVIEW) {
      void todayOverviewWidgetService.unregisterForm(this.context, formId);
      return;
    }
    if (formType === FORM_NAME_TODAY_RECORD) {
      void todayRecordWidgetService.unregisterForm(this.context, formId);
      return;
    }
    if (formType === FORM_NAME_IDEA_SNAPSHOT) {
      void ideaSnapshotWidgetService.unregisterForm(this.context, formId);
      return;
    }
    if (formType === FORM_NAME_TAG_DISTRIBUTION) {
      void tagDistributionWidgetService.unregisterForm(this.context, formId);
      return;
    }
    if (formType === FORM_NAME_REFLECT_TODAY) {
      void reflectTodayWidgetService.unregisterForm(this.context, formId);
      return;
    }
    if (formType === FORM_NAME_SHORTCUT) {
      void todayShortcutWidgetService.unregisterForm(this.context, formId);
      return;
    }
    void todayRecordWidgetService.unregisterForm(this.context, formId);
    void todayOverviewWidgetService.unregisterForm(this.context, formId);
    void todayTimerWidgetService.unregisterForm(this.context, formId);
    void ideaSnapshotWidgetService.unregisterForm(this.context, formId);
    void tagDistributionWidgetService.unregisterForm(this.context, formId);
    void reflectTodayWidgetService.unregisterForm(this.context, formId);
    void todayShortcutWidgetService.unregisterForm(this.context, formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    // Called to return a {@link FormState} object.
    return formInfo.FormState.READY;
  }

  private resolveDimension(dimension: number | undefined): string {
    if (dimension === formInfo.FormDimension.Dimension_1_2) {
      return FORM_DIMENSION_1X2;
    }
    if (dimension === formInfo.FormDimension.Dimension_2_4) {
      return FORM_DIMENSION_2X4;
    }
    return FORM_DIMENSION_2X2;
  }

  private resolveFormName(want: Want): string {
    const name = want.parameters?.[formInfo.FormParam.NAME_KEY] as string | undefined;
    return name ?? '';
  }

  private buildTodayRecordFormData(dimension: string, data: TodayRecordWidgetData | null): TodayRecordWidgetFormData {
    const formData = new TodayRecordWidgetFormData();
    formData.formDimension = dimension;
    formData.todayRecordWidgetItems = data ? JSON.stringify(data.items) : '[]';
    formData.todayRecordWidgetTotalDuration = data ? data.totalDurationMs.toString() : '0';
    return formData;
  }

  private buildTodayOverviewFormData(dimension: string, data: TodayOverviewWidgetData | null): TodayOverviewWidgetFormData {
    const formData = new TodayOverviewWidgetFormData();
    formData.formDimension = dimension;
    formData.todayOverviewTotalDuration = data ? data.totalDurationMs.toString() : '0';
    formData.todayOverviewItemCount = data ? data.itemCount.toString() : '0';
    return formData;
  }

  private buildTodayTimerFormData(data: TodayTimerWidgetData | null): TodayTimerWidgetFormData {
    const formData = new TodayTimerWidgetFormData();
    formData.todayTimerWidgetState = data ? data.state : '';
    formData.todayTimerWidgetTitle = data ? data.title : '';
    formData.todayTimerWidgetColor = data ? data.colorHex : '';
    formData.todayTimerWidgetElapsedSeconds = data ? data.elapsedSeconds.toString() : '0';
    formData.todayTimerWidgetStartToken = data ? data.startToken : '';
    
    if (data && data.startTime > 0) {
      const date = new Date(data.startTime);
      const hours = date.getHours().toString().padStart(2, '0');
      const minutes = date.getMinutes().toString().padStart(2, '0');
      formData.todayTimerWidgetStartTime = `${hours}:${minutes}`;
    } else {
      formData.todayTimerWidgetStartTime = '';
    }
    
    return formData;
  }

  private buildIdeaSnapshotFormData(dimension: string, data: IdeaSnapshotWidgetData | null): IdeaSnapshotWidgetFormData {
    const formData = new IdeaSnapshotWidgetFormData();
    formData.formDimension = dimension;
    formData.ideaSnapshotUnlitCount = data ? data.unlitCount.toString() : '0';
    formData.ideaSnapshotLatestTitle = data ? data.latestIdeaTitle : '';
    return formData;
  }

  private buildTagDistributionFormData(dimension: string, data: TagDistributionWidgetData | null): TagDistributionWidgetFormData {
    const formData = new TagDistributionWidgetFormData();
    formData.formDimension = dimension;
    formData.tagDistributionWidgetItems = data ? JSON.stringify(data.items) : '[]';
    return formData;
  }

  private buildReflectTodayFormData(dimension: string, data: ReflectTodayWidgetData | null): ReflectTodayWidgetFormData {
    const formData = new ReflectTodayWidgetFormData();
    formData.formDimension = dimension;
    formData.reflectTodayWidgetSegments = data ? JSON.stringify(data.segments) : '[]';
    formData.reflectTodayWidgetTotalDuration = data ? data.totalDurationMs.toString() : '0';
    return formData;
  }

  private buildTodayShortcutFormData(
    dimension: string,
    data: TodayShortcutWidgetData | null
  ): TodayShortcutWidgetFormData {
    const formData = new TodayShortcutWidgetFormData();
    formData.formDimension = dimension === FORM_DIMENSION_1X2 ? FORM_DIMENSION_1X2 : FORM_DIMENSION_2X2;
    formData.todayShortcutBinding = data && data.binding ? JSON.stringify(data.binding) : '';
    return formData;
  }

  private async refreshTodayRecordFormData(formId: string, dimension: string): Promise<void> {
    try {
      const data = await todayRecordWidgetService.getTodayRecordWidgetData(this.context);
      const formData = this.buildTodayRecordFormData(dimension, data);
      const binding = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, binding);
    } catch (error) {
      hilog.error(0x0000, TAG, `refreshTodayRecordFormData failed: ${JSON.stringify(error)}`);
    }
  }

  private async refreshOverviewFormData(formId: string, dimension: string): Promise<void> {
    try {
      const data = await todayOverviewWidgetService.getTodayOverviewWidgetData(this.context);
      const formData = this.buildTodayOverviewFormData(dimension, data);
      const binding = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, binding);
    } catch (error) {
      hilog.error(0x0000, TAG, `refreshOverviewFormData failed: ${JSON.stringify(error)}`);
    }
  }

  private async refreshTodayTimerFormData(formId: string): Promise<void> {
    try {
      const data = await todayTimerWidgetService.getTodayTimerWidgetData(this.context);
      const formData = this.buildTodayTimerFormData(data);
      const binding = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, binding);
    } catch (error) {
      hilog.error(0x0000, TAG, `refreshTodayTimerFormData failed: ${JSON.stringify(error)}`);
    }
  }

  private async refreshIdeaSnapshotFormData(formId: string, dimension: string): Promise<void> {
    try {
      const data = await ideaSnapshotWidgetService.getIdeaSnapshotWidgetData(this.context);
      const formData = this.buildIdeaSnapshotFormData(dimension, data);
      const binding = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, binding);
    } catch (error) {
      hilog.error(0x0000, TAG, `refreshIdeaSnapshotFormData failed: ${JSON.stringify(error)}`);
    }
  }

  private async refreshTagDistributionFormData(formId: string, dimension: string): Promise<void> {
    try {
      const data = await tagDistributionWidgetService.getTagDistributionWidgetData(this.context);
      const formData = this.buildTagDistributionFormData(dimension, data);
      const binding = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, binding);
    } catch (error) {
      hilog.error(0x0000, TAG, `refreshTagDistributionFormData failed: ${JSON.stringify(error)}`);
    }
  }

  private async refreshReflectTodayFormData(formId: string, dimension: string): Promise<void> {
    try {
      const data = await reflectTodayWidgetService.getReflectTodayWidgetData(this.context);
      const formData = this.buildReflectTodayFormData(dimension, data);
      const binding = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, binding);
    } catch (error) {
      hilog.error(0x0000, TAG, `refreshReflectTodayFormData failed: ${JSON.stringify(error)}`);
    }
  }

  private async refreshTodayShortcutFormData(formId: string, dimension: string): Promise<void> {
    try {
      const data = await todayShortcutWidgetService.getWidgetData(this.context, formId, dimension);
      const formData = this.buildTodayShortcutFormData(dimension, data);
      const binding = formBindingData.createFormBindingData(formData);
      await formProvider.updateForm(formId, binding);
    } catch (error) {
      hilog.error(0x0000, TAG, `refreshTodayShortcutFormData failed: ${JSON.stringify(error)}`);
    }
  }

  private async refreshOverviewFormById(formId: string): Promise<void> {
    const dimension = this.formDimensions.get(formId);
    if (dimension) {
      await this.refreshOverviewFormData(formId, dimension);
      return;
    }

    const refreshed = await todayOverviewWidgetService.refreshFormById(this.context, formId);
    if (!refreshed) {
      await todayOverviewWidgetService.refreshRegisteredForms(this.context);
    }
  }

  private async refreshTodayRecordFormById(formId: string): Promise<void> {
    const dimension = this.formDimensions.get(formId);
    if (dimension) {
      await this.refreshTodayRecordFormData(formId, dimension);
      return;
    }

    const refreshed = await todayRecordWidgetService.refreshFormById(this.context, formId);
    if (!refreshed) {
      await todayRecordWidgetService.refreshRegisteredForms(this.context);
    }
  }

  private async refreshIdeaSnapshotFormById(formId: string): Promise<void> {
    const dimension = this.formDimensions.get(formId);
    if (dimension) {
      await this.refreshIdeaSnapshotFormData(formId, dimension);
      return;
    }

    const refreshed = await ideaSnapshotWidgetService.refreshFormById(this.context, formId);
    if (!refreshed) {
      await ideaSnapshotWidgetService.refreshRegisteredForms(this.context);
    }
  }

  private async refreshTagDistributionFormById(formId: string): Promise<void> {
    const dimension = this.formDimensions.get(formId);
    if (dimension) {
      await this.refreshTagDistributionFormData(formId, dimension);
      return;
    }

    const refreshed = await tagDistributionWidgetService.refreshFormById(this.context, formId);
    if (!refreshed) {
      await tagDistributionWidgetService.refreshRegisteredForms(this.context);
    }
  }

  private async refreshReflectTodayFormById(formId: string): Promise<void> {
    const dimension = this.formDimensions.get(formId);
    if (dimension) {
      await this.refreshReflectTodayFormData(formId, dimension);
      return;
    }

    const refreshed = await reflectTodayWidgetService.refreshFormById(this.context, formId);
    if (!refreshed) {
      await reflectTodayWidgetService.refreshRegisteredForms(this.context);
    }
  }

  private async refreshTodayShortcutFormById(formId: string): Promise<void> {
    const dimension = this.formDimensions.get(formId);
    if (dimension) {
      await this.refreshTodayShortcutFormData(formId, dimension);
      return;
    }

    const refreshed = await todayShortcutWidgetService.refreshFormById(this.context, formId);
    if (!refreshed) {
      await todayShortcutWidgetService.refreshRegisteredForms(this.context);
    }
  }

  private async handleFormRefresh(formId: string): Promise<void> {
    if (!formId || formId.length === 0) {
      await todayRecordWidgetService.refreshRegisteredForms(this.context);
      await todayOverviewWidgetService.refreshRegisteredForms(this.context);
      await todayTimerWidgetService.refreshRegisteredForms(this.context);
      await ideaSnapshotWidgetService.refreshRegisteredForms(this.context);
      await tagDistributionWidgetService.refreshRegisteredForms(this.context);
      await reflectTodayWidgetService.refreshRegisteredForms(this.context);
      await todayShortcutWidgetService.refreshRegisteredForms(this.context);
      return;
    }

    const formType = this.formTypes.get(formId);
    if (formType === FORM_NAME_TODAY_OVERVIEW) {
      await this.refreshOverviewFormById(formId);
      return;
    }
    if (formType === FORM_NAME_TODAY_TIMER) {
      await this.refreshTodayTimerFormData(formId);
      return;
    }
    if (formType === FORM_NAME_TODAY_RECORD) {
      await this.refreshTodayRecordFormById(formId);
      return;
    }
    if (formType === FORM_NAME_IDEA_SNAPSHOT) {
      await this.refreshIdeaSnapshotFormById(formId);
      return;
    }
    if (formType === FORM_NAME_TAG_DISTRIBUTION) {
      await this.refreshTagDistributionFormById(formId);
      return;
    }
    if (formType === FORM_NAME_REFLECT_TODAY) {
      await this.refreshReflectTodayFormById(formId);
      return;
    }
    if (formType === FORM_NAME_SHORTCUT) {
      await this.refreshTodayShortcutFormById(formId);
      return;
    }

    const overviewRegistered = await todayOverviewWidgetService.isRegisteredForm(this.context, formId);
    if (overviewRegistered) {
      await this.refreshOverviewFormById(formId);
      return;
    }

    const recordRegistered = await todayRecordWidgetService.isRegisteredForm(this.context, formId);
    if (recordRegistered) {
      await this.refreshTodayRecordFormById(formId);
      return;
    }

    const timerRegistered = await todayTimerWidgetService.isRegisteredForm(this.context, formId);
    if (timerRegistered) {
      await this.refreshTodayTimerFormData(formId);
      return;
    }

    const ideaSnapshotRegistered = await ideaSnapshotWidgetService.isRegisteredForm(this.context, formId);
    if (ideaSnapshotRegistered) {
      await this.refreshIdeaSnapshotFormById(formId);
      return;
    }

    const tagDistributionRegistered = await tagDistributionWidgetService.isRegisteredForm(this.context, formId);
    if (tagDistributionRegistered) {
      await this.refreshTagDistributionFormById(formId);
      return;
    }

    const reflectTodayRegistered = await reflectTodayWidgetService.isRegisteredForm(this.context, formId);
    if (reflectTodayRegistered) {
      await this.refreshReflectTodayFormById(formId);
      return;
    }

    const shortcutRegistered = await todayShortcutWidgetService.isRegisteredForm(this.context, formId);
    if (shortcutRegistered) {
      await this.refreshTodayShortcutFormById(formId);
      return;
    }

    await todayRecordWidgetService.refreshRegisteredForms(this.context);
    await todayOverviewWidgetService.refreshRegisteredForms(this.context);
    await todayTimerWidgetService.refreshRegisteredForms(this.context);
    await ideaSnapshotWidgetService.refreshRegisteredForms(this.context);
    await tagDistributionWidgetService.refreshRegisteredForms(this.context);
    await reflectTodayWidgetService.refreshRegisteredForms(this.context);
    await todayShortcutWidgetService.refreshRegisteredForms(this.context);
  }
}
