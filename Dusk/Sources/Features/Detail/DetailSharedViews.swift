import SwiftUI

struct ActorCreditCard: View {
    let person: PlexPersonReference
    let plexService: PlexService

    var body: some View {
        NavigationLink(value: AppNavigationRoute.person(person)) {
            VStack(spacing: 8) {
                if let thumbPath = person.thumb {
                    AsyncImage(url: plexService.imageURL(for: thumbPath, width: 72, height: 72)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            placeholder
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                } else {
                    placeholder
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                }

                VStack(spacing: 2) {
                    Text(person.name)
                        .font(.caption)
                        .foregroundStyle(Color.duskTextPrimary)
                        .lineLimit(1)

                    if let roleName = person.roleName, !roleName.isEmpty {
                        Text(roleName)
                            .font(.caption2)
                            .foregroundStyle(Color.duskTextSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
        .duskSuppressTVOSButtonChrome()
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.title2)
            .foregroundStyle(Color.duskTextSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.duskSurface)
    }
}

struct ExpandableSummaryText: View {
    let text: String

    private let collapsedLineLimit = 9

    @State private var isExpanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var expandedHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.body)
                .foregroundStyle(Color.duskTextSecondary)
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .truncationMode(.tail)
                .overlay(alignment: .topLeading) {
                    ZStack {
                        measurementText(lineLimit: collapsedLineLimit) { height in
                            collapsedHeight = height
                        }

                        measurementText(lineLimit: nil) { height in
                            expandedHeight = height
                        }
                    }
                    .hidden()
                    .allowsHitTesting(false)
                }

            if isExpandable {
                Button(isExpanded ? "Show Less" : "Show More") {
                    isExpanded.toggle()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.duskAccent)
                .buttonStyle(.plain)
                .duskSuppressTVOSButtonChrome()
            }
        }
    }

    private var isExpandable: Bool {
        expandedHeight > collapsedHeight + 1
    }

    private func measurementText(
        lineLimit: Int?,
        onHeightChange: @escaping (CGFloat) -> Void
    ) -> some View {
        Text(text)
            .font(.body)
            .lineSpacing(4)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            onHeightChange(proxy.size.height)
                        }
                        .onChange(of: proxy.size.height) { _, newHeight in
                            onHeightChange(newHeight)
                        }
                }
            }
    }
}
