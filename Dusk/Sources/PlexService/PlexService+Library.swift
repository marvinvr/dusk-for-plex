import Foundation

extension PlexService {
    func getLibraries() async throws -> [PlexLibrary] {
        try await fetchDirectories(path: "/library/sections")
    }

    func getLibraryItems(sectionId: String, start: Int = 0, size: Int = 50) async throws -> [PlexItem] {
        try await fetchMetadata(
            path: "/library/sections/\(sectionId)/all",
            queryItems: [
                URLQueryItem(name: "X-Plex-Container-Start", value: String(start)),
                URLQueryItem(name: "X-Plex-Container-Size", value: String(size)),
            ]
        )
    }

    func getSeasons(showKey: String) async throws -> [PlexSeason] {
        try await fetchMetadata(path: "/library/metadata/\(showKey)/children")
    }

    func getEpisodes(seasonKey: String) async throws -> [PlexEpisode] {
        try await fetchMetadata(path: "/library/metadata/\(seasonKey)/children")
    }

    func getNextEpisode(after episode: PlexMediaDetails) async throws -> PlexEpisode? {
        guard episode.type == .episode,
              let seasonKey = episode.parentRatingKey,
              let showKey = episode.grandparentRatingKey else {
            return nil
        }

        let currentSeasonEpisodes = try await getEpisodes(seasonKey: seasonKey)
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }

        if let currentEpisodeIndex = currentSeasonEpisodes.firstIndex(where: { $0.ratingKey == episode.ratingKey }),
           currentEpisodeIndex < currentSeasonEpisodes.index(before: currentSeasonEpisodes.endIndex) {
            return currentSeasonEpisodes[currentSeasonEpisodes.index(after: currentEpisodeIndex)]
        }

        if let currentEpisodeNumber = episode.index,
           let nextEpisodeInSeason = currentSeasonEpisodes.first(where: { ($0.index ?? 0) > currentEpisodeNumber }) {
            return nextEpisodeInSeason
        }

        let seasons = try await getSeasons(showKey: showKey)
            .sorted { $0.index < $1.index }

        let currentSeasonIndex = episode.parentIndex
            ?? seasons.first(where: { $0.ratingKey == seasonKey })?.index

        guard let currentSeasonIndex else { return nil }

        for season in seasons where season.index > currentSeasonIndex {
            let episodes = try await getEpisodes(seasonKey: season.ratingKey)
                .sorted { ($0.index ?? 0) < ($1.index ?? 0) }

            if let firstEpisode = episodes.first {
                return firstEpisode
            }
        }

        return nil
    }

    func getHubs() async throws -> [PlexHub] {
        try await fetchHubs(path: "/hubs")
    }

    func getContinueWatching() async throws -> [PlexItem] {
        try await fetchMetadata(path: "/library/onDeck")
    }

    func getHubItems(hubKey: String) async throws -> [PlexItem] {
        try await fetchMetadata(path: hubKey)
    }

    func search(query: String) async throws -> [PlexSearchResult] {
        let hubs = try await fetchHubs(
            path: "/hubs/search",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "limit", value: "10"),
                URLQueryItem(name: "includeCollections", value: "0"),
            ]
        )

        return hubs
            .filter { !$0.items.isEmpty }
            .map { PlexSearchResult(hub: $0) }
    }

    func getMediaDetails(ratingKey: String) async throws -> PlexMediaDetails {
        let items: [PlexMediaDetails] = try await fetchMetadata(
            path: "/library/metadata/\(ratingKey)",
            queryItems: [
                URLQueryItem(name: "includeMarkers", value: "1"),
            ]
        )

        guard let details = items.first else {
            throw PlexServiceError.decodingError("No metadata found for ratingKey \(ratingKey)")
        }

        return details
    }
}
