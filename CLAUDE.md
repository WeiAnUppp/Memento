# 忆物 — 复赛开发指南

## 项目概况

**忆物**是一款基于 AI 多模态视觉识别与空间记忆的物品查找 App。用户拍照记录物品后，App 自动提取物品语义特征与 GPS 位置，支持通过自然语言语音/文字搜索回忆物品位置。

- **App 名称**：忆物 / Memento
- **比赛**：第十一届（2026年）中国高校计算机大赛—移动应用创新赛
- **赛道**：启迪赛道（初赛→复赛→决赛）
- **复赛截止**：2026年8月10日（剩余约20天）
- **最低系统**：iOS 26（当前稳定版，Liquid Glass 设计语言）
- **开发状态**：从零开始

## 赛道评审要点

启迪赛道复赛 & 决赛评审标准：

| 维度 | 分值 | 重点 |
|------|------|------|
| 创新与特色 | 40 | 设计理念、界面、交互、可行性 |
| 前景评估 | 25 | 用户需求程度、市场欢迎度 |
| 作品基本参数 | 25 | 功能性、可靠性、流畅性 |
| 资料完整度 | 10 | 文档、视频质量 |

复赛提交物：作品说明文档（模板）+ 演示视频 + 可选提交部分源代码。

## 技术选型

| 层 | 技术 | 理由 |
|----|------|------|
| UI | SwiftUI | Apple 原生，声明式，适合新手 |
| 数据 | SQLite + sqlite-vec | 本地向量检索，隐私，零网络依赖 |
| 语音输入 | Speech framework | iOS 原生，中文支持，免费 |
| 语音输出 | AVSpeechSynthesizer | iOS 原生，中文 TTS，免费 |
| 地图 | MapKit + CoreLocation | iOS 原生 |
| 图像理解 | **小米 MiMo v2.5 API** | OpenAI 兼容，视觉理解强，中文友好 |
| 搜索查询解析 | **小米 MiMo v2.5 API** | 将模糊查询解析为结构化关键词 |
| 文本向量化 | Apple NaturalLanguage | iOS 原生，免费，端侧运行 |
| 端侧视觉 | FastVLM（文档留作未来方向） | 中文弱，20天来不及集成 |

### MiMo API 集成要点

- **端点**：`https://api.xiaomimimo.com/v1/chat/completions`
- **协议**：完全兼容 OpenAI Chat Completions，Swift 端用 `URLSession` + JSON 即可
- **模型**：`mimo-v2.5`（全模态旗舰，图片/文本理解 + 1M 上下文）
- **鉴权**：Bearer Token，用户自行在 App 设置页填写，存入本地 Keychain
- **用途**：① 图片→物品描述 ② 搜索查询→结构化关键词

```swift
// AIService 调用示例
let requestBody: [String: Any] = [
    "model": "mimo-v2.5",
    "messages": [
        ["role": "system", "content": "你是物品识别助手，分析图片中的物品，返回物品名称、外观特征、所在场景。"],
        ["role": "user", "content": [
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]],
            ["type": "text", "text": "请识别这张图片中的主要物品"]
        ]]
    ]
]
```

### 端侧策略说明

| 方案 | iOS支持 | 中文效果 | 当前可用 |
|------|---------|----------|----------|
| MiMo 端侧 (MiMo-VL-Miloco-7B) | ❌ 仅小米 HyperOS | ✅ | 不可用 |
| Apple FastVLM | ✅ | ❌ 中文弱 | 效果不够 |
| **MiMo Cloud API** | ✅ REST | ✅ | **当前主方案** |

**结论**：iOS 端目前没有一个能打的中文端侧视觉模型。MiMo 端侧模型是小米生态专属，FastVLM 中文识别弱。复赛阶段，MiMo Cloud API 是最务实的选择。文档和答辩中可强调：待苹果端侧模型中文能力成熟后（或 FastVLM 后续版本），可无缝迁移到端侧，实现完全离线隐私保护。

## MVP 核心功能（20天范围内）

### 必须跑通（P0）

1. **拍照记录物品** — 调用系统相机拍照
2. **AI 自动识别描述** — 图片发给 MiMo v2.5，返回物品名称、特征、场景描述
3. **GPS 自动标记位置** — 拍照时记录经纬度
4. **地图首页** — MapKit 展示所有物品标记，点击查看详情；右下角浮动拍照按钮
5. **浮动搜索按钮** — 独立圆形玻璃按钮浮于 TabView 上方，按下展开为搜索栏（文字输入 + 语音图标）
6. **混合搜索** — MiMo 解析查询为关键词 + Apple NL 向量检索 + 文本匹配，融合排序
7. **搜索结果展示** — 列表 + 地图定位 + TTS 语音播报

### 可以简化（P1）

8. **手动补充描述** — 语音或文字追加备注
9. **物品列表页** — 时间线方式浏览所有记录
10. **基础动画与转场** — Liquid Glass 风格转场
11. **设置页** — MiMo API Key 填写、基础偏好

### 文档里写、代码不做（P2）

12. **FastVLM 端侧模型** — 隐私保护未来方向
13. **室内 3D 空间建模** — 远期愿景
14. **多设备 iCloud 同步**
15. **智能收纳建议**
16. **无障碍（VoiceOver 等）**

## 架构设计

### 数据流

```
记录物品：
  拍照 → 本地存图 → Base64 上传 MiMo v2.5
      → 返回: {物品名称, 特征描述, 场景描述}
      → 描述文本用 Apple NL 向量化 → 存入 sqlite-vec
      → 原始描述文本 + GPS + 时间戳 → 存入 SQLite

混合搜索：
  语音/文字输入 → Speech → 查询文本
      → MiMo v2.5 解析 → 结构化关键词 {颜色, 物品, 位置...}
      → 查询文本 Apple NL 向量化 → sqlite-vec KNN (top-20)
      → 关键词在候选集中文本匹配加权
      → 融合排序 → 返回 top-5
      → 列表展示 + 地图定位 + TTS 播报
```

> **隐私设计**：图片仅在记录时上传 MiMo，之后仅保留本地缩略图。搜索链路中向量匹配完全离线，仅查询解析步骤调用 MiMo（仅传文本，不传图片）。

### 目录结构

```
Memento/                         # Xcode 项目名
├── App.swift                     # App 入口
├── ContentView.swift             # TabView 主容器
├── Models/
│   ├── Item.swift               # 物品数据模型
│   ├── SearchResult.swift       # 搜索结果模型
│   └── AIResponse.swift         # AI API 响应模型
├── Services/
│   ├── CameraService.swift      # 相机拍照
│   ├── LocationService.swift    # GPS 定位
│   ├── SpeechService.swift      # 语音识别 & TTS
│   ├── AIService.swift          # MiMo v2.5：图像理解 + 查询解析
│   ├── EmbeddingService.swift   # 文本向量化
│   └── DatabaseService.swift    # SQLite + sqlite-vec 操作
├── ViewModels/
│   ├── CaptureViewModel.swift   # 拍照 & 记录逻辑
│   ├── MapViewModel.swift       # 地图 & 标记逻辑
│   ├── SearchViewModel.swift    # 搜索逻辑
│   └── ItemDetailViewModel.swift
├── Views/
│   ├── Map/
│   │   ├── MapHomeView.swift    # 首页地图
│   │   └── ItemAnnotation.swift # 自定义地图标记
│   ├── Capture/
│   │   ├── CaptureView.swift    # 拍照界面
│   │   └── ItemPreviewView.swift # 拍照后AI识别结果预览
│   ├── Search/
│   │   ├── SearchTabView.swift   # 搜索 Tab（role: .search，TabBar 右侧圆形按钮）
│   │   ├── SearchBarView.swift   # 搜索栏组件
│   │   └── SearchResultView.swift # 搜索结果列表
│   ├── List/
│   │   └── ItemListView.swift   # 物品列表
│   ├── Detail/
│   │   └── ItemDetailView.swift # 物品详情
│   ├── Settings/
│   │   └── SettingsView.swift    # API Key 设置 + 偏好
│   └── Components/
│       ├── VoiceButton.swift    # 语音按钮组件
│       └── ItemCard.swift       # 物品卡片组件
├── Resources/
│   └── Assets.xcassets
└── Utils/
    ├── ImagePicker.swift        # SwiftUI 相机封装
    └── Extensions.swift         # 常用扩展
```

### 状态管理

每个页面一个 `@Observable` ViewModel，简洁直白：

```swift
@Observable
class MapViewModel {
    var items: [Item] = []
    var selectedItem: Item?
    var cameraPosition: MapCameraPosition = .automatic

    func loadItems() async { ... }
    func focusOnItem(_ item: Item) { ... }
}
```

### 数据库设计

> ✅ 已实现。MVP 阶段放弃 sqlite-vec（iOS 不支持动态加载 C 扩展），改用 **embedding BLOB + Accelerate 暴力搜索**，几百条数据亚毫秒级，足够用。

```sql
-- 单表设计，embedding 作为 BLOB 列，删物品自动删向量
CREATE TABLE items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    keywords TEXT,                -- JSON: {"颜色":"黑","物品":"盒子"}
    scene TEXT,                   -- 场景描述
    user_note TEXT,               -- 用户手动补充
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    image_path TEXT,              -- 本地图片路径
    embedding BLOB,               -- 512维 float32 向量
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

- **GPS 优先级**：照片 EXIF > 设备当前位置 > 0,0
- **图片存储**：Documents/MementoImages/ 目录，数据库只存文件名
- **线程安全**：DatabaseService 内部串行队列

## 20天开发计划

### 第1周：基础搭建（Day 1-5）

| 天 | 任务 | 产出 | 状态 |
|----|------|------|------|
| 1 | 创建 Xcode 项目，搭建目录结构，跑通 TabView | 项目骨架 | ✅ |
| 2 | DatabaseService：SQLite CRUD，embedding BLOB，图片磁盘管理 | 数据库层完成 | ✅ |
| 3 | ImagePicker：UIImagePickerController 封装，相机/相册 | 能拍照选图 | ✅ |
| 4 | LocationService：CoreLocation，MapHomeView 地图展示 | 地图+定位 | ✅ |
| 5 | iOS 26 Liquid Glass UI 框架搭建 | 设计系统 | ✅ |

### 第2周：核心闭环（Day 6-13）

| 天 | 任务 | 产出 | 状态 |
|----|------|------|------|
| 6-7 | AIService：MiMo v2.5 图像识别；EmbeddingService：Apple NL 向量化 | AI 链路通 | ✅ |
| 8 | CaptureViewModel + CaptureView：拍照→AI→预览→保存（照片EXIF GPS优先） | 记录物品闭环 | ✅ |
| 9 | MapViewModel + MapHomeView：DB加载物品，地图大头针，点击详情 | 地图闭环 | ✅ |
| 10 | SearchViewModel + SearchView：混合搜索 | 搜索 | ⬜ |
| 11 | SpeechService：语音识别 + TTS | 语音闭环 | ⬜ |
| 12 | ItemDetailView + ItemListView：详情页+列表页+滑动删除 | 详情+列表 | ✅ |
| 13 | 缓冲日 + 整体联调 | — | ⬜ |

### 第3周：交互打磨 + 视频（Day 14-20）

| 天 | 任务 | 产出 |
|----|------|------|
| 14-15 | Liquid Glass 交互打磨：`.glass` 材质、弹簧动画、触觉反馈、流畅转场 | 交互品质提升 |
| 16-17 | 整体流程测试、bug 修复、边界情况处理 | 稳定版本 |
| 18-19 | 录制演示视频（iPhone 录屏 + 配音/字幕） | 复赛视频 |
| 20 | 编写复赛作品说明文档 + 提交 | 完整提交包 |

## 关键设计决策

- [x] App 名称：**忆物 / Memento**
- [x] 搜索策略：**混合搜索**（MiMo 关键词解析 + Apple NL 向量 + 文本匹配加权）
- [x] API Key：用户自行在设置页填写，存入 UserDefaults（后续迁移 Keychain）
- [x] 最低系统：**iOS 26**（Liquid Glass 设计语言）
- [x] 向量方案：**embedding BLOB + Accelerate**（放弃 sqlite-vec，iOS 不支持动态加载 C 扩展）
- [x] GPS 来源：**照片 EXIF 优先** → 设备位置兜底
- [x] API 配置：**设置页预设多服务商**（MiMo/OpenAI/DeepSeek/智谱/通义千问等），选即填 URL+模型
- [x] 无障碍：MVP 不做
- [x] iCloud 同步：不做
- [x] 地图大头针视觉风格：蓝色 mappin.circle.fill + 玻璃胶囊名称标签
- [x] 列表页：ItemCard 缩略图卡片 + 滑动删除 + 下拉刷新
- [x] 列表页设计定稿（2026-07-23）：缩略图 + 名称 + 位置·时间，白色填充卡片 + 细线描边
- [ ] 物品分类体系（AI 自动分类 vs 用户手动标签）

## 当前实现笔记（2026-07-22）

### 已完成闭环（更新：2026-07-23）
```
点"+"打开菜单 → 相机/相册 → 底部栏变身记录模式
  → 输入描述文字（支持语音） → 点 ✨ 识别
  → ✨ 三阶段退出动画（键盘收起 → ✨缩进 → 搜索栏展开）
  → 左上角旋转圆点图标（SpinningDotsButton，所有页面可见）
  → MiMo v2.5 后台分析 + 自动保存
  → 旋转图标消失 + 地图自动定位到物品 GPS 坐标
```

旧流程（CaptureView 前台预览保存）保留作为 retry 兼容路径。

### 地图 & 大头针
- **MapKitView**：`UIViewRepresentable` 包裹 `MKMapView`（非 SwiftUI Map），原因：
  - SwiftUI Map 的 `Annotation` 手势被 MapKit 底层拦截，无法实现拖拽
  - MKMapView 的 annotation views 是独立 UIView，可自由添加 UIKit 手势
- **拖拽移动**：`UILongPressGestureRecognizer`（0.15s）+ 坐标转换 → 松手写库更新 GPS
- **点击详情**：`UITapGestureRecognizer`，「tap.require(toFail: longPress)」防止拖拽误触
- **Emoji 图标**：详情页 3 组 36 个 emoji 可选，「圆形蓝色底 + emoji」，拖拽时变橙色
- **原生聚类**：`clusteringIdentifier = "item"`，缩到一定级别自动聚合成数字圆圈
- **页面切换**：`ZStack + opacity` 保持视图存活，地图位置/缩放不丢失
- 隐藏比例尺/指南针、用户定位按钮、首次自动居中

### AI 集成
- 图片识别 prompt 增加 emoji 推荐字段，保存时自动写入 Item
- API 响应模型 `AIResponse` 含 `emoji: String?`
- 设置页支持 8 个预设服务商，完全兼容 OpenAI Chat Completions 协议

### 数据库
- 单表 items，含 emoji TEXT 列（旧表自动 ALTER TABLE 迁移）
- `updateLocation` / `updateEmoji` 专用更新方法
- DatabaseService 串行队列保证线程安全
- 图片存 Documents/MementoImages/，数据库只记文件名

### 列表页（2026-07-23 设计定稿）

**布局**：左侧 64×64 缩略图 + 右侧名称(.headline) + 下方位置·日期(.subheadline)
```
┌──────────────────────────────────────┐
│ ┌──────────┐                         │
│ │  缩略图  │  钥匙                    │
│ │  64×64   │  玄关 · 7月21日          │
│ └──────────┘                         │
└──────────────────────────────────────┘
```

**设计决策**：
- 内容层不用 glassEffect（符合设计原则第1条：玻璃仅用于导航/交互层）
- 卡片用 `.background(.background, in: RoundedRect)` 白色填充 + `.quaternary` 细线描边
- 列表页背景 `.systemGroupedBackground`，与设置页统一
- 列表行 `.listRowBackground(Color.clear)` 让页面背景透出
- 无图时显示 emoji 占位符（`item.emoji ?? "📦"`）

**全年龄/老年群体考量**：
- 最小字号 `.subheadline`（15pt），禁用 `.caption` / `.caption2`
- 日期用中文友好格式（`Date.friendlyChineseFormat`：今天/昨天/M月d日）
- 场景名直接显示，不用 icon+label 增加认知负担
- 卡片有清晰边框 + 白色填充，对比度高
- 64×64 缩略图够大，老年用户能看清

**日期格式化**（`Extensions.swift`）：
```swift
var friendlyChineseFormat: String {
    // 今天 HH:mm / 昨天 HH:mm / M月d日 / yyyy年M月d日
}
```

### 底部栏变身 — 记录物品融入搜索栏（2026-07-23 实现）

**设计目标**：消除"记录物品"独立 sheet 的割裂感，将记录功能融入底部搜索栏。

**架构**：
- `ContentView` 持有 `CaptureViewModel`，底部栏基于 `captureViewModel.state` 切换模式
- 拍照/选图后底部栏从搜索模式切换为记录模式，不再弹出 CaptureView sheet
- 照片卡片和 AI 结果作为浮层（overlay）显示在底部栏上方
- 顶部栏在记录时显示 ✕ 取消按钮，替代汉堡菜单

**底部栏模式对照**：

| CaptureState | 底部栏 | 浮层 |
|---|---|---|
| `.idle` / `.saved` | 搜索栏 `[🔍 搜索... 🎤] [+]` | 无 |
| `.readyForInput` | `[🎤 描述...] [📷+] [✨识别]` | PhotoCardStack |
| `.analyzing` | `[AI 正在识别… ⏳]` | AnalysisOverlay |
| `.backgroundAnalyzing` | 搜索栏 `[🔍 搜索... 🎤] [+]` | 无（正常地图 UI） |
| `.preview` | `[物品名称] [💾保存]` | AIResultOverlay |
| `.saving` | `[正在保存… ⏳]` | SavingOverlay |
| `.error` | `[🔄重试] [✕关闭]` | CaptureErrorOverlay |

**涉及文件**：
- `ContentView.swift` — 核心重构，底部栏模式切换 + 浮层 + 流程连接
- `Views/Components/CaptureOverlay.swift` — 提取的可复用 UI（PhotoCardStack, AnalysisOverlay, AIResultOverlay, CaptureErrorOverlay, SavingOverlay, AnalysisProgressSheet）
- `Views/Components/SpinningDotsButton.swift` — 左上角旋转圆点后台分析指示器（所有页面可见）
- `CaptureView.swift` — 保留文件但不再被 ContentView 使用（可后续清理）

### AI 后台分析 + 自动定位（2026-07-23 实现）

**设计目标**：点 ✨ 后立即退出记录页面，API 调用在后台运行，分析完成后自动保存并定位地图。

**核心变更**：
- `CaptureState` 新增 `.backgroundAnalyzing` case — API 调用中，UI 已退出
- `CaptureViewModel.proceedToAnalysis()` → 捕获数据 → 立即设 `.backgroundAnalyzing` → 启动后台 Task
- `performBackgroundAnalysis()` → API 调用 → 成功后自动调用 `saveItem()` → `.saved`
- 保存后 `MapViewModel.focusOnItem()` → 地图自动平移到物品 GPS 坐标

**旋转圆点指示器**：
- `SpinningDotsView`：8 个 SF Symbol `circle.fill` 圆点绕圆环旋转（7s 一圈，linear）
- `SpinningDotsButton`：50×50 玻璃圆按钮，`.tint(.primary)` 与筛选图标颜色一致
- 点击弹出 `AnalysisProgressSheet`（medium detent）：显示分析中图片 + 进度文字
- 分析完成后图标自动消失

**动画时序**：
```
有键盘时：键盘收起(0.28s) → ✨缩进(0.22s) → 搜索栏展开(0.40s)
无键盘时：✨缩进(0.22s) → 搜索栏展开(0.40s)  // 无键盘延迟，直接开始
```

**涉及文件**：
- `CaptureViewModel.swift` — `.backgroundAnalyzing` 状态、`performBackgroundAnalysis()`、`saveItem()`
- `ContentView.swift` — `isRecording` 排除 `.backgroundAnalyzing`、三阶段动画、进度 sheet
- `MapViewModel.swift` — `focusOnCoordinate()`、`focusTrigger`
- `MapHomeView.swift` / `MapKitView.swift` — 坐标聚焦参数传递
- `Views/Components/SpinningDotsButton.swift` — 新建
- `Views/Components/CaptureOverlay.swift` — `AnalysisProgressSheet`

### 待实现
- 搜索功能（Day 10）
- 语音播报 TTS（Day 11，语音输入已完成）
- Liquid Glass 动画打磨（Day 14-15，录制退出动画已完成）
- 演示视频录制（Day 18-19）

## 复赛文档 & 视频要点

### 文档重点补充（相比初赛）

- 技术实现细节：AI API 调用流程、本地向量检索原理、数据安全与隐私设计
- App 界面截图：至少 5 张核心页面
- 用户测试反馈：找 2-3 人试用并记录反馈
- 与初赛文档的呼应：承诺的功能实现了哪些

### 视频要点（建议3-5分钟）

1. **问题引入（30秒）**：一个人找不到东西的真实场景
2. **核心演示（2分钟）**：拍照记录 → AI 自动识别 → 地图查看 → 语音搜索 → 找到
3. **亮点展示（1分钟）**：模糊描述搜索、语音播报、隐私设计
4. **结尾（30秒）**：技术架构简述 + 未来展望

## iOS 26 设计系统（Liquid Glass）

iOS 26 引入了自 iOS 7 以来最大的设计变革。核心概念：控件像液体玻璃一样浮在内容上方，实时折射背景光线，随内容明暗自适应切换。

### 设计原则

1. **玻璃仅用于导航/交互层** — 地图上的浮动按钮、底部 TabBar、Sheet。内容层（列表、图片）不用。
2. **按钮组必须用 `GlassEffectContainer`** — 同一容器内的玻璃元素共享采样区域，视觉效果统一。
3. **着色克制** — `.tint()` 仅用于主操作按钮传达语义，不用于装饰。

### 忆物 App 中的应用

TabView 结构：三个标签页 + 独立浮动搜索按钮

```swift
// TabView — 地图、列表、设置
TabView {
    Tab("地图", systemImage: "map") { MapHomeView() }
    Tab("列表", systemImage: "list.bullet") { ItemListView() }
    Tab("设置", systemImage: "gearshape") { SettingsView() }
}

// 浮动搜索按钮 — 独立圆形玻璃按钮，浮于 TabView 上方
// 按下后展开为搜索栏（顶部横条：文字输入 + 右侧语音图标）
Button { /* 展开搜索栏 */ } label: {
    Image(systemName: "magnifyingglass")
}
.glassEffect(.regular.tint(.blue).interactive(), in: .circle)
.controlSize(.extraLarge)
.overlay(alignment: .bottom) {
    // 搜索栏（展开状态）：TextField + 语音按钮
    if isSearchActive {
        SearchBarView()
    }
}

// 地图首页 — 右下角浮动拍照按钮
Button { /* 拍照记录 */ } label: {
    Image(systemName: "camera.fill")
}
.glassEffect(.regular.interactive(), in: .circle)

// 拍照页 — 主操作按钮
Button("识别物品") { }
    .buttonStyle(.glassProminent)
    .tint(.blue)
    .controlSize(.extraLarge)

// AI 识别结果卡片
VStack { /* 物品信息 */ }
    .glassEffect(.regular, in: .rect(cornerRadius: 16))
```
```

### 关键 API 速查

| API | 用途 |
|-----|------|
| `.glassEffect(.regular, in: .capsule)` | 默认玻璃效果 |
| `.glassEffect(.regular.tint(.blue).interactive())` | 着色 + 触控响应 |
| `.glassEffect(.clear, in: .rect(cornerRadius: 16))` | 高透明度玻璃（图片背景用） |
| `GlassEffectContainer(spacing:)` | 包裹多个玻璃元素，统一采样 |
| `.buttonStyle(.glass)` | 半透明玻璃按钮 |
| `.buttonStyle(.glassProminent)` | 不透明白底玻璃按钮（主操作） |
| `.controlSize(.extraLarge)` | 新增大号控件尺寸 |

### 其他 iOS 26 新特性

- **`@Animatable`** 宏：自动合成 `animatableData`，自定义动画大幅减少代码
- **`PhotosPicker`**：系统拍照/选图原生支持，无需桥接 UIImagePicker
- **搜索栏**：`.searchable` 在 iPhone 上自动底部对齐，符合拇指操作区域
- **Toolbar 重设计**：图标默认单色，`ToolbarSpacer` 控制分组

## 编码规范

- 遵循 Apple Swift API Design Guidelines
- 遵循 iOS 26 Liquid Glass 设计语言（`.glass` 材质、流体动画）
- ViewModel 用 `@Observable` 宏（iOS 17+，iOS 26 完全兼容）
- 网络请求用 `async/await` + `URLSession`
- 敏感数据（API Key）存入 Keychain，不落 UserDefaults
- 图片用 `PhotosPicker`（iOS 26 原生支持）
- 所有用户可见文字用 `String(localized:)`（iOS 26 推荐方式）
- 错误处理用 `do-catch`，不 crash，给用户友好提示
- 提交粒度：每完成一个 Service/ViewModel/View 提交一次
