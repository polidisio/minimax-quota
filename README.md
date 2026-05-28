# MiniMax Quota Menu Bar

macOS menu bar app that monitors your MiniMax API quota in real-time.

![Platform](https://img.shields.io/badge/platform-macOS%2012.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu bar display**: Shows remaining quota % with color indicators
  - 🟢 Green: >50% remaining
  - 🟡 Yellow: 20-50% remaining
  - 🔴 Red: <20% remaining
- **Auto-refresh**: Updates every 5 minutes automatically
- **Quick actions menu**:
  - Copy % to clipboard
  - Open MiniMax dashboard in browser
  - Manual refresh
- **Logging**: All quota checks logged to `~/.hermes/logs/minimax-quota.log`
- **No Dock icon**: Runs silently in the menu bar only (`LSUIElement`)

## Requirements

- macOS 12.0+
- **MiniMax CLI app (`mmx`) installed and authenticated** — [Install from GitHub](https://github.com/MiniMax-AI/cli)

> ⚠️ This app does NOT include the MiniMax CLI. You must install [`mmx`](https://github.com/MiniMaxAi/mmx) separately and run `mmx auth login` before using MiniMaxQuota.

## Installation

### Build from source

```bash
# Clone or navigate to the project
cd MiniMaxQuota

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project MiniMaxQuota.xcodeproj -scheme MiniMaxQuota -configuration Release build

# Locate the app
open ~/Library/Developer/Xcode/DerivedData/MiniMaxQuota-*/Build/Products/Release/
```

### Run

```bash
open ~/Library/Developer/Xcode/DerivedData/MiniMaxQuota-*/Build/Products/Release/MiniMaxQuota.app
```

Or copy to `/Applications`:
```bash
cp -R ~/Library/Developer/Xcode/DerivedData/MiniMaxQuota-*/Build/Products/Release/MiniMaxQuota.app /Applications/
```

## Usage

1. The app appears in your menu bar showing `XX% ↓`
2. Click to see details and actions
3. Quota auto-refreshes every 5 minutes

## Uninstall

```bash
rm -rf /Applications/MiniMaxQuota.app
rm -f ~/.hermes/logs/minimax-quota.log
```

## Log format

```
[2026-05-26T18:30:00Z] 293/1500 | 80.5% remaining | ✓
[2026-05-26T18:35:00Z] 295/1500 | 80.3% remaining | ✓
[2026-05-26T18:40:00Z] --/-- | --% remaining | ✗
```

## Troubleshooting

**First time setup**: You need the MiniMax CLI installed on your system.

1. Install `mmx` via npm (requires Node.js):
   ```bash
   npm install -g mmx-cli
   ```
   Or if using Homebrew on Apple Silicon:
   ```bash
   /opt/homebrew/bin/brew install node && /opt/homebrew/bin/npm install -g mmx-cli
   ```

2. Authenticate:
   ```bash
   mmx auth login
   ```

3. Verify it works:
   ```bash
   mmx quota show  # should return JSON with your quota info
   ```

**"⚠️ Error" shown in menu bar**: Run the commands above to confirm `mmx` is installed and authenticated.

**mmx path**: The app looks for `mmx` at:
- `/opt/homebrew/bin/mmx` (Homebrew on Apple Silicon)
- `/usr/local/bin/mmx` (Homebrew on Intel)

## License

MIT
