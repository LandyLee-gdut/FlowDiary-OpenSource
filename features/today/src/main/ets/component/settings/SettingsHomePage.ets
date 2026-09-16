import { VibratorUtil } from 'base';
import { SettingsEntryRow, SettingsSectionHeader } from './SettingsEntryRow';
import { SettingsPageHeader } from './SettingsPageHeader';

@Component
export struct SettingsHomePage {
  onClose?: () => void;
  onOpenRecordSettings?: () => void;
  onOpenCalendarSyncSettings?: () => void;
  onOpenTagSettings?: () => void;
  onOpenIdeaPoolSettings?: () => void;
  onOpenReflectChartSettings?: () => void;
  onOpenAppearanceSettings?: () => void;
  onOpenQuickLaunchSettings?: () => void;
  onOpenBackupSettings?: () => void;
  onOpenAboutSettings?: () => void;
  private readonly vibratorUtil: VibratorUtil = VibratorUtil.getInstance();

  private handleEntryClick(onOpen?: () => void): void {
    void this.vibratorUtil.triggerHaptic('haptic.effect.sharp', 'touch');
    onOpen?.();
  }

  build() {
    Column() {
      SettingsPageHeader({
        title: $r('app.string.settings_title'),
        showCloseButton: true,
        onAction: () => {
          this.onClose?.();
        }
      })

      List() {
        ListItemGroup({ header: this.functionSectionHeader() }) {
          ListItem() {
            SettingsEntryRow({
              title: $r('app.string.settings_entry_record'),
              icon: $r('sys.symbol.collection_panel')
            })
          }
          .onClick(() => {
            this.handleEntryClick(this.onOpenRecordSettings);
          })
          .borderRadius({
            topLeft: $r('app.float.settings_card_radius'),
            topRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsEntryRow({
              title: $r('app.string.settings_entry_calendar_sync'),
              icon: $r('sys.symbol.calendar_badge_clock')
            })
          }
          .onClick(() => {
            this.handleEntryClick(this.onOpenCalendarSyncSettings);
          })
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsEntryRow({
              title: $r('app.string.settings_entry_tag'),
              icon: $r('sys.symbol.square_and_pencil')
            })
          }
          .onClick(() => {
            this.handleEntryClick(this.onOpenTagSettings);
          })
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsEntryRow({
              title: $r('app.string.settings_entry_idea_pool'),
              icon: $r('sys.symbol.capture_smiles')
            })
          }
          .onClick(() => {
            this.handleEntryClick(this.onOpenIdeaPoolSettings);
          })
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsEntryRow({
              title: $r('app.string.settings_entry_reflect_chart'),
              icon: $r('sys.symbol.rectangle_split_2x1')
            })
          }
          .onClick(() => {
            this.handleEntryClick(this.onOpenReflectChartSettings);
          })
          .borderRadius({
            bottomLeft: $r('app.float.settings_card_radius'),
            bottomRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))
        }
        .borderRadius($r('app.float.settings_card_radius'))

        ListItemGroup({ header: this.personalizationSectionHeader() }) {
          ListItem() {
            SettingsEntryRow({
              title: $r('app.string.settings_entry_appearance'),
              icon: $r('sys.symbol.dark_mode')
            })
          }
          .onClick(() => {
            this.handleEntryClick(this.onOpenAppearanceSettings);
          })
          .borderRadius({
            topLeft: $r('app.float.settings_card_radius'),
            topRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsEntryRow({
              title: $r('app.string.settings_entry_quick_launch'),
              icon: $r('sys.symbol.paintpalette')
            })
          }
          .onClick(() => {
            this.handleEntryClick(this.onOpenQuickLaunchSettings);
          })
          .borderRadius({
            bottomLeft: $r('app.float.settings_card_radius'),
            bottomRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))
        }
        .borderRadius($r('app.float.settings_card_radius'))
        .margin({ top: $r('app.float.settings_section_spacing') })

        ListItemGroup({ header: this.dataAndSupportSectionHeader() }) {
          ListItem() {
            SettingsEntryRow({
              title: $r('app.string.settings_entry_backup'),
              icon: $r('sys.symbol.save')
            })
          }
          .onClick(() => {
            this.handleEntryClick(this.onOpenBackupSettings);
          })
          .borderRadius({
            topLeft: $r('app.float.settings_card_radius'),
            topRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsEntryRow({
              title: $r('app.string.settings_entry_about'),
              icon: $r('sys.symbol.lightbulb')
            })
          }
          .onClick(() => {
            this.handleEntryClick(this.onOpenAboutSettings);
          })
          .borderRadius({
            bottomLeft: $r('app.float.settings_card_radius'),
            bottomRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))
        }
        .borderRadius($r('app.float.settings_card_radius'))
        .margin({ top: $r('app.float.settings_section_spacing') })

        ListItem()
          .height($r('app.float.settings_list_bottom_spacer'))
      }
      .width('100%')
      .scrollBar(BarState.Off)
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

  @Builder
  private functionSectionHeader() {
    SettingsSectionHeader({ title: $r('app.string.settings_section_function') })
  }

  @Builder
  private personalizationSectionHeader() {
    SettingsSectionHeader({ title: $r('app.string.settings_section_personalization') })
  }

  @Builder
  private dataAndSupportSectionHeader() {
    SettingsSectionHeader({ title: $r('app.string.settings_section_data_support') })
  }

}
