import { SettingsToggleRow } from './SettingsControlRows';
import { SettingsPageHeader } from './SettingsPageHeader';
import { REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION } from '../ReflectChartSettingsMotionTokens';

@Component
export struct IdeaPoolSettingsPage {
  @Prop ideapoolUnlitFirst: boolean = true;
  @Prop ideapoolDirectRecordEnabled: boolean = false;
  onBack?: () => void;
  onIdeaPoolOrderToggle?: (isOn: boolean) => void;
  onIdeaPoolDirectRecordToggle?: (isOn: boolean) => void;
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
          title: $r('app.string.settings_entry_idea_pool'),
          onAction: () => {
            this.handleBack();
          }
        })

        List({ space: 0 }) {
          ListItem() {
            SettingsToggleRow({
              title: $r('app.string.ideapool_unlit_first'),
              detail: $r('app.string.ideapool_unlit_first_detail'),
              icon: $r('sys.symbol.list_bullet'),
              checked: this.ideapoolUnlitFirst,
              onChange: (isOn: boolean) => {
                this.onIdeaPoolOrderToggle?.(isOn);
              }
            })
          }
          .borderRadius({
            topLeft: $r('app.float.settings_card_radius'),
            topRight: $r('app.float.settings_card_radius')
          })
          .backgroundColor($r('app.color.bg_card'))

          ListItem() {
            SettingsToggleRow({
              title: $r('app.string.ideapool_direct_record'),
              detail: $r('app.string.ideapool_direct_record_detail'),
              icon: $r('sys.symbol.capture_smiles'),
              checked: this.ideapoolDirectRecordEnabled,
              onChange: (isOn: boolean) => {
                this.onIdeaPoolDirectRecordToggle?.(isOn);
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
