export { AppColors, AppGradients } from './src/main/ets/constants/Color';
export { AppShadows } from './src/main/ets/constants/Shadow'
export { buildPointLightEffect, resolvePointLightProfile } from './src/main/ets/constants/PointLight'
export { RDBSQL } from './src/main/ets/constants/RDBSQL'
export { newTagColorOptions as TagOptions } from './src/main/ets/constants/TagConfig'
export { StorageKeys } from './src/main/ets/constants/StorageKeys'
export { PreferenceKeys } from './src/main/ets/constants/PreferenceKeys'
export { WidgetEventKeys } from './src/main/ets/constants/WidgetEventKeys'
export { TodayActivityItem } from './src/main/ets/common/model/TodayActivityItem'
export { TimeRecord } from './src/main/ets/common/model/TimeRecord'
export {
  FlowDiaryImportMode,
  FlowDiaryImportRecord,
  FlowDiaryImportEnvelope,
  FlowDiaryShareableTimeRecord,
  buildFlowDiaryImportEnvelope,
  buildFlowDiaryImportRecord,
  generateFlowDiaryImportRequestId,
  isShareableFlowDiaryRecord
} from './src/main/ets/common/goalfighter/FlowDiaryImportContract'
export {
  GoalFighterShareService,
  GoalFighterShareResult,
  GoalFighterShareOutcome,
  goalFighterShareService,
  GOAL_FIGHTER_BUNDLE_NAME,
  GOAL_FIGHTER_ABILITY_NAME,
  GOAL_FIGHTER_IMPORT_URI,
  GOAL_FIGHTER_IMPORT_PAYLOAD_KEY
} from './src/main/ets/common/goalfighter/GoalFighterShareService'
export { MatterStatus, IdeaType, IdeaLightState } from './src/main/ets/common/model/MatterStatus'
export { RDBStoreUtil } from './src/main/ets/database/RDBStoreUtil'
export { ColorUtil } from './src/main/ets/common/ColorUtil'
export { ColorConversion } from './src/main/ets/utils/ColorConversion'
export { EmojiUtil, EMOJI_PRESETS, EmojiCategory, EmojiItem, EmojiItemPayload, EmojiItemUpdate } from './src/main/ets/common/EmojiUtil'
export { EmojiPreference, DEFAULT_EMOJI_PREFERENCE } from './src/main/ets/common/EmojiPreference'
export { EmojiPreferenceService, emojiPreferenceService } from './src/main/ets/common/Service/EmojiPreferenceService'
export { TagColorPreferenceService, tagColorPreferenceService } from './src/main/ets/common/Service/TagColorPreferenceService'
export { ReflectChartPreferenceService, reflectChartPreferenceService } from './src/main/ets/common/Service/ReflectChartPreferenceService'
export { CalendarSyncService, calendarSyncService } from './src/main/ets/common/Service/CalendarSyncService'
export { TimeRecordUtil } from './src/main/ets/common/TimeRecordUtil'
export { StringUtil } from './src/main/ets/common/StringUtil'
export { VibratorUtil } from './src/main/ets/common/VibratorUtil'
export { PreferencesUtil, preferencesUtil } from './src/main/ets/common/PreferencesUtil'
export { HoldingHandService, holdingHandService } from './src/main/ets/common/holding/HoldingHandService'
export {
  ReflectChartIds,
  ReflectChartSettingItem,
  ReflectChartSettings,
  REFLECT_CHART_SETTINGS_VERSION,
  buildDefaultReflectChartSettings,
  getManagedReflectChartIds,
  isManagedReflectChartId,
  sanitizeReflectChartSettings
} from './src/main/ets/common/model/ReflectChartSettings'
export { TimeRecordWithContext, DayAggregation, TagPaletteEntry, TagPaletteMap, FocusDateBoundsRow } from './src/main/ets/database/ReviewAggregationTypes'
export { LabelSummaryModel } from './src/main/ets/common/model/LabelSummaryModel'
export { TagItem, TagModel } from './src/main/ets/common/model/TagItem'
export { tagService } from './src/main/ets/common/Service/TagService'
export { MatterItemModel, MatterItemModelInit } from './src/main/ets/common/model/MatterItemModel'
export { DEFAULT_SHEET_HEIGHT, calculateSheetHeight } from './src/main/ets/common/SheetHeightUtil'
export { ColorModeUtil, COLOR_MODE_STORAGE_KEY, COLOR_MODE_VERSION_KEY } from './src/main/ets/common/theme/ColorModeUtil'
export { buildFlowLightEffect, FlowLightColors } from './src/main/ets/common/FlowLightEffect'
export {
  IdeaActivity,
  SortEntry,
  IdeaPoolState,
  IdeaPoolPreferences,
  IdeaPoolViewMode,
  DEFAULT_IDEA_POOL_PREFERENCES,
  IdeaSummary,
  IdeaLightSummary,
  IdeaCollectionPatch,
  IdeaCategoryPatch,
  IdeaCollectionSummary,
  IdeaCategorySummary,
  IdeaCollection,
  IdeaCategory,
  MoveResult
} from './src/main/ets/common/model/IdeaPoolModels'

export { BreakpointConstants } from './src/main/ets/constants/BreakpointConstants'
export { BreakpointSystem, BreakpointType } from './src/main/ets/utils/BreakpointSystem'
export {
  FilesDirCarrier,
  SandboxMediaCopyResult,
  computeFileHashFromUri,
  deleteStoredFileBestEffort,
  guessFileExt,
  guessMimeTypeFromUri,
  relPathToImageUri,
  resolveStoredPath,
  savePickerUriToSandboxFiles
} from './src/main/ets/utils/MediaPersistence'
export { PickSingleImageOptions, pickSingleImageUri } from './src/main/ets/utils/SystemPhotoPicker'
export { ImageCacheUtils } from './src/main/ets/utils/ImageCacheUtils'
export {
  RecordingPhase,
  StartResult,
  StopResult,
  OpenRecordInfo,
  SessionSnapshot
} from './src/main/ets/recording/RecordingSessionTypes'
export type {
  SessionChangeCallback,
  TickCallback,
  SessionProjectionWriter,
  Unsubscribe
} from './src/main/ets/recording/RecordingSessionTypes'
export type { SessionCommands } from './src/main/ets/recording/SessionCommands'
export { RecordingSessionStore, recordingSessionStore, registerSessionCommands } from './src/main/ets/recording/RecordingSessionStore'
export { AddNewTagDialog, TagDialogDependencies, TagDialogMode } from './src/main/ets/common/component/AddNewTagDialog'
export {
  DEFAULT_CUSTOMIZE_COLOR,
  resetCustomizeColor,
  resolveSelectedColor,
  showValidationToast,
  validateTagForm
} from './src/main/ets/common/utils/TagDialogUtils'

export { BackupConstants, buildBackupZipFileName, formatBackupFilenameTimestamp } from './src/main/ets/backup/BackupConstants'
export {
  BackupErrorCode,
  BackupManifestV1,
  BackupValidationResult,
  BackupResult,
  AutoBackupDirState,
  BackupListItem
} from './src/main/ets/backup/BackupTypes'
export { listAutoBackups, purgeOldBackups } from './src/main/ets/backup/BackupRepository'
export { ensureAutoBackupDir, getAutoBackupDirState, clearAutoBackupDir } from './src/main/ets/backup/BackupLocationManager'
export {
  createManualBackupAndExport,
  createManualBackup,
  createAutoBackup,
  validateBackupZip,
  importAndRestore
} from './src/main/ets/backup/BackupService'
export type {
  ManualBackupOptions,
  ManualBackupPrepareOptions,
  AutoBackupOptions,
  RestoreBackupOptions
} from './src/main/ets/backup/BackupService'

// 通用Sheet组件
export {
  SheetMode,
  SheetTitleBarConfig,
  NameInputConfig,
  TagSelectorConfig,
  EmojiSelectorConfig,
  ItemFormSheetConfig,
  ItemFormState,
  ItemFormSheetCallbacks,
  ItemFormSheetPresets
} from './src/main/ets/common/component/ItemFormSheetTypes'
export {
  SheetTitleBar,
  SheetTitleBarParams,
  buildSheetTitleBar,
  createTitleBarParams
} from './src/main/ets/common/component/SheetTitleBar'
export { IdeaFormSheet, IdeaFormTitleBar } from './src/main/ets/common/component/IdeaFormSheet'
export { ItemFormContent } from './src/main/ets/common/component/ItemFormContent'
export { IdeaCollectionFormContent } from './src/main/ets/common/component/IdeaCollectionFormContent'
export { IdeaCollectionUpsertSheetContent } from './src/main/ets/common/component/IdeaCollectionUpsertSheetContent'
