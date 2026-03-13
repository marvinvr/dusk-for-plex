import Foundation

extension PlexService {
    func setAuthToken(_ token: String) {
        authToken = token
        KeychainHelper.save(key: Self.keychainTokenKey, data: Data(token.utf8))
    }

    func clearAuthToken() {
        authToken = nil
        KeychainHelper.delete(key: Self.keychainTokenKey)
    }

    func generatePin(strong: Bool = false) async throws -> PlexPin {
        try await plexTVRequest(
            method: "POST",
            path: "/api/v2/pins",
            formBody: strong ? ["strong": "true"] : nil
        )
    }

    func checkPin(_ pinId: Int) async throws -> String? {
        let pin: PlexPin = try await plexTVRequest(path: "/api/v2/pins/\(pinId)")
        return pin.authToken
    }

    func signOut() {
        clearAuthToken()
        clearServer()
    }

    func authURL(for pin: PlexPin) -> URL? {
        URL(string: "https://app.plex.tv/auth#?clientID=\(clientIdentifier)&code=\(pin.code)&context%5Bdevice%5D%5Bproduct%5D=Dusk")
    }
}
