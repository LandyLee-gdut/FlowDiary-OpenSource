import { hilog } from '@kit.PerformanceAnalysisKit';
import { AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT } from '../model/AutoStopSettings';
import { CalendarSyncSettingsPage } from './CalendarSyncSettingsPage';
import { EditSwissKnifePage } from './EditSwissKnifePage';
import { ReflectChartVisibilitySettingsPage } from './ReflectChartVisibilitySettingsPage';
import { TagSettingsPage } from './TagSettingsPage';
import { AboutSettingsPage } from './settings/AboutSettingsPage';
import { AppearanceSettingsPage } from './settings/AppearanceSettingsPage';
import { BackupSettingsPage } from './settings/BackupSettingsPage';
import { IdeaPoolSettingsPage } from './settings/IdeaPoolSettingsPage';
import { RecordSettingsPage } from './settings/RecordSettingsPage';
import { SettingsHomePage } from './settings/SettingsHomePage';
import { SettingsRoutes } from './settings/SettingsRoutes';

const TAG: string = 'TodaySettingsSheetContent';

@Component
export struct TodaySettingsSheetContent {
  @Prop directStartEnabled: boolean = false;
  @Prop autoStopEnabled: boolean = false;
  @Prop autoStopLimitHalfHours: number = AUTO_STOP_LIMIT_HALF_HOURS_DEFAULT;
  @Prop calendarSyncEnabled: boolean = false;
  @Prop calendarSyncPermissionGranted: boolean = true;
  @Prop defaultLinePanelEnabled: boolean = false;
  @Prop floatingActionBarEnabled: boolean = false;
  @Prop ideapoolUnlitFirst: boolean = true;
  @Prop ideapoolDirectRecordEnabled: boolean = false;
  @Prop isDarkTheme: boolean = false;
  @Prop autoBackupEnabled: boolean = false;
  @Prop manualExportStatusText: string = '';
  @Prop manualImportStatusText: string = '';
  @Prop restoreAutoStatusText: string = '';
  @Prop autoBackupStatusText: string = '';
  @Prop holdingHandEnabled: boolean = false;
  @Prop holdingHandOffsetPercent: number = 0;
  @Prop currentBreakpoint: string = '';
  @Link tabSelectedIndexes: number[];
  @Link isSettingsSubPageActive: boolean;
  onClose?: () => void;
  onDirectStartToggle?: (isOn: boolean) => void;
  onAutoStopEnabledChange?: (enabled: boolean) => void;
  onAutoStopLimitHalfHoursChange?: (limitHalfHours: number) => void;
  onCalendarSyncToggle?: (isOn: boolean) => Promise<void> | void;
  onCalendarResyncCopyClick?: () => Promise<void> | void;
  onCalendarPermissionRecoverClick?: () => Promise<void> | void;
  onDefaultLinePanelToggle?: (isOn: boolean) => void;
  onFloatingActionBarToggle?: (isOn: boolean) => void;
  onIdeaPoolOrderToggle?: (isOn: boolean) => void;
  onIdeaPoolDirectRecordToggle?: (isOn: boolean) => void;
  onOpenUserGuide?: () => void;
  onManualBackupExport?: () => void;
  onManualBackupImport?: () => void;
  onRestoreAutoBackup?: () => void;
  onAutoBackupToggle?: (isOn: boolean) => void;
  onHoldingHandToggle?: (isOn: boolean) => void;
  onHoldingHandOffsetChange?: (nextValue: number) => void;
  onResetReflectChartSettings?: () => void;
  onTagDataChanged?: () => Promise<void> | void;
  private settingsNavStack: NavPathStack = new NavPathStack();

  aboutToDisappear(): void {
    this.resetNavigationState();
  }

  private pushSettingsSubPage(pageName: string): void {
    if (this.isSettingsSubPageActive) {
      return;
    }
    hilog.info(0x0000, TAG, `[Settings] push sub page: ${pageName}`);
    this.isSettingsSubPageActive = true;
    this.settingsNavStack.pushPathByName(pageName, undefined, () => {
      this.isSettingsSubPageActive = false;
    });
  }

  private handleBackToSettings(): void {
    if (!this.isSettingsSubPageActive) {
      return;
    }
    this.settingsNavStack.pop(1);
  }

  private resetNavigationState(): void {
    this.isSettingsSubPageActive = false;
    this.settingsNavStack.clear();
  }

  private handleClose(): void {
    this.resetNavigationState();
    this.onClose?.();
  }

  @Builder
  private settingsPageMap(name: string): void {
    if (name === SettingsRoutes.RECORD) {
      RecordSettingsPage({
        directStartEnabled: this.directStartEnabled,
        autoStopEnabled: this.autoStopEnabled,
        autoStopLimitHalfHours: this.autoStopLimitHalfHours,
        defaultLinePanelEnabled: this.defaultLinePanelEnabled,
        onBack: () => {
          this.handleBackToSettings();
        },
        onDirectStartToggle: (isOn: boolean) => {
          this.onDirectStartToggle?.(isOn);
        },
        onAutoStopEnabledChange: (enabled: boolean) => {
          this.onAutoStopEnabledChange?.(enabled);
        },
        onAutoStopLimitHalfHoursChange: (limitHalfHours: number) => {
          this.onAutoStopLimitHalfHoursChange?.(limitHalfHours);
        },
        onDefaultLinePanelToggle: (isOn: boolean) => {
          this.onDefaultLinePanelToggle?.(isOn);
        }
      })
    } else if (name === SettingsRoutes.CALENDAR_SYNC) {
      CalendarSyncSettingsPage({
        calendarSyncEnabled: this.calendarSyncEnabled,
        calendarSyncPermissionGranted: this.calendarSyncPermissionGranted,
        onBack: () => {
          this.handleBackToSettings();
        },
        onCalendarSyncToggle: (isOn: boolean) => {
          return this.onCalendarSyncToggle?.(isOn);
        },
        onCalendarResyncCopyClick: () => {
          return this.onCalendarResyncCopyClick?.();
        },
        onCalendarPermissionRecoverClick: () => {
          return this.onCalendarPermissionRecoverClick?.();
        }
      })
    } else if (name === SettingsRoutes.TAG) {
      TagSettingsPage({
        onBack: () => {
          this.handleBackToSettings();
        },
        onTagDataChanged: async () => {
          await this.onTagDataChanged?.();
        }
      })
    } else if (name === SettingsRoutes.IDEA_POOL) {
      IdeaPoolSettingsPage({
        ideapoolUnlitFirst: this.ideapoolUnlitFirst,
        ideapoolDirectRecordEnabled: this.ideapoolDirectRecordEnabled,
        onBack: () => {
          this.handleBackToSettings();
        },
        onIdeaPoolOrderToggle: (isOn: boolean) => {
          this.onIdeaPoolOrderToggle?.(isOn);
        },
        onIdeaPoolDirectRecordToggle: (isOn: boolean) => {
          this.onIdeaPoolDirectRecordToggle?.(isOn);
        }
      })
    } else if (name === SettingsRoutes.REFLECT_CHART) {
      ReflectChartVisibilitySettingsPage({
        onBack: () => {
          this.handleBackToSettings();
        },
        onResetToDefault: () => {
          this.onResetReflectChartSettings?.();
        }
      })
    } else if (name === SettingsRoutes.APPEARANCE) {
      AppearanceSettingsPage({
        floatingActionBarEnabled: this.floatingActionBarEnabled,
        isDarkTheme: this.isDarkTheme,
        holdingHandEnabled: this.holdingHandEnabled,
        holdingHandOffsetPercent: this.holdingHandOffsetPercent,
        currentBreakpoint: this.currentBreakpoint,
        tabSelectedIndexes: this.tabSelectedIndexes,
        onBack: () => {
          this.handleBackToSettings();
        },
        onFloatingActionBarToggle: (isOn: boolean) => {
          this.onFloatingActionBarToggle?.(isOn);
        },
        onHoldingHandToggle: (isOn: boolean) => {
          this.onHoldingHandToggle?.(isOn);
        },
        onHoldingHandOffsetChange: (nextValue: number) => {
          this.onHoldingHandOffsetChange?.(nextValue);
        }
      })
    } else if (name === SettingsRoutes.QUICK_LAUNCH) {
      EditSwissKnifePage({
        onBack: () => {
          this.handleBackToSettings();
        }
      })
    } else if (name === SettingsRoutes.BACKUP) {
      BackupSettingsPage({
        autoBackupEnabled: this.autoBackupEnabled,
        manualExportStatusText: this.manualExportStatusText,
        manualImportStatusText: this.manualImportStatusText,
        restoreAutoStatusText: this.restoreAutoStatusText,
        autoBackupStatusText: this.autoBackupStatusText,
        onBack: () => {
          this.handleBackToSettings();
        },
        onManualBackupExport: () => {
          this.onManualBackupExport?.();
        },
        onManualBackupImport: () => {
          this.onManualBackupImport?.();
        },
        onRestoreAutoBackup: () => {
          this.onRestoreAutoBackup?.();
        },
        onAutoBackupToggle: (isOn: boolean) => {
          this.onAutoBackupToggle?.(isOn);
        }
      })
    } else if (name === SettingsRoutes.ABOUT) {
      AboutSettingsPage({
        onBack: () => {
          this.handleBackToSettings();
        },
        onOpenUserGuide: () => {
          this.onOpenUserGuide?.();
        }
      })
    }
  }

  build() {
    Navigation(this.settingsNavStack) {
      SettingsHomePage({
        onClose: () => {
          this.handleClose();
        },
        onOpenRecordSettings: () => {
          this.pushSettingsSubPage(SettingsRoutes.RECORD);
        },
        onOpenCalendarSyncSettings: () => {
          this.pushSettingsSubPage(SettingsRoutes.CALENDAR_SYNC);
        },
        onOpenTagSettings: () => {
          this.pushSettingsSubPage(SettingsRoutes.TAG);
        },
        onOpenIdeaPoolSettings: () => {
          this.pushSettingsSubPage(SettingsRoutes.IDEA_POOL);
        },
        onOpenReflectChartSettings: () => {
          this.pushSettingsSubPage(SettingsRoutes.REFLECT_CHART);
        },
        onOpenAppearanceSettings: () => {
          this.pushSettingsSubPage(SettingsRoutes.APPEARANCE);
        },
        onOpenQuickLaunchSettings: () => {
          this.pushSettingsSubPage(SettingsRoutes.QUICK_LAUNCH);
        },
        onOpenBackupSettings: () => {
          this.pushSettingsSubPage(SettingsRoutes.BACKUP);
        },
        onOpenAboutSettings: () => {
          this.pushSettingsSubPage(SettingsRoutes.ABOUT);
        }
      })
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .hideToolBar(true)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.settingsPageMap)
  }
}
