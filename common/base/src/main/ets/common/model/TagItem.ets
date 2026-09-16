/**
 * Represents a single Tag entity from the database.
 */
export class TagItem {
  id: string;
  name: string;
  color: string;
  lightColor: string;
  createdAt: number;
  updatedAt: number;

  constructor(id: string, name: string, color: string, lightColor: string, createdAt: number, updatedAt: number) {
    this.id = id;
    this.name = name;
    this.color = color;
    this.lightColor = lightColor
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }
}

// /model/TagModel.ts

/**
 * Represents a single user-defined tag.
 * Corresponds to the 'tag' table in the database schema.
 */
export interface TagModel {
  /**
   * The unique identifier for the tag (e.g., 'tag-001').
   * Maps to 'tag_id' (TEXT, PRIMARY KEY).
   */
  id: string;

  /**
   * The display name of the tag (e.g., '工作').
   * Maps to 'name' (TEXT, UNIQUE).
   */
  name: string;

  /**
   * The main, saturated color for the tag.
   * Used for text, icons, or borders to ensure high contrast and visibility.
   * Maps to 'color' (TEXT).
   */
  color: string;

  /**
   * A lighter, less saturated shade of the main color.
   * **Purpose**: Designed to be used as the background fill for tag "pills" or "capsules".
   * This provides a soft, visually appealing look without overwhelming the user.
   * Dynamically derived from the corresponding gradient in AppGradients.
   */
  lightColor: string;
}
