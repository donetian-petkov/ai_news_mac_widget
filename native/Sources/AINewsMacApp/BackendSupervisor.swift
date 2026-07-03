import Foundation

@MainActor
final class BackendSupervisor {
    static let shared = BackendSupervisor()
    private static let runtimeAppID = "ai-news-mac-widget"
    private static let runtimeInfoPathDefaultsKey = "ai-news.mac-widget.runtime-info-path"

    private var process: Process?
    private let fileManager = FileManager.default

    func ensureBackendStarted() {
        guard process?.isRunning != true else { return }
        guard let config = loadConfig() else { return }
        UserDefaults.standard.set(config.runtimeInfoPath, forKey: Self.runtimeInfoPathDefaultsKey)
        guard shouldStartBackend(runtimeInfoPath: config.runtimeInfoPath) else { return }

        let process = Process()
        let environment = backendEnvironment(nodePath: config.nodePath, npmPath: config.npmPath)
        if fileManager.isExecutableFile(atPath: config.npmPath) {
            process.currentDirectoryURL = URL(fileURLWithPath: config.repoRoot, isDirectory: true)
            process.executableURL = URL(fileURLWithPath: config.npmPath)
            process.arguments = ["run", "start:backend"]
            process.environment = environment
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-lc", "cd '\(config.repoRoot)' && npm run start:backend"]
            process.environment = environment
        }

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

    private func backendEnvironment(nodePath: String, npmPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var pathEntries = [
            URL(fileURLWithPath: npmPath).deletingLastPathComponent().path,
            URL(fileURLWithPath: nodePath).deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        if let existing = environment["PATH"], !existing.isEmpty {
            pathEntries.append(existing)
        }
        environment["PATH"] = pathEntries
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ":")
        return environment
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
        let nodePath = decoded.nodePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let npmPath = decoded.npmPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if !repoRoot.isEmpty, !runtimeInfoPath.isEmpty, !logFile.isEmpty, !nodePath.isEmpty, !npmPath.isEmpty {
            return BackendLaunchConfig(
                repoRoot: repoRoot,
                runtimeInfoPath: runtimeInfoPath,
                logFile: logFile,
                nodePath: nodePath,
                npmPath: npmPath
            )
        }

        guard let inferred = inferredConfigFromBundle() else { return nil }
        return BackendLaunchConfig(
            repoRoot: repoRoot.isEmpty ? inferred.repoRoot : repoRoot,
            runtimeInfoPath: runtimeInfoPath.isEmpty ? inferred.runtimeInfoPath : runtimeInfoPath,
            logFile: logFile.isEmpty ? inferred.logFile : logFile,
            nodePath: nodePath.isEmpty ? inferred.nodePath : nodePath,
            npmPath: npmPath.isEmpty ? inferred.npmPath : npmPath
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
                    logFile: logDir.appendingPathComponent("backend.log").path,
                    nodePath: ProcessInfo.processInfo.environment["NODE_BINARY_PATH"] ?? "/opt/homebrew/bin/node",
                    npmPath: ProcessInfo.processInfo.environment["NPM_BINARY_PATH"] ?? "/opt/homebrew/bin/npm"
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
    let nodePath: String
    let npmPath: String
}
