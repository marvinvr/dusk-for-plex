import Foundation

extension PlaybackCoordinator {
    func playUpNextNow() {
        Task { @MainActor in
            await startUpNextPlayback()
        }
    }

    func cancelUpNextAutoplay() {
        guard var upNextPresentation else { return }
        cancelUpNextCountdown()
        upNextPresentation.shouldAutoplay = false
        upNextPresentation.secondsRemaining = nil
        self.upNextPresentation = upNextPresentation
    }

    func presentUpNext(for episode: PlexEpisode) {
        cancelUpNextCountdown()

        upNextPresentation = UpNextPresentation(
            episode: episode,
            shouldAutoplay: preferences.continuousPlayEnabled,
            countdownDuration: preferences.continuousPlayCountdown.rawValue,
            secondsRemaining: preferences.continuousPlayEnabled ? preferences.continuousPlayCountdown.rawValue : nil
        )

        if preferences.continuousPlayEnabled {
            startUpNextCountdown()
        }
    }

    func startUpNextCountdown() {
        guard let presentation = upNextPresentation,
              presentation.shouldAutoplay else { return }

        cancelUpNextCountdown()

        upNextCountdownTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for remaining in stride(from: presentation.countdownDuration, through: 1, by: -1) {
                if Task.isCancelled { return }

                guard var current = self.upNextPresentation,
                      current.shouldAutoplay else { return }
                current.secondsRemaining = remaining
                self.upNextPresentation = current

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }

            if Task.isCancelled { return }
            await self.startUpNextPlayback()
        }
    }

    func cancelUpNextCountdown() {
        upNextCountdownTask?.cancel()
        upNextCountdownTask = nil
    }

    func startUpNextPlayback() async {
        guard var presentation = upNextPresentation,
              !presentation.isStarting else { return }

        cancelUpNextCountdown()
        presentation.isStarting = true
        presentation.errorMessage = nil
        upNextPresentation = presentation

        let nextRatingKey = presentation.episode.ratingKey
        let didStart = await startPlaybackSession(
            ratingKey: nextRatingKey,
            startPositionOverride: nil,
            presentPlayer: false
        )
        if didStart { return }

        guard var failedPresentation = upNextPresentation else { return }
        failedPresentation.isStarting = false
        failedPresentation.shouldAutoplay = false
        failedPresentation.secondsRemaining = nil
        failedPresentation.errorMessage = loadError ?? "Could not start the next episode."
        upNextPresentation = failedPresentation
        loadError = nil
    }
}
