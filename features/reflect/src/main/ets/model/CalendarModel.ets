import dayjs from 'dayjs'
import { TimeRecord, LabelSummaryModel } from 'base'
import { reflectService } from './ReflectService'

export interface HmCalendarSelectedDay {
  date: string
  text?: ResourceStr
  textColor?: ResourceColor
  backgroundColor?: ResourceColor
}

export enum HmCalendarType {
  MONTH,
  WEEK,
  MONTH_DOT
}

export interface HmCalendarItem {
  date: number
  month: number
  year: number
  day?: number
  inMonth?: boolean
  selectedFlag?: boolean
  selectedText?: ResourceStr
  selectedTextColor?: ResourceColor
  selectedBackgroundColor?: ResourceColor
  timeRecordData?: TimeRecord[]
  labelSummaryData: LabelSummaryModel[]
}

export interface ViewDateState {
  viewYear: number
  viewMonth: number
  viewDate: number
}

export type DaySummaryProvider = (dateMs: number, forceReload?: boolean) => Promise<LabelSummaryModel[]>

export interface MonthSwipeResult extends ViewDateState {
  monthString: string
  dateString: string
}

export function getViewDateString(state: ViewDateState): string {
  return `${state.viewYear}-${state.viewMonth.toString().padStart(2, '0')}-${state.viewDate.toString().padStart(2, '0')}`
}

export function computeMonthSwipe(state: ViewDateState, isNext: boolean, format: string): MonthSwipeResult {
  const currentDate = dayjs(getViewDateString(state))
  const targetDate = isNext ? currentDate.add(1, 'month') : currentDate.subtract(1, 'month')
  const daysInTargetMonth = targetDate.daysInMonth()
  const newDate = Math.min(state.viewDate, daysInTargetMonth)

  const updatedViewYear = targetDate.year()
  const updatedViewMonth = targetDate.month() + 1

  const monthString = targetDate.format('YYYY-MM')
  const dateString = targetDate.date(newDate).format(format)

  return {
    viewYear: updatedViewYear,
    viewMonth: updatedViewMonth,
    viewDate: newDate,
    monthString,
    dateString
  }
}

export function buildSelectedDayMap(selectedDays: HmCalendarSelectedDay[], format: string): Map<string, HmCalendarSelectedDay> {
  const map = new Map<string, HmCalendarSelectedDay>()
  selectedDays.forEach(day => {
    const parsed = dayjs(day.date)
    if (parsed.isValid()) {
      map.set(parsed.format(format), day)
    }
  })
  return map
}

async function getDaySummaryData(dateString: string, provider?: DaySummaryProvider, forceReload: boolean = false): Promise<LabelSummaryModel[]> {
  try {
    const dateMs = dayjs(dateString).valueOf()
    const result: LabelSummaryModel[] = provider
      ? await provider(dateMs, forceReload)
      : await reflectService.getDayLabelSummary(dateMs)

    if (result.length > 0) {
      console.info(`Calendar: Got ${result.length} label summaries for ${dateString}`)
    }
    return result
  } catch (error) {
    console.error('Error getting day summary data:', error)
    return []
  }
}

interface LoadCalendarItemsParams {
  viewState: ViewDateState
  selectedDays: HmCalendarSelectedDay[]
  type: HmCalendarType
  format: string
  defaultText: ResourceStr
  defaultColor: ResourceColor
  getDaySummaryData?: DaySummaryProvider
  forceReload?: boolean
}

export async function loadCalendarItems(params: LoadCalendarItemsParams): Promise<HmCalendarItem[]> {
  const viewState = params.viewState;
  const selectedDays = params.selectedDays;
  const type = params.type;
  const format = params.format;
  const defaultText = params.defaultText;
  const defaultColor = params.defaultColor;
  const provider = params.getDaySummaryData;
  const forceReload = params.forceReload ?? false;
  const items: HmCalendarItem[] = []
  const currDate = dayjs(getViewDateString(viewState))
  const selectedDayMap = buildSelectedDayMap(selectedDays, format)
  const LEN = 42

  const currDays = currDate.daysInMonth()
  const dayItems: HmCalendarItem[] = []
  const dateStrings: string[] = []

  for (let index = 1; index <= currDays; index++) {
    const dayDate = currDate.date(index)
    const dateString = dayDate.format(format)
    const selectedDay = selectedDayMap.get(dateString)
    const selectedFlag = !!selectedDay
    const selectedText: ResourceStr = selectedDay?.text || defaultText
    const selectedTextColor: ResourceColor = selectedDay?.textColor || defaultColor
    const selectedBackgroundColor: ResourceColor = selectedDay?.backgroundColor || defaultColor

    dayItems.push({
      date: index,
      month: currDate.month() + 1,
      year: currDate.year(),
      day: dayDate.day(),
      inMonth: true,
      selectedFlag,
      selectedText,
      selectedTextColor,
      selectedBackgroundColor,
      labelSummaryData: []
    })

    dateStrings.push(dateString)
  }

  try {
    const summaryDataPromises = dateStrings.map(dateString => getDaySummaryData(dateString, provider, forceReload))
    const allSummaryData = await Promise.all(summaryDataPromises)
    for (let i = 0; i < dayItems.length; i++) {
      dayItems[i].labelSummaryData = allSummaryData[i]
    }
  } catch (error) {
    console.error('Error loading calendar summary data:', error)
  }

  items.push(...dayItems)

  if (type === HmCalendarType.MONTH || type === HmCalendarType.WEEK) {
    const prevMonth = currDate.date(0)
    const prevMonthLastDate = prevMonth.date()
    const prevDays = prevMonth.day()
    if (prevDays < 6) {
      for (let index = 0; index <= prevDays; index++) {
        items.unshift({
          date: prevMonthLastDate - index,
          month: prevMonth.month() + 1,
          year: prevMonth.year(),
          inMonth: false,
          labelSummaryData: []
        })
      }
    }

    const nextMonth = currDate.date(currDays + 1)
    const start = items.length
    for (let index = 1; index <= LEN - start; index++) {
      items.push({
        date: index,
        month: nextMonth.month() + 1,
        year: nextMonth.year(),
        inMonth: false,
        labelSummaryData: []
      })
    }
  }

  if (type === HmCalendarType.WEEK) {
    const focusDate = dayjs(getViewDateString(viewState))
    const weekIndex = Math.floor(focusDate.date() / 7)
    return items.slice(weekIndex * 7, (weekIndex + 1) * 7)
  }

  return items
}
