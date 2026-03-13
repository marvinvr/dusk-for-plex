import SwiftUI

struct PlayerDebugOverlayView: View {
    let debugInfo: PlaybackDebugInfo
    let state: PlaybackState
    let isBuffering: Bool

    var body: some View {
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
                        ForEach(debugEntries) { entry in
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

    private var debugEntries: [DebugOverlayEntry] {
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
            DebugOverlayEntry(label: "State", value: stateLabel),
        ]
    }

    private var stateLabel: String {
        let stateText: String
        switch state {
        case .idle:
            stateText = "Idle"
        case .loading:
            stateText = "Loading"
        case .playing:
            stateText = "Playing"
        case .paused:
            stateText = "Paused"
        case .stopped:
            stateText = "Stopped"
        case .error:
            stateText = "Error"
        }

        return isBuffering ? "\(stateText) / Buffering" : stateText
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
}

private struct DebugOverlayEntry: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}
