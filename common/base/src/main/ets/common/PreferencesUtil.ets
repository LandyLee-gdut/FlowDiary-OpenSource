import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'PreferencesUtil';

/**
 * 用户首选项工具类
 * 提供轻量级键值型数据的持久化能力
 */
export class PreferencesUtil {
  private dataPreferences: preferences.Preferences | undefined = undefined;
  private readonly STORE_NAME = 'FlowDiaryStore';
  private isGskvStorage: boolean = false;
  private initializationPromise: Promise<preferences.Preferences | undefined> | null = null;

  constructor() {
  }

  /**
   * 初始化Preferences实例
   * @param context 应用上下文
   * @param storeName 存储文件名称,默认为'FlowDiaryStore'
   * @param useGSKV 是否使用GSKV存储模式,默认true
   */
  async init(context: Context, storeName?: string, useGSKV: boolean = true): Promise<preferences.Preferences | undefined> {
    if (this.dataPreferences) {
      hilog.info(DOMAIN, TAG, 'Preferences already initialized, skip re-init.');
      return this.dataPreferences;
    }

    if (this.initializationPromise) {
      hilog.info(DOMAIN, TAG, 'Preferences initialization in progress, awaiting existing promise.');
      return this.initializationPromise;
    }

    const targetName = storeName || this.STORE_NAME;
    const options: preferences.Options = { name: targetName };
    this.isGskvStorage = false;

    if (useGSKV) {
      const gskvSupported = typeof preferences.isStorageTypeSupported === 'function'
        ? preferences.isStorageTypeSupported(preferences.StorageType.GSKV)
        : false;

      if (gskvSupported) {
        hilog.info(DOMAIN, TAG, `Using GSKV storage mode for store ${targetName}`);
        options.storageType = preferences.StorageType.GSKV;
        this.isGskvStorage = true;
      } else {
        hilog.warn(DOMAIN, TAG, `GSKV mode not supported, fallback to XML mode for store ${targetName}`);
      }
    }

    const initPromise = new Promise<preferences.Preferences | undefined>((resolve, reject) => {
      try {
        preferences.getPreferences(context, options, (err: BusinessError, val: preferences.Preferences) => {
          if (err) {
            hilog.error(DOMAIN, TAG, `Failed to get preferences. code=${err.code}, message=${err.message}`);
            this.dataPreferences = undefined;
            this.isGskvStorage = false;
            reject(err);
            return;
          }
          this.dataPreferences = val;
          hilog.info(DOMAIN, TAG, `Preferences initialized successfully for ${targetName}. storageMode=${this.isGskvStorage ? 'GSKV' : 'XML'}`);
          resolve(val);
        });
      } catch (error) {
        hilog.error(DOMAIN, TAG, `Exception when initializing preferences: ${JSON.stringify(error)}`);
        this.dataPreferences = undefined;
        this.isGskvStorage = false;
        reject(error as BusinessError);
      }
    });

    this.initializationPromise = initPromise;
    initPromise.finally(() => {
      if (this.initializationPromise === initPromise) {
        this.initializationPromise = null;
      }
    });
    return initPromise;
  }

  /**
   * 获取Preferences实例
   */
  getPreferences(): preferences.Preferences | undefined {
    return this.dataPreferences;
  }

  /**
   * 判断当前Preferences是否已初始化
   */
  isInitialized(): boolean {
    return this.dataPreferences !== undefined;
  }

  /**
   * XML模式下需要手动flush，GSKV模式则不需要
   */
  requiresManualFlush(): boolean {
    return !this.isGskvStorage;
  }

  /**
   * 检查是否包含指定的键
   * @param key 键名
   * @returns true表示包含,false表示不包含
   */
  hasSync(key: string): boolean {
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, 'Preferences not initialized when calling hasSync');
      return false;
    }
    return this.dataPreferences.hasSync(key);
  }

  /**
   * 写入数据
   * @param key 键名(非空且长度不超过1024字节)
   * @param value 值
   */
  putSync(key: string, value: preferences.ValueType): void {
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, `Preferences not initialized when putting key '${key}'`);
      return;
    }
    try {
      hilog.info(DOMAIN, TAG, `putSync invoked. key=${key}, value=${JSON.stringify(value)}`);
      this.dataPreferences.putSync(key, value);
      if (!this.isGskvStorage) {
        this.flush();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to put value for key '${key}': ${JSON.stringify(err)}`);
    }
  }

  /**
   * 读取数据
   * @param key 键名
   * @param defValue 默认值
   * @returns 键对应的值,如果值为null或非默认值类型,返回默认值
   */
  getSync(key: string, defValue: preferences.ValueType): preferences.ValueType {
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, `Preferences not initialized when getting key '${key}'`);
      return defValue;
    }
    try {
      const value = this.dataPreferences.getSync(key, defValue);
      hilog.info(DOMAIN, TAG, `getSync retrieved. key=${key}, value=${JSON.stringify(value)}`);
      return value;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get value for key '${key}': ${JSON.stringify(err)}`);
      return defValue;
    }
  }

  /**
   * 删除数据
   * @param key 键名
   */
  deleteSync(key: string): void {
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, `Preferences not initialized when deleting key '${key}'`);
      return;
    }
    try {
      hilog.info(DOMAIN, TAG, `deleteSync invoked. key=${key}`);
      this.dataPreferences.deleteSync(key);
      if (!this.isGskvStorage) {
        this.flush();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to delete key '${key}': ${JSON.stringify(err)}`);
    }
  }

  /**
   * 数据持久化(仅XML模式需要调用,GSKV模式会自动持久化)
   * @param callback 回调函数
   */
  flush(callback?: (err: BusinessError) => void): void {
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, 'Preferences not initialized when flushing');
      return;
    }
    hilog.info(DOMAIN, TAG, 'Flushing preferences (XML mode)');
    this.dataPreferences.flush((err: BusinessError) => {
      if (err) {
        hilog.error(DOMAIN, TAG, `Failed to flush: Code:${err.code}, message:${err.message}`);
      } else {
        hilog.info(DOMAIN, TAG, 'Succeeded in flushing');
      }
      if (callback) {
        callback(err);
      }
    });
  }

  /**
   * 订阅数据变更
   * @param callback 数据变更回调函数
   */
  on(callback: (key: string) => void): void {
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, 'Preferences not initialized when subscribing to changes');
      return;
    }
    hilog.info(DOMAIN, TAG, 'Subscribed to preferences change event');
    this.dataPreferences.on('change', callback);
  }

  /**
   * 取消订阅数据变更
   * @param callback 数据变更回调函数(可选)
   */
  off(callback?: (key: string) => void): void {
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, 'Preferences not initialized when unsubscribing from changes');
      return;
    }
    hilog.info(DOMAIN, TAG, 'Unsubscribed from preferences change event');
    this.dataPreferences.off('change', callback);
  }

  /**
   * 删除指定的Preferences文件
   * @param context 应用上下文
   * @param storeName 存储文件名称
   * @param storageType 存储类型, 默认GSKV
   * @param callback 回调函数
   */
  static deletePreferences(
    context: Context,
    storeName: string,
    storageType: preferences.StorageType = preferences.StorageType.GSKV,
    callback?: (err: BusinessError) => void
  ): void {
    let options: preferences.Options = {
      name: storeName,
      storageType
    };
    preferences.deletePreferences(context, options, (err: BusinessError) => {
      if (err) {
        hilog.error(DOMAIN, TAG, `Failed to delete preferences: Code:${err.code}, message:${err.message}`);
      } else {
        hilog.info(DOMAIN, TAG, 'Succeeded in deleting preferences');
      }
      if (callback) {
        callback(err);
      }
    });
  }
}

// 单例实例，供全局复用
export const preferencesUtil: PreferencesUtil = new PreferencesUtil();
