# R1 + D1 架构改造冻结清单

> 范围：第二刀浅拆 + 多水管进水契约  
> 节奏：P1 分阶段  
> 红线：不改无感语义 / 不改 3·25·60 秒数字 / 不改 UI / 不改未关拦截 / 合并只搬家不改算法

## 成功标准

体感与 v742 一致：前台立刻更新、BLE 锁先动再 HTTP 收敛、无感边沿不变、假开门不回归。

## 禁止改语义（阶段 0–3 均冻结）

| 项 | 现状要点 |
|---|---|
| HTTP 权威 | `queryDefaultCarStatus` 全量；`mergeHTTPBaseState`；旧 `collectTime` 丢弃 |
| 前台轮询 | `vehicleHTTPPollInterval` 来自 `conditionPollTime`，夹在 2…10，默认 3 |
| 后台轮询 | 活跃 ~3 / 闲 25 / 同步关 60（`currentHTTPPollInterval`） |
| MQTT | 半包不直接盖门窗；电源/空调可即时；其余 `scheduleHTTPRefreshFromRealtime` |
| BLE 锁回写 | `applyLocalDoorLockState` + 15s `localDoorLockHoldSeconds` + 唤醒 HTTP |
| 无感 | `KeylessDecisionEngine` 条件；边沿/灰区/丢信号；未关不锁 |
| UI 出水 | `VehicleStateStore.apply` / `applyVehicleSnapshot` 真变才 `objectWillChange` |

## 多水管契约

```text
Pipe HTTP  → ingestHTTPAuthority → mergeHTTPBaseState → applyVehicleSnapshot
Pipe MQTT  → ingestMQTTStatusPayload →（电源/空调即时 / 其余叫醒 HTTP）
Pipe BLE   → ingestBLEDoorLockLocal / ingestBLEPowerLocal → apply* → 可叫醒 HTTP
                ↓
         唯一总表 state + dashboard
                ↓
         唯一出水 applyVehicleSnapshot / apply
```

## 阶段

| 阶段 | 内容 | IPA |
|---|---|---|
| 0 | 本冻结清单 | 可不单独出包 |
| 1 | 命名进水入口 + 调用点改走入口（行为不变） | v743 |
| 2 | Store 门面变薄、文件边界对齐（仍 D1） | 另包 |
| 3 | 收口旁路/注释 | 另包 |

## 明确不做（本里程碑）

- 第三刀线程模型
- 第四刀 UI 深拆
- 调轮询秒数 / 无感阈值
- 重写 merge 算法
