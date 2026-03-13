import Foundation

extension PlexService {
    func discoverServers() async throws -> [PlexServer] {
        guard authToken != nil else { throw PlexServiceError.notAuthenticated }

        guard let url = buildURL(
            base: Self.plexTVBase,
            path: "/api/v2/resources",
            queryItems: [
                URLQueryItem(name: "includeHttps", value: "1"),
                URLQueryItem(name: "includeRelay", value: "1"),
            ]
        ) else { throw PlexServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        let data = try await executeRequest(request)

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PlexServiceError.decodingError("Expected JSON array from resources endpoint")
        }

        return jsonArray.compactMap { json -> PlexServer? in
            guard let provides = json["provides"] as? String, provides.contains("server") else {
                return nil
            }
            guard let itemData = try? JSONSerialization.data(withJSONObject: json) else {
                return nil
            }
            return try? decoder.decode(PlexServer.self, from: itemData)
        }
    }

    func connect(to server: PlexServer) async throws {
        let candidates = connectionCandidates(for: server)
        var lastFailure = "Could not connect to \(server.name)"

        for candidate in candidates {
            for token in connectionProbeTokens(for: server) {
                var request = URLRequest(url: candidate.probeURL)
                request.httpMethod = "GET"
                request.timeoutInterval = candidate.connection.local ? 20 : 8
                applyHeaders(to: &request)

                if let token {
                    request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
                }

                do {
                    let (_, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        lastFailure = "Invalid response from \(server.name)"
                        continue
                    }

                    guard (200...299).contains(http.statusCode) else {
                        lastFailure = "HTTP \(http.statusCode) from \(server.name)"
                        continue
                    }

                    setServer(server, baseURL: candidate.baseURL)
                    return
                } catch {
                    lastFailure = error.localizedDescription
                }
            }
        }

        throw PlexServiceError.networkError(lastFailure)
    }

    func connectionCandidates(for server: PlexServer) -> [ConnectionCandidate] {
        var candidates: [ConnectionCandidate] = []
        var seen = Set<String>()

        for connection in server.sortedConnections where !connection.isKnownUnreachableAddress {
            if connection.local, let httpFallbackURI = connection.httpFallbackURI {
                appendConnectionCandidate(
                    uri: httpFallbackURI,
                    connection: connection,
                    seen: &seen,
                    into: &candidates
                )
            }

            appendConnectionCandidate(
                uri: connection.uri,
                connection: connection,
                seen: &seen,
                into: &candidates
            )

            if !connection.local, let httpFallbackURI = connection.httpFallbackURI {
                appendConnectionCandidate(
                    uri: httpFallbackURI,
                    connection: connection,
                    seen: &seen,
                    into: &candidates
                )
            }
        }

        return candidates
    }

    func appendConnectionCandidate(
        uri: String,
        connection: PlexConnection,
        seen: inout Set<String>,
        into candidates: inout [ConnectionCandidate]
    ) {
        guard let baseURL = URL(string: uri),
              seen.insert(baseURL.absoluteString).inserted,
              let probeURL = buildURL(base: baseURL.absoluteString, path: "/identity") else {
            return
        }

        candidates.append(
            ConnectionCandidate(
                baseURL: baseURL,
                probeURL: probeURL,
                connection: connection
            )
        )
    }

    func connectionProbeTokens(for server: PlexServer) -> [String?] {
        var tokens: [String?] = []

        if let serverToken = server.accessToken {
            tokens.append(serverToken)
        }

        if let authToken, tokens.contains(authToken) == false {
            tokens.append(authToken)
        }

        return tokens.isEmpty ? [nil] : tokens
    }
}

struct ConnectionCandidate {
    let baseURL: URL
    let probeURL: URL
    let connection: PlexConnection
}
