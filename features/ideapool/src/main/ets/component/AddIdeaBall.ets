import { buildFlowLightEffect, buildPointLightEffect, COLOR_MODE_VERSION_KEY, FlowLightColors } from 'base';
import { hdsEffect } from "@kit.UIDesignKit";

@Preview
@Component
export struct AddIdeaBall {
  private static readonly TOUCH_LIGHT_HEIGHT = 100;
  private static readonly TOUCH_LIGHT_INTENSITY_LIGHT = 0.8;
  private static readonly TOUCH_LIGHT_INTENSITY_DARK = 0.45;
  private static readonly TOUCH_LIGHT_BLOOM = 0.15;
  private static readonly GLASS_BLUR_RADIUS = 12;
  private static readonly FLOW_LAYER_OPACITY = 0.6;
  private static readonly FLOW_LIGHT_COLORS: FlowLightColors = {
    colorSource: [
      $r('app.color.warning'),
      $r('app.color.add_idea_ball_flow_gold_light'),
      $r('app.color.add_idea_ball_flow_gold_pale'),
      $r('app.color.warning_light')
    ],
    colorTarget: [
      $r('app.color.warning_light'),
      $r('app.color.add_idea_ball_flow_gold_pale'),
      $r('app.color.add_idea_ball_flow_gold_light'),
      $r('app.color.warning')
    ]
  };
  @StorageLink('isDarkTheme') @Watch('onThemeChanged') isDarkTheme: boolean = false;
  // 版本号在系统资源真正切换之后才会递增，是重建流光 shader 的可靠触发源
  @StorageProp(COLOR_MODE_VERSION_KEY) @Watch('onColorModeVersionChange') private colorModeVersion: number = 0;
  @State isPressed: boolean = false;
  @State private shaderController: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  @State private isFlowEffectMounted: boolean = true;
  private flowEffectRemountToken: number = 0;
  private isComponentActive: boolean = false;

  aboutToAppear(): void {
    this.isComponentActive = true;
    this.recreateFlowEffect();
  }

  aboutToDisappear(): void {
    this.isComponentActive = false;
    this.flowEffectRemountToken += 1;
  }

  private onThemeChanged(): void {
    this.recreateFlowEffect();
  }

  private onColorModeVersionChange(): void {
    this.recreateFlowEffect();
  }

  private recreateFlowEffect(): void {
    this.flowEffectRemountToken += 1;
    const remountToken: number = this.flowEffectRemountToken;
    this.shaderController = new hdsEffect.ShaderEffectController();
    this.isFlowEffectMounted = false;
    setTimeout((): void => {
      if (this.isComponentActive && remountToken === this.flowEffectRemountToken) {
        this.isFlowEffectMounted = true;
      }
    }, 0);
  }

  private buildFlowLightBackground(): VisualEffect {
    return buildFlowLightEffect(this.shaderController, AddIdeaBall.FLOW_LIGHT_COLORS);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 流光层：半透明，透出 Stack 自身模糊+罩色后的背景
      if (this.isFlowEffectMounted) {
        Column()
          .width('100%')
          .height('100%')
          .visualEffect(this.buildFlowLightBackground())
          .opacity(AddIdeaBall.FLOW_LAYER_OPACITY)
      }

      SymbolGlyph($r('sys.symbol.lightbulb'))
        .fontSize(35)
        .fontWeight(600)
        .fontColor([$r('app.color.text_on_primary')])
    }
    .visualEffect(buildPointLightEffect({
      preset: 'fabTouch',
      color: $r('app.color.immersive_glow_warning'),
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      isActive: this.isPressed,
      isDarkTheme: this.isDarkTheme,
      overrides: {
        height: AddIdeaBall.TOUCH_LIGHT_HEIGHT,
        intensity: this.isDarkTheme
          ? AddIdeaBall.TOUCH_LIGHT_INTENSITY_DARK
          : AddIdeaBall.TOUCH_LIGHT_INTENSITY_LIGHT,
        bloom: AddIdeaBall.TOUCH_LIGHT_BLOOM
      }
    }))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isPressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false;
      }
    })
    .shadow({
      radius: $r('app.float.add_idea_ball_shadow_radius'),
      offsetY: $r('app.float.add_idea_ball_shadow_offset_y'),
      color: $r('app.color.ideapool_add_ball_shadow')
    })
    .clickEffect({level: ClickEffectLevel.MIDDLE, scale: 0.7})
    .borderRadius('50%')
    .clip(true)
    .backdropBlur(AddIdeaBall.GLASS_BLUR_RADIUS)
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [
        [$r('app.color.add_idea_ball_glass_top'), 0],
        [$r('app.color.add_idea_ball_glass_bottom'), 1]
      ]
    })
    .width('100%')
    .height('100%')

  }
}
