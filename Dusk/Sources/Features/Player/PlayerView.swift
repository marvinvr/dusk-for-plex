import SwiftUI

/// Full-screen video player with controls overlay, track pickers, and auto-hide.
///
/// Present via `.fullScreenCover`. Playback starts on first appearance so the
/// underlying render surface is attached before the engine begins loading.
struct PlayerView: View {
    @Environment(UserPreferences.self) private var preferences
    @State private var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    private let playbackSource: PlaybackSource
    private let mediaDetails: PlexMediaDetails?
    private let debugInfo: PlaybackDebugInfo?

    init(
        engine: any PlaybackEngine,
        playbackSource: PlaybackSource,
        mediaDetails: PlexMediaDetails? = nil,
        debugInfo: PlaybackDebugInfo? = nil
    ) {
        _viewModel = State(
            initialValue: PlayerViewModel(
                engine: engine,
                markers: mediaDetails?.markers ?? []
            )
        )
        self.playbackSource = playbackSource
        self.mediaDetails = mediaDetails
        self.debugInfo = debugInfo
    }

    var body: some View {
        @Bindable var vm = viewModel

        ZStack {
            // Black letterbox behind video
            Color.black.ignoresSafeArea()

            // Video surface
            viewModel.engineView
                .ignoresSafeArea()

            interactionOverlay

            // Buffering spinner
            if viewModel.shouldShowBufferingIndicator {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // Error overlay
            if let error = viewModel.playbackError {
                errorOverlay(error)
            }

            if preferences.playerDebugOverlayEnabled,
               let debugInfo,
               viewModel.playbackError == nil {
                debugOverlay(debugInfo)
            }

            if let marker = viewModel.activeSkipMarker,
               viewModel.playbackError == nil {
                skipMarkerOverlay(marker)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Controls overlay
            if viewModel.showControls, viewModel.playbackError == nil {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        .animation(.easeInOut(duration: 0.2), value: viewModel.activeSkipMarker?.id)
        .duskStatusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.configureAutomaticTrackSelection(
                preferences: preferences,
                part: debugInfo?.part ?? mediaDetails?.media.first?.parts.first
            )
            // Start playback only after the full-screen player view exists.
            viewModel.startPlaybackIfNeeded(source: playbackSource)
        }
        .onDisappear { viewModel.cleanup() }
        .sheet(isPresented: $vm.showSubtitlePicker) { subtitlePicker }
        .sheet(isPresented: $vm.showAudioPicker) { audioPicker }
    }

    private var interactionOverlay: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                interactionZone(
                    seekOffset: -preferences.playerDoubleTapBackwardInterval.timeInterval
                )
                interactionZone(
                    seekOffset: preferences.playerDoubleTapForwardInterval.timeInterval
                )
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func interactionZone(seekOffset: TimeInterval) -> some View {
        #if os(tvOS)
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { viewModel.toggleControls() }
        #else
        if preferences.playerDoubleTapSeekEnabled {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    TapGesture(count: 2)
                        .onEnded { viewModel.seek(by: seekOffset) }
                        .exclusively(
                            before: TapGesture()
                                .onEnded { viewModel.toggleControls() }
                        )
                )
        } else {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture { viewModel.toggleControls() }
        }
        #endif
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack {
            // Gradient scrim (extends behind safe area)
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.7), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 120)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 160)
            }
            .ignoresSafeArea()

            // Actual controls (respect safe area)
            VStack {
                topBar
                Spacer()
                centerControls
                Spacer()
                bottomBar
            }
            .padding()
        }
    }

    // MARK: - Debug Overlay

    private func debugOverlay(_ debugInfo: PlaybackDebugInfo) -> some View {
        GeometryReader { geometry in
            VStack {
                HStack {
                    Spacer()
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 110), spacing: 12, alignment: .top),
                            GridItem(.flexible(minimum: 110), spacing: 12, alignment: .top),
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(debugEntries(for: debugInfo)) { entry in
                            debugRow(entry.label, entry.value)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }
                    .frame(width: 288, alignment: .leading)
                }
                Spacer()
            }
            .padding(.top, max(16, geometry.safeAreaInsets.top + 8))
            .padding(.horizontal, 16)
        }
        .allowsHitTesting(false)
    }

    private func debugEntries(for debugInfo: PlaybackDebugInfo) -> [DebugOverlayEntry] {
        [
            DebugOverlayEntry(label: "Engine", value: debugInfo.engineLabel),
            DebugOverlayEntry(label: "Mode", value: debugInfo.decisionLabel),
            DebugOverlayEntry(label: "Transcode", value: debugInfo.transcodeLabel),
            DebugOverlayEntry(label: "Container", value: debugInfo.containerLabel),
            DebugOverlayEntry(label: "Bitrate", value: debugInfo.bitrateLabel),
            DebugOverlayEntry(label: "Video", value: debugInfo.videoLabel),
            DebugOverlayEntry(label: "Audio", value: debugInfo.audioLabel),
            DebugOverlayEntry(label: "Resolution", value: debugInfo.resolutionLabel),
            DebugOverlayEntry(label: "File", value: debugInfo.fileSizeLabel),
            DebugOverlayEntry(label: "Subtitles", value: debugInfo.subtitleLabel),
            DebugOverlayEntry(label: "State", value: debugStateLabel),
        ]
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var debugStateLabel: String {
        let stateText: String
        switch viewModel.state {
        case .idle: stateText = "Idle"
        case .loading: stateText = "Loading"
        case .playing: stateText = "Playing"
        case .paused: stateText = "Paused"
        case .stopped: stateText = "Stopped"
        case .error: stateText = "Error"
        }

        if viewModel.isBuffering {
            return "\(stateText) / Buffering"
        }
        return stateText
    }

    private struct DebugOverlayEntry: Identifiable {
        let label: String
        let value: String

        var id: String { label }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                viewModel.cleanup()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }

            if let header = mediaHeader {
                mediaHeaderView(header)
            }

            Spacer()
        }
    }

    private func mediaHeaderView(_ header: PlayerMediaHeader) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(header.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let secondaryTitle = header.secondaryTitle {
                Text(secondaryTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            if let subtitle = header.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
    }

    private var mediaHeader: PlayerMediaHeader? {
        guard let mediaDetails else { return nil }

        if mediaDetails.type == .episode {
            let title = mediaDetails.grandparentTitle ?? mediaDetails.title
            let secondaryTitle = mediaDetails.grandparentTitle == nil ? nil : mediaDetails.title
            let subtitle = episodeContextSubtitle(
                season: mediaDetails.parentIndex,
                episode: mediaDetails.index
            )

            return PlayerMediaHeader(
                title: title,
                secondaryTitle: secondaryTitle,
                subtitle: subtitle
            )
        }

        return PlayerMediaHeader(
            title: mediaDetails.title,
            secondaryTitle: nil,
            subtitle: mediaDetails.year.map(String.init)
        )
    }

    private func episodeContextSubtitle(season: Int?, episode: Int?) -> String? {
        switch (season, episode) {
        case let (season?, episode?):
            return "Season \(season) · Episode \(episode)"
        case let (season?, nil):
            return "Season \(season)"
        case let (nil, episode?):
            return "Episode \(episode)"
        default:
            return nil
        }
    }

    private struct PlayerMediaHeader {
        let title: String
        let secondaryTitle: String?
        let subtitle: String?
    }

    // MARK: - Skip Marker Overlay

    private func skipMarkerOverlay(_ marker: PlexMarker) -> some View {
        GeometryReader { geometry in
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    Button {
                        viewModel.skipActiveMarker()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: marker.isCredits ? "forward.end.fill" : "chevron.forward.2")
                                .font(.callout.weight(.semibold))

                            Text(marker.skipButtonTitle ?? "Skip")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                        .opacity(0.92)
                    }
                    .duskSuppressTVOSButtonChrome()
                    .duskTVOSFocusEffectShape(Capsule())
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, max(geometry.safeAreaInsets.bottom + skipMarkerBottomInset, 24))
        }
        .ignoresSafeArea()
    }

    private var skipMarkerBottomInset: CGFloat {
        viewModel.showControls ? 124 : 36
    }

    // MARK: - Center Controls

    private var centerControls: some View {
        HStack {
            Spacer()
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            seekBar

            HStack {
                Text(viewModel.formattedTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Text("/")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Text(viewModel.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                if !viewModel.subtitleTracks.isEmpty {
                    Button { viewModel.showSubtitlePicker = true } label: {
                        Image(systemName: "captions.bubble")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                }

                if !viewModel.audioTracks.isEmpty {
                    Button { viewModel.showAudioPicker = true } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                }
            }
        }
    }

    // MARK: - Seek Bar

    private var seekBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = viewModel.duration > 0
                ? viewModel.displayPosition / viewModel.duration
                : 0
            let seekTrack = ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.3))
                    .frame(height: 4)

                // Filled track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.duskAccent)
                    .frame(width: max(0, width * progress), height: 4)

                // Thumb
                Circle()
                    .fill(Color.duskAccent)
                    .frame(
                        width: viewModel.isScrubbing ? 16 : 12,
                        height: viewModel.isScrubbing ? 16 : 12
                    )
                    .offset(x: thumbOffset(progress: progress, trackWidth: width))
                    .animation(.easeOut(duration: 0.15), value: viewModel.isScrubbing)
            }
            .frame(height: 32) // tall hit area
            .contentShape(Rectangle())

            #if os(tvOS)
            seekTrack
            #else
            seekTrack.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !viewModel.isScrubbing {
                            viewModel.beginScrub()
                        }
                        let fraction = max(0, min(1, value.location.x / width))
                        viewModel.updateScrub(to: fraction * viewModel.duration)
                    }
                    .onEnded { _ in
                        viewModel.endScrub()
                    }
            )
            #endif
        }
        .frame(height: 32)
    }

    private func thumbOffset(progress: Double, trackWidth: Double) -> Double {
        let thumbRadius: Double = viewModel.isScrubbing ? 8 : 6
        return max(0, min(trackWidth * progress - thumbRadius, trackWidth - thumbRadius * 2))
    }

    // MARK: - Error Overlay

    private func errorOverlay(_ error: PlaybackError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.duskAccent)

            Text(error.localizedDescription)
                .font(.headline)
                .foregroundStyle(Color.duskTextPrimary)
                .multilineTextAlignment(.center)

            Button("Close") {
                viewModel.cleanup()
                dismiss()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color.duskAccent, in: Capsule())
            .duskSuppressTVOSButtonChrome()
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    // MARK: - Subtitle Picker

    private var subtitlePicker: some View {
        NavigationStack {
            List {
                Button {
                    viewModel.selectSubtitle(nil)
                } label: {
                    Text("Off")
                        .foregroundStyle(Color.duskTextPrimary)
                }
                .listRowBackground(Color.duskSurface)
                .duskSuppressTVOSButtonChrome()

                ForEach(viewModel.subtitleTracks) { track in
                    Button {
                        viewModel.selectSubtitle(track)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayTitle)
                                .foregroundStyle(Color.duskTextPrimary)
                            if let lang = track.language {
                                Text(lang)
                                    .font(.caption)
                                    .foregroundStyle(Color.duskTextSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.duskSurface)
                    .duskSuppressTVOSButtonChrome()
                }
            }
            .duskScrollContentBackgroundHidden()
            .background(Color.duskBackground)
            .duskNavigationTitle("Subtitles")
            .duskNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewModel.showSubtitlePicker = false }
                        .duskSuppressTVOSButtonChrome()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.duskBackground)
    }

    // MARK: - Audio Picker

    private var audioPicker: some View {
        NavigationStack {
            List {
                ForEach(viewModel.audioTracks) { track in
                    Button {
                        viewModel.selectAudio(track)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.displayTitle)
                                .foregroundStyle(Color.duskTextPrimary)
                            if let lang = track.language {
                                Text(lang)
                                    .font(.caption)
                                    .foregroundStyle(Color.duskTextSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.duskSurface)
                    .duskSuppressTVOSButtonChrome()
                }
            }
            .duskScrollContentBackgroundHidden()
            .background(Color.duskBackground)
            .duskNavigationTitle("Audio")
            .duskNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewModel.showAudioPicker = false }
                        .duskSuppressTVOSButtonChrome()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.duskBackground)
    }
}
