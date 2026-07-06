import Foundation

private struct BackendRuntimeInfo: Codable {
    var app: String?
    var url: String
    var port: Int
    var pid: Int?
    var startedAt: String?
    var capabilities: BackendCapabilities?
}

private struct BackendCapabilities: Codable {
    var widgetAPI: Bool?
}

private struct BackendLaunchConfig: Decodable {
    var repoRoot: String?
    var runtimeInfoPath: String?
    var logFile: String?
    var nodePath: String?
    var npmPath: String?
}

public enum BackendDiscovery {
    private static let runtimeAppID = "ai-news-mac-widget"
    private static let runtimeInfoPathDefaultsKey = "ai-news.mac-widget.runtime-info-path"

    public static func discoveredBackendURLString(fallback: String) -> String {
        guard let info = loadRuntimeInfo(),
              let url = URL(string: info.url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return fallback
        }

        let fallbackHost = URL(string: fallback)?.host?.lowercased()
        let discoveredHost = url.host?.lowercased()
        let isLocalFallback = fallbackHost == nil || fallbackHost == "127.0.0.1" || fallbackHost == "localhost"
        let isLocalDiscovered = discoveredHost == "127.0.0.1" || discoveredHost == "localhost"
        if isLocalFallback && isLocalDiscovered {
            return info.url
        }
        return fallback
    }

    public static func runtimeBackendURLString() -> String? {
        loadRuntimeInfo()?.url
    }

    public static func candidateBackendURLStrings(primary: String) -> [String] {
        var urls: [String] = []
        if !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            urls.append(primary)
        }
        if let runtime = runtimeBackendURLString(), !runtime.isEmpty {
            urls.append(runtime)
        }
        urls.append("http://127.0.0.1:3000")
        urls.append("http://127.0.0.1:4000")
        urls.append("http://localhost:3000")
        urls.append("http://localhost:4000")
        return uniqueStrings(urls)
    }

    private static func loadRuntimeInfo() -> BackendRuntimeInfo? {
        for url in runtimeInfoURLs() {
            guard let data = try? Data(contentsOf: url),
                  let info = try? JSONDecoder().decode(BackendRuntimeInfo.self, from: data),
                  info.app == runtimeAppID,
                  info.capabilities?.widgetAPI == true else {
                continue
            }
            return info
        }
        return nil
    }

    private static func runtimeInfoURLs() -> [URL] {
        var urls: [URL] = []
        let defaults = UserDefaults.standard
        if let persisted = defaults.string(forKey: runtimeInfoPathDefaultsKey), !persisted.isEmpty {
            urls.append(URL(fileURLWithPath: persisted))
        }
        if
            let configURL = Bundle.main.url(forResource: "backend-launch", withExtension: "json"),
            let data = try? Data(contentsOf: configURL),
            let config = try? JSONDecoder().decode(BackendLaunchConfig.self, from: data),
            let runtimeInfoPath = config.runtimeInfoPath?.trimmingCharacters(in: .whitespacesAndNewlines),
            !runtimeInfoPath.isEmpty {
            urls.append(URL(fileURLWithPath: runtimeInfoPath))
        }
        urls.append(URL(fileURLWithPath: "/tmp/ai-news-mac-widget-runtime.json"))
        urls.append(URL(fileURLWithPath: "/private/tmp/ai-news-mac-widget-runtime.json"))
        return unique(urls)
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                out.append(URL(fileURLWithPath: path))
            }
        }
        return out
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                out.append(normalized)
            }
        }
        return out
    }
}
