import Foundation

extension PlayerViewModel {
    func startSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sync()
            }
        }
    }

    func sync() {
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

    func scheduleHide() {
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

    func seek(to position: TimeInterval, revealControls: Bool) {
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
}
