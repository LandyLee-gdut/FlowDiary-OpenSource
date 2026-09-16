/**
 * Storage keys for shared AppStorage values
 * These keys are used to synchronize date selection across components
 */
export class StorageKeys {
  // Date selection keys
  static readonly SELECTED_DATE: string = 'selectedDate';
  static readonly SELECTED_MONTH: string = 'selectedMonth';
  static readonly SELECTED_YEAR: string = 'selectedYear';
  // Calendar view keys (month navigation)
  static readonly VIEW_DATE: string = 'viewDate';
  static readonly VIEW_MONTH: string = 'viewMonth';
  static readonly VIEW_YEAR: string = 'viewYear';
  // Reflect refresh revision
  static readonly REFLECT_REFRESH_REVISION: string = 'reflectRefreshRevision';
  static readonly REFLECT_CALENDAR_REVISION: string = 'reflectCalendarRevision';
  static readonly REFLECT_CHART_SETTINGS_REVISION: string = 'reflectChartSettingsRevision';
  static readonly AUTO_BACKUP_ENABLED: string = 'autoBackupEnabled';
  static readonly AUTO_BACKUP_LAST_RUN_AT: string = 'autoBackupLastRunAt';
  static readonly AUTO_BACKUP_LAST_ERROR_CODE: string = 'autoBackupLastErrorCode';
  static readonly PHONE_UI_ABILITY_NAME: string = 'phoneUiAbilityName';
  static readonly SHORTCUT_FORM_EDIT_UI_ABILITY_NAME: string = 'shortcutFormEditUiAbilityName';
}
