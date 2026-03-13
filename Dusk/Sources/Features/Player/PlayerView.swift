import SwiftUI

struct PlayerView: View {
    @Environment(PlexService.self) private var plexService
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PlayerViewModel

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
            Color.black.ignoresSafeArea()

            viewModel.engineView
                .ignoresSafeArea()

            if let upNextPresentation = playback.upNextPresentation {
                PlayerUpNextOverlayView(
                    presentation: upNextPresentation,
                    plexService: plexService,
                    onPlayNow: { playback.playUpNextNow() },
                    onDismiss: { dismiss() }
                )
                .transition(.opacity)
            } else {
                interactionOverlay

                if viewModel.shouldShowBufferingIndicator {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }

                if let error = viewModel.playbackError {
                    errorOverlay(error)
                }

                if preferences.playerDebugOverlayEnabled,
                   let debugInfo,
                   viewModel.playbackError == nil {
                    PlayerDebugOverlayView(
                        debugInfo: debugInfo,
                        state: viewModel.state,
                        isBuffering: viewModel.isBuffering
                    )
                }

                if let marker = viewModel.activeSkipMarker,
                   viewModel.playbackError == nil {
                    skipMarkerOverlay(marker)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if viewModel.showControls, viewModel.playbackError == nil {
                    PlayerControlsOverlay(
                        viewModel: viewModel,
                        mediaDetails: mediaDetails,
                        onDismiss: dismissPlayer
                    )
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        .animation(.easeInOut(duration: 0.2), value: viewModel.activeSkipMarker?.id)
        .animation(.easeInOut(duration: 0.25), value: playback.upNextPresentation?.episode.ratingKey)
        .duskStatusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.configureAutomaticTrackSelection(
                preferences: preferences,
                part: debugInfo?.part ?? mediaDetails?.media.first?.parts.first
            )
            viewModel.startPlaybackIfNeeded(source: playbackSource)
        }
        .onDisappear { viewModel.cleanup() }
        .sheet(isPresented: $vm.showSubtitlePicker) {
            PlayerSelectionSheet(
                title: "Subtitles",
                allowsDeselection: true,
                deselectionTitle: "Off",
                items: viewModel.subtitleTracks,
                selectedID: viewModel.selectedSubtitleTrackID,
                itemTitle: \.displayTitle,
                itemSubtitle: \.language,
                onSelect: { item in
                    viewModel.selectSubtitle(item)
                },
                onDismiss: {
                    viewModel.showSubtitlePicker = false
                }
            )
        }
        .sheet(isPresented: $vm.showAudioPicker) {
            PlayerSelectionSheet(
                title: "Audio",
                items: viewModel.audioTracks,
                selectedID: viewModel.selectedAudioTrackID,
                itemTitle: \.displayTitle,
                itemSubtitle: \.language,
                onSelect: { item in
                    if let item {
                        viewModel.selectAudio(item)
                    }
                },
                onDismiss: {
                    viewModel.showAudioPicker = false
                }
            )
        }
    }

    private var interactionOverlay: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                interactionZone(seekOffset: -preferences.playerDoubleTapBackwardInterval.timeInterval)
                interactionZone(seekOffset: preferences.playerDoubleTapForwardInterval.timeInterval)
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

    private func errorOverlay(_ error: PlaybackError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.duskAccent)

            Text(error.localizedDescription)
                .font(.headline)
                .foregroundStyle(Color.duskTextPrimary)
                .multilineTextAlignment(.center)

            Button("Close", action: dismissPlayer)
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

    private func dismissPlayer() {
        viewModel.cleanup()
        dismiss()
    }
}
