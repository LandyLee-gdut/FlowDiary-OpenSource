import { SettingsActionRow } from './SettingsControlRows';
import { SettingsPageHeader } from './SettingsPageHeader';
import { REFLECT_CHART_SETTINGS_NAV_SYSTEM_TRANSITION } from '../ReflectChartSettingsMotionTokens';

@Component
export struct AboutSettingsPage {
  onBack?: () => void;
  onOpenUserGuide?: () => void;
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
          title: $r('app.string.settings_entry_about'),
          onAction: () => {
            this.handleBack();
          }
        })

        List({ space: 0 }) {
          ListItem() {
            SettingsActionRow({
              title: $r('app.string.settings_about_user_guide'),
              detail: $r('app.string.settings_about_user_guide_detail'),
              icon: $r('sys.symbol.lightbulb'),
              onAction: () => {
                this.onOpenUserGuide?.();
              }
            })
          }
          .borderRadius($r('app.float.settings_card_radius'))
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
