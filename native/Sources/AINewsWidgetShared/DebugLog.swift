import Foundation

/// Lightweight append-only debug logger to a fixed file, so behavior can be
/// inspected without attaching a debugger. Safe to call from any thread.
public enum AINewsDebugLog {
    public static let path = "/tmp/ai-news-widget-debug.log"
    private static let queue = DispatchQueue(label: "ai-news.debuglog")

    public static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = URL(fileURLWithPath: path)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
