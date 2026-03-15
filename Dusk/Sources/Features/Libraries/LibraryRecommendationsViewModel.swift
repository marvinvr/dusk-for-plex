import Foundation
import SwiftUI

@MainActor
@Observable
final class LibraryRecommendationsViewModel {
    private var maxRecentlyAddedItems = 10

    let library: PlexLibrary

    private(set) var hubs: [PlexHub] = []
    private(set) var continueWatching: [PlexItem] = []
    private(set) var continueWatchingTitle = "Continue Watching"
    private(set) var isLoading = false
    private(set) var hasLoadedOnce = false
    private(set) var error: String?

    private let plexService: PlexService

    init(library: PlexLibrary, plexService: PlexService) {
        self.library = library
        self.plexService = plexService
    }

    func load(maxRecentlyAddedItems: Int? = nil) async {
        if let maxRecentlyAddedItems {
            self.maxRecentlyAddedItems = maxRecentlyAddedItems
        }

        let isInitialLoad = hubs.isEmpty && continueWatching.isEmpty

        if isInitialLoad {
            isLoading = true
            error = nil
        }

        do {
            let fetchedHubs = try await plexService.getLibraryHubs(
                sectionId: library.key,
                count: max(maxRecentlyAddedItems ?? self.maxRecentlyAddedItems, 12)
            )

            let baseHubs = fetchedHubs.filter { !shouldHideHub($0) }
            let expandedHubs = try await expandedRecentlyAddedHubs(from: baseHubs)

            let continueWatchingHub = expandedHubs.first(where: isContinueWatchingHub)
            let recommendationHubs = expandedHubs.filter { !isContinueWatchingHub($0) }
            let continueWatchingItems = continueWatchingHub.map(visibleItems(in:)) ?? []
            let continueWatchingTitle = continueWatchingHub.map(normalizedContinueWatchingTitle(for:)) ?? "Continue Watching"

            if isInitialLoad {
                self.hubs = recommendationHubs
                self.continueWatching = continueWatchingItems
                self.continueWatchingTitle = continueWatchingTitle
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.hubs = recommendationHubs
                    self.continueWatching = continueWatchingItems
                    self.continueWatchingTitle = continueWatchingTitle
                }
            }

            error = nil
        } catch {
            if isInitialLoad {
                self.error = error.localizedDescription
            }
        }

        hasLoadedOnce = true
        isLoading = false
    }

    func setWatched(_ watched: Bool, for item: PlexItem) async {
        do {
            try await plexService.setWatched(watched, ratingKey: item.ratingKey)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func posterURL(for item: PlexItem, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: item.preferredPosterPath, width: width, height: height)
    }

    func landscapeImageURL(for item: PlexItem, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: item.preferredLandscapePath, width: width, height: height)
    }

    func progress(for item: PlexItem) -> Double? {
        MediaTextFormatter.progress(durationMs: item.duration, offsetMs: item.viewOffset)
    }

    func displayTitle(for item: PlexItem) -> String {
        if item.type == .episode, let show = item.grandparentTitle {
            return show
        }

        return item.title
    }

    func displaySubtitle(for item: PlexItem) -> String? {
        if item.type == .episode {
            return MediaTextFormatter.seasonEpisodeLabel(season: item.parentIndex, episode: item.index) ?? item.title
        }

        return item.year.map(String.init)
    }

    func subtitle(for item: PlexItem) -> String? {
        switch item.type {
        case .movie:
            return item.year.map(String.init)
        case .show:
            if let childCount = item.childCount {
                return MediaTextFormatter.seasonCount(childCount)?.lowercased()
            }
            return item.year.map(String.init)
        case .episode:
            return MediaTextFormatter.seasonEpisodeLabel(season: item.parentIndex, episode: item.index) ?? item.grandparentTitle
        default:
            return item.year.map(String.init)
        }
    }

    func visibleItems(in hub: PlexHub) -> [PlexItem] {
        hub.items.filter { !shouldHideItem($0) }
    }

    func inlineItems(in hub: PlexHub) -> [PlexItem] {
        let items = visibleItems(in: hub)

        guard isRecentlyAddedHub(hub) else { return items }
        return Array(items.prefix(maxRecentlyAddedItems))
    }

    func shouldShowAll(for hub: PlexHub) -> Bool {
        guard hub.key != nil else { return false }

        let visibleCount = visibleItems(in: hub).count

        if isRecentlyAddedHub(hub) {
            return visibleCount > maxRecentlyAddedItems ||
                hub.more == true ||
                (hub.size ?? 0) > maxRecentlyAddedItems
        }

        return hub.more == true || (hub.size ?? visibleCount) > visibleCount
    }

    func normalizedTitle(for hub: PlexHub) -> String {
        guard hub.title.lowercased().contains("recently added") else { return hub.title }

        let suffix = hub.title.replacingOccurrences(
            of: "Recently Added",
            with: "",
            options: [.caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return suffix.isEmpty ? "Recently added" : "Recently added \(suffix)"
    }

    private func normalizedContinueWatchingTitle(for hub: PlexHub) -> String {
        let title = hub.title.lowercased()

        if title.contains("continue watching") || title.contains("on deck") || title.contains("in progress") || title.contains("inprogress") {
            return "Continue Watching"
        }

        return hub.title
    }

    private func expandedRecentlyAddedHubs(from hubs: [PlexHub]) async throws -> [PlexHub] {
        var expandedHubs: [PlexHub] = []
        expandedHubs.reserveCapacity(hubs.count)

        for hub in hubs {
            guard isRecentlyAddedHub(hub), let hubKey = hub.key else {
                expandedHubs.append(hub)
                continue
            }

            let items = try await plexService.getHubItems(
                hubKey: hubKey,
                size: maxRecentlyAddedItems
            )

            expandedHubs.append(
                PlexHub(
                    key: hub.key,
                    title: hub.title,
                    type: hub.type,
                    hubIdentifier: hub.hubIdentifier,
                    size: hub.size,
                    more: hub.more,
                    items: items
                )
            )
        }

        return expandedHubs
    }

    private func isContinueWatchingHub(_ hub: PlexHub) -> Bool {
        let fields = [hub.title, hub.key, hub.hubIdentifier]
            .compactMap { $0?.lowercased() }

        return fields.contains { value in
            value.contains("continue watching") ||
            value.contains("continuewatching") ||
            value.contains("on deck") ||
            value.contains("ondeck") ||
            value.contains("inprogress")
        }
    }

    private func isRecentlyAddedHub(_ hub: PlexHub) -> Bool {
        let normalizedTitle = hub.title.lowercased()

        guard normalizedTitle.contains("recently added") else { return false }

        let itemTypes = Set(visibleItems(in: hub).map(\.type))
        return !itemTypes.isEmpty && itemTypes.isSubset(of: [.movie, .show, .season, .episode])
    }

    private func shouldHideHub(_ hub: PlexHub) -> Bool {
        let fields = [hub.title, hub.key, hub.hubIdentifier]
            .compactMap { $0?.lowercased() }

        return fields.contains { value in
            value.contains("playlist") || value.contains("playlists")
        }
    }

    private func shouldHideItem(_ item: PlexItem) -> Bool {
        let normalizedKey = item.key.lowercased()

        switch item.type {
        case .artist, .album, .track, .unknown:
            return true
        default:
            return normalizedKey.contains("/playlists/")
        }
    }
}
