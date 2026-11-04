# ManaBar 🔵

[English](README.md) · **简体中文**

macOS 菜单栏 AI 配额监控器 — 实时显示多家 AI 编程订阅的用量，菜单栏图标是一条会消耗、会「回蓝」的魔法条。

支持：**Kimi Coding Plan**、**Claude Code**、**Codex**（ChatGPT 订阅）、**Devin**。

![ManaBar：Icons + % 菜单栏与 Popover 面板](https://i.roshanca.com/img/upic/25pSKB.png)

## 特性

### 菜单栏双样式

- **魔法条**：填充 = 选定服务商的配额消耗，>80% 变橙，>95% 变红闪烁，可配 "Out of mana" 彩蛋。
- **Icons + %**：每家一个「图标 + 百分比」条带；weekly 窗口带上标 ʷ，无数据的槽位显示暗色 `--`，数字同样 >80% 橙 / >95% 红。
- 每家可选菜单栏指标：短周期（5h，Devin 为 daily）、weekly，或 **Both** 双层同显（短周期在上、weekly 在下；某一窗口无数据时保留空槽位，绝不假装 0%）。Icons + % 下双层取较满窗口。

### Popover 面板

- 按服务商分区：每个配额窗口一条进度条 + 重置倒计时、套餐徽标（Kimi 会员档位如 Allegretto、Claude Max 5x、Codex Pro 20x）与各家附加信息。
- 每条进度条带 **pace tick**（消耗节奏标线）：标记窗口已流逝比例对应的「应然用量」，实际消耗超前节奏 ~5pp 以上时变橙。
- **Kimi**：booster 余额与本月加油包消费；配置可选的 kimi.com 网页会话后，可显示真实充值余额与订阅周期用量条。
- **Claude Code**：5h / weekly 窗口、按模型细分的 weekly 限额（如 Sonnet weekly），以及 extra usage 本月已用 / 上限。
- **Codex**：flex credits 余额，以及**可消费的 rate-limit reset 券**：展开行内列表查看每张券的到期时间（严重度圆点：红 <48h / 橙 <7d），可直接在面板里用掉最早一张 —— 内联确认、幂等请求、数量原地刷新。
- **Devin**：daily / weekly 窗口与 extra usage（透支）余额。
- 顶栏显示上次更新时间，底栏为 Refresh / Settings / Quit；打开面板即触发刷新。刷新失败保留上次数据并标记橙色 stale，面板绝不清空。

### 凭证与行为

- 凭证只读本机文件 / Keychain，绝不外传；token 刷新后原子写回（与 CLI 并发安全）。
- 刷新间隙零 CPU。

## 构建

```bash
brew install xcodegen   # 一次性
make build              # xcodegen + xcodebuild
make install            # 构建并替换 /Applications/ManaBar.app
make run                # 安装并启动
```

或直接 `xcodegen && open ManaBar.xcodeproj` 在 Xcode 里运行。要求 macOS 26+ / Xcode 27+。

### App 图标

macOS 26 使用 `ManaBar/AppIcon.icon`（Icon Composer 格式），由系统负责圆角和外观适配，避免旧式图标被套上额外外框。原始图案保存在其 `Assets/Artwork.png` 中，不预先裁圆角。

`AppIcon.appiconset` 保留带透明留白的 PNG 资源；更新图案后运行 `swift scripts/generate-app-icons.swift` 同步这 10 个尺寸。Xcode 构建时优先使用同名的 `.icon` 文件。

开发调试 / 截图时可用 `defaults write com.roshan.manabar debugShowPopover -bool true`（或 `debugShowSettings`）让 Popover / 设置以普通窗口启动。

## 凭证来源

| 服务商 | 来源 |
| --- | --- |
| Kimi | `~/.kimi-code/credentials/kimi-code.json`（kimi CLI 登录后自动获得） |
| Kimi 网页会话（可选） | 在设置页粘贴 kimi.com 的 `refresh_token` → 解锁真实 booster 充值余额与订阅周期用量条。获取方式：kimi.com → DevTools → Console → `localStorage.getItem('refresh_token')`。存入 Keychain，有效期约 90 天 |
| Claude Code | macOS Keychain `Claude Code-credentials`（首次读取会弹系统授权框，属正常） |
| Codex | `~/.codex/auth.json`（需 ChatGPT 登录方式，纯 API key 无用量数据） |
| Devin | 自动发现 `~/.local/share/devin/credentials.toml` / Devin Desktop 状态库；设置页只读显示命中的来源 |

## 设置

启用服务商及各家的菜单栏指标（短周期 / weekly / 双层）、菜单栏样式与魔法条显示哪家、刷新间隔（手动 / 1 / 5 / 15 / 30 / 60 分钟 + Refresh 按钮）、剩余/已用切换、登录启动、"Out of mana" 提醒、Kimi 网页会话 token、Devin 凭证来源显示。

## 署名

Claude Code / Codex / Devin 的接口契约改编自 [ai-usage-menubar](https://github.com/burakgon/ai-usage-menubar)（MIT），其自身改编自 [OpenUsage](https://github.com/robinebers/openusage)（MIT）；pace tick 逻辑同样来自 OpenUsage。详见 [NOTICE](NOTICE)。
