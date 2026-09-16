import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { formInfo } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferencesUtil, RDBStoreUtil, StorageKeys } from 'base';

const TAG: string = 'TodayShortcutFormEditAbility';
const DOMAIN: number = 0x0000;
const PAGE_URL: string = 'pages/TodayShortcutFormEditPage';
const FORM_DIMENSION_1X2: string = '1*2';
const FORM_DIMENSION_2X2: string = '2*2';
const STORAGE_FORM_ID: string = 'formId';
const STORAGE_FORM_DIMENSION: string = 'formDimension';
const SHORTCUT_FORM_EDIT_ABILITY_NAME: string = 'TodayShortcutFormEditAbility';

export default class TodayShortcutFormEditAbility extends UIAbility {
  private formId: string = '';
  private formDimension: string = FORM_DIMENSION_2X2;
  private currentWindowStage: window.WindowStage | null = null;

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, TAG, `today shortcut ui-ability onCreate, launchReason=${launchParam.launchReason}`);
    AppStorage.setOrCreate('context', this.context);
    AppStorage.setOrCreate(StorageKeys.SHORTCUT_FORM_EDIT_UI_ABILITY_NAME, SHORTCUT_FORM_EDIT_ABILITY_NAME);
    this.parseWantMetadata(want, 'onCreate');
    await this.initializeDataSources();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'today shortcut ui-ability onDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, `today shortcut ui-ability onNewWant, launchReason=${launchParam.launchReason}`);
    this.parseWantMetadata(want, 'onNewWant');
    if (this.currentWindowStage !== null) {
      this.loadTodayShortcutFormEditPage(this.currentWindowStage);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'today shortcut ui-ability onWindowStageCreate');
    if (this.currentWindowStage === null) {
      this.currentWindowStage = windowStage;
    }
    this.loadTodayShortcutFormEditPage(windowStage);
  }

  onWindowStageDestroy(): void {
    this.currentWindowStage = null;
    hilog.info(DOMAIN, TAG, 'today shortcut ui-ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'today shortcut ui-ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'today shortcut ui-ability onBackground');
  }

  private async initializeDataSources(): Promise<void> {
    try {
      await preferencesUtil.init(this.context, 'todayStore', true);
      hilog.info(DOMAIN, TAG, `today shortcut ui-ability preferences initialized, ready=${preferencesUtil.isInitialized()}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `today shortcut ui-ability initialize preferences failed: ${JSON.stringify(error)}`);
    }

    try {
      RDBStoreUtil.init(this.context);
      await RDBStoreUtil.getInstance().initRDB();
      hilog.info(DOMAIN, TAG, 'today shortcut ui-ability rdb initialized');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `today shortcut ui-ability initialize rdb failed: ${JSON.stringify(error)}`);
    }
  }

  private loadTodayShortcutFormEditPage(windowStage: window.WindowStage): void {
    const storage: LocalStorage = new LocalStorage();
    storage.setOrCreate(STORAGE_FORM_ID, this.formId);
    storage.setOrCreate(STORAGE_FORM_DIMENSION, this.formDimension);
    hilog.info(DOMAIN, TAG,
      `today shortcut ui-ability load content start, page=${PAGE_URL}, formId=${this.formId}, formDimension=${this.formDimension}`);
    windowStage.loadContent(PAGE_URL, storage, (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, `today shortcut ui-ability load content failed: ${JSON.stringify(err)}`);
        return;
      }
      hilog.info(DOMAIN, TAG,
        `today shortcut ui-ability load content success, page=${PAGE_URL}, formId=${this.formId}, formDimension=${this.formDimension}`);
    });
  }

  private parseWantMetadata(want: Want, source: string): void {
    this.formId = this.resolveFormId(want);
    this.formDimension = this.resolveFormDimension(want);
    hilog.info(DOMAIN, TAG,
      `today shortcut ui-ability parse want done, source=${source}, formId=${this.formId}, formDimension=${this.formDimension}, parameters=${this.stringifyParameters(want)}`);
  }

  private resolveFormId(want: Want): string {
    const directFormId = this.toNonEmptyString(want.parameters?.formId);
    if (directFormId.length > 0) {
      return directFormId;
    }
    const cardId = this.toNonEmptyString(want.parameters?.cardId);
    if (cardId.length > 0) {
      return cardId;
    }
    const identityId = this.toNonEmptyString(want.parameters?.[formInfo.FormParam.IDENTITY_KEY]);
    if (identityId.length > 0) {
      return identityId;
    }
    const previewCardId = this.toNonEmptyString(want.parameters?.previewCardId);
    if (previewCardId.length > 0) {
      return previewCardId;
    }
    return '';
  }

  private resolveFormDimension(want: Want): string {
    const customDimension = want.parameters?.formDimension;
    if (typeof customDimension === 'string') {
      if (customDimension === FORM_DIMENSION_1X2) {
        return FORM_DIMENSION_1X2;
      }
      if (customDimension === FORM_DIMENSION_2X2) {
        return FORM_DIMENSION_2X2;
      }
    }
    const rawDimension = want.parameters?.[formInfo.FormParam.DIMENSION_KEY] as number | undefined;
    if (rawDimension === formInfo.FormDimension.Dimension_1_2) {
      return FORM_DIMENSION_1X2;
    }
    const previewDimension = this.toNonEmptyString(want.parameters?.previewDimension);
    if (previewDimension === FORM_DIMENSION_1X2) {
      return FORM_DIMENSION_1X2;
    }
    return FORM_DIMENSION_2X2;
  }

  private stringifyParameters(want: Want): string {
    try {
      return JSON.stringify(want.parameters);
    } catch (error) {
      return `failed_to_stringify_parameters:${JSON.stringify(error)}`;
    }
  }

  private toNonEmptyString(value: Object | string | number | boolean | undefined | null): string {
    if (value === undefined || value === null) {
      return '';
    }
    const result = value.toString();
    if (result.length === 0) {
      return '';
    }
    return result;
  }
}
