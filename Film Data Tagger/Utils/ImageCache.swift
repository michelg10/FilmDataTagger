//
//  ImageCache.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import UIKit

/// In-memory cache for decoded reference photo thumbnails (180px JPEG).
/// NSCache automatically evicts under memory pressure.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSUUID, UIImage>()

    func cachedImage(for id: UUID) -> UIImage? {
        cache.object(forKey: id as NSUUID)
    }

    func image(for id: UUID, thumbnailData: Data?) -> UIImage? {
        let key = id as NSUUID
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let thumbnailData,
              let image = UIImage(data: thumbnailData) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Insert a decoded image into the cache so the first display is free.
    func preload(for id: UUID, data: Data) {
        let key = id as NSUUID
        guard cache.object(forKey: key) == nil,
              let image = UIImage(data: data) else { return }
        cache.setObject(image, forKey: key)
    }
}
