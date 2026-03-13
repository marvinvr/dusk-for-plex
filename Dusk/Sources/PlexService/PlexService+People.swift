import Foundation

extension PlexService {
    func getPerson(personID: String) async throws -> PlexPerson {
        let people: [PlexPerson] = try await fetchDirectories(path: "/library/people/\(personID)")
        guard let person = people.first else {
            throw PlexServiceError.decodingError("No person found for id \(personID)")
        }
        return person
    }

    func getPersonMedia(personID: String) async throws -> [PlexItem] {
        let items: [PlexItem] = try await fetchMetadata(path: "/library/people/\(personID)/media")

        var seen = Set<String>()
        return items
            .filter { $0.type == .movie || $0.type == .show }
            .filter { seen.insert($0.ratingKey).inserted }
    }
}
