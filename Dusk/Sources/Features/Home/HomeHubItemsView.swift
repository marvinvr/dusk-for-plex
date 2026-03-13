import SwiftUI

struct HomeHubItemsView: View {
    @State private var viewModel: HomeHubItemsViewModel

    private let horizontalPadding: CGFloat = 12
    private let gridSpacing: CGFloat = 12
    private let gridRowSpacing: CGFloat = 18
    private let preferredPosterWidth: CGFloat = 104
    private let minimumColumnCount = 2

    init(hub: PlexHub, plexService: PlexService) {
        _viewModel = State(initialValue: HomeHubItemsViewModel(
            hub: hub,
            plexService: plexService
        ))
    }

    var body: some View {
        ZStack {
            Color.duskBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.items.isEmpty {
                FeatureLoadingView()
            } else if let error = viewModel.error, viewModel.items.isEmpty {
                FeatureErrorView(message: error) {
                    Task { await viewModel.reloadItems() }
                }
            } else if viewModel.items.isEmpty {
                emptyView
            } else {
                itemsGrid
            }
        }
        .duskNavigationTitle(viewModel.navigationTitle)
        .duskNavigationBarTitleDisplayModeLarge()
        .task {
            await viewModel.loadItems()
        }
    }

    private var itemsGrid: some View {
        GeometryReader { geometry in
            let layout = AdaptivePosterGridLayout.make(
                containerWidth: geometry.size.width,
                horizontalPadding: horizontalPadding,
                gridSpacing: gridSpacing,
                preferredPosterWidth: preferredPosterWidth,
                minimumColumnCount: minimumColumnCount
            )
            let imageWidth = Int(layout.posterWidth.rounded(.up))
            let imageHeight = Int((layout.posterWidth * 1.5).rounded(.up))

            ScrollView {
                LazyVGrid(columns: layout.columns, spacing: gridRowSpacing) {
                    ForEach(viewModel.items) { item in
                        #if os(tvOS)
                        VStack(alignment: .leading, spacing: 6) {
                            NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                                PosterArtwork(
                                    imageURL: viewModel.posterURL(for: item, width: imageWidth, height: imageHeight),
                                    progress: viewModel.progress(for: item),
                                    width: layout.posterWidth
                                )
                            }
                            .buttonStyle(.plain)
                            .duskSuppressTVOSButtonChrome()

                            PosterCardText(
                                title: item.title,
                                subtitle: viewModel.subtitle(for: item),
                                width: layout.posterWidth
                            )
                        }
                        .frame(width: layout.posterWidth, alignment: .topLeading)
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
                                subtitle: viewModel.subtitle(for: item),
                                progress: viewModel.progress(for: item),
                                width: layout.posterWidth
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var emptyView: some View {
        FeatureEmptyStateView(systemImage: "film", title: "No items found")
    }
}
