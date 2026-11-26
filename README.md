# dchat

dchat 是一个局域网点对点聊天客户端，功能与 [`zchat`](../zchat-main) 对齐，聊天与文件传输协议完全兼容，可与 Go 版 mygo 客户端以及本 Flutter 客户端互通。

- 无需服务器，设备通过 UDP 组播/广播自动发现，聊天使用 TCP 直连。
- 支持文字、图片、文件、群聊、撤回、已读、输入状态、离线消息队列。
- 支持 TCP 直连文件传输、HTTP 回退下载、断点续传。
- 支持局域网文件共享（只读目录 + 可选上传目录、二维码、网页访问）。
- 支持本地 RSS/Atom 订阅：信息流阅读、卡片式订阅管理、文章详情排版，全部数据只存本机。
- 支持 Windows、Linux、macOS、Android、iOS。

## 平台支持

| 平台 | 界面习惯 | 说明 |
| --- | --- | --- |
| Windows / Linux | 侧边栏 + 菜单栏 + 右键菜单 + 键盘快捷键 + 系统托盘 | Enter 发送，Shift+Enter 换行 |
| macOS | Cupertino 风格操作表 + 菜单栏 + 托盘 + 快捷键 | Enter 发送，Shift+Enter 换行 |
| Android | Material 3、底部导航、FAB、底部操作表、长按菜单、拍照 | 自动申请通知与局域网权限 |
| iOS | Cupertino 底部导航、操作表、长按菜单、相册/相机 | 需要 `NSLocalNetworkUsageDescription` |

所有平台共用同一套协议、数据库和文件缓存；界面层根据平台选择 Material / Cupertino 组件与交互方式。

## 主要功能

### 设备发现与状态

- UDP 组播 + 定向广播 + 受限广播发现同一局域网设备。
- 显示名称、签名、头像、IP、聊天端口、传输端口、版本、平台。
- 在线、离开、忙碌、请勿打扰、隐身五种状态。
- 手动输入 `IP` 或 `IP:端口` 连接无法自动发现的设备。
- 本机备注、复制 IP、复制签名、移除设备。

### 聊天

- 文字、图片、文件消息；图片支持相册、拍照、拖放、剪贴板。
- 发送/接收进度、速度、TCP/HTTP 传输方式提示。
- 已发送 / 已送达 / 已读状态、正在输入提示、未读角标。
- 消息撤回（2 分钟内）、删除、复制、另存为、打开、分享。
- 会话置顶、免打扰、清空记录、删除会话、聊天记录搜索。
- 离线消息队列，对方上线后自动补发。
- 应用内截图，可保存、复制、分享或直接发送到当前会话。
- 使用期间保持屏幕常亮（可关闭）。

### 群聊

- 创建群聊、选择成员、改名、添加/移出成员。
- 群主解散、成员退出、群系统消息。
- 群消息逐成员单播，群操作同样支持离线队列。

### 文件与共享

- TCP 附件直连传输，失败自动回退 HTTP。
- `.part` 断点续传，完成后校验大小。
- 共享目录只读浏览、搜索、返回上级、二维码访问。
- 可选上传目录，访客网页上传，单次最大 8 GiB。
- 令牌持久化，发送方重启后旧消息仍可下载。

### 本地资讯（RSS）

- 直接抓取用户自己添加的 RSS 2.0 / RSS 1.0 / Atom / JSON Feed，没有服务器模式，订阅与文章全部存在本机 SQLite。
- 信息流按发布时间倒序分页加载，卡片只显示标题、摘要与出处；订阅源、收藏夹用卡片视图，未读数和同步错误直接显示在卡片上。
- 收藏夹可以分组管理订阅源，长按或右上角菜单进行二次操作，主界面只保留搜索、刷新、添加订阅三个按钮。
- 文章详情是新闻客户端式排版：封面、标题、出处标签、正文列宽与字号可调，图片单独渲染避免溢出。
- 抓取限制：单响应 4 MiB、15 秒超时、只允许 http/https，不跳过证书校验；批量同步并发 4，连续失败的源自动降频。
- OPML 2.0（含嵌套分组）与 CSV 导入导出，可自动备份订阅到本机备份目录，支持按天数清理历史文章。

### 版本更新

- 从 GitHub Releases JSON 检查最新版本，支持替换为自有更新服务器。
- 按 Windows / Linux / macOS / Android / iOS 分别选择安装包。
- 支持应用内直接下载、复制下载链接、浏览器打开。
- 详细配置与 JSON 格式见 [`docs/UPDATE.md`](docs/UPDATE.md)。

### 设置与数据

- 跟随系统 / 浅色 / 深色主题，切换立即生效。
- 跟随系统 / 简体中文 / English 国际化。
- 通知、通知预览、自动下载图片、触感反馈、常亮、截图开关。
- 聊天端口、传输端口、共享端口、自动发现开关。
- SQLite 聊天记录、数据库整理、清空记录。
- 资讯：自动同步与间隔、打开即已读、图片、字号、行距、正文宽度、文章保留天数、自动备份。
- 桌面端关闭窗口留在托盘、开机自动共享。设置改为独立页面，托盘与 `Ctrl/⌘+,` 均可打开。

## 架构

采用 MVVM + Provider：

```
lib/
  core/      模型、设置、数据库、路径、国际化、工具函数
  rss/       RSS/Atom/JSON Feed 抓取、解析、OPML 与 CSV 导入导出
  net/       帧协议、UDP 发现、TCP 连接、附件传输、HTTP 共享
  state/     ChatController + 各页面 ViewModel（ChangeNotifier）
  services/  桌面托盘/快捷键、移动端桥接、通知、常亮、截图、版本更新
  ui/        自适应组件、主题、页面与对话框
```

- 业务状态集中在 `ChatController`（`ChangeNotifier`），资讯独立为 `RssController`，各自的 SQLite 文件与设置互不影响。
- 页面状态使用 `HomeViewModel`、`ChatsViewModel`、`ChatViewModel` 等。
- 通过 `Provider` / `Selector` / `context.watch` 订阅，不使用 `setState`。
- 页面只负责布局与转发事件，网络、持久化、协议处理在 `state` / `net` 层。

## 协议兼容

dchat 实现 `zchat` 协议 `v=1`，与 Go 客户端完全互通：

- 发现：UDP `42223`，`app="zchat"`，4 秒心跳，16 秒超时。
- 聊天：TCP `42224`，行式 JSON 帧，最大 2 MiB。
- 附件：TCP `42225`，`token` + `offset` 请求，支持续传。
- HTTP 回退与共享：默认 `42230`，`Range` 下载，`/health` 探活。
- 帧类型：`hello`、`presence`、`bye`、`ping`、`pong`、`chat`、`ack`、`read`、`typing`、`recall`、`group`。

协议细节见 [`../zchat-main/docs/PROTOCOL.md`](../zchat-main/docs/PROTOCOL.md)。

## 开发

环境要求：Flutter 3.47.5+（Dart 3.13+）。

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux      # 或 windows / macos / android / ios
```

### 平台补充

- Linux 构建依赖：`clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libayatana-appindicator3-dev`。
- macOS / iOS 使用 Swift Package Manager；iOS 首次构建需要 Xcode。
- Android 使用 Java 17、minSdk 24；发布包默认使用 debug 签名，正式发布请配置自己的签名。
- iOS 真机运行需要配置开发团队；文件共享与本地网络权限已写入 `Info.plist`。

## 打包

```bash
flutter build linux --release     # build/linux/x64/release/bundle
flutter build windows --release   # build/windows/x64/runner/Release
flutter build macos --release     # build/macos/Build/Products/Release/dchat.app
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
flutter build apk --split-per-abi
flutter build ios --release --no-codesign
```

## CI 全平台打包

- `.github/workflows/ci.yml`：`analyze`、`test`，并构建 Android APK、iOS（未签名）、macOS、Linux、Windows 产物。
- `.github/workflows/release.yml`：推送 `v*` 标签时构建全部平台并上传到 GitHub Release。

```
git add pubspec.yaml
git commit -m "chore: release v1.0.0"
git push github master

git tag -a v1.0.0 -m "dchat v1.0.0"
git push github v1.0.0
```

产物命名：

| 平台 | 文件 |
| --- | --- |
| Android | `dchat-android.apk` |
| iOS | `dchat-ios-unsigned.zip` |
| macOS | `dchat-macos.zip` |
| Linux | `dchat-linux-x64.tar.gz` |
| Windows | `dchat-windows-x64.zip` |

## 数据目录

| 平台 | 位置 |
| --- | --- |
| Windows | `%APPDATA%\xin.dart.dchat` |
| macOS | `~/Library/Application Support/xin.dart.dchat` |
| Linux | `~/.local/share/xin.dart.dchat` |
| Android / iOS | 应用私有支持目录 |

下载目录默认为系统下载目录下的 `xin.dart.dchat`，截图保存在 Pictures 或下载目录。

资讯数据在同一目录下另存 `dchat_rss.db`（订阅、文章、收藏夹）与 `rss_settings.json`（阅读与同步偏好），OPML 备份写入 `rss_backups`，手动导出文件写入下载目录的 `rss`。

## 安全说明

协议默认运行在可信局域网，没有 TLS、签名或设备认证；附件令牌是 bearer token。请勿将 42224/42225/42230 暴露到公网，跨不可信网络请使用 VPN 或额外隧道。

资讯抓取只访问用户自己添加的 http/https 地址：单响应上限 4 MiB、15 秒超时、不跳过证书校验，重定向同样受限；正文按排版渲染文本与图片，链接交给系统浏览器打开。
