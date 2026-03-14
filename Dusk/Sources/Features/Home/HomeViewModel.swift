import Foundation
import SwiftUI

@MainActor @Observable
final class HomeViewModel {
    private var maxRecentlyAddedItems = 10

    private(set) var hubs: [PlexHub] = []
    private(set) var continueWatching: [PlexItem] = []
    private(set) var isLoading = false
    private(set) var error: String?

    private let plexService: PlexService

    init(plexService: PlexService) {
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
            async let fetchedHubs = plexService.getHubs()
            async let fetchedOnDeck = plexService.getContinueWatching()

            let baseHubs = try await fetchedHubs.filter { !shouldHideHomeHub($0) }
            let newHubs = try await expandedRecentlyAddedHubs(from: baseHubs)
            let newContinueWatching = try await fetchedOnDeck.filter { !shouldHideHomeItem($0) }

            if isInitialLoad {
                hubs = newHubs
                continueWatching = newContinueWatching
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hubs = newHubs
                    continueWatching = newContinueWatching
                }
            }
            error = nil
        } catch {
            // On refresh, only show error if we have no existing data
            if isInitialLoad {
                self.error = error.localizedDescription
            }
        }

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

    /// Resolve the best poster URL for an item.
    func posterURL(for item: PlexItem, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: item.preferredPosterPath, width: width, height: height)
    }

    /// Resolve the best landscape artwork URL for continue watching cards.
    func landscapeImageURL(for item: PlexItem, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: item.preferredLandscapePath, width: width, height: height)
    }

    /// Progress fraction (0–1) for partially watched items. Nil if unwatched.
    func progress(for item: PlexItem) -> Double? {
        MediaTextFormatter.progress(durationMs: item.duration, offsetMs: item.viewOffset)
    }

    /// Display title for continue watching items.
    /// Episodes show the series title; movies just show the title.
    func displayTitle(for item: PlexItem) -> String {
        if item.type == .episode, let show = item.grandparentTitle {
            return show
        }
        return item.title
    }

    /// Subtitle for continue watching: natural-language episode label or year.
    func displaySubtitle(for item: PlexItem) -> String? {
        if item.type == .episode {
            return MediaTextFormatter.seasonEpisodeLabel(season: item.parentIndex, episode: item.index) ?? item.title
        }
        return item.year.map(String.init)
    }

    func visibleItems(in hub: PlexHub) -> [PlexItem] {
        hub.items.filter { !shouldHideHomeItem($0) }
    }

    func inlineItems(in hub: PlexHub, maxRecentlyAddedItems: Int) -> [PlexItem] {
        let items = visibleItems(in: hub)

        guard isRecentlyAddedHub(hub) else { return items }
        return Array(items.prefix(maxRecentlyAddedItems))
    }

    func shouldShowAll(for hub: PlexHub, maxRecentlyAddedItems: Int) -> Bool {
        guard isRecentlyAddedHub(hub), hub.key != nil else { return false }

        let visibleCount = visibleItems(in: hub).count
        return visibleCount > maxRecentlyAddedItems ||
            hub.more == true ||
            (hub.size ?? 0) > maxRecentlyAddedItems
    }

    func isRecentlyAddedHub(_ hub: PlexHub) -> Bool {
        let normalizedTitle = hub.title.lowercased()

        guard normalizedTitle.contains("recently added") else { return false }

        let itemTypes = Set(visibleItems(in: hub).map(\.type))
        return !itemTypes.isEmpty && itemTypes.isSubset(of: [.movie, .show, .season, .episode])
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

    private func shouldHideHomeHub(_ hub: PlexHub) -> Bool {
        let fields = [hub.title, hub.key, hub.hubIdentifier]
            .compactMap { $0?.lowercased() }

        return fields.contains(where: { value in
            value.contains("continue watching") ||
            value.contains("continuewatching") ||
            value.contains("on deck") ||
            value.contains("ondeck") ||
            value.contains("playlist") ||
            value.contains("playlists")
        })
    }

    private func shouldHideHomeItem(_ item: PlexItem) -> Bool {
        let normalizedKey = item.key.lowercased()

        switch item.type {
        case .artist, .album, .track, .unknown:
            return true
        default:
            return normalizedKey.contains("/playlists/")
        }
    }
}
