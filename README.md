# ManaBar 🔵

macOS 菜单栏 AI 配额监控器 — 实时显示多家 AI 编程订阅的用量，菜单栏图标是一条会消耗、会「回蓝」的魔法条。

支持：**Kimi Coding Plan**、**Claude Code**、**Codex**（ChatGPT 订阅）、**Devin**。

## 特性

- 菜单栏魔法条：填充 = 选定服务商的配额消耗，>80% 变橙，>95% 变红闪烁（可配 "Out of mana" 彩蛋）
- Popover 面板按服务商分卡片：5h / weekly 限额、重置倒计时、套餐名
- Kimi 卡片附 booster 余额与本月加油包消费；Claude 附 extra usage；Codex 附 flex credits 与 usage-limit reset 券（数量/可用数/最早到期）
- 失败保留上次数据并标记 stale；刷新间隙零 CPU
- 凭证只读本机文件 / Keychain，绝不外传；token 刷新后原子写回（与 CLI 并发安全）

## 构建

```bash
brew install xcodegen   # 一次性
make build              # xcodegen + xcodebuild
make install            # 构建并替换 /Applications/ManaBar.app
make run                # 安装并启动
```

或直接 `xcodegen && open ManaBar.xcodeproj` 在 Xcode 里运行。要求 macOS 26+ / Xcode 27+。

## 凭证来源

| 服务商 | 来源 |
| --- | --- |
| Kimi | `~/.kimi-code/credentials/kimi-code.json`（kimi CLI 登录后自动获得） |
| Claude Code | macOS Keychain `Claude Code-credentials`（首次读取会弹系统授权框，属正常） |
| Codex | `~/.codex/auth.json`（需 ChatGPT 登录方式，纯 API key 无用量数据） |
| Devin | 自动发现 `~/.local/share/devin/credentials.toml` / Devin 编辑器状态库；设置页只读显示命中的来源 |

## 设置

启用服务商、每家的菜单栏指标（5h / weekly / 双层同显）、菜单栏显示哪家、刷新间隔（1/5/15/30/60 分钟 + 手动）、剩余/已用切换、登录启动、Devin 凭证来源显示。

## 署名

Claude Code / Codex / Devin 的接口契约改编自 [ai-usage-menubar](https://github.com/burakgon/ai-usage-menubar)（MIT），其自身改编自 [OpenUsage](https://github.com/robinebers/openusage)（MIT）。详见 [NOTICE](NOTICE)。
