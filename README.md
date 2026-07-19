# Quota

[简体中文](README.zh-CN.md)

Quota is a lightweight macOS menu bar app for monitoring AI coding quota — [Codex](https://github.com/openai/codex) and [Grok](https://x.ai) (Grok Build / CLI).

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

> [!NOTE]
> **Codex:** requires Codex CLI, ChatGPT.app, or Codex.app, with an account that exposes rate limit data.  
> **Grok:** requires Grok CLI signed in (`grok login`). Some networks need a proxy to reach Grok billing.

## Features

- Menu bar popup for **Codex** (5-hour + weekly limits, reset credits) and **Grok** (weekly Build credits)
- Provider tabs: All / each enabled provider; enable up to 5 providers and drag to reorder in Settings
- First enabled provider (top of the list) is primary for Touch Bar when available
- macOS notifications when remaining quota is low (per provider / window)
- Automatic refresh every 2 minutes, plus manual refresh
- Proxy settings (useful for Codex app-server and Grok billing)
- Global hotkey to open the menu bar popup
- Languages: System, English, Simplified Chinese
- Accessory mode: no Dock icon

## Screenshots

English screenshots use the English UI. Chinese screenshots live in [README.zh-CN.md](README.zh-CN.md).

### Menu Bar

![Menu bar quota view](Docs/Images/menu-bar-en.png)

### Low Quota Notifications

![Low quota notifications](Docs/Images/notification-en.png)

### Touch Bar

![Touch Bar quota view](Docs/Images/touch-bar.jpg)

> Touch Bar is only available on Macs that include one. On newer MacBooks without a Touch Bar, use the menu bar popup.

## Installation

### Download DMG

Download the latest `Quota-*.dmg` from [GitHub Releases](https://github.com/slightlee/quota/releases), open it, and drag `Quota.app` into `Applications`.

### Build From Source

```bash
git clone https://github.com/slightlee/quota.git
cd quota
bash Scripts/package-app.sh
ditto .build/package/Quota.app /Applications/Quota.app
```

Then launch `Quota.app` from `Applications`.

To launch Quota at login:

**System Settings → General → Login Items → Add Quota**

Do not install the raw `.build/release/Quota` executable directly. Notifications, app icons, and bundled resources rely on the standard `.app` bundle structure.

## Usage

After launch, Quota appears in the menu bar. Wait a few seconds for the first refresh.

- Click the menu bar icon to open the popup
- Switch **All** / provider chips to filter the view
- While the popup is open: `⌘R` refresh · `⌘,` settings · `⌘Q` quit · `Esc` dismiss
- **Settings → Providers:** enable services (max 5), drag to reorder; the first enabled row is primary (leftmost tab; Touch Bar when present)

### Providers

| Provider | Data source | What you see |
|----------|-------------|--------------|
| **Codex** | Local `codex app-server` (`account/rateLimits/read`) | 5-hour + weekly windows; reset credits when available |
| **Grok** | Local `~/.grok/auth.json` + Grok CLI billing API | Weekly usage pool for Grok Build |

### Notification Thresholds

Default remaining-percent thresholds (each provider and window independently):

- Below 20%: warning
- Below 10%: urgent
- Below 5%: critical

Each threshold fires once per window until remaining recovers above 50%.

## Packaging

### Build `.app`

```bash
bash Scripts/package-app.sh
```

Output:

```text
.build/package/Quota.app
```

### Build `.dmg`

```bash
bash Scripts/package-dmg.sh
```

Output:

```text
.build/Quota-<version>.dmg
```

The DMG includes a Finder installer layout with `Quota.app` on the left and an `Applications` shortcut on the right. In CI environments where Finder scripting is unavailable, packaging falls back to a default DMG layout.

## How It Works

```text
                    ┌─────────────────────────────┐
                    │            Quota            │
                    │     (menu bar + settings)   │
                    └───────┬───────────┬─────────┘
                            │           │
           JSON-RPC stdio   │           │  HTTPS + local auth
           app-server       │           │  ~/.grok/auth.json
                            ▼           ▼
                   ┌──────────────┐  ┌──────────────────────────┐
                   │    Codex     │  │  Grok CLI billing API    │
                   │ (app-server) │  │  cli-chat-proxy.grok.com │
                   └──────────────┘  └──────────────────────────┘
```

- **Codex:** starts a local `app-server` child process and reads rate limits over JSON-RPC (stdin/stdout). Prefers `codex` on `PATH`, then the binary bundled with ChatGPT.app or Codex.app.
- **Grok:** reads the OIDC access token from `~/.grok/auth.json` (after `grok login`) and calls the same billing endpoint the Grok CLI uses for usage.
- Data refreshes about every 2 minutes.

## Privacy

Quota reads quota data on your machine through local CLI/login state and provider endpoints. It does not upload quota or account data to any third-party analytics service of its own.

Proxy, hotkey, language, and provider settings are stored locally in macOS app preferences.

## Troubleshooting

- **No menu bar icon:** launch `Quota.app` from `Applications`, not the raw `.build/release/Quota` binary.
- **No Codex data:** install Codex CLI, ChatGPT.app, or Codex.app; sign in with an account that exposes rate limits; ensure `codex` is on `PATH` or the app is in `/Applications`.
- **No Grok data:** run `grok login` so `~/.grok/auth.json` exists; if requests time out, enable a proxy (Settings → Proxy) on restricted networks.
- **No notifications:** allow notifications for Quota in System Settings (requires a proper `.app` bundle).

## Requirements

- macOS 14 Sonoma or later
- For Codex: Codex CLI, ChatGPT.app, or Codex.app + account with rate limit data
- For Grok: Grok CLI signed in (`grok login`)

## Development

```bash
# Run locally
swift run

# Build .app
bash Scripts/package-app.sh

# Build .dmg
bash Scripts/package-dmg.sh

# View debug logs
swift run 2>&1 | grep "\[Quota\]"
```

## Contributing

- Found an issue? Please open an [Issue](https://github.com/slightlee/quota/issues).
- Have a good idea? Pull requests are welcome via [Pull Requests](https://github.com/slightlee/quota/pulls).
- If Quota is useful to you, consider giving the project a star.

## Community

- [LINUX DO](https://linux.do)

## License

[MIT](LICENSE)
