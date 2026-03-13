import Foundation
import SwiftUI

/// Manages player UI state: syncs from the engine via timer, handles overlay
/// visibility, scrubbing, and forwards control actions to the engine.
@MainActor @Observable
final class PlayerViewModel {

    // MARK: - Engine State (synced periodically)

    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isBuffering = false
    private(set) var hasStartedPlayback = false
    private(set) var playbackError: PlaybackError?
    private(set) var subtitleTracks: [SubtitleTrack] = []
    private(set) var audioTracks: [AudioTrack] = []

    // MARK: - UI State

    var showControls = true
    var showSubtitlePicker = false
    var showAudioPicker = false
    var isScrubbing = false
    var scrubPosition: TimeInterval = 0

    // MARK: - Private

    private let engine: any PlaybackEngine
    private let markers: [PlexMarker]
    private var hasLoadedSource = false
    private var sourcePart: PlexMediaPart?
    private var preferredSubtitleLanguage: String?
    private var preferredAudioLanguage: String?
    private var subtitleForcedOnly = false
    private var hasConfiguredAutomaticTrackSelection = false
    private var hasAppliedAutomaticAudioSelection = false
    private var hasAppliedAutomaticSubtitleSelection = false
    @ObservationIgnored nonisolated(unsafe) private var syncTimer: Timer?
    @ObservationIgnored nonisolated(unsafe) private var hideTimer: Timer?

    // MARK: - Init / Cleanup

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

    // MARK: - Sync

    private func startSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sync()
            }
        }
    }

    private func sync() {
        state = engine.state
        if !isScrubbing {
            currentTime = engine.currentTime
        }
        duration = engine.duration
        isBuffering = engine.isBuffering
        if !hasStartedPlayback, (state == .playing || currentTime > 0) {
            hasStartedPlayback = true
        }
        playbackError = engine.error
        syncTrackLists()
        applyAutomaticTrackSelectionIfNeeded()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if state == .playing {
            engine.pause()
        } else {
            engine.play()
        }
        touchControls()
    }

    func seek(by offset: TimeInterval, revealControls: Bool = false) {
        seek(to: displayPosition + offset, revealControls: revealControls)
    }

    func skipActiveMarker() {
        guard let marker = activeSkipMarker else { return }

        let targetTime = TimeInterval(marker.endTimeOffset) / 1000.0
        seek(to: targetTime, revealControls: true)
    }

    // MARK: - Scrubbing

    func beginScrub() {
        isScrubbing = true
        scrubPosition = currentTime
        hideTimer?.invalidate()
    }

    func updateScrub(to position: TimeInterval) {
        scrubPosition = max(0, min(position, duration))
    }

    func endScrub() {
        engine.seek(to: scrubPosition)
        isScrubbing = false
        touchControls()
    }

    // MARK: - Track Selection

    func selectSubtitle(_ track: SubtitleTrack?) {
        hasAppliedAutomaticSubtitleSelection = true
        engine.selectSubtitleTrack(track)
        showSubtitlePicker = false
    }

    func selectAudio(_ track: AudioTrack) {
        hasAppliedAutomaticAudioSelection = true
        engine.selectAudioTrack(track)
        showAudioPicker = false
    }

    // MARK: - Overlay Visibility

    func toggleControls() {
        showControls.toggle()
        if showControls {
            scheduleHide()
        } else {
            hideTimer?.invalidate()
        }
    }

    func touchControls() {
        showControls = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state == .playing, !self.isScrubbing {
                    self.showControls = false
                }
            }
        }
    }

    private func seek(to position: TimeInterval, revealControls: Bool) {
        let clampedPosition: TimeInterval
        if duration > 0 {
            clampedPosition = min(max(position, 0), duration)
        } else {
            clampedPosition = max(position, 0)
        }

        engine.seek(to: clampedPosition)

        if revealControls {
            touchControls()
        } else if showControls {
            scheduleHide()
        }
    }

    // MARK: - Automatic Track Selection

    private func syncTrackLists() {
        audioTracks = mergeAudioMetadata(into: engine.availableAudioTracks)
        subtitleTracks = mergeSubtitleMetadata(into: engine.availableSubtitleTracks)
    }

    private func applyAutomaticTrackSelectionIfNeeded() {
        guard hasConfiguredAutomaticTrackSelection else { return }

        if !hasAppliedAutomaticAudioSelection, !audioTracks.isEmpty {
            if let preferredAudioTrack = preferredAudioTrack() {
                engine.selectAudioTrack(preferredAudioTrack)
            }
            hasAppliedAutomaticAudioSelection = true
        }

        if !hasAppliedAutomaticSubtitleSelection, !subtitleTracks.isEmpty {
            engine.selectSubtitleTrack(preferredSubtitleTrack())
            hasAppliedAutomaticSubtitleSelection = true
        }
    }

    private func preferredAudioTrack() -> AudioTrack? {
        guard let preferredAudioLanguage else { return nil }

        return audioTracks.first {
            Self.normalizedLanguageCode($0.languageCode) == preferredAudioLanguage
        }
    }

    private func preferredSubtitleTrack() -> SubtitleTrack? {
        if subtitleForcedOnly {
            let forcedTracks = subtitleTracks.filter { $0.isForced || Self.containsForcedMarker($0.displayTitle) }
            guard !forcedTracks.isEmpty else { return nil }

            if let preferredSubtitleLanguage {
                return rankedSubtitleTrack(
                    from: forcedTracks,
                    preferredLanguage: preferredSubtitleLanguage,
                    preferForcedTracks: true
                )
            }

            return forcedTracks.sorted(by: Self.subtitleOrdering(preferForcedTracks: true)).first
        }

        guard let preferredSubtitleLanguage else { return nil }
        return rankedSubtitleTrack(
            from: subtitleTracks,
            preferredLanguage: preferredSubtitleLanguage,
            preferForcedTracks: false
        )
    }

    private func rankedSubtitleTrack(
        from tracks: [SubtitleTrack],
        preferredLanguage: String,
        preferForcedTracks: Bool
    ) -> SubtitleTrack? {
        tracks
            .filter { Self.normalizedLanguageCode($0.languageCode) == preferredLanguage }
            .sorted(by: Self.subtitleOrdering(preferForcedTracks: preferForcedTracks))
            .first
    }

    private func mergeAudioMetadata(into engineTracks: [AudioTrack]) -> [AudioTrack] {
        let sourceStreams = sourcePart?.streams.filter { $0.streamType == .audio } ?? []
        guard !sourceStreams.isEmpty else { return engineTracks }

        var remaining = Array(sourceStreams.enumerated())

        return engineTracks.enumerated().map { index, track in
            guard let source = popBestMatch(
                for: track,
                at: index,
                from: &remaining,
                score: scoreAudioMatch(track:stream:)
            ) else {
                return track
            }

            return AudioTrack(
                id: track.id,
                displayTitle: source.extendedDisplayTitle ?? source.displayTitle ?? track.displayTitle,
                language: source.language ?? track.language,
                languageCode: Self.normalizedLanguageCode(source.languageCode ?? source.languageTag) ?? track.languageCode,
                codec: source.codec ?? track.codec,
                channels: source.channels ?? track.channels,
                channelLayout: source.channelLayout ?? track.channelLayout
            )
        }
    }

    private func mergeSubtitleMetadata(into engineTracks: [SubtitleTrack]) -> [SubtitleTrack] {
        let sourceStreams = sourcePart?.streams.filter { $0.streamType == .subtitle } ?? []
        guard !sourceStreams.isEmpty else { return engineTracks }

        var remaining = Array(sourceStreams.enumerated())

        return engineTracks.enumerated().map { index, track in
            guard let source = popBestMatch(
                for: track,
                at: index,
                from: &remaining,
                score: scoreSubtitleMatch(track:stream:)
            ) else {
                return track
            }

            return SubtitleTrack(
                id: track.id,
                displayTitle: source.extendedDisplayTitle ?? source.displayTitle ?? track.displayTitle,
                language: source.language ?? track.language,
                languageCode: Self.normalizedLanguageCode(source.languageCode ?? source.languageTag) ?? track.languageCode,
                codec: source.codec ?? track.codec,
                isForced: source.isForced ?? track.isForced,
                isHearingImpaired: source.isHearingImpaired ?? track.isHearingImpaired,
                isExternal: source.key != nil || track.isExternal,
                externalURL: track.externalURL
            )
        }
    }

    private func popBestMatch<Track>(
        for track: Track,
        at index: Int,
        from candidates: inout [(offset: Int, element: PlexStream)],
        score: (Track, PlexStream) -> Int
    ) -> PlexStream? {
        guard !candidates.isEmpty else { return nil }

        let rankedCandidates = candidates.enumerated().map { candidateIndex, candidate in
            let positionalBonus = candidate.offset == index ? 2 : 0
            return (
                candidateIndex: candidateIndex,
                totalScore: score(track, candidate.element) + positionalBonus
            )
        }

        let best = rankedCandidates.max { lhs, rhs in
            lhs.totalScore < rhs.totalScore
        }

        let selectedIndex: Int
        if let best, best.totalScore > 0 {
            selectedIndex = best.candidateIndex
        } else if let positionalMatch = candidates.firstIndex(where: { $0.offset == index }) {
            selectedIndex = positionalMatch
        } else {
            selectedIndex = 0
        }

        return candidates.remove(at: selectedIndex).element
    }

    private func scoreAudioMatch(track: AudioTrack, stream: PlexStream) -> Int {
        var score = 0

        if let trackLanguage = Self.normalizedLanguageCode(track.languageCode),
           trackLanguage == Self.normalizedLanguageCode(stream.languageCode ?? stream.languageTag) {
            score += 4
        }

        if let trackTitle = Self.normalizedTitle(track.displayTitle),
           trackTitle == Self.normalizedTitle(stream.extendedDisplayTitle ?? stream.displayTitle) {
            score += 3
        }

        if let trackLanguage = Self.normalizedTitle(track.language),
           trackLanguage == Self.normalizedTitle(stream.language) {
            score += 1
        }

        return score
    }

    private func scoreSubtitleMatch(track: SubtitleTrack, stream: PlexStream) -> Int {
        var score = 0

        if let trackLanguage = Self.normalizedLanguageCode(track.languageCode),
           trackLanguage == Self.normalizedLanguageCode(stream.languageCode ?? stream.languageTag) {
            score += 4
        }

        if let trackTitle = Self.normalizedTitle(track.displayTitle),
           trackTitle == Self.normalizedTitle(stream.extendedDisplayTitle ?? stream.displayTitle) {
            score += 3
        }

        let trackIsForced = track.isForced || Self.containsForcedMarker(track.displayTitle)
        let streamIsForced = stream.isForced ?? false
        if trackIsForced == streamIsForced {
            score += 2
        }

        let trackIsHI = track.isHearingImpaired || Self.containsHearingImpairedMarker(track.displayTitle)
        let streamIsHI = stream.isHearingImpaired ?? false
        if trackIsHI == streamIsHI {
            score += 1
        }

        return score
    }

    private static func subtitleOrdering(preferForcedTracks: Bool) -> (SubtitleTrack, SubtitleTrack) -> Bool {
        { lhs, rhs in
            let lhsForced = lhs.isForced || containsForcedMarker(lhs.displayTitle)
            let rhsForced = rhs.isForced || containsForcedMarker(rhs.displayTitle)
            let lhsHI = lhs.isHearingImpaired || containsHearingImpairedMarker(lhs.displayTitle)
            let rhsHI = rhs.isHearingImpaired || containsHearingImpairedMarker(rhs.displayTitle)

            let lhsScore = subtitleSortScore(
                isForced: lhsForced,
                isHearingImpaired: lhsHI,
                preferForcedTracks: preferForcedTracks
            )
            let rhsScore = subtitleSortScore(
                isForced: rhsForced,
                isHearingImpaired: rhsHI,
                preferForcedTracks: preferForcedTracks
            )

            if lhsScore == rhsScore {
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }

            return lhsScore > rhsScore
        }
    }

    private static func subtitleSortScore(
        isForced: Bool,
        isHearingImpaired: Bool,
        preferForcedTracks: Bool
    ) -> Int {
        var score = 0
        score += preferForcedTracks ? (isForced ? 4 : 0) : (isForced ? 0 : 4)
        score += isHearingImpaired ? 0 : 2
        return score
    }

    private static func normalizedLanguageCode(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
            .split(separator: "-")
            .first?
            .lowercased()
    }

    private static func normalizedTitle(_ value: String?) -> String? {
        guard let value = value?.lowercased(),
              !value.isEmpty else {
            return nil
        }

        let normalized = value
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        return normalized.isEmpty ? nil : normalized
    }

    private static func containsForcedMarker(_ value: String) -> Bool {
        let normalized = normalizedTitle(value) ?? ""
        return normalized.contains("forced")
    }

    private static func containsHearingImpairedMarker(_ value: String) -> Bool {
        let normalized = normalizedTitle(value) ?? ""
        return normalized.contains("sdh")
            || normalized.contains("cc")
            || normalized.contains("hearing impaired")
    }

    // MARK: - Computed Helpers

    var engineView: AnyView {
        engine.makePlayerView()
    }

    var displayPosition: TimeInterval {
        isScrubbing ? scrubPosition : currentTime
    }

    var activeSkipMarker: PlexMarker? {
        let positionMs = Int(displayPosition * 1000)
        return markers.first {
            $0.skipButtonTitle != nil && $0.contains(positionMs: positionMs)
        }
    }

    var shouldShowBufferingIndicator: Bool {
        isBuffering && !hasStartedPlayback && playbackError == nil
    }

    var formattedTime: String {
        formatTime(displayPosition)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
