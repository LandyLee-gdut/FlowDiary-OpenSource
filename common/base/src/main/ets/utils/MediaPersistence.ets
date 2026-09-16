import fs from '@ohos.file.fs';
import { fileUri, hash } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';

export interface SandboxMediaCopyResult {
  relPath: string;
  absPath: string;
  imageUri: string;
}

const DEFAULT_IMAGE_EXT = '.jpg';
const TAG = 'MediaPersistence';
const ONE_MB = 1024 * 1024;
const DEFAULT_COMPRESS_QUALITY = 80;

export interface FilesDirCarrier {
  filesDir?: string;
}

interface ErrorLike {
  code?: number;
  message?: string;
}

// Define PackingOption format explicitly since ArkTS doesn't support indexed access types
export type PackingFormat = 'image/png' | 'image/jpeg' | 'image/webp' | 'image/gif' | 'image/heic';

interface PackingFormatResult {
  format: PackingFormat;
  outputExt: string;
}

interface CompressionPacking {
  format: PackingFormat;
  quality: number;
}

interface TargetPathsResult {
  fileName: string;
  absPath: string;
  relPath: string;
}

function resolveFilesDir(ctx: FilesDirCarrier, tag: string): string {
  if (ctx && typeof ctx.filesDir === 'string' && ctx.filesDir.trim().length > 0) {
    return ctx.filesDir;
  }

  try {
    const appCtx = AppStorage.get('context') as common.UIAbilityContext;
    if (appCtx && typeof appCtx.filesDir === 'string' && appCtx.filesDir.trim().length > 0) {
      hilog.warn(0x0000, tag, 'PhotoPick resolveFilesDir fallback to AppStorage context filesDir');
      return appCtx.filesDir;
    }
  } catch (_err) {
    // ignore and throw below
  }

  throw new Error('PhotoPick invalid context: filesDir is missing');
}

function normalizeStoredPath(ctx: FilesDirCarrier, storedPath: string): string | null {
  if (storedPath.startsWith('/')) {
    return storedPath;
  }
  try {
    const filesDir = resolveFilesDir(ctx, TAG);
    return `${filesDir}/${storedPath}`;
  } catch (err) {
    hilog.error(0x0000, TAG, `PhotoPick normalizeStoredPath failed: ${err instanceof Error ? err.message : String(err)}`);
    return null;
  }
}

export function guessFileExt(uri: string): string {
  const match = uri.match(/\.(jpg|jpeg|png|webp|heic|gif)\b/i);
  if (!match) {
    return DEFAULT_IMAGE_EXT;
  }
  return `.${match[1].toLowerCase()}`;
}

export function guessMimeTypeFromUri(uri: string): string {
  const ext = guessFileExt(uri).toLowerCase();
  switch (ext) {
    case '.png':
      return 'image/png';
    case '.webp':
      return 'image/webp';
    case '.gif':
      return 'image/gif';
    case '.heic':
      return 'image/heic';
    case '.jpeg':
    case '.jpg':
    default:
      return 'image/jpeg';
  }
}

export function resolveStoredPath(ctx: FilesDirCarrier, storedPath: string): string | null {
  if (!storedPath || storedPath.trim().length === 0) {
    return null;
  }
  return normalizeStoredPath(ctx, storedPath);
}

export async function computeFileHashFromUri(srcUri: string, algorithm: string = 'sha256'): Promise<string> {
  if (!srcUri || srcUri.trim().length === 0) {
    throw new Error('PhotoPick computeFileHashFromUri failed: srcUri is empty');
  }

  let srcFd: number | null = null;
  try {
    srcFd = fs.openSync(srcUri, fs.OpenMode.READ_ONLY).fd;
  } catch (err) {
    const maybeError = err as ErrorLike;
    const errMessage = maybeError?.message ? maybeError.message : JSON.stringify(err);
    const errCode = typeof maybeError?.code === 'number' ? maybeError.code : -1;
    hilog.error(0x0000, TAG,
      `PhotoPick computeFileHashFromUri open src failed srcUri=${srcUri} code=${errCode} message=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }

  try {
    const hasher = hash.createHash(algorithm);
    const buffer = new ArrayBuffer(1024 * 1024);
    while (true) {
      const bytesRead = fs.readSync(srcFd as number, buffer);
      if (bytesRead <= 0) {
        break;
      }
      const chunk = bytesRead === buffer.byteLength ? buffer : buffer.slice(0, bytesRead);
      hasher.update(chunk);
    }
    const digest = hasher.digest();
    const digestValue = typeof digest === 'string' ? digest : String(digest);
    hilog.info(0x0000, TAG, `PhotoPick computeFileHashFromUri ok hash=${digestValue}`);
    return digestValue;
  } finally {
    try {
      if (srcFd !== null) {
        fs.closeSync(srcFd);
      }
    } catch (err) {
      hilog.warn(0x0000, TAG, `PhotoPick computeFileHashFromUri close src failed: ${JSON.stringify(err)}`);
    }
  }
}

function resolvePackingFormat(ext: string): PackingFormatResult {
  const lower = ext.toLowerCase();
  switch (lower) {
    case '.png':
      return { format: 'image/png', outputExt: '.png' };
    case '.webp':
      return { format: 'image/webp', outputExt: '.webp' };
    case '.jpeg':
    case '.jpg':
    default:
      return { format: 'image/jpeg', outputExt: '.jpg' };
  }
}

async function compressImageToFile(srcUri: string, absPath: string, packing: CompressionPacking): Promise<number> {
  let srcFile: fs.File | null = null;
  let imagePacker: image.ImagePacker | null = null;
  let pixelMap: image.PixelMap | null = null;

  try {
    // 使用异步打开文件，这样可以通过文件描述符获取大小
    srcFile = await fs.open(srcUri, fs.OpenMode.READ_ONLY);

    // 通过文件描述符获取文件大小
    const stat = await fs.stat(srcFile.fd);
    const srcFileSize = Number(stat.size) || 0;

    // 根据文件大小动态调整压缩质量和缩放比例
    const sizeInMB = srcFileSize / 1024 / 1024;
    const quality = sizeInMB > 8 ? 30 : (sizeInMB > 2 ? 50 : DEFAULT_COMPRESS_QUALITY);

    // 根据文件大小动态调整缩放比例
    let scaleRatio: number;
    if (sizeInMB > 10) {
      scaleRatio = 0.3; // 超大图片缩放到30%
    } else if (sizeInMB > 5) {
      scaleRatio = 0.5; // 大图片缩放到50%
    } else if (sizeInMB > 2) {
      scaleRatio = 0.7; // 中等图片缩放到70%
    } else {
      scaleRatio = 1.0; // 小图片不缩放
    }

    hilog.info(0x0000, TAG,
      `PhotoPick compressImageToFile srcFileSize=${srcFileSize}MB=${sizeInMB.toFixed(2)} quality=${quality} scaleRatio=${scaleRatio}`);

    // 创建图像源
    const imageSource = image.createImageSource(srcFile.fd);

    // 创建可编辑的 PixelMap
    const decodingOptions: image.DecodingOptions = { editable: true };
    pixelMap = await imageSource.createPixelMap(decodingOptions);

    // 使用 scale 进行尺寸缩放
    if (scaleRatio < 1.0) {
      await pixelMap.scale(scaleRatio, scaleRatio);
      const imageInfo = await pixelMap.getImageInfo();
      hilog.info(0x0000, TAG,
        `PhotoPick compressImageToFile scaled size=${imageInfo.size.width}x${imageInfo.size.height}`);
    }

    // 释放 imageSource
    imageSource.release();

    // 创建图像打包器
    imagePacker = image.createImagePacker();

    // 打包 PixelMap 到 buffer（质量压缩）
    const packingOption: image.PackingOption = {
      format: packing.format,
      quality: quality,
      bufferSize: srcFileSize
    };
    const imageBuffer = await imagePacker.packing(pixelMap, packingOption);

    // 释放资源
    if (pixelMap !== null) {
      pixelMap.release();
      pixelMap = null;
    }
    imagePacker.release();
    imagePacker = null;

    // 写入目标文件
    fs.closeSync(srcFile);
    srcFile = null;

    const dstFile = fs.openSync(absPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    fs.writeSync(dstFile.fd, imageBuffer);
    fs.closeSync(dstFile.fd);

    hilog.info(0x0000, TAG,
      `PhotoPick compressImageToFile compressed outputSize=${imageBuffer.byteLength}`);

    return imageBuffer.byteLength;
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    hilog.error(0x0000, TAG, `PhotoPick compressImageToFile failed err=${errMsg}`);

    // 清理资源
    if (pixelMap !== null) {
      try {
        pixelMap.release();
      } catch (_) {
        // ignore release failure
      }
    }
    if (imagePacker !== null) {
      try {
        imagePacker.release();
      } catch (_) {
        // ignore release failure
      }
    }
    if (srcFile !== null) {
      try {
        fs.closeSync(srcFile.fd);
      } catch (_) {
        // ignore close failure
      }
    }

    throw err instanceof Error ? err : new Error(errMsg);
  }
}

function buildTargetPaths(targetDir: string, dirName: string, ext: string): TargetPathsResult {
  const fileName = `${Date.now()}_${Math.floor(Math.random() * 1000000)}${ext}`;
  const result: TargetPathsResult = {
    fileName,
    absPath: `${targetDir}/${fileName}`,
    relPath: `${dirName}/${fileName}`
  };
  return result;
}

function copyFileToPath(srcUri: string, absPath: string, tag: string): number {
  let srcFd: number | null = null;
  let dstFd: number | null = null;
  try {
    srcFd = fs.openSync(srcUri, fs.OpenMode.READ_ONLY).fd;
  } catch (err) {
    const maybeError = err as ErrorLike;
    const errMessage = maybeError?.message ? maybeError.message : JSON.stringify(err);
    const errCode = typeof maybeError?.code === 'number' ? maybeError.code : -1;
    hilog.error(0x0000, tag,
      `PhotoPick savePickerUriToSandboxFiles open src failed srcUri=${srcUri} code=${errCode} message=${errMessage}`);
    throw err instanceof Error ? err : new Error(errMessage);
  }
  try {
    dstFd = fs.openSync(absPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC).fd;
  } catch (err) {
    const maybeError = err as ErrorLike;
    const errMessage = maybeError?.message ? maybeError.message : JSON.stringify(err);
    const errCode = typeof maybeError?.code === 'number' ? maybeError.code : -1;
    hilog.error(0x0000, tag,
      `PhotoPick savePickerUriToSandboxFiles open dst failed absPath=${absPath} code=${errCode} message=${errMessage}`);
    try {
      if (srcFd !== null) {
        fs.closeSync(srcFd);
      }
    } catch (_) {
      // ignore close failure
    }
    throw err instanceof Error ? err : new Error(errMessage);
  }
  try {
    const buffer = new ArrayBuffer(1024 * 1024);
    let totalWritten = 0;
    while (true) {
      const bytesRead = fs.readSync(srcFd as number, buffer);
      if (bytesRead <= 0) {
        break;
      }
      fs.writeSync(dstFd as number, buffer, { length: bytesRead });
      totalWritten += bytesRead;
    }
    return totalWritten;
  } finally {
    try {
      if (srcFd !== null) {
        fs.closeSync(srcFd);
      }
    } catch (err) {
      hilog.warn(0x0000, tag, `PhotoPick savePickerUriToSandboxFiles close src failed: ${JSON.stringify(err)}`);
    }
    try {
      if (dstFd !== null) {
        fs.closeSync(dstFd);
      }
    } catch (err) {
      hilog.warn(0x0000, tag, `PhotoPick savePickerUriToSandboxFiles close dst failed: ${JSON.stringify(err)}`);
    }
  }
}

export async function savePickerUriToSandboxFiles(
  ctx: FilesDirCarrier,
  srcUri: string,
  dirName: string = 'diary_images'
): Promise<SandboxMediaCopyResult> {
  hilog.info(0x0000, TAG, `PhotoPick savePickerUriToSandboxFiles start dirName=${dirName} srcUri=${srcUri}`);
  let filesDir: string;
  try {
    filesDir = resolveFilesDir(ctx, TAG);
  } catch (err) {
    hilog.error(0x0000, TAG, 'PhotoPick savePickerUriToSandboxFiles invalid ctx: missing filesDir');
    throw err instanceof Error ? err : new Error(String(err));
  }

  const targetDir = `${filesDir}/${dirName}`;
  try {
    fs.mkdirSync(targetDir, true);
  } catch (_err) {
    // ignore if already exists
  }

  const originalExt = guessFileExt(srcUri);
  const packing = resolvePackingFormat(originalExt);
  let srcFileSize = 0;
  try {
    const stat = fs.statSync(srcUri);
    srcFileSize = Number(stat.size) || 0;
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    hilog.warn(0x0000, TAG,
      `PhotoPick savePickerUriToSandboxFiles stat failed srcUri=${srcUri}, will try compress anyway err=${errMsg}`);
    // 无法获取文件大小时，尝试压缩（相册URI的文件通常比较大）
    srcFileSize = 0;
  }
  // 如果无法获取文件大小（srcFileSize=0），默认尝试压缩
  const shouldCompress = srcFileSize === 0 || srcFileSize > ONE_MB;
  hilog.info(0x0000, TAG,
    `PhotoPick savePickerUriToSandboxFiles originalExt=${originalExt} packing.format=${packing.format} packing.outputExt=${packing.outputExt} srcFileSize=${srcFileSize} shouldCompress=${shouldCompress}`);

  let target = buildTargetPaths(targetDir, dirName, shouldCompress ? packing.outputExt : originalExt);
  let didCompress = false;
  let compressedSize = 0;
  if (shouldCompress) {
    try {
      // 传递格式，质量会在 compressImageToFile 内部动态计算
      const compressionPacking: CompressionPacking = {
        format: packing.format,
        quality: DEFAULT_COMPRESS_QUALITY  // 初始值，会被函数内部覆盖
      };
      compressedSize = await compressImageToFile(srcUri, target.absPath, compressionPacking);
      didCompress = true;
      hilog.info(0x0000, TAG,
        `PhotoPick savePickerUriToSandboxFiles compressed srcBytes=${srcFileSize} outputBytes=${compressedSize} relPath=${target.relPath}`);
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      hilog.warn(0x0000, TAG,
        `PhotoPick savePickerUriToSandboxFiles compress failed, fallback to copy relPath=${target.relPath} err=${errMsg}`);
      try {
        fs.unlinkSync(target.absPath);
      } catch (_unlinkErr) {
        // ignore unlink failure
      }
      if (packing.outputExt !== originalExt) {
        target = buildTargetPaths(targetDir, dirName, originalExt);
      }
    }
  }

  if (!didCompress) {
    const bytesCopied = copyFileToPath(srcUri, target.absPath, TAG);
    hilog.info(0x0000, TAG,
      `PhotoPick savePickerUriToSandboxFiles copy done bytes=${bytesCopied} relPath=${target.relPath}`);
  }

  const imageUri = fileUri.getUriFromPath(target.absPath);
  hilog.info(0x0000, TAG, `PhotoPick savePickerUriToSandboxFiles done imageUri=${imageUri} relPath=${target.relPath}`);
  const result: SandboxMediaCopyResult = {
    relPath: target.relPath,
    absPath: target.absPath,
    imageUri
  };
  return result;
}

export function relPathToImageUri(ctx: FilesDirCarrier, relPath: string): string | null {
  if (!relPath || relPath.trim().length === 0) {
    return null;
  }

  const absPath = normalizeStoredPath(ctx, relPath);
  if (!absPath) {
    return null;
  }
  try {
    fs.statSync(absPath);
  } catch (_err) {
    hilog.warn(0x0000, TAG, `PhotoPick relPathToImageUri missing file relPath=${relPath} absPath=${absPath}`);
    return null;
  }
  return fileUri.getUriFromPath(absPath);
}

export function deleteStoredFileBestEffort(ctx: FilesDirCarrier, storedPath: string): boolean {
  if (!storedPath || storedPath.trim().length === 0) {
    return true;
  }
  const absPath = normalizeStoredPath(ctx, storedPath);
  if (!absPath) {
    return false;
  }
  try {
    fs.unlinkSync(absPath);
    hilog.info(0x0000, TAG, `PhotoPick deleteStoredFileBestEffort ok storedPath=${storedPath}`);
    return true;
  } catch (_err) {
    hilog.warn(0x0000, TAG, `PhotoPick deleteStoredFileBestEffort failed storedPath=${storedPath}`);
    return false;
  }
}
