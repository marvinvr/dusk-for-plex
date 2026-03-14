import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HomeView: View {
    @Environment(PlexService.self) private var plexService
    @Environment(PlaybackCoordinator.self) private var playback
    @Binding var path: NavigationPath
    @State private var viewModel: HomeViewModel?

    private let continueWatchingCardWidth: CGFloat = 280
    private let continueWatchingAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.duskBackground.ignoresSafeArea()

                if let viewModel {
                    if viewModel.isLoading, viewModel.hubs.isEmpty {
                        FeatureLoadingView()
                    } else if let error = viewModel.error, viewModel.hubs.isEmpty {
                        FeatureErrorView(message: error) {
                            Task { await viewModel.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit) }
                        }
                    } else {
                        contentView(viewModel)
                    }
                }
            }
            .task(id: plexService.connectedServer?.clientIdentifier) {
                if viewModel == nil {
                    viewModel = HomeViewModel(plexService: plexService)
                }
                await viewModel?.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit)
            }
            .refreshable {
                await viewModel?.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit)
            }
            .duskNavigationTitle("Home")
            .duskNavigationBarTitleDisplayModeLarge()
            .duskAppNavigationDestinations()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(_ vm: HomeViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsHomeServerSubtitle, let serverName = plexService.connectedServer?.name {
                    homeSubtitle(serverName)
                        .padding(.bottom, 12)
                }

                LazyVStack(alignment: .leading, spacing: 18) {
                    // Continue Watching (Task B) — top of home
                    if !vm.continueWatching.isEmpty {
                        continueWatchingSection(vm)
                    }

                    // Hub carousels (Task A) — Recently Added, etc.
                    ForEach(vm.hubs) { hub in
                        let items = vm.inlineItems(
                            in: hub,
                            maxRecentlyAddedItems: recentlyAddedInlineItemLimit
                        )
                        if !items.isEmpty {
                            hubSection(hub, items: items, vm: vm)
                        }
                    }
                }
            }
            .padding(.top, showsHomeServerSubtitle ? -10 : 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 88)
        }
    }

    // MARK: - Continue Watching

    @ViewBuilder
    private func continueWatchingSection(_ vm: HomeViewModel) -> some View {
        let imageWidth = Int(continueWatchingCardWidth.rounded(.up))
        let imageHeight = Int((continueWatchingCardWidth / continueWatchingAspectRatio).rounded(.up))

        MediaCarousel(title: "Continue Watching") {
            ForEach(vm.continueWatching) { item in
                #if os(tvOS)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        play(item)
                    } label: {
                        PosterArtwork(
                            imageURL: vm.landscapeImageURL(for: item, width: imageWidth, height: imageHeight),
                            progress: vm.progress(for: item),
                            width: continueWatchingCardWidth,
                            imageAspectRatio: continueWatchingAspectRatio,
                            showsPlayOverlay: true
                        )
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()

                    PosterCardText(
                        title: vm.displayTitle(for: item),
                        subtitle: vm.displaySubtitle(for: item),
                        width: continueWatchingCardWidth
                    )
                }
                .frame(width: continueWatchingCardWidth, alignment: .topLeading)
                .contextMenu {
                    PlexItemContextMenuContent(
                        item: item,
                        onMarkWatched: {
                            Task { await vm.setWatched(true, for: item) }
                        },
                        onMarkUnwatched: {
                            Task { await vm.setWatched(false, for: item) }
                        },
                        detailsRoute: AppNavigationRoute.destination(for: item),
                        detailsLabel: detailsLabel(for: item)
                    )
                }
                #else
                Button {
                    play(item)
                } label: {
                    PosterCard(
                        imageURL: vm.landscapeImageURL(for: item, width: imageWidth, height: imageHeight),
                        title: vm.displayTitle(for: item),
                        subtitle: vm.displaySubtitle(for: item),
                        progress: vm.progress(for: item),
                        width: continueWatchingCardWidth,
                        imageAspectRatio: continueWatchingAspectRatio,
                        showsPlayOverlay: true
                    )
                }
                .buttonStyle(.plain)
                .duskSuppressTVOSButtonChrome()
                .contextMenu {
                    PlexItemContextMenuContent(
                        item: item,
                        onMarkWatched: {
                            Task { await vm.setWatched(true, for: item) }
                        },
                        onMarkUnwatched: {
                            Task { await vm.setWatched(false, for: item) }
                        },
                        detailsRoute: AppNavigationRoute.destination(for: item),
                        detailsLabel: detailsLabel(for: item)
                    )
                }
                #endif
            }
        }
    }

    // MARK: - Hub Section

    @ViewBuilder
    private func hubSection(_ hub: PlexHub, items: [PlexItem], vm: HomeViewModel) -> some View {
        let imageWidth = 130
        let imageHeight = 195
        let showsShowAll = vm.shouldShowAll(
            for: hub,
            maxRecentlyAddedItems: recentlyAddedInlineItemLimit
        )

        MediaCarousel(
            title: hub.title,
            headerAccessory: {
                if showsShowAll {
                    NavigationLink(value: AppNavigationRoute.hub(hub)) {
                        Text("Show all")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.duskAccent)
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()
                }
            }
        ) {
            ForEach(items) { item in
                #if os(tvOS)
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                        PosterArtwork(
                            imageURL: vm.posterURL(for: item, width: imageWidth, height: imageHeight),
                            width: 130,
                            imageAspectRatio: 2.0 / 3.0
                        )
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()

                    PosterCardText(
                        title: item.title,
                        subtitle: item.year.map(String.init),
                        width: 130
                    )
                }
                .frame(width: 130, alignment: .topLeading)
                .contextMenu {
                    PlexItemContextMenuContent(
                        item: item,
                        onMarkWatched: {
                            Task { await vm.setWatched(true, for: item) }
                        },
                        onMarkUnwatched: {
                            Task { await vm.setWatched(false, for: item) }
                        }
                    )
                }
                #else
                NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                    PosterCard(
                        imageURL: vm.posterURL(for: item, width: imageWidth, height: imageHeight),
                        title: item.title,
                        subtitle: item.year.map(String.init)
                    )
                }
                .buttonStyle(.plain)
                .duskSuppressTVOSButtonChrome()
                .contextMenu {
                    PlexItemContextMenuContent(
                        item: item,
                        onMarkWatched: {
                            Task { await vm.setWatched(true, for: item) }
                        },
                        onMarkUnwatched: {
                            Task { await vm.setWatched(false, for: item) }
                        }
                    )
                }
                #endif
            }
        }
    }

    // MARK: - Error

    private func homeSubtitle(_ serverName: String) -> some View {
        Text(serverName)
            .font(.subheadline)
            .foregroundStyle(Color.duskTextSecondary)
            .lineLimit(1)
            .padding(.horizontal, 20)
    }

    private var showsHomeServerSubtitle: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var recentlyAddedInlineItemLimit: Int {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 15 : 10
        #else
        10
        #endif
    }

    private func play(_ item: PlexItem) {
        Task {
            await playback.play(ratingKey: item.ratingKey)
        }
    }

    private func detailsLabel(for item: PlexItem) -> String {
        switch item.type {
        case .episode:
            "Go to Episode"
        case .movie:
            "Go to Movie"
        default:
            "View Details"
        }
    }
}
