# macOS 多窗格文件管理器开发计划书

## 0. 项目说明

本计划书用于交给 AI 编程助手、AI Agent 或开发团队直接执行。目标是开发一款 macOS 端多窗格文件管理器，功能方向参考 QSpace、Path Finder、Finder 增强工具，但必须保持独立产品设计，不复制任何第三方应用的品牌、界面、图标、文案、布局细节或专有命名。

项目暂定名称：**Clover**

目标平台：macOS 15+

开发语言：Swift

技术栈：AppKit

最低系统要求：macOS 15+

核心目标：

- 提供比 Finder 更高效的多窗格文件管理体验。
- 支持多个目录同时查看、拖拽、复制、移动、对比。
- 支持工作区保存和恢复。
- 后续扩展远程连接、批量重命名、文件夹同步、压缩包浏览、暂存架等高级能力。

---

# 1. 给 AI 的总执行指令

下面这段可以直接复制给 AI 编程助手作为总 Prompt：

```text
你是一个资深 macOS Swift/AppKit 开发工程师。请帮我开发一款 macOS 多窗格文件管理器，项目名为 Clover。

要求：
1. 使用 Swift 开发。
2. UI 使用 AppKit，不使用 SwiftUI。
3. 第一阶段只做本地文件管理，不做远程连接和云盘。
4. 核心功能包括：多窗格布局、文件列表、地址栏、基础文件操作、拖拽复制移动、工作区保存恢复、当前目录搜索、Quick Look 预览。
5. 代码必须模块化，不能把逻辑都堆在 ViewController 里。
6. 文件系统操作必须通过 FileProvider 抽象层，不允许 UI 层直接操作 FileManager。
7. 所有耗时操作必须异步执行，不能阻塞主线程。
8. 文件访问要考虑 macOS 沙盒和 security-scoped bookmark，虽然第一版可以先不强制上架 App Store，但架构要预留。
9. 所有功能必须有清晰的验收标准。
10. 不要复制 QSpace 或其他产品的 UI、图标、品牌和文案，只参考功能类型。

请先搭建项目架构，然后按阶段逐步实现。每完成一个阶段，请给出已完成文件清单、关键代码说明、运行方式和下一步计划。
```

---

# 2. 产品范围

## 2.1 第一版目标

第一版目标是做出一个可运行、可日常试用的本地文件管理器。

必须完成：

1. 主窗口
2. 多窗格布局
3. 本地文件浏览
4. 列表视图
5. 图标视图基础版
6. 地址栏
7. 文件复制
8. 文件移动
9. 文件重命名
10. 新建文件夹
11. 放入废纸篓
12. 窗格间拖拽
13. 工作区保存和恢复
14. 当前目录搜索
15. Quick Look 预览
16. 基础右键菜单
17. 基础快捷键

第一版不做：

1. 远程连接
2. 云盘
3. 压缩包内部浏览
4. 文件夹同步
5. 高级批量重命名
6. 插件系统
7. 多设备同步
8. 付费系统

---

# 3. 产品功能模块

## 3.1 主窗口模块

### 功能说明

应用启动后打开一个主窗口。主窗口内包含工具栏、侧边栏、多窗格区域、状态栏。

### UI 结构

```text
MainWindowController
├── Toolbar
├── RootSplitViewController
│   ├── SidebarViewController
│   └── WorkspaceViewController
│       ├── PaneLayoutController
│       │   ├── FilePaneViewController
│       │   ├── FilePaneViewController
│       │   └── FilePaneViewController ...
│       └── StatusBarView
```

### 实现要求

- 使用 `NSWindowController` 管理主窗口。
- 使用 `NSSplitViewController` 管理侧边栏和内容区域。
- 使用 `NSSplitViewController` 或自定义布局控制器管理多窗格。
- 当前激活窗格必须高亮显示。
- 所有快捷键默认作用于当前激活窗格。

### 验收标准

- 应用启动后可以显示主窗口。
- 主窗口可以调整大小。
- 侧边栏和文件区域可以拖动调整宽度。
- 当前激活窗格有明显视觉状态。

---

## 3.2 多窗格布局模块

### 功能说明

用户可以在一个窗口内切换不同窗格布局。

第一版支持：

1. 单窗格
2. 左右双窗格
3. 上下双窗格
4. 四宫格窗格

### 数据结构

```swift
enum PaneLayout: String, Codable, CaseIterable {
    case single
    case twoVertical
    case twoHorizontal
    case fourGrid
}
```

```swift
struct PaneState: Codable, Identifiable {
    var id: UUID
    var currentURLBookmark: Data?
    var currentPath: String
    var viewMode: FileViewMode
    var sortOption: SortOption
    var selectedFileNames: [String]
    var backHistory: [String]
    var forwardHistory: [String]
}
```

```swift
enum FileViewMode: String, Codable {
    case list
    case icon
}
```

### 实现要求

- `PaneLayoutController` 负责创建、销毁和重排窗格。
- 切换布局时尽量保留已有窗格状态。
- 如果从四宫格切到单窗格，优先保留当前激活窗格。
- 如果从单窗格切到多窗格，新窗格默认打开用户 Home 目录。
- 窗格之间可以拖拽文件。

### 验收标准

- 可以在四种布局之间切换。
- 切换布局不会导致应用崩溃。
- 每个窗格都可以独立打开不同目录。
- 当前激活窗格在切换后仍然合理保留。

---

## 3.3 文件浏览模块

### 功能说明

每个窗格可以显示当前目录下的文件和文件夹。

第一版支持：

1. 文件名
2. 图标
3. 类型
4. 大小
5. 修改时间
6. 是否文件夹
7. 是否隐藏文件

### 数据结构

```swift
struct FileItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let typeIdentifier: String?
    let isHidden: Bool
}
```

```swift
enum SortOption: String, Codable {
    case nameAscending
    case nameDescending
    case dateAscending
    case dateDescending
    case sizeAscending
    case sizeDescending
    case typeAscending
    case typeDescending
}
```

### 实现要求

- 使用 `URLResourceValues` 获取文件属性。
- 文件列表加载必须放在后台线程。
- UI 更新必须回到主线程。
- 大目录加载时要显示 loading 状态。
- 文件夹优先显示可以作为设置项预留。
- 默认不显示隐藏文件，但提供快捷键切换。

### 推荐类设计

```text
LocalFileProvider
FileListLoader
FileItemMapper
FileSortService
FilePaneViewModel
FilePaneViewController
```

### 验收标准

- 可以打开 Home、Desktop、Downloads、Documents 等目录。
- 文件名、图标、大小、修改时间显示正确。
- 打开大目录时 UI 不应明显卡死。
- 双击文件夹可以进入该文件夹。
- 双击普通文件可以用默认 App 打开。

---

## 3.4 FileProvider 抽象层

### 功能说明

所有文件来源都必须通过统一协议访问。第一版只实现本地文件系统，但架构要为远程连接和压缩包预留。

### 协议设计

```swift
protocol FileProvider {
    var providerID: String { get }
    var displayName: String { get }

    func listDirectory(at url: URL) async throws -> [FileItem]
    func createFolder(at parentURL: URL, name: String) async throws -> URL
    func renameItem(at url: URL, to newName: String) async throws -> URL
    func moveItems(_ urls: [URL], to destinationURL: URL) async throws
    func copyItems(_ urls: [URL], to destinationURL: URL) async throws
    func trashItems(_ urls: [URL]) async throws
    func deleteItemsPermanently(_ urls: [URL]) async throws
    func openItem(_ url: URL) async throws
}
```

### 第一版实现

```swift
final class LocalFileProvider: FileProvider {
    // 使用 FileManager、NSWorkspace、NSFileCoordinator 实现本地文件操作
}
```

### 实现要求

- UI 层不得直接调用 `FileManager.default` 做文件操作。
- 所有文件操作要统一走 `FileOperationService`。
- 后续远程文件、压缩包文件也要能接入同一套 UI。

### 验收标准

- 搜索项目代码，除 Provider 和底层 Service 外，UI 层不应直接出现复杂 FileManager 文件操作。
- 新增一个 MockFileProvider 后，理论上可以替换本地 provider 做 UI 测试。

---

## 3.5 地址栏模块

### 功能说明

每个窗格上方显示当前路径，支持面包屑导航和路径输入。

### 第一版功能

1. 显示当前路径。
2. 点击任意父级目录可跳转。
3. 支持 `Command + L` 进入路径输入模式。
4. 输入路径后回车跳转。
5. 支持 `~` 展开到用户 Home 目录。
6. 支持拖拽文件到路径节点进行复制或移动。

### 组件设计

```text
PathBarView
PathComponentView
PathInputField
PathResolver
```

### 路径解析规则

| 输入 | 解析结果 |
|---|---|
| `~` | 当前用户 Home 目录 |
| `~/Downloads` | Downloads 目录 |
| `/Applications` | Applications 目录 |
| 相对路径 | 基于当前目录解析 |

### 验收标准

- 地址栏能正确显示路径层级。
- 点击父级路径可以跳转。
- Command + L 可以输入路径。
- 输入不存在路径时显示错误提示，不崩溃。

---

## 3.6 文件操作模块

### 功能说明

实现基础文件操作。

第一版支持：

1. 复制
2. 移动
3. 重命名
4. 新建文件夹
5. 放入废纸篓
6. 永久删除，需二次确认
7. 复制文件路径
8. 在 Finder 中显示
9. 使用默认 App 打开

### 数据结构

```swift
enum FileOperationKind {
    case copy
    case move
    case rename
    case trash
    case deletePermanently
    case createFolder
}
```

```swift
struct FileOperationTask: Identifiable {
    var id: UUID
    var kind: FileOperationKind
    var sourceURLs: [URL]
    var destinationURL: URL?
    var progress: Progress
    var state: FileOperationState
}
```

```swift
enum FileOperationState {
    case pending
    case running
    case completed
    case failed(Error)
    case cancelled
}
```

### 实现要求

- 文件操作统一由 `FileOperationService` 执行。
- 复制和移动要支持多文件。
- 删除默认进入废纸篓。
- 永久删除必须二次确认。
- 文件冲突时显示选择弹窗：替换、跳过、保留两者、取消。
- 操作完成后刷新相关窗格。

### 文件冲突策略

```swift
enum FileConflictResolution {
    case replace
    case skip
    case keepBoth
    case cancel
    case applyToAll(FileConflictResolution)
}
```

### 验收标准

- 可以复制文件到另一个目录。
- 可以移动文件到另一个目录。
- 可以重命名单个文件。
- 可以新建文件夹。
- 可以放入废纸篓。
- 文件冲突不会直接覆盖，必须提示用户。

---

## 3.7 拖拽模块

### 功能说明

支持窗格内和窗格间拖拽。

### 第一版拖拽行为

| 场景 | 默认行为 |
|---|---|
| 同一磁盘拖拽 | 移动 |
| 跨磁盘拖拽 | 复制 |
| 按住 Option | 强制复制 |
| 按住 Command | 强制移动 |
| 拖到文件夹上 | 复制或移动到该文件夹 |
| 拖到另一个窗格空白区域 | 复制或移动到该窗格当前目录 |

### 实现要求

- 使用 AppKit drag and drop。
- `NSTableView` 和 `NSCollectionView` 都要支持拖拽。
- 拖拽目标高亮显示。
- 拖拽完成后刷新源窗格和目标窗格。

### 验收标准

- 文件可以从一个窗格拖到另一个窗格。
- 文件夹可以作为拖拽目标。
- 按 Option 可以复制。
- 按 Command 可以移动。
- 拖拽失败要有错误提示。

---

## 3.8 工作区模块

### 功能说明

保存和恢复用户的窗口状态。

### 第一版保存内容

1. 窗口大小和位置
2. 当前窗格布局
3. 每个窗格打开的目录
4. 每个窗格视图模式
5. 每个窗格排序方式
6. 侧边栏宽度
7. 最近打开工作区

### 数据结构

```swift
struct Workspace: Codable, Identifiable {
    var id: UUID
    var name: String
    var layout: PaneLayout
    var panes: [PaneState]
    var windowFrame: String
    var sidebarWidth: CGFloat
    var createdAt: Date
    var updatedAt: Date
}
```

### 存储方案

第一版可以使用 JSON 文件存储：

```text
~/Library/Application Support/Clover/Workspaces/default.json
```

后续可迁移到 SQLite 或 Core Data。

### 实现要求

- 应用关闭时自动保存当前工作区。
- 应用启动时恢复上次工作区。
- 用户可以手动保存当前工作区。
- 用户可以重置为默认工作区。

### 验收标准

- 打开多个窗格后退出应用，再打开能恢复目录和布局。
- 切换视图模式后退出应用，再打开能恢复。
- 如果某个目录已不存在，应回退到 Home 目录并提示。

---

## 3.9 搜索模块

### 功能说明

第一版只做当前目录搜索，不做全局 Spotlight 搜索。

### 搜索能力

1. 当前目录文件名过滤
2. 是否区分大小写，默认不区分
3. 是否包含隐藏文件，跟随当前窗格设置
4. 搜索结果实时刷新
5. 清空搜索后恢复完整列表

### 组件设计

```text
PaneSearchBar
FileFilterService
FilePaneViewModel.searchQuery
```

### 实现要求

- 不重新扫描磁盘，优先对当前已加载列表过滤。
- 搜索框输入时 debounce 100-200ms。
- 过滤结果为空时显示空状态。

### 验收标准

- 输入关键词后列表实时过滤。
- 清空关键词后显示完整列表。
- 搜索不影响当前目录状态。

---

## 3.10 Quick Look 预览模块

### 功能说明

选中文件后按空格可以预览。

### 实现要求

- 使用 `QLPreviewPanel` 或 `QLPreviewView`。
- 当前激活窗格提供预览数据源。
- 支持单文件预览。
- 多选时预留多文件预览能力。

### 验收标准

- 选中图片后按空格能预览。
- 选中 PDF 后按空格能预览。
- 关闭预览后仍然保持当前选中状态。

---

## 3.11 侧边栏模块

### 第一版功能

侧边栏显示常用位置：

1. Home
2. Desktop
3. Documents
4. Downloads
5. Applications
6. Movies
7. Music
8. Pictures
9. Volumes

### 数据结构

```swift
struct SidebarItem: Identifiable, Codable {
    var id: UUID
    var title: String
    var urlBookmark: Data?
    var systemIconName: String?
    var children: [SidebarItem]
}
```

### 实现要求

- 使用 `NSOutlineView`。
- 点击侧边栏项目时，在当前激活窗格打开对应目录。
- 后续预留自定义收藏夹功能。

### 验收标准

- 点击 Downloads，当前窗格打开 Downloads。
- 点击 Applications，当前窗格打开 Applications。
- 侧边栏项目图标显示正确。

---

## 3.12 右键菜单和快捷键模块

### 第一版右键菜单

文件右键菜单包含：

1. 打开
2. 复制
3. 移动到...
4. 重命名
5. 放入废纸篓
6. 复制路径
7. 在 Finder 中显示
8. 显示简介，后续实现

空白区域右键菜单包含：

1. 新建文件夹
2. 粘贴
3. 刷新
4. 显示隐藏文件

### 第一版快捷键

| 快捷键 | 功能 |
|---|---|
| Command + L | 编辑路径 |
| Command + R | 刷新当前窗格 |
| Command + C | 复制选中文件 |
| Command + V | 粘贴文件 |
| Command + Delete | 放入废纸篓 |
| Return | 重命名 |
| Space | Quick Look |
| Command + 1 | 单窗格 |
| Command + 2 | 左右双窗格 |
| Command + 3 | 上下双窗格 |
| Command + 4 | 四宫格 |
| Command + F | 搜索当前目录 |
| Command + Shift + . | 显示或隐藏隐藏文件 |

### 命令系统设计

```swift
struct AppCommand: Identifiable {
    let id: String
    let title: String
    let defaultShortcut: String?
    let handler: (CommandContext) -> Void
}
```

```swift
struct CommandContext {
    let activePaneID: UUID?
    let selectedURLs: [URL]
    let currentDirectoryURL: URL?
}
```

### 实现要求

- 菜单、工具栏、快捷键都调用同一套 CommandRegistry。
- 快捷键必须作用于当前激活窗格。

### 验收标准

- Command + 1/2/3/4 可以切换布局。
- Return 可以重命名选中文件。
- Command + Delete 可以把文件放入废纸篓。
- 右键菜单功能可以正常执行。

---

# 4. 高级功能规划

高级功能不进入第一版，但架构必须预留。

## 4.1 批量重命名

计划功能：

1. 添加前缀
2. 添加后缀
3. 替换文本
4. 正则替换
5. 自动编号
6. 修改扩展名
7. 日期格式插入
8. 实时预览
9. 冲突检测
10. 执行历史

建议模块：

```text
BatchRenameService
RenameRule
RenamePreview
RenameConflictChecker
```

---

## 4.2 文件夹同步

计划功能：

1. 左到右同步
2. 右到左同步
3. 双向同步
4. 同步前预览
5. 按大小和修改时间比较
6. 可选 hash 精确比较
7. 忽略隐藏文件
8. 忽略规则
9. 同步日志

建议模块：

```text
FolderSyncService
SyncScanner
SyncPlanner
SyncExecutor
SyncLogStore
```

---

## 4.3 暂存架

计划功能：

1. 把文件拖入暂存架
2. 暂存架内多选
3. 批量复制到当前窗格
4. 批量移动到当前窗格
5. 批量移除暂存项
6. 暂存架可作为侧边栏区域或浮动面板

建议模块：

```text
StashShelfService
StashItemStore
StashShelfViewController
```

---

## 4.4 压缩包浏览

计划功能：

1. 浏览 zip 文件内容
2. 解压 zip
3. 创建 zip
4. 后续支持 7z、rar、tar、gz 等
5. 压缩包作为 VirtualFileProvider 接入

建议模块：

```text
ArchiveFileProvider
ArchiveReader
ArchiveExtractor
ArchiveCreator
```

---

## 4.5 远程连接

推荐开发顺序：

1. SFTP
2. WebDAV
3. FTP
4. SMB，优先走系统挂载
5. S3
6. Dropbox / OneDrive / Google Drive

建议模块：

```text
RemoteFileProvider
SFTPFileProvider
WebDAVFileProvider
RemoteConnectionStore
RemoteCredentialStore
```

密码和 token 必须存入 Keychain。

---

# 5. 推荐项目目录结构

```text
Clover/
├── CloverApp.swift 或 AppDelegate.swift
├── App/
│   ├── AppDelegate.swift
│   ├── MainWindowController.swift
│   └── AppEnvironment.swift
│
├── UI/
│   ├── Window/
│   ├── Workspace/
│   ├── Pane/
│   │   ├── FilePaneViewController.swift
│   │   ├── FilePaneViewModel.swift
│   │   ├── FileListViewController.swift
│   │   ├── FileIconViewController.swift
│   │   └── PaneLayoutController.swift
│   ├── PathBar/
│   ├── Sidebar/
│   ├── Toolbar/
│   ├── Search/
│   └── Shared/
│
├── Domain/
│   ├── Models/
│   │   ├── FileItem.swift
│   │   ├── PaneState.swift
│   │   ├── Workspace.swift
│   │   └── SidebarItem.swift
│   ├── Commands/
│   ├── FileOperations/
│   ├── Search/
│   ├── Workspace/
│   └── Settings/
│
├── Providers/
│   ├── FileProvider.swift
│   ├── Local/
│   │   └── LocalFileProvider.swift
│   ├── Archive/
│   └── Remote/
│
├── Infrastructure/
│   ├── Persistence/
│   │   ├── JSONStore.swift
│   │   └── WorkspaceStore.swift
│   ├── Security/
│   │   ├── BookmarkStore.swift
│   │   └── KeychainStore.swift
│   ├── Thumbnail/
│   ├── FileWatching/
│   └── Logging/
│
├── Resources/
│   ├── Assets.xcassets
│   └── Localizable.strings
│
└── Tests/
    ├── DomainTests/
    ├── ProviderTests/
    └── UITests/
```

---

# 6. 开发阶段拆分

## 阶段 1：项目初始化

### 目标

创建可以运行的 macOS App 基础工程。

### 任务

1. 创建 Swift macOS App 项目。
2. 配置 AppKit 生命周期。
3. 创建 `MainWindowController`。
4. 创建基础目录结构。
5. 添加日志工具。
6. 添加基础错误类型。

### AI 执行 Prompt

```text
请为 Clover 创建 macOS Swift/AppKit 项目基础结构。实现 MainWindowController，启动后显示一个 1100x720 的主窗口。窗口包含顶部 toolbar 占位区、左侧 sidebar 占位区、右侧 content 占位区、底部 status bar 占位区。请按照计划书中的目录结构创建文件，并保证项目可以编译运行。
```

### 验收标准

- 项目可以编译。
- 应用启动后显示主窗口。
- 窗口尺寸合理。
- UI 区域划分清晰。

---

## 阶段 2：FileProvider 和本地目录读取

### 目标

实现本地目录读取能力。

### 任务

1. 创建 `FileProvider` 协议。
2. 创建 `LocalFileProvider`。
3. 创建 `FileItem`。
4. 实现目录枚举。
5. 实现文件属性读取。
6. 实现排序。
7. 写单元测试。

### AI 执行 Prompt

```text
请实现 Clover 的 FileProvider 抽象层和 LocalFileProvider。本阶段只需要支持 listDirectory(at:)。请使用 URLResourceValues 读取文件名、是否目录、大小、创建时间、修改时间、类型标识、是否隐藏。目录读取必须异步执行。请同时实现 FileItem 模型、SortOption 枚举和基础排序服务，并添加单元测试。
```

### 验收标准

- 能读取指定目录文件列表。
- 能区分文件和文件夹。
- 文件属性基本正确。
- 目录不存在时返回合理错误。
- 单元测试通过。

---

## 阶段 3：单窗格文件列表

### 目标

在 UI 中显示文件列表。

### 任务

1. 创建 `FilePaneViewController`。
2. 创建 `FilePaneViewModel`。
3. 使用 `NSTableView` 显示文件列表。
4. 支持双击文件夹进入。
5. 支持双击文件用默认 App 打开。
6. 支持刷新当前目录。

### AI 执行 Prompt

```text
请实现单窗格文件浏览 UI。使用 NSTableView 展示 LocalFileProvider 返回的 FileItem。列包括名称、大小、类型、修改时间。双击文件夹进入该目录，双击文件使用 NSWorkspace 默认打开。添加刷新按钮或 Command+R 刷新当前目录。注意 UI 不能阻塞主线程。
```

### 验收标准

- 能显示 Home 目录。
- 双击文件夹可以进入。
- 双击文件可以打开。
- Command+R 可以刷新。
- 大目录加载时 UI 不明显卡顿。

---

## 阶段 4：地址栏

### 目标

实现路径显示和路径输入。

### 任务

1. 创建 `PathBarView`。
2. 显示当前目录面包屑。
3. 点击父级路径跳转。
4. Command+L 进入输入模式。
5. 输入路径跳转。

### AI 执行 Prompt

```text
请为 FilePaneViewController 添加地址栏 PathBarView。地址栏以面包屑形式显示当前路径，点击任意父级目录可跳转。支持 Command+L 进入路径输入模式，输入 ~/Downloads、/Applications 等路径后回车跳转。路径无效时显示错误提示。
```

### 验收标准

- 地址栏显示正确路径。
- 点击父级目录可以跳转。
- Command+L 可输入路径。
- 无效路径不会崩溃。

---

## 阶段 5：多窗格布局

### 目标

实现 1、2、4 窗格切换。

### 任务

1. 创建 `PaneLayoutController`。
2. 实现单窗格布局。
3. 实现左右双窗格。
4. 实现上下双窗格。
5. 实现四宫格。
6. 支持 Command+1/2/3/4 切换。
7. 维护当前激活窗格。

### AI 执行 Prompt

```text
请实现 Clover 的多窗格布局。支持 single、twoVertical、twoHorizontal、fourGrid 四种布局。使用 NSSplitViewController 或自定义 NSView 布局。每个窗格都是独立的 FilePaneViewController。支持 Command+1/2/3/4 切换布局，并维护 activePaneID。切换布局时尽量保留已有窗格状态。
```

### 验收标准

- 四种布局都能显示。
- 每个窗格能打开不同目录。
- 当前激活窗格可识别。
- 快捷键切换布局稳定。

---

## 阶段 6：基础文件操作

### 目标

实现复制、移动、重命名、新建文件夹、放入废纸篓。

### 任务

1. 创建 `FileOperationService`。
2. 扩展 `LocalFileProvider` 文件操作能力。
3. 实现复制。
4. 实现移动。
5. 实现重命名。
6. 实现新建文件夹。
7. 实现放入废纸篓。
8. 实现文件冲突提示。
9. 操作后刷新窗格。

### AI 执行 Prompt

```text
请实现 Clover 的基础文件操作模块。所有操作必须通过 FileOperationService 调用 FileProvider，不允许 UI 直接调用 FileManager。支持复制、移动、重命名、新建文件夹、放入废纸篓。文件冲突时弹出选择：替换、跳过、保留两者、取消。操作完成后刷新相关窗格。
```

### 验收标准

- 可以新建文件夹。
- 可以重命名单个文件。
- 可以复制文件到另一个目录。
- 可以移动文件到另一个目录。
- 可以把文件放入废纸篓。
- 文件冲突会弹窗确认。

---

## 阶段 7：右键菜单和快捷键

### 目标

完善基础操作入口。

### 任务

1. 创建 `CommandRegistry`。
2. 创建 `CommandContext`。
3. 右键菜单接入命令系统。
4. 快捷键接入命令系统。
5. 工具栏按钮预留接入命令系统。

### AI 执行 Prompt

```text
请实现 CommandRegistry，让右键菜单、快捷键、未来工具栏都通过同一套命令系统执行。请添加文件右键菜单：打开、复制、移动到、重命名、放入废纸篓、复制路径、在 Finder 中显示。添加空白区域右键菜单：新建文件夹、粘贴、刷新、显示隐藏文件。实现 Command+L、Command+R、Command+C、Command+V、Command+Delete、Return、Space、Command+F、Command+Shift+. 等快捷键。
```

### 验收标准

- 右键菜单可用。
- 快捷键可用。
- 命令作用于当前激活窗格。

---

## 阶段 8：拖拽复制和移动

### 目标

实现窗格间拖拽。

### 任务

1. NSTableView 支持拖拽源。
2. NSTableView 支持拖拽目标。
3. 跨窗格拖拽到空白区域。
4. 拖拽到文件夹。
5. Option 强制复制。
6. Command 强制移动。
7. 拖拽完成后刷新。

### AI 执行 Prompt

```text
请为 Clover 实现窗格内和窗格间拖拽。文件可以从一个 FilePaneViewController 拖到另一个窗格，也可以拖到目标窗格中的文件夹。默认规则：同一磁盘移动，跨磁盘复制；按 Option 强制复制；按 Command 强制移动。拖拽操作仍然必须通过 FileOperationService 执行。
```

### 验收标准

- 可以从左窗格拖文件到右窗格。
- 可以拖文件到另一个文件夹。
- Option 和 Command 修饰键生效。
- 拖拽失败有错误提示。

---

## 阶段 9：工作区保存和恢复

### 目标

应用关闭后恢复之前状态。

### 任务

1. 创建 `Workspace` 模型。
2. 创建 `WorkspaceStore`。
3. 应用关闭时保存。
4. 应用启动时恢复。
5. 保存窗格布局。
6. 保存每个窗格当前路径。
7. 保存视图模式和排序。

### AI 执行 Prompt

```text
请实现 Clover 的工作区保存和恢复。使用 JSON 文件存储到 Application Support/Clover/Workspaces/default.json。保存窗口大小、布局类型、每个窗格当前路径、视图模式、排序方式、侧边栏宽度。应用退出时自动保存，启动时自动恢复。如果路径不存在，则回退到 Home 目录。
```

### 验收标准

- 退出再打开能恢复布局。
- 退出再打开能恢复每个窗格目录。
- 目录不存在时不会崩溃。

---

## 阶段 10：搜索

### 目标

实现当前目录快速过滤。

### 任务

1. 添加搜索框。
2. 实现文件名过滤。
3. debounce 输入。
4. 空状态显示。
5. Command+F 聚焦搜索框。

### AI 执行 Prompt

```text
请实现当前目录搜索功能。在 FilePaneViewController 中添加搜索框。Command+F 聚焦搜索框。搜索时只过滤当前已加载的 FileItem，不重新扫描磁盘。默认不区分大小写。输入时 debounce 150ms。无结果时显示空状态。
```

### 验收标准

- Command+F 可以搜索。
- 输入关键词后列表过滤。
- 清空关键词后恢复完整列表。

---

## 阶段 11：Quick Look 预览

### 目标

支持按空格预览文件。

### 任务

1. 接入 `QLPreviewPanel`。
2. 当前激活窗格作为数据源。
3. Space 触发预览。
4. 关闭后保持选择。

### AI 执行 Prompt

```text
请为 Clover 接入 Quick Look。选中文件后按 Space 显示 QLPreviewPanel。当前激活窗格提供预览数据源。先支持单文件预览，多文件预览可以预留接口。
```

### 验收标准

- 图片可预览。
- PDF 可预览。
- 文本文件可预览。
- 关闭预览后选择状态不丢失。

---

## 阶段 12：图标视图

### 目标

支持列表视图和图标视图切换。

### 任务

1. 创建 `FileIconViewController`。
2. 使用 `NSCollectionView`。
3. 显示文件图标和名称。
4. 支持双击打开。
5. 支持选择。
6. 支持拖拽基础能力。

### AI 执行 Prompt

```text
请为 FilePaneViewController 增加图标视图模式。使用 NSCollectionView 显示文件图标和名称。支持和列表视图相同的数据源、选择、双击打开、基础拖拽。添加视图模式切换按钮，并把 viewMode 存入 PaneState。
```

### 验收标准

- 可以在列表和图标视图间切换。
- 图标视图能打开文件夹和文件。
- 切换视图不改变当前目录。

---

# 7. 大文件处理方案

大文件能力必须在第一版架构阶段提前设计，不允许后期再临时补丁式处理。文件管理器涉及复制、移动、Hash、预览、搜索、同步、压缩、远程传输等高风险场景，如果没有统一的大文件策略，容易出现 UI 卡死、内存暴涨、进度不准确、取消失败、文件损坏或操作不可恢复等问题。

---

## 7.1 大文件定义

项目中统一使用以下文件大小分级：

| 等级 | 文件大小 | 处理策略 |
|---|---:|---|
| 小文件 | < 100 MB | 可直接普通处理，但仍不得阻塞主线程 |
| 中等文件 | 100 MB - 1 GB | 必须异步处理，显示进度 |
| 大文件 | 1 GB - 10 GB | 必须分块处理，支持取消，显示精确进度 |
| 超大文件 | > 10 GB | 必须分块处理，支持取消，操作前显示风险提示 |

文件大小阈值统一放在配置中：

```swift
enum FileSizePolicy {
    static let smallFileLimit: Int64 = 100 * 1024 * 1024
    static let mediumFileLimit: Int64 = 1 * 1024 * 1024 * 1024
    static let largeFileLimit: Int64 = 10 * 1024 * 1024 * 1024
    static let defaultChunkSize: Int = 8 * 1024 * 1024
}
```

---

## 7.2 总体原则

所有涉及大文件的能力必须遵守：

1. **禁止一次性读入内存**：不得使用 `Data(contentsOf:)` 直接读取大文件。
2. **必须异步执行**：复制、Hash、压缩、上传、下载、同步比较都不能阻塞主线程。
3. **必须有进度**：大文件操作必须显示当前文件、总字节数、已处理字节数、速度、预计剩余时间。
4. **必须可取消**：用户可以取消长时间任务。
5. **必须保证文件安全**：复制到临时文件，完成校验后再替换目标文件。
6. **必须处理磁盘空间不足**：复制前预估目标卷可用空间。
7. **必须处理休眠和中断**：任务失败后给出清晰错误，不留下误导性的完成状态。
8. **必须限制并发**：多个大文件任务不能无限并发。
9. **必须避免 UI 频繁刷新**：进度更新需要节流，例如 100-250ms 更新一次。

---

## 7.3 文件复制策略

### 7.3.1 本地同卷移动

如果源文件和目标目录位于同一个 volume，移动优先使用系统 rename/move 操作。

特点：

- 通常不需要复制文件内容。
- 速度快。
- 进度可以显示为瞬时操作。
- 失败时需要回退错误提示。

### 7.3.2 跨卷移动

跨卷移动必须视为：

```text
复制到目标临时文件
校验复制结果
删除源文件或放入废纸篓
刷新源窗格和目标窗格
```

不允许在复制未完成时删除源文件。

### 7.3.3 本地复制

大文件复制必须使用流式分块复制。

推荐策略：

```text
sourceURL
  ↓
InputStream / FileHandle.read(upToCount:)
  ↓  chunk 8MB
OutputStream / FileHandle.write
  ↓
temporary target file
  ↓
完成后 rename 为最终文件名
```

目标文件临时命名建议：

```text
.filename.clover-copying
```

复制完成后再原子性改名为最终目标文件。

### 7.3.4 APFS 克隆优化

在本地 APFS 卷上复制大文件时，可以优先尝试 clone/copy-on-write 能力。失败后回退到普通分块复制。

要求：

- clone 优化必须封装在 `LocalCopyStrategy` 中。
- 不允许业务层依赖 clone 一定成功。
- clone 成功时也要刷新 UI 和文件属性。

建议抽象：

```swift
enum CopyStrategy {
    case systemFastCopy
    case apfsClone
    case chunkedCopy
}
```

---

## 7.4 FileOperationService 大文件任务模型

所有大文件操作必须通过统一任务模型执行。

```swift
struct FileTransferTask: Identifiable {
    let id: UUID
    let sources: [URL]
    let destination: URL
    var totalBytes: Int64
    var completedBytes: Int64
    var currentFileURL: URL?
    var state: FileTransferState
    var startedAt: Date?
    var updatedAt: Date?
    var speedBytesPerSecond: Double
    var estimatedRemainingSeconds: TimeInterval?
}
```

```swift
enum FileTransferState {
    case pending
    case preparing
    case running
    case paused
    case cancelling
    case cancelled
    case completed
    case failed(Error)
}
```

第一版至少支持：

- pending
- preparing
- running
- cancelling
- cancelled
- completed
- failed

`paused` 可以预留，第一版不强制实现。

---

## 7.5 进度计算

复制多个文件时，进度必须按总字节数计算，而不是按文件数量计算。

流程：

```text
扫描所有源文件
计算 totalBytes
执行复制
每写入一个 chunk，累加 completedBytes
节流通知 UI
```

进度模型：

```swift
struct FileOperationProgressSnapshot {
    var taskID: UUID
    var totalBytes: Int64
    var completedBytes: Int64
    var currentFileName: String?
    var fractionCompleted: Double
    var speedBytesPerSecond: Double
    var estimatedRemainingSeconds: TimeInterval?
}
```

要求：

- UI 不直接读取任务内部状态。
- UI 只订阅 progress snapshot。
- 进度更新频率限制在 4-10 次/秒。

---

## 7.6 取消策略

大文件复制和传输必须支持取消。

取消流程：

```text
用户点击取消
任务状态改为 cancelling
当前 chunk 写完后停止
关闭文件句柄
删除目标临时文件
状态改为 cancelled
刷新目标目录
```

要求：

- 不允许在写入 chunk 的中间强杀导致句柄泄漏。
- 取消后不得留下最终文件名的半成品。
- 如果临时文件删除失败，需要提示用户。

---

## 7.7 磁盘空间检查

复制或跨卷移动大文件前，需要检查目标卷可用空间。

策略：

1. 计算源文件总大小。
2. 获取目标目录所在 volume 的可用空间。
3. 如果空间不足，操作前阻止。
4. 如果空间接近不足，提示用户风险。

建议封装：

```swift
struct VolumeCapacityInfo {
    var availableBytes: Int64
    var totalBytes: Int64
    var volumeURL: URL
}
```

```swift
protocol VolumeCapacityChecking {
    func capacityInfo(for destinationURL: URL) throws -> VolumeCapacityInfo
}
```

---

## 7.8 大文件 Hash 计算

Hash 功能后续加入时必须分块读取。

支持算法可规划：

- MD5，兼容校验用途
- SHA1，兼容旧校验用途
- SHA256，推荐默认
- SHA512，后续可选

要求：

- 不允许一次性读取文件。
- 支持取消。
- 显示进度。
- Hash 任务和复制任务共用大文件任务进度模型。

建议接口：

```swift
protocol FileHashService {
    func hashFile(at url: URL, algorithm: HashAlgorithm) async throws -> String
}
```

---

## 7.9 大文件预览策略

Quick Look 可以交给系统处理，但应用自身不得主动把大文件完整读入内存。

对于文本文件预览，如果后续自研预览器：

| 文件大小 | 策略 |
|---|---|
| < 10 MB | 可完整读取 |
| 10 MB - 100 MB | 只读取开头部分，并提示文件较大 |
| > 100 MB | 默认不全文读取，只显示文件信息和“用外部应用打开” |

对于图片、视频、PDF：

- 第一版直接使用 Quick Look。
- 缩略图使用系统缩略图服务。
- 不自己解码超大图片。

---

## 7.10 大文件搜索策略

第一版搜索只做文件名过滤，不读取文件内容。

后续如果做内容搜索：

- 默认跳过大于指定阈值的文件。
- 文本内容搜索必须流式读取。
- 二进制文件默认跳过。
- 对大文件内容搜索前需要用户确认。

建议阈值：

```swift
enum SearchPolicy {
    static let maxInlineTextSearchFileSize: Int64 = 50 * 1024 * 1024
}
```

---

## 7.11 文件夹同步中的大文件策略

文件夹同步后续开发时，大文件比较不能默认计算 Hash。

默认比较策略：

```text
relativePath + fileSize + modificationDate
```

精确比较策略：

```text
relativePath + fileSize + streaming hash
```

要求：

- Hash 精确比较必须由用户主动开启。
- 对超过 10 GB 的文件计算 Hash 前必须提示。
- 同步执行前必须显示预览计划。
- 跨卷同步必须检查磁盘空间。

---

## 7.12 远程传输中的大文件策略

远程连接后续开发时，大文件上传和下载必须支持：

1. 分块传输。
2. 传输进度。
3. 取消。
4. 失败重试。
5. 临时文件。
6. 断点续传，后续阶段实现。

第一版远程能力未实现，但 `FileProvider` 协议设计时要避免只适配本地文件。

后续建议扩展：

```swift
protocol TransferCapableFileProvider: FileProvider {
    func download(_ remotePath: String, to localURL: URL, progress: FileTransferProgressHandler?) async throws
    func upload(_ localURL: URL, to remotePath: String, progress: FileTransferProgressHandler?) async throws
}
```

---

## 7.13 压缩包中的大文件策略

后续压缩和解压大文件时必须：

- 使用流式压缩/解压。
- 显示进度。
- 支持取消。
- 解压到临时目录后再移动到目标目录。
- 目标空间不足时提前阻止。
- 避免将压缩包内大文件完整加载到内存。

---

## 7.14 UI 设计要求

大文件操作需要专门的任务面板。

第一版可设计为底部任务条，后续升级为任务中心。

### 底部任务条显示

```text
正在复制：video.mov
42.3 GB / 80.0 GB    128 MB/s    剩余 5 分 12 秒    [取消]
```

### 任务中心后续显示

- 当前任务
- 已完成任务
- 失败任务
- 可重试任务
- 可取消任务
- 每个任务的源路径和目标路径

UI 要求：

- 大文件任务不得用模态弹窗阻塞整个应用。
- 用户可以继续浏览文件。
- 当前正在操作的文件夹可以显示刷新延迟或忙碌状态。

---

## 7.15 并发控制

大文件操作必须限制并发。

建议第一版策略：

```swift
enum FileOperationConcurrencyPolicy {
    static let maxConcurrentLargeTransfers = 1
    static let maxConcurrentSmallOperations = 4
}
```

规则：

- 大文件复制同一时间默认只跑 1 个。
- 小文件批量复制可以并发，但写入同一目标目录时要谨慎。
- 同一源文件不能同时参与多个写操作。
- 同一目标路径不能被多个任务同时写入。

---

## 7.16 错误处理

大文件相关错误必须有明确类型。

```swift
enum LargeFileOperationError: LocalizedError {
    case insufficientDiskSpace(required: Int64, available: Int64)
    case sourceFileUnavailable(URL)
    case destinationUnavailable(URL)
    case temporaryFileCleanupFailed(URL)
    case copyCancelled
    case checksumMismatch(URL)
    case fileHandleError(URL, underlying: Error)
}
```

错误展示要求：

- 用户能知道哪个文件失败。
- 用户能知道失败原因。
- 用户能选择重试、跳过或取消剩余任务。
- 失败任务不得显示为完成。

---

## 7.17 第一版必须完成的大文件能力

第一版必须完成：

1. 大文件复制不阻塞 UI。
2. 大文件复制不一次性读入内存。
3. 复制和跨卷移动显示进度。
4. 大文件任务支持取消。
5. 复制前检查目标空间。
6. 复制到临时文件，完成后再改名。
7. 多文件复制按总字节数计算进度。
8. 文件操作任务有统一状态模型。
9. UI 有底部任务条或任务浮层。

第一版可以暂不完成：

1. 暂停和继续。
2. 断点续传。
3. Hash 校验。
4. 远程大文件传输。
5. 压缩包大文件流式处理。

---

## 7.18 大文件夹扫描方案

大文件夹扫描必须作为第一版核心架构设计。文件管理器不能假设一个目录只有几百个文件，必须支持包含上万、几十万甚至更多文件的目录。目录扫描、排序、搜索、缩略图生成、文件属性读取都可能导致 UI 卡死，因此必须统一设计异步扫描和增量加载机制。

---

### 7.18.1 大文件夹定义

项目中统一使用以下目录规模分级：

| 等级 | 文件数量 | 处理策略 |
|---|---:|---|
| 普通目录 | < 1,000 项 | 可一次性加载结果，但仍必须异步 |
| 较大目录 | 1,000 - 10,000 项 | 必须增量加载、分批刷新 UI |
| 大目录 | 10,000 - 100,000 项 | 必须分页、可取消、懒加载属性 |
| 超大目录 | > 100,000 项 | 必须使用扫描任务、虚拟列表、延迟排序和提示用户 |

统一配置：

```swift
enum DirectoryScanPolicy {
    static let normalDirectoryLimit = 1_000
    static let largeDirectoryLimit = 10_000
    static let hugeDirectoryLimit = 100_000
    static let batchSize = 300
    static let uiUpdateInterval: TimeInterval = 0.15
    static let maxConcurrentDirectoryScans = 2
    static let maxConcurrentThumbnailRequests = 4
}
```

---

### 7.18.2 总体原则

所有目录扫描必须遵守：

1. **禁止在主线程扫描目录**。
2. **禁止扫描完成后才显示 UI**，必须边扫描边显示。
3. **禁止一次性读取所有重属性**，例如大文件夹中不要一开始就读取全部文件大小、缩略图、UTType、扩展元数据。
4. **必须支持取消扫描**，用户切换目录后旧扫描必须停止。
5. **必须防止旧扫描结果污染新目录**，每次扫描需要 scanID。
6. **必须限制 UI 刷新频率**，不得每发现一个文件刷新一次表格。
7. **必须限制缩略图并发**，缩略图生成不得挤占目录扫描线程。
8. **必须能应对权限错误**，单个文件读取失败不能导致整个目录失败。
9. **必须有大目录提示**，目录项目过多时 UI 显示“正在加载 x 项”。
10. **必须支持用户继续操作**，扫描期间用户可以切换目录、切换窗格、取消扫描。

---

### 7.18.3 目录扫描任务模型

目录扫描必须通过独立任务模型执行。

```swift
struct DirectoryScanTask: Identifiable {
    let id: UUID
    let directoryURL: URL
    var state: DirectoryScanState
    var discoveredCount: Int
    var loadedCount: Int
    var startedAt: Date
    var updatedAt: Date
}
```

```swift
enum DirectoryScanState {
    case pending
    case scanning
    case cancelling
    case cancelled
    case completed
    case failed(Error)
}
```

扫描结果用 snapshot 传给 UI：

```swift
struct DirectoryScanSnapshot {
    let scanID: UUID
    let directoryURL: URL
    let items: [FileItem]
    let totalDiscoveredCount: Int
    let isFinal: Bool
}
```

要求：

- 每次打开目录创建新的 `scanID`。
- `FilePaneViewModel` 只接受当前 scanID 的结果。
- 如果用户切换目录，旧 scanID 的结果必须丢弃。

---

### 7.18.4 FileItem 属性分层加载

大文件夹不能一次性读取全部属性。`FileItem` 应分为基础属性和扩展属性。

基础属性，扫描时读取：

- url
- name
- isDirectory
- isHidden
- modificationDate，可选
- typeIdentifier，可选

扩展属性，后续懒加载：

- 文件大小，特别是文件夹大小
- 缩略图
- 精确 UTType 描述
- 权限信息
- Finder tag
- Finder comment
- Hash

建议模型：

```swift
struct FileItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let isHidden: Bool
    var basicAttributes: FileBasicAttributes
    var extendedAttributes: FileExtendedAttributes?
}
```

```swift
struct FileBasicAttributes: Hashable {
    var modificationDate: Date?
    var typeIdentifier: String?
}
```

```swift
struct FileExtendedAttributes: Hashable {
    var size: Int64?
    var creationDate: Date?
    var permissionsText: String?
    var tagNames: [String]
}
```

要求：

- 列表第一屏优先显示名称和图标。
- 大小、类型描述、缩略图允许延迟出现。
- 文件夹大小默认不递归计算，除非用户主动请求。

---

### 7.18.5 增量扫描流程

推荐流程：

```text
用户打开目录
创建 scanID
清空当前列表或显示旧列表的 loading overlay
后台开始枚举目录
每收集 batchSize 个 FileItem 形成一个 batch
对 batch 做轻量排序或暂存
节流后发送 DirectoryScanSnapshot 给 ViewModel
ViewModel 校验 scanID
更新 table/collection 数据源
扫描完成后发送 isFinal = true
最终排序和状态更新
```

伪代码：

```swift
func scanDirectory(_ url: URL) -> AsyncThrowingStream<DirectoryScanSnapshot, Error> {
    AsyncThrowingStream { continuation in
        let scanID = UUID()
        Task.detached(priority: .userInitiated) {
            var batch: [FileItem] = []
            var total = 0

            do {
                for childURL in try directoryEnumerator(url) {
                    try Task.checkCancellation()
                    let item = try makeBasicFileItem(childURL)
                    batch.append(item)
                    total += 1

                    if batch.count >= DirectoryScanPolicy.batchSize {
                        continuation.yield(
                            DirectoryScanSnapshot(
                                scanID: scanID,
                                directoryURL: url,
                                items: batch,
                                totalDiscoveredCount: total,
                                isFinal: false
                            )
                        )
                        batch.removeAll(keepingCapacity: true)
                    }
                }

                if !batch.isEmpty {
                    continuation.yield(
                        DirectoryScanSnapshot(
                            scanID: scanID,
                            directoryURL: url,
                            items: batch,
                            totalDiscoveredCount: total,
                            isFinal: false
                        )
                    )
                }

                continuation.yield(
                    DirectoryScanSnapshot(
                        scanID: scanID,
                        directoryURL: url,
                        items: [],
                        totalDiscoveredCount: total,
                        isFinal: true
                    )
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

实际实现时需注意：

- `scanID` 应由调用方创建并传入，方便取消和校验。
- UI 更新必须在 MainActor。
- batch 不要太小，否则 UI 高频刷新。
- batch 不要太大，否则首屏显示慢。

---

### 7.18.6 UI 虚拟化和表格性能

大目录必须使用 AppKit 原生高性能控件：

- 列表视图使用 `NSTableView`。
- 图标视图使用 `NSCollectionView`。
- 不使用 SwiftUI List。
- 不一次性创建所有 Cell View。
- 使用复用机制。

列表模式建议：

```text
NSTableView + NSView-based cell + diff/batch update
```

更新策略：

- 小 batch 可以 append rows。
- 大 batch 可以合并后 `reloadData()`，但频率必须节流。
- 超大目录下避免复杂动画。
- 排序变化时避免每 batch 全量排序 UI。

要求：

- 滚动时再请求可见区域缩略图。
- 离屏 item 不生成缩略图。
- 快速滚动时取消旧缩略图请求。

---

### 7.18.7 排序策略

大目录排序非常容易卡顿，必须分级处理。

默认策略：

| 目录规模 | 排序策略 |
|---|---|
| < 1,000 项 | 每个 batch 后可排序 |
| 1,000 - 10,000 项 | batch 合并后节流排序 |
| > 10,000 项 | 扫描中仅追加显示，扫描完成后再最终排序 |
| > 100,000 项 | 提示用户正在大目录模式，排序可能延迟 |

要求：

- 排序必须在后台完成。
- 排序完成后一次性提交结果给 UI。
- 用户切换排序规则时取消旧排序任务。
- 旧排序结果不能覆盖新排序结果。

排序任务模型：

```swift
struct DirectorySortTask: Identifiable {
    let id: UUID
    let scanID: UUID
    let sortOption: SortOption
}
```

---

### 7.18.8 搜索和过滤策略

当前目录搜索对大目录也必须不卡 UI。

要求：

- 搜索输入 debounce 150-300ms。
- 过滤在后台执行。
- 过滤结果用 filterTaskID 校验。
- 旧过滤结果不得覆盖新搜索。
- 对超过 100,000 项的目录，搜索框显示“大目录搜索中”。

策略：

```text
用户输入关键词
取消旧 filter task
创建新 filterTaskID
后台过滤当前 items
分批或一次性返回结果
MainActor 更新 UI
```

第一版搜索只过滤已加载项目。扫描尚未完成时，搜索结果随着新 batch 增量更新。

---

### 7.18.9 缩略图生成策略

大目录缩略图是 UI 卡顿常见原因，必须独立队列处理。

要求：

- 缩略图不得在目录扫描阶段生成。
- 只为可见区域生成缩略图。
- 最大并发 4 个。
- 使用内存缓存和磁盘缓存。
- 快速滚动时取消不可见项目的缩略图任务。
- 超大目录默认优先显示系统通用图标。

建议组件：

```text
ThumbnailService
ThumbnailMemoryCache
ThumbnailDiskCache
VisibleItemThumbnailScheduler
```

第一版可先只使用系统图标，缩略图延后，但接口必须预留。

---

### 7.18.10 文件夹大小计算策略

文件夹大小计算不能在目录扫描时递归执行。

要求：

- 默认文件夹大小显示为 `--`。
- 用户右键选择“计算文件夹大小”时再执行。
- 计算必须作为独立任务。
- 支持取消。
- 支持进度。
- 结果可缓存。

错误示例，禁止：

```swift
// 禁止在扫描目录时递归计算每个文件夹大小
let folderSize = calculateFolderSizeRecursively(folderURL)
```

正确策略：

```text
显示目录
文件夹大小为空
用户主动请求
后台递归扫描
更新指定 item 的 size 字段
```

---

### 7.18.11 目录扫描取消策略

用户切换目录、关闭窗格、切换工作区时，必须取消旧扫描。

取消流程：

```text
用户打开新目录
ViewModel.cancelCurrentScan()
旧 scan task 标记 cancelling
后台扫描 Task.checkCancellation()
关闭 enumerator
丢弃旧结果
创建新 scanID
开始新扫描
```

要求：

- 取消后不能继续向 UI 追加旧目录文件。
- 取消无需弹窗，除非发生文件句柄或权限异常。
- ViewModel deinit 时必须取消扫描任务。

---

### 7.18.12 FSEvents 增量刷新策略

目录首次扫描完成后，文件变化不能总是全量重扫。

第一版策略：

- 普通目录：变化后 debounce 300ms，重新扫描当前目录。
- 大目录：变化后标记为“目录已变化”，延迟刷新，避免频繁全量重扫。
- 超大目录：提示用户点击刷新，不自动高频重扫。

后续高级策略：

- 使用 FSEvents 获取变化通知。
- 通过目标路径判断新增、删除、修改。
- 只更新受影响 item。
- 批量变化合并处理。

建议组件：

```text
DirectoryChangeWatcher
DirectoryRefreshCoordinator
DirectorySnapshotCache
```

---

### 7.18.13 缓存策略

为了避免反复打开大目录都重新从零开始，可以设计轻量缓存。

第一版可缓存：

- 最近打开目录路径
- 排序选项
- 基础文件列表快照，短期内有效
- 缩略图，后续实现

缓存要求：

- 缓存必须可失效。
- 缓存不能替代真实扫描结果。
- 打开目录时可以先显示缓存，再后台刷新。
- 如果 FSEvents 表明目录变化，则缓存标记为 stale。

---

### 7.18.14 权限和错误处理

大文件夹中可能部分文件无权限读取。

要求：

- 单个 item 属性读取失败时，创建降级 FileItem。
- 整个目录无权限时，显示权限错误。
- 读取部分失败时，在状态栏提示“部分项目无法读取”。
- 不因为单个文件属性失败中断整个扫描。

错误类型：

```swift
enum DirectoryScanError: LocalizedError {
    case directoryNotFound(URL)
    case permissionDenied(URL)
    case scanCancelled
    case tooManyItems(URL, count: Int)
    case unknown(URL, underlying: Error)
}
```

---

### 7.18.15 UI 状态设计

大目录扫描时，窗格需要清晰状态。

状态栏显示：

```text
正在加载 Downloads，已发现 12,430 项...
```

扫描完成显示：

```text
12,430 项
```

大目录模式显示：

```text
大目录模式：已发现 84,200 项，缩略图和排序将延迟处理
```

空状态显示：

```text
此文件夹为空
```

权限错误显示：

```text
没有权限访问此文件夹
[选择授权目录]
```

---

### 7.18.16 第一版必须完成的大文件夹能力

第一版必须完成：

1. 目录扫描不在主线程执行。
2. 大目录边扫描边显示。
3. 扫描结果按 batch 增量更新。
4. UI 更新有节流。
5. 用户切换目录时取消旧扫描。
6. 使用 scanID 防止旧结果污染新目录。
7. 不在扫描阶段生成缩略图。
8. 不在扫描阶段计算文件夹大小。
9. 大目录排序在后台执行。
10. 搜索过滤在后台执行。
11. 大目录状态在状态栏显示。
12. 单个文件属性读取失败不影响整个目录。

第一版可以暂不完成：

1. 完整 FSEvents 增量更新。
2. 持久化目录快照缓存。
3. 可见区域缩略图调度。
4. 文件夹大小递归任务。
5. 超大目录虚拟滚动深度优化。

---

### 7.18.17 大文件夹扫描 AI 执行 Prompt

```text
请为 Clover 实现大文件夹扫描基础架构。

要求：
1. 项目最低系统 macOS 15+。
2. 技术栈只使用 Swift + AppKit。
3. 单个 Swift 文件不能超过 1000 行，超过必须拆分。
4. 所有图标使用系统 SF Symbols。
5. 目录扫描不能在主线程执行。
6. 实现 DirectoryScanTask、DirectoryScanState、DirectoryScanSnapshot。
7. 每次扫描必须有 scanID。
8. FilePaneViewModel 只能接受当前 scanID 的结果。
9. 用户切换目录时必须取消旧扫描。
10. 使用 AsyncThrowingStream 或等价方式实现增量扫描。
11. 每 300 个 item 或每 150ms 向 UI 推送一次 batch，避免每个 item 都刷新 UI。
12. 扫描阶段只读取基础属性：url、name、isDirectory、isHidden、modificationDate、typeIdentifier。
13. 不允许扫描时计算文件夹大小。
14. 不允许扫描时生成缩略图。
15. NSTableView 使用增量更新或节流 reloadData。
16. 排序必须在后台执行，大目录扫描中可以延迟最终排序。
17. 搜索过滤必须 debounce，并在后台执行。
18. 单个文件属性读取失败时生成降级 item，不中断整个目录扫描。
19. 状态栏显示正在加载、已发现项目数、完成状态、错误状态。
20. ViewModel deinit 时必须取消扫描任务。

请输出：
- 新增文件路径
- 每个文件的完整代码
- 如何接入 FilePaneViewModel
- 如何接入 NSTableView 数据源
- 如何测试 10,000 个文件的目录
- 如何测试切换目录时取消旧扫描
- 如何测试扫描期间 UI 仍可滚动和响应点击
```

---

## 7.19 大文件模块 AI 执行 Prompt

```text
请为 Clover 设计并实现大文件处理基础架构。

要求：
1. 项目最低系统 macOS 15+。
2. 技术栈只使用 Swift + AppKit。
3. 所有图标使用系统 SF Symbols。
4. 单个 Swift 文件不能超过 1000 行，超过必须拆分。
5. 不允许使用 Data(contentsOf:) 读取大文件。
6. 实现 FileTransferTask、FileTransferState、FileOperationProgressSnapshot。
7. 实现 ChunkedFileCopier，使用 FileHandle 或 InputStream/OutputStream 分块复制，默认 chunk size 为 8MB。
8. 复制目标必须先写入临时文件，完成后再 rename 成最终文件。
9. 支持取消任务，取消后删除临时文件。
10. 复制前检查目标磁盘空间。
11. 进度按总字节数计算，包含速度和预计剩余时间。
12. 进度更新需要节流，避免 UI 高频刷新。
13. 实现基础任务队列，大文件同一时间只执行一个。
14. 在 AppKit UI 中实现底部任务条，显示当前文件、总进度、速度、剩余时间和取消按钮。
15. 所有文件操作必须通过 FileOperationService，不允许 ViewController 直接调用 FileManager 做复制。

请输出：
- 新增文件路径
- 每个文件的完整代码
- 如何接入现有 FileOperationService
- 如何测试 1GB 以上文件复制
- 取消任务的测试方式
- 磁盘空间不足的测试方式
```

---

# 8. 第一版最终验收清单

第一版完成时，必须满足以下条件：

## 基础运行

- 应用可以正常启动。
- 主窗口布局稳定。
- 无明显崩溃。

## 多窗格

- 支持单窗格。
- 支持左右双窗格。
- 支持上下双窗格。
- 支持四宫格。
- 每个窗格可以打开独立目录。

## 文件浏览

- 可以浏览本地目录。
- 可以显示文件名称、图标、大小、类型、修改时间。
- 可以打开文件和文件夹。
- 可以刷新目录。

## 文件操作

- 可以复制。
- 可以移动。
- 可以重命名。
- 可以新建文件夹。
- 可以放入废纸篓。
- 文件冲突有提示。

## 交互

- 支持右键菜单。
- 支持核心快捷键。
- 支持窗格间拖拽。
- 支持 Quick Look。
- 支持地址栏跳转。

## 工作区

- 退出后可以恢复上次布局。
- 退出后可以恢复各窗格目录。

## 搜索

- 可以过滤当前目录文件名。

---

# 8. 代码质量要求

## 8.0 文件拆分和图标要求

### 单文件行数限制

项目中任何单个 Swift 文件都不能超过 **1000 行**。

如果某个文件接近或超过 1000 行，必须按职责拆分，例如：

- ViewController 拆分为主控制器、数据源、代理、菜单处理、快捷键处理。
- Service 拆分为协议、实现、错误类型、任务模型、工具方法。
- Provider 拆分为文件读取、文件操作、权限处理、路径工具。
- UI 组件拆分为独立 View、Cell、Header、Footer、Overlay。

AI 编程助手在每个阶段输出代码时，必须主动检查文件行数。如果预计某个文件会超过 1000 行，需要提前拆分，不得等到后续再重构。

### 图标要求

项目内所有功能图标优先使用 macOS 系统图标，即 **SF Symbols / NSImage system symbol**。

要求：

- 不引入第三方图标库。
- 不复制其他应用图标。
- 工具栏、侧边栏、菜单辅助图标均使用系统图标。
- 如果某个功能没有完全匹配的系统图标，选择语义相近的 SF Symbol。
- 图标封装在统一的 `AppIconProvider` 或类似工具类中，避免在各处硬编码 symbol 名称。

建议封装：

```swift
import AppKit

enum AppSymbol: String {
    case home = "house"
    case desktop = "macwindow"
    case documents = "doc.text"
    case downloads = "arrow.down.circle"
    case applications = "app"
    case folder = "folder"
    case file = "doc"
    case search = "magnifyingglass"
    case refresh = "arrow.clockwise"
    case trash = "trash"
    case copy = "doc.on.doc"
    case move = "arrow.right"
    case rename = "pencil"
    case preview = "eye"
    case grid = "square.grid.2x2"
    case list = "list.bullet"
}

struct AppIconProvider {
    static func image(_ symbol: AppSymbol, accessibilityDescription: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: accessibilityDescription)
    }
}
```

---

# 8. 代码质量要求

## 8.1 基础规范

- Swift 代码必须清晰命名。
- ViewController 不得承担大量业务逻辑。
- 文件操作必须通过 Service 和 Provider。
- UI 更新必须在主线程。
- 耗时操作必须 async。
- 错误必须可展示给用户。

## 8.2 错误处理

定义统一错误类型：

```swift
enum CloverError: LocalizedError {
    case directoryNotFound(URL)
    case permissionDenied(URL)
    case fileAlreadyExists(URL)
    case operationCancelled
    case unsupportedOperation
    case unknown(Error)
}
```

所有用户可见错误必须转成可读文案。

## 8.3 日志

建议添加：

```text
Logger.fileProvider
Logger.fileOperation
Logger.workspace
Logger.ui
Logger.dragDrop
```

## 8.4 测试

第一版至少添加以下测试：

1. LocalFileProvider 读取目录测试。
2. FileItem 排序测试。
3. 路径解析测试。
4. Workspace JSON 编码解码测试。
5. Rename 冲突检测测试，后续加入。
6. FileOperationService 基础 Mock 测试。

---

# 9. 设计注意事项

## 9.1 不要照抄其他产品

允许参考的只是功能类型，例如：

- 多窗格
- 工作区
- 地址栏
- 快捷键
- 文件操作队列
- 批量重命名
- 文件夹同步

不能复制：

- 第三方产品名称
- 图标
- 具体 UI 布局
- 文案
- 帮助文档
- 付费模块命名
- 视觉风格细节

## 9.2 macOS 体验要求

- 快捷键符合 macOS 用户习惯。
- 文件删除默认进入废纸篓。
- 永久删除必须确认。
- 双击行为遵守 Finder 习惯。
- 支持空格 Quick Look。
- 支持拖拽。
- 支持右键菜单。
- 支持菜单栏命令。

## 9.3 沙盒预留

即使第一版不开启 App Sandbox，也要预留：

- Security-scoped bookmark
- 用户授权目录
- Application Support 存储
- Keychain 存储远程密码

---

# 10. 推荐开发顺序总览

```text
1. 项目初始化
2. 主窗口布局
3. FileProvider 协议
4. LocalFileProvider
5. 单窗格文件列表
6. 文件夹进入和文件打开
7. 地址栏
8. 多窗格布局
9. 当前激活窗格管理
10. 基础文件操作
11. 右键菜单
12. 快捷键
13. 拖拽复制移动
14. 工作区保存恢复
15. 当前目录搜索
16. Quick Look
17. 图标视图
18. 第一版打磨和测试
19. 批量重命名
20. 文件夹同步
21. 暂存架
22. SFTP / WebDAV
23. 压缩包浏览
```

---

# 11. AI 执行时的输出格式要求

每完成一个阶段，AI 必须输出：

```text
阶段名称：
已完成内容：
新增文件：
修改文件：
关键实现说明：
如何运行：
如何测试：
已知问题：
下一步建议：
```

AI 不得只给解释，必须给出可运行代码或明确的代码修改。

---

# 12. 第一阶段推荐落地 Prompt

如果要现在开始开发，可以先把下面这段给 AI：

```text
请从阶段 1 开始执行 Clover 项目。

目标：创建一个 macOS Swift/AppKit 项目基础架构。

要求：
1. 创建主窗口 MainWindowController。
2. 窗口大小 1100x720。
3. 左侧 sidebar 宽度 220。
4. 右侧 content 区域用于后续放置多窗格。
5. 底部 status bar 高度 24。
6. 顶部 toolbar 先使用 NSToolbar 或自定义占位区域。
7. 创建计划书中推荐的目录结构。
8. 创建基础模型空文件，包括 FileItem、PaneState、Workspace、SidebarItem。
9. 创建 FileProvider 协议空定义。
10. 创建 LocalFileProvider 空实现。
11. 保证项目可以编译运行。

请输出：
- 需要创建的文件路径
- 每个文件的完整代码
- Xcode 中如何配置
- 运行后的预期效果
```

---

# 13. 后续商业化规划

第一版稳定后，可以考虑：

## 免费版

- 单窗格
- 双窗格
- 本地文件浏览
- 基础文件操作
- 基础搜索

## Pro 版

- 四窗格和更多布局
- 工作区
- 批量重命名
- 文件夹同步
- 暂存架
- SFTP / WebDAV
- 压缩包浏览
- 高级快捷键
- 自定义工具栏

## 终身版或订阅版

- 云盘连接
- 多设备配置同步
- 自动同步任务
- 插件系统
- 专业脚本能力

注意：商业化功能必须等基础体验稳定后再做。文件管理器最重要的是可靠，不能因为高级功能影响基础文件操作安全。

---

# 14. 最重要的开发原则

1. **文件安全优先**：任何删除、覆盖、批量操作都必须谨慎。
2. **UI 不能卡顿**：所有磁盘操作必须异步。
3. **多窗格是核心**：第一版必须把多窗格体验做好。
4. **工作区是差异点**：让用户可以快速恢复工作环境。
5. **Provider 抽象必须早做**：否则后续接远程、压缩包会非常痛苦。
6. **不要急着做高级功能**：先把本地文件管理做稳定。
7. **不要复制竞品 UI**：功能可参考，产品必须独立。

---

# 15. 一句话执行目标

先用 Swift + AppKit 做出一个稳定、流畅、支持多窗格和工作区恢复的本地文件管理器，再逐步扩展批量重命名、文件夹同步、暂存架、远程连接和压缩包浏览。

