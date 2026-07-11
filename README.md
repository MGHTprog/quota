# Quota

[简体中文](README.zh-CN.md)

Quota is a lightweight macOS menu bar app for monitoring [Codex](https://github.com/openai/codex) rate limits.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

> [!NOTE]
> Quota requires Codex CLI or ChatGPT.app, and your account must expose valid rate limit data.

## Features

- Menu bar quota overview for Codex 5-hour and weekly limits, plus reset credits when available
- Touch Bar display when Terminal, ChatGPT, Codex, or IntelliJ IDEA is the active app
- macOS notifications when quota is running low
- Automatic refresh every 2 minutes, plus manual refresh
- Proxy settings for Codex app-server connectivity
- Global hotkey for opening the menu bar popover
- Language switcher with System, English, and Simplified Chinese options
- Accessory app mode: no Dock icon
- Reads quota data through Codex `app-server`, preferring `codex` from `PATH` and falling back to the copy bundled with ChatGPT.app, then legacy Codex.app

## Screenshots

### Menu Bar

![Menu bar quota view](Docs/Images/menu-bar-en.png)

### Low Quota Notifications

![Low quota notifications](Docs/Images/notification-en.png)

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

**System Settings -> General -> Login Items -> Add Quota**

Do not install the raw `.build/release/Quota` executable directly. Notifications, app icons, and bundled resources rely on the standard `.app` bundle structure.

## Usage

After launch, Quota appears in the macOS menu bar. Wait a few seconds for the first quota refresh.

- Click the menu bar icon to view 5-hour, weekly, and reset credit details
- Click `Refresh` or press `⌘R` to refresh manually
- Click `Settings` to configure proxy, global hotkey, and language options
- Click `Quit` or press `⌘Q` to exit

Touch Bar appears only when Terminal, ChatGPT, Codex, or IntelliJ IDEA is the active app.

### Notification Thresholds

Quota sends low-quota notifications at these default remaining-percent thresholds:

- Below 20%: warning
- Below 10%: urgent
- Below 5%: critical

Each threshold is notified once per quota window. Notification state resets after the remaining quota recovers above 50%.

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
┌──────────────┐     JSON-RPC (stdio)     ┌──────────────┐
│              │ ◄──────────────────────► │              │
│    Quota     │   account/rateLimits/    │    Codex     │
│              │         read             │ (app-server) │
└──────┬───────┘                          └──────┬───────┘
       │                                         │
       ▼                                         ▼
 ┌──────────────────────────┐             ┌──────────────────────┐
 │ MenuBarController        │             │ TouchBarController   │
 │ + MenuBarLimitView       │             │ + TouchBarLimitView  │
 └──────────────────────────┘             └──────────────────────┘
```

Quota starts Codex `app-server` as a child process and reads quota data, including reset credit availability when exposed by the account, through JSON-RPC over stdin/stdout. It refreshes quota data every 2 minutes.

## Privacy

Quota reads Codex rate limit data locally through Codex `app-server`. It does not upload quota data or account information to any third-party service.

Proxy, hotkey, and language settings are stored locally by macOS app preferences.

## Troubleshooting

- No menu bar icon: launch `Quota.app` from `Applications` instead of running the raw `.build/release/Quota` executable.
- No quota data: make sure Codex CLI or ChatGPT.app is installed and signed in with an account that exposes rate limit data.
- Codex cannot be found: ensure `codex` is available in `PATH`, or install `ChatGPT.app` in `/Applications`.
- No notifications: check macOS notification permissions for Quota in System Settings.

## Requirements

- macOS 14 Sonoma or later
- Codex CLI or ChatGPT.app
- A Codex account with rate limit data

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
