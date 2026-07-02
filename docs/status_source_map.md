# BaoJunKeyless 状态来源总表

> 目的：明确每个字段来自哪里、谁覆盖谁，以及哪些变更**不会影响无感和快捷操作**。

## 设计原则

- **HTTP `carStatus`**：基础状态 / 仪表盘基线
- **HTTP `tirePressure`**：胎压 / 胎温专用来源
- **MQTT**：实时门窗 / 车锁 / 尾门 / 空调等增量覆盖
- **BLE query**：钥匙详情弹窗信息
- **Keyless / 快捷操作** 只依赖 `VehicleState` 的核心字段，不依赖 dashboard 文案排版。

---

## VehicleState（影响无感 / 快捷操作）

| 字段 | 主要来源 | 覆盖规则 | 影响 |
|---|---|---|---|
| `locked` | HTTP `doorLockStatus` + MQTT | MQTT 优先实时覆盖 | 无感 / 快捷操作 |
| `doorsClosed` | HTTP `doorOpenStatus` / `door1-4OpenStatus` + MQTT | MQTT 优先实时覆盖 | 无感 / 快捷操作 |
| `driverDoorOpen` | HTTP `door1OpenStatus` + MQTT | MQTT 优先实时覆盖 | 无感 |
| `trunkOpen` | HTTP `tailDoorOpenStatus` + MQTT | MQTT 优先实时覆盖 | 快捷操作展示 |
| `windowsClosed` | HTTP `windowStatus` / `window1-4Status` + MQTT | MQTT 优先实时覆盖 | 快捷操作展示 |
| `acOn` | HTTP `acStatus` + MQTT | MQTT 优先实时覆盖 | 快捷操作展示 |
| `acTemperature` | HTTP `accCntTemp` / `interiorTemperature` | HTTP 为主 | 快捷操作温度初值 |
| `gear` | HTTP `autoGearStatus` | HTTP 为主 | 无感判断 |
| `power` | HTTP `engineStatus` | HTTP 为主 | 无感 / 快捷操作 |
| `speed` | HTTP `speed/vehSpd/vehSpdAvgDrvn` + MQTT 若有 | MQTT 可覆盖 | 无感 / 状态页 |
| `physicalKeyPosition` | HTTP `keyStatus` | HTTP 为主 | 无感 |
| `bleRssi` | HTTP `bleRssi` | HTTP 为主 | 无感 |
| `phoneNearby` | 由 `physicalKeyPosition` 推导 | HTTP 为主 | 无感 |

### 说明

这些字段是**无感和快捷操作最敏感的核心字段**。本轮收口没有改字段语义，只改了来源合并方式，因此：

- **不会影响无感判断规则**
- **不会影响快捷操作按钮和确认弹窗入口**

---

## VehicleDashboardState（不直接影响无感）

### HTTP `carStatus` 基础字段

- 电池：`batteryRemainingText` / `batteryHealthPercentText` / `batteryVoltageText` / `batteryAuxText`
- 温度：`cabinTemperatureText` / `batteryTemperatureText` / `motorTemperatureText` / `inverterTemperatureText`
- 充电：`chargingStatusText` / `chargingPowerValueText` / `obcCurrentText` / `obcTemperatureText` / `chargingStateText`
- 行驶与能耗：`steeringAngleText` / `throttlePercentText` / `brakePercentText` / `totalMileageText` / `yesterdayMileageText` / `averageFuelConsumptionText` / `averagePowerConsumptionText`
- 灯光：`lowBeamText` / `highBeamText` / `leftTurnText` / `rightTurnText` / `positionLightText` / `frontFogText`

### HTTP `tirePressure` 专用字段

- `tireTemperatureText`
- `leftFrontTirePressureText`
- `rightFrontTirePressureText`
- `leftRearTirePressureText`
- `rightRearTirePressureText`

### MQTT 实时覆盖字段

- `lockStatusText`
- `doorStatusText`
- `windowStatusText`
- `tailgateStatusText`
- `driverDoorStatusText`
- `passengerDoorStatusText`
- `leftRearDoorStatusText`
- `rightRearDoorStatusText`
- `leftFrontWindowStatusText`
- `rightFrontWindowStatusText`
- `leftRearWindowStatusText`
- `rightRearWindowStatusText`
- `speedText`
- `acTemperatureText`（当 MQTT 仅回空调开关时表现为 开启/关闭）
- 若 MQTT 带胎压/胎温字段，也允许增量覆盖对应胎压/胎温字段

---

## 关键合并规则

### `mergeHTTPBase(...)`

只负责把 HTTP 基础状态补到 `VehicleState`，并且对实时布尔字段采取**保守写入**：

- 只在当前值为 `nil` 时补写 `locked/doorsClosed/windowsClosed/...`
- 避免 HTTP 慢速轮询反复压掉 MQTT 已知实时状态

### `mergeHTTPBaseDashboard(...)`

只负责写入 **HTTP 应该管理的仪表盘字段**：

- 电池 / 温度 / 充电 / 里程 / 油耗 / 灯光 等基础指标
- **不会整块覆盖 MQTT 实时门窗 / 车锁 / 尾门 / 明细门窗 / 胎压**

### `mergeRealtimeDashboard(...)`

只负责写入 **MQTT 实时字段**：

- 门窗锁尾门
- 单独门窗明细
- 胎压 / 胎温（若 MQTT 带）
- `speedText`
- `acTemperatureText`

---

## 胎压字段 key 收口

统一在 `VehicleStatusMapping.swift` 中维护：

- `TireCorner.leftFront`
- `TireCorner.rightFront`
- `TireCorner.leftRear`
- `TireCorner.rightRear`

并区分：

- `carStatusKeys`
- `tirePayloadKeys`

这样后续新增兼容 key 只改一处。

---

## 对无感和快捷操作的影响边界

### 不会影响的内容

- `KeylessDecisionEngine` 的判断规则
- 快捷操作按钮入口
- 快捷操作确认弹窗的真实状态显示
- `refreshNow()` 刷新行为

### 可能影响的内容

- 状态页展示更新顺序更稳定
- HTTP 不再整块冲掉 MQTT 实时门窗 / 胎压文案
- 胎压来源更清晰，维护成本更低

---

## 后续建议

1. 若继续新增状态字段，先确定归属：`VehicleState` 还是 `VehicleDashboardState`
2. 若字段有实时性，优先归入 MQTT patch
3. 若字段属于单独接口，优先新增 `xxxDashboard(from:base:)` 映射，而不是散落在调用处 patch
