import Foundation

@MainActor
@Observable
final class ShowDetailViewModel {
    private let plexService: PlexService
    let ratingKey: String

    private(set) var details: PlexMediaDetails?
    private(set) var seasons: [PlexSeason] = []
    private(set) var isLoading = false
    private(set) var error: String?

    init(ratingKey: String, plexService: PlexService) {
        self.ratingKey = ratingKey
        self.plexService = plexService
    }

    func load() async {
        guard details == nil else { return }
        isLoading = true
        error = nil

        do {
            try await reload()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func markSeason(_ season: PlexSeason, watched: Bool) async {
        do {
            if watched {
                try await plexService.scrobble(ratingKey: season.ratingKey)
            } else {
                try await plexService.unscrobble(ratingKey: season.ratingKey)
            }

            try await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Computed Helpers

    var genreText: String? {
        guard let genres = details?.genres, !genres.isEmpty else { return nil }
        return genres.prefix(3).map(\.tag).joined(separator: ", ")
    }

    var seasonCountText: String? {
        guard let count = details?.childCount, count > 0 else {
            guard !seasons.isEmpty else { return nil }
            return "\(seasons.count) Season\(seasons.count == 1 ? "" : "s")"
        }
        return "\(count) Season\(count == 1 ? "" : "s")"
    }

    var episodeCountText: String? {
        guard let count = details?.leafCount, count > 0 else { return nil }
        return "\(count) Episode\(count == 1 ? "" : "s")"
    }

    func backdropURL(width: Int, height: Int) -> URL? {
        plexService.imageURL(for: details?.art)
    }

    func posterURL(width: Int, height: Int) -> URL? {
        plexService.imageURL(for: details?.thumb, width: width, height: height)
    }

    func seasonPosterURL(_ season: PlexSeason, width: Int, height: Int) -> URL? {
        plexService.imageURL(
            for: season.thumb ?? season.parentThumb ?? season.art,
            width: width,
            height: height
        )
    }

    func seasonSubtitle(_ season: PlexSeason) -> String? {
        guard let count = season.leafCount, count > 0 else { return nil }
        return "\(count) Episode\(count == 1 ? "" : "s")"
    }

    func seasonProgress(_ season: PlexSeason) -> Double? {
        guard let total = season.leafCount,
              let viewed = season.viewedLeafCount,
              total > 0,
              viewed > 0 else { return nil }
        return Double(viewed) / Double(total)
    }

    private func reload() async throws {
        async let detailsReq = plexService.getMediaDetails(ratingKey: ratingKey)
        async let seasonsReq = plexService.getSeasons(showKey: ratingKey)
        let (loadedDetails, loadedSeasons) = try await (detailsReq, seasonsReq)
        details = loadedDetails
        seasons = loadedSeasons.sorted { $0.index < $1.index }
    }
}

@MainActor
@Observable
final class SeasonDetailViewModel {
    private let plexService: PlexService
    let ratingKey: String

    private(set) var details: PlexMediaDetails?
    private(set) var episodes: [PlexEpisode] = []
    private(set) var isLoading = false
    private(set) var error: String?

    init(ratingKey: String, plexService: PlexService) {
        self.ratingKey = ratingKey
        self.plexService = plexService
    }

    func load() async {
        guard details == nil else { return }
        isLoading = true
        error = nil

        do {
            async let detailsReq = plexService.getMediaDetails(ratingKey: ratingKey)
            async let episodesReq = plexService.getEpisodes(seasonKey: ratingKey)
            let (loadedDetails, loadedEpisodes) = try await (detailsReq, episodesReq)
            details = loadedDetails
            episodes = loadedEpisodes.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func toggleWatched(for episode: PlexEpisode) async {
        do {
            if episode.isWatched {
                try await plexService.unscrobble(ratingKey: episode.ratingKey)
            } else {
                try await plexService.scrobble(ratingKey: episode.ratingKey)
            }

            async let detailsReq = plexService.getMediaDetails(ratingKey: ratingKey)
            async let episodesReq = plexService.getEpisodes(seasonKey: ratingKey)
            let (loadedDetails, loadedEpisodes) = try await (detailsReq, episodesReq)
            details = loadedDetails
            episodes = loadedEpisodes.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    var showTitle: String? {
        details?.grandparentTitle ?? episodes.first?.grandparentTitle
    }

    var showRatingKey: String? {
        details?.parentRatingKey ?? episodes.first?.grandparentRatingKey
    }

    var episodeCountText: String? {
        let count = details?.leafCount ?? details?.childCount ?? episodes.count
        guard count > 0 else { return nil }
        return "\(count) Episode\(count == 1 ? "" : "s")"
    }

    var watchedEpisodeCountText: String? {
        let viewedCount = details?.viewedLeafCount ?? episodes.filter(\.isWatched).count
        guard viewedCount > 0 else { return nil }
        return "\(viewedCount) watched"
    }

    func backdropURL(width: Int, height: Int) -> URL? {
        plexService.imageURL(for: details?.art)
    }

    func posterURL(width: Int, height: Int) -> URL? {
        plexService.imageURL(for: details?.thumb, width: width, height: height)
    }

    func episodeImageURL(_ episode: PlexEpisode, width: Int, height: Int) -> URL? {
        plexService.imageURL(
            for: episode.thumb ?? episode.grandparentThumb,
            width: width,
            height: height
        )
    }

    func episodeSubtitle(_ episode: PlexEpisode) -> String? {
        var parts: [String] = []

        if let duration = formattedDuration(for: episode) {
            parts.append(duration)
        }

        if let originallyAvailableAt = episode.originallyAvailableAt, !originallyAvailableAt.isEmpty {
            parts.append(originallyAvailableAt)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func episodeLabel(_ episode: PlexEpisode) -> String? {
        guard let index = episode.index else { return nil }
        return "Episode \(index)"
    }

    func progress(for episode: PlexEpisode) -> Double? {
        guard let duration = episode.duration,
              let offset = episode.viewOffset,
              duration > 0,
              offset > 0 else { return nil }
        return Double(offset) / Double(duration)
    }

    private func formattedDuration(for episode: PlexEpisode) -> String? {
        guard let ms = episode.duration, ms > 0 else { return nil }
        let totalMinutes = ms / 60_000
        return "\(totalMinutes) min"
    }
}

@MainActor
@Observable
final class EpisodeDetailViewModel {
    private let plexService: PlexService
    let ratingKey: String

    private(set) var details: PlexMediaDetails?
    private(set) var isLoading = false
    private(set) var error: String?

    init(ratingKey: String, plexService: PlexService) {
        self.ratingKey = ratingKey
        self.plexService = plexService
    }

    func load() async {
        guard details == nil else { return }
        await reload()
    }

    func toggleWatched() async {
        guard let details else { return }

        do {
            if isWatched(details) {
                try await plexService.unscrobble(ratingKey: details.ratingKey)
            } else {
                try await plexService.scrobble(ratingKey: details.ratingKey)
            }
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    var seasonLabel: String? {
        guard let season = details?.parentIndex else { return nil }
        return "Season \(season)"
    }

    var seasonRatingKey: String? {
        details?.parentRatingKey
    }

    var episodeLabel: String? {
        guard let episode = details?.index else { return nil }
        return "Episode \(episode)"
    }

    var showTitle: String? {
        details?.grandparentTitle
    }

    var showRatingKey: String? {
        details?.grandparentRatingKey
    }

    var formattedDuration: String? {
        guard let ms = details?.duration, ms > 0 else { return nil }
        let totalMinutes = ms / 60_000
        return "\(totalMinutes) min"
    }

    var isWatched: Bool {
        guard let details else { return false }
        return isWatched(details)
    }

    func backdropURL(width: Int, height: Int) -> URL? {
        plexService.imageURL(for: details?.thumb ?? details?.art)
    }

    func posterURL(width: Int, height: Int) -> URL? {
        plexService.imageURL(
            for: details?.parentThumb ?? details?.grandparentThumb ?? details?.thumb,
            width: width,
            height: height
        )
    }

    private func reload() async {
        isLoading = true
        error = nil

        do {
            details = try await plexService.getMediaDetails(ratingKey: ratingKey)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func isWatched(_ details: PlexMediaDetails) -> Bool {
        guard let viewCount = details.viewCount else { return false }
        return viewCount > 0
    }
}

@MainActor
@Observable
final class ActorDetailViewModel {
    private let plexService: PlexService

    private(set) var person: PlexPersonReference
    private(set) var filmography: [PlexItem] = []
    private(set) var isLoading = false
    private(set) var error: String?

    init(person: PlexPersonReference, plexService: PlexService) {
        self.person = person
        self.plexService = plexService
    }

    func load() async {
        guard filmography.isEmpty else { return }
        isLoading = true
        error = nil

        do {
            if let personID = person.personID {
                async let personRequest = plexService.getPerson(personID: personID)
                async let mediaRequest = plexService.getPersonMedia(personID: personID)
                let (loadedPerson, loadedMedia) = try await (personRequest, mediaRequest)
                mergePersonDetails(loadedPerson)
                filmography = sortFilmography(loadedMedia)
            } else {
                filmography = sortFilmography(try await fallbackFilmography())
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    var movies: [PlexItem] {
        filmography.filter { $0.type == .movie }
    }

    var shows: [PlexItem] {
        filmography.filter { $0.type == .show }
    }

    var creditSummary: String {
        let parts = [
            movies.isEmpty ? nil : "\(movies.count) Movie\(movies.count == 1 ? "" : "s")",
            shows.isEmpty ? nil : "\(shows.count) Show\(shows.count == 1 ? "" : "s")",
        ].compactMap { $0 }

        return parts.isEmpty ? "No titles found in this library" : parts.joined(separator: " · ")
    }

    func personImageURL(size: Int) -> URL? {
        plexService.imageURL(for: person.thumb, width: size, height: size)
    }

    func posterURL(for item: PlexItem, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: item.preferredPosterPath, width: width, height: height)
    }

    func subtitle(for item: PlexItem) -> String? {
        switch item.type {
        case .movie:
            return item.year.map(String.init)
        case .show:
            var parts: [String] = []
            if let year = item.year {
                parts.append(String(year))
            }
            if let seasons = item.childCount, seasons > 0 {
                parts.append("\(seasons) Season\(seasons == 1 ? "" : "s")")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        default:
            return nil
        }
    }

    private func mergePersonDetails(_ loadedPerson: PlexPerson) {
        person = PlexPersonReference(
            personID: loadedPerson.personID ?? person.personID,
            name: loadedPerson.tag,
            thumb: loadedPerson.thumb ?? person.thumb,
            roleName: person.roleName
        )
    }

    private func fallbackFilmography() async throws -> [PlexItem] {
        let results = try await plexService.search(query: person.name)
        let supportedItems = results
            .flatMap(\.items)
            .filter { $0.type == .movie || $0.type == .show }

        let exactRoleMatches = supportedItems.filter { item in
            item.roles?.contains(where: { $0.tag.caseInsensitiveCompare(person.name) == .orderedSame }) == true
        }

        return exactRoleMatches.isEmpty ? supportedItems : exactRoleMatches
    }

    private func sortFilmography(_ items: [PlexItem]) -> [PlexItem] {
        var seen = Set<String>()
        return items
            .filter { seen.insert($0.ratingKey).inserted }
            .sorted { lhs, rhs in
                let leftYear = lhs.year ?? Int.min
                let rightYear = rhs.year ?? Int.min
                if leftYear != rightYear {
                    return leftYear > rightYear
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }
}
