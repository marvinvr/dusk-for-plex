import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension PlexService {
    func imageURL(for path: String?, width: Int? = nil, height: Int? = nil) -> URL? {
        guard let path else { return nil }

        let requestSize = imageRequestSize(width: width, height: height)
        if requestSize.hasDimensions,
           let transcodedURL = transcodedImageURL(for: path, size: requestSize) {
            return transcodedURL
        }

        return directImageURL(for: path)
    }

    func directImageURL(for path: String) -> URL? {
        guard let urlString = imageRequestURLString(for: path, includeToken: true) else {
            return nil
        }
        return URL(string: urlString)
    }

    func transcodedImageURL(for path: String, size: ImageRequestSize) -> URL? {
        guard let baseURL = serverBaseURL,
              let originalURLString = imageRequestURLString(for: path, includeToken: true) else {
            return nil
        }

        let base = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard var components = URLComponents(string: base + "/photo/:/transcode") else {
            return nil
        }

        var items = [
            URLQueryItem(name: "width", value: String(max(size.width ?? 1, 1))),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "0"),
            URLQueryItem(name: "url", value: originalURLString),
        ]

        if let height = size.height {
            items.append(URLQueryItem(name: "height", value: String(height)))
        }

        if let token = authToken {
            items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }

        components.queryItems = items
        return components.url
    }

    func imageRequestURLString(for path: String, includeToken: Bool) -> String? {
        if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
            return absoluteURL.absoluteString
        }

        guard let baseURL = serverBaseURL else { return nil }
        let base = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard var components = URLComponents(string: base + path) else { return nil }

        if includeToken, let token = authToken {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "X-Plex-Token", value: token))
            components.queryItems = items
        }

        return components.url?.absoluteString
    }

    func imageRequestSize(width: Int?, height: Int?) -> ImageRequestSize {
        ImageRequestSize(
            width: scaledImageDimension(width),
            height: scaledImageDimension(height)
        )
    }

    func scaledImageDimension(_ dimension: Int?) -> Int? {
        guard let dimension, dimension > 0 else { return nil }
        return Int(ceil(Double(dimension) * Double(displayScale)))
    }

    var displayScale: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.scale
        #else
        1
        #endif
    }
}

struct ImageRequestSize {
    let width: Int?
    let height: Int?

    var hasDimensions: Bool {
        width != nil || height != nil
    }
}
