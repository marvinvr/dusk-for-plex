import SwiftUI

struct ShowDetailView: View {
    @Environment(PlexService.self) private var plexService
    @State private var viewModel: ShowDetailViewModel

    private let horizontalPadding: CGFloat = 20
    private let gridSpacing: CGFloat = 14
    private let preferredPosterWidth: CGFloat = 120
    private let minimumColumnCount = 2

    init(ratingKey: String, plexService: PlexService) {
        _viewModel = State(initialValue: ShowDetailViewModel(
            ratingKey: ratingKey,
            plexService: plexService
        ))
    }

    var body: some View {
        ZStack {
            Color.duskBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.details == nil {
                FeatureLoadingView()
            } else if let error = viewModel.error, viewModel.details == nil {
                FeatureErrorView(message: error) {
                    Task { await viewModel.load() }
                }
            } else if let details = viewModel.details {
                contentView(details)
            }
        }
        .duskNavigationBarTitleDisplayModeInline()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func contentView(_ details: PlexMediaDetails) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection(details, topInset: geometry.safeAreaInsets.top, containerWidth: geometry.size.width)
                    metadataSection(details)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 20)

                    if let summary = details.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(Color.duskTextSecondary)
                            .lineSpacing(4)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 16)
                    }

                    seasonsSection(width: geometry.size.width)
                        .padding(.top, 24)

                    if let roles = details.roles, !roles.isEmpty {
                        castSection(roles)
                            .padding(.top, 24)
                            .padding(.bottom, 40)
                    }
                }
                .padding(.top, -geometry.safeAreaInsets.top)
                .frame(width: geometry.size.width, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func heroSection(_ details: PlexMediaDetails, topInset: CGFloat, containerWidth: CGFloat) -> some View {
        let heroHeight = 380 + topInset
        let posterWidth: CGFloat = 120
        let backdropWidth = Int(containerWidth.rounded(.up))
        let backdropHeight = Int(heroHeight.rounded(.up))

        ZStack(alignment: .bottomLeading) {
            DetailHeroBackdrop(
                imageURL: viewModel.backdropURL(width: backdropWidth, height: backdropHeight),
                height: heroHeight
            )

            LinearGradient(
                colors: [.clear, Color.duskBackground.opacity(0.6), Color.duskBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)

            HStack(alignment: .bottom, spacing: 16) {
                if let posterURL = viewModel.posterURL(width: 120, height: 180) {
                    AsyncImage(url: posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(2 / 3, contentMode: .fit)
                        default:
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.duskSurface)
                                .aspectRatio(2 / 3, contentMode: .fit)
                        }
                    }
                    .frame(width: posterWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(details.title)
                        .font(.title2.bold())
                        .foregroundStyle(Color.duskTextPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    metadataTagline(details)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 16)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func metadataTagline(_ details: PlexMediaDetails) -> some View {
        let parts = [
            details.year.map(String.init),
            details.contentRating,
            viewModel.seasonCountText,
            viewModel.episodeCountText,
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Color.duskTextSecondary)
        }
    }

    @ViewBuilder
    private func metadataSection(_ details: PlexMediaDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let genres = viewModel.genreText {
                Text(genres)
                    .font(.subheadline)
                    .foregroundStyle(Color.duskTextSecondary)
            }

            if let rating = details.rating {
                HStack(spacing: 12) {
                    ratingBadge(
                        icon: "star.fill",
                        value: String(format: "%.1f", rating),
                        color: .yellow
                    )

                    if let audience = details.audienceRating {
                        ratingBadge(
                            icon: "person.fill",
                            value: String(format: "%.0f%%", audience * 10),
                            color: Color.duskAccent
                        )
                    }
                }
            }

            if let studio = details.studio {
                Text(studio)
                    .font(.caption)
                    .foregroundStyle(Color.duskTextSecondary)
            }
        }
    }

    private func ratingBadge(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)

            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.duskTextPrimary)
        }
    }

    @ViewBuilder
    private func castSection(_ roles: [PlexRole]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast")
                .font(.headline)
                .foregroundStyle(Color.duskTextPrimary)
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(roles.prefix(20).enumerated()), id: \.offset) { _, role in
                        ActorCreditCard(person: PlexPersonReference(role: role), plexService: plexService)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private func seasonsSection(width: CGFloat) -> some View {
        if !viewModel.seasons.isEmpty {
            let layout = AdaptivePosterGridLayout.make(
                containerWidth: width,
                horizontalPadding: horizontalPadding,
                gridSpacing: gridSpacing,
                preferredPosterWidth: preferredPosterWidth,
                minimumColumnCount: minimumColumnCount
            )
            let imageWidth = Int(layout.posterWidth.rounded(.up))
            let imageHeight = Int((layout.posterWidth * 1.5).rounded(.up))

            VStack(alignment: .leading, spacing: 16) {
                Text("Seasons")
                    .font(.headline)
                    .foregroundStyle(Color.duskTextPrimary)
                    .padding(.horizontal, horizontalPadding)

                LazyVGrid(columns: layout.columns, alignment: .leading, spacing: 18) {
                    ForEach(viewModel.seasons) { season in
                        #if os(tvOS)
                        VStack(alignment: .leading, spacing: 6) {
                            NavigationLink(value: AppNavigationRoute.media(type: .season, ratingKey: season.ratingKey)) {
                                PosterArtwork(
                                    imageURL: viewModel.seasonPosterURL(season, width: imageWidth, height: imageHeight),
                                    progress: viewModel.seasonProgress(season),
                                    width: layout.posterWidth
                                )
                            }
                            .buttonStyle(.plain)
                            .duskSuppressTVOSButtonChrome()

                            PosterCardText(
                                title: season.title,
                                subtitle: viewModel.seasonSubtitle(season),
                                width: layout.posterWidth
                            )
                        }
                        .frame(width: layout.posterWidth, alignment: .topLeading)
                        .contextMenu {
                            seasonContextMenu(season)
                        }
                        #else
                        NavigationLink(value: AppNavigationRoute.media(type: .season, ratingKey: season.ratingKey)) {
                            PosterCard(
                                imageURL: viewModel.seasonPosterURL(season, width: imageWidth, height: imageHeight),
                                title: season.title,
                                subtitle: viewModel.seasonSubtitle(season),
                                progress: viewModel.seasonProgress(season),
                                width: layout.posterWidth
                            )
                        }
                        .buttonStyle(.plain)
                        .duskSuppressTVOSButtonChrome()
                        .contextMenu {
                            seasonContextMenu(season)
                        }
                        #endif
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private func seasonContextMenu(_ season: PlexSeason) -> some View {
        if season.isPartiallyWatched {
            Button {
                Task { await viewModel.markSeason(season, watched: true) }
            } label: {
                Label("Mark Watched", systemImage: "eye")
            }

            Button {
                Task { await viewModel.markSeason(season, watched: false) }
            } label: {
                Label("Mark Unwatched", systemImage: "eye.slash")
            }
        } else if season.isFullyWatched {
            Button {
                Task { await viewModel.markSeason(season, watched: false) }
            } label: {
                Label("Mark Unwatched", systemImage: "eye.slash")
            }
        } else {
            Button {
                Task { await viewModel.markSeason(season, watched: true) }
            } label: {
                Label("Mark Watched", systemImage: "eye")
            }
        }
    }
}
