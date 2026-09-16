import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 公共标签弹窗工具方法，封装了表单校验和颜色选择逻辑。
 */
export const DEFAULT_CUSTOMIZE_COLOR: string = '#F5F5F5';

export function validateTagForm(inputTagName: string, selectedLabelIndex: number): string | undefined {
  if (!inputTagName || inputTagName.trim().length === 0) {
    return '标签名称不能为空';
  }

  if (selectedLabelIndex < 0 && selectedLabelIndex !== -100) {
    return '请选择标签颜色';
  }

  return undefined;
}

export function resolveSelectedColor(selectedLabelIndex: number, customizeColorState: string, presetColors: string[]): string {
  return selectedLabelIndex === -100 ? customizeColorState : presetColors[selectedLabelIndex];
}

export function resetCustomizeColor(): string {
  return DEFAULT_CUSTOMIZE_COLOR;
}

export async function showValidationToast(message: string, tag: string): Promise<void> {
  hilog.error(0x0000, tag, message);
  await promptAction.openToast({
    duration: 1000,
    message
  });
}
