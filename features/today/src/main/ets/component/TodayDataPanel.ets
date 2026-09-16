import { CircleDataPanel } from "./CircleDataPanel"
import { curves } from "@kit.ArkUI";
import { LineDataPanel } from "./LineDataPanel";
import { MatterItemModel, MatterItemModelInit } from 'base'
import {
  MatterStatus,
  LabelSummaryModel,
  AppShadows,
  buildPointLightEffect,
  BreakpointConstants,
  BreakpointType,
  AppGradients,
  ColorUtil,
  SessionSnapshot,
  COLOR_MODE_VERSION_KEY
} from 'base'
import { todayActivityService } from '../model/TodayActivityService'
import { hilog } from "@kit.PerformanceAnalysisKit";
import { VibratorUtil } from 'base';
import { hdsEffect } from '@kit.UIDesignKit';
import { uiEffect } from "@kit.ArkGraphics2D";
import { ecnyPaymentService, thirdPaymentService } from "@kit.PaymentKit";
import { ConfigurationConstant } from '@kit.AbilityKit';
import { Constants } from '../utils/Constants';

const TAG = 'TodayDataPanel';
const IDLE_TITLE: string = '无进行任务';
// 「正在记录」标题超过该字数时切换到紧凑字号，避免单行截断
const RUNNING_TITLE_COMPACT_THRESHOLD: number = 6;

@Preview
@Component
export struct TodayDataPanel {
  @StorageLink('doneMatterData') @Watch('onDoneMatterDataChange') doneMatterData: MatterItemModel[] = []; // 仅已完成/进行中的事项
  @StorageLink("showPanel") @Watch('onShowPanelChange') showPanel: boolean = true;
  @StorageProp('runningSessionView') @Watch('onRunningStateChange') runningSessionView: SessionSnapshot | null = null;
  @Watch('onHostVisibilityChanged') @Prop pageVisible: boolean = false;
  @Link @Watch('onDefaultLinePanelPreferenceChanged') defaultLinePanelEnabled: boolean;
  @State controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  @State flowColor: VisualEffect | undefined = undefined;
  @State private isFlowEffectMounted: boolean = true;
  @State private isComponentVisible: boolean = false;
  @State labelSummaries: LabelSummaryModel[] = [];
  @State totalDurationHoursText: string = '';
  @State totalDurationMinutesText: string = '0';
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State positionX: number = 0;
  @State positionY: number = 0;
  @State rotateAngle: number = 0;
  @State matterFontColor: ResourceColor = $r('app.color.text_secondary');
  @State heightSize: number = 250;
  // 从父组件（NodeBuilder）传入的深色模式状态，用于 BuilderNode 上下文中的主题响应
  @Watch('onThemeChange') @Prop isDarkThemeProp?: boolean;
  @StorageLink('isDarkTheme') @Watch('onThemeChange') isDarkTheme: boolean = false;
  // 版本号在系统资源真正切换之后才会递增，保证流光 shader 用新色板重建
  @StorageProp(COLOR_MODE_VERSION_KEY) @Watch('onColorModeVersionChange') private colorModeVersion: number = 0;
  @Prop @Watch('onBreakpointChange') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @State tabSelectedIndexes: number[] = [0]
  private isPageActive: boolean = false;
  private flowEffectRemountToken: number = 0;
  private flowEffectRemountTimer: number = -1;
  private effect: TransitionEffect = TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.6, 0.8) })
    .combine(TransitionEffect.scale({
      x: 0,
      y: 0
    })) // 添加旋转转场效果,这里的动画参数会跟随上面带animation的TransitionEffect,也就是springMotion(0.6, 0.8)
  private panOption: PanGestureOptions = new PanGestureOptions({ direction: PanDirection.Up | PanDirection.Down });

  private buildPanelVisualEffect(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT
      })
      .shaderEffect({
        effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
        animation: {
          duration: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 8000 : 20000,
          iterations: -1,
          autoPlay: true,
          onFinish: () => {
            console.info('Flow effect animation finished');
          }
        },
        controller: this.controller,
        params: {
          firstEdgeFlowLight: {
            startPos: 0,
            endPos: 1,
            color: $r('app.color.panel_blue'),

          },
          secondEdgeFlowLight: {
            startPos: 0,
            endPos: -1,
            color: $r('app.color.panel_accent')
          }
        }
      })
      .buildEffect();
  }

  private resetFlowEffect(): void {
    this.flowColor = new hdsEffect.HdsEffectBuilder()
      .pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT
      })
      .buildEffect();
  }

  private getCurrentRecordingItem(): MatterItemModel | undefined {
    if (!this.doneMatterData || this.doneMatterData.length === 0) {
      return undefined;
    }
    return this.doneMatterData.find(item => item.status === MatterStatus.RECORDING);
  }

  private shouldShowFlowEffect(): boolean {
    return this.runningSessionView !== null &&
      !!this.getCurrentRecordingItem() &&
      this.pageVisible &&
      this.isComponentVisible;
  }

  private updateVisualEffect(): void {
    if (!this.shouldShowFlowEffect()) {
      this.resetFlowEffect();
      this.controller = new hdsEffect.ShaderEffectController();
      return;
    }
    this.flowColor = this.buildPanelVisualEffect();
  }

  private onRunningStateChange(): void {
    this.updateVisualEffect();
  }

  private onHostVisibilityChanged(): void {
    this.updateVisualEffect();
  }

  /**
   * 摘下再挂回 shader，强制用最新色板/尺寸重建（对齐老版本的 remount 机制）
   */
  private recreateFlowEffect(): void {
    this.flowEffectRemountToken += 1;
    const remountToken = this.flowEffectRemountToken;
    this.controller = new hdsEffect.ShaderEffectController();
    this.updateVisualEffect();
    this.isFlowEffectMounted = false;
    setTimeout((): void => {
      if (!this.isPageActive || remountToken !== this.flowEffectRemountToken) {
        return;
      }
      this.isFlowEffectMounted = true;
    }, 0);
  }

  /**
   * 展开/收起后重建流光。remount 会整体重建子树、打断 500ms 高度动画，
   * 因此延迟到动画结束后再执行；快速连续切换时只保留最后一次。
   */
  private scheduleFlowEffectRemountAfterResize(): void {
    if (!this.shouldShowFlowEffect()) {
      return;
    }
    if (this.flowEffectRemountTimer >= 0) {
      clearTimeout(this.flowEffectRemountTimer);
    }
    this.flowEffectRemountTimer = setTimeout((): void => {
      this.flowEffectRemountTimer = -1;
      if (!this.isPageActive) {
        return;
      }
      this.recreateFlowEffect();
    }, 550);
  }

  private onDefaultLinePanelPreferenceChanged(): void {
    hilog.info(0x0000, TAG, `[TodayDataPanel] Default data panel preference changed -> useLinePanel=${this.defaultLinePanelEnabled}`);
    this.syncTabSelectionWithPreference(this.defaultLinePanelEnabled);
  }

  private onShowPanelChange(): void {
    this.applyThemeSurfaceStyles();
  }

  private onThemeChange(): void {
    this.applyThemeSurfaceStyles();
    this.recreateFlowEffect();
  }

  private onColorModeVersionChange(): void {
    this.onThemeChange();
  }

  private applyThemeSurfaceStyles(): void {
    this.matterFontColor = $r('app.color.text_secondary');
  }

  private syncTabSelectionWithPreference(useLinePanel: boolean): void {
    const targetIndex = useLinePanel ? 1 : 0;
    if (this.tabSelectedIndexes[0] === targetIndex) {
      return;
    }
    this.tabSelectedIndexes = [targetIndex];
  }

  private onBreakpointChange(): void {
    if (this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM) {
      // Force expanded on larger breakpoints.
      this.showPanel = true;
      this.rotateAngle = 0;
      this.heightSize = 250;
    }
  }

  private getHeaderValueFontSize(): Resource {
    return new BreakpointType<Resource>({
      sm: $r('app.float.data_panel_header_value_font_size'),
      md: $r('app.float.data_panel_header_value_font_size_md'),
      lg: $r('app.float.data_panel_header_value_font_size_lg')
    }).getValue(this.currentBreakpoint);
  }

  /**
   * 「正在记录」标题的动态字号：短标题用标准大字号，长标题切换为紧凑字号以显示更多内容。
   * 行高由左侧数值列（始终使用标准字号）撑开，因此切换字号不会改变标题行高度。
   */
  private getRunningTitleFontSize(): Resource {
    if (this.getRunningItemTitle().length <= RUNNING_TITLE_COMPACT_THRESHOLD) {
      return this.getHeaderValueFontSize();
    }
    return new BreakpointType<Resource>({
      sm: $r('app.float.data_panel_header_value_font_size_compact'),
      md: $r('app.float.data_panel_header_value_font_size_compact_md'),
      lg: $r('app.float.data_panel_header_value_font_size_compact_lg')
    }).getValue(this.currentBreakpoint);
  }

  private getDistributionDotSize(): Resource {
    return new BreakpointType<Resource>({
      sm: $r('app.float.data_panel_distribution_dot_size'),
      md: $r('app.float.data_panel_distribution_dot_size_md'),
      lg: $r('app.float.data_panel_distribution_dot_size_lg')
    }).getValue(this.currentBreakpoint);
  }

  private getDistributionNameFontSize(): Resource {
    return new BreakpointType<Resource>({
      sm: $r('app.float.data_panel_distribution_name_font_size'),
      md: $r('app.float.data_panel_distribution_name_font_size_md'),
      lg: $r('app.float.data_panel_distribution_name_font_size_lg')
    }).getValue(this.currentBreakpoint);
  }

  private getDistributionValueFontSize(): Resource {
    return new BreakpointType<Resource>({
      sm: $r('app.float.data_panel_distribution_value_font_size'),
      md: $r('app.float.data_panel_distribution_value_font_size_md'),
      lg: $r('app.float.data_panel_distribution_value_font_size_lg')
    }).getValue(this.currentBreakpoint);
  }

  private getDistributionUnitFontSize(): Resource {
    return new BreakpointType<Resource>({
      sm: $r('app.float.data_panel_distribution_unit_font_size'),
      md: $r('app.float.data_panel_distribution_unit_font_size_md'),
      lg: $r('app.float.data_panel_distribution_unit_font_size_lg')
    }).getValue(this.currentBreakpoint);
  }

  private getDistributionRowHeight(): Resource {
    return new BreakpointType<Resource>({
      sm: $r('app.float.data_panel_distribution_row_height'),
      md: $r('app.float.data_panel_distribution_row_height_md'),
      lg: $r('app.float.data_panel_distribution_row_height_lg')
    }).getValue(this.currentBreakpoint);
  }

  private getCircleChartSize(): Resource {
    return new BreakpointType<Resource>({
      sm: $r('app.float.data_panel_circle_size'),
      md: $r('app.float.data_panel_circle_size_md'),
      lg: $r('app.float.data_panel_circle_size_lg')
    }).getValue(this.currentBreakpoint);
  }

  private getWideCircleChartWidth(): string {
    return this.currentBreakpoint === BreakpointConstants.BREAKPOINT_MD ?
      Constants.DATA_PANEL_CIRCLE_WIDTH_MD : Constants.DATA_PANEL_CIRCLE_WIDTH_LG;
  }

  private getLineChartHeight(): Resource {
    return new BreakpointType<Resource>({
      sm: $r('app.float.data_panel_line_height'),
      md: $r('app.float.data_panel_line_height_md'),
      lg: $r('app.float.data_panel_line_height_lg')
    }).getValue(this.currentBreakpoint);
  }

  private getLineSectionHorizontalPadding(): Resource {
    return this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ?
      $r('app.float.data_panel_text_inset_horizontal') : $r('app.float.data_panel_spacing_none');
  }

  private getLineSectionVerticalPadding(): Resource {
    return this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ?
      $r('app.float.data_panel_line_padding_vertical') : $r('app.float.data_panel_spacing_none');
  }

  private getLineListHorizontalPadding(): Resource {
    return this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ?
      $r('app.float.data_panel_spacing_none') : $r('app.float.data_panel_text_inset_horizontal');
  }

  private getDistributionHours(totalMinutes: number): string {
    const hours = Math.floor(totalMinutes / 60);
    return hours > 0 ? `${hours}` : '';
  }

  private getDistributionMinutes(totalMinutes: number): string {
    return `${Math.max(totalMinutes, 0) % 60}`;
  }

  private getDistributionPercentage(totalMinutes: number): string {
    const allMinutes = this.labelSummaries.reduce((sum: number, item: LabelSummaryModel) =>
      sum + item.totalMinutes, 0);
    if (allMinutes <= 0) {
      return '0';
    }
    return `${Math.round(totalMinutes * 100 / allMinutes)}`;
  }

  private getExpandedHeight(): string | number {
    return this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? this.heightSize : this.currentBreakpoint == BreakpointConstants.BREAKPOINT_MD ? '90%' : '95%';
  }

  private getPanelHeight(): string | number {
    return this.showPanel ? this.getExpandedHeight() : this.heightSize;
  }

  private isSessionRunning(): boolean {
    return this.runningSessionView !== null;
  }

  private getRunningItemTitle(): string {
    if (this.runningSessionView !== null && this.runningSessionView.title !== '') {
      return this.runningSessionView.title;
    }
    return IDLE_TITLE;
  }

  async onRunningItemChange(): Promise<void> {
    hilog.info(0x0000, TAG, 'doneMatterData changed via @Watch, checking if update is needed...');
    // 查找当前正在运行的项目
    const recordingItem = this.doneMatterData.find(item => item.status === MatterStatus.RECORDING);

    hilog.info(0x0000, TAG, 'recording item is:' + JSON.stringify(recordingItem?.title));

    // 如果有正在运行的项目且该项目没有持续时间，则不刷新数据面板
    // 这表明项目刚从TODO状态变为RECORDING状态，但还没有实际的时间记录
    if (recordingItem && recordingItem.durationInMilliseconds == 0 && this.isSessionRunning()) {
      hilog.info(0x0000, TAG, 'Skipping data panel update - item just started recording with no duration yet');
      return;
    }
    // 其他情况（有暂停状态的项目、有持续时间、或不在运行状态）则刷新数据面板
    if (!this.isSessionRunning()) {
      await this.processMatterData();
    } else {
      hilog.info(0x0000, TAG, 'Skipping data panel update - no meaningful data changes');
    }
  }

  async onDoneMatterDataChange(): Promise<void> {
    hilog.info(0x0000, TAG, 'doneMatterData changed via @Watch, updating data panel...');
    await this.processMatterData();
  }

  /**
   * 核心数据处理方法 - 计算已完成任务的总时长并聚合数据
   */
  private async processMatterData() {
    try {
      if (!this.doneMatterData || this.doneMatterData.length <= 0) {
        this.totalDurationHoursText = '';
        this.totalDurationMinutesText = '0';
        this.labelSummaries = [];
        hilog.warn(0x0000, TAG, 'no available data in todayDataPanel');
        return;
      }

      // --- 步骤 1: 计算总时长和找到正在记录的任务 ---
      let totalMilliseconds = 0;

      // 批量获取所有任务的今日总时长（仅已完成任务的时长）
      const durationPromises = this.doneMatterData.map(async (item): Promise<itemDuration> => {
        try {
          // 使用 getTodayTotalDuration 方法获取已完成任务的时长
          const duration = await todayActivityService.getTodayTotalDuration(item.id);

          return { id: item.id, duration };
        } catch (error) {
          console.error(TAG, `Error getting duration for item ${item.id}:`, error);
          return { id: item.id, duration: 0 };
        }
      });

      // 等待所有时长查询完成
      const durationResults = await Promise.all(durationPromises);

      // 计算总时长
      durationResults.forEach(result => {
        totalMilliseconds += result.duration;
      });

      // 将毫秒转换为分钟进行显示（小时/分钟拆分，供 header 分样式渲染）
      const totalMinutes = Math.round(totalMilliseconds / 60000);
      const totalHours = Math.floor(totalMinutes / 60);
      this.totalDurationHoursText = totalHours > 0 ? `${totalHours}` : '';
      this.totalDurationMinutesText = `${totalMinutes % 60}`;

      // --- 步骤 2: 使用 Map 按标签聚合时长和颜色 ---
      const summaryMap = new Map<string, millisecondsLabel>();

      // 使用之前获取的时长结果，避免重复查询
      this.doneMatterData.forEach(item => {
        const durationResult = durationResults.find(r => r.id === item.id);
        const duration = durationResult ? durationResult.duration : 0;

        if (duration > 0) {
          const summary = summaryMap.get(item.label);
          if (summary) {
            // 如果该标签已存在，只累加时长
            summary.totalMilliseconds += duration;
          } else {
            // 如果该标签首次出现，则记录其时长和颜色
            summaryMap.set(item.label, {
              totalMilliseconds: duration,
              color: this.resolveDataPanelColor(item.labelColor) // 以第一次遇到的 item 的颜色为准
            });
          }
        }
      });

      // --- 步骤 3: 转换 Map 为数组并排序 ---
      const summaries: LabelSummaryModel[] = Array.from(summaryMap.entries())
        .map((entry: [string, millisecondsLabel]) => {
          const labelName = entry[0];
          const summaryData = entry[1];

          // 创建一个符合 LabelSummaryModel 接口的对象
          const summaryItem: LabelSummaryModel = {
            labelName: labelName,
            totalMinutes: Math.round(summaryData.totalMilliseconds / 60000), // 将毫秒转换为分钟
            labelColor: summaryData.color // 使用聚合时记录的权威颜色
          };
          return summaryItem;
        })
        .sort((a, b) => b.totalMinutes - a.totalMinutes);

      this.labelSummaries = summaries;
      // 数据刷新后重新检查流光：开始记录时 runningSessionView 可能先于
      // doneMatterData 里的 RECORDING 状态到达，需要这里再触发一次
      this.updateVisualEffect();
    } catch (error) {
      console.error(TAG, 'Error in processMatterData:', error);
      // 在出错时提供合理的默认值
      this.totalDurationHoursText = '';
      this.totalDurationMinutesText = '0';
      this.labelSummaries = [];
      this.updateVisualEffect();
    }
  }

  private resolveDataPanelColor(color: ResourceColor): ResourceColor {
    if (typeof color !== 'string') {
      return color;
    }
    if (color.trim().length === 0) {
      return AppGradients.DATA_PANEL_COLORS[0] ?? color;
    }
    return ColorUtil.normalizeHexColor(color);
  }

  private expandOrClose() {
    if (this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM) {
      // Non-sm breakpoints stay expanded; keep visual state consistent.
      this.showPanel = true;
      this.rotateAngle = 0;
      this.heightSize = 250;
      return;
    }
    const willCollapse = this.showPanel;
    this.rotateAngle = willCollapse ? 180 : 0;
    this.heightSize = willCollapse ? 70 : 250;

    this.showPanel = !willCollapse;
    this.applyThemeSurfaceStyles();
    // 面板高度变化后重建流光，让 shader 以新尺寸重渲染；延迟执行避免拆树打断高度动画
    this.scheduleFlowEffectRemountAfterResize();
    VibratorUtil.getInstance().triggerHaptic('haptic.effect.sharp', 'touch')
  }

  async aboutToAppear(): Promise<void> {
    this.isPageActive = true;
    this.onThemeChange();
    if (AppStorage.get('doneMatterData')) {
      const stored = AppStorage.get('doneMatterData') as (MatterItemModel | MatterItemModelInit)[] | undefined;
      if (stored) {
        this.doneMatterData = MatterItemModel.ensureList(stored);
      }
      hilog.info(0x0000, TAG,
        'successfully load doneMatterItem in todayDataPanel' + `len${this.doneMatterData.length}}`);
    } else {
      hilog.error(0x0000, TAG, 'Failed to load doneMatterItem in todayDataPanel');
    }
    await this.processMatterData();

    this.syncTabSelectionWithPreference(this.defaultLinePanelEnabled);
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    if (this.flowEffectRemountTimer >= 0) {
      clearTimeout(this.flowEffectRemountTimer);
      this.flowEffectRemountTimer = -1;
    }
    this.resetFlowEffect();
    this.controller = new hdsEffect.ShaderEffectController();
  }

  @Builder
  private renderPanelContent() {
    this.renderHeaderRow();

    if (this.showPanel) {
      Column() {
        this.renderDistributionSection();
      }
      .layoutWeight(1)
      .width('100%')
    }
  }

  @Builder
  private renderHeaderRow() {
    Column() {
      // 标签行：「累积记录时长」「正在记录」与折叠箭头统一置顶对齐
      Row() {
        Text('累积记录时长')
          .fontSize(new BreakpointType<number>({sm: 12, md: 15, lg: 15}).getValue(this.currentBreakpoint))
          .fontWeight(500)
          .fontColor($r('app.color.text_secondary'))
          .flexShrink(0) // 禁止左侧被压缩
          .margin({ right: 10 }) // 最小间距，防止左右贴在一起

        Row() {
          Text('正在记录')
            .fontSize(new BreakpointType<number>({sm: 12, md: 15, lg: 15}).getValue(this.currentBreakpoint))
            .fontWeight(500)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 5 })

          Column() {
            Column() {
              SymbolGlyph($r('sys.symbol.chevron_up'))
                .fontSize(14)
                .borderRadius('50%')
                .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
                .fontWeight(500)
                .fontColor([this.getChevronIconColor()])
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.5 })
            }
            .rotate({ angle: this.rotateAngle })
            .animation({
              duration: 100,
              curve: curves.springMotion(),
              playMode: PlayMode.Normal
            })
            .justifyContent(FlexAlign.Start)
            .borderRadius('50%')
            .onClick(() => {
              this.expandOrClose()
            })
            .visibility(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? Visibility.Visible : Visibility.None)
          }
        }
        .layoutWeight(1) // 占据标签行剩余空间
        .alignItems(VerticalAlign.Top)
        .justifyContent(FlexAlign.End) // 内部内容靠右对齐
        .onClick(() => {
          this.expandOrClose()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 5 })

      // 数值行：左右内容底部对齐，标题字号缩小时底边仍与左侧数值齐平
      Row() {
        Text() {
          if (this.totalDurationHoursText.length > 0) {
            Span(this.totalDurationHoursText)
            Span('h')
              .fontSize($r('app.float.data_panel_header_unit_font_size'))
              .fontWeight(500)
              .fontColor($r('app.color.primary_light'))
          }
          Span(this.totalDurationMinutesText)
          Span('m')
            .fontSize($r('app.float.data_panel_header_unit_font_size'))
            .fontWeight(500)
            .fontColor($r('app.color.primary_light'))
        }
          .fontWeight(700)
          .fontSize(this.getHeaderValueFontSize())
          .fontColor($r('app.color.primary'))
          .animation({ curve: curves.springMotion(), duration: 100 })
          .flexShrink(0) // 禁止左侧被压缩，保证重要数据完整显示
          .margin({ right: 10 })

        Text(this.getRunningItemTitle())
          .fontWeight(600)
          .fontColor(this.matterFontColor)
          .fontSize(this.getRunningTitleFontSize())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }) // 必须保留，配合 layoutWeight 生效
          .textAlign(TextAlign.End) // 确保文字内容靠右对齐
          .layoutWeight(1) // 占据数值行剩余空间
          .onClick(() => {
            this.expandOrClose()
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .margin({
      top: $r('app.float.data_panel_header_margin_top'),
      bottom: new BreakpointType<number>({ sm: 0, md: 5, lg: 5}).getValue(this.currentBreakpoint)
    })
    .padding({
      left: $r('app.float.data_panel_text_inset_horizontal'),
      right: $r('app.float.data_panel_text_inset_horizontal')
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderDistributionSection() {
    Column() {
      Row() {
        Text('时间分布')
          .fontSize(new BreakpointType<number>({sm: 12, md: 15, lg: 15}).getValue(this.currentBreakpoint))
          .fontWeight(500)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height(24)
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ top: 0, bottom: this.tabSelectedIndexes[0] == 1 ? 8 : 4 })
      .padding({
        left: $r('app.float.data_panel_text_inset_horizontal'),
        right: $r('app.float.data_panel_text_inset_horizontal')
      })
      .flexShrink(0)

      if (this.tabSelectedIndexes[0] == 0) {
        if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM) {
          GridRow({
            columns: BreakpointConstants.COLUMN_SM,
            gutter: { x: $r('app.float.data_panel_distribution_column_gap') }
          }) {
            GridCol({ span: BreakpointConstants.COLUMN_SM / 2 }) {
              Column() {
                CircleDataPanel({ summaryData: this.labelSummaries })
                  .width(this.getCircleChartSize())
                  .height(this.getCircleChartSize())
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }

            GridCol({ span: BreakpointConstants.COLUMN_SM / 2 }) {
              Scroll() {
                Column() {
                  ForEach(this.labelSummaries, (item: LabelSummaryModel) => {
                    this.renderDistributionRow(item);
                  }, (item: LabelSummaryModel) => item.labelName)
                }
                .width('100%')
              }
              .scrollBar(BarState.Off)
              .height('100%')
              .align(Alignment.TopStart)
              .edgeEffect(EdgeEffect.Spring)
              .width('100%')
              .nestedScroll({
                scrollForward: NestedScrollMode.PARENT_FIRST,
                scrollBackward: NestedScrollMode.PARENT_FIRST
              })
            }
          }
          .width('100%')
          .padding({
            left: $r('app.float.data_panel_text_inset_horizontal'),
            right: $r('app.float.data_panel_text_inset_horizontal')
          })
          .alignItems(ItemAlign.Start)
          .layoutWeight(1)
        } else {
          Column() {
            Column() {
              CircleDataPanel({ summaryData: this.labelSummaries })
                .width(this.getWideCircleChartWidth())
                .aspectRatio(1)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            Scroll() {
              Column() {
                ForEach(this.labelSummaries, (item: LabelSummaryModel) => {
                  this.renderDistributionRow(item);
                }, (item: LabelSummaryModel) => item.labelName)
              }
              .width('100%')
              .padding({ bottom: $r('app.float.data_panel_distribution_list_padding_bottom') })
            }
            .scrollBar(BarState.Off)
            .layoutWeight(1)
            .align(Alignment.TopStart)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
            .nestedScroll({
              scrollForward: NestedScrollMode.PARENT_FIRST,
              scrollBackward: NestedScrollMode.PARENT_FIRST
            })
            .padding({
              left: $r('app.float.data_panel_text_inset_horizontal'),
              right: $r('app.float.data_panel_text_inset_horizontal')
            })
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
      } else {
        Column() {
          if (this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM) {
            LineDataPanel({ summaryData: this.labelSummaries })
              .width('100%')
              .height(this.getLineChartHeight())
              .margin({ bottom: $r('app.float.data_panel_line_margin_bottom') })
          } else {
            Column() {
              LineDataPanel({ summaryData: this.labelSummaries })
                .width('100%')
                .height(this.getLineChartHeight())
            }
            .width(this.getWideCircleChartWidth())
            .aspectRatio(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .alignSelf(ItemAlign.Center)
          }

          Scroll() {
            GridRow({
              breakpoints: { value: BreakpointConstants.BREAKPOINT_VALUE, reference: BreakpointsReference.WindowSize },
              columns: {
                sm: BreakpointConstants.COLUMN_LG,
                md: BreakpointConstants.COLUMN_LG,
                lg: BreakpointConstants.COLUMN_LG
              },
              gutter: {
                y: $r('app.float.data_panel_distribution_grid_gap'),
                x: $r('app.float.data_panel_distribution_column_gap')
              }
            }) {
              ForEach(this.labelSummaries, (item: LabelSummaryModel) => {
                GridCol({
                  span: {
                    sm: BreakpointConstants.COLUMN_LG / 2,
                    md: BreakpointConstants.COLUMN_LG / 2,
                    lg: BreakpointConstants.COLUMN_LG / 2
                  }
                }) {
                  this.renderDistributionRow(item);
                }
              }, (item: LabelSummaryModel) => item.labelName)
            }
            .width('100%')
            .padding({ bottom: $r('app.float.data_panel_distribution_list_padding_bottom') })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .align(Alignment.TopStart)
          .nestedScroll({
            scrollForward: NestedScrollMode.PARENT_FIRST,
            scrollBackward: NestedScrollMode.PARENT_FIRST
          })
          .padding({
            left: this.getLineListHorizontalPadding(),
            right: this.getLineListHorizontalPadding()
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          top: this.getLineSectionVerticalPadding(),
          bottom: this.getLineSectionVerticalPadding(),
          left: this.getLineSectionHorizontalPadding(),
          right: this.getLineSectionHorizontalPadding()
        })
        .alignItems(HorizontalAlign.Start)
        // .transition(this.effect)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .height('100%')
    // .transition(this.effect)
  }

  @Builder
  private renderDistributionRow(item: LabelSummaryModel) {
    Row() {
      Row() {
        Row()
          .width(this.getDistributionDotSize())
          .height(this.getDistributionDotSize())
          .borderRadius($r('app.float.data_panel_distribution_dot_radius'))
          .backgroundColor(item.labelColor)
          .margin({ right: $r('app.float.data_panel_distribution_dot_margin_right') })

        Text(item.labelName)
          .fontSize(this.getDistributionNameFontSize())
          .fontWeight(500)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      Row() {
        Text() {
          if (this.getDistributionHours(item.totalMinutes).length > 0) {
            Span(this.getDistributionHours(item.totalMinutes))
            Span($r('app.string.data_panel_duration_hour_unit'))
              .fontSize(this.getDistributionUnitFontSize())
              .fontWeight(500)
              .fontColor($r('app.color.text_secondary'))
          }
          Span(this.getDistributionMinutes(item.totalMinutes))
          Span($r('app.string.data_panel_duration_minute_unit'))
            .fontSize(this.getDistributionUnitFontSize())
            .fontWeight(500)
            .fontColor($r('app.color.text_secondary'))
        }
        .fontSize(this.getDistributionValueFontSize())
        .fontWeight(700)
        .fontColor($r('app.color.text_primary'))

        Text($r('app.string.data_panel_distribution_separator'))
          .fontSize(this.getDistributionUnitFontSize())
          .fontWeight(500)
          .fontColor($r('app.color.text_secondary'))

        Text() {
          Span(this.getDistributionPercentage(item.totalMinutes))
          Span($r('app.string.data_panel_percentage_unit'))
        }
        .fontSize(this.getDistributionValueFontSize())
        .fontWeight(700)
        .fontColor($r('app.color.text_primary'))
      }
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .flexShrink(0)
    }
    .width('100%')
    .height(this.getDistributionRowHeight())
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    // .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(), duration: 50 }))
  }

  build() {
    if (canIUse("SystemCapability.UIDesign.HDSComponent.Core")) {
      if (this.isFlowEffectMounted) {
        Column() {
          this.renderPanelContent();
        }
        .gesture(
          PanGesture(this.panOption)
            .onActionUpdate((event: GestureEvent) => {
              if (event) {
                this.offsetX = this.positionX + event.offsetX;
                this.offsetY = this.positionY + event.offsetY;
              }
            })
            .onActionEnd((event: GestureEvent) => {
              this.positionX = this.offsetX;
              this.positionY = this.offsetY;
              if (event.offsetY >= 30 || event.offsetY <= -30) {
                this.expandOrClose();

              }
            })
        )
        .alignItems(HorizontalAlign.Start)
        .backgroundColor($r('app.color.panel_bg'))
        .shadow(this.getPanelShadow())
        .borderRadius(15)
        .padding({
          top: new BreakpointType<number>({sm: 12, md: 15, lg: 20}).getValue(this.currentBreakpoint),
          left: new BreakpointType<number>({sm: 8, md: 12, lg: 15}).getValue(this.currentBreakpoint),
          right: new BreakpointType<number>({sm: 8, md: 12, lg: 15}).getValue(this.currentBreakpoint),
          // 顶部另有 header 的 margin-top(4vp)，底部加大同等补偿使视觉上下留白一致
          bottom: new BreakpointType<number>({sm: 16, md: 19, lg: 24}).getValue(this.currentBreakpoint)
        })
        .width('100%')
        .height(this.getPanelHeight())
        .animation({ curve: curves.springMotion(), duration: 500 })
        .visualEffect(this.flowColor)
        .onVisibleAreaChange([0, 1], (_isExpanding: boolean, currentRatio: number) => {
          const nextVisible = currentRatio > 0;
          if (this.isComponentVisible === nextVisible) {
            return;
          }
          this.isComponentVisible = nextVisible;
          this.updateVisualEffect();
        })
      } else {
        Column() {
          this.renderPanelContent();
        }
        .gesture(
          PanGesture(this.panOption)
            .onActionUpdate((event: GestureEvent) => {
              if (event) {
                this.offsetX = this.positionX + event.offsetX;
                this.offsetY = this.positionY + event.offsetY;
              }
            })
            .onActionEnd((event: GestureEvent) => {
              this.positionX = this.offsetX;
              this.positionY = this.offsetY;
              if (event.offsetY >= 30 || event.offsetY <= -30) {
                this.expandOrClose();

              }
            })
        )
        .alignItems(HorizontalAlign.Start)
        .backgroundColor($r('app.color.panel_bg'))
        .shadow(this.getPanelShadow())
        .borderRadius(15)
        .padding({
          top: new BreakpointType<number>({sm: 12, md: 15, lg: 20}).getValue(this.currentBreakpoint),
          left: new BreakpointType<number>({sm: 8, md: 12, lg: 15}).getValue(this.currentBreakpoint),
          right: new BreakpointType<number>({sm: 8, md: 12, lg: 15}).getValue(this.currentBreakpoint),
          // 顶部另有 header 的 margin-top(4vp)，底部加大同等补偿使视觉上下留白一致
          bottom: new BreakpointType<number>({sm: 16, md: 19, lg: 24}).getValue(this.currentBreakpoint)
        })
        .width('100%')
        .height(this.getPanelHeight())
        .animation({ curve: curves.springMotion(), duration: 500 })
        .onVisibleAreaChange([0, 1], (_isExpanding: boolean, currentRatio: number) => {
          const nextVisible = currentRatio > 0;
          if (this.isComponentVisible === nextVisible) {
            return;
          }
          this.isComponentVisible = nextVisible;
          this.updateVisualEffect();
        })
      }
    } else {
      Column() {
        this.renderPanelContent();
      }
      .gesture(
        PanGesture(this.panOption)
          .onActionUpdate((event: GestureEvent) => {
            if (event) {
              this.offsetX = this.positionX + event.offsetX;
              this.offsetY = this.positionY + event.offsetY;
            }
          })
          .onActionEnd((event: GestureEvent) => {
            this.positionX = this.offsetX;
            this.positionY = this.offsetY;
            if (event.offsetY >= 30 || event.offsetY <= -30) {
              this.expandOrClose();

            }
          })
      )
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.panel_bg'))
      .shadow(this.getPanelShadow())
      .borderRadius(15)
      .padding({
        top: 12,
        left: 12,
        right: 12,
        bottom: 16
      })
      .width('100%')
      .height(this.getPanelHeight())
      .onVisibleAreaChange([0, 1], (_isExpanding: boolean, currentRatio: number) => {
        const nextVisible = currentRatio > 0;
        if (this.isComponentVisible === nextVisible) {
          return;
        }
        this.isComponentVisible = nextVisible;
        this.updateVisualEffect();
      })
    }
  }
  private getChevronIconColor(): ResourceColor {
    return this.isDarkTheme ? $r('app.color.text_secondary') : $r('app.color.neutral_500');
  }

  private getPanelShadow(): ShadowOptions {
    if (this.isDarkTheme) {
      return AppShadows.CARD_INTERACTIVE_DARK;
    }
    return { radius: 35, color: '#59aeadad', type: ShadowType.COLOR };
  }
}

interface millisecondsLabel {
  totalMilliseconds: number;
  color: ResourceColor
}

interface itemDuration {
  id: string,
  duration: number
}
