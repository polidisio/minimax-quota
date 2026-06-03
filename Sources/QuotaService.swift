import Foundation

// MARK: - QuotaCategory

enum QuotaCategory: String, CaseIterable {
    case text = "text"
    case speech = "speech"
    case music = "music"
    case video = "video"
    case image = "image"
    case lyrics = "lyrics"
    case coding = "coding"

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .speech: return "Speech"
        case .music: return "Music"
        case .video: return "Video"
        case .image: return "Image"
        case .lyrics: return "Lyrics"
        case .coding: return "Coding"
        }
    }

    var icon: String {
        switch self {
        case .text: return "📝"
        case .speech: return "🔊"
        case .music: return "🎵"
        case .video: return "🎬"
        case .image: return "🖼️"
        case .lyrics: return "📜"
        case .coding: return "💻"
        }
    }
}

// MARK: - CategoryQuota

struct CategoryQuota: Identifiable {
    let id = UUID()
    let category: QuotaCategory
    let used: Int
    let total: Int
    let pctRemaining: Double
}

// MARK: - QuotaData

struct QuotaData {
    let used: Int
    let total: Int
    let pctRemaining: Double
}

// MARK: - QuotaError

enum QuotaError: Error {
    case mmxNotFound
    case parseFailed
    case commandFailed(String)
}

// MARK: - QuotaService

class QuotaService {

    private let mmxPaths = ["/opt/homebrew/bin/mmx", "/usr/local/bin/mmx"]
    private let timeoutSeconds: TimeInterval = 10

    private let categoryMap: [String: QuotaCategory] = [
        "text": .text,
        "speech": .speech,
        "music": .music,
        "video": .video,
        "image": .image,
        "lyrics": .lyrics,
        "coding": .coding,
        "general": .text
    ]

    func fetchAllQuotas() async throws -> [CategoryQuota] {
        guard let mmxPath = findMmx() else {
            throw QuotaError.mmxNotFound
        }

        let result = try await runMmxCommand(path: mmxPath)
        return try parseAllQuotas(from: result)
    }

    func fetchQuota() async throws -> QuotaData {
        guard let mmxPath = findMmx() else {
            throw QuotaError.mmxNotFound
        }

        let result = try await runMmxCommand(path: mmxPath)
        return try parseMainQuota(from: result)
    }

    private func findMmx() -> String? {
        for path in mmxPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func runMmxCommand(path: String) async throws -> String {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["quota", "show", "--output", "json"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            var didComplete = false
            let completionLock = NSLock()

            let timeoutWorkItem = DispatchWorkItem {
                completionLock.lock()
                if !didComplete {
                    didComplete = true
                    completionLock.unlock()
                    process.terminate()
                    continuation.resume(throwing: QuotaError.commandFailed("Timeout after \(self.timeoutSeconds) seconds"))
                } else {
                    completionLock.unlock()
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)

            process.terminationHandler = { _ in
                completionLock.lock()
                if !didComplete {
                    didComplete = true
                    timeoutWorkItem.cancel()
                    completionLock.unlock()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: QuotaError.commandFailed("Exit code: \(process.terminationStatus)"))
                    }
                } else {
                    completionLock.unlock()
                }
            }

            do {
                try process.run()
            } catch {
                completionLock.lock()
                if !didComplete {
                    didComplete = true
                    timeoutWorkItem.cancel()
                    completionLock.unlock()
                    continuation.resume(throwing: QuotaError.commandFailed("Failed to run process: \(error.localizedDescription)"))
                } else {
                    completionLock.unlock()
                }
            }
        }
    }

    private func parseAllQuotas(from jsonString: String) throws -> [CategoryQuota] {
        guard let data = jsonString.data(using: .utf8) else {
            throw QuotaError.parseFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelRemains = json["model_remains"] as? [[String: Any]] else {
            throw QuotaError.parseFailed
        }

        var quotas: [CategoryQuota] = []

        for model in modelRemains {
            guard let modelName = model["model_name"] as? String,
                  let mappedCategory = categoryMap[modelName] else {
                continue
            }

            let remainingPercent = model["current_interval_remaining_percent"] as? Double ?? 100
            let pctRemaining = remainingPercent

            // Use a synthetic total/used based on remaining percent
            // If remaining is 85%, assume total=100 and used=15
            let total = 100
            let used = Int((100 - pctRemaining) * Double(total) / 100)

            if pctRemaining <= 0 {
                continue
            }

            let quota = CategoryQuota(
                category: mappedCategory,
                used: used,
                total: total,
                pctRemaining: pctRemaining
            )
            quotas.append(quota)
        }

        return quotas
    }

    private func parseMainQuota(from jsonString: String) throws -> QuotaData {
        guard let data = jsonString.data(using: .utf8) else {
            throw QuotaError.parseFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelRemains = json["model_remains"] as? [[String: Any]] else {
            throw QuotaError.parseFailed
        }

        // Find first model with an actual quota (non-zero total)
        for model in modelRemains {
            guard let modelName = model["model_name"] as? String,
                  modelName.hasPrefix("MiniMax-M") || modelName == "general" else {
                continue
            }

            let total = model["current_interval_total_count"] as? Int ?? 100
            let remainingPercent = model["current_interval_remaining_percent"] as? Double ?? 100

            if total == 0 {
                // Use remaining percent directly
                let used = Int((100 - remainingPercent) * 100 / 100)
                return QuotaData(used: used, total: 100, pctRemaining: remainingPercent)
            }

            let used = Int((100 - remainingPercent) * Double(total) / 100)
            return QuotaData(used: used, total: total, pctRemaining: remainingPercent)
        }

        throw QuotaError.parseFailed
    }
}
