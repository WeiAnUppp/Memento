# 忆物（Memento）

忆物是一款基于 AI 多模态理解与空间记忆的 iOS 物品查找 App。

用户可以拍照记录物品，应用会结合图片、用户描述和拍摄位置生成详细的物品档案；以后只需要输入或说出“卧室床头柜上的黑色耳机”这类自然语言，忆物就能从本地物品库中检索相关记录，并在地图上定位、用语音播报结果。

> 第十一届（2026 年）中国高校计算机大赛——移动应用创新赛启迪赛道 华东赛区 二等奖。

## 功能特性

- **拍照记录**：使用系统相机或从照片库选择一张或多张图片。
- **AI 物品识别**：识别物品名称、颜色、形状、材质、品牌、使用痕迹、周围物品和所在场景等信息。
- **用户补充描述**：支持在识别前输入文字或使用中文语音描述物品。
- **位置与时间记录**：优先读取照片中的 GPS 与拍摄时间；缺失时使用设备当前位置或当前时间作为兜底。
- **地图浏览**：在 MapKit 地图上查看物品位置，支持点击详情、拖动标记修改位置和原生标记聚类。
- **自然语言搜索**：支持文字和中文语音搜索，可识别物品、颜色、场景、附近关系、地点和时间表达。
- **混合检索排序**：将本地文本匹配、Apple NaturalLanguage 向量相似度和地理位置相关性融合排序。
- **搜索结果播报**：使用 `AVSpeechSynthesizer` 以中文语音播报搜索结果。
- **物品列表与详情**：以卡片和时间线方式查看记录，支持多图、备注、编辑位置、修改图标和删除记录。
- **多服务商配置**：支持 MiMo AI、OpenAI、Azure OpenAI、DeepSeek、Moonshot、智谱 GLM、通义千问以及自定义 OpenAI 兼容接口。
- **Liquid Glass 界面**：使用 iOS 26 的玻璃材质、浮动搜索栏、后台分析状态和交互动画。

## 技术架构

```text
拍照/选图
   │
   ├── 本地保存图片
   ├── 读取 EXIF / PHAsset GPS 与拍摄时间
   └── 图片 + 用户描述
          │
          ▼
   OpenAI 兼容视觉 API
          │
          ├── 物品名称与摘要
          ├── 详细外观描述
          ├── 场景与位置标签
          ├── 结构化关键词
          └── 周围物品
          │
          ▼
   Apple NaturalLanguage 生成文本向量
          │
          ▼
   SQLite 本地存储

自然语言/语音查询
   │
   ├── API 解析关键词、地点和时间
   ├── Apple NaturalLanguage 生成查询向量
   ├── SQLite 读取物品与向量
   ├── 文本匹配 + 余弦相似度 + 地理距离融合
   └── 结果列表 + 地图定位 + 中文 TTS
```

### 主要技术

| 模块 | 技术 |
| --- | --- |
| UI | SwiftUI、iOS 26 Liquid Glass |
| 地图 | MapKit、CoreLocation |
| 相机与照片 | AVFoundation、Photos、PhotosUI 相关封装 |
| AI 图像理解 | OpenAI Chat Completions 兼容 API |
| 语音输入 | Speech framework |
| 语音输出 | AVFoundation `AVSpeechSynthesizer` |
| 本地向量化 | NaturalLanguage `NLEmbedding` |
| 本地数据 | SQLite3 |
| 向量检索 | Accelerate / `vDSP` 余弦相似度 |
| 状态管理 | Observation `@Observable` |

应用不依赖 sqlite-vec 动态扩展，而是将向量以 BLOB 保存到 SQLite，并在本地使用 Accelerate 完成暴力检索。对于个人物品数量有限的使用场景，这种方案部署简单且足够高效。

## 运行环境

- macOS，安装 Xcode 26 或更高版本
- iOS 26.5 或更高版本
- Swift 5
- iPhone 或 iPad 真机（完整功能建议使用真机）
- 一个可用的 OpenAI Chat Completions 兼容视觉模型 API Key

项目当前部署配置：

- 最低系统：iOS 26.5
- Bundle Identifier：`work.goufu.Memento`
- 支持设备：iPhone、iPad
- 当前版本：`1.0 (1)`

## 开始使用

### 1. 克隆并打开项目

```bash
git clone <repository-url>
cd Memento
open Memento.xcodeproj
```

如果项目目录名称不同，请将 `cd` 路径替换为实际路径。

### 2. 配置签名

在 Xcode 中选择项目 `Memento`，进入 **Signing & Capabilities**：

1. 选择自己的 Apple Developer Team。
2. 确认 Bundle Identifier 唯一，必要时修改为自己的标识符。
3. 选择一台已连接的 iPhone 或 iPad 作为运行设备。

### 3. 配置 AI 服务

首次运行后进入：

```text
设置 → AI 服务
```

选择服务商后，应用会自动填入默认 API 地址和推荐模型；然后填写 API Key。也可以选择“自定义”，手动填写：

- API Base URL
- API Key
- Model

默认 MiMo 配置如下：

```text
Base URL: https://api.xiaomimimo.com/v1
Model: mimo-v2.5
```

应用请求的是兼容 OpenAI Chat Completions 协议的接口，实际模型和 URL 应以所选服务商的官方文档为准。没有配置 API 时，部分搜索流程可以回退到本地文本匹配，但图片 AI 识别和完整的查询解析无法使用。

### 4. 授予系统权限

根据使用的功能，首次操作时需要允许：

- 相机：拍摄物品照片
- 照片库：选择已有照片
- 定位：记录物品所在位置和进行地点搜索
- 麦克风：语音输入
- 语音识别：将中文语音转换为文字

拒绝权限后，相关功能会不可用，但不会影响其他本地页面的使用。

## 基本操作流程

### 记录物品

1. 在地图首页点击右下角的添加按钮。
2. 选择拍照或从照片库选择图片，可添加多张图片。
3. 输入补充描述，或点击麦克风进行语音描述。
4. 点击识别按钮，等待 AI 在后台分析。
5. 分析完成后，物品会自动保存到本地数据库并出现在地图上。

### 查找物品

1. 点击底部浮动搜索栏。
2. 输入自然语言，或点击麦克风直接说出要查找的物品。
3. 等待搜索完成，查看匹配结果。
4. 点击结果可查看详情，或使用定位功能在地图上查看物品位置。
5. 点击播报按钮，使用中文语音听取结果。

示例查询：

```text
黑色的充电宝
卧室床头柜上的东西
前天在办公室记录的钥匙
键盘旁边的白色物品
```

## 数据与隐私

- 物品记录、图片和搜索向量默认保存在设备本地。
- 图片只在进行 AI 图像识别时上传到用户配置的 API 服务商；识别完成后仍保留本地图片。
- 搜索中的向量相似度计算在设备端完成，不需要上传本地物品库。
- 如果使用 AI 查询解析，搜索文本会发送到用户配置的 API 服务商。
- API 地址、模型名称和 API Key 当前通过 `UserDefaults` 持久化保存，应用设置页不会将其上传到项目作者的服务器。生产发布前建议将 API Key 迁移到系统 Keychain。
- 本项目不包含作者提供的默认 API Key，也不会在源码中提交任何密钥。

## 项目结构

```text
Memento/
├── MementoApp.swift                 # App 入口
├── ContentView.swift                # TabView 与全局浮动交互
├── Models/
│   ├── AIResponse.swift             # AI 响应与搜索解析模型
│   ├── APIConfig.swift              # 服务商、模型和 API 配置
│   ├── Item.swift                   # 物品数据模型
│   └── SearchResult.swift            # 搜索结果模型
├── Services/
│   ├── AIService.swift              # 图片识别与查询解析
│   ├── DatabaseService.swift        # SQLite CRUD 与向量存储
│   ├── EmbeddingService.swift       # NaturalLanguage 文本向量化
│   ├── LocationService.swift        # 定位服务
│   ├── SearchIndexService.swift     # 本地搜索索引维护
│   └── SpeechService.swift          # 语音输入
├── ViewModels/
│   ├── CaptureViewModel.swift       # 记录流程与后台分析
│   ├── ItemDetailViewModel.swift    # 详情页逻辑
│   ├── MapViewModel.swift           # 地图与物品标记
│   └── SearchViewModel.swift        # 混合搜索与排序
├── Views/                           # 地图、搜索、列表、详情、设置等界面
└── Utils/                           # 图片选择器与通用扩展
```

## 构建与验证

在 Xcode 中选择 `Memento` scheme 后，可以使用 `⌘R` 构建并运行。

也可以通过命令行构建：

```bash
xcodebuild \
  -project Memento.xcodeproj \
  -scheme Memento \
  -sdk iphonesimulator \
  -configuration Debug \
  build
```

完整功能验证建议覆盖以下场景：

- 相机拍照与照片库选图
- 单图和多图 AI 识别
- 有 EXIF GPS 与无 GPS 的照片
- 文字搜索、语音搜索和地点搜索
- “今天”“昨天”“前天”等时间查询
- 地图标记点击、拖拽和聚类
- AI 分析期间切换页面、取消记录和网络失败
- 未配置 API Key、无定位权限和无语音权限

## 当前限制与后续方向

- Apple NaturalLanguage 对较短中文文本的向量区分度有限，未来可引入更适合中文的本地 embedding 模型。
- AI 图像识别和查询解析依赖用户配置的网络 API。
- API Key 当前保存在 `UserDefaults`，后续应迁移到 Keychain。
- 当前搜索结果以列表为主，后续可增加所有结果的地图总览。
- 可继续增加物品分类、标签体系、搜索历史、自动补全和推荐。
- FastVLM 或其他中文端侧视觉模型成熟后，可迁移图像识别链路，实现更完整的离线隐私保护。
- iCloud 同步、室内 3D 空间建模和智能收纳建议暂不属于当前 MVP 范围。
