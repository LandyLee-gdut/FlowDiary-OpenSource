import { TimeRecordUtil } from 'base'
import type { TimeRecordWithContext } from 'base'

export type TagTimeDistributionDimension = 'day' | 'week' | 'month' | 'year'

export interface TagTimeDistributionRequest {
  dimension: TagTimeDistributionDimension
  focusDateMs: number
}

export type DayPartKey = 'morning' | 'afternoon' | 'night'

export interface TagTimeDistributionPart {
  key: DayPartKey
  label: string
  minutes: number
  durationLabel: string
  ratio: number
}

export interface TagTimeDistributionItem {
  tagId: string | null
  tagName: string
  tagColor: string
  totalMinutes: number
  durationLabel: string
  ratio: number
  parts: TagTimeDistributionPart[]
}

export interface TagTimeDistributionPanelData {
  dimension: TagTimeDistributionDimension
  startMs: number
  endMs: number
  rangeLabel: string
  totalMinutes: number
  totalDurationLabel: string
  items: TagTimeDistributionItem[]
  dominantTagId?: string | null
}

const UNTITLED_TAG_NAME: string = '未分配'
const UNTAGGED_ID: string = '__untagged__'
const UNTAGGED_COLOR: string = '#9CA3AF'

const MINUTES_PER_HOUR: number = 60
const MS_PER_MINUTE: number = 60 * 1000
const MS_PER_HOUR: number = MINUTES_PER_HOUR * MS_PER_MINUTE

const MORNING_END_HOUR: number = 12
const AFTERNOON_END_HOUR: number = 18
const DAY_MS: number = 24 * 60 * 60 * 1000

function formatDateLabel(dateMs: number): string {
  const date: Date = new Date(dateMs)
  const month: string = (date.getMonth() + 1).toString().padStart(2, '0')
  const day: string = date.getDate().toString().padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

function formatMonthDayLabel(dateMs: number): string {
  const date: Date = new Date(dateMs)
  const month: string = (date.getMonth() + 1).toString().padStart(2, '0')
  const day: string = date.getDate().toString().padStart(2, '0')
  return `${month}/${day}`
}

function formatYearLabel(dateMs: number): string {
  const date: Date = new Date(dateMs)
  return `${date.getFullYear()}年`
}

function toMinutes(durationMs: number): number {
  if (!durationMs || durationMs <= 0) {
    return 0
  }
  return Math.round(durationMs / MS_PER_MINUTE)
}

interface ClampedRange {
  startMs: number
  endMs: number
}

function resolveClampedRange(record: TimeRecordWithContext, rangeStartMs: number, rangeEndExclusive: number): ClampedRange | null {
  if (!record.endTimeMs && !record.durationMs) {
    return null
  }
  const declaredDuration: number | undefined = record.durationMs ?? undefined
  const rawEnd: number = record.endTimeMs ?? (declaredDuration !== undefined ? record.startTimeMs + declaredDuration : record.startTimeMs)
  const clampedStart: number = Math.max(record.startTimeMs, rangeStartMs)
  const clampedEnd: number = Math.min(rawEnd, rangeEndExclusive)

  if (clampedEnd <= clampedStart) {
    return null
  }

  const span: number = clampedEnd - clampedStart
  if (declaredDuration !== undefined && declaredDuration > 0) {
    const duration: number = Math.min(span, declaredDuration)
    return { startMs: clampedStart, endMs: clampedStart + duration }
  }
  return { startMs: clampedStart, endMs: clampedEnd }
}

function overlapMs(startMs: number, endMs: number, segmentStartMs: number, segmentEndMs: number): number {
  const start: number = Math.max(startMs, segmentStartMs)
  const end: number = Math.min(endMs, segmentEndMs)
  if (end <= start) {
    return 0
  }
  return end - start
}

interface TagAccumulator {
  tagId: string | null
  tagName: string
  tagColor: string
  totalMs: number
  morningMs: number
  afternoonMs: number
  nightMs: number
}

function ensureAccumulator(accumulators: Map<string, TagAccumulator>, record: TimeRecordWithContext): TagAccumulator {
  const key: string = record.tagId ?? UNTAGGED_ID
  const existing: TagAccumulator | undefined = accumulators.get(key)
  if (existing) {
    return existing
  }

  const accumulator: TagAccumulator = {
    tagId: record.tagId,
    tagName: record.tagName ?? UNTITLED_TAG_NAME,
    tagColor: record.tagColorHex ?? UNTAGGED_COLOR,
    totalMs: 0,
    morningMs: 0,
    afternoonMs: 0,
    nightMs: 0,
  }
  accumulators.set(key, accumulator)
  return accumulator
}

function buildParts(morningMinutes: number, afternoonMinutes: number, nightMinutes: number): TagTimeDistributionPart[] {
  const maxMinutes: number = Math.max(morningMinutes, afternoonMinutes, nightMinutes, 0)
  const toRatio = (minutes: number): number => (maxMinutes > 0 ? minutes / maxMinutes : 0)

  return [
    {
      key: 'morning',
      label: '上午',
      minutes: morningMinutes,
      durationLabel: TimeRecordUtil.formatDurationForMinutes(morningMinutes),
      ratio: toRatio(morningMinutes),
    },
    {
      key: 'afternoon',
      label: '下午',
      minutes: afternoonMinutes,
      durationLabel: TimeRecordUtil.formatDurationForMinutes(afternoonMinutes),
      ratio: toRatio(afternoonMinutes),
    },
    {
      key: 'night',
      label: '夜间',
      minutes: nightMinutes,
      durationLabel: TimeRecordUtil.formatDurationForMinutes(nightMinutes),
      ratio: toRatio(nightMinutes),
    },
  ]
}

export interface TagTimeDistributionRange {
  startMs: number
  endMs: number
}

function getWeekStart(timestamp: number): number {
  const dayStart: number = TimeRecordUtil.getDayStart(timestamp)
  const date: Date = new Date(dayStart)
  const dayOfWeek: number = date.getDay()
  const offsetToMonday: number = (dayOfWeek + 6) % 7
  date.setHours(0, 0, 0, 0)
  date.setDate(date.getDate() - offsetToMonday)
  return date.getTime()
}

export function resolveTagTimeDistributionRange(dimension: TagTimeDistributionDimension, focusDateMs: number): TagTimeDistributionRange {
  const focusDayStart: number = TimeRecordUtil.getDayStart(focusDateMs)
  if (dimension === 'week') {
    const weekStart: number = getWeekStart(focusDayStart)
    return { startMs: weekStart, endMs: weekStart + DAY_MS * 7 - 1 }
  }
  if (dimension === 'month') {
    const focusDate: Date = new Date(focusDayStart)
    const startMs: number = new Date(focusDate.getFullYear(), focusDate.getMonth(), 1).getTime()
    const nextMonthStart: number = new Date(focusDate.getFullYear(), focusDate.getMonth() + 1, 1).getTime()
    return { startMs, endMs: nextMonthStart - 1 }
  }
  if (dimension === 'year') {
    const focusDate: Date = new Date(focusDayStart)
    const startMs: number = new Date(focusDate.getFullYear(), 0, 1).getTime()
    const nextYearStart: number = new Date(focusDate.getFullYear() + 1, 0, 1).getTime()
    return { startMs, endMs: nextYearStart - 1 }
  }
  return { startMs: focusDayStart, endMs: focusDayStart + DAY_MS - 1 }
}

function buildRangeLabel(dimension: TagTimeDistributionDimension, startMs: number, endMs: number): string {
  if (dimension === 'day') {
    return formatDateLabel(startMs)
  }
  if (dimension === 'year') {
    return formatYearLabel(startMs)
  }
  const startLabel: string = formatMonthDayLabel(startMs)
  const endLabel: string = formatMonthDayLabel(endMs)
  if (startLabel === endLabel) {
    return startLabel
  }
  return `${startLabel} - ${endLabel}`
}

function accumulateDayParts(accumulator: TagAccumulator, startMs: number, endMs: number): void {
  const segments = TimeRecordUtil.splitIntoDaySegments(startMs, endMs)
  segments.forEach(segment => {
    const segmentStart: number = segment.start
    const segmentEnd: number = segment.end
    if (segmentEnd <= segmentStart) {
      return
    }
    const segmentDayStart: number = TimeRecordUtil.getDayStart(segmentStart)
    const morningEnd: number = segmentDayStart + MORNING_END_HOUR * MS_PER_HOUR
    const afternoonEnd: number = segmentDayStart + AFTERNOON_END_HOUR * MS_PER_HOUR
    const nightEnd: number = segmentDayStart + DAY_MS

    accumulator.morningMs += overlapMs(segmentStart, segmentEnd, segmentDayStart, morningEnd)
    accumulator.afternoonMs += overlapMs(segmentStart, segmentEnd, morningEnd, afternoonEnd)
    accumulator.nightMs += overlapMs(segmentStart, segmentEnd, afternoonEnd, nightEnd)
  })
}

export function buildTagTimeDistributionPanelData(
  dimension: TagTimeDistributionDimension,
  range: TagTimeDistributionRange,
  records: TimeRecordWithContext[]
): TagTimeDistributionPanelData {
  const rangeEndExclusive: number = range.endMs + 1
  const accumulators: Map<string, TagAccumulator> = new Map()
  let totalMs: number = 0

  records.forEach((record: TimeRecordWithContext) => {
    const clampedRange: ClampedRange | null = resolveClampedRange(record, range.startMs, rangeEndExclusive)
    if (!clampedRange) {
      return
    }

    const spanMs: number = clampedRange.endMs - clampedRange.startMs
    if (spanMs <= 0) {
      return
    }

    const accumulator: TagAccumulator = ensureAccumulator(accumulators, record)
    accumulator.totalMs += spanMs
    totalMs += spanMs
    accumulateDayParts(accumulator, clampedRange.startMs, clampedRange.endMs)
  })

  const totalMinutes: number = toMinutes(totalMs)

  const items: TagTimeDistributionItem[] = Array.from(accumulators.values())
    .map((acc: TagAccumulator): TagTimeDistributionItem => {
      const minutes: number = toMinutes(acc.totalMs)
      const morningMinutes: number = toMinutes(acc.morningMs)
      const afternoonMinutes: number = toMinutes(acc.afternoonMs)
      const nightMinutes: number = toMinutes(acc.nightMs)
      const ratio: number = totalMinutes > 0 ? minutes / totalMinutes : 0

      return {
        tagId: acc.tagId,
        tagName: acc.tagName,
        tagColor: acc.tagColor,
        totalMinutes: minutes,
        durationLabel: TimeRecordUtil.formatDurationForMinutes(minutes),
        ratio,
        parts: buildParts(morningMinutes, afternoonMinutes, nightMinutes),
      }
    })
    .filter((item: TagTimeDistributionItem) => item.totalMinutes > 0)
    .sort((a: TagTimeDistributionItem, b: TagTimeDistributionItem) => b.totalMinutes - a.totalMinutes)

  const dominantTagId: string | null | undefined = items.length > 0 ? items[0].tagId : null

  return {
    dimension,
    startMs: range.startMs,
    endMs: range.endMs,
    rangeLabel: buildRangeLabel(dimension, range.startMs, range.endMs),
    totalMinutes,
    totalDurationLabel: TimeRecordUtil.formatDurationForMinutes(totalMinutes),
    items,
    dominantTagId,
  }
}
