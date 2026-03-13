import SwiftUI

struct SettingsView: View {
    @Binding var path: NavigationPath
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        #if os(tvOS)
        SettingsTVView(path: $path, viewModel: viewModel)
        #else
        SettingsIOSView(path: $path, viewModel: viewModel)
        #endif
    }
}
