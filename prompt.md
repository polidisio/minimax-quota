# Prompt — MiniMax Quota Menu Bar App (Swift)

Crea una app de menú bar para macOS en Swift puro (AppKit) que monitoree la quota de MiniMax. El proyecto se llamará `MiniMaxQuota` y vivirá en el directorio actual.

---

## 1. Estructura del proyecto

Crea esta estructura:

```
MiniMaxQuota/
├── Sources/
│   ├── main.swift              # Entry point: NSApplication.shared.run()
│   ├── AppDelegate.swift       # NSApplicationDelegate
│   ├── StatusBarController.swift  # Menú bar UI
│   ├── QuotaService.swift      # Ejecuta `mmx quota show` y parsea JSON
│   └── Logger.swift            # Logging a ~/.hermes/logs/minimax-quota.log
├── Resources/
│   └── Info.plist              # LSUIElement = true (no Dock)
└── project.yml                 # XcodeGen config
```

---

## 2. main.swift

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

---

## 3. Info.plist

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

---

## 4. QuotaService.swift

### Lógica

- Ejecuta el comando: `mmx quota show --output json`
- El binario `mmx` puede estar en `/opt/homebrew/bin/mmx` o `/usr/local/bin/mmx`
- Parsea el JSON buscando el objeto donde `model_name == "MiniMax-M*"`
- Extrae `current_interval_usage_count` y `current_interval_total_count`
- Calcula: `pctRemaining = 100 - (usage / total * 100)`
- Retorna los datos parseados o un error

### Método principal

```swift
struct QuotaData {
    let used: Int
    let total: Int
    let pctRemaining: Double
}

func fetchQuota() async throws -> QuotaData
```

### Implementación

```swift
import Foundation

struct QuotaData {
    let used: Int
    let total: Int
    let pctRemaining: Double

    static let empty = QuotaData(used: 0, total: 1500, pctRemaining: 100.0)
}

enum QuotaError: Error {
    case mmxNotFound
    case parseFailed
    case commandFailed(Int32)
}

class QuotaService {
    private let mmxPath = "/opt/homebrew/bin/mmx"

    func fetchQuota() async throws -> QuotaData {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: mmxPath)
        task.arguments = ["quota", "show", "--output", "json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw QuotaError.commandFailed(task.terminationStatus)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return try parseQuota(from: data)
    }

    private func parseQuota(from data: Data) throws -> QuotaData {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelRemains = json["model_remains"] as? [[String: Any]] else {
            throw QuotaError.parseFailed
        }

        for model in modelRemains {
            guard let name = model["model_name"] as? String,
                  name == "MiniMax-M*",
                  let used = model["current_interval_usage_count"] as? Int,
                  let total = model["current_interval_total_count"] as? Int else {
                continue
            }

            let pctUsed = Double(used) / Double(total) * 100
            let pctRemaining = 100 - pctUsed
            return QuotaData(used: used, total: total, pctRemaining: pctRemaining)
        }

        throw QuotaError.parseFailed
    }
}
```

---

## 5. StatusBarController.swift

### UI

- `NSStatusItem` con `button`
- **Título del botón**: `String(format: "%.0f%% ↓", quota.pctRemaining)`
- **Color del texto** según umbral:
  - >50%: `NSColor.systemGreen`
  - 20-50%: `NSColor.systemYellow`
  - <20%: `NSColor.systemRed`
- **Tooltip**: `MiniMax M2: \(used)/\(total) requests (\(String(format: "%.1f", pctUsed))% usado)`

### Menú al click

```
📊 293 / 1500 requests
— (separador)
📋 Copiar % al clipboard    → copia "80.47%"
🌐 Abrir dashboard MiniMax  → abre https://platform.minimax.io/usage
🔄 Actualizar ahora
— (separador)
❌ Salir
```

### Implementación

```swift
import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem
    private let quotaService = QuotaService()
    private var refreshTimer: Timer?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMenu()
        startRefreshTimer()
        Task { await refresh() }
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Stats item (no action)
        let statsItem = NSMenuItem(title: "📊 -- / -- requests", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "📋 Copiar % al clipboard", action: #selector(copyPercentage), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "🌐 Abrir dashboard MiniMax", action: #selector(openDashboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "🔄 Actualizar ahora", action: #selector(refreshAction), keyEquivalent: "r"))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "❌ Salir", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    @objc func refreshAction() {
        Task { await refresh() }
    }

    func refresh() async {
        do {
            let quota = try await quotaService.fetchQuota()
            await MainActor.run {
                updateUI(with: quota)
            }
            Logger.shared.log(used: quota.used, total: quota.total, remaining: quota.pctRemaining, success: true)
        } catch {
            await MainActor.run {
                showError()
            }
            Logger.shared.log(success: false)
        }
    }

    private func updateUI(with quota: QuotaData) {
        let btn = statusItem.button!
        let pctUsed = 100 - quota.pctRemaining
        btn.title = String(format: "%.0f%% ↓", quota.pctRemaining)

        // Color
        if quota.pctRemaining > 50 {
            btn.contentTintColor = .systemGreen
        } else if quota.pctRemaining > 20 {
            btn.contentTintColor = .systemYellow
        } else {
            btn.contentTintColor = .systemRed
        }

        // Tooltip
        btn.toolTip = "MiniMax M2: \(quota.used)/\(quota.total) requests (\(String(format: "%.1f", pctUsed))% usado)"

        // Update menu stats
        if let menu = statusItem.menu, let statsItem = menu.items.first {
            statsItem.title = "📊 \(quota.used) / \(quota.total) requests"
        }
    }

    private func showError() {
        statusItem.button?.title = "⚠️ Error"
        statusItem.button?.contentTintColor = .systemRed
    }

    @objc private func copyPercentage() {
        // Get current percentage from button title
        let title = statusItem.button?.title ?? ""
        if let pct = title.components(separatedBy: "%").first {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pct + "%", forType: .string)
        }
    }

    @objc private func openDashboard() {
        NSWorkspace.shared.open(URL(string: "https://platform.minimax.io/usage")!)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
```

---

## 6. AppDelegate.swift

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // cleanup
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
}
```

---

## 7. Logger.swift

```swift
import Foundation

class Logger {
    static let shared = Logger()

    private let logPath: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes")
            .appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("minimax-quota.log")
    }()

    func log(used: Int, total: Int, remaining: Double, success: Bool) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let status = success ? "✓" : "✗"
        let line = "[\(timestamp)] \(used)/\(total) | \(String(format: "%.1f", remaining))% remaining | \(status)\n"

        if let handle = try? FileHandle(forWritingTo: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        }
    }

    func log(success: Bool) {
        log(used: 0, total: 0, remaining: 0, success: success)
    }
}
```

---

## 8. project.yml (XcodeGen)

```yaml
name: MiniMaxQuota
options:
  bundleIdPrefix: com.minimax
  deploymentTarget:
    macOS: "12.0"
targets:
  MiniMaxQuota:
    type: application
    platform: macOS
    sources:
      - path: Sources
    resources:
      - path: Resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.minimax.Quota
        INFOPLIST_FILE: Resources/Info.plist
        SWIFT_VERSION: "5.9"
        MACOSX_DEPLOYMENT_TARGET: "12.0"
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGNING_REQUIRED: NO
        CODE_SIGNING_ALLOWED: NO
        ENABLE_HARDENED_RUNTIME: NO
```

---

## 9. Instrucciones de build

1. Generar el proyecto Xcode:
   ```bash
   cd MiniMaxQuota
   which xcodegen || brew install xcodegen
   xcodegen generate
   ```

2. Compilar:
   ```bash
   xcodebuild -project MiniMaxQuota.xcodeproj -scheme MiniMaxQuota -configuration Release build
   ```

3. El `.app` estará en:
   ```
   build/Release/MiniMaxQuota.app
   ```

4. Para ejecutar: hacer doble click en `MiniMaxQuota.app` o copiar a `/Applications`

---

## Validación

Antes de considerar terminado, verificar:
- [ ] El proyecto compila sin errores (`xcodebuild` exit 0)
- [ ] La app aparece SOLO en el menú bar, no en el Dock
- [ ] El % se calcula correctamente para el caso actual (293/1500)
- [ ] El color cambia según los umbrales (>50% verde, 20-50% amarillo, <20% rojo)
- [ ] El menú desplegable tiene todas las opciones
- [ ] El log se escribe en `~/.hermes/logs/minimax-quota.log`
- [ ] Al hacer clic en "Abrir dashboard" se abre el navegador
- [ ] Al hacer clic en "Copiar %" se copia al clipboard
