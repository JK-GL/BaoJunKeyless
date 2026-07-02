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

---

## 当前行为

现阶段执行器仍是：

```text
反馈型执行
```

即：

1. 生成 `VehicleCommand`
2. 调用 `VehicleCommandExecutor`
3. 只触发 `refreshNow()`
4. UI 继续显示“已反馈，状态以真实回报为准”

这保证：

- 不破坏现有快捷操作行为
- 不引入未知控制接口风险
- 不影响后续无感接入

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

源码中暂未发现已接入的真实车控 API 封装，只有：

- 状态查询
- 胎压查询
- BLE 钥匙查询
- MQTT token 查询

### 2. 控制回执

当前没有统一的：

- command request
- command result
- timeout / failed binding

### 3. 执行 transport 选择

后续需要根据真实能力决定：

- MQTT 控制
- HTTP 控制
- BLE 控制

目前统一留在 `VehicleCommandTransportHint` 中占位。

---

## 结论

当前骨架已经能保证：

- 后续加无感，不需要另起一套执行模型
- 后续加快捷操作真实执行，不需要推倒现有确认链路
- 只需继续在执行器中补 transport 和结果回执即可
