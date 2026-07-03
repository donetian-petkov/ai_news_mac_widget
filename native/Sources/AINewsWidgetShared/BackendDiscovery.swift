import Foundation

private struct BackendRuntimeInfo: Codable {
    var url: String
    var port: Int
    var pid: Int?
    var startedAt: String?
}

public enum BackendDiscovery {
    private static let runtimeInfoURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ai-news-mac-widget-runtime.json")

    public static func discoveredBackendURLString(fallback: String) -> String {
        guard
            let data = try? Data(contentsOf: runtimeInfoURL),
            let info = try? JSONDecoder().decode(BackendRuntimeInfo.self, from: data),
            let url = URL(string: info.url),
            ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
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
}
