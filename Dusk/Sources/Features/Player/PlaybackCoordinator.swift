import Foundation
import SwiftUI

/// Orchestrates the "play an item" flow: fetch metadata → resolve engine →
/// construct URL → present player → report timeline → scrobble.
///
/// Injected into the environment so any view can trigger playback via
/// `coordinator.play(ratingKey:)`. The player is presented as a full-screen
/// cover in MainTabView.
@MainActor @Observable
final class PlaybackCoordinator {

    // MARK: - Public State

    /// When true, the full-screen player cover is presented.
    var showPlayer = false

    /// True while fetching metadata / creating the engine.
    private(set) var isLoading = false

    /// Non-nil if metadata fetch or engine creation failed.
    private(set) var loadError: String?

    /// The active engine (set after successful load, nil otherwise).
    private(set) var engine: (any PlaybackEngine)?

    /// Snapshot of the currently playing media for the debug overlay.
    private(set) var debugInfo: PlaybackDebugInfo?

    /// The media source to load once the player view is attached.
    private(set) var playbackSource: PlaybackSource?

    /// Changes whenever the active playback item changes so PlayerView rebuilds.
    private(set) var playerPresentationID = UUID()

    // MARK: - Private

    private let plexService: PlexService
    private let preferences: UserPreferences
    private var ratingKey: String?
    private var activeItemDetails: PlexMediaDetails?
    private var hasScrobbled = false
    private var didFinalizeCurrentSession = false
    private var isHandlingPlaybackEnded = false

    /// Most recent position captured by the timeline timer (ms).
    private var lastReportedTimeMs = 0
    private var lastReportedDurationMs = 0

    @ObservationIgnored nonisolated(unsafe) private var timelineTimer: Timer?

    // MARK: - Init

    init(plexService: PlexService, preferences: UserPreferences = UserPreferences()) {
        self.plexService = plexService
        self.preferences = preferences
    }

    deinit {
        timelineTimer?.invalidate()
    }

    // MARK: - Play an Item

    /// Full "play an item" flow: fetch details → pick engine → build URL → present.
    func play(ratingKey: String) async {
        isLoading = true
        defer { isLoading = false }

        _ = await startPlaybackSession(ratingKey: ratingKey, presentPlayer: true)
    }

    /// Called when the full-screen player cover is dismissed.
    /// Sends a final "stopped" timeline, scrobbles if needed, and tears down.
    func onPlayerDismissed() {
        finalizeCurrentPlaybackSession(markCompleted: false)
        clearPlayerState()
        showPlayer = false
    }

    /// Dismiss any loading error so the UI can return to normal.
    func clearError() {
        loadError = nil
    }

    // MARK: - Timeline Reporting

    private func startTimelineReporting() {
        timelineTimer?.invalidate()
        timelineTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reportCurrentTimeline()
            }
        }
    }

    private func reportCurrentTimeline() {
        guard let engine, let ratingKey else { return }

        let timeMs = Int(engine.currentTime * 1000)
        let durationMs = Int(engine.duration * 1000)

        // Store for final report on dismiss
        lastReportedTimeMs = timeMs
        lastReportedDurationMs = durationMs

        let plexState: PlaybackState
        switch engine.state {
        case .playing: plexState = .playing
        case .paused: plexState = .paused
        default: return // Don't report idle/loading/stopped/error
        }

        Task {
            await plexService.reportTimeline(
                ratingKey: ratingKey,
                state: plexState,
                timeMs: timeMs,
                durationMs: durationMs
            )
        }

        // Scrobble at >90% watched
        if !hasScrobbled, durationMs > 0, timeMs > Int(Double(durationMs) * 0.9) {
            hasScrobbled = true
            Task {
                try? await plexService.scrobble(ratingKey: ratingKey)
            }
        }
    }

    @discardableResult
    private func startPlaybackSession(ratingKey: String, presentPlayer: Bool) async -> Bool {
        loadError = nil

        do {
            let details = try await plexService.getMediaDetails(ratingKey: ratingKey)

            guard let media = details.media.first,
                  let part = media.parts.first else {
                loadError = "No playable media found."
                return false
            }

            guard let url = plexService.directPlayURL(for: part) else {
                loadError = "Could not construct playback URL."
                return false
            }

            let engineType = StreamResolver.resolve(
                media: media,
                forceAVPlayer: preferences.forceAVPlayer,
                forceVLCKit: preferences.forceVLCKit
            )

            let newEngine = PlaybackEngineFactory.makeEngine(
                for: media,
                forceAVPlayer: preferences.forceAVPlayer,
                forceVLCKit: preferences.forceVLCKit
            )
            newEngine.onPlaybackEnded = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.handlePlaybackEnded()
                }
            }

            hasScrobbled = false
            didFinalizeCurrentSession = false
            lastReportedTimeMs = 0
            lastReportedDurationMs = 0
            self.ratingKey = ratingKey
            activeItemDetails = details
            engine = newEngine
            playbackSource = PlaybackSource(
                url: url,
                startPosition: details.viewOffset.map { TimeInterval($0) / 1000.0 }
            )
            debugInfo = PlaybackDebugInfo(
                title: details.title,
                engine: engineType,
                decision: .directPlay,
                media: media,
                part: part
            )
            playerPresentationID = UUID()
            startTimelineReporting()

            if presentPlayer {
                showPlayer = true
            }

            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    private func handlePlaybackEnded() async {
        guard !isHandlingPlaybackEnded else { return }
        isHandlingPlaybackEnded = true
        defer { isHandlingPlaybackEnded = false }

        if preferences.continuousPlayEnabled,
           let activeItemDetails,
           let nextEpisode = try? await plexService.getNextEpisode(after: activeItemDetails) {
            finalizeCurrentPlaybackSession(markCompleted: true)

            let didStartNextEpisode = await startPlaybackSession(
                ratingKey: nextEpisode.ratingKey,
                presentPlayer: false
            )

            if didStartNextEpisode {
                return
            }
        }

        finalizeCurrentPlaybackSession(markCompleted: true)
        showPlayer = false
    }

    private func finalizeCurrentPlaybackSession(markCompleted: Bool) {
        guard !didFinalizeCurrentSession else { return }
        didFinalizeCurrentSession = true

        timelineTimer?.invalidate()
        timelineTimer = nil

        let snapshot = timelineSnapshot(markCompleted: markCompleted)
        lastReportedTimeMs = snapshot.timeMs
        lastReportedDurationMs = snapshot.durationMs

        if let ratingKey {
            Task {
                await plexService.reportTimeline(
                    ratingKey: ratingKey,
                    state: .stopped,
                    timeMs: snapshot.timeMs,
                    durationMs: snapshot.durationMs
                )
            }

            if !hasScrobbled,
               snapshot.durationMs > 0,
               snapshot.timeMs > Int(Double(snapshot.durationMs) * 0.9) {
                hasScrobbled = true
                Task {
                    try? await plexService.scrobble(ratingKey: ratingKey)
                }
            }
        }

        engine?.onPlaybackEnded = nil
        engine?.stop()
    }

    private func timelineSnapshot(markCompleted: Bool) -> (timeMs: Int, durationMs: Int) {
        let engineTimeMs = engine.map { Int($0.currentTime * 1000) } ?? 0
        let engineDurationMs = engine.map { Int($0.duration * 1000) } ?? 0

        let durationMs = max(lastReportedDurationMs, engineDurationMs)
        var timeMs = max(lastReportedTimeMs, engineTimeMs)

        if markCompleted, durationMs > 0 {
            timeMs = durationMs
        } else if durationMs > 0 {
            timeMs = min(timeMs, durationMs)
        }

        return (timeMs, durationMs)
    }

    private func clearPlayerState() {
        timelineTimer?.invalidate()
        timelineTimer = nil
        engine?.onPlaybackEnded = nil
        engine = nil
        activeItemDetails = nil
        debugInfo = nil
        playbackSource = nil
        ratingKey = nil
        hasScrobbled = false
        didFinalizeCurrentSession = false
        isHandlingPlaybackEnded = false
        lastReportedTimeMs = 0
        lastReportedDurationMs = 0
    }
}

struct PlaybackSource: Sendable {
    let url: URL
    let startPosition: TimeInterval?
}

struct PlaybackDebugInfo: Sendable {
    let title: String
    let engine: PlaybackEngineType
    let decision: PlaybackDecision
    let media: PlexMedia
    let part: PlexMediaPart

    var engineLabel: String {
        switch engine {
        case .avPlayer: "AVPlayer"
        case .vlcKit: "VLCKit"
        }
    }

    var transcodeLabel: String {
        "No"
    }

    var directPlayLabel: String {
        "Yes"
    }

    var decisionLabel: String {
        switch decision {
        case .directPlay: "Direct Play"
        }
    }

    var containerLabel: String {
        (part.container ?? media.container ?? "Unknown").uppercased()
    }

    var resolutionLabel: String {
        if let width = media.width, let height = media.height {
            return "\(width)x\(height)"
        }
        if let height = media.height {
            return "\(height)p"
        }
        if let resolution = media.videoResolution {
            return resolution.uppercased()
        }
        return "Unknown"
    }

    var bitrateLabel: String {
        if let bitrate = media.bitrate {
            return Self.formatBitrateKbps(bitrate)
        }
        if let bitrate = selectedVideoStream?.bitrate {
            return Self.formatBitrateKbps(bitrate)
        }
        return "Unknown"
    }

    var videoLabel: String {
        let codec = media.videoCodec?.uppercased() ?? selectedVideoStream?.codec?.uppercased() ?? "Unknown"
        if let profile = media.videoProfile?.uppercased() {
            return "\(codec) (\(profile))"
        }
        return codec
    }

    var audioLabel: String {
        let codec = media.audioCodec?.uppercased() ?? selectedAudioStream?.codec?.uppercased() ?? "Unknown"
        let channels = media.audioChannels ?? selectedAudioStream?.channels
        if let channels {
            return "\(codec) \(channels)ch"
        }
        return codec
    }

    var fileSizeLabel: String {
        guard let size = part.size else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var subtitleLabel: String {
        guard let subtitle = selectedSubtitleStream else { return "None" }
        return subtitle.extendedDisplayTitle ?? subtitle.displayTitle ?? subtitle.codec?.uppercased() ?? "Selected"
    }

    private var selectedVideoStream: PlexStream? {
        part.streams.first { $0.streamType == .video }
    }

    private var selectedAudioStream: PlexStream? {
        part.streams.first { $0.streamType == .audio && ($0.isSelected ?? false) }
            ?? part.streams.first { $0.streamType == .audio }
    }

    private var selectedSubtitleStream: PlexStream? {
        part.streams.first { $0.streamType == .subtitle && ($0.isSelected ?? false) }
    }

    private static func formatBitrateKbps(_ value: Int) -> String {
        if value >= 1_000 {
            return String(format: "%.1f Mbps", Double(value) / 1_000.0)
        }
        return "\(value) kbps"
    }
}

enum PlaybackDecision: Sendable {
    case directPlay
}
