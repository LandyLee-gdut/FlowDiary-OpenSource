/**
 * Represents a single activity item displayed on the "Today List" page.
 * It combines data from the activity, tag, and sort_config tables for UI rendering.
 */
export class TodayActivityItem {
  id: string;
  name: string;
  status: number;
  tagName: string | null;
  tagColorHex: string | null;
  displayOrder: number | null;

  constructor(
    id: string,
    name: string,
    status: number,
    tagName: string | null,
    tagColorHex: string | null,
    displayOrder: number | null
  ) {
    this.id = id;
    this.name = name;
    this.status = status;
    this.tagName = tagName;
    this.tagColorHex = tagColorHex;
    this.displayOrder = displayOrder;
  }
}
