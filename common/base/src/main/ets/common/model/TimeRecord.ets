/**
 * Observable time record model used across modules.
 */
@Observed
export class TimeRecord {
  id: string;
  activityId: string;
  startTime: number;
  endTime?: number;
  duration?: number;

  constructor(id: string, activityId: string, startTime: number, endTime?: number, duration?: number) {
    this.id = id;
    this.activityId = activityId;
    this.startTime = startTime;
    this.endTime = endTime;
    this.duration = duration;
  }
}
