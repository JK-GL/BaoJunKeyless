# 无感蓝牙车控决策规则设计

本文档用于后续实现 BaoJunKeyless 的无感蓝牙车控逻辑，重点说明：

- BLE 负责判断手机与车辆距离趋势。
- MQTT 负责提供车辆实时状态。
- 决策引擎负责判断是否允许解锁/上锁。
- 日志系统负责记录“为什么执行 / 为什么拒绝”。

目标：避免只靠 RSSI 误判，降低误解锁、误上锁风险。

---

## 1. 总体架构

推荐架构：

```text
BLE RSSI / 手机靠近远离
        ↓
MQTT VehicleState / 车辆状态
        ↓
KeylessDecisionEngine / 无感决策引擎
        ↓
VehicleEventLogStore / 车辆事件日志
        ↓
CommandSender / 解锁、上锁、寻车等命令发送
```

原则：

```text
BLE 判断“人在哪里”
MQTT 判断“车现在能不能执行”
决策引擎判断“该不该执行”
日志记录“为什么执行 / 为什么拒绝”
```

---

## 2. MQTT 车辆状态建议

MQTT 可以作为车辆实时状态来源。建议状态分 topic 发送，或者统一发 JSON。

### 2.1 建议 topic

```text
baojun/{carId}/state
baojun/{carId}/ble
baojun/{carId}/keyless/event
baojun/{carId}/command
baojun/{carId}/command/result
```

### 2.2 建议 VehicleState JSON

```json
{
  "ts": 1717650000,
  "online": true,
  "locked": true,
  "doorsClosed": true,
  "driverDoorOpen": false,
  "trunkOpen": false,
  "gear": "P",
  "power": "off",
  "speed": 0,
  "physicalKeyInside": false,
  "bleRssi": -52,
  "phoneNearby": true
}
```

### 2.3 字段说明

| 字段 | 类型 | 说明 |
|---|---|---|
| `ts` | Int | 状态时间戳 |
| `online` | Bool | MQTT/车辆是否在线 |
| `locked` | Bool | 当前是否已上锁 |
| `doorsClosed` | Bool | 所有车门是否关闭 |
| `driverDoorOpen` | Bool | 主驾门是否打开 |
| `trunkOpen` | Bool | 后备箱是否打开 |
| `gear` | String | P/R/N/D/unknown |
| `power` | String | off/acc/on/ready/unknown |
| `speed` | Double | 车速 |
| `physicalKeyInside` | Bool? | 物理钥匙是否在车内；拿不到则 unknown/null |
| `bleRssi` | Int? | 手机 BLE RSSI |
| `phoneNearby` | Bool | 根据 BLE 判断手机是否靠近 |

---

## 3. 数据模型建议

后续 Swift 可以按下面结构实现。

### 3.1 VehicleState

```swift
struct VehicleState {
    var timestamp: Date
    var online: Bool
    var locked: Bool?
    var doorsClosed: Bool?
    var driverDoorOpen: Bool?
    var trunkOpen: Bool?
    var gear: VehicleGear
    var power: VehiclePowerState
    var speed: Double?
    var physicalKeyInside: Bool?
    var bleRssi: Int?
    var phoneNearby: Bool
}
```

### 3.2 档位

```swift
enum VehicleGear: String {
    case p = "P"
    case r = "R"
    case n = "N"
    case d = "D"
    case unknown
}
```

### 3.3 电源状态

```swift
enum VehiclePowerState: String {
    case off
    case acc
    case on
    case ready
    case unknown
}
```

### 3.4 决策结果

```swift
enum KeylessDecision {
    case allow(action: KeylessAction, reason: String)
    case deny(action: KeylessAction, reason: String)
    case wait(action: KeylessAction, reason: String)
}

enum KeylessAction {
    case unlock
    case lock
}
```

---

## 4. BLE 判断策略

BLE RSSI 不应该直接等于“解锁/上锁”，只能作为距离趋势输入。

### 4.1 建议阈值

| 行为 | 默认值 | 说明 |
|---|---:|---|
| 解锁阈值 | -48 dBm | RSSI 高于该值认为靠近 |
| 上锁阈值 | -72 dBm | RSSI 低于该值认为远离 |
| 上锁延迟 | 15 秒 | 远离后等待再上锁 |

### 4.2 必须做迟滞

避免 RSSI 抖动导致反复触发。

```text
靠近：RSSI >= unlockThreshold 持续 N 次 / N 秒
远离：RSSI <= lockThreshold 持续 N 次 / N 秒
```

不要每次 RSSI 更新都写日志。建议只记录状态变化：

```text
手机进入解锁范围
手机离开解锁范围
手机进入上锁范围
RSSI 信号丢失
```

---

## 5. 解锁规则

### 5.1 允许解锁的推荐条件

```text
手机靠近
车辆在线
车辆已锁
车速 = 0
档位 = P 或 unknown 但车辆 power=off
车辆未处于 ready/on 行驶状态
```

推荐逻辑：

```text
phoneNearby == true
locked == true
speed == 0
power == off
gear == P
```

### 5.2 应拒绝解锁的条件

| 条件 | 结果 | 日志原因 |
|---|---|---|
| 手机不在范围 | 拒绝 | RSSI 未达到解锁阈值 |
| 车辆不在线 | 拒绝 | MQTT 状态离线 |
| 状态过期 | 拒绝 | 车辆状态超过有效时间 |
| 已解锁 | 拒绝 | 车辆已解锁，无需重复执行 |
| 档位 D/R/N | 拒绝 | 档位不允许无感解锁 |
| 车辆 ready/on | 拒绝 | 车辆非熄火状态 |
| 车速 > 0 | 拒绝 | 车辆行驶中 |

### 5.3 解锁日志示例

```text
[Keyless] 解锁允许 | rssi=-47 threshold=-48 locked=true gear=P power=off
[Keyless] 解锁拒绝 | reason=档位 D 不允许无感解锁
[Keyless] 解锁拒绝 | reason=车辆状态超过 10 秒未更新
```

---

## 6. 上锁规则

自动上锁比自动解锁更危险，规则必须更保守。

### 6.1 允许上锁的推荐条件

```text
手机远离
车辆在线
车辆未锁
所有车门关闭
后备箱关闭
车辆熄火
车速 = 0
档位 = P
物理钥匙不在车内
远离状态持续达到上锁延迟
```

推荐逻辑：

```text
phoneFarAway == true
locked == false
doorsClosed == true
trunkOpen == false
speed == 0
power == off
gear == P
physicalKeyInside != true
lockDelayReached == true
```

### 6.2 应拒绝上锁的条件

| 条件 | 结果 | 日志原因 |
|---|---|---|
| 手机未远离 | 拒绝 | RSSI 未达到上锁阈值 |
| 车辆已上锁 | 拒绝 | 已上锁，无需重复执行 |
| 任一车门未关 | 拒绝 | 车门未关闭 |
| 后备箱开启 | 拒绝 | 后备箱未关闭 |
| 车辆未熄火 | 拒绝 | 电源状态不允许上锁 |
| 档位非 P | 拒绝 | 档位不允许上锁 |
| 车速 > 0 | 拒绝 | 车辆非静止 |
| 物理钥匙在车内 | 拒绝 | 检测到物理钥匙在车内 |
| MQTT 状态过期 | 拒绝 | 状态过期，禁止自动上锁 |

### 6.3 上锁日志示例

```text
[Keyless] 上锁等待 | 手机远离，等待 15s
[Keyless] 上锁允许 | rssi=-76 threshold=-72 doorsClosed=true gear=P power=off
[Keyless] 上锁拒绝 | reason=检测到物理钥匙在车内
[Keyless] 上锁拒绝 | reason=主驾门未关闭
```

---

## 7. 物理钥匙判断

### 7.1 如果 MQTT 能提供钥匙位置

最理想：

```json
"physicalKeyInside": true
```

策略：

```text
physicalKeyInside == true → 禁止自动上锁
physicalKeyInside == false → 可继续判断其他条件
```

### 7.2 如果只能知道钥匙存在

例如：

```json
"keyDetected": true
```

但不知道内外。

推荐保守策略：

```text
keyDetected == true → 禁止自动上锁
```

避免误锁。

### 7.3 如果拿不到物理钥匙状态

如果 MQTT 没有物理钥匙状态，则不能假装知道。

推荐策略：

```text
physicalKeyInside == nil
→ 不作为上锁允许条件
→ 日志里标记 key=unknown
→ 可提供设置项：未知钥匙状态是否允许自动上锁
```

默认建议：

```text
未知钥匙状态：允许解锁，但上锁更保守
```

---

## 8. MQTT 状态新鲜度

任何决策都要检查状态是否过期。

建议：

```text
状态更新时间超过 10 秒 → 拒绝自动解锁/上锁
```

原因：

```text
车辆状态过期时，档位/车门/钥匙状态都不可信
```

日志：

```text
[Keyless] 解锁拒绝 | reason=车辆状态 18s 未更新
```

---

## 9. 决策引擎伪代码

### 9.1 解锁

```swift
func evaluateUnlock(state: VehicleState, settings: KeylessSettings) -> KeylessDecision {
    guard settings.keylessEnabled else {
        return .deny(action: .unlock, reason: "无感开关关闭")
    }
    guard settings.unlockEnabled else {
        return .deny(action: .unlock, reason: "解锁开关关闭")
    }
    guard state.isFresh else {
        return .deny(action: .unlock, reason: "车辆状态过期")
    }
    guard state.phoneNearby else {
        return .deny(action: .unlock, reason: "手机未进入解锁范围")
    }
    guard state.locked == true else {
        return .deny(action: .unlock, reason: "车辆未上锁")
    }
    guard state.speed ?? 0 == 0 else {
        return .deny(action: .unlock, reason: "车辆非静止")
    }
    guard state.gear == .p else {
        return .deny(action: .unlock, reason: "档位不是 P")
    }
    guard state.power == .off else {
        return .deny(action: .unlock, reason: "车辆未熄火")
    }
    return .allow(action: .unlock, reason: "满足无感解锁条件")
}
```

### 9.2 上锁

```swift
func evaluateLock(state: VehicleState, settings: KeylessSettings) -> KeylessDecision {
    guard settings.keylessEnabled else {
        return .deny(action: .lock, reason: "无感开关关闭")
    }
    guard settings.lockEnabled else {
        return .deny(action: .lock, reason: "上锁开关关闭")
    }
    guard state.isFresh else {
        return .deny(action: .lock, reason: "车辆状态过期")
    }
    guard state.phoneFarAway else {
        return .deny(action: .lock, reason: "手机未离开上锁范围")
    }
    guard state.locked == false else {
        return .deny(action: .lock, reason: "车辆已上锁")
    }
    guard state.doorsClosed == true else {
        return .deny(action: .lock, reason: "车门未关闭")
    }
    guard state.trunkOpen != true else {
        return .deny(action: .lock, reason: "后备箱未关闭")
    }
    guard state.speed ?? 0 == 0 else {
        return .deny(action: .lock, reason: "车辆非静止")
    }
    guard state.gear == .p else {
        return .deny(action: .lock, reason: "档位不是 P")
    }
    guard state.power == .off else {
        return .deny(action: .lock, reason: "车辆未熄火")
    }
    guard state.physicalKeyInside != true else {
        return .deny(action: .lock, reason: "物理钥匙在车内")
    }
    return .allow(action: .lock, reason: "满足无感上锁条件")
}
```

---

## 10. 日志设计

车辆事件日志用于给用户和开发排查“为什么执行/为什么拒绝”。

### 10.1 建议分类

当前已经预留：

```text
system
ble
keyless
plugin
action
warning
error
```

### 10.2 BLE 日志节流

不要每个 RSSI 都写日志。

建议只记录：

```text
开始扫描
发现目标车辆
连接成功
断开连接
进入解锁范围
离开解锁范围
进入上锁范围
信号丢失
```

### 10.3 决策日志必须记录 reason

每次拒绝都要记录原因：

```text
[Keyless] 解锁拒绝 | reason=档位不是 P
[Keyless] 上锁拒绝 | reason=物理钥匙在车内
[Keyless] 上锁等待 | reason=远离未满 15s
```

这样用户反馈“为什么没解锁/没上锁”时，可以直接看日志。

---

## 11. 设置项建议

后续设置页可以增加“安全规则”：

```text
仅 P 挡允许无感操作：开
车辆未熄火禁止上锁：开
车门未关禁止上锁：开
钥匙在车内禁止上锁：开
状态过期禁止自动操作：开
未知钥匙状态允许上锁：关
```

默认建议全部保守。

---

## 12. 测试矩阵

后续实现后至少测试：

| 场景 | 预期 |
|---|---|
| 手机靠近，车锁，P 挡，熄火 | 允许解锁 |
| 手机靠近，车已解锁 | 不重复解锁 |
| 手机靠近，档位 D | 拒绝解锁 |
| 手机远离，车未锁，门已关，P 挡，熄火 | 延迟后允许上锁 |
| 手机远离，门未关 | 拒绝上锁 |
| 手机远离，钥匙在车内 | 拒绝上锁 |
| MQTT 状态超过 10 秒未更新 | 拒绝自动操作 |
| RSSI 抖动在阈值附近 | 不反复解锁/上锁 |
| BLE 断开但 MQTT 在线 | 不直接执行，记录信号丢失 |
| MQTT 离线但 BLE 近 | 拒绝自动操作 |

---

## 13. 实施顺序建议

建议后续按这个顺序开发：

1. `VehicleState` 数据模型
2. `MQTTVehicleStateStore`，负责接收并解析 MQTT 状态
3. `BLENearbyStateStore`，负责 RSSI 和靠近/远离判断
4. `KeylessDecisionEngine`，只负责规则判断
5. `VehicleEventLogStore` 接入决策日志
6. `CommandSender`，负责真正发送解锁/上锁命令
7. 设置页增加安全规则配置

原则：

```text
先只记录决策，不真实发命令
确认日志正确后，再开放真实执行
```

---

## 14. 当前结论

后续无感蓝牙车控不要只靠 BLE RSSI。

推荐最终判断必须同时参考：

```text
BLE 距离趋势
MQTT 车辆状态
用户安全配置
状态新鲜度
物理钥匙状态
档位/电源/车门/车速
```

所有允许或拒绝都写入车辆事件日志，方便排查。
