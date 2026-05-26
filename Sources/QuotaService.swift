import Foundation

struct QuotaData {
    let used: Int
    let total: Int
    let pctRemaining: Double
}

enum QuotaError: Error {
    case mmxNotFound
    case parseFailed
    case commandFailed(String)
}

class QuotaService {

    private let mmxPaths = ["/opt/homebrew/bin/mmx", "/usr/local/bin/mmx"]
    private let timeoutSeconds: TimeInterval = 10

    func fetchQuota() async throws -> QuotaData {
        guard let mmxPath = findMmx() else {
            throw QuotaError.mmxNotFound
        }

        let result = try await runMmxCommand(path: mmxPath)
        return try parseJsonOutput(result)
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
        return try await withCheckedThrowingContinuation { continuation in
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
                guard !didComplete else {
                    completionLock.unlock()
                    return
                }
                didComplete = true
                completionLock.unlock()
                process.terminate()
                continuation.resume(throwing: QuotaError.commandFailed("Timeout after \(self.timeoutSeconds) seconds"))
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)

            process.terminationHandler = { _ in
                completionLock.lock()
                guard !didComplete else {
                    completionLock.unlock()
                    return
                }
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
            }

            do {
                try process.run()
            } catch {
                completionLock.lock()
                guard !didComplete else {
                    completionLock.unlock()
                    return
                }
                didComplete = true
                timeoutWorkItem.cancel()
                completionLock.unlock()
                continuation.resume(throwing: QuotaError.commandFailed("Failed to run process: \(error.localizedDescription)"))
            }
        }
    }

    private func parseJsonOutput(_ jsonString: String) throws -> QuotaData {
        guard let data = jsonString.data(using: .utf8) else {
            throw QuotaError.parseFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelRemains = json["model_remains"] as? [[String: Any]] else {
            throw QuotaError.parseFailed
        }

        for model in modelRemains {
            guard let modelName = model["model_name"] as? String,
                  modelName.hasPrefix("MiniMax-M"),
                  let total = model["current_interval_total_count"] as? Int,
                  let used = model["current_interval_usage_count"] as? Int else {
                continue
            }

            let pctRemaining = 100 - (Double(used) / Double(total) * 100)
            return QuotaData(used: used, total: total, pctRemaining: pctRemaining)
        }

        throw QuotaError.parseFailed
    }
}
