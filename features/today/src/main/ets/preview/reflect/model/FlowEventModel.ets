export interface FlowEvent {
  id: number
  time: string
  duration: string
  title: string
  color: string
}

export interface FlowTimelineItem extends FlowEvent {
  startMs: number
  endMs: number
  durationMs: number
  durationMinutes: number
  endLabel: string
}
