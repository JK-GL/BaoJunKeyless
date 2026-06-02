# 宝骏无感车控

基于 SwiftUI 的 iOS 车辆 BLE 无感控制 App，支持 iOS 15+。

## 功能

- 🚗 **车辆状态** — 续航/电量/油量 · 电池仪表盘 · 温度监控 · 车门车窗状态 · BLE 钥匙信息
- 📡 **无感车控** — 解锁/上锁阈值设置 · 震动反馈(5种模式) · 无感开关 · 插件托管 · 智能切换
- 📋 **操作日志** — 时间线样式 · 按类型分类 · 支持清除
- ⚙️ **设置** — 深色模式 · 车辆信息 · 导入/导出配置 · 重置

## 构建

需要配置以下 GitHub Secrets：

| Secret | 说明 |
|--------|------|
| `CERTIFICATE_P12` | 签名证书 (base64) |
| `CERTIFICATE_PASSWORD` | 证书密码 |
| `PROVISIONING_PROFILE` | 描述文件 (base64) |
| `SIGNING_IDENTITY` | 签名身份 (如 `iPhone Distribution: XXX`) |
| `PROVISIONING_PROFILE_NAME` | 描述文件名称 |
| `TEAM_ID` | Apple Developer Team ID |

### 导出证书

```bash
# 从钥匙串导出 P12 证书并 base64 编码
security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -o cert.p12
base64 -i cert.p12 | pbcopy

# base64 编码描述文件
base64 -i profile.mobileprovision | pbcopy
```

Push 到 `main` 分支或手动触发 Actions 即可自动构建 IPA。

## 技术栈

- SwiftUI · iOS 15+ · XcodeGen · GitHub Actions
