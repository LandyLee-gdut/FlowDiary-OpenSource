import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { FilesDirCarrier } from '../utils/MediaPersistence';

const TAG = 'ImageCacheUtils';

/**
 * 图片缓存工具类
 * 用于从应用沙箱定位图片，校验文件是否存在，提供默认占位图兜底
 */
export class ImageCacheUtils {
  private context: common.UIAbilityContext;
  
  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }
  
  /**
   * 根据业务标识获取沙箱图片路径
   * 
   * @param key 业务标识（如活动 ID）
   * @returns 沙箱图片路径，如果不存在则返回默认占位图路径
   */
  public async getSandboxImagePath(key: string): Promise<string> {
    const sandboxPath = `${this.context.filesDir}/diary_images/${key}.jpg`;
    
    try {
      // 校验文件是否存在
      if (fs.accessSync(sandboxPath)) {
        hilog.info(0x0000, TAG, `getSandboxImagePath found: ${sandboxPath}`);
        return sandboxPath;
      }
    } catch (error) {
      hilog.warn(0x0000, TAG, `getSandboxImagePath file not found: ${sandboxPath}`);
    }
    
    // 若沙箱图片不存在，返回默认占位图
    return this.getDefaultPlaceholderPath();
  }
  
  /**
   * 获取默认占位图路径
   * 
   * @returns 默认占位图的沙箱路径
   */
  public getDefaultPlaceholderPath(): string {
    const defaultPath = `${this.context.filesDir}/diary_images/default_cover.jpg`;
    
    // 检查默认占位图是否存在
    try {
      if (fs.accessSync(defaultPath)) {
        return defaultPath;
      }
    } catch (error) {
      hilog.warn(0x0000, TAG, `getDefaultPlaceholderPath default cover not found: ${defaultPath}`);
    }
    
    // 如果默认占位图也不存在，返回空字符串
    return '';
  }
  
  /**
   * 检查指定路径的图片是否存在
   * 
   * @param imagePath 图片路径
   * @returns 图片是否存在
   */
  public imageExists(imagePath: string): boolean {
    if (!imagePath || imagePath.trim().length === 0) {
      return false;
    }
    
    try {
      return fs.accessSync(imagePath);
    } catch (error) {
      return false;
    }
  }
}