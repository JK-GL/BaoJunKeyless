# BaoJunKeyless Radar 13mini 内存暴涨修复记录

最后确认稳定版本：`6ccf2f6 perf: drive radar marker outside SwiftUI publishes`

对应 IPA：`/var/minis/workspace/BaoJunKeyless/BaoJunKeyless.ipa`

## 现象

iPhone 13 mini 上打开状态页 Radar 后，内存会持续上涨，严重时从一两百 MB 一路涨到 1GB+，最后卡顿甚至被系统杀掉。

iPhone 13 Pro Max 不明显，基本稳定在 170–200MB 左右。

后续稳定日志确认：

- 启动约 44–52MB
- 背景 + Radar 加载后约 70–76MB
- 在线车图开启 `sfCar=false` 时稳定在约 73MB
- Radar deinit 后约 74MB

## 已排除的原因

这些方向测试后不是主因：

1. 在线 PNG 车图不是主因
   - 加了 `雷达使用 SF 车图标` 开关。
   - `sfCar=true` 后仍然涨过，所以在线车图不是根因。

2. 自定义背景图 / 主题预览不是主因
   - 曾经加过 13mini 低内存轻量图片模式 `lightImages=true`。
   - 禁用背景大图和主题预览后仍然涨，所以撤回。

3. 车光环不是主因
   - 光环已去掉，问题仍出现过。

4. 陀螺仪不是直接主因
   - 当前 Radar 实际没有使用 pitch/roll。
   - 但之前 `MotionManager` 作为 `@ObservedObject` 传入 Radar，会造成无用 SwiftUI 刷新，所以也移除了。

## 真正问题

核心问题是：

```text
heading 高频更新
→ @Published relativeAngle 高频发布
→ SwiftUI 高频刷新 RadarRepresentable
→ updateUIView 频繁触发
→ Radar/UIImageView/layer 频繁更新
→ 13mini 内存持续增长
```

也就是说，问题不是“雷达车图本身很大”，而是**用 SwiftUI 的 @Published 高频驱动车图位置**。

13PM 性能/内存余量更大，看不明显；13mini 更容易暴露。

## 最终修复方法

### 1. 保留连续 heading 采样

为了车图移动流畅，不能退回：

```swift
manager.headingFilter = 5
```

因为这会导致车图 5° 一跳，肉眼看到一卡一卡。

当前保留：

```swift
manager.headingFilter = kCLHeadingFilterNone
```

这样方向数据连续。

### 2. 不再 @Published 高频发布 relativeAngle

以前：

```swift
@Published var relativeAngle: CLLocationDirection = 0
```

这会让每次方向变化都触发 SwiftUI 更新。

现在改成内部状态：

```swift
private(set) var radarDistance: CLLocationDistance = 0
private(set) var radarRelativeAngle: CLLocationDirection = 0
var radarPositionHandler: ((CLLocationDistance, CLLocationDirection) -> Void)?
```

Radar 位置不再通过 SwiftUI 刷新传递，而是直接回调 UIKit 视图。

### 3. 只低频 @Published 距离文字

SwiftUI 现在只负责显示距离文字：

```swift
@Published private(set) var distance: CLLocationDistance = 0
```

并且只有距离变化达到约 1 米才发布，避免文字频繁刷新。

### 4. RadarUIView 直接接收位置回调

`RadarRepresentable` 里绑定：

```swift
locationManager.radarPositionHandler = { [weak view] distance, relativeAngle in
    guard let view else { return }
    view.distance = distance
    view.relativeAngle = relativeAngle
    view.updatePosition()
}
```

这样车图移动还是实时的，但不会让整个 SwiftUI 页面高频刷新。

### 5. CADisplayLink 不常驻

以前进入窗口后就启动 displayLink，可能一直跑。

现在改成：

- 目标点变化才启动
- 车图追到目标点后停止
- 离开窗口 / dismantle 时释放

关键逻辑：

```swift
if targetChanged && !force {
    startMarkerDisplayLinkIfNeeded()
}
```

到位后：

```swift
applyMarkerFrame()
stopMarkerDisplayLink()
return
```

### 6. 避免重复设置同一张在线车图

在线车图缓存命中时，不再每次更新都重复：

```swift
carImageView.image = shared
```

而是判断不同才设置：

```swift
if carImageView.image !== shared {
    carImageView.image = shared
}
```

### 7. 移除 Radar 对 MotionManager 的依赖

Radar 当前没有使用陀螺仪 pitch/roll，所以不要把 `MotionManager` 作为 `@ObservedObject` 传进 Radar。

否则即使 Radar 不用陀螺仪，MotionManager 发布也会触发 SwiftUI 更新。

## 保留的诊断开关

### 雷达使用 SF 车图标

路径：

```text
设置 → 内存诊断 → 雷达使用 SF 车图标
```

用途：排查在线 PNG 车图是否有问题。

日志字段：

```text
sfCar=true / false
```

当前结论：在线车图不是主因，所以正式使用可以保持 `sfCar=false`。

## 不要再做的错误修复

1. 不要简单把 `headingFilter` 改回 5
   - 会让车图一卡一卡。

2. 不要用 `@Published relativeAngle` 高频驱动 SwiftUI
   - 这是 13mini 内存暴涨主因。

3. 不要让 `CADisplayLink` 常驻运行
   - 必须按需启动，到位停止。

4. 不要把无用的 `MotionManager` 注入 Radar
   - Radar 不用 pitch/roll 就不要观察它。

5. 不要误判成背景图/主题预览问题
   - 已用 `lightImages=true` 测试排除。

## 当前正确架构

白话版：

```text
手机方向传感器可以连续采样
但是不要让 SwiftUI 跟着每一帧刷新
只把车图位置直接告诉 UIKit 雷达视图
车图自己动
页面其他部分不动
```

也就是：

```text
LocationManager
→ radarPositionHandler
→ RadarUIView.updatePosition()
→ CADisplayLink 按需平滑移动
```

而不是：

```text
LocationManager @Published relativeAngle
→ SwiftUI 刷新
→ updateUIView
→ RadarUIView.updatePosition()
```

## 后续如果再出问题的排查方向

如果以后又出现 13mini 慢涨，可以加临时诊断开关：

```text
禁用雷达车图移动
```

也就是只显示雷达盘和固定车图，不启动 CADisplayLink。

判断：

- 静态雷达不涨：问题在车图移动 / layer frame 更新。
- 静态雷达还涨：问题在状态页其他 SwiftUI 内容或背景层。

但当前稳定版暂时不需要这个开关。
