//
//  ImageCache.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import UIKit

/// In-memory cache for decoded reference photo thumbnails.
/// Avoids re-decoding JPEG data on every SwiftUI body evaluation.
/// NSCache automatically evicts entries under memory pressure.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSUUID, UIImage>()

    func image(for id: UUID, data: Data?) -> UIImage? {
        let key = id as NSUUID
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
