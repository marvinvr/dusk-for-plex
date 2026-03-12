import SwiftUI

struct ServerPickerView: View {
    let servers: [PlexServer]
    let onSelect: (PlexServer) -> Void
    @State private var connectingTo: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.duskBackground.ignoresSafeArea()

                List(servers) { server in
                    Button {
                        connectingTo = server.clientIdentifier
                        onSelect(server)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .font(.headline)
                                    .foregroundStyle(Color.duskTextPrimary)

                                Text(server.owned ? "Your server" : "Shared by \(server.sourceTitle ?? "Unknown")")
                                    .font(.caption)
                                    .foregroundStyle(Color.duskTextSecondary)
                            }

                            Spacer()

                            if connectingTo == server.clientIdentifier {
                                ProgressView()
                                    .tint(Color.duskAccent)
                            } else {
                                Circle()
                                    .fill(server.presence ? Color.duskAccent : Color.duskTextSecondary)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(connectingTo != nil)
                    .duskSuppressTVOSButtonChrome()
                    .listRowBackground(Color.duskSurface)
                }
                .duskScrollContentBackgroundHidden()
                .duskNavigationTitle("Choose Server")
            }
        }
    }
}
