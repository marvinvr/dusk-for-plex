import Foundation

/// A "hub" on the Plex home screen (e.g. "Continue Watching", "Recently Added Movies").
/// Returned from `GET /hubs`, `GET /hubs/sections/{sectionId}`, and `GET /hubs/search`.
struct PlexHub: Decodable, Sendable, Identifiable, Hashable {
    var id: String { hubIdentifier ?? title }

    let key: String?
    let title: String
    let type: String?
    let hubIdentifier: String?
    let size: Int?
    let more: Bool?
    let items: [PlexItem]

    enum CodingKeys: String, CodingKey {
        case key, title, type, hubIdentifier, size, more
        case metadata = "Metadata"
        case directories = "Directory"
    }

    init(
        key: String?,
        title: String,
        type: String?,
        hubIdentifier: String?,
        size: Int?,
        more: Bool?,
        items: [PlexItem]
    ) {
        self.key = key
        self.title = title
        self.type = type
        self.hubIdentifier = hubIdentifier
        self.size = size
        self.more = more
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        hubIdentifier = try container.decodeIfPresent(String.self, forKey: .hubIdentifier)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        more = try container.decodeIfPresent(Bool.self, forKey: .more) ??
            (try container.decodeIfPresent(Int.self, forKey: .more).map { $0 != 0 })

        let metadataItems = try container.decodeIfPresent([PlexItem].self, forKey: .metadata) ?? []
        let directoryItems = try container.decodeIfPresent([PlexItem].self, forKey: .directories) ?? []
        items = metadataItems + directoryItems
    }
}
