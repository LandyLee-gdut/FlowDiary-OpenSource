export interface DaySegment {
  start: number;
  end: number;
}

export class TimeRecordUtil {

  // 格式化时间显示（毫秒 -> MM:SS 或 HH:MM:SS）
  static formatTime(milliseconds: number): string {
    const totalSeconds = Math.floor(milliseconds / 1000)
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60

    if (hours > 0) {
      // 返回 HH:MM:SS 格式
      return `${hours.toString().padStart(2, '0')}:${minutes
        .toString()
        .padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
    } else {
      // 返回 MM:SS 格式
      return `${minutes.toString().padStart(2, '0')}:${seconds
        .toString()
        .padStart(2, '0')}`
    }
  }

  /**
   * 将时间戳转换为一天中的具体时间 (HH:mm)
   * @param timestamp 时间戳（毫秒）
   * @returns 格式化后的时间字符串
   */
  static formatToHHmm(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = date.getHours();
    const minutes = date.getMinutes();

    return `${hours.toString().padStart(2, '0')}:${minutes
      .toString()
      .padStart(2, '0')}`;
  }

  /**
   * 格式化时长为可读格式（例如：1h 30m）
   * @param milliseconds 时长（毫秒）
   * @returns 格式化后的字符串
   */
  static formatDuration(milliseconds: number): string {
    if (milliseconds < 1) return '0m';

    const totalMinutes = Math.floor(milliseconds / 60000);
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;

    if (hours > 0) {
      return `${hours}h${minutes}m`;
    }
    return `${minutes}m`;
  }

  static formatDurationForMinutes(totalMinutes: number): string {
    if (totalMinutes < 1) return '0m';
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    if (hours > 0) {
      return `${hours}h${minutes}m`;
    }
    return `${minutes}m`;
  }

  /**
   * 计算两个时间戳之间的时长（毫秒）
   * @param startTime 开始时间（时间戳）
   * @param endTime 结束时间（时间戳），可选，如果不提供则使用当前时间
   * @returns 时长（毫秒）
   */
  static calculateDuration(startTime: number, endTime?: number): number {
    const end = endTime || Date.now();
    return end - startTime;
  }

  static getDayStart(timestamp: number): number {
    const date = new Date(timestamp);
    date.setHours(0, 0, 0, 0);
    return date.getTime();
  }

  static getNextDayStart(timestamp: number): number {
    const start = TimeRecordUtil.getDayStart(timestamp);
    return start + 24 * 60 * 60 * 1000;
  }

  static splitIntoDaySegments(startTime: number, endTime: number): DaySegment[] {
    if (endTime <= startTime) {
      const singleSegment: DaySegment = { start: startTime, end: endTime };
      return [singleSegment];
    }

    const segments: DaySegment[] = [];
    let segmentStart = startTime;
    const finalEnd = endTime;

    while (segmentStart < finalEnd) {
      const nextDayStart = TimeRecordUtil.getNextDayStart(segmentStart);
      const segmentEnd = Math.min(nextDayStart, finalEnd);
      const segment: DaySegment = { start: segmentStart, end: segmentEnd };
      segments.push(segment);
      if (segmentEnd >= finalEnd) {
        break;
      }
      segmentStart = segmentEnd;
    }

    return segments;
  }

  /**
   * 根据状态获取状态文本
   * @param status MatterStatus 枚举值
   * @returns 状态文本
   */
  static getStatusText(status: number): string {
    switch (status) {
      case 0:
        return '待办';
      case 1:
        return '进行中';
      case 2:
        return '已暂停';
      case 3:
        return '已归档';
      default:
        return '未知';
    }
  }

  /**
   * 根据时间戳，返回相对时间字符串（XX分钟前/X小时前/X天前）
   * @param timestamp 时间戳（毫秒）
   * @returns 相对时间字符串
   */
  static formatRelativeTime(timestamp: number, now: number = Date.now()): string {
    const diffMs = now - timestamp;
    const diffMinutes = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffMinutes < 60) {
      return `${diffMinutes}分钟前`;
    } else if (diffHours < 24) {
      return `${diffHours}小时前`;
    } else {
      return `${diffDays}天前`;
    }
  }

  /**
   * 将时间戳格式化为 YYYY-MM-DD 格式
   * @param timestamp 时间戳（毫秒）
   * @returns YYYY-MM-DD 格式的日期字符串
   */
  static formatToYYYYMMDD(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');

    return `${year}-${month}-${day}`;
  }
}
