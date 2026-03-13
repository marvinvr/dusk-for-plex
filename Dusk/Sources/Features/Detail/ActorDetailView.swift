import SwiftUI

struct ActorDetailView: View {
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
                FeatureLoadingView()
            } else if let error = viewModel.error, viewModel.filmography.isEmpty {
                FeatureErrorView(message: error) {
                    Task { await viewModel.load() }
                }
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
}
