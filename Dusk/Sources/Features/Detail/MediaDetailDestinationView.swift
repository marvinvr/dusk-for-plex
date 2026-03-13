import SwiftUI

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
