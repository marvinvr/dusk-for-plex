import SwiftUI

struct AdaptivePosterGridLayout {
    let columns: [GridItem]
    let posterWidth: CGFloat

    static func make(
        containerWidth: CGFloat,
        horizontalPadding: CGFloat,
        gridSpacing: CGFloat,
        preferredPosterWidth: CGFloat,
        minimumColumnCount: Int = 2
    ) -> Self {
        let availableWidth = max(containerWidth - (horizontalPadding * 2), preferredPosterWidth)
        let rawColumnCount = Int((availableWidth + gridSpacing) / (preferredPosterWidth + gridSpacing))
        let columnCount = max(rawColumnCount, minimumColumnCount)
        let totalSpacing = CGFloat(columnCount - 1) * gridSpacing
        let posterWidth = floor((availableWidth - totalSpacing) / CGFloat(columnCount))
        let columns = Array(
            repeating: GridItem(.fixed(posterWidth), spacing: gridSpacing, alignment: .top),
            count: columnCount
        )

        return Self(columns: columns, posterWidth: posterWidth)
    }
}
