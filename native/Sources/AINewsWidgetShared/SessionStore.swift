import Foundation

@MainActor
public final class SessionStore {
    public static let shared = SessionStore()

    private let defaults: UserDefaults
    private let tokenKey = "ai-news.mac-widget.token"
    private let usernameKey = "ai-news.mac-widget.username"
    private let userIDKey = "ai-news.mac-widget.user-id"
    private let baseURLKey = "ai-news.mac-widget.base-url"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.string(forKey: baseURLKey) == nil {
            defaults.set(BackendDiscovery.discoveredBackendURLString(fallback: "http://127.0.0.1:4000"), forKey: baseURLKey)
        }
    }

    public var baseURLString: String {
        get {
            BackendDiscovery.discoveredBackendURLString(
                fallback: defaults.string(forKey: baseURLKey) ?? "http://127.0.0.1:4000"
            )
        }
        set { defaults.set(newValue, forKey: baseURLKey) }
    }

    public var session: UserSession? {
        guard
            let token = defaults.string(forKey: tokenKey),
            let username = defaults.string(forKey: usernameKey)
        else {
            return nil
        }
        let id = defaults.integer(forKey: userIDKey)
        return UserSession(token: token, user: UserAccount(id: id, username: username))
    }

    public func save(session: UserSession) {
        defaults.set(session.token, forKey: tokenKey)
        defaults.set(session.user.username, forKey: usernameKey)
        defaults.set(session.user.id, forKey: userIDKey)
    }

    public func clear() {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: usernameKey)
        defaults.removeObject(forKey: userIDKey)
    }
}
