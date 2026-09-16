import { SettingsActionRow, SettingsToggleRow } from './SettingsControlRows';
import { SettingsPageHeader } from './SettingsPageHeader';
import { REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION } from '../ReflectChartSettingsMotionTokens';

@Component
export struct BackupSettingsPage {
  @Prop autoBackupEnabled: boolean = false;
  @Prop manualExportStatusText: string = '';
  @Prop manualImportStatusText: string = '';
  @Prop restoreAutoStatusText: string = '';
  @Prop autoBackupStatusText: string = '';
  onBack?: () => void;
  onManualBackupExport?: () => void;
  onManualBackupImport?: () => void;
  onRestoreAutoBackup?: () => void;
  onAutoBackupToggle?: (isOn: boolean) => void;
  private pageInfos: NavPathStack = new NavPathStack();

  private handleBack(): void {
    if (this.onBack) {
      this.onBack();
      return;
    }
    this.pageInfos.pop(1);
  }

  build() {
    NavDestination() {
      Column() {
        SettingsPageHeader({
          title: $r('app.string.settings_entry_backup'),
          onAction: () => {
            this.handleBack();
          }
        })

        List({ space: 0 }) {
          ListItem() {
            SettingsActionRow({
              title: $r('app.string.backup_manual_export'),
              detail: $r('app.string.backup_manual_export_desc'),
              statusText: this.manualExportStatusText,
              icon: $r('sys.symbol.save'),
              onAction: () => {
                this.onManualBackupExport?.();
              }
            })
          }
          .borderRadius({
            topLeft: $r('app.float.settings_card_radius'),
            topRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsActionRow({
              title: $r('app.string.backup_manual_import'),
              detail: $r('app.string.backup_manual_import_desc'),
              statusText: this.manualImportStatusText,
              icon: $r('sys.symbol.chevron_down_2_circle'),
              onAction: () => {
                this.onManualBackupImport?.();
              }
            })
          }
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsActionRow({
              title: $r('app.string.backup_restore_auto'),
              detail: $r('app.string.backup_restore_auto_desc'),
              statusText: this.restoreAutoStatusText,
              icon: $r('sys.symbol.externaldrive'),
              onAction: () => {
                this.onRestoreAutoBackup?.();
              }
            })
          }
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsToggleRow({
              title: $r('app.string.backup_auto_toggle'),
              detail: $r('app.string.backup_auto_toggle_detail'),
              icon: $r('sys.symbol.clock'),
              checked: this.autoBackupEnabled,
              onChange: (isOn: boolean) => {
                this.onAutoBackupToggle?.(isOn);
              }
            })
          }
          .borderRadius({
            bottomLeft: $r('app.float.settings_card_radius'),
            bottomRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))
        }
        .width('100%')
        .scrollBar(BarState.Off)

        if (this.autoBackupStatusText.length > 0) {
          Text(this.autoBackupStatusText)
            .width('100%')
            .fontSize($r('app.float.settings_detail_tip_font_size'))
            .lineHeight($r('app.float.settings_detail_tip_line_height'))
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .margin({ top: $r('app.float.settings_detail_tip_margin_top') })
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: $r('app.float.settings_page_padding_horizontal'),
        right: $r('app.float.settings_page_padding_horizontal'),
        bottom: $r('app.float.settings_page_padding_bottom')
      })
      .backgroundColor($r('app.color.bg_main'))
    }
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack;
    })
    .onBackPressed((): boolean => {
      this.handleBack();
      return true;
    })
    .hideTitleBar(true)
    .systemTransition(REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_main'))
  }
}
