import Foundation
import SwiftUI

/// Manages player UI state: syncs from the engine via timer, handles overlay
/// visibility, scrubbing, and forwards control actions to the engine.
@MainActor @Observable
final class PlayerViewModel {
    var state: PlaybackState = .idle
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isBuffering = false
    var hasStartedPlayback = false
    var playbackError: PlaybackError?
    var subtitleTracks: [SubtitleTrack] = []
    var audioTracks: [AudioTrack] = []
    var selectedSubtitleTrackID: Int?
    var selectedAudioTrackID: Int?
    var showControls = true
    var showSubtitlePicker = false
    var showAudioPicker = false
    var isScrubbing = false
    var scrubPosition: TimeInterval = 0

    let engine: any PlaybackEngine
    let markers: [PlexMarker]
    var hasLoadedSource = false
    var sourcePart: PlexMediaPart?
    var preferredSubtitleLanguage: String?
    var preferredAudioLanguage: String?
    var subtitleForcedOnly = false
    var hasConfiguredAutomaticTrackSelection = false
    var hasAppliedAutomaticAudioSelection = false
    var hasAppliedAutomaticSubtitleSelection = false
    @ObservationIgnored nonisolated(unsafe) var syncTimer: Timer?
    @ObservationIgnored nonisolated(unsafe) var hideTimer: Timer?

    init(engine: any PlaybackEngine, markers: [PlexMarker] = []) {
        self.engine = engine
        self.markers = markers.sorted { $0.startTimeOffset < $1.startTimeOffset }
        startSync()
        scheduleHide()
    }

    deinit {
        syncTimer?.invalidate()
        hideTimer?.invalidate()
    }

    func cleanup() {
        syncTimer?.invalidate()
        hideTimer?.invalidate()
        syncTimer = nil
        hideTimer = nil
        // Pause (not stop) so the coordinator can read final position
        // for timeline reporting before tearing down the engine.
        engine.pause()
    }

    func configureAutomaticTrackSelection(
        preferences: UserPreferences,
        part: PlexMediaPart?
    ) {
        sourcePart = part
        preferredSubtitleLanguage = Self.normalizedLanguageCode(preferences.defaultSubtitleLanguage)
        preferredAudioLanguage = Self.normalizedLanguageCode(preferences.defaultAudioLanguage)
        subtitleForcedOnly = preferences.subtitleForcedOnly
        hasConfiguredAutomaticTrackSelection = true
        hasAppliedAutomaticAudioSelection = false
        hasAppliedAutomaticSubtitleSelection = false
        syncTrackLists()
        applyAutomaticTrackSelectionIfNeeded()
    }

    func startPlaybackIfNeeded(source: PlaybackSource) {
        guard !hasLoadedSource else { return }
        hasLoadedSource = true
        engine.load(url: source.url, startPosition: source.startPosition)
    }
}
