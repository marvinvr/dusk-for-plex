import SwiftUI

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
}
