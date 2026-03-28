//
//  ImageCache.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import UIKit

/// Header for raw bitmap thumbnail files.
private struct BitmapHeader {
    var width: UInt16
    var height: UInt16
    var scale: UInt16
}

/// Tracks when each roll was last viewed. Persisted as a plist.
/// Owns the warming policy: given relationship data from the DataStore,
/// decides which thumbnails to warm into BGRA memory.
actor CacheBookkeeper {
    private var rollAccessDates: [UUID: Date] = [:]

    private static let priorityCameraCount = 8
    private static let lruBudget = 512

    private static let file: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("rollAccessDates.plist")
    }()

    func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let dict = try? PropertyListDecoder().decode([UUID: Date].self, from: data)
        else { return }
        rollAccessDates = dict
    }

    func recordAccess(_ rollID: UUID) {
        rollAccessDates[rollID] = Date()
        save()
    }

    /// Remove access dates for rolls that no longer exist.
    /// TODO: Call from DataStore's orphan cleanup (every 72h), once that's migrated.
    func purgeStaleEntries(existingRollIDs: Set<UUID>) {
        let before = rollAccessDates.count
        rollAccessDates = rollAccessDates.filter { existingRollIDs.contains($0.key) }
        if rollAccessDates.count != before { save() }
    }

    /// Compute which thumbnail IDs to warm, given relationship data from the DataStore.
    ///
    /// `cameraInfo`: each camera's active roll ID (if any) and all its roll IDs.
    /// `rollItemIDs`: maps roll ID → thumbnail item IDs in that roll.
    ///
    /// Policy:
    /// 1. Top 8 most recently accessed cameras → their active rolls' items.
    /// 2. Rolls sorted by last accessed → accumulate items until 512.
    /// 3. Union = priority set.
    func computePriorityIDs(
        cameraInfo: [(cameraID: UUID, activeRollID: UUID?, rollIDs: [UUID])],
        rollItemIDs: [UUID: [UUID]]
    ) -> Set<UUID> {
        var result = Set<UUID>()

        // 1. Priority: active rolls of the 8 most recently accessed cameras
        let camerasByAccess = cameraInfo
            .compactMap { info -> (activeRollID: UUID, date: Date)? in
                guard let activeRollID = info.activeRollID else { return nil }
                let latestAccess = info.rollIDs.compactMap { rollAccessDates[$0] }.max()
                guard let date = latestAccess else { return nil }
                return (activeRollID, date)
            }
            .sorted { $0.date > $1.date }
            .prefix(Self.priorityCameraCount)

        for (activeRollID, _) in camerasByAccess {
            if let ids = rollItemIDs[activeRollID] {
                result.formUnion(ids)
            }
        }

        // 2. LRU: rolls by recency, accumulate until budget
        let rollsByAccess = rollAccessDates.sorted { $0.value > $1.value }
        var budget = Self.lruBudget - result.count
        for (rollID, _) in rollsByAccess {
            guard budget > 0 else { break }
            if let ids = rollItemIDs[rollID] {
                result.formUnion(ids)
                budget -= ids.count
            }
        }

        return result
    }

    private func save() {
        guard let data = try? PropertyListEncoder().encode(rollAccessDates) else { return }
        try? data.write(to: Self.file)
    }
}

// MARK: - ImageCache

/// Three-layer thumbnail cache.
///
/// L1: in-memory NSCache (iOS handles eviction via memory pressure).
/// L2: disk BGRA — raw pixels, zero-decode load. For priority thumbnails.
/// L3: disk JPEG — smaller footprint, needs decode. For everything else.
///
/// New thumbnails always enter as BGRA. On app launch, the DataStore provides
/// relationship data (cameras, rolls, item IDs) and the bookkeeper computes
/// which thumbnails to warm based on roll access recency. Non-priority BGRA
/// files are demoted to JPEG.
///
/// Thread safety: NSCache is thread-safe. Disk I/O is idempotent per thumbnail.
/// Roll access tracking is fire-and-forget to the CacheBookkeeper actor.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSUUID, UIImage>()
    private let bgraURL: URL
    private let jpegURL: URL
    let bookkeeper = CacheBookkeeper()

    private static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
    private static let headerSize = MemoryLayout<BitmapHeader>.size

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let base = caches.appendingPathComponent("thumbnails", isDirectory: true)
        bgraURL = base.appendingPathComponent("bgra", isDirectory: true)
        jpegURL = base.appendingPathComponent("jpeg", isDirectory: true)
        try? FileManager.default.createDirectory(at: bgraURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: jpegURL, withIntermediateDirectories: true)
    }

    // MARK: - Read (callable from any thread)

    /// Fast synchronous check — memory only.
    func cachedImage(for id: UUID) -> UIImage? {
        memory.object(forKey: id as NSUUID)
    }

    /// Full lookup: memory → BGRA disk → JPEG disk → decode from source data.
    /// Async to prevent accidental main-thread calls — disk I/O and decoding happen on the caller's context.
    func image(for id: UUID, thumbnailData: Data?) async -> UIImage? {
        let key = id as NSUUID
        if let cached = memory.object(forKey: key) { return cached }
        if let image = loadFromDisk(id: id) {
            memory.setObject(image, forKey: key)
            return image
        }
        guard let thumbnailData, let image = UIImage(data: thumbnailData) else { return nil }
        memory.setObject(image, forKey: key)
        saveBGRA(id: id, image: image)
        return image
    }

    // MARK: - Write (callable from any thread — NSCache is thread-safe, disk writes are idempotent)

    /// Decode + cache a thumbnail.
    func preload(for id: UUID, data: Data) {
        let key = id as NSUUID
        guard memory.object(forKey: key) == nil else { return }
        if let image = loadFromDisk(id: id) {
            memory.setObject(image, forKey: key)
            return
        }
        guard let image = UIImage(data: data) else { return }
        memory.setObject(image, forKey: key)
        saveBGRA(id: id, image: image)
    }

    /// Remove a thumbnail from all layers.
    func evict(id: UUID) {
        memory.removeObject(forKey: id as NSUUID)
        try? FileManager.default.removeItem(at: bgraPath(for: id))
        try? FileManager.default.removeItem(at: jpegPath(for: id))
    }

    // MARK: - Startup warming

    /// Warm the memory cache from disk based on roll access recency.
    /// The DataStore provides relationship data; the bookkeeper owns the policy.
    /// Non-priority BGRA files are demoted to JPEG to save disk space.
    /// WARNING: Do not call from the main thread.
    func warmOnLaunch(
        cameraInfo: [(cameraID: UUID, activeRollID: UUID?, rollIDs: [UUID])],
        rollItemIDs: [UUID: [UUID]]
    ) async {
        await bookkeeper.load()
        let priorityIDs = await bookkeeper.computePriorityIDs(
            cameraInfo: cameraInfo,
            rollItemIDs: rollItemIDs
        )

        // Warm priority thumbnails from BGRA into memory
        for id in priorityIDs {
            let key = id as NSUUID
            guard memory.object(forKey: key) == nil else { continue }
            if let image = loadBGRA(url: bgraPath(for: id)) {
                memory.setObject(image, forKey: key)
            }
        }

        // Demote non-priority BGRA files to JPEG
        if let files = try? FileManager.default.contentsOfDirectory(at: bgraURL, includingPropertiesForKeys: nil) {
            for file in files {
                guard let id = UUID(uuidString: file.lastPathComponent),
                      !priorityIDs.contains(id) else { continue }
                if let image = loadBGRA(url: file) {
                    saveJPEG(id: id, image: image)
                }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Disk — BGRA (raw pixels, zero decode)

    private func bgraPath(for id: UUID) -> URL {
        bgraURL.appendingPathComponent(id.uuidString)
    }

    private func loadFromDisk(id: UUID) -> UIImage? {
        if let image = loadBGRA(url: bgraPath(for: id)) { return image }
        if let image = loadJPEG(id: id) { return image }
        return nil
    }

    private func loadBGRA(url: URL) -> UIImage? {
        guard let fileData = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let headerSize = Self.headerSize
        guard fileData.count > headerSize else { return nil }

        let header = fileData.withUnsafeBytes { $0.load(as: BitmapHeader.self) }
        let width = Int(header.width)
        let height = Int(header.height)
        let scale = CGFloat(header.scale)
        guard width > 0, height > 0, scale > 0 else { return nil }

        let pixelCount = width * height * 4
        guard fileData.count >= headerSize + pixelCount else { return nil }

        let pixelData = fileData.subdata(in: headerSize..<headerSize + pixelCount)
        guard let provider = CGDataProvider(data: pixelData as CFData),
              let cgImage = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                  space: Self.colorSpace, bitmapInfo: Self.bitmapInfo,
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { return nil }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    private func saveBGRA(id: UUID, image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: Self.colorSpace, bitmapInfo: Self.bitmapInfo.rawValue
        ), let data = context.data else { return }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var header = BitmapHeader(width: UInt16(width), height: UInt16(height), scale: UInt16(image.scale))
        var fileData = Data(bytes: &header, count: Self.headerSize)
        fileData.append(Data(bytes: data, count: width * height * 4))
        try? fileData.write(to: bgraPath(for: id))
        // Remove JPEG version if it exists (promoted back to BGRA)
        try? FileManager.default.removeItem(at: jpegPath(for: id))
    }

    // MARK: - Disk — JPEG (compact fallback, needs decode)

    private func jpegPath(for id: UUID) -> URL {
        jpegURL.appendingPathComponent(id.uuidString)
    }

    private func loadJPEG(id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: jpegPath(for: id)) else { return nil }
        return UIImage(data: data)
    }

    private func saveJPEG(id: UUID, image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: jpegPath(for: id))
    }
}
