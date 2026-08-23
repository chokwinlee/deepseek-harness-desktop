# DSH Remote Android 开发与验收计划

Android 版是现有 DSH Desktop 的原生控制端，不运行第二套 Agent、仓库、终端或模型服务。Desktop、LAN bearer 代理、Tailscale Serve 和 Harness runtime 保持不变。

## 技术方案

- Kotlin、Jetpack Compose、Material 3 基础组件；可见产品层使用 DSH Remote 自己的克制设计语言。
- 单 Activity，基于 Compose Navigation 管理电脑、项目、会话、对话、轨迹和详情。
- Kotlin Coroutines 与 StateFlow 管理状态。
- Kotlin Serialization 解析协议，OkHttp 负责 HTTP 和 WebSocket。
- DataStore 保存普通配置，Android Keystore 保护局域网访问凭据。
- CameraX/ML Kit 扫描 Desktop 二维码。
- Photo Picker、受限图片解码与元数据清理处理图片提示词。
- NotificationManager 与受约束的后台工作只提供尽力而为的提醒，不宣称 App 被系统杀死后仍能实时在线。

## 功能对齐范围

1. 新鲜安装引导、离线 Demo、多电脑列表和删除本地数据。
2. 同一 Wi-Fi 扫码配对、Tailscale/自有 HTTPS 扫码或手输、深链导入和权威连接验证。
3. 项目与会话列表、归档过滤、运行和等待状态、新建会话。
4. 会话历史、流式恢复、文本 Prompt、queue/steer、停止任务。
5. 图片选择、剪贴板图片、压缩预检、消息内附件和失败重试。
6. `@` 文件与会话引用。
7. 审批、结构化问题和队列编辑。
8. 模型与 reasoning effort 选择。
9. Goal、Plan、轨迹、工具、diff 与详情。
10. 多层子代理浏览、补充消息和停止运行。
11. 英文、简体中文、明暗外观、大字体、TalkBack 和键盘安全区。

## 发布边界

- `applicationId`: `com.chokwinlee.dshremote`
- 最低版本：Android 8.0（API 26）
- 编译目标：仓库构建矩阵固定的稳定 Android SDK
- 不包含项目方 relay、账号系统、分析、广告、推送服务或模型网关。
- 首次交付以可复现 debug/release APK、JVM 测试和模拟器验收为准；Google Play 发布凭据和商店审核属于后续发布步骤。

## 验收门槛

- `testDebugUnitTest`、`lintDebug`、`validateDebugScreenshotTest`、`assembleDebug` 全部通过。
- Remote 协议 fixtures 在 Android 与 Desktop 测试中使用同一组请求、响应和事件样本。
- 模拟器完整走通 Demo、添加电脑错误恢复、项目/会话、对话、审批、模型、轨迹、子代理和删除数据。
- 至少一台真机验证扫码、局域网、Tailscale、图片、通知和进程恢复；未完成真机验证时必须明确标记，不以模拟器构建代替。
- README 英文和中文同步说明 Android 的源码、构建、安装、隐私与已验证边界。
