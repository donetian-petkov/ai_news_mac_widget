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
    private let snapshotURL: URL
    private let commandsURL: URL

    public init(rootDirectory: URL? = nil) {
        let baseDirectory = rootDirectory
            ?? Self.preferredContainerURL(fileManager: fm)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("AINewsMacWidget", isDirectory: true)
        self.rootDirectory = baseDirectory
        self.snapshotURL = baseDirectory.appendingPathComponent("widget-snapshot.json")
        self.commandsURL = baseDirectory.appendingPathComponent("widget-commands.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadSnapshot() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL) else {
            return WidgetSnapshot()
        }
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? WidgetSnapshot()
    }

    public func saveSnapshot(_ snapshot: WidgetSnapshot) throws {
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
        reloadWidgetTimelines()
    }

    public func appendCommand(_ command: WidgetCommand) throws {
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        var commands = loadCommands()
        commands.append(command)
        let data = try encoder.encode(commands)
        try data.write(to: commandsURL, options: .atomic)
        reloadWidgetTimelines()
    }

    public func loadCommands() -> [WidgetCommand] {
        guard let data = try? Data(contentsOf: commandsURL) else {
            return []
        }
        return (try? decoder.decode([WidgetCommand].self, from: data)) ?? []
    }

    public func clearCommands() throws {
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode([WidgetCommand]())
        try data.write(to: commandsURL, options: .atomic)
        reloadWidgetTimelines()
    }

    private static func preferredContainerURL(fileManager: FileManager) -> URL? {
        for url in containerCandidates(fileManager: fileManager) {
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return containerCandidates(fileManager: fileManager).first
    }

    private static func containerCandidates(fileManager: FileManager) -> [URL] {
        var urls: [URL] = []

        if let appGroupURL = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("AINewsMacWidget", isDirectory: true) {
            urls.append(appGroupURL)
        }

        let explicitGroupURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(appGroupIdentifier)/AINewsMacWidget", isDirectory: true)
        urls.append(explicitGroupURL)

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.standardizedFileURL.path
            return seen.insert(key).inserted
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
