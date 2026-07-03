import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
public final class SnapshotStore {
    public static let shared = SnapshotStore()
    public static let appGroupIdentifier = "group.com.donetianpetkov.ainewswidget"
    private static let snapshotDefaultsKey = "widget.snapshot.json"
    private static let commandsDefaultsKey = "widget.commands.json"

    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let rootDirectory: URL
    private let snapshotURL: URL
    private let commandsURL: URL
    private let sharedDefaults: UserDefaults?

    public init(rootDirectory: URL? = nil) {
        let baseDirectory = rootDirectory
            ?? Self.preferredContainerURL(fileManager: fm)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("AINewsMacWidget", isDirectory: true)
        self.rootDirectory = baseDirectory
        self.snapshotURL = baseDirectory.appendingPathComponent("widget-snapshot.json")
        self.commandsURL = baseDirectory.appendingPathComponent("widget-commands.json")
        self.sharedDefaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadSnapshot() -> WidgetSnapshot {
        if let data = sharedDefaults?.data(forKey: Self.snapshotDefaultsKey),
           let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) {
            return snapshot
        }
        guard let data = try? Data(contentsOf: snapshotURL) else {
            return WidgetSnapshot()
        }
        let snapshot = (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? WidgetSnapshot()
        sharedDefaults?.set(data, forKey: Self.snapshotDefaultsKey)
        return snapshot
    }

    public func saveSnapshot(_ snapshot: WidgetSnapshot) throws {
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        sharedDefaults?.set(data, forKey: Self.snapshotDefaultsKey)
        try data.write(to: snapshotURL, options: .atomic)
        reloadWidgetTimelines()
    }

    public func appendCommand(_ command: WidgetCommand) throws {
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        var commands = loadCommands()
        commands.append(command)
        let data = try encoder.encode(commands)
        sharedDefaults?.set(data, forKey: Self.commandsDefaultsKey)
        try data.write(to: commandsURL, options: .atomic)
        reloadWidgetTimelines()
    }

    public func loadCommands() -> [WidgetCommand] {
        if let data = sharedDefaults?.data(forKey: Self.commandsDefaultsKey),
           let commands = try? decoder.decode([WidgetCommand].self, from: data) {
            return commands
        }
        guard let data = try? Data(contentsOf: commandsURL) else {
            return []
        }
        let commands = (try? decoder.decode([WidgetCommand].self, from: data)) ?? []
        sharedDefaults?.set(data, forKey: Self.commandsDefaultsKey)
        return commands
    }

    public func clearCommands() throws {
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode([WidgetCommand]())
        sharedDefaults?.set(data, forKey: Self.commandsDefaultsKey)
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
