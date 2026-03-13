import Foundation

enum MediaTextFormatter {
    static func seasonEpisodeLabel(
        season: Int?,
        episode: Int?,
        separator: String = " · "
    ) -> String? {
        switch (season, episode) {
        case let (season?, episode?):
            return "Season \(season)\(separator)Episode \(episode)"
        case let (season?, nil):
            return "Season \(season)"
        case let (nil, episode?):
            return "Episode \(episode)"
        default:
            return nil
        }
    }

    static func seasonCount(_ count: Int?) -> String? {
        pluralizedCount(count, singular: "Season", plural: "Seasons")
    }

    static func episodeCount(_ count: Int?) -> String? {
        pluralizedCount(count, singular: "Episode", plural: "Episodes")
    }

    static func watchedCount(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return "\(count) watched"
    }

    static func shortDuration(milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let totalMinutes = milliseconds / 60_000
        return "\(totalMinutes) min"
    }

    static func playbackDuration(milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let totalMinutes = milliseconds / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    static func progress(durationMs: Int?, offsetMs: Int?) -> Double? {
        guard let durationMs,
              let offsetMs,
              durationMs > 0,
              offsetMs > 0 else {
            return nil
        }

        return Double(offsetMs) / Double(durationMs)
    }

    static func mediaTypeIconName(_ type: PlexMediaType) -> String {
        switch type {
        case .movie:
            return "film"
        case .show:
            return "tv"
        case .person:
            return "person.fill"
        case .episode:
            return "play.rectangle"
        case .season:
            return "rectangle.stack"
        default:
            return "square.grid.2x2"
        }
    }

    private static func pluralizedCount(
        _ count: Int?,
        singular: String,
        plural: String
    ) -> String? {
        guard let count, count > 0 else { return nil }
        let label = count == 1 ? singular : plural
        return "\(count) \(label)"
    }
}
