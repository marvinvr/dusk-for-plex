import Foundation

@MainActor
@Observable
final class PlexService {
    var authToken: String?
    private(set) var connectedServer: PlexServer?
    var serverBaseURL: URL?

    var isAuthenticated: Bool { authToken != nil }
    var isConnected: Bool { serverBaseURL != nil }

    let clientIdentifier: String
    let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    static let plexTVBase = "https://plex.tv"
    static let keychainTokenKey = "PlexAuthToken"
    static let defaultsClientIDKey = "PlexClientIdentifier"
    static let defaultsServerURLKey = "PlexServerURL"
    static let defaultsServerIDKey = "PlexServerID"
    static let defaultsServerDataKey = "PlexServerData"

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = AppImageCache.shared
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        if let stored = UserDefaults.standard.string(forKey: Self.defaultsClientIDKey) {
            clientIdentifier = stored
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: Self.defaultsClientIDKey)
            clientIdentifier = id
        }

        if let data = KeychainHelper.load(key: Self.keychainTokenKey),
           let token = String(data: data, encoding: .utf8) {
            authToken = token
        }

        if let urlString = UserDefaults.standard.string(forKey: Self.defaultsServerURLKey),
           let url = URL(string: urlString) {
            serverBaseURL = url
        }

        if let serverData = UserDefaults.standard.data(forKey: Self.defaultsServerDataKey),
           let server = try? decoder.decode(PlexServer.self, from: serverData) {
            connectedServer = server
        }
    }

    func setServer(_ server: PlexServer, baseURL: URL) {
        connectedServer = server
        serverBaseURL = baseURL
        UserDefaults.standard.set(baseURL.absoluteString, forKey: Self.defaultsServerURLKey)
        UserDefaults.standard.set(server.clientIdentifier, forKey: Self.defaultsServerIDKey)
        if let data = try? encoder.encode(server) {
            UserDefaults.standard.set(data, forKey: Self.defaultsServerDataKey)
        }
    }

    func clearServer() {
        connectedServer = nil
        serverBaseURL = nil
        UserDefaults.standard.removeObject(forKey: Self.defaultsServerURLKey)
        UserDefaults.standard.removeObject(forKey: Self.defaultsServerIDKey)
        UserDefaults.standard.removeObject(forKey: Self.defaultsServerDataKey)
    }
}
