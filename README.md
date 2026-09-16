# FlowDiary

FlowDiary 是一个采用 HarmonyOS Stage 模型与 ArkTS 构建的个人日常记录应用。它围绕「计划、记录、回顾」组织体验：把当天事项和专注计时放在一起，用灵感池收集零散想法，再通过回顾图表观察时间与标签的变化。

## 功能概览

- 今日事项、计时记录与快捷启动项
- 灵感收集、整理与轻量回顾
- 日、周维度的时间和标签统计图表
- 标签管理、日历同步、数据备份与恢复
- 桌面卡片和计时实况窗能力
- 面向手机及不同屏幕尺寸的响应式 ArkUI 布局

## 工程结构

| 路径 | 用途 |
| --- | --- |
| `products/phone/` | 可安装、可运行的手机入口模块 `phone` |
| `features/today/` | 今日事项、计时、设置与实况窗功能 |
| `features/ideapool/` | 灵感池功能 |
| `features/reflect/` | 回顾与图表功能 |
| `common/base/` | 跨功能模块的数据、工具与通用 UI |
| `AppScope/` | 应用级配置与资源 |

## 环境要求

- HarmonyOS SDK API 23，即 `6.1.0(23)`；项目的 `targetSdkVersion` 和 `compatibleSdkVersion` 均为该版本。
- 安装包含该 SDK 的 DevEco Studio，或安装 HarmonyOS Command Line Tools 并使 `devecocli` 可用。
- 用于安装运行的 HarmonyOS 真机，或已创建并启动的兼容模拟器。
- 首次生成调试签名时，需要登录自己的华为开发者账号；不要使用、索取或提交他人的签名材料。

DevEco Studio 的图形界面和 DevEco CLI 都可以使用。下面的命令从项目根目录执行。

## 从克隆到启动

### 1. 克隆并安装依赖

```bash
git clone <fork-url>
cd FlowDiary
ohpm install
```

也可以直接用 DevEco Studio 打开项目根目录，等待 OHPM 依赖同步完成。`oh-package-lock.json5` 已包含，首次 `devecocli build` 或 `devecocli run` 也会触发依赖安装。

### 2. 配置自己的应用标识

如果你只是本地体验，可以先保留现有标识。发布 fork、接入自己的云服务或创建自己的签名 profile 前，必须改为唯一的 bundle name，例如 `com.example.flowdiary`。

至少同步检查以下位置：

- `AppScope/app.json5` 中的 `app.bundleName`
- 根目录 `build-profile.json5` 的 capability 配置中的 `bundleName`
- 任何与你自己的签名 profile、云能力或发布配置相关的 bundle name

更换 bundle name 后，必须重新生成与新标识匹配的签名和 profile；旧 profile 不能复用。

### 3. 生成本地调试签名

公开仓库刻意不含证书、profile、私钥、口令或已有签名配置。没有自己的签名时可以检查源码和构建流程，但不能把应用安装到设备或模拟器。

任选一种方式生成**仅属于你自己的**调试签名：

1. 在 DevEco Studio 打开 **File > Project Structure > Signing Configs**，按照界面提示创建或选择自己的调试证书与 profile，并将它关联到 `default` product 的 debug 构建。
2. 使用 CLI：先执行 `devecocli auth login`，连接或启动一个设备/模拟器，再执行：

   ```bash
   devecocli signature generate --product default
   ```

   该命令会在你的本机生成签名材料，并更新本地的 `build-profile.json5`。这些变更和生成的文件都只应保留在你的本机，绝不能提交、复制到 issue，或上传到公开仓库。

若签名更换后安装报“签名信息不一致”，可在下一次运行时使用 `--uninstall`，让设备先卸载旧包。

### 4. 连接或启动运行目标

查看当前可用的真机和模拟器：

```bash
devecocli device list
devecocli emulator list
```

若已在 DevEco Studio 的 Device Manager 中创建模拟器，可启动它：

```bash
devecocli emulator start "<模拟器名称>"
```

模拟器管理要求较新的 DevEco Studio（6.1.0 或更高）。没有设备时，请先在 Device Manager 创建与项目 SDK 兼容的模拟器；首次下载系统镜像时，按工具提示接受许可协议。

### 5. 构建并启动

先进行只构建验证：

```bash
devecocli build --product default --build-mode debug
```

在只有一个运行目标时，构建、安装并启动 `phone` 入口模块：

```bash
devecocli run --module phone --product default --build-mode debug
```

有多个目标时，显式选择设备或模拟器序列号：

```bash
devecocli run --module phone --product default --build-mode debug --device <serial>
```

需要清除设备上的旧数据和旧签名包时：

```bash
devecocli run --module phone --product default --build-mode debug --device <serial> --uninstall
```

在 DevEco Studio 中，选择 `phone` 作为运行模块、选择你的设备或模拟器，然后点击 Run。默认 Ability 由 `products/phone/src/main/module.json5` 中的 `mainElement` 指定。

## 日常开发命令

```bash
# ArkTS / TypeScript 静态检查
devecocli check lint

# 清理本地构建产物和停止 Hvigor daemon
devecocli build clean

# 查看崩溃日志；将 bundle name 替换为你自己的标识
devecocli log --crash --bundle-name <your.bundle.name>
```

对于一次完整的首次部署，优先使用 `devecocli run`。它成功后，符合条件的少量 ArkTS 修改可使用 `devecocli run --apply <变更列表文件>` 加快迭代；资源、状态装饰器、feature/HSP 模块变更则应回到完整运行流程。

## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| 找不到 SDK 或构建失败 | 在 DevEco Studio 的 SDK Manager 安装 API 23（`6.1.0(23)`），并确认 CLI 使用同一套 SDK。 |
| 没有活动设备 | 使用 `devecocli device list` 和 `devecocli emulator list` 检查；连接真机或启动已创建的模拟器。 |
| 无法安装或提示没有 signingConfig | 先完成“生成本地调试签名”，再以 debug 模式运行。 |
| 安装时签名不一致 | 使用 `devecocli run ... --uninstall`，或重新生成自己的调试签名。 |
| Product 或 build mode 不存在 | 检查根目录 `build-profile.json5`，本项目使用 product `default`。 |

## 隐私与安全

此源码仓库不含用户数据、照片、调试截图、证书、profile、私钥、口令或其他签名材料。仅保留应用运行所需的图标和插画资源。请将自己的签名文件、本机路径和任何凭据保留在本地，不要提交到 fork。

## License

本项目采用 [PolyForm Noncommercial License 1.0.0](LICENSE)：允许个人学习、个人部署、兴趣项目与其他非商业用途；商业使用、商业分发、收费托管或利用本项目获取商业收益，必须先取得版权方的单独书面许可。本项目为 source-available，并非 OSI 定义的开源软件。
