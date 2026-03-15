import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LibraryRecommendationsView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var viewModel: LibraryRecommendationsViewModel

    private let navigationTitle: String

    private let continueWatchingCardWidth: CGFloat = 280
    private let continueWatchingAspectRatio: CGFloat = 16.0 / 9.0

    init(
        library: PlexLibrary,
        plexService: PlexService,
        navigationTitle: String
    ) {
        self.navigationTitle = navigationTitle
        _viewModel = State(initialValue: LibraryRecommendationsViewModel(
            library: library,
            plexService: plexService
        ))
    }

    var body: some View {
        ZStack {
            Color.duskBackground.ignoresSafeArea()

            if !viewModel.hasLoadedOnce, viewModel.error == nil, viewModel.hubs.isEmpty, viewModel.continueWatching.isEmpty {
                FeatureLoadingView()
            } else {
                contentView
            }
        }
        .task {
            await viewModel.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit)
        }
        .onChange(of: playback.showPlayer) { _, isShowing in
            if !isShowing {
                Task { await viewModel.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppNavigationRoute.library(viewModel.library)) {
                    Label("Browse Library", systemImage: "square.grid.2x2")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .duskSuppressTVOSButtonChrome()
            }
        }
        .duskNavigationTitle(navigationTitle)
        .duskNavigationBarTitleDisplayModeLarge()
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error = viewModel.error, viewModel.hubs.isEmpty, viewModel.continueWatching.isEmpty {
                    FeatureErrorView(message: error) {
                        Task { await viewModel.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit) }
                    }
                    .padding(.top, 24)
                } else if viewModel.hubs.isEmpty, viewModel.continueWatching.isEmpty {
                    emptyView
                        .padding(.top, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !viewModel.continueWatching.isEmpty {
                            continueWatchingSection
                        }

                        ForEach(viewModel.hubs) { hub in
                            let items = viewModel.inlineItems(in: hub)

                            if !items.isEmpty {
                                hubSection(hub, items: items)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 88)
        }
        .refreshable {
            await viewModel.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit)
        }
    }

    private var continueWatchingSection: some View {
        let imageWidth = Int(continueWatchingCardWidth.rounded(.up))
        let imageHeight = Int((continueWatchingCardWidth / continueWatchingAspectRatio).rounded(.up))

        return MediaCarousel(title: viewModel.continueWatchingTitle) {
            ForEach(viewModel.continueWatching) { item in
                #if os(tvOS)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        play(item)
                    } label: {
                        PosterArtwork(
                            imageURL: viewModel.landscapeImageURL(for: item, width: imageWidth, height: imageHeight),
                            progress: viewModel.progress(for: item),
                            width: continueWatchingCardWidth,
                            imageAspectRatio: continueWatchingAspectRatio,
                            showsPlayOverlay: true
                        )
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()

                    PosterCardText(
                        title: viewModel.displayTitle(for: item),
                        subtitle: viewModel.displaySubtitle(for: item),
                        width: continueWatchingCardWidth
                    )
                }
                .frame(width: continueWatchingCardWidth, alignment: .topLeading)
                .contextMenu {
                    PlexItemContextMenuContent(
                        item: item,
                        onMarkWatched: {
                            Task { await viewModel.setWatched(true, for: item) }
                        },
                        onMarkUnwatched: {
                            Task { await viewModel.setWatched(false, for: item) }
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
                        imageURL: viewModel.landscapeImageURL(for: item, width: imageWidth, height: imageHeight),
                        title: viewModel.displayTitle(for: item),
                        subtitle: viewModel.displaySubtitle(for: item),
                        progress: viewModel.progress(for: item),
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
                            Task { await viewModel.setWatched(true, for: item) }
                        },
                        onMarkUnwatched: {
                            Task { await viewModel.setWatched(false, for: item) }
                        },
                        detailsRoute: AppNavigationRoute.destination(for: item),
                        detailsLabel: detailsLabel(for: item)
                    )
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private func hubSection(_ hub: PlexHub, items: [PlexItem]) -> some View {
        let imageWidth = 130
        let imageHeight = 195
        let showsShowAll = viewModel.shouldShowAll(for: hub)

        MediaCarousel(
            title: viewModel.normalizedTitle(for: hub),
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
                            imageURL: viewModel.posterURL(for: item, width: imageWidth, height: imageHeight),
                            width: 130,
                            imageAspectRatio: 2.0 / 3.0
                        )
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()

                    PosterCardText(
                        title: item.title,
                        subtitle: viewModel.subtitle(for: item),
                        width: 130
                    )
                }
                .frame(width: 130, alignment: .topLeading)
                .contextMenu {
                    PlexItemContextMenuContent(
                        item: item,
                        onMarkWatched: {
                            Task { await viewModel.setWatched(true, for: item) }
                        },
                        onMarkUnwatched: {
                            Task { await viewModel.setWatched(false, for: item) }
                        }
                    )
                }
                #else
                NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                    PosterCard(
                        imageURL: viewModel.posterURL(for: item, width: imageWidth, height: imageHeight),
                        title: item.title,
                        subtitle: viewModel.subtitle(for: item)
                    )
                }
                .buttonStyle(.plain)
                .duskSuppressTVOSButtonChrome()
                .contextMenu {
                    PlexItemContextMenuContent(
                        item: item,
                        onMarkWatched: {
                            Task { await viewModel.setWatched(true, for: item) }
                        },
                        onMarkUnwatched: {
                            Task { await viewModel.setWatched(false, for: item) }
                        }
                    )
                }
                #endif
            }
        }
    }

    private var emptyView: some View {
        FeatureEmptyStateView(
            systemImage: viewModel.library.libraryType?.systemImage ?? "rectangle.stack",
            title: "No recommendations right now"
        )
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
