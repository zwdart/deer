# 版本更新功能说明

本文档说明 deer 的版本检查、平台安装包选择、下载与跳转逻辑，以及如何把默认的 GitHub Releases 接口替换成自己的更新服务器。

## 1. 功能概览

- 从发布服务器读取 JSON 版本信息。
- 使用 `package_info_plus` 读取本机版本，与服务器版本做语义化比较。
- 根据当前平台选择对应的安装包。
- 支持三种操作：
  - 应用内直接下载安装包；
  - 复制下载链接；
  - 在系统浏览器中打开下载页面。
- 下载完成后可直接打开安装包；iOS 会打开系统分享面板。
- 所有界面文案支持中英文（`assets/en.tsv`）。
- 默认数据源：`https://api.github.com/repos/zwdart/deer/releases/latest`。

## 2. 代码结构

| 文件 | 作用 |
| --- | --- |
| `lib/services/update/update_platform.dart` | 平台枚举、当前平台识别、各平台扩展名和文件名提示 |
| `lib/services/update/update_models.dart` | 版本号、发布信息、资源、检查结果、JSON 解析器 |
| `lib/services/update/update_service.dart` | HTTP 请求、版本比较入口、平台资源选择、下载、打开安装包 |
| `lib/state/update_view_model.dart` | 更新状态机（检查/可用/下载中/完成/错误）、下载进度、复制/浏览器操作 |
| `lib/ui/dialogs/update_dialog.dart` | 更新对话框、平台按钮、进度显示 |
| `lib/ui/screens/settings_screen.dart` | “关于”区域中的“检查更新”入口 |
| `lib/app.dart` | 全局注册 `UpdateViewModel` |
| `test/update_service_test.dart` | 版本比较、JSON 解析、全平台资源选择测试 |

## 3. 版本比较规则

本机版本来自 `package_info_plus` 的 `version` 和 `buildNumber`。

支持的版本写法：

```text
1.2.3
v1.2.3
1.2.3+12
2.0.0-beta.1
```

比较顺序：

1. `major`、`minor`、`patch` 逐段按数字比较。
2. 如果两边都带构建号，再比较构建号。
3. 如果版本号相同，再比较预发布后缀：
   - `2.0.0-beta < 2.0.0-rc.1 < 2.0.0`
   - `beta.2 > beta.1`
4. 服务器没有构建号时不比较构建号，避免同等版本被误判为“有更新”。

只有服务器版本大于本机版本时，界面才显示“发现新版本”。

## 4. 默认数据源：GitHub Releases JSON

默认请求 GitHub 的 latest release 接口：

```http
GET https://api.github.com/repos/zwdart/deer/releases/latest
Accept: application/vnd.github+json
User-Agent: deer-updater
```

解析的字段：

| 标准字段 | 兼容字段 | 说明 |
| --- | --- | --- |
| `tag_name` | `version`、`tag` | 版本号，`v` 前缀会自动忽略 |
| `name` | `title`、`release_name` | 发布名称 |
| `body` | `notes`、`changelog`、`description` | 更新说明 |
| `html_url` | `release_url`、`releaseUrl`、`url` | 发布页面 |
| `published_at` | `publishedAt`、`date` | 发布时间 |
| `prerelease` | - | 是否预发布 |
| `assets[].name` | `filename`、`file_name` | 文件名 |
| `assets[].browser_download_url` | `download_url`、`url`、`href` | 下载地址 |
| `assets[].size` | `bytes`、`file_size` | 文件大小（字节） |
| `assets[].content_type` | `contentType`、`type` | MIME 类型 |

示例：

```json
{
  "tag_name": "v1.2.0",
  "name": "deer 1.2.0",
  "body": "修复若干问题，优化文件传输。",
  "html_url": "https://github.com/zwdart/deer/releases/tag/v1.2.0",
  "published_at": "2026-01-02T03:04:05Z",
  "prerelease": false,
  "assets": [
    {
      "name": "deer-linux-x64.tar.gz",
      "browser_download_url": "https://example.com/deer-linux-x64.tar.gz",
      "size": 12345678,
      "content_type": "application/gzip"
    }
  ]
}
```

## 5. 使用自己的更新服务器

### 5.1 修改地址

当前入口在 `lib/app.dart`：

```dart
ChangeNotifierProvider<UpdateViewModel>(
  create: (_) => UpdateViewModel(),
)
```

改为：

```dart
ChangeNotifierProvider<UpdateViewModel>(
  create: (_) => UpdateViewModel(
    service: UpdateService(
      feedUrl: 'https://updates.example.com/deer/latest',
      authorization: 'Bearer YOUR_TOKEN', // 可选
    ),
  ),
)
```

`UpdateService` 构造参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `feedUrl` | GitHub latest release API | 更新 JSON 地址 |
| `userAgent` | `deer-updater` | 请求 User-Agent |
| `authorization` | `null` | 可选鉴权头 |
| `timeout` | 15 秒 | 连接、响应和下载超时 |

### 5.2 服务器返回格式

自己的服务器可以直接返回 GitHub 兼容格式，也可以使用下面的简化格式：

```json
{
  "version": "1.3.0",
  "build": 13,
  "name": "deer 1.3.0",
  "notes": "新增自动更新说明文档。",
  "release_url": "https://updates.example.com/deer/1.3.0",
  "published_at": "2026-02-01T12:00:00Z",
  "assets": [
    {
      "name": "deer-android.apk",
      "download_url": "https://updates.example.com/files/deer-android.apk",
      "size": 43210000,
      "content_type": "application/vnd.android.package-archive"
    }
  ]
}
```

解析器也支持返回发布数组（如 GitHub `/releases`）。数组模式会优先选择第一条非草稿、非预发布版本。

### 5.3 建议的服务器字段

- `version`：必须，语义化版本号。
- `build`：可选，整数构建号。
- `notes`：更新说明，纯文本即可。
- `release_url`：发布页面，找不到平台安装包时使用。
- `assets`：各平台安装包列表。
- `assets[].name`：必须包含平台和架构信息，便于自动选择。
- `assets[].download_url`：必须是 HTTPS。
- `assets[].size`：建议提供，用于下载进度和大小展示。

## 6. 全平台安装包选择

选择逻辑在 `UpdateService.selectAsset`，调用方通过 `UpdatePlatform` 参数明确指定平台：

| 平台 | 扩展名优先级 | 典型文件名 | 下载后行为 |
| --- | --- | --- | --- |
| Android | `.apk` | `deer-android.apk` | 调用系统安装器；需要允许安装未知应用 |
| iOS | `.ipa`、`.zip` | `deer-ios-unsigned.zip` | 保存后打开系统分享面板，不直接安装 |
| macOS | `.dmg`、`.pkg`、`.zip` | `deer-macos.zip` | 用默认应用打开 DMG/PKG/压缩包 |
| Windows | `.exe`、`.msi`、`.zip` | `deer-windows-x64.zip` | 用默认应用打开安装器或压缩包 |
| Linux | `.AppImage`、`.deb`、`.rpm`、`.pkg.tar.zst`、`.tar.gz`、`.tar.xz`、`.zip` | `deer-linux-x64.tar.gz` | AppImage 会先 `chmod +x`，再打开；其他交给默认应用 |

评分规则：

1. 扩展名必须匹配当前平台。
2. 文件名包含平台关键字（如 `android`、`windows`、`macos`、`linux`、`ios`）会加分。
3. 文件名包含架构关键字（`x64`、`x86_64`、`amd64`、`arm64`、`aarch64`、`universal`）会加分。
4. 显式传入 `architecture` 时，匹配架构的包优先，其他架构降权；界面默认通过 `Abi.current()` 自动推断本机架构。
5. 包含 `debug`、`symbols`、`sha256`、`.sig`、`.txt` 的资源会被降权，避免误选校验文件。

CI 当前发布产物与上述命名一致：

```text
deer-android.apk
deer-ios-unsigned.zip
deer-macos.zip
deer-linux-x64.tar.gz
deer-windows-x64.zip
```

## 7. 下载行为

- 默认下载目录：
  - 桌面和可获取 Downloads 的平台：`<Downloads>/deer-updates`；
  - Android 回退到应用外部存储目录；
  - 再回退到应用文档目录。
- 文件名会做安全清洗，移除路径分隔符和 Windows 非法字符。
- 同名文件自动追加 ` (1)`、` (2)`，不会覆盖已有文件。
- 下载使用流式写入，每 256 KiB 更新一次进度。
- 下载失败会删除不完整文件。
- 下载完成后：
  - Android：`OpenFilex` 打开 APK 安装器；
  - iOS：`SharePlus` 打开分享面板；
  - macOS/Windows/Linux：交给系统默认应用打开；
  - Linux `.AppImage`：自动增加可执行权限。

## 8. 界面状态

`UpdateViewModel` 的状态：

```text
idle -> checking -> upToDate
                 -> available -> downloading -> downloaded
                 -> noAsset
                 -> error
```

- 检查中显示旋转进度。
- 有新版本时显示当前版本、最新版本、平台、发布日期、安装包名称和大小、更新说明。
- 下载中显示进度条和已下载/总大小。
- 下载完成显示保存路径，可直接打开或分享。
- 找不到当前平台安装包时，提示前往发布页面手动下载。
- 所有操作都不依赖 `setState`，状态通过 `ChangeNotifier` 通知界面。

## 9. 错误处理

- 网络超时、无法连接、HTTP 非 2xx、JSON 解析失败都会转成可读错误。
- GitHub 403 且包含 rate limit 时，提示频率受限。
- 404 时提示没有找到发布版本。
- 单个损坏的 asset 会被忽略，不会导致整个版本解析失败。
- 没有匹配安装包时不会崩溃，界面提供浏览器下载入口。

## 10. 安全建议

- 更新接口和下载地址必须使用 HTTPS。
- 建议在服务器端对安装包做代码签名，客户端后续可增加签名校验。
- 不建议在客户端硬编码长期有效的私有 Token；如需要鉴权，使用短期 Token 或公开只读接口。
- iOS 的未签名 `.zip` 无法直接安装，正式发布应使用 TestFlight/App Store 或企业签名。
- Android 安装 APK 需要用户授权“安装未知应用”。
- 桌面安装包应使用系统代码签名（Windows Authenticode、macOS notarization），减少安全提示。

## 11. 测试

```bash
flutter test test/update_service_test.dart
flutter test
flutter analyze
```

测试覆盖：

- 语义化版本比较、构建号、预发布版本。
- GitHub JSON 和自定义服务器 JSON 解析。
- 发布数组中选择稳定版本。
- Android、iOS、macOS、Windows、Linux 的安装包选择。
- 架构提示和 SHA256 等非安装包过滤。
- 无匹配平台资源时返回空。

## 12. 后续可扩展项

- 自动检查更新（启动后每天一次）。
- 下载完成后自动校验 SHA256/签名。
- 应用内静默下载与增量更新。
- 服务器下发强制更新标记和最低支持版本。
- 可配置的镜像/CDN 下载地址。
