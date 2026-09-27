# MovieInfoEdit Agent Handoff

更新时间：2026-09-28

## 常用选项、片长获取与提交（2026-09-28）

- 年份、国家/地区、分级、演员角色新增常用选项菜单，保留手动输入。
- 片长使用 AVFoundation 异步一键读取；支持逐片批量读取、草稿恢复、入队逐片应用、取消及错误保护。
- `NFOData.runtimeByVideoID` 为可选字段，兼容旧会话；队列快照生成前调用 `resolvingRuntime(for:)`。
- 统一编辑器标签/输入/操作三列，基础与扩展字段、类型、演员行使用同一布局。
- macOS 27 SDK Debug 构建通过，80 项核心断言通过；包含本地 PCM 时长读取验证。完整 UI 与真实格式/外接盘测试按用户要求留给用户。
- 用户要求 commit/push；远端 `origin` 为 `https://github.com/kGMia/MediaInfoEdit`。本轮提交包含此前累积项目功能，排除本机 `xcuserdata` 设置。

## 字段与原生界面更新（2026-09-28）

本轮新增 13 个可编辑字段，并接入读取、批量编辑、草稿、写入预览/撤销和 Finder Quick Look。编辑器改为原生分组 Form，侧栏改用系统搜索；图片通过 ImageIO 在独立 actor 上生成 512 像素缩略图，移除 View body 中的文件读取，限制缓存并取消过期选择任务。导入使用 Set 去重和一次性列表追加。

Debug 构建和深度签名校验通过，71 项回归断言通过。构建目录 `/tmp/MovieInfoEdit-metadata-native`。

详细范围、兼容策略和用户验收见 [METADATA_AND_NATIVE_UI.md](METADATA_AND_NATIVE_UI.md)。新增代码均放入已注册源文件，无新增 Target 文件依赖。

## 源码注册修复（2026-09-26）

用户反馈 ContentView 中大量 `Cannot find ... in scope`。磁盘上的实现完整，但 Xcode 的构建与索引文件列表存在新旧差异。已将主应用目录从 `PBXFileSystemSynchronizedRootGroup` 改为常规 `PBXGroup`，在主 Target 中显式注册全部 12 个 Swift 源文件与 Assets/字符串资源。Quick Look 保持独立的 2 个源文件和嵌入关系。后续新增源文件需要显式加入对应 Target 的 Compile Sources。

在全新 `/tmp/MovieInfoEdit-explicit-sources` 目录完成 Debug 构建和签名，`BUILD SUCCEEDED`。如果已打开的 Xcode 仍显示旧诊断，重新打开 `MovieInfoEdit.xcodeproj`，执行 Clean Build Folder 后重新构建。

## 最新功能更新

已实现写入预览/撤销/备份恢复、会话持久化、媒体库筛选及 Finder NFO Quick Look 扩展。最新入口、结构与验收以 [FEATURES_AND_QUICKLOOK.md](FEATURES_AND_QUICKLOOK.md) 为准。新构建目录 `/tmp/MovieInfoEdit-features`；49 项核心回归断言通过，完整 Finder/UI/外接盘验收按用户要求交给用户。

新增目标 `NFOQuickLook`（应用扩展）由主 App 依赖并嵌入 `Contents/PlugIns`；纯预览解析器位于 `Shared/NFOPreviewDocument.swift`。`WritePlan`/`NFOStore` 分离准备与提交，`SessionStore`/`SessionState` 持久化会话及撤销历史，`LibraryReview`/`LibraryReviewState` 负责检查。


## 后续适配更新（2026-09-26）

本轮已完成 macOS 27 SDK/工具栏适配及进一步的文件/NFO/队列修复。以下旧章节记录的是本轮开始前的状态；最新实现、验证范围、用户验收和功能建议以 [MACOS27_ADAPTATION.md](MACOS27_ADAPTATION.md) 为准。

- 本机工具链：Xcode 27.0（27A266a）、macOS 27 SDK；最低系统仍为 macOS 26.0。
- 新增 `Models.swift`、`MediaFiles.swift`、`NFOStore.swift`、`ScopedQuickLook.swift`，相关模型、授权、NFO 解析已从 ContentView 拆出。
- Debug/Release 编译签名成功。Release 显式关闭自动注入基础 entitlements，已确认最终签名不含 `get-task-allow`；Debug 保留。
- 本轮构建目录为 `/tmp/MovieInfoEdit-macOS27`，无需清理源文件扩展属性。
- 新增 `.gitignore`、`Tests/MediaFileRegression.swift`、`scripts/test-media.sh`；29 项文件/NFO 回归断言通过。
- 用户明确要求无需完整测试：真实外接盘、Xcode 调试附加、macOS 26 运行时和完整 UI 验收交给用户，详见适配文档。


## 项目概况

这是一个 macOS SwiftUI 应用，主目标是批量编辑/生成视频旁边的 `.nfo` 元数据文件，并管理本地封面、背景图等媒体资料。

主要源码集中在：

- `MovieInfoEdit/ContentView.swift`
- `MovieInfoEdit/MovieInfoEditApp.swift`
- `MovieInfoEdit/Localizable.xcstrings`
- `MovieInfoEdit.xcodeproj/project.pbxproj`

当前项目最低部署目标为 macOS 26.0，使用 Swift 6、SwiftUI、Observation (`@Observable`)、AVFoundation、Vision、AppKit、QuickLook。

## 用户原始问题

用户反馈：

1. App 在本地独立运行时，不是从 Xcode 内运行，会无法显示封面预览。
2. 无法自动读取已有 `.nfo` 文件。
3. 这些文件来自外接硬盘。
4. 后续又反馈 Xcode 启动时报错：`Could not attach to pid : “76228”`。

## 当前未提交改动

请先运行：

```bash
git status --short
```

当前预期会看到：

```text
 M MovieInfoEdit.xcodeproj/project.pbxproj
 M MovieInfoEdit/ContentView.swift
 M MovieInfoEdit/Localizable.xcstrings
?? MovieInfoEdit/MovieInfoEdit.entitlements
?? MovieInfoEdit/MovieInfoEditDebug.entitlements
```

## 已做修复

### 1. 外接盘和沙盒访问

在 `ContentView.swift` 中重写/扩展了 `SandboxAccessManager`：

- 新增 `SecurityScopedBookmarks` 存储 key。
- 兼容旧的 `DirectoryBookmarks`。
- 同时支持文件、目录、最近的已授权父目录。
- 新增 `startAccessingFileAndParent(for:)`，用于同时尝试访问视频文件本身和父目录。
- 所有关键读取路径改为先打开 security-scoped access：
  - 视频缩略图读取
  - OCR
  - 智能封面提取
  - 本地图片读取
  - 队列处理时复制海报/fanart

这是为了解决：用户只选择外接盘上的单个视频文件时，App 可能只拿到该文件访问权，无法读取同目录 `.nfo` / 图片。

### 2. 导入文件夹支持

`SidebarView` 的文件导入器已从：

```swift
allowedContentTypes: [.audiovisualContent]
```

改为：

```swift
allowedContentTypes: [.audiovisualContent, .folder]
```

`AppState.importFiles(urls:)` 现在支持目录递归扫描视频。

### 3. 父目录授权兜底

如果用户只导入单个视频文件，代码会检测父目录是否可读；不可读时弹出 `NSOpenPanel`，请用户授权该媒体文件夹。

相关字符串：

- `Grant Folder Access`
- `Grant Access`
- `Grant access to this media folder so MovieInfoEdit can read existing .nfo files and artwork next to the selected videos.`

这些已补进 `MovieInfoEdit/Localizable.xcstrings`，包含 en/fr/ja/zh-Hans/zh-Hant。

### 4. 更宽容的 NFO 自动发现

新增 `findExistingNFOURL(for:)`，现在不只查找 `视频同名.nfo`，还支持：

- `视频同名.nfo`
- `movie.nfo`
- 文件名包含视频 baseName 的 `.nfo`
- 单视频目录里的唯一 `.nfo`

`parseExistingNFO(for:)` 也扩展了字段读取：

- `title` / `originaltitle`
- `year`
- `country`
- `studio`
- `premiered` / `releasedate` / `dateadded`
- `director`
- `plot` / `outline`
- `userrating` / `rating` / `<ratings><rating><value>`
- `genre`
- `actor/name`
- `actor/role`
- `<thumb aspect="poster">`
- `<fanart><thumb>...</thumb></fanart>`

### 5. 更宽容的本地封面/fanart 识别

新增 `discoverLocalArtwork(for:)` 和相关 rank 规则。当前支持的常见命名包括：

- `视频名-poster.jpg`
- `视频名_poster.jpg`
- `视频名.poster.jpg`
- `poster.jpg`
- `cover.jpg`
- `folder.jpg`
- `视频名.jpg`
- `视频名-fanart.jpg`
- `视频名_fanart.jpg`
- `fanart.jpg`
- `backdrop.jpg`
- `background.jpg`
- `landscape.jpg`

支持图片扩展名：

```text
jpg, jpeg, png, webp, tif, tiff, heic
```

### 6. Debug attach pid 修复

用户后续反馈 Xcode 启动失败：

```text
Could not attach to pid : “76228”
```

原因判断：新增显式 entitlements 后，Debug 配置缺少 `com.apple.security.get-task-allow`，导致 Xcode 无法附加调试器。

当前修复：

- 新增 `MovieInfoEdit/MovieInfoEdit.entitlements`
  - 用于 Release
  - 包含 sandbox、app-scope bookmarks、user-selected read-write
- 新增 `MovieInfoEdit/MovieInfoEditDebug.entitlements`
  - 用于 Debug
  - 在 Release 权限基础上额外包含：

```xml
<key>com.apple.security.get-task-allow</key>
<true/>
```

`project.pbxproj` 中当前配置：

```text
Debug   -> MovieInfoEdit/MovieInfoEditDebug.entitlements
Release -> MovieInfoEdit/MovieInfoEdit.entitlements
```

## 已验证内容

源码编译已通过：

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project MovieInfoEdit.xcodeproj \
  -scheme MovieInfoEdit \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

注意：在当前 Codex 沙盒内，如果不使用 `require_escalated`，Swift 宏插件可能会失败，典型报错类似：

```text
external macro implementation type 'ObservationMacros.ObservableMacro' could not be found
sandbox-exec: sandbox_apply: Operation not permitted
```

所以构建验证建议在非沙盒环境或 Xcode 内运行。

## 已知问题 / 注意事项

### 1. 真签名构建曾暴露扩展属性问题

曾尝试运行真实签名构建：

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project MovieInfoEdit.xcodeproj \
  -scheme MovieInfoEdit \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  build
```

它确认了 Debug entitlements 里有：

```text
"com.apple.security.get-task-allow" = 1
```

但 codesign 阶段曾失败：

```text
resource fork, Finder information, or similar detritus not allowed
```

检测到源码树/生成 app 中存在一些 macOS 扩展属性，例如：

- `com.apple.FinderInfo`
- `com.apple.fileprovider.fpfs#P`
- `com.apple.provenance`
- `com.apple.quarantine`
- `com.apple.macl`

接手 Agent 如果需要彻底修真实签名，可考虑清理相关扩展属性。请谨慎执行，避免破坏用户文件。优先检查：

```bash
xattr -lr MovieInfoEdit MovieInfoEdit.xcodeproj
```

常见清理命令示例：

```bash
xattr -cr MovieInfoEdit MovieInfoEdit.xcodeproj
```

如果要执行这类命令，应先向用户说明它会移除扩展属性。

### 2. `.build/` 是临时构建产物

验证时多次生成 `.build/`，已清理。仓库当前没有 `.gitignore`。如再次生成 `.build/`，不要提交。

### 3. `.DS_Store` 已存在但被忽略

工作区中可见一些被 Git 忽略的 `.DS_Store` 和 Xcode 用户状态文件。不要动它们，除非用户要求清理。

### 4. `ContentView.swift` 仍然很大

此次修复为了控制风险，没有拆分文件或大规模重构 UI。`ContentView.swift` 当前包含大量模型、状态、UI 组件和文件逻辑。后续可考虑分拆：

- `SandboxAccessManager.swift`
- `LocalArtworkResolver.swift`
- `NFOParser.swift`
- `AppState.swift`
- UI component files

但这不是当前修复必需项。

## 推荐下一步

1. 在 Xcode 中执行 `Product > Clean Build Folder`。
2. 运行 Debug scheme，确认不再出现 `Could not attach to pid`。
3. 使用外接硬盘上的真实媒体目录测试：
   - 导入单个视频文件。
   - 如弹出授权面板，选择该视频所在文件夹。
   - 选择视频后确认：
     - header 缩略图显示。
     - Gallery 中显示本地 poster/fanart。
     - 已有 `.nfo` 字段自动填入。
4. 再测试导入整个文件夹，确认递归导入和本地资源读取都正常。
5. 如果 Xcode 真签名仍因扩展属性失败，再处理 `xattr` 问题。

## 关键文件索引

- `MovieInfoEdit/ContentView.swift`
  - `SandboxAccessManager`
  - `discoverLocalArtwork(for:)`
  - `findExistingNFOURL(for:)`
  - `parseExistingNFO(for:)`
  - `AppState.importFiles(urls:)`
  - `SidebarView.fileImporter`
- `MovieInfoEdit/MovieInfoEdit.entitlements`
  - Release entitlements
- `MovieInfoEdit/MovieInfoEditDebug.entitlements`
  - Debug entitlements with `get-task-allow`
- `MovieInfoEdit/Localizable.xcstrings`
  - 新增文件夹授权弹窗本地化
- `MovieInfoEdit.xcodeproj/project.pbxproj`
  - Debug/Release entitlements 配置
