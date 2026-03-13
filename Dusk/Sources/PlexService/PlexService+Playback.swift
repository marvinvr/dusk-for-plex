import Foundation

extension PlexService {
    func reportTimeline(ratingKey: String, state: PlaybackState, timeMs: Int, durationMs: Int) async {
        let stateString: String
        switch state {
        case .playing:
            stateString = "playing"
        case .paused:
            stateString = "paused"
        default:
            stateString = "stopped"
        }

        _ = try? await rawServerRequest(
            path: "/:/timeline",
            queryItems: [
                URLQueryItem(name: "ratingKey", value: ratingKey),
                URLQueryItem(name: "key", value: "/library/metadata/\(ratingKey)"),
                URLQueryItem(name: "state", value: stateString),
                URLQueryItem(name: "time", value: String(timeMs)),
                URLQueryItem(name: "duration", value: String(durationMs)),
            ]
        )
    }

    func scrobble(ratingKey: String) async throws {
        _ = try await rawServerRequest(
            path: "/:/scrobble",
            queryItems: [
                URLQueryItem(name: "key", value: ratingKey),
                URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            ]
        )
    }

    func unscrobble(ratingKey: String) async throws {
        _ = try await rawServerRequest(
            path: "/:/unscrobble",
            queryItems: [
                URLQueryItem(name: "key", value: ratingKey),
                URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            ]
        )
    }

    func setWatched(_ watched: Bool, ratingKey: String) async throws {
        if watched {
            try await scrobble(ratingKey: ratingKey)
        } else {
            try await unscrobble(ratingKey: ratingKey)
        }
    }

    func directPlayURL(for part: PlexMediaPart) -> URL? {
        guard let baseURL = serverBaseURL else { return nil }
        let urlString = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast()) + part.key
            : baseURL.absoluteString + part.key
        guard var components = URLComponents(string: urlString) else { return nil }
        var items = components.queryItems ?? []
        if let token = authToken {
            items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}
