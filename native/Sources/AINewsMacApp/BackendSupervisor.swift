import Foundation

@MainActor
final class BackendSupervisor {
    static let shared = BackendSupervisor()
    private static let runtimeAppID = "ai-news-mac-widget"

    private var process: Process?
    private let fileManager = FileManager.default

    func ensureBackendStarted() {
        guard process?.isRunning != true else { return }
        guard let config = loadConfig() else { return }
        guard shouldStartBackend(runtimeInfoPath: config.runtimeInfoPath) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "cd '\(config.repoRoot)' && npm run start:backend"]

        let logDirectory = URL(fileURLWithPath: config.logFile).deletingLastPathComponent()
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        fileManager.createFile(atPath: config.logFile, contents: nil)
        if let logHandle = FileHandle(forWritingAtPath: config.logFile) {
            _ = try? logHandle.seekToEnd()
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("AI News Widget backend start failed: \(error.localizedDescription)")
        }
    }

    private func shouldStartBackend(runtimeInfoPath: String) -> Bool {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: runtimeInfoPath)),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let appID = object["app"] as? String,
            let urlString = object["url"] as? String,
            let healthURL = URL(string: "\(urlString)/api/health")
        else {
            return true
        }

        guard appID == Self.runtimeAppID else {
            return true
        }

        let widgetAPIReady = ((object["capabilities"] as? [String: Any])?["widgetAPI"] as? Bool) == true
        guard widgetAPIReady else {
            return true
        }

        guard
            let healthData = try? Data(contentsOf: healthURL),
            let payload = try? JSONSerialization.jsonObject(with: healthData) as? [String: Any],
            let ok = payload["ok"] as? Bool,
            let authConfigured = payload["authConfigured"] as? Bool
        else {
            return true
        }
        return !(ok && authConfigured)
    }

    private func loadConfig() -> BackendLaunchConfig? {
        if
            let url = Bundle.main.url(forResource: "backend-launch", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(BackendLaunchConfig.self, from: data),
            let resolved = resolvedConfig(from: decoded) {
            return resolved
        }

        return inferredConfigFromBundle()
    }

    private func resolvedConfig(from decoded: BackendLaunchConfig) -> BackendLaunchConfig? {
        let repoRoot = decoded.repoRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let runtimeInfoPath = decoded.runtimeInfoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let logFile = decoded.logFile.trimmingCharacters(in: .whitespacesAndNewlines)

        if !repoRoot.isEmpty, !runtimeInfoPath.isEmpty, !logFile.isEmpty {
            return decoded
        }

        guard let inferred = inferredConfigFromBundle() else { return nil }
        return BackendLaunchConfig(
            repoRoot: repoRoot.isEmpty ? inferred.repoRoot : repoRoot,
            runtimeInfoPath: runtimeInfoPath.isEmpty ? inferred.runtimeInfoPath : runtimeInfoPath,
            logFile: logFile.isEmpty ? inferred.logFile : logFile
        )
    }

    private func inferredConfigFromBundle() -> BackendLaunchConfig? {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        var cursor = bundleURL
        let fm = fileManager

        while cursor.path != "/" {
            let packageJSON = cursor.appendingPathComponent("package.json")
            let backendAPI = cursor.appendingPathComponent("backend/apps/api")
            if fm.fileExists(atPath: packageJSON.path), fm.fileExists(atPath: backendAPI.path) {
                let logDir = fm.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/AINewsMacWidget", isDirectory: true)
                let runtimeInfoPath = "/tmp/ai-news-mac-widget-runtime.json"
                return BackendLaunchConfig(
                    repoRoot: cursor.path,
                    runtimeInfoPath: runtimeInfoPath,
                    logFile: logDir.appendingPathComponent("backend.log").path
                )
            }
            cursor.deleteLastPathComponent()
        }

        return nil
    }
}

private struct BackendLaunchConfig: Decodable {
    let repoRoot: String
    let runtimeInfoPath: String
    let logFile: String
}
