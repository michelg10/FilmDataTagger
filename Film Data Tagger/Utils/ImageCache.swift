//
//  ImageCache.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import UIKit

/// Header for raw bitmap thumbnail files.
private struct BitmapHeader {
    var version: UInt16
    var width: UInt16
    var height: UInt16
    var scale: UInt16

    static let currentVersion: UInt16 = 1
}

/// Tracks when each roll was last viewed. Persisted as a plist.
/// Owns the warming policy: given relationship data from the DataStore,
/// decides which thumbnails to warm into BGRA memory.
actor CacheBookkeeper {
    private var rollAccessDates: [UUID: Date] = [:]
    private var isDirty = false
    private var saveTask: Task<Void, Never>?

    private static let priorityCameraCount = 8
    private static let lruRollBudget = 32

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
        scheduleSave()
    }

    /// Remove access dates for rolls that no longer exist.
    func purgeStaleEntries(existingRollIDs: Set<UUID>) {
        let before = rollAccessDates.count
        rollAccessDates = rollAccessDates.filter { existingRollIDs.contains($0.key) }
        if rollAccessDates.count != before { scheduleSave() }
    }

    /// Determine which rolls should be warmed, given camera/roll metadata.
    /// Returns the set of roll IDs whose items should be fetched and warmed.
    ///
    /// Policy:
    /// 1. Top 8 most recently accessed cameras → their active rolls.
    /// 2. Rolls sorted by last accessed → up to 32 rolls.
    /// 3. Union = rolls to warm.
    func rollsToWarm(
        cameraInfo: [(cameraID: UUID, activeRollID: UUID?, rollIDs: [UUID])]
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
            result.insert(activeRollID)
        }

        // 2. LRU: rolls by recency, up to 32 rolls total
        let rollsByAccess = rollAccessDates.sorted { $0.value > $1.value }
        for (rollID, _) in rollsByAccess {
            result.insert(rollID)
            if result.count >= Self.lruRollBudget { break }
        }

        return result
    }

    private func scheduleSave() {
        isDirty = true
        saveTask?.cancel()
        saveTask = Task(priority: .background) {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    private func flush() {
        guard isDirty else { return }
        isDirty = false
        guard let data = try? PropertyListEncoder().encode(rollAccessDates) else {
            debugLog("CacheBookkeeper: failed to encode rollAccessDates")
            return
        }
        try? data.write(to: Self.file, options: .atomic)
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
/// relationship data (cameras, rolls) and the bookkeeper decides which rolls
/// to warm. The DataStore then fetches item IDs only for those rolls and passes
/// them to `warmOnLaunch(priorityIDs:)`. Non-priority BGRA files are demoted to JPEG.
///
/// Thread safety: NSCache is thread-safe. Disk I/O is idempotent per thumbnail.
/// Roll access tracking is fire-and-forget to the CacheBookkeeper actor.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private nonisolated(unsafe) let memory = NSCache<NSUUID, UIImage>()
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
        discardCacheIfVersionMismatch()
    }

    /// If the on-disk format version doesn't match, wipe everything.
    /// Thumbnails will be re-cached from SwiftData on next access.
    private func discardCacheIfVersionMismatch() {
        // Check any existing BGRA file for the version header
        guard let files = try? FileManager.default.contentsOfDirectory(at: bgraURL, includingPropertiesForKeys: nil),
              let firstFile = files.first,
              let data = try? Data(contentsOf: firstFile, options: .mappedIfSafe),
              data.count >= Self.headerSize
        else { return }

        let header = data.withUnsafeBytes { $0.load(as: BitmapHeader.self) }
        if header.version != BitmapHeader.currentVersion {
            // Wipe both directories
            try? FileManager.default.removeItem(at: bgraURL)
            try? FileManager.default.removeItem(at: jpegURL)
            try? FileManager.default.createDirectory(at: bgraURL, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: jpegURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Read (callable from any thread)

    /// Fast synchronous check — memory only.
    func cachedImage(for id: UUID) -> UIImage? {
        memory.object(forKey: id as NSUUID)
    }

    // MARK: - Write (callable from any thread — NSCache is thread-safe, disk writes are idempotent)

    /// Decode + cache a thumbnail. Promotes JPEG→BGRA if the item was previously demoted.
    /// Async to prevent accidental main-thread calls.
    @concurrent func preload(for id: UUID, data: Data) async {
        let key = id as NSUUID
        guard memory.object(forKey: key) == nil else { return }
        // Check BGRA first — already in the fast tier
        if let image = loadBGRA(url: bgraPath(for: id)) {
            memory.setObject(image, forKey: key)
            return
        }
        // JPEG hit — promote back to BGRA
        if let image = loadJPEG(id: id) {
            memory.setObject(image, forKey: key)
            saveBGRA(id: id, image: image)
            return
        }
        // Full miss — decode from source data
        guard let image = UIImage(data: data) else { return }
        memory.setObject(image, forKey: key)
        saveBGRA(id: id, image: image)
    }

    /// Decode + cache a single thumbnail and return it.
    /// Use for cache-miss recovery when the ViewModel needs an image back.
    /// Async to prevent accidental main-thread calls.
    @concurrent func decodeAndCache(for id: UUID, data: Data) async -> UIImage? {
        let key = id as NSUUID
        if let cached = memory.object(forKey: key) { return cached }
        if let image = loadBGRA(url: bgraPath(for: id)) {
            memory.setObject(image, forKey: key)
            return image
        }
        if let image = loadJPEG(id: id) {
            memory.setObject(image, forKey: key)
            saveBGRA(id: id, image: image)
            return image
        }
        guard let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key)
        saveBGRA(id: id, image: image)
        return image
    }

    /// Remove a thumbnail from all layers.
    func evict(id: UUID) {
        memory.removeObject(forKey: id as NSUUID)
        try? FileManager.default.removeItem(at: bgraPath(for: id))
        try? FileManager.default.removeItem(at: jpegPath(for: id))
    }

    // MARK: - Startup warming

    private static let warmItemLimit = 768

    /// Warm the memory cache from disk for the given priority thumbnails (capped at 768).
    /// Non-priority BGRA files are demoted to JPEG to save disk space.
    /// WARNING: Do not call from the main thread.
    @concurrent func warmOnLaunch(priorityIDs: Set<UUID>) async {
        // Warm priority thumbnails from disk into memory (BGRA first, then JPEG with promotion)
        var count = 0
        for id in priorityIDs {
            guard count < Self.warmItemLimit else { break }
            let key = id as NSUUID
            guard memory.object(forKey: key) == nil else { continue }
            if let image = loadBGRA(url: bgraPath(for: id)) {
                memory.setObject(image, forKey: key)
            } else if let image = loadJPEG(id: id) {
                memory.setObject(image, forKey: key)
                saveBGRA(id: id, image: image) // promote back to fast tier
            }
            count += 1
            if count % 50 == 0 { await Task.yield() }
        }

        // Demote non-priority BGRA files to JPEG
        if let files = try? FileManager.default.contentsOfDirectory(at: bgraURL, includingPropertiesForKeys: nil) {
            count = 0
            for file in files {
                guard let id = UUID(uuidString: file.lastPathComponent),
                      !priorityIDs.contains(id) else { continue }
                if let image = loadBGRA(url: file) {
                    if saveJPEG(id: id, image: image) {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
                count += 1
                if count % 50 == 0 { await Task.yield() }
            }
        }
    }

    // MARK: - Disk — BGRA (raw pixels, zero decode)

    private func bgraPath(for id: UUID) -> URL {
        bgraURL.appendingPathComponent(id.uuidString)
    }

    /// Load from disk (BGRA then JPEG), cache in memory, and return.
    /// Use when the source Data is not available (snapshot world — no thumbnailData on the snapshot).
    @concurrent func loadFromDiskAndCache(for id: UUID) async -> UIImage? {
        let key = id as NSUUID
        if let cached = memory.object(forKey: key) { return cached }
        if let image = loadBGRA(url: bgraPath(for: id)) {
            memory.setObject(image, forKey: key)
            return image
        }
        if let image = loadJPEG(id: id) {
            memory.setObject(image, forKey: key)
            saveBGRA(id: id, image: image)
            return image
        }
        return nil
    }

    private func loadBGRA(url: URL) -> UIImage? {
        guard let fileData = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let headerSize = Self.headerSize
        guard fileData.count > headerSize else { return nil }

        let header = fileData.withUnsafeBytes { $0.load(as: BitmapHeader.self) }
        guard header.version == BitmapHeader.currentVersion else { return nil }
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

        var header = BitmapHeader(version: BitmapHeader.currentVersion, width: UInt16(width), height: UInt16(height), scale: UInt16(image.scale))
        var fileData = Data(bytes: &header, count: Self.headerSize)
        fileData.append(Data(bytes: data, count: width * height * 4))
        do {
            try fileData.write(to: bgraPath(for: id), options: .atomic)
            // Only remove JPEG after BGRA write confirmed
            try? FileManager.default.removeItem(at: jpegPath(for: id))
        } catch {
            debugLog("saveBGRA(\(id)): write failed: \(error)")
        }
    }

    // MARK: - Disk — JPEG (compact fallback, needs decode)

    private func jpegPath(for id: UUID) -> URL {
        jpegURL.appendingPathComponent(id.uuidString)
    }

    private func loadJPEG(id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: jpegPath(for: id)) else { return nil }
        return UIImage(data: data)
    }

    @discardableResult
    private func saveJPEG(id: UUID, image: UIImage) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return false }
        do {
            try data.write(to: jpegPath(for: id), options: .atomic)
            return true
        } catch {
            debugLog("saveJPEG(\(id)): write failed: \(error)")
            return false
        }
    }
}
