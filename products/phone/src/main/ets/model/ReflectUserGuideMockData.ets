import dayjs from 'dayjs';
import { HmCalendarSelectedDay } from 'reflect/src/main/ets/model/CalendarModel';
import { AppColors } from 'base';

export interface ReflectTimelineSegment {
  id: string;
  label: string;
  range: string;
  weight: number;
  color: ResourceColor;
  textColor: ResourceColor;
}

export interface ReflectStreamTimelineItem {
  id: string;
  title: string;
  range: string;
  time: string;
  duration: string;
  color: ResourceColor;
  isLast: boolean;
}

export interface ReflectTrendSeries {
  name: string;
  color: string;
  lightColor: string;
  values: number[];
}

export interface ReflectTrendData {
  labels: string[];
  series: ReflectTrendSeries[];
}

export function createReflectGuideSelectedDays(): HmCalendarSelectedDay[] {
  const today = dayjs();
  const month = today.month();
  const year = today.year();

  const focusedDates: number[] = [
    Math.min(4, today.daysInMonth()),
    Math.min(11, today.daysInMonth()),
    Math.min(18, today.daysInMonth())
  ];

  return focusedDates.map((date: number): HmCalendarSelectedDay => {
    const formatted = dayjs().year(year).month(month).date(date).format('YYYY-MM-DD');
    return {
      date: formatted,
      text: `${date} 日`,
      textColor: $r('app.color.primary'),
      backgroundColor: $r('app.color.primary_lighter')
    };
  });
}

export function createReflectGuideTimelineSegments(): ReflectTimelineSegment[] {
  return [
    {
      id: 'warm-up',
      label: '晨间热身',
      range: '06:40 - 07:20',
      weight: 40,
      color: $r('app.color.data_viz_6'),
      textColor: $r('app.color.text_on_primary')
    },
    {
      id: 'deep-work',
      label: '书籍阅读',
      range: '09:00 - 10:30',
      weight: 90,
      color: $r('app.color.primary'),
      textColor: $r('app.color.text_on_primary')
    },
    {
      id: 'lunch',
      label: '午间放松',
      range: '12:20 - 13:00',
      weight: 40,
      color: $r('app.color.warning'),
      textColor: $r('app.color.text_primary')
    },
    {
      id: 'project',
      label: '看场电影',
      range: '13:30 - 16:20',
      weight: 170,
      color: $r('app.color.data_viz_1'),
      textColor: $r('app.color.text_on_primary')
    },
    {
      id: 'review',
      label: '游戏开黑',
      range: '20:00 - 21:00',
      weight: 60,
      color: $r('app.color.data_viz_5'),
      textColor: $r('app.color.text_on_primary')
    }
  ];
}

export function createReflectGuideStreamItems(): ReflectStreamTimelineItem[] {
  return [
    {
      id: 'stream-1',
      title: '晨间热身',
      range: '06:40 - 07:20',
      time: '06:40',
      duration: '40 分钟',
      color: $r('app.color.data_viz_6'),
      isLast: false
    },
    {
      id: 'stream-2',
      title: '书籍阅读',
      range: '09:00 - 10:30',
      time: '09:00',
      duration: '90 分钟',
      color: $r('app.color.primary'),
      isLast: false
    },
    {
      id: 'stream-3',
      title: '午间放松',
      range: '12:20 - 13:00',
      time: '12:20',
      duration: '40 分钟',
      color: $r('app.color.accent'),
      isLast: false
    },
    {
      id: 'stream-4',
      title: '看场电影',
      range: '13:30 - 16:20',
      time: '13:30',
      duration: '170 分钟',
      color: $r('app.color.data_viz_1'),
      isLast: false
    },
    {
      id: 'stream-5',
      title: '游戏开黑',
      range: '20:00 - 21:00',
      time: '20:00',
      duration: '60 分钟',
      color: $r('app.color.data_viz_5'),
      isLast: true
    }

  ];
}

export function createReflectGuideTrendData(): ReflectTrendData {
  const labels: string[] = [];
  for (let index = 6; index >= 0; index--) {
    const label = dayjs().subtract(index, 'day').format('MM/DD');
    labels.push(label);
  }

  const series: ReflectTrendSeries[] = [
    {
      name: '学习',
      color: AppColors.DATA_VIZ_1,
      lightColor: AppColors.DATA_VIZ_1_LIGHT,
      values: [3, 4, 6, 5, 7, 6, 8]
    },
    {
      name: '健康',
      color: AppColors.DATA_VIZ_6,
      lightColor: AppColors.DATA_VIZ_6_LIGHT,
      values: [2, 3, 3, 4, 4, 5, 5]
    },
    {
      name: '灵感',
      color: AppColors.DATA_VIZ_5,
      lightColor: AppColors.DATA_VIZ_5_LIGHT,
      values: [1, 2, 2, 3, 2, 3, 4]
    }
  ];

  return { labels, series };
}
