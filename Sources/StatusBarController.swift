import AppKit

class StatusBarController: NSObject {

    private var statusItem: NSStatusItem
    private var quotaService: QuotaService
    private var refreshTimer: Timer?
    private var logger: Logger

    private var currentQuotas: [CategoryQuota] = []
    private var isErrorState = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        quotaService = QuotaService()
        logger = Logger()
        super.init()
        setupStatusItem()
        setupMenu()
        startAutoRefresh()

        Task {
            await refreshQuota()
        }
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.title = "..."
            button.imagePosition = .imageLeft
        }
    }

    private func updateStatusIcon(percentage: Double?) {
        guard let button = statusItem.button else { return }

        if let pct = percentage {
            let intPct = Int(pct.rounded())

            let color: NSColor
            if pct > 50 {
                color = .systemGreen
            } else if pct > 20 {
                color = .systemYellow
            } else {
                color = .systemRed
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ]
            button.attributedTitle = NSAttributedString(string: "\(intPct)%", attributes: attrs)
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ]
            button.attributedTitle = NSAttributedString(string: "?", attributes: attrs)
        }
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        // Header
        let headerItem = NSMenuItem(title: "📊 MiniMax Quota", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // All quotas
        let allCategories: [(QuotaCategory, String)] = [
            (.text, "📝 Text"),
            (.speech, "🔊 Speech"),
            (.music, "🎵 Music"),
            (.video, "🎬 Video"),
            (.image, "🖼️ Image"),
            (.lyrics, "📝 Lyrics"),
            (.coding, "💻 Coding")
        ]

        for (category, label) in allCategories {
            if let quota = currentQuotas.first(where: { $0.category == category }) {
                let pct = Int(quota.pctRemaining.rounded())
                let used = formatNumber(quota.used)
                let total = formatNumber(quota.total)
                let color = colorEmoji(for: quota.pctRemaining)
                let item = NSMenuItem(title: "\(color) \(label): \(used)/\(total) (\(pct)%)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            } else {
                let item = NSMenuItem(title: "⚪ \(label): --", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Copy main percentage
        if let mainQuota = currentQuotas.first(where: { $0.category == .text }) {
            let pct = Int(mainQuota.pctRemaining.rounded())
            let copyItem = NSMenuItem(title: "📋 Copy main % (\(pct)%)", action: #selector(copyToClipboard), keyEquivalent: "c")
            copyItem.target = self
            menu.addItem(copyItem)
        }

        let dashboardItem = NSMenuItem(title: "🌐 Open MiniMax Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let refreshItem = NSMenuItem(title: "🔄 Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "❌ Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func colorEmoji(for pct: Double) -> String {
        if pct > 50 {
            return "🟢"
        } else if pct > 20 {
            return "🟡"
        } else {
            return "🔴"
        }
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
            let quotas = try await quotaService.fetchAllQuotas()
            currentQuotas = quotas
            isErrorState = false

            if let mainQuota = quotas.first(where: { $0.category == .text }) {
                updateStatusIcon(percentage: mainQuota.pctRemaining)
                logger.log(category: "text", used: mainQuota.used, total: mainQuota.total, success: true)
            } else if let mainQuota = quotas.first {
                updateStatusIcon(percentage: mainQuota.pctRemaining)
            }

            rebuildMenu()
        } catch {
            isErrorState = true
            if let button = statusItem.button {
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                ]
                button.attributedTitle = NSAttributedString(string: "⚠️", attributes: attrs)
            }
            logger.log(category: "error", success: false)
            rebuildMenu()
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    @objc private func copyToClipboard() {
        if let mainQuota = currentQuotas.first(where: { $0.category == .text }) {
            let pct = Int(mainQuota.pctRemaining.rounded())
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString("\(pct)%", forType: .string)
        }
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

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        Task {
            await refreshQuota()
        }
    }
}
