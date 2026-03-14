import Foundation

@MainActor
@Observable
final class LibrariesViewModel {
    private let plexService: PlexService

    private(set) var libraries: [PlexLibrary] = []
    private(set) var isLoading = false
    private(set) var error: String?

    init(plexService: PlexService) {
        self.plexService = plexService
    }

    var availableLibraryTypes: [PlexLibraryType] {
        PlexLibraryType.allCases.filter { hasLibraries(for: $0) }
    }

    func libraries(for type: PlexLibraryType) -> [PlexLibrary] {
        libraries.filter { $0.libraryType == type }
    }

    func hasLibraries(for type: PlexLibraryType) -> Bool {
        libraries.contains { $0.libraryType == type }
    }

    func loadLibraries(force: Bool = false) async {
        guard !isLoading else { return }
        guard force || libraries.isEmpty else { return }

        isLoading = true
        error = nil
        do {
            libraries = try await plexService.getLibraries().filter { $0.libraryType != nil }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func iconName(for library: PlexLibrary) -> String {
        library.libraryType?.systemImage ?? "folder"
    }

    func artURL(for library: PlexLibrary, width: Int, height: Int) -> URL? {
        plexService.imageURL(
            for: library.composite ?? library.art ?? library.thumb,
            width: width,
            height: height
        )
    }
}
