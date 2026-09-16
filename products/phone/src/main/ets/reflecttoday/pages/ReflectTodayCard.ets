import { LabelSummaryModel } from 'base';
import { ReflectTodayCirclePanel } from '../component/ReflectTodayCirclePanel';

const FULL_PERCENT: string = '100%';
const STORAGE_SEGMENTS_KEY: string = 'reflectTodayWidgetSegments';
const STORAGE_TOTAL_DURATION_KEY: string = 'reflectTodayWidgetTotalDuration';
const ROUTER_ABILITY_NAME: string = 'PhoneAbility';
const ROUTER_TARGET_REFLECT: string = 'reflect';

interface ReflectTodaySegmentPayload {
  label?: string;
  durationMs?: number;
  ratio?: number;
  colorHex?: string;
  color?: string;
}

interface ReflectTodaySegmentParseResult {
  items: LabelSummaryModel[];
  totalDurationMs: number;
}

const reflectTodayStorage: LocalStorage = new LocalStorage();

@Entry(reflectTodayStorage)
@Component
struct ReflectTodayCard {
  @LocalStorageProp(STORAGE_SEGMENTS_KEY) @Watch('handleSegmentsChange')
  private segmentsRaw: string = '';
  @LocalStorageProp(STORAGE_TOTAL_DURATION_KEY) @Watch('handleTotalDurationChange')
  private totalDurationRaw: string = '';

  @State private summaryData: LabelSummaryModel[] = [];
  @State private totalDurationMs: number = 0;
  @State private totalHoursLabel: string = '0.0';


  aboutToAppear(): void {
    this.applyTotalDuration(this.totalDurationRaw);
    this.applySegments(this.segmentsRaw);
  }

  private handleSegmentsChange(): void {
    this.applySegments(this.segmentsRaw);
  }

  private handleTotalDurationChange(): void {
    this.applyTotalDuration(this.totalDurationRaw);
    this.applySegments(this.segmentsRaw);
  }

  private applyTotalDuration(raw: string): void {
    const parsed = Number(raw);
    const safeDuration = Number.isNaN(parsed) || parsed < 0 ? 0 : parsed;
    this.totalDurationMs = safeDuration;
    this.totalHoursLabel = this.formatHoursLabel(safeDuration);
  }

  private applySegments(raw: string): void {
    const result = this.parseSegments(raw, this.totalDurationMs);
    this.summaryData = result.items;
    if (result.totalDurationMs !== this.totalDurationMs) {
      this.totalDurationMs = result.totalDurationMs;
      this.totalHoursLabel = this.formatHoursLabel(result.totalDurationMs);
    }
  }

  private parseSegments(raw: string, totalDurationMs: number): ReflectTodaySegmentParseResult {
    let parsed: ReflectTodaySegmentPayload[] = [];
    if (raw && raw.length > 0) {
      try {
        parsed = JSON.parse(raw) as ReflectTodaySegmentPayload[];
      } catch (error) {
        return this.buildFallbackResult(totalDurationMs);
      }
    }

    const items: LabelSummaryModel[] = [];
    let sumDurationMs = 0;
    parsed.forEach((payload: ReflectTodaySegmentPayload) => {
      const durationMs = this.resolveSegmentDuration(payload, totalDurationMs);
      if (durationMs <= 0) {
        return;
      }
      sumDurationMs += durationMs;
      items.push({
        labelName: this.resolveSegmentLabel(payload),
        totalMinutes: durationMs / 60000,
        labelColor: this.resolveSegmentColor(payload)
      });
    });

    let resolvedTotalMs = totalDurationMs > 0 ? totalDurationMs : sumDurationMs;
    if (resolvedTotalMs < sumDurationMs) {
      resolvedTotalMs = sumDurationMs;
    }
    const remainingMs = resolvedTotalMs - sumDurationMs;
    if (remainingMs > 0) {
      items.push({
        labelName: '',
        totalMinutes: remainingMs / 60000,
        labelColor: $r('app.color.neutral_200')
      });
    }

    return items.length > 0
      ? { items: items, totalDurationMs: resolvedTotalMs }
      : this.buildFallbackResult(resolvedTotalMs);
  }

  private buildFallbackResult(totalDurationMs: number): ReflectTodaySegmentParseResult {
    if (!Number.isFinite(totalDurationMs) || totalDurationMs <= 0) {
      return { items: [], totalDurationMs: 0 };
    }
    return {
      items: [{
        labelName: '',
        totalMinutes: totalDurationMs / 60000,
        labelColor: $r('app.color.neutral_200')
      }],
      totalDurationMs: totalDurationMs
    };
  }

  private resolveSegmentDuration(payload: ReflectTodaySegmentPayload, totalDurationMs: number): number {
    if (typeof payload.durationMs === 'number' && payload.durationMs > 0) {
      return payload.durationMs;
    }
    if (typeof payload.ratio === 'number' && totalDurationMs > 0) {
      return totalDurationMs * this.normalizeRatio(payload.ratio);
    }
    return 0;
  }

  private resolveSegmentLabel(payload: ReflectTodaySegmentPayload): string {
    if (payload.label && payload.label.trim().length > 0) {
      return payload.label.trim();
    }
    return '';
  }

  private resolveSegmentColor(payload: ReflectTodaySegmentPayload): ResourceColor {
    const colorHex = payload.colorHex ?? payload.color;
    if (colorHex && colorHex.length > 0) {
      return colorHex;
    }
    return $r('app.color.neutral_200');
  }

  private normalizeRatio(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.min(1, Math.max(0, value));
  }

  private formatHoursLabel(milliseconds: number): string {
    if (!Number.isFinite(milliseconds) || milliseconds <= 0) {
      return '0.0';
    }
    return (milliseconds / 3600000).toFixed(1);
  }

  private handleCardClick(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: ROUTER_ABILITY_NAME,
      params: {
        target: ROUTER_TARGET_REFLECT
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Text($r('app.string.reflect_today_widget_label'))
        .fontSize($r('app.float.reflect_today_widget_title_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .letterSpacing($r('app.float.reflect_today_widget_title_letter_spacing'))
        .position({ x: 8, y: 8 })
        .textAlign(TextAlign.Start);

      Stack({ alignContent: Alignment.Center }) {
        ReflectTodayCirclePanel({ summaryData: this.summaryData })
          .width('100%')
          .height('100%')
          .translate({ y: 5 })

        Column({ space: $r('app.float.reflect_today_widget_unit_margin_top') }) {
          Text(this.totalHoursLabel)
            .fontSize($r('app.float.reflect_today_widget_value_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .lineHeight($r('app.float.reflect_today_widget_value_font_size'))
            .fontFamily($r('app.string.today_widget_time_font_family_monospace'));

          Text($r('app.string.reflect_today_widget_unit_hour'))
            .fontSize($r('app.float.reflect_today_widget_unit_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_tertiary'));
        }
        .width($r('app.float.reflect_today_widget_hole_size'))
        .height($r('app.float.reflect_today_widget_hole_size'))
        .borderRadius($r('app.float.reflect_today_widget_hole_radius'))
        // .backgroundColor($r('app.color.bg_card'))
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .translate({ y: 5 })
      }
      .margin({ top: $r('app.float.reflect_today_widget_chart_margin_top') })
    }
    .width(FULL_PERCENT)
    .height(FULL_PERCENT)
    .padding($r('app.float.reflect_today_widget_padding'))
    .linearGradient({
      direction: GradientDirection.RightTop,
      colors: [
        [$r('app.color.accent_lighter'), 0],
        [$r('app.color.primary_lighter'), 1],
      ]
    })
    .backgroundColor($r('app.color.bg_card'))
    .onClick(() => {
      this.handleCardClick();
    });
  }
}
