import Foundation

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
            ?? Self.sharedContainerURL(fileManager: fm)
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
    }

    public func appendCommand(_ command: WidgetCommand) throws {
        try fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        var commands = loadCommands()
        commands.append(command)
        let data = try encoder.encode(commands)
        try data.write(to: commandsURL, options: .atomic)
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
    }

    private static func sharedContainerURL(fileManager: FileManager) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("AINewsMacWidget", isDirectory: true)
    }
}
