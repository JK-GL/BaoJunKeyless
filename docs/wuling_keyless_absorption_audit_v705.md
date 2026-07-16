# BaoJunKeyless v705 对 Wuling 1.0.81 无感与后台能力吸收审计

## 1. 设置接线矩阵

| 设置项 | UI | Codable | 运行时消费者 | 当前语义 | 结论 |
|---|---|---|---|---|---|
| 无感总开关 | 有 | 有 | Store / BackgroundExecutionManager | 关闭时停 BLE 与后台能力 | 完整 |
| 增强后台执行 | 有 | 有 | `beginBackgroundTask` | 只控制短时后台任务；不关闭独立围栏/BLE/定位开关 | 完整，但名称易被理解成总开关 |
| 电子围栏预唤醒 | 有 | 有 | `CLCircularRegion` | 车辆位置圆心；进入唤醒 BLE，离开降活跃度 | 完整 |
| 围栏半径 | 有 | 有 | 主围栏及停车备用围栏 | 50–500m，停车备用最小 100m | 完整 |
| 仅围栏内扫描 | 有 | 有 | `shouldSuppressAutomaticBLEScan` | 主围栏外停自动扫描；forceBLE/已连接会话例外 | 完整 |
| 停车位置备用唤醒 | 有 | 有，默认关 | 停车围栏 + 显著位置变化 | 固定停车点、离开后再进入、只预唤醒 | 部分完整：未跨进程持久化 |
| 定位保活 | 有 | 有 | `startUpdatingLocation` | 圈内/BLE 活跃/已鉴权时按需开启 | 完整；WhenInUse 时后台能力有限 |
| 后台状态同步 | 有 | 有 | HTTP/MQTT 调度 | 开：活跃3s/空闲25s；关：活跃25s/空闲60s | 已接线，但“关”是降频而非完全停止 |
| 后台折叠状态 | 有 | 有 | 纯 UI | 记忆展开状态 | 完整 |

## 2. Wuling 能力吸收对照

| Wuling 能力 | BaoJunKeyless v705 | 结论 |
|---|---|---|
| BLE 已鉴权后的 connected RSSI 决策 | 只有鉴权后 live RSSI 进入无感；广播 RSSI 只预览 | 已完整吸收，更安全 |
| connectRSSI / unlockRSSI / lockRSSI 三阈值 | 当前只有解锁/上锁动作阈值；精确目标一发现即连接 | 未吸收 connectRSSI，需实车耗电/连接数据后再决定 |
| 自动动作 cooldown | `cmdInterval` + 一次性接近边沿 + 负 ACK 周期抑制 | 已吸收且更强 |
| D/R 禁止解锁 | 当前已知非 P 均拒绝 | 已吸收且更保守 |
| RSSI 弱才上锁 | 三段 RSSI，只有离开区 live 弱信号才计时 | 已完整吸收且更安全 |
| RSSI 丢失/陈旧上锁分支 | 明确禁止信号丢失上锁 | 不吸收 Wuling 激进分支 |
| post-unlock 超时自动上锁 | 当前持续状态机，无固定到期强锁 | 不吸收；当前逻辑更安全 |
| 停车点 100m 围栏 | 独立默认关闭的停车备用唤醒 | 已吸收主体，持久性不足 |
| 显著位置变化 | 仅停车备用开关开启时监听，由远到近预唤醒 | 已吸收 |
| CoreBluetooth state restoration | RestoreIdentifier + 恢复后清旧鉴权、完整重鉴权 | 已完整吸收且更安全 |
| pending-connect | 记录创建/扫描/连接/鉴权/失败与耗时 | 部分吸收：运行期可观察，但未跨进程持久化/TTL 接力 |
| 后台失败重连 | 断连、连接失败、绑定失败会回扫描 | 主体已吸收；未使用 Wuling 的持久 pending 接力 |
| 后台 service-filtered scan fallback | 当前以 manufacturer/MAC 的未过滤扫描为主 | 未吸收，需先确认车辆广播包含 181A/182A 服务再加 |
| BGTaskScheduler 车况刷新 | 当前只有短后台任务、定位和 BLE restoration | 未吸收；可作为机会型补充，不能保证准时 |
| 锁态来源优先级 | BLE 即时回写、HTTP 原始最终确认、MQTT 仅唤醒 | 已吸收且更强 |
| 负 ACK 分类 | `FFFF/39D6` 同随机数即时拒绝、离开再靠近恢复 | BaoJunKeyless 更强 |
| 外部锁车保护 | 外部锁态跃迁后必须离开再靠近 | BaoJunKeyless 更强 |
| 门窗未关策略 | 门尾预检可开关；车窗不阻断；锁后 HTTP 原始检查并提醒 | 按用户车型需求优化，不照搬 Wuling |
| 电源判断 | 只信明确字段/BLE 回包，不用 P/钥匙/空调猜 | BaoJunKeyless 更严谨 |

## 3. 仍建议吸收（按优先级）

### P0：停车点与 pending-connect 持久化

1. 将停车点坐标、半径、生成时间、是否已离开写入小型 UserDefaults 状态；
2. App 被系统杀死后，由区域事件/CoreBluetooth restoration 恢复；
3. 加 TTL（建议 24h 或下一次明确停车点覆盖）；
4. 只在“车辆位置新鲜”或“车旁 BLE 已鉴权 + P挡/静止”时更新停车点；
5. pending-connect 持久化：原因、创建时间、最后阶段、尝试次数；
6. 到期只清状态，不直接控车。

### P0：后台定位权限语义收紧

- 主围栏若用于后台触发，应把 Always 作为可靠工作状态；
- WhenInUse 可以前台展示，但设置页需明确“后台围栏受限”；
- 权限不足时不应只显示泛化错误，要指出受影响的具体开关。

### P1：后台服务过滤扫描回退（条件实施）

先通过 BLE 广播日志确认目标车辆稳定广告 `181A/182A`。确认后：

```text
后台 unfiltered 长时间无发现
→ 退回 service-filtered [181A,182A]
→ 找到后仍按 manufacturer MAC / 绑定 UUID 验证
```

若车辆不广告这些服务，不应强行吸收，否则会漏车。

### P1：BGAppRefreshTask 机会型补充

用途仅为：

- 刷新一次 HTTP 状态；
- 清理过期 pending-connect；
- 重新挂载停车/车辆围栏；
- 不直接锁解。

注意：iOS 不保证执行时间，不能替代 CoreBluetooth/区域监控。

### P2：connectRSSI（暂缓）

需先收集：广播 RSSI、开始连接 RSSI、鉴权成功率、耗时和耗电。当前精确目标发现即连接能保证响应；贸然加 connectRSSI 可能让后台靠近延迟。

## 4. 明确不吸收

- RSSI 丢失或陈旧就上锁；
- 固定 post-unlock 超时后强制上锁；
- 未开围栏时分钟级扫描冷却；
- 围栏/显著位置变化直接锁解；
- 用 P 挡、keyStatus、空调状态猜测电源；
- 车辆拒绝后只等待固定秒数再次自动重试。

## 5. 下一步实车验证

1. App 在车旁恢复：不应自动解锁；
2. 真实走远再返回：只消费一次接近边沿；
3. 灰区徘徊：不锁不解；
4. RSSI 丢失：不锁；持续弱 RSSI：达到 lockDelay 后才锁；
5. 外部锁车：保持车旁不反解锁；
6. BLE 负 ACK：显示拒绝且当前周期不重试；
7. 锁/解 BLE ACK 后，HTTP 原始 `doorLockStatus` 最终确认；
8. 停车备用开启：离开后再进入只预唤醒，不直接控车；
9. App 被系统杀死后测试停车区域事件和 pending-connect 是否还能恢复（当前预期为部分能力，P0 待补）。
