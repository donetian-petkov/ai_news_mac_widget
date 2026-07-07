import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
public final class SnapshotStore {
    public static let shared = SnapshotStore()
    public static let appGroupIdentifier = "group.com.donetianpetkov.ainewswidget"

    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let rootDirectory: URL
    private let storageDirectories: [URL]
    private let usesExplicitRoot: Bool

    public init(rootDirectory: URL? = nil) {
        let directories = rootDirectory.map { [$0] } ?? Self.containerCandidates(fileManager: fm)
        let baseDirectory = directories.first
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("AINewsMacWidget", isDirectory: true)
        self.rootDirectory = baseDirectory
        self.storageDirectories = directories.isEmpty ? [baseDirectory] : directories
        self.usesExplicitRoot = rootDirectory != nil
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadSnapshot() -> WidgetSnapshot {
        var firstDecodedSnapshot: WidgetSnapshot?

        for url in snapshotURLs {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else {
                continue
            }
            if firstDecodedSnapshot == nil {
                firstDecodedSnapshot = snapshot
            }
            if !snapshot.categories.isEmpty || !snapshot.storiesByCategory.isEmpty {
                writeDiagnostic("loadSnapshot hit \(url.path) categories=\(snapshot.categories.count) storyBuckets=\(snapshot.storiesByCategory.count)")
                return snapshot
            }
        }

        if let snapshot = firstDecodedSnapshot {
            writeDiagnostic("loadSnapshot decoded empty snapshot")
            return snapshot
        }

        writeDiagnostic("loadSnapshot found no readable snapshot in \(snapshotURLs.map(\.path).joined(separator: " | "))")
        return WidgetSnapshot()
    }

    public func saveSnapshot(_ snapshot: WidgetSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try write(data, filename: "widget-snapshot.json")
        writeDiagnostic("saveSnapshot categories=\(snapshot.categories.count) storyBuckets=\(snapshot.storiesByCategory.count)")
        reloadWidgetTimelines()
    }

    public func appendCommand(_ command: WidgetCommand) throws {
        var commands = loadCommands()
        commands.append(command)
        let data = try encoder.encode(commands)
        try write(data, filename: "widget-commands.json")
        writeDiagnostic("appendCommand kind=\(command.kind.rawValue) count=\(commands.count)")
        reloadWidgetTimelines()
    }

    public func loadCommands() -> [WidgetCommand] {
        for url in commandURLs {
            guard let data = try? Data(contentsOf: url),
                  let commands = try? decoder.decode([WidgetCommand].self, from: data) else {
                continue
            }
            if !commands.isEmpty {
                writeDiagnostic("loadCommands hit \(url.path) count=\(commands.count)")
                return commands
            }
        }
        return []
    }

    public func clearCommands() throws {
        let data = try encoder.encode([WidgetCommand]())
        try write(data, filename: "widget-commands.json")
        writeDiagnostic("clearCommands")
        reloadWidgetTimelines()
    }

    private var snapshotURLs: [URL] {
        storageDirectories.map { $0.appendingPathComponent("widget-snapshot.json") }
    }

    private var commandURLs: [URL] {
        storageDirectories.map { $0.appendingPathComponent("widget-commands.json") }
    }

    private static func containerCandidates(fileManager: FileManager) -> [URL] {
        var urls: [URL] = []

        if let appGroupURL = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("AINewsMacWidget", isDirectory: true) {
            urls.append(appGroupURL)
        }

        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AINewsMacWidget", isDirectory: true) {
            urls.append(appSupportURL)
        }

        let unsandboxedSupportURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AINewsMacWidget", isDirectory: true)
        urls.append(unsandboxedSupportURL)

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.standardizedFileURL.path
            return seen.insert(key).inserted
        }
    }

    private func write(_ data: Data, filename: String) throws {
        var firstError: Error?
        var wroteAtLeastOnce = false

        for directory in storageDirectories {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
                wroteAtLeastOnce = true
                if usesExplicitRoot { break }
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if !wroteAtLeastOnce {
            throw firstError ?? CocoaError(.fileWriteUnknown)
        }
    }

    private func writeDiagnostic(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        for directory in storageDirectories {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                let logURL = directory.appendingPathComponent("widget-debug.log")
                if fm.fileExists(atPath: logURL.path),
                   let handle = try? FileHandle(forWritingTo: logURL) {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: logURL, options: .atomic)
                }
                if usesExplicitRoot { break }
            } catch {
                continue
            }
        }
    }

    private func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        if #available(macOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}
