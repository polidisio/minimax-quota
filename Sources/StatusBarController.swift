import AppKit

class StatusBarController {

    private var statusItem: NSStatusItem
    private var quotaService: QuotaService
    private var refreshTimer: Timer?
    private var logger: Logger

    private var currentQuota: QuotaData?
    private var isErrorState = false

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        quotaService = QuotaService()
        logger = Logger()

        setupStatusItem()
        setupMenu()

        Task {
            await refreshQuota()
        }

        startAutoRefresh()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.title = "..."
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let infoItem = NSMenuItem(title: "📊 -- / -- requests", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        infoItem.tag = 100
        menu.addItem(infoItem)

        menu.addItem(NSMenuItem.separator())

        let copyItem = NSMenuItem(title: "📋 Copy % to clipboard", action: #selector(copyToClipboard), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        let dashboardItem = NSMenuItem(title: "🌐 Open MiniMax dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let refreshItem = NSMenuItem(title: "🔄 Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "❌ Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshQuota()
            }
        }
    }

    @MainActor
    private func refreshQuota() async {
        do {
            let quota = try await quotaService.fetchQuota()
            currentQuota = quota
            isErrorState = false
            updateUI(with: quota)
            logger.log(used: quota.used, total: quota.total, success: true)
        } catch {
            isErrorState = true
            updateUIForError()
            logger.log(used: nil, total: nil, success: false)
        }
    }

    private func updateUI(with quota: QuotaData) {
        guard let button = statusItem.button else { return }

        let pctRemainingInt = Int(quota.pctRemaining.rounded())
        button.title = "\(pctRemainingInt)% ↓"

        let pctUsed = 100 - quota.pctRemaining
        let usedFormatted = formatNumber(quota.used)
        let totalFormatted = formatNumber(quota.total)

        if quota.pctRemaining > 50 {
            button.contentTintColor = .systemGreen
        } else if quota.pctRemaining > 20 {
            button.contentTintColor = .systemYellow
        } else {
            button.contentTintColor = .systemRed
        }

        button.toolTip = "MiniMax M2: \(usedFormatted)/\(totalFormatted) requests (\(String(format: "%.1f", pctUsed))% usado)"

        if let menu = statusItem.menu, let infoItem = menu.item(withTag: 100) {
            infoItem.title = "📊 \(usedFormatted) / \(totalFormatted) requests"
        }
    }

    private func updateUIForError() {
        guard let button = statusItem.button else { return }
        button.title = "⚠️ Error"
        button.contentTintColor = .systemRed
        button.toolTip = "Failed to fetch MiniMax quota"

        if let menu = statusItem.menu, let infoItem = menu.item(withTag: 100) {
            infoItem.title = "📊 -- / -- requests"
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    @objc private func copyToClipboard() {
        guard let quota = currentQuota else { return }
        let pctRemainingInt = Int(quota.pctRemaining.rounded())
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(pctRemainingInt)%", forType: .string)
    }

    @objc private func openDashboard() {
        if let url = URL(string: "https://platform.minimax.io/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func refreshNow() {
        Task {
            await refreshQuota()
        }
    }

    @objc private func quit() {
        refreshTimer?.invalidate()
        NSApplication.shared.terminate(nil)
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
