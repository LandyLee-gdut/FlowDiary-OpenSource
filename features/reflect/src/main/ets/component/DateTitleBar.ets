import dayjs from 'dayjs';
import { AppShadows } from 'base';
import { StorageKeys } from 'base';

/**
 * DateTitleBar - A reusable date navigation component
 *
 * This component displays a date title with left/right navigation buttons
 * and manages the selected date, month, and year through shared AppStorage.
 *
 * The component synchronizes date selection across all views (month, week, day)
 * using @StorageLink decorators.
 */
@Component
export struct DateTitleBar {
  // Shared date selection state via AppStorage
  @StorageLink(StorageKeys.SELECTED_DATE) @Watch('syncViewToSelection') selectedDate: number = dayjs().date();
  @StorageLink(StorageKeys.SELECTED_MONTH) @Watch('syncViewToSelection') selectedMonth: number = dayjs().month() + 1;
  @StorageLink(StorageKeys.SELECTED_YEAR) @Watch('syncViewToSelection') selectedYear: number = dayjs().year();
  // Calendar view state (month navigation)
  @StorageLink(StorageKeys.VIEW_DATE) @Watch('handleViewChange') viewDate: number = dayjs().date();
  @StorageLink(StorageKeys.VIEW_MONTH) @Watch('handleViewChange') viewMonth: number = dayjs().month() + 1;
  @StorageLink(StorageKeys.VIEW_YEAR) @Watch('handleViewChange') viewYear: number = dayjs().year();
  @State isCurrentMonth: boolean = false;
  // Optional callbacks for consumers that need to react to date changes
  onDateChange?: (dateString: string) => void;
  onMonthChange?: (monthString: string) => void;

  // Date format
  private format: string = 'YYYY-MM-DD';
  private checkCurrentMonth() {
    const today = new Date();
    this.isCurrentMonth = this.viewYear === today.getFullYear() &&
      this.viewMonth === today.getMonth() + 1;
  }
  private syncViewToSelection(): void {
    if (this.viewYear !== this.selectedYear || this.viewMonth !== this.selectedMonth || this.viewDate !== this.selectedDate) {
      this.updateViewStorage(this.selectedYear, this.selectedMonth, this.selectedDate);
    }
  }
  private handleViewChange(): void {
    this.checkCurrentMonth();
  }
  aboutToAppear(): void {
    this.checkCurrentMonth();
  }
  /**
   * Get current date string from storage values
   */
  private getCurrentDateString(): string {
    return `${this.viewYear}-${this.viewMonth.toString().padStart(2, '0')}-${this.viewDate.toString().padStart(2, '0')}`;
  }

  /**
   * Update storage with new date values
   */
  private updateViewStorage(year: number, month: number, date: number): void {
    this.viewYear = year;
    this.viewMonth = month;
    this.viewDate = date;
  }

  /**
   * Handle previous month navigation
   */
  private handlePrevMonth(): void {
    const currentDate = dayjs(`${this.viewYear}-${this.viewMonth.toString().padStart(2, '0')}-${this.viewDate.toString().padStart(2, '0')}`);
    const prevMonthDate = currentDate.subtract(1, 'month');

    // Adjust date if it exceeds the days in the new month
    const daysInPrevMonth = prevMonthDate.daysInMonth();
    const newDate = Math.min(this.viewDate, daysInPrevMonth);

    this.updateViewStorage(
      prevMonthDate.year(),
      prevMonthDate.month() + 1,
      newDate
    );

    this.checkCurrentMonth();

    // Notify consumers
    if (this.onMonthChange) {
      this.onMonthChange(prevMonthDate.format('YYYY-MM'));
    }
    if (this.onDateChange) {
      this.onDateChange(prevMonthDate.date(newDate).format(this.format));
    }
  }

  /**
   * Handle next month navigation
   */
  private handleNextMonth(): void {
    const currentDate = dayjs(`${this.viewYear}-${this.viewMonth.toString().padStart(2, '0')}-${this.viewDate.toString().padStart(2, '0')}`);
    const nextMonthDate = currentDate.add(1, 'month');

    // Adjust date if it exceeds the days in the new month
    const daysInNextMonth = nextMonthDate.daysInMonth();
    const newDate = Math.min(this.viewDate, daysInNextMonth);

    this.updateViewStorage(
      nextMonthDate.year(),
      nextMonthDate.month() + 1,
      newDate
    );

    this.checkCurrentMonth();

    // Notify consumers
    if (this.onMonthChange) {
      this.onMonthChange(nextMonthDate.format('YYYY-MM'));
    }
    if (this.onDateChange) {
      this.onDateChange(nextMonthDate.date(newDate).format(this.format));
    }
  }

  /**
   * Render navigation button
   */
  @Builder
  btnBuilder(glyph: Resource, onClick: () => void, bgc?: ResourceColor) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(glyph)
        .fontSize(15)
        .fontWeight(500)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(30)
    .height(30)
    .backgroundColor($r('app.color.neutral_200'))
    .onClick(bgc ? undefined : () => onClick())
    .shadow(AppShadows.CARD_RESTING)
  }

  build() {
    Row() {
      // Previous month button
      this.btnBuilder($r('sys.symbol.arrow_left'), () => this.handlePrevMonth())
      // Date display
      // Text(this.getCurrentDateString())
      //   .width('60%')
      //   .textAlign(TextAlign.Center)
      //   .fontSize(16)
      //   .fontColor($r('app.color.text_secondary'))
      //   .fontWeight(500)
      //   .backgroundColor($r('app.color.neutral_200'))
      //   .padding({top: 5, bottom: 5})
      //   .borderRadius('50%')

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_right'))
          .fontSize(15)
          .fontWeight(500)
          .fontColor(this.isCurrentMonth ? [Color.White] : [$r('app.color.text_primary')])
      }
      .width(30)
      .height(30)
      .backgroundColor(this.isCurrentMonth ? $r('app.color.neutral_100') : $r('app.color.neutral_200'))
      .onClick(this.isCurrentMonth ? undefined : () => this.handleNextMonth())
      .shadow(AppShadows.CARD_RESTING)
    }
    .backgroundColor($r('app.color.bg_card'))
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .height('100%')
    .shadow(AppShadows.CARD_RESTING)
    .borderRadius('50%')
    .padding({left: 10, right: 10})
    // .margin({bottom: 20 })
  }
}
