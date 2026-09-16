/**
 * Shared enum for matter lifecycle states.
 */
export enum MatterStatus {
  TODO = 0,
  RECORDING = 1,
  PAUSED = 2,
  IDEA_POOL = 3,
  ARCHIVED = 4
}

/**
 * Enum for Idea Type to decouple IdeaPool membership from status.
 */
export enum IdeaType {
  UNKNOWN = 0,
  IDEA_POOL = 1,
  TODAY_ONLY = 2
}

/**
 * Enum for Idea Light State.
 */
export enum IdeaLightState {
  UNLIT = 0,
  LIT = 1
}
