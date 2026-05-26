Create a macOS menu bar app in Swift that monitors MiniMax quota. The project is in /Users/jmaudisio/Developer/minimax-quota/

Read CLAUDE.md first for project context, then create all source files.

## Files to create

### Sources/main.swift
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

### Sources/AppDelegate.swift
```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
}
```

### Sources/QuotaService.swift
Execute `mmx quota show --output json` using Process. mmx is at /opt/homebrew/bin/mmx
Parse JSON looking for model where model_name == "MiniMax-M*"
Extract current_interval_usage_count and current_interval_total_count
Return struct QuotaData { used: Int, total: Int, pctRemaining: Double }
Calculate: pctRemaining = 100 - (used / total * 100)
Throw QuotaError on failure (mmxNotFound, parseFailed, commandFailed)

### Sources/StatusBarController.swift
- NSStatusItem button showing "XX% ↓" (XX = pctRemaining rounded to integer)
- Text color: .systemGreen if pctRemaining > 50, .systemYellow if > 20, .systemRed otherwise
- Tooltip: "MiniMax M2: used/total requests (XX% usado)"
- Menu items:
  1. "📊 used / total requests" (disabled, info only)
  2. separator
  3. "📋 Copy % to clipboard" - copies "XX%" to NSPasteboard
  4. "🌐 Open MiniMax dashboard" - opens https://platform.minimax.io/usage
  5. "🔄 Refresh now"
  6. separator
  7. "❌ Quit"
- Auto-refresh every 5 minutes using Timer
- On refresh error show "⚠️ Error" in red

### Sources/Logger.swift
Log to ~/.hermes/logs/minimax-quota.log
Format: [ISO8601 timestamp] used/total | XX.X% remaining | ✓ or ✗
Create directory if needed.

### Resources/Info.plist
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

### project.yml
XcodeGen config for macOS app, Swift 5.9, deployment target 12.0.
No code signing required.

## Build steps
1. Run xcodegen generate
2. Run xcodebuild -project MiniMaxQuota.xcodeproj -scheme MiniMaxQuota -configuration Release build
3. Verify exit code 0

Do NOT add any API keys or tokens. Do NOT commit .log files or cache.
