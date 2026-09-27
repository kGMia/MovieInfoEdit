# macOS 27 适配与验收

更新日期：2026-09-26。

后续已实现优先推荐的三项功能及 Finder NFO 预览，最新用法和验收见 [新功能与 Finder 预览](FEATURES_AND_QUICKLOOK.md)。下方适配验证记录保留前一轮状态。

## 适配范围

使用本机 Xcode 27.0（27A266a）、macOS 27.0 SDK 构建，最低部署版本保留 macOS 26.0。未将系统要求提高到 27。

- 使用系统统一工具栏、原生分段选择器、Liquid Glass 操作按钮与安全区布局，移除顶部悬浮切换控件、硬编码白色渐变和内容覆盖。
- macOS 27 使用 `ToolbarItemVisibilityPriority(higherThan: .high)` 保持导入操作的较高显示优先级；macOS 26 回退到普通工具栏项。
- 采用 SDK 27 的 SwiftUI `@State` 实现，保持 Observation 状态管理。没有使用仅在 iOS 提供的 `toolbarOverflowMenu` 等 API。
- 编辑器在查看队列时保持存活，保留未提交的表单；增加空状态说明、批量编辑提示，改善键盘可访问的图片选择按钮。
- 项目/Target 的部署版本统一为 26.0；Debug 与 Release 分离 entitlements。Release 设置 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`，防止开发签名自动注入 `get-task-allow`。

参考：[Apple SwiftUI 更新](https://developer.apple.com/swiftui/whats-new/)、[macOS 27 发布说明](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)。API 可用性同时依据本机 SDK 的 Swift interface 核实。

## 修复内容

- 导入时先取得 security-scoped access，再判断文件/目录；递归导入仅接受实际文件，暴露扫描错误。单文件导入需要授权时，检查选中的目录确实包含媒体，检查读写可用性，并提示失败。
- 封面、背景图、NFO 和 Quick Look 使用授权访问。视频缩略图无法提取时，可先显示本地海报；这不代表增加了 AVFoundation 原本不支持的视频解码器。
- `*-fanart` 不再误归类为海报；文件名匹配使用分隔符边界，减少多影片目录中串图的情况。
- NFO 支持大小写扩展名；`movie.nfo`、模糊名称和唯一 NFO 回退只用于单视频目录，避免多视频目录中串片。
- 写入已有 NFO 时保留未在表单展示的节点，例如 provider IDs、自定义字段、演员图片。图片文件名交由 XML API 转义；复制图片保留原扩展名。
- 首次覆盖已有 NFO 前，保存 `<原文件名>.nfo.bak`；已有备份不覆盖。非重命名操作更新找到的原 NFO。重命名时生成新同名 NFO，旧 NFO 保留。
- 写入前验证文件名、源图片及目标冲突；按文件原子写入。失败时尝试恢复本次已改动的文件和视频名称；若恢复失败，队列显示具体错误。多文件操作无法保证断电级事务原子性。
- 批量编辑只应用相对初始表单实际变化的字段，保留各影片不同的标题、剧情、评分、封面等。字段从初始非空值改为空可清空该字段；初始为空的混合字段目前不能通过再次留空表达“全部清空”。
- 队列防止重复启动，按任务 ID 更新状态；重复加入尚未处理的视频会更新待处理快照。错误不再显示为成功，支持将失败项重置为待处理后重新生成。
- 智能封面先暂存于应用临时目录，生成 NFO 时才复制到媒体目录；取消海报选择不删除原媒体文件。跨影片切换时取消过期 OCR/封面任务，避免结果写入另一影片。
- NFO 中不在预设列表内的年份、地区可以正常显示。

## 已做的有限验证

按用户要求未执行完整端到端测试。

- Debug 和 Release：Xcode 27 编译和开发证书签名通过。
- Release：`codesign --verify --deep --strict` 通过；最终签名不含 `get-task-allow`。Debug 保留该权限。
- `scripts/test-media.sh`：29 项回归断言通过，涉及封面分类、NFO 自动发现/解析、批量字段保留、XML 转义、额外节点保留、备份、图片扩展名、无效文件名、重命名冲突、缺失图片失败保护及损坏 NFO 保护。
- 独立启动 Release，确认工具栏与空状态出现。尚未实际验证外接盘、Xcode debugger attach、macOS 26 运行时或完整浅色/深色布局。
- 在 `/tmp/MovieInfoEdit-macOS27` 构建签名成功，没有清除源文件扩展属性；原交接记录的 Finder 扩展属性问题在该构建路径未复现。
- 回归脚本在 Codex 沙盒内会输出 bookmark extension 权限提示，因此该脚本不代替真实沙盒授权验收。

## 请用户完成的验收

建议先用一个复制出的媒体目录，包含两部具有不同标题、剧情和封面的影片。

1. 在 Xcode 打开 `MovieInfoEdit.xcodeproj`，选择 Debug 运行，确认不再出现 `Could not attach to pid`。
2. 退出 Xcode 启动的进程，从 Finder 打开本次构建的 App。导入外接盘上的单个视频，按提示选择所在文件夹；确认 NFO 自动填入、海报和背景图显示、空格 Quick Look 可用。再退出/重开并重新导入，检查书签授权。
3. 导入整个媒体目录，检查子目录影片均出现，多影片目录不会共享错误的 `movie.nfo`。拔盘后尝试生成，确认队列显示错误而非成功；重新接盘并重试。
4. 多选两部影片只修改片厂，生成后确认各自标题/剧情/评分/封面保留。检查原 NFO 备份与额外 ID 节点。用无效文件名或重名目标检查失败提示和原文件保留。
5. 在浅色/深色外观、不同窗口大小下检查工具栏与表单。编辑后切换到队列再返回，确认内容保留；提取封面/OCR 时切换影片，确认结果不会串片。

## 后续功能计划与状态

| 优先级 | 功能 | 价值与范围 |
| --- | --- | --- |
| 已实现 | 写入预览与撤销 | 逐影片差异、重命名/图片目标、持久撤销记录、NFO 备份恢复。 |
| 已实现 | 工作会话恢复 | 导入列表、草稿、队列、选择与提取图片持久化，恢复书签，离线任务保留。 |
| 已实现 | 媒体库检查与筛选 | 文件名搜索、缺失信息/无效 NFO/离线/目标冲突筛选。 |
| P2 | 视频帧时间轴 | 拖动时间轴选封面，预览 2:3 裁切，支持无脸画面；明确提示不支持的容器/编码。 |
| P3 | 可选在线元数据匹配 | 按片名/年份候选匹配，逐字段确认写入；需另行设计来源、凭据和网络权限，默认仍可离线使用。 |

## 开发验证命令

```sh
# 当前机器 xcode-select 指向 CommandLineTools，因此显式指定 Xcode。
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MovieInfoEdit.xcodeproj -scheme MovieInfoEdit \
  -configuration Debug -derivedDataPath /tmp/MovieInfoEdit-macOS27 build

scripts/test-media.sh
```

若在受限沙盒中遇到 SwiftUI/Observation 宏插件加载失败，请在正常终端或 Xcode 内构建。不要通过禁用 App Sandbox 规避授权问题。
