# DSH Desktop v0.5.0

<!-- dsh-summary:zh -->
## 中文

- 内置 Harness 升级至官方 `0.1.5-rc.2`，同步运行时依赖、设置、引导流程和鉴权接口。上游版本仍为 Release Candidate。
- 首次启动会先备份并校验 DSH_HOME，再调用官方迁移器生成 V3 会话；原始日志保留。重复启动校验已有备份，设置页显示迁移结果和报告位置。
- 兼容现有 Remote v1 的会话、历史、问答与审批接口，修复网络重试可能重复提交同一条消息的问题；用量统计避免重复计算保留的旧日志。
- 已用真实模型验证桌面对话、文件读写、允许与拒绝审批、停止生成、重启续聊及迁移旧会话续聊；也验证了 Remote 问答、审批和 iOS 客户端的数据解码。
- **迁移限制：**实际历史样本中 31 份记录有 28 份迁移成功，3 份子任务日志因上游不支持 descriptor v2 而拒绝迁移。原件和备份完整保留，这 3 份仍需兼容的旧运行时读取。升级前请退出其他 DSH 进程，保留备份；回滚须使用独立的新 DSH_HOME，避免覆盖升级后的新工作。
- 本轮未完成手机真机、外部 Tailnet、附件上传、完整子任务生命周期和系统目录选择器验收。配套 Android APK 使用现有发布签名。

详见 [迁移与回滚说明](https://github.com/chokwinlee/deepseek-harness-desktop/blob/v0.5.0/docs/HARNESS_0.1.5_MIGRATION.md)及[实际功能验收记录](https://github.com/chokwinlee/deepseek-harness-desktop/blob/v0.5.0/docs/HARNESS_0.1.5_ACCEPTANCE.md)。
<!-- /dsh-summary:zh -->

<!-- dsh-summary:en -->
## English

- Bundle official Harness `0.1.5-rc.2`, including aligned runtime dependencies, settings, onboarding and authentication. The upstream runtime remains a release candidate.
- Back up and hash-verify DSH_HOME before the first migration, then use the official migrator to create V3 sessions while retaining original logs. Later launches verify the backup; settings expose migration counts and report paths.
- Adapt existing Remote v1 sessions, history, questions and approvals to the new gateway. Prevent duplicate prompt admission during retries and double-counting usage from retained log generations.
- Real-model acceptance covered desktop conversations, file writes and reads, approval and rejection, cancellation, restart recovery and continuing a migrated session. Remote questions and approvals and actual iOS client decoding were also verified.
- **Migration limitation:** 28 of 31 historical samples migrated; three child logs were refused because upstream does not support their descriptor v2. Originals and backups remain intact; those three still require a compatible older runtime. Quit other DSH processes before upgrading and retain backups. Restore into a separate, empty DSH_HOME when rolling back so new work is not overwritten.
- Physical mobile devices, external Tailnet access, attachments, the complete subagent lifecycle and the system directory picker were not fully accepted in this pass. The companion Android APK uses the existing release signing identity.

See the [migration and rollback guide](https://github.com/chokwinlee/deepseek-harness-desktop/blob/v0.5.0/docs/HARNESS_0.1.5_MIGRATION.md) and [functional acceptance record](https://github.com/chokwinlee/deepseek-harness-desktop/blob/v0.5.0/docs/HARNESS_0.1.5_ACCEPTANCE.md).
<!-- /dsh-summary:en -->
