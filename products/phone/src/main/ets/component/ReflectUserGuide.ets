import { curves } from '@kit.ArkUI';
import { HmCalendarSelectedDay } from 'reflect/src/main/ets/model/CalendarModel';
import { BreakpointConstants } from 'base';
import {
  createReflectGuideSelectedDays,
  createReflectGuideStreamItems,
  createReflectGuideTimelineSegments,
  createReflectGuideTrendData,
  ReflectStreamTimelineItem,
  ReflectTimelineSegment,
  ReflectTrendData
} from '../model/ReflectUserGuideMockData';
import { ReflectDemoStack } from './ReflectDemoStack';

@Component
export struct ReflectUserGuide {
  onContinue?: () => void;
  @Prop isActive: boolean = false;
  @State calendarHighlights: HmCalendarSelectedDay[] = [];
  @State timelineSegments: ReflectTimelineSegment[] = [];
  @State streamItems: ReflectStreamTimelineItem[] = [];
  private readonly trendData: ReflectTrendData = createReflectGuideTrendData();
  private readonly sectionSpacing: number = 16;
  private readonly headingSpacing: number = 8;
  private readonly demoStackWidth: string = '90%';
  private readonly demoStackMarginBottom: number = 30;
  private readonly ctaSectionSpacing: number = 8;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  aboutToAppear(): void {
    this.calendarHighlights = createReflectGuideSelectedDays();
    this.timelineSegments = createReflectGuideTimelineSegments();
    this.streamItems = createReflectGuideStreamItems();
  }

  build() {
    Column({ space: this.sectionSpacing }) {
      Column({ space: this.headingSpacing }) {
        Text('「回顾」页面')
          .fontSize(30)
          .fontColor($r('app.color.primary'))
          .fontWeight(600)
          .transition(TransitionEffect.translate({ y: 260 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1400 }))
        Text('月度 · 时间轴 · 标签，多维视图，温和回顾')
          .fontColor($r('app.color.text_tertiary'))
          .fontSize(14)
          .transition(TransitionEffect.translate({ y: 320 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.7, 0.8), duration: 1400 }))
      }
      .height(50)
      .offset({ y: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 20 })
      .alignItems(HorizontalAlign.Center)

      Column() {
        ReflectDemoStack({
          isActive: this.isActive,
          calendarHighlights: this.calendarHighlights,
          timelineSegments: this.timelineSegments,
          streamItems: this.streamItems,
          trendData: this.trendData,
          dateLabel: `${new Date().getFullYear().toString()}-${new Date().getMonth()+1}-${new Date().getDate().toString()}`
        });
      }
      .width(this.demoStackWidth)
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: this.demoStackMarginBottom })

      Column({ space: 8 }) {
        Text('月度、时间轴支持长按，展示更多细节！')
          .transition(TransitionEffect.translate({ y: 240 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1200, delay: 400 }))
          .fontSize(16)
          .fontColor($r('app.color.text_tertiary'))
          .fontWeight(600)
        Text('现在就长按"时间轴"试试吧！')
          .transition(TransitionEffect.translate({ y: 240 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1200, delay: 400 }))
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .fontWeight(500)
      }
      .justifyContent(FlexAlign.End)
      .height(this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 65 : 55)
      .alignItems(HorizontalAlign.Center)
      .margin({
        bottom: this.currentBreakpoint == BreakpointConstants.BREAKPOINT_SM ? 0 : 20,
      })

      Button('继续')
        .transition(TransitionEffect.translate({ y: 500 }).combine(TransitionEffect.OPACITY).animation({ curve: curves.springMotion(0.8, 0.8), duration: 1500, delay: 700 }))
        .width('60%')
        .backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.neutral_100'))
        .padding({ top: 8, right: 24, bottom: 8, left: 24 })
        .margin({ top: 30 })
        .onClick(() => {
          if (this.onContinue) {
            this.onContinue();
          }
        })
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
