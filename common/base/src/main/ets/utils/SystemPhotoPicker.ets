import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SystemPhotoPicker';

export interface PickSingleImageOptions {
  preselectedUris?: string[];
  isSearchSupported?: boolean;
  isPhotoTakingSupported?: boolean;
  isEditSupported?: boolean;
  isOriginalSupported?: boolean;
}

export async function pickSingleImageUri(options?: PickSingleImageOptions): Promise<string | null> {
  const picker = new photoAccessHelper.PhotoViewPicker();
  const selectOptions = new photoAccessHelper.PhotoSelectOptions();

  selectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  selectOptions.maxSelectNumber = 1;
  selectOptions.isSearchSupported = options?.isSearchSupported ?? true;
  selectOptions.isPhotoTakingSupported = options?.isPhotoTakingSupported ?? true;
  selectOptions.isEditSupported = options?.isEditSupported ?? false;
  selectOptions.isOriginalSupported = options?.isOriginalSupported ?? false;

  if (options?.preselectedUris && options.preselectedUris.length > 0) {
    selectOptions.preselectedUris = [...options.preselectedUris];
  }

  try {
    const result = await picker.select(selectOptions);
    const uri = result?.photoUris?.[0];
    return uri ?? null;
  } catch (err) {
    hilog.error(0x0000, TAG, `pickSingleImageUri failed: ${JSON.stringify(err)}`);
    throw err instanceof Error ? err : new Error(JSON.stringify(err));
  }
}
