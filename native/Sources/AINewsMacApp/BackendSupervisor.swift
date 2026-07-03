import Foundation

@MainActor
final class BackendSupervisor {
    static let shared = BackendSupervisor()

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
            let urlString = object["url"] as? String,
            let healthURL = URL(string: "\(urlString)/api/health")
        else {
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
        guard
            let url = Bundle.main.url(forResource: "backend-launch", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        return try? JSONDecoder().decode(BackendLaunchConfig.self, from: data)
    }
}

private struct BackendLaunchConfig: Decodable {
    let repoRoot: String
    let runtimeInfoPath: String
    let logFile: String
}
