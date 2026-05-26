import Foundation

class Logger {

    private let logDirectory: String
    private let logFilePath: String

    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        logDirectory = "\(homeDirectory)/.hermes/logs"
        logFilePath = "\(logDirectory)/minimax-quota.log"

        createLogDirectoryIfNeeded()
    }

    private func createLogDirectoryIfNeeded() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logDirectory) {
            do {
                try fileManager.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create log directory: \(error)")
            }
        }
    }

    func log(used: Int?, total: Int?, success: Bool) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let statusSymbol = success ? "✓" : "✗"

        var logLine: String
        if success, let used = used, let total = total {
            let pctRemaining = 100 - (Double(used) / Double(total) * 100)
            logLine = "[\(timestamp)] \(used)/\(total) | \(String(format: "%.1f", pctRemaining))% remaining | \(statusSymbol)\n"
        } else {
            logLine = "[\(timestamp)] --/-- | --% remaining | \(statusSymbol)\n"
        }

        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFilePath) {
                if let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logFilePath)) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logFilePath))
            }
        }
    }
}
