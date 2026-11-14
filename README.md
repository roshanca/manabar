# ManaBar 🔵

**English** · [简体中文](README.zh-CN.md)

A macOS menu bar app that monitors usage across your AI coding subscriptions — the menu bar icon is a literal mana bar that drains as you burn quota and refills when the window resets.

Supports **Kimi Coding Plan**, **Claude Code**, **Codex** (ChatGPT subscription), **Devin**, and **DeepSeek**.

<a href="https://i.roshanca.com/img/2026/11/SCR-20261114-jpmg.png"><img src="https://i.roshanca.com/img/2026/11/SCR-20261114-jpmg.png" alt="ManaBar: Icons + % menu bar and the popover panel" width="410"></a>

## Features

### Menu bar — two styles

- **Mana bar**: fill level tracks the chosen provider's quota. Turns orange above 80%, blinking red above 95%, with an optional "Out of mana" easter-egg label at critical.
- **Icons + %**: one icon + percentage slot per enabled provider. Weekly windows carry a superscript ʷ, a slot with no data shows a dimmed `--`, and the same 80/95 coloring applies.
- Per-provider window choice: short cycle only (5h — daily for Devin), weekly only, or **Both**: two stacked bars, short cycle on top, weekly below. A window with no data keeps its empty track instead of pretending 0%. In Icons + % mode, *Both* displays whichever window is fuller.

### Popover panel

- One section per provider: a bar per quota window with its reset countdown, a plan badge (Kimi tier such as *Allegretto*, Claude *Max 5x*, Codex *Pro 20x*), plus account extras.
- Every bar carries a **pace tick** marking expected usage for the elapsed window — it turns orange when you're burning more than ~5pp ahead of pace.
- **Kimi** — booster credit balance and this month's booster spend. Add the optional kimi.com web session to also see the real recharge balance and a subscription-period meter.
- **Claude Code** — 5h and weekly windows, per-model weekly limits (e.g. *Sonnet weekly*), and extra-usage spend vs. monthly cap.
- **Codex** — flex credit balance, plus banked **rate-limit reset credits**: an expandable row listing each credit's expiry (severity dots: red <48 h, orange <7 d), and you can spend the earliest credit right from the panel — inline confirm, idempotent claim, count refreshes in place.
- **Devin** — daily and weekly windows plus the extra-usage (overage) balance.
- **DeepSeek** — wallet balance total with topped-up / granted breakdown and an estimated today's spend (computed locally from balance changes); orange below the low-balance threshold, red when exhausted; popover only, not shown in the menu bar.
- Header shows last-refresh age; footer has Refresh / Settings / Quit. Opening the popover always fetches fresh data. A failed refresh keeps the last snapshot under an orange *stale* badge — the panel never blanks out.

### Credentials & behavior

- Credentials are read-only against local files / the Keychain and never leave the machine. Refreshed tokens are written back atomically — safe alongside concurrent CLI usage.
- Zero CPU between refreshes.

## Build

```bash
brew install xcodegen   # once
make build              # xcodegen + xcodebuild
make install            # build and replace /Applications/ManaBar.app
make run                # install and launch
```

Or `xcodegen && open ManaBar.xcodeproj` and run from Xcode. Requires macOS 26+ / Xcode 27+.

### App icon

The app ships only `ManaBar/AppIcon.icon` (Icon Composer format): the system handles corner rounding and appearance variants. The source artwork lives in `Assets/Artwork.png`, uncropped.

Do not add an `AppIcon.appiconset` back. actool ignores same-named asset-catalog icons when a `.icon` exists anyway, and the old PNGs baked in a rounded mask plus transparent margin — a shape macOS 26+ insets on a gray glass plate (the "icon jail" ring) in any context that renders it.

For UI work and screenshots, `defaults write com.roshan.manabar debugShowPopover -bool true` (or `debugShowSettings`) opens the popover / settings in a regular window at launch.

## Credentials

| Provider | Source |
| --- | --- |
| Kimi | `~/.kimi-code/credentials/kimi-code.json` — created by signing in with the kimi CLI |
| Kimi web session (optional) | Paste your kimi.com `refresh_token` in Settings → unlocks the real booster recharge balance and the subscription meter. Grab it on kimi.com: DevTools → Console → `localStorage.getItem('refresh_token')`. Stored in the Keychain, valid ~90 days |
| Claude Code | macOS Keychain item `Claude Code-credentials` — the first read pops a system consent prompt, which is expected |
| Codex | `~/.codex/auth.json` — requires the ChatGPT sign-in flow; an API-key-only login exposes no usage data |
| Devin | Auto-discovered from `~/.local/share/devin/credentials.toml` or the Devin Desktop state DB; Settings shows which source matched |
| DeepSeek | API key pasted in Settings → stored in the Keychain |

## Settings

Per-provider enable toggles and menu-bar window (short cycle / weekly / both), menu bar style and which provider drives the mana bar, refresh interval (manual, 1/5/15/30/60 min — plus the Refresh button), used-vs-remaining display, launch at login, the "Out of mana" alert, the Kimi web-session token, the DeepSeek API key and low-balance threshold, and a readout of the detected Devin credential source.

## Acknowledgements

The Claude Code / Codex / Devin API contracts are adapted from [ai-usage-menubar](https://github.com/burakgon/ai-usage-menubar) (MIT), itself adapted from [OpenUsage](https://github.com/robinebers/openusage) (MIT); the pace-tick logic also comes from OpenUsage. See [NOTICE](NOTICE).
