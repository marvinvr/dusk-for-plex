import SwiftUI

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.duskTextSecondary.opacity(0.3), lineWidth: 2)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.duskAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
