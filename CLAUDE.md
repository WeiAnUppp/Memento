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

```sql
-- 主表
CREATE TABLE items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,                    -- AI 识别的物品名
    description TEXT,             -- AI 生成的完整描述
    keywords TEXT,                -- AI 提取的结构化关键词（JSON: {"颜色":"黑","物品":"盒子","位置":"床头柜"}）
    scene TEXT,                   -- 场景描述（房间类型等）
    user_note TEXT,               -- 用户手动补充
    latitude REAL,
    longitude REAL,
    image_path TEXT,              -- 本地图片路径
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- 向量表（sqlite-vec vec0 虚拟表）
-- Apple NL NLEmbedding 维度待运行时确定，先设占位值
CREATE VIRTUAL TABLE item_embeddings USING vec0(
    embedding float[512]
);
-- embedding 行 id 与 items 表 id 对应
```

## 20天开发计划

### 第1周：基础搭建（Day 1-5）

| 天 | 任务 | 产出 |
|----|------|------|
| 1 | 创建 Xcode 项目，配置 SPM 依赖（SQLiteVec），搭建目录结构，跑通 TabView | 项目骨架 |
| 2 | DatabaseService 实现：建表、CRUD、sqlite-vec 初始化 | 数据库层完成 |
| 3 | CameraService + ImagePicker：调用系统相机、保存图片到本地 | 能拍照存图 |
| 4 | LocationService：CoreLocation 获取 GPS，MapHomeView 基础地图展示 | 地图能显示当前位置 |
| 5 | 缓冲日 + 代码 Review + 修 bug | — |

### 第2周：核心闭环（Day 6-13）

| 天 | 任务 | 产出 |
|----|------|------|
| 6-7 | AIService：封装 MiMo v2.5 两个调用（图片→描述、查询→关键词）；EmbeddingService：Apple NL 文本向量化 | AI 链路通 |
| 8 | CaptureViewModel + CaptureView：拍照 → AI识别 → 预览 → 保存 | 记录物品闭环 |
| 9 | 地图标记展示：从数据库加载物品，MapKit 标注经纬度 | 地图首页能看标记 |
| 10 | SearchViewModel + SearchView：混合搜索（关键词解析 + 向量检索 + 融合排序） | 能搜到物品 |
| 11 | SpeechService：语音识别集成到搜索，TTS 播报搜索结果；SettingsView：API Key 设置 | 语音闭环 + 设置 |
| 12 | ItemDetailView：点击标记/搜索结果查看物品详情 | 详情页 |
| 13 | 缓冲日 + 整体联调 | — |

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
- [x] API Key：用户自行在设置页填写，存入 Keychain
- [x] 最低系统：**iOS 26**（Liquid Glass 设计语言）
- [x] 无障碍：MVP 不做
- [x] iCloud 同步：不做
- [ ] 地图标记的视觉风格（默认 pin vs 自定义图标）
- [ ] 物品分类体系（AI 自动分类 vs 用户手动标签）

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
