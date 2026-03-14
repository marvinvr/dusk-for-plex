#if canImport(VLCKit)
import SwiftUI
import UIKit
import VLCKit

/// PlaybackEngine implementation backed by upstream VLCKit 4.x.
///
/// Handles MKV, DTS, PGS subtitles, and any other format that AVPlayer
/// cannot natively decode. On iOS, Dusk uses VLCKit's PiP drawable APIs and
/// automatically requests PiP when the app backgrounds during active playback.
@MainActor
@Observable
final class VLCKitEngine: NSObject, PlaybackEngine {
    private static let seekSettleDelay: Duration = .milliseconds(150)
    private static let seekRetryDelay: Duration = .milliseconds(450)
    private static let pendingSeekTolerance: TimeInterval = 1.0
    private static let pendingSeekStaleUpdateWindow: TimeInterval = 1.5

    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isBuffering = false
    private(set) var error: PlaybackError?
    private(set) var availableSubtitleTracks: [SubtitleTrack] = []
    private(set) var availableAudioTracks: [AudioTrack] = []
    private(set) var selectedSubtitleTrackID: Int?
    private(set) var selectedAudioTrackID: Int?
    var onPlaybackEnded: (@MainActor () -> Void)?

    nonisolated(unsafe) private let mediaPlayer: VLCMediaPlayer
    private let renderHost: VLCPictureInPictureRenderHost

    private var pendingStartPosition: TimeInterval?
    private var hasAppliedStartPosition = false
    private var hasReportedPlaybackEnded = false
    private var suppressPlaybackEndedEvent = false
    private var pendingSeekTarget: TimeInterval?
    private var pendingSeekStartedAt: Date?
    @ObservationIgnored nonisolated(unsafe) private var seekVerificationTask: Task<Void, Never>?

    override init() {
        let player = VLCMediaPlayer()
        let renderHost = VLCPictureInPictureRenderHost()
        self.mediaPlayer = player
        self.renderHost = renderHost
        super.init()

        renderHost.playHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.play()
            }
        }
        renderHost.pauseHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.pause()
            }
        }
        renderHost.seekHandler = { [weak self] offsetMs, completion in
            Task { @MainActor [weak self] in
                guard let self else {
                    completion()
                    return
                }
                let targetSeconds = max(0, self.currentTime + (TimeInterval(offsetMs) / 1000.0))
                self.seek(to: targetSeconds)
                completion()
            }
        }
        player.delegate = self
        player.drawable = renderHost
        player.timeChangeUpdateInterval = 0.25
        player.minimalTimePeriod = 250_000
    }

    deinit {
        seekVerificationTask?.cancel()
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
        mediaPlayer.drawable = nil
        renderHost.playHandler = nil
        renderHost.pauseHandler = nil
        renderHost.seekHandler = nil
    }

    func load(url: URL, startPosition: TimeInterval?) {
        state = .loading
        isBuffering = true
        error = nil
        currentTime = 0
        duration = 0
        hasAppliedStartPosition = false
        hasReportedPlaybackEnded = false
        suppressPlaybackEndedEvent = false
        clearPendingSeek()
        pendingStartPosition = startPosition
        availableSubtitleTracks = []
        availableAudioTracks = []
        selectedSubtitleTrackID = nil
        selectedAudioTrackID = nil
        syncPictureInPictureState()

        guard let media = VLCMedia(url: url) else {
            isBuffering = false
            state = .error
            error = .unknown("VLCKit could not create media for the selected URL")
            return
        }
        applySubtitleStyling(to: media)
        mediaPlayer.media = media
        mediaPlayer.currentSubTitleFontScale = PlaybackSubtitleStyle.vlcSubtitleFontScale
        mediaPlayer.play()
    }

    func play() {
        suppressPlaybackEndedEvent = false
        mediaPlayer.play()
        syncPictureInPictureState()
    }

    func pause() {
        seekVerificationTask?.cancel()
        seekVerificationTask = nil
        mediaPlayer.pause()
        syncPictureInPictureState()
    }

    func stop() {
        clearPendingSeek()
        suppressPlaybackEndedEvent = true
        mediaPlayer.stop()
        state = .stopped
        hasReportedPlaybackEnded = false
        syncPictureInPictureState()
    }

    func seek(to position: TimeInterval) {
        let clampedPosition: TimeInterval
        if duration > 0 {
            clampedPosition = min(max(position, 0), duration)
        } else {
            clampedPosition = max(position, 0)
        }

        pendingSeekTarget = clampedPosition
        pendingSeekStartedAt = Date()
        currentTime = clampedPosition

        // Seek without pausing — pausing first creates a race between
        // VLCKit's asynchronous state callbacks and the timed resume,
        // which can leave the player stuck in a paused state.
        applySeek(to: clampedPosition)
        scheduleSeekVerification(target: clampedPosition)
        syncPictureInPictureState()
    }

    func selectSubtitleTrack(_ track: SubtitleTrack?) {
        guard let track else {
            mediaPlayer.deselectAllTextTracks()
            selectedSubtitleTrackID = nil
            return
        }

        mediaPlayer.textTracks
            .first { Int($0.identifier) == track.id }?
            .isSelectedExclusively = true
        selectedSubtitleTrackID = track.id
    }

    func selectAudioTrack(_ track: AudioTrack) {
        mediaPlayer.audioTracks
            .first { Int($0.identifier) == track.id }?
            .isSelectedExclusively = true
        selectedAudioTrackID = track.id
    }

    func makePlayerView() -> AnyView {
        AnyView(VLCPlayerRepresentable(playerView: renderHost.containerView))
    }

    fileprivate func handleStateChange(_ vlcState: VLCMediaPlayerState) {
        switch vlcState {
        case .opening, .buffering:
            isBuffering = true
            if state != .playing && state != .paused {
                state = .loading
            }

        case .playing:
            isBuffering = false
            state = .playing
            suppressPlaybackEndedEvent = false

            if !hasAppliedStartPosition, let start = pendingStartPosition, start > 0 {
                hasAppliedStartPosition = true
                seek(to: start)
            }

            refreshTracks()

        case .paused:
            isBuffering = false
            state = .paused

        case .stopping:
            isBuffering = false

        case .stopped:
            isBuffering = false
            state = .stopped
            clearPendingSeek()

            if !suppressPlaybackEndedEvent, shouldTreatCurrentStopAsPlaybackEnded {
                currentTime = max(currentTime, duration)
                if !hasReportedPlaybackEnded {
                    hasReportedPlaybackEnded = true
                    onPlaybackEnded?()
                }
            }

            suppressPlaybackEndedEvent = false

        case .error:
            isBuffering = false
            state = .error
            error = .unknown("VLCKit playback error")
            clearPendingSeek()

        @unknown default:
            break
        }

        syncPictureInPictureState()
        renderHost.invalidatePlaybackState()
    }

    fileprivate func updateTime(timeMs: Int32, lengthMs: Int32) {
        let updatedTime = max(0, TimeInterval(timeMs) / 1000.0)
        if lengthMs > 0 {
            duration = TimeInterval(lengthMs) / 1000.0
        }

        if shouldAcceptUpdatedTime(updatedTime) {
            currentTime = updatedTime
        }
        syncPictureInPictureState()
    }

    private var shouldTreatCurrentStopAsPlaybackEnded: Bool {
        let durationTolerance = max(1.0, min(5.0, duration * 0.01))
        let reachedDuration = duration > 0 && currentTime >= max(0, duration - durationTolerance)
        let reachedEndPosition = mediaPlayer.position >= 0.98
        return reachedDuration || reachedEndPosition
    }

    private func syncPictureInPictureState() {
        renderHost.updatePlaybackState(
            currentTimeMs: Int64(currentTime * 1000),
            durationMs: Int64(duration * 1000),
            isPlaying: state == .playing,
            isSeekable: duration > 0
        )
    }

    private func applySubtitleStyling(to media: VLCMedia) {
        media.addOption(":freetype-color=#FFFFFF")
        media.addOption(":freetype-background-color=#000000")
        media.addOption(":freetype-background-opacity=110")
        media.addOption(":freetype-shadow-color=#000000")
        media.addOption(":freetype-shadow-opacity=80")
        media.addOption(":freetype-shadow-distance=1")
    }

    private func applySeek(to position: TimeInterval) {
        if duration > 0 {
            let normalizedPosition = min(max(position / duration, 0), 1)
            if normalizedPosition.isFinite {
                mediaPlayer.position = normalizedPosition
            }
        }

        let targetMs = Int(position * 1000.0)
        mediaPlayer.time = VLCTime(int: Int32(clamping: targetMs))
    }

    private func scheduleSeekVerification(target: TimeInterval) {
        seekVerificationTask?.cancel()
        seekVerificationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.seekSettleDelay)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }

            if self.shouldRetrySeek(toward: target) {
                self.applySeek(to: target)
            }

            do {
                try await Task.sleep(for: Self.seekRetryDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            if self.shouldRetrySeek(toward: target) {
                self.applySeek(to: target)
            }
        }
    }

    private func shouldRetrySeek(toward target: TimeInterval) -> Bool {
        guard let pendingSeekTarget else { return false }
        guard abs(pendingSeekTarget - target) <= Self.pendingSeekTolerance else { return false }
        return !hasReachedPendingSeekTarget(using: observedPlayerTime)
    }

    private func shouldAcceptUpdatedTime(_ updatedTime: TimeInterval) -> Bool {
        guard pendingSeekTarget != nil else { return true }

        if hasReachedPendingSeekTarget(using: updatedTime) {
            clearPendingSeek()
            return true
        }

        let elapsed = pendingSeekStartedAt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        if elapsed < Self.pendingSeekStaleUpdateWindow {
            return false
        }

        clearPendingSeek()
        return true
    }

    private func hasReachedPendingSeekTarget(using updatedTime: TimeInterval) -> Bool {
        guard let pendingSeekTarget else { return true }
        return abs(updatedTime - pendingSeekTarget) <= Self.pendingSeekTolerance
    }

    private var observedPlayerTime: TimeInterval {
        max(0, TimeInterval(mediaPlayer.time.intValue) / 1000.0)
    }

    private func clearPendingSeek() {
        pendingSeekTarget = nil
        pendingSeekStartedAt = nil
        seekVerificationTask?.cancel()
        seekVerificationTask = nil
    }

    private func refreshTracks() {
        availableAudioTracks = mediaPlayer.audioTracks.map { track in
            AudioTrack(
                id: Int(track.identifier),
                displayTitle: trackDisplayTitle(for: track),
                language: track.language,
                languageCode: normalizedLanguageCode(from: track.language),
                codec: track.codecName(),
                channels: Int(track.audio?.channelsNumber ?? 0).nonZeroValue,
                channelLayout: nil
            )
        }
        selectedAudioTrackID = mediaPlayer.audioTracks.first(where: \.isSelected).map { Int($0.identifier) }

        availableSubtitleTracks = mediaPlayer.textTracks.map { track in
            SubtitleTrack(
                id: Int(track.identifier),
                displayTitle: trackDisplayTitle(for: track),
                language: track.language,
                languageCode: normalizedLanguageCode(from: track.language),
                codec: track.codecName(),
                isForced: false,
                isHearingImpaired: false,
                isExternal: false,
                externalURL: nil
            )
        }
        selectedSubtitleTrackID = mediaPlayer.textTracks.first(where: \.isSelected).map { Int($0.identifier) }
    }

    private func trackDisplayTitle(for track: VLCMediaPlayer.Track) -> String {
        if !track.trackName.isEmpty {
            return track.trackName
        }

        if let description = track.trackDescription, !description.isEmpty {
            return description
        }

        if let language = track.language, !language.isEmpty {
            return language
        }

        return "Unknown"
    }

    private func normalizedLanguageCode(from language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        return language.lowercased()
    }
}

extension VLCKitEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor [weak self] in
            self?.handleStateChange(newState)
        }
    }

    nonisolated func mediaPlayerLengthChanged(_ length: Int64) {
        let timeMs = mediaPlayer.time.intValue
        Task { @MainActor [weak self] in
            self?.updateTime(timeMs: timeMs, lengthMs: Int32(length))
            self?.renderHost.invalidatePlaybackState()
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let timeMs = mediaPlayer.time.intValue
        let lengthMs = mediaPlayer.media?.length.intValue ?? 0
        Task { @MainActor [weak self] in
            self?.updateTime(timeMs: timeMs, lengthMs: lengthMs)
        }
    }

    nonisolated func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            self?.refreshTracks()
        }
    }

    nonisolated func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            self?.refreshTracks()
        }
    }

    nonisolated func mediaPlayerTrackUpdated(_ trackId: String, with trackType: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            self?.refreshTracks()
        }
    }

    nonisolated func mediaPlayerTrackSelected(
        _ trackType: VLCMedia.TrackType,
        selectedId: String,
        unselectedId: String
    ) {
        Task { @MainActor [weak self] in
            self?.refreshTracks()
        }
    }
}

private struct VLCPlayerRepresentable: UIViewRepresentable {
    let playerView: UIView

    func makeUIView(context: Context) -> UIView {
        playerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class VLCPictureInPictureRenderHost: NSObject, @unchecked Sendable, VLCDrawable, VLCPictureInPictureDrawable, VLCPictureInPictureMediaControlling {
    let containerView: VLCPictureInPictureContainerView

    var playHandler: (() -> Void)?
    var pauseHandler: (() -> Void)?
    var seekHandler: ((Int64, @escaping () -> Void) -> Void)?

    private var pictureInPictureController: (any VLCPictureInPictureWindowControlling)?
    private var hostedVideoView: UIView?
    private var currentTimeMs: Int64 = 0
    private var durationMs: Int64 = 0
    private var mediaPlaying = false
    private var mediaSeekable = false
    private var pendingAutomaticPiPStart = false
    private var isPictureInPictureActive = false
    private var notificationObservers: [NSObjectProtocol] = []

    @MainActor
    override init() {
        self.containerView = VLCPictureInPictureContainerView()
        super.init()
        containerView.backgroundColor = .black
        observeApplicationLifecycle()
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func updatePlaybackState(
        currentTimeMs: Int64,
        durationMs: Int64,
        isPlaying: Bool,
        isSeekable: Bool
    ) {
        self.currentTimeMs = currentTimeMs
        self.durationMs = durationMs
        self.mediaPlaying = isPlaying
        self.mediaSeekable = isSeekable
    }

    func invalidatePlaybackState() {
        pictureInPictureController?.invalidatePlaybackState()
    }

    func addSubview(_ view: UIView) {
        MainActor.assumeIsolated {
            if hostedVideoView !== view {
                hostedVideoView?.removeFromSuperview()
                hostedVideoView = view
                view.frame = containerView.bounds
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                containerView.addSubview(view)
            }
        }
    }

    func bounds() -> CGRect {
        MainActor.assumeIsolated {
            containerView.bounds
        }
    }

    func mediaController() -> (any VLCPictureInPictureMediaControlling)? {
        self
    }

    func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)? {
        { [weak self] controller in
            guard let self, let controller else { return }

            self.pictureInPictureController = controller
            controller.stateChangeEventHandler = { [weak self] isStarted in
                self?.isPictureInPictureActive = isStarted
                if isStarted {
                    self?.pendingAutomaticPiPStart = false
                }
            }
            controller.invalidatePlaybackState()
        }
    }

    func play() {
        playHandler?()
    }

    func pause() {
        pauseHandler?()
    }

    func seek(by offset: Int64, completion: @escaping () -> Void) {
        seekHandler?(offset, completion)
    }

    func mediaLength() -> Int64 {
        durationMs
    }

    func mediaTime() -> Int64 {
        currentTimeMs
    }

    func isMediaSeekable() -> Bool {
        mediaSeekable
    }

    func isMediaPlaying() -> Bool {
        mediaPlaying
    }

    private func observeApplicationLifecycle() {
        let notificationCenter = NotificationCenter.default
        notificationObservers = [
            notificationCenter.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.pendingAutomaticPiPStart = self?.shouldStartPictureInPictureAutomatically ?? false
            },
            notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.pendingAutomaticPiPStart = false
            },
            notificationCenter.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.startPictureInPictureIfNeeded()
            },
        ]
    }

    private var shouldStartPictureInPictureAutomatically: Bool {
        MainActor.assumeIsolated {
            pictureInPictureController != nil &&
            !isPictureInPictureActive &&
            mediaPlaying &&
            containerView.window != nil &&
            !containerView.bounds.isEmpty
        }
    }

    private func startPictureInPictureIfNeeded() {
        guard pendingAutomaticPiPStart, shouldStartPictureInPictureAutomatically else {
            pendingAutomaticPiPStart = false
            return
        }

        pendingAutomaticPiPStart = false
        pictureInPictureController?.startPictureInPicture()
    }
}

private final class VLCPictureInPictureContainerView: UIView {}

private extension Int {
    var nonZeroValue: Int? {
        self == 0 ? nil : self
    }
}
#endif
