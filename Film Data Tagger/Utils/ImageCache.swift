//
//  ImageCache.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import UIKit
import ImageIO

/// In-memory cache for decoded reference photo thumbnails.
/// Decodes directly at display size (~120px) to avoid loading full-resolution
/// images into memory. NSCache automatically evicts under memory pressure.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSUUID, UIImage>()

    /// Maximum pixel dimension for cached thumbnails (60pt × 2x retina).
    private let maxPixelSize = 120

    func image(for id: UUID, data: Data?) -> UIImage? {
        let key = id as NSUUID
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }
}
