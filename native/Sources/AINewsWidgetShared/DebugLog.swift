import Foundation

/// Lightweight append-only debug logger to a fixed file, so behavior can be
/// inspected without attaching a debugger. Safe to call from any thread.
public enum AINewsDebugLog {
    public static let path = "/tmp/ai-news-widget-debug.log"
    private static let queue = DispatchQueue(label: "ai-news.debuglog")
    /// Only touched on `queue`.
    nonisolated(unsafe) private static let formatter = ISO8601DateFormatter()

    public static func log(_ message: String) {
        let now = Date()
        queue.async {
            let line = "\(formatter.string(from: now)) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            try? LogFile.append(data, to: URL(fileURLWithPath: path))
        }
    }
}

/// Appends to a log file and keeps it from growing without bound: once the file
/// passes `maxBytes`, it is cut down to roughly the newest `keepBytes`, starting
/// at a line boundary.
enum LogFile {
    static let defaultMaxBytes = 1_048_576
    static let defaultKeepBytes = 524_288

    static func append(
        _ data: Data,
        to url: URL,
        maxBytes: Int = defaultMaxBytes,
        keepBytes: Int = defaultKeepBytes
    ) throws {
        let size: UInt64
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: data)
            size = try handle.offset()
        } else {
            try data.write(to: url, options: .atomic)
            size = UInt64(data.count)
        }
        if size > UInt64(maxBytes) {
            try trim(url, keepBytes: keepBytes)
        }
    }

    static func trim(_ url: URL, keepBytes: Int) throws {
        let contents = try Data(contentsOf: url)
        guard contents.count > keepBytes else { return }
        var tail = contents.suffix(keepBytes)
        // Drop the partial first line so the file starts on a whole entry.
        if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) {
            tail = tail[tail.index(after: newline)...]
        }
        try Data(tail).write(to: url, options: .atomic)
    }
}
