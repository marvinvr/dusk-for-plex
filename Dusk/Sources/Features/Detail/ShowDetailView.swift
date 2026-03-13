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
                ProgressView()
                    .tint(Color.duskAccent)
            } else if let error = viewModel.error, viewModel.details == nil {
                errorView(error)
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

    // MARK: - Content

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

    // MARK: - Hero

    @ViewBuilder
    private func heroSection(_ details: PlexMediaDetails, topInset: CGFloat, containerWidth: CGFloat) -> some View {
        let heroHeight = 320 + topInset
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
                if let posterURL = viewModel.posterURL(width: 100, height: 150) {
                    AsyncImage(url: posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(2/3, contentMode: .fit)
                        default:
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.duskSurface)
                                .aspectRatio(2/3, contentMode: .fit)
                        }
                    }
                    .frame(width: 100)
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

    // MARK: - Metadata

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

    @ViewBuilder
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

    // MARK: - Cast

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

    // MARK: - Seasons

    @ViewBuilder
    private func seasonsSection(width: CGFloat) -> some View {
        if !viewModel.seasons.isEmpty {
            let layout = gridLayout(for: width)
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

    private func gridLayout(for containerWidth: CGFloat) -> (columns: [GridItem], posterWidth: CGFloat) {
        let availableWidth = max(containerWidth - (horizontalPadding * 2), preferredPosterWidth)
        let rawColumnCount = Int((availableWidth + gridSpacing) / (preferredPosterWidth + gridSpacing))
        let columnCount = max(rawColumnCount, minimumColumnCount)
        let totalSpacing = CGFloat(columnCount - 1) * gridSpacing
        let posterWidth = floor((availableWidth - totalSpacing) / CGFloat(columnCount))
        let columns = Array(
            repeating: GridItem(.fixed(posterWidth), spacing: gridSpacing, alignment: .top),
            count: columnCount
        )

        return (columns, posterWidth)
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

    // MARK: - Error

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.duskTextSecondary)
            Text(message)
                .foregroundStyle(Color.duskTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .foregroundStyle(Color.duskAccent)
            .duskSuppressTVOSButtonChrome()
        }
    }
}

struct SeasonDetailView: View {
    @Environment(PlexService.self) private var plexService
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var viewModel: SeasonDetailViewModel

    private let horizontalPadding: CGFloat = 20

    init(ratingKey: String, plexService: PlexService) {
        _viewModel = State(initialValue: SeasonDetailViewModel(
            ratingKey: ratingKey,
            plexService: plexService
        ))
    }

    var body: some View {
        ZStack {
            Color.duskBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.details == nil {
                ProgressView()
                    .tint(Color.duskAccent)
            } else if let error = viewModel.error, viewModel.details == nil {
                errorView(error)
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
                    if let summary = details.summary, !summary.isEmpty {
                        ExpandableSummaryText(text: summary)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 20)
                    }
                    episodesSection(width: geometry.size.width)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
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
        let heroHeight = 340 + topInset
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
                seasonArtwork

                VStack(alignment: .leading, spacing: 10) {
                    if let showTitle = viewModel.showTitle {
                        if let showRatingKey = viewModel.showRatingKey {
                            NavigationLink(value: AppNavigationRoute.media(type: .show, ratingKey: showRatingKey)) {
                                Text(showTitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.duskAccent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .duskSuppressTVOSButtonChrome()
                        } else {
                            Text(showTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.duskAccent)
                        }
                    }

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
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 16)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func metadataTagline(_ details: PlexMediaDetails) -> some View {
        let parts = [
            viewModel.episodeCountText,
            viewModel.watchedEpisodeCountText,
            details.contentRating,
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Color.duskTextSecondary)
        }
    }

    @ViewBuilder
    private func episodesSection(width: CGFloat) -> some View {
        if !viewModel.episodes.isEmpty {
            let contentWidth = max(width - (horizontalPadding * 2), 280)
            let artworkWidth = min(max(contentWidth * 0.48, 170), 320)
            let imageWidth = Int(artworkWidth.rounded(.up))
            let imageHeight = Int((artworkWidth / (16.0 / 9.0)).rounded(.up))

            VStack(alignment: .leading, spacing: 16) {
                Text("Episodes")
                    .font(.headline)
                    .foregroundStyle(Color.duskTextPrimary)

                LazyVStack(spacing: 20) {
                    ForEach(viewModel.episodes) { episode in
                        NavigationLink(value: AppNavigationRoute.media(type: .episode, ratingKey: episode.ratingKey)) {
                            SeasonEpisodeRow(
                                episode: episode,
                                imageURL: viewModel.episodeImageURL(episode, width: imageWidth, height: imageHeight),
                                label: viewModel.episodeLabel(episode),
                                subtitle: viewModel.episodeSubtitle(episode),
                                progress: viewModel.progress(for: episode),
                                artworkWidth: artworkWidth
                            )
                        }
                        .buttonStyle(.plain)
                        .duskSuppressTVOSButtonChrome()
                        .duskTVOSFocusEffectShape(Rectangle())
                        .contextMenu {
                            if episode.isPartiallyWatched {
                                Button {
                                    Task { await playback.playFromStart(ratingKey: episode.ratingKey) }
                                } label: {
                                    Label("Play from Start", systemImage: "arrow.counterclockwise")
                                }
                            }

                            Button {
                                Task { await viewModel.toggleWatched(for: episode) }
                            } label: {
                                Label(
                                    episode.isWatched ? "Mark Unwatched" : "Mark Watched",
                                    systemImage: episode.isWatched ? "eye.slash" : "eye"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.duskTextSecondary)
            Text(message)
                .foregroundStyle(Color.duskTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .foregroundStyle(Color.duskAccent)
            .duskSuppressTVOSButtonChrome()
        }
    }

    @ViewBuilder
    private var seasonArtwork: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        if let posterURL = viewModel.posterURL(width: 112, height: 168) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                default:
                    shape.fill(Color.duskBackground)
                }
            }
            .frame(width: 112)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(shape)
        } else {
            shape
                .fill(Color.duskBackground)
                .frame(width: 112)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
        }
    }
}

private struct SeasonEpisodeRow: View {
    let episode: PlexEpisode
    let imageURL: URL?
    let label: String?
    let subtitle: String?
    let progress: Double?
    let artworkWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                artwork

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let label, !label.isEmpty {
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.duskTextSecondary)
                        }

                        if episode.isWatched {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.duskAccent)
                        }
                    }

                    Text(episode.title)
                        .font(.headline)
                        .foregroundStyle(Color.duskTextPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.duskTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if let summary = episode.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.duskTextSecondary)
                    .lineSpacing(4)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    default:
                        Color.duskBackground
                            .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    }
                }
            } else {
                Color.duskBackground
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
            }

            Image(systemName: "play.fill")
                .font(.system(size: artworkWidth * 0.16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(artworkWidth * 0.09)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            if let progress {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 3)

                            Rectangle()
                                .fill(Color.duskAccent)
                                .frame(width: geometry.size.width * progress, height: 3)
                        }
                    }
                }
            }
        }
        .frame(width: artworkWidth)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ExpandableSummaryText: View {
    let text: String

    private let collapsedLineLimit = 9

    @State private var isExpanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var expandedHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.body)
                .foregroundStyle(Color.duskTextSecondary)
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .truncationMode(.tail)
                .overlay(alignment: .topLeading) {
                    ZStack {
                        measurementText(lineLimit: collapsedLineLimit) { height in
                            collapsedHeight = height
                        }

                        measurementText(lineLimit: nil) { height in
                            expandedHeight = height
                        }
                    }
                    .hidden()
                    .allowsHitTesting(false)
                }

            if isExpandable {
                Button(isExpanded ? "Show Less" : "Show More") {
                    isExpanded.toggle()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.duskAccent)
                .buttonStyle(.plain)
                .duskSuppressTVOSButtonChrome()
            }
        }
    }

    private var isExpandable: Bool {
        expandedHeight > collapsedHeight + 1
    }

    private func measurementText(
        lineLimit: Int?,
        onHeightChange: @escaping (CGFloat) -> Void
    ) -> some View {
        Text(text)
            .font(.body)
            .lineSpacing(4)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            onHeightChange(proxy.size.height)
                        }
                        .onChange(of: proxy.size.height) { _, newHeight in
                            onHeightChange(newHeight)
                        }
                }
            }
    }
}

struct EpisodeDetailView: View {
    @Environment(PlexService.self) private var plexService
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var viewModel: EpisodeDetailViewModel

    init(ratingKey: String, plexService: PlexService) {
        _viewModel = State(initialValue: EpisodeDetailViewModel(
            ratingKey: ratingKey,
            plexService: plexService
        ))
    }

    var body: some View {
        ZStack {
            Color.duskBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.details == nil {
                ProgressView()
                    .tint(Color.duskAccent)
            } else if let error = viewModel.error, viewModel.details == nil {
                errorView(error)
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
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    actionButtons(details)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    if let summary = details.summary, !summary.isEmpty {
                        ExpandableSummaryText(text: summary)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                    }
                    if let roles = details.roles, !roles.isEmpty {
                        castSection(roles)
                            .padding(.top, 24)
                    }
                }
                .padding(.top, -geometry.safeAreaInsets.top)
                .frame(width: geometry.size.width, alignment: .topLeading)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func heroSection(_ details: PlexMediaDetails, topInset: CGFloat, containerWidth: CGFloat) -> some View {
        let heroHeight = 320 + topInset
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
                if let posterURL = viewModel.posterURL(width: 100, height: 150) {
                    AsyncImage(url: posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        default:
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.duskSurface)
                                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        }
                    }
                    .frame(width: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if let showTitle = viewModel.showTitle {
                        showTitleLink(showTitle)
                    }

                    Text(details.title)
                        .font(.title2.bold())
                        .foregroundStyle(Color.duskTextPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    episodeMarkerRow()
                    metadataTagline(details)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private func episodeMarkerRow() -> some View {
        let seasonLabel = viewModel.seasonLabel
        let episodeLabel = viewModel.episodeLabel

        if seasonLabel != nil || episodeLabel != nil {
            HStack(spacing: 8) {
                if let seasonLabel {
                    seasonChipLink(seasonLabel)
                }

                if let episodeLabel {
                    markerChip(episodeLabel)
                }
            }
        }
    }

    @ViewBuilder
    private func showTitleLink(_ title: String) -> some View {
        if let showRatingKey = viewModel.showRatingKey {
            NavigationLink(value: AppNavigationRoute.media(type: .show, ratingKey: showRatingKey)) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.duskAccent)
            }
            .buttonStyle(.plain)
            .duskSuppressTVOSButtonChrome()
        } else {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.duskAccent)
        }
    }

    @ViewBuilder
    private func seasonChipLink(_ title: String) -> some View {
        if let seasonRatingKey = viewModel.seasonRatingKey {
            NavigationLink(value: AppNavigationRoute.media(type: .season, ratingKey: seasonRatingKey)) {
                markerChip(title)
            }
            .buttonStyle(.plain)
            .duskSuppressTVOSButtonChrome()
        } else {
            markerChip(title)
        }
    }

    private func markerChip(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.duskTextPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.duskSurface.opacity(0.9))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func metadataTagline(_ details: PlexMediaDetails) -> some View {
        let parts = [
            details.contentRating,
            viewModel.formattedDuration,
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
            if let originalDate = details.originallyAvailableAt {
                Text(originalDate)
                    .font(.subheadline)
                    .foregroundStyle(Color.duskTextSecondary)
            }

            if let rating = details.rating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.duskTextPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(_ details: PlexMediaDetails) -> some View {
        VStack(spacing: 12) {
            Button {
                Task { await playback.play(ratingKey: details.ratingKey) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Play Episode")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.duskAccent)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .duskSuppressTVOSButtonChrome()

            Button {
                Task { await viewModel.toggleWatched() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isWatched ? "eye.slash" : "eye")
                    Text(viewModel.isWatched ? "Mark Unwatched" : "Mark Watched")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.duskSurface)
                .foregroundStyle(Color.duskTextPrimary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
            }
            .duskSuppressTVOSButtonChrome()
        }
    }

    @ViewBuilder
    private func castSection(_ roles: [PlexRole]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast")
                .font(.headline)
                .foregroundStyle(Color.duskTextPrimary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(roles.prefix(20).enumerated()), id: \.offset) { _, role in
                        ActorCreditCard(person: PlexPersonReference(role: role), plexService: plexService)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.duskTextSecondary)
            Text(message)
                .foregroundStyle(Color.duskTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .foregroundStyle(Color.duskAccent)
            .duskSuppressTVOSButtonChrome()
        }
    }
}

struct MediaDetailDestinationView: View {
    let type: PlexMediaType
    let ratingKey: String
    let plexService: PlexService

    @ViewBuilder
    var body: some View {
        switch type {
        case .movie:
            MovieDetailView(ratingKey: ratingKey, plexService: plexService)
        case .show:
            ShowDetailView(ratingKey: ratingKey, plexService: plexService)
        case .person:
            ActorDetailView(
                person: PlexPersonReference(personID: ratingKey, name: "Actor", thumb: nil),
                plexService: plexService
            )
        case .season:
            SeasonDetailView(ratingKey: ratingKey, plexService: plexService)
        case .episode:
            EpisodeDetailView(ratingKey: ratingKey, plexService: plexService)
        default:
            MovieDetailView(ratingKey: ratingKey, plexService: plexService)
        }
    }
}

struct ActorCreditCard: View {
    let person: PlexPersonReference
    let plexService: PlexService

    var body: some View {
        NavigationLink(value: AppNavigationRoute.person(person)) {
            VStack(spacing: 8) {
                if let thumbPath = person.thumb {
                    AsyncImage(url: plexService.imageURL(for: thumbPath, width: 72, height: 72)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            placeholder
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                } else {
                    placeholder
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                }

                VStack(spacing: 2) {
                    Text(person.name)
                        .font(.caption)
                        .foregroundStyle(Color.duskTextPrimary)
                        .lineLimit(1)

                    if let roleName = person.roleName, !roleName.isEmpty {
                        Text(roleName)
                            .font(.caption2)
                            .foregroundStyle(Color.duskTextSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
        .duskSuppressTVOSButtonChrome()
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.title2)
            .foregroundStyle(Color.duskTextSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.duskSurface)
    }
}

struct ActorDetailView: View {
    @Environment(PlexService.self) private var plexService
    @State private var viewModel: ActorDetailViewModel

    private let horizontalPadding: CGFloat = 20
    private let gridSpacing: CGFloat = 14
    private let preferredPosterWidth: CGFloat = 120
    private let minimumColumnCount = 2

    init(person: PlexPersonReference, plexService: PlexService) {
        _viewModel = State(initialValue: ActorDetailViewModel(
            person: person,
            plexService: plexService
        ))
    }

    var body: some View {
        ZStack {
            Color.duskBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.filmography.isEmpty {
                ProgressView()
                    .tint(Color.duskAccent)
            } else if let error = viewModel.error, viewModel.filmography.isEmpty {
                errorView(error)
            } else {
                contentView
            }
        }
        .duskNavigationBarTitleDisplayModeInline()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
    }

    private var contentView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerCard
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 20)

                    if !viewModel.movies.isEmpty {
                        filmographySection(
                            title: "Movies",
                            items: viewModel.movies,
                            width: geometry.size.width
                        )
                    }

                    if !viewModel.shows.isEmpty {
                        filmographySection(
                            title: "Shows",
                            items: viewModel.shows,
                            width: geometry.size.width
                        )
                    }

                    if viewModel.movies.isEmpty && viewModel.shows.isEmpty && !viewModel.isLoading {
                        emptyState
                            .padding(.horizontal, horizontalPadding)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 20) {
            personArtwork

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.person.name)
                    .font(.title2.bold())
                    .foregroundStyle(Color.duskTextPrimary)
                    .multilineTextAlignment(.leading)

                if let roleName = viewModel.person.roleName, !roleName.isEmpty {
                    Text(roleName)
                        .font(.subheadline)
                        .foregroundStyle(Color.duskTextSecondary)
                }

                Text(viewModel.creditSummary)
                    .font(.subheadline)
                    .foregroundStyle(Color.duskTextSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.duskSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var personArtwork: some View {
        if let imageURL = viewModel.personImageURL(size: 120) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    personPlaceholder
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
        } else {
            personPlaceholder
                .frame(width: 120, height: 120)
                .clipShape(Circle())
        }
    }

    private var personPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.duskBackground)

            Image(systemName: "person.fill")
                .font(.title)
                .foregroundStyle(Color.duskTextSecondary)
        }
    }

    @ViewBuilder
    private func filmographySection(title: String, items: [PlexItem], width: CGFloat) -> some View {
        let layout = gridLayout(for: width)
        let imageWidth = Int(layout.posterWidth.rounded(.up))
        let imageHeight = Int((layout.posterWidth * 1.5).rounded(.up))

        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.duskTextPrimary)
                .padding(.horizontal, horizontalPadding)

            LazyVGrid(columns: layout.columns, alignment: .leading, spacing: 18) {
                ForEach(items) { item in
                    NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                        PosterCard(
                            imageURL: viewModel.posterURL(for: item, width: imageWidth, height: imageHeight),
                            title: item.title,
                            subtitle: viewModel.subtitle(for: item),
                            width: layout.posterWidth
                        )
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No titles found")
                .font(.headline)
                .foregroundStyle(Color.duskTextPrimary)

            Text("This actor doesn't have any movies or shows available in your connected Plex library.")
                .font(.subheadline)
                .foregroundStyle(Color.duskTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color.duskSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.duskTextSecondary)

            Text(message)
                .foregroundStyle(Color.duskTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Retry") {
                Task { await viewModel.load() }
            }
            .foregroundStyle(Color.duskAccent)
            .duskSuppressTVOSButtonChrome()
        }
    }

    private func gridLayout(for containerWidth: CGFloat) -> (columns: [GridItem], posterWidth: CGFloat) {
        let availableWidth = max(containerWidth - (horizontalPadding * 2), preferredPosterWidth)
        let rawColumnCount = Int((availableWidth + gridSpacing) / (preferredPosterWidth + gridSpacing))
        let columnCount = max(rawColumnCount, minimumColumnCount)
        let totalSpacing = CGFloat(columnCount - 1) * gridSpacing
        let posterWidth = floor((availableWidth - totalSpacing) / CGFloat(columnCount))
        let columns = Array(
            repeating: GridItem(.fixed(posterWidth), spacing: gridSpacing, alignment: .top),
            count: columnCount
        )

        return (columns, posterWidth)
    }
}
