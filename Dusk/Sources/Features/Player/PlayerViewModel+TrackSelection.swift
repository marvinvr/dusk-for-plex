import Foundation

extension PlayerViewModel {
    func selectSubtitle(_ track: SubtitleTrack?) {
        hasAppliedAutomaticSubtitleSelection = true
        engine.selectSubtitleTrack(track)
        selectedSubtitleTrackID = track?.id
        showSubtitlePicker = false
    }

    func selectAudio(_ track: AudioTrack) {
        hasAppliedAutomaticAudioSelection = true
        engine.selectAudioTrack(track)
        selectedAudioTrackID = track.id
        showAudioPicker = false
    }

    func syncTrackLists() {
        audioTracks = mergeAudioMetadata(into: engine.availableAudioTracks)
        subtitleTracks = mergeSubtitleMetadata(into: engine.availableSubtitleTracks)
        selectedAudioTrackID = resolvedSelectedAudioTrackID()
        selectedSubtitleTrackID = resolvedSelectedSubtitleTrackID()
    }

    func applyAutomaticTrackSelectionIfNeeded() {
        guard hasConfiguredAutomaticTrackSelection else { return }

        if !hasAppliedAutomaticAudioSelection, !audioTracks.isEmpty {
            if let preferredAudioTrack = preferredAudioTrack() {
                engine.selectAudioTrack(preferredAudioTrack)
                selectedAudioTrackID = preferredAudioTrack.id
            }
            hasAppliedAutomaticAudioSelection = true
        }

        if !hasAppliedAutomaticSubtitleSelection, !subtitleTracks.isEmpty {
            let preferredSubtitleTrack = preferredSubtitleTrack()
            engine.selectSubtitleTrack(preferredSubtitleTrack)
            selectedSubtitleTrackID = preferredSubtitleTrack?.id
            hasAppliedAutomaticSubtitleSelection = true
        }
    }

    func preferredAudioTrack() -> AudioTrack? {
        guard let preferredAudioLanguage else { return nil }

        return audioTracks.first {
            Self.normalizedLanguageCode($0.languageCode) == preferredAudioLanguage
        }
    }

    func preferredSubtitleTrack() -> SubtitleTrack? {
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

    func rankedSubtitleTrack(
        from tracks: [SubtitleTrack],
        preferredLanguage: String,
        preferForcedTracks: Bool
    ) -> SubtitleTrack? {
        tracks
            .filter { Self.normalizedLanguageCode($0.languageCode) == preferredLanguage }
            .sorted(by: Self.subtitleOrdering(preferForcedTracks: preferForcedTracks))
            .first
    }

    func resolvedSelectedAudioTrackID() -> Int? {
        if let selectedTrackID = engine.selectedAudioTrackID,
           audioTracks.contains(where: { $0.id == selectedTrackID }) {
            return selectedTrackID
        }

        if let sourceStream = sourcePart?.streams.first(where: {
            $0.streamType == .audio && ($0.isSelected ?? false)
        }), let matchedTrack = bestMatchingAudioTrack(for: sourceStream) {
            return matchedTrack.id
        }

        return audioTracks.first?.id
    }

    func resolvedSelectedSubtitleTrackID() -> Int? {
        if let selectedTrackID = engine.selectedSubtitleTrackID,
           subtitleTracks.contains(where: { $0.id == selectedTrackID }) {
            return selectedTrackID
        }

        if let sourceStream = sourcePart?.streams.first(where: {
            $0.streamType == .subtitle && ($0.isSelected ?? false)
        }), let matchedTrack = bestMatchingSubtitleTrack(for: sourceStream) {
            return matchedTrack.id
        }

        return nil
    }

    func bestMatchingAudioTrack(for stream: PlexStream) -> AudioTrack? {
        bestMatchingTrack(in: audioTracks) { track in
            scoreAudioMatch(track: track, stream: stream)
        }
    }

    func bestMatchingSubtitleTrack(for stream: PlexStream) -> SubtitleTrack? {
        bestMatchingTrack(in: subtitleTracks) { track in
            scoreSubtitleMatch(track: track, stream: stream)
        }
    }

    func bestMatchingTrack<Track>(
        in tracks: [Track],
        score: (Track) -> Int
    ) -> Track? {
        let best = tracks.max { lhs, rhs in
            score(lhs) < score(rhs)
        }

        guard let best, score(best) > 0 else { return nil }
        return best
    }

    func mergeAudioMetadata(into engineTracks: [AudioTrack]) -> [AudioTrack] {
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

    func mergeSubtitleMetadata(into engineTracks: [SubtitleTrack]) -> [SubtitleTrack] {
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

    func popBestMatch<Track>(
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

    func scoreAudioMatch(track: AudioTrack, stream: PlexStream) -> Int {
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

    func scoreSubtitleMatch(track: SubtitleTrack, stream: PlexStream) -> Int {
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

    static func subtitleOrdering(preferForcedTracks: Bool) -> (SubtitleTrack, SubtitleTrack) -> Bool {
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

    static func subtitleSortScore(
        isForced: Bool,
        isHearingImpaired: Bool,
        preferForcedTracks: Bool
    ) -> Int {
        var score = 0
        score += preferForcedTracks ? (isForced ? 4 : 0) : (isForced ? 0 : 4)
        score += isHearingImpaired ? 0 : 2
        return score
    }

    static func normalizedLanguageCode(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
            .split(separator: "-")
            .first?
            .lowercased()
    }

    static func normalizedTitle(_ value: String?) -> String? {
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

    static func containsForcedMarker(_ value: String) -> Bool {
        let normalized = normalizedTitle(value) ?? ""
        return normalized.contains("forced")
    }

    static func containsHearingImpairedMarker(_ value: String) -> Bool {
        let normalized = normalizedTitle(value) ?? ""
        return normalized.contains("sdh")
            || normalized.contains("cc")
            || normalized.contains("hearing impaired")
    }
}
