# 忆物 / Memento — 开发日志

## 2026-07-24

### 🎨 思考图标颜色对齐筛选图标
- **文件**：`Views/Components/SpinningDotsButton.swift`
- **问题**：左上角后台分析旋转圆点（`Circle` 形状）没有显式颜色，裸 `Circle()` 不受 `.tint(.primary)` 影响（tint 仅作用于 SF Symbol 模板图像），导致圆点颜色与筛选按钮（`line.horizontal.3.decrease`）不一致。
- **修复**：给 `Circle()` 添加 `.fill(.primary)`，圆点颜色现在与筛选图标统一。

### 🚀 保存性能优化 — 增分插入
- **文件**：`ContentView.swift`、`MapViewModel.swift`、`MapHomeView.swift`
- **问题**：AI 后台分析保存后调用 `mapViewModel.loadItems()` 整表重查，保存瞬间主线程阻塞，地图刷新卡顿。
- **修复**：新增 `MapViewModel.addSavedItem(_:)` 增分插入，保存后直接追加新物品而不重查全表，地图立即出针。

### 🎬 旋转圆点消失动画优化
- **文件**：`ContentView.swift`
- **问题**：旋转圆点消失时使用 `.scale.combined(with: .opacity)`，收缩过程中 glassEffect 每帧重采样背景，与保存瞬间的地图刷新叠加导致卡顿。
- **修复**：消失动画改为纯 `.opacity` 淡出，出现保持缩放弹入。`showSpinningDots` 独立于 ViewModel 状态，支持平滑动画。

### 📍 照片 GPS 提取修复
- **文件**：`CameraHalfView.swift`、`PhotoHalfView.swift`、`ContentView.swift`
- **问题**：拍照/选图后 GPS 永远为 `nil`，所有物品回退到设备当前位置。
- **修复**：相机从 JPEG 数据提 EXIF GPS，相册取 `PHAsset.location`，回调传递 `CLLocationCoordinate2D?`。

### 🕐 物品记录时间修复
- **文件**：`ContentView.swift`、`CaptureViewModel.swift`
- **问题**：`createdAt` 永远是保存时刻，照片原始拍摄时间被丢弃。
- **修复**：相册取 `PHAsset.creationDate`，相机取 `nil` → fallback `Date()`。

### 🔍 时间搜索精确日支持
- **文件**：`AIResponse.swift`、`AIService.swift`、`SearchViewModel.swift`
- **问题**：搜索"前天的东西"返回全部，AI 无"前天"映射值。
- **修复**：`TimeFilter` 新增 `daysAgo: Int?`，prompt 补充精确日映射表。

### 📝 AI 图片分析详细度增强
- **文件**：`AIService.swift`
- **问题**：AI 返回描述太简短（"黑色手机，长方形"），搜索匹配细节太少。
- **修复**：重写 system prompt，描述 ≥150 字、场景 ≥80 字、关键词 8 维度、nearby_objects 3-8 个，max_tokens 1024→2048。

### 🎯 保存后地图定位时序优化
- **文件**：`ContentView.swift`
- **修复**：保存后延迟 0.45s 再定位地图（等旋转圆点消失动画播完），避免两个动画抢主线程。
