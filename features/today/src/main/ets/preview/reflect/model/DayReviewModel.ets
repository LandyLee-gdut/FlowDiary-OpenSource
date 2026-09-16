import { TimeRecordUtil } from 'base'
import type { TimeRecordWithContext } from 'base'

export interface DayReviewRecord {
  recordId: string
  activityId: string
  activityTitle: string
  startTimeMs: number
  endTimeMs: number | null
  startLabel: string
  endLabel: string
  durationMinutes: number
  durationLabel: string
  note?: string | null
}

export interface DayReviewTagGroup {
  tagId: string | null
  tagName: string
  tagColor: string
  totalMinutes: number
  totalDurationLabel: string
  records: DayReviewRecord[]
}

export interface DayReviewPanelData {
  dateMs: number
  dateLabel: string
  backgroundColorHex: string
  accentColorHex?: string
  totalMinutes: number
  totalDurationLabel: string
  untaggedMinutes: number
  groups: DayReviewTagGroup[]
  dominantTagId?: string | null
}

const DEFAULT_BACKGROUND = '#F2F4FF'
const UNTITLED_ACTIVITY = '未命名活动'
const UNTAGGED_ID = '__untagged__'
const UNTAGGED_NAME = '未分配'
const UNTAGGED_COLOR = '#9CA3AF'

function toMinutes(durationMs?: number | null): number {
  if (!durationMs || durationMs <= 0) {
    return 0
  }
  return Math.round(durationMs / 60000)
}

function computeDuration(record: TimeRecordWithContext, dayStart: number, dayEndExclusive: number): number {
  const declaredDuration = record.durationMs ?? undefined
  
  // 如果没有 endTimeMs 且没有 durationMs，直接忽略该记录
  if (record.endTimeMs == null && declaredDuration === undefined) {
    return 0
  }
  
  const rawEnd = record.endTimeMs ?? (declaredDuration !== undefined ? record.startTimeMs + declaredDuration : 0)
  if (rawEnd === 0) {
    return 0
  }
  
  const clampedStart = Math.max(record.startTimeMs, dayStart)
  const clampedEnd = Math.min(rawEnd, dayEndExclusive)

  if (clampedEnd <= clampedStart) {
    return 0
  }

  const span = clampedEnd - clampedStart
  if (declaredDuration !== undefined && declaredDuration > 0) {
    return Math.min(span, declaredDuration)
  }
  return span
}

function toRecordView(record: TimeRecordWithContext, durationMs: number, durationMinutes: number): DayReviewRecord {
  const startLabel = TimeRecordUtil.formatToHHmm(record.startTimeMs)
  const rawEnd = record.endTimeMs ?? (record.startTimeMs + durationMs)
  const endLabel = rawEnd ? TimeRecordUtil.formatToHHmm(rawEnd) : '--'

  return {
    recordId: record.recordId,
    activityId: record.activityId,
    activityTitle: record.activityName || UNTITLED_ACTIVITY,
    startTimeMs: record.startTimeMs,
    endTimeMs: rawEnd ?? null,
    startLabel,
    endLabel,
    durationMinutes,
    durationLabel: TimeRecordUtil.formatDurationForMinutes(durationMinutes),
    note: undefined,
  }
}

interface GroupAccumulator {
  tagId: string | null
  tagName: string
  tagColor: string
  totalMinutes: number
  records: DayReviewRecord[]
}

function ensureGroup(accumulators: Map<string, GroupAccumulator>, record: TimeRecordWithContext): GroupAccumulator {
  const key = record.tagId ?? UNTAGGED_ID
  const existing = accumulators.get(key)
  if (existing) {
    return existing
  }

  const accumulator: GroupAccumulator = {
    tagId: record.tagId,
    tagName: record.tagName ?? UNTAGGED_NAME,
    tagColor: record.tagColorHex ?? UNTAGGED_COLOR,
    totalMinutes: 0,
    records: [],
  }
  accumulators.set(key, accumulator)
  return accumulator
}

function toHexComponent(value: number): string {
  const clamped = Math.max(0, Math.min(255, Math.round(value)))
  return clamped.toString(16).padStart(2, '0')
}

function lightenHexColor(hexColor: string | undefined, factor: number = 0.65): string {
  if (!hexColor || !hexColor.startsWith('#') || (hexColor.length !== 7 && hexColor.length !== 4)) {
    return DEFAULT_BACKGROUND
  }

  let normalized = hexColor
  if (hexColor.length === 4) {
    const r = hexColor.charAt(1)
    const g = hexColor.charAt(2)
    const b = hexColor.charAt(3)
    normalized = `#${r}${r}${g}${g}${b}${b}`
  }

  const r = parseInt(normalized.substring(1, 3), 16)
  const g = parseInt(normalized.substring(3, 5), 16)
  const b = parseInt(normalized.substring(5, 7), 16)

  if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) {
    return DEFAULT_BACKGROUND
  }

  const mix = (component: number) => component + (255 - component) * factor

  return `#${toHexComponent(mix(r))}${toHexComponent(mix(g))}${toHexComponent(mix(b))}`
}

function formatDateLabel(dateMs: number): string {
  const date = new Date(dateMs)
  const month = (date.getMonth() + 1).toString().padStart(2, '0')
  const day = date.getDate().toString().padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

function finalizeGroups(groups: GroupAccumulator[]): DayReviewTagGroup[] {
  return groups
    .map(group => ({
      tagId: group.tagId,
      tagName: group.tagName,
      tagColor: group.tagColor,
      totalMinutes: group.totalMinutes,
      totalDurationLabel: TimeRecordUtil.formatDurationForMinutes(group.totalMinutes),
      records: [...group.records].sort((a, b) => a.startTimeMs - b.startTimeMs),
    } as DayReviewTagGroup))
    .sort((a, b) => b.totalMinutes - a.totalMinutes)
}

export function buildDayReviewPanelData(dateMs: number, records: TimeRecordWithContext[]): DayReviewPanelData {
  const dayStart = TimeRecordUtil.getDayStart(dateMs)
  const dayEnd = dayStart + 24 * 60 * 60 * 1000

  const accumulators: Map<string, GroupAccumulator> = new Map()
  let totalMinutes = 0

  records.forEach(record => {
    const durationMs = computeDuration(record, dayStart, dayEnd)
    const durationMinutes = toMinutes(durationMs)
    if (durationMinutes <= 0) {
      return
    }

    const viewRecord = toRecordView(record, durationMs, durationMinutes)
    const group = ensureGroup(accumulators, record)
    group.records.push(viewRecord)
    group.totalMinutes += durationMinutes
    totalMinutes += durationMinutes
  })

  const groups = finalizeGroups(Array.from(accumulators.values()))
  const untaggedGroup = groups.find(group => group.tagId === null)
  const untaggedMinutes = untaggedGroup ? untaggedGroup.totalMinutes : 0

  const dominantGroup = groups[0]
  const accentColor = dominantGroup ? dominantGroup.tagColor : undefined
  const backgroundColorHex = dominantGroup ? lightenHexColor(accentColor) : DEFAULT_BACKGROUND

  return {
    dateMs: dayStart,
    dateLabel: formatDateLabel(dayStart),
    backgroundColorHex,
    accentColorHex: accentColor,
    totalMinutes,
    totalDurationLabel: TimeRecordUtil.formatDurationForMinutes(totalMinutes),
    untaggedMinutes,
    groups,
    dominantTagId: dominantGroup?.tagId ?? null,
  }
}
