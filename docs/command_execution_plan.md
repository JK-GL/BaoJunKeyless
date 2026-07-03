# BaoJunKeyless 执行层骨架说明

## 目的

在**不改变当前行为**的前提下，为后续：

- 无感自动解锁 / 上锁
- 快捷操作真实执行

建立统一命令模型和执行入口，避免两套链路分别实现。

---

## 当前骨架

### 统一命令模型

- `VehicleCommandKind`
- `VehicleCommandSource`
- `VehicleCommandTransportHint`
- `VehicleCommand`

### 执行结果模型

- `VehicleCommandExecutionState`
- `VehicleCommandExecutionResult`

### 执行器

- `VehicleCommandExecutor.executeFeedbackOnly(...)`
- `VehicleCommandExecutor.execute(...transport:refresher:)`
- `VehicleCommandExecutor.executeAsync(...transport:refresher:completion:)`

### transport 层

- `FeedbackOnlyTransport`
- `PlaceholderControlTransport`
- `HTTPControlTransport`（快捷操作使用；未确认 endpoint 会在草稿层阻止）
- `VehicleCommandAsyncTransport`

### 控制草稿层

- `VehicleControlRequestPlan`
- `VehicleControlRequestDraft`
- `makeVehicleControlRequestDraft(accessToken:vin:command:)`

---

## 当前行为

现阶段执行器已经进入**快捷操作 HTTP 试接**：

```text
快捷操作 → HTTPControlTransport → SGMW HTTP 控制草稿发送
无感 → 尚未接真实控制
```

快捷操作确认弹窗现在会等待执行层回调：

1. 生成 `VehicleCommand`
2. 使用 `HTTPControlTransport` 发送文档确认的 HTTP 请求
3. 请求成功后刷新车辆状态；失败/超时会在确认弹窗展示结果
4. 未确认 endpoint 的命令会在草稿层失败，不发送占位请求

这保证：

- 锁车 / 解锁 / 寻车 / 车窗 / 空调 / 快速降温进入真实 HTTP 试运行
- 远程启动只发送 `car/control/ignition/authorize` 授权请求，后续 BLE CMD 仍待确认
- 远程熄火因 `BLE_SPEC.md v7.1` 未提供云端 endpoint，暂不发送占位请求
- 无感决策链路暂不下发真实车控，避免误触发

---

## 后续接入方向

### 快捷操作

```text
CommandConfirmPopup
→ VehicleCommand
→ VehicleCommandExecutor
→ 真实控制接口
→ 回执 / 刷新 / UI
```

### 无感

```text
KeylessDecisionEngine.allow(...)
→ VehicleCommand(kind: .lock/.unlock, source: .keyless)
→ VehicleCommandExecutor
→ 真实控制接口
→ 回执 / 刷新 / 日志
```

---

## 当前明确缺口

### 1. 真实控制接口

当前快捷操作已按 `/var/minis/shared/BLE_SPEC.md v7.1` 收口到云端接口：

- 门锁：`POST car/control/doorLock`，锁车 `status=1`，解锁 `status=0`
- 寻车：`POST car/control/searchCar`，`status=0`
- 车窗：`POST car/control/window`，开窗 `status=0`，关窗 `status=1`
- 空调：`POST car/control/acc`，开空调 `status=6`，关空调 `status=7`
- 快速降温：`POST car/control/acc`，`status=4`，`temperature=17`，`blowerLvl=7`，`duration=10`
- 远程启动：`POST car/control/ignition/authorize` 只覆盖 PEPS 授权；真正启动的 BLE CMD 仍待确认
- 远程熄火：文档未提供云端 endpoint，当前禁止发送占位请求。

### 2. 控制回执

当前确认弹窗已能展示：

- sent / completed / failed / timeout 的基础结果
- `HTTPControlTransport` 返回的错误文案

仍缺少官方业务级命令 ID、车辆端最终执行完成回执与更精确的 timeout / polling 绑定。

### 3. 执行 transport 选择

后续需要根据真实能力决定：

- MQTT 控制
- HTTP 控制
- BLE 控制

目前统一留在 `VehicleCommandTransportHint` 中占位。

---

## 结论

当前骨架已经能保证：

- 快捷操作已可小范围验证 lock / unlock 的真实 HTTP 下发
- 后续加无感，不需要另起一套执行模型
- 后续扩展其它快捷操作真实执行，不需要推倒现有确认链路
- 只需继续校准 endpoint / body / 回执解析即可
