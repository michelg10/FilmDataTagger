//
//  DebugLog.swift
//  Film Data Tagger
//

import Foundation

#if DEBUG
private nonisolated enum DebugLogConfig {
    static let queue = DispatchQueue(label: "debugLog", qos: .utility)
    static let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("debug.log")
    }()
}

/// Append a timestamped message to the debug log file.
/// Only available in DEBUG builds. The log file lives in the app's Documents directory.
nonisolated func debugLog(_ message: String, file: String = #fileID, line: Int = #line) {
    let timestamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withFullTime, .withFractionalSeconds])
    let entry = "[\(timestamp)] \(file):\(line) \(message)\n"
    print("[debugLog] \(file):\(line) \(message)")
    DebugLogConfig.queue.async {
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: DebugLogConfig.url.path) {
                if let handle = try? FileHandle(forWritingTo: DebugLogConfig.url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: DebugLogConfig.url)
            }
        }
    }
}

/// Returns the contents of the debug log file, or nil if it doesn't exist.
nonisolated func readDebugLog() -> String? {
    try? String(contentsOf: DebugLogConfig.url, encoding: .utf8)
}

/// Clears the debug log file.
nonisolated func clearDebugLog() {
    DebugLogConfig.queue.async {
        try? FileManager.default.removeItem(at: DebugLogConfig.url)
    }
}
#else
@inline(__always)
nonisolated func debugLog(_ message: String, file: String = #fileID, line: Int = #line) {}
#endif

// MARK: - Error log (always active, persists to disk in all builds)

private nonisolated enum ErrorLogConfig {
    static let queue = DispatchQueue(label: "errorLog", qos: .utility)
    static let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("error.log")
    }()
    static let maxSize = 32 * 1024 * 1024 // 32 MB
}

/// Log an error to a persistent file. Always active, including in release builds.
/// Use for unexpected failures: catch blocks, guard-else fallbacks, nil coalescing fallbacks.
nonisolated func errorLog(_ message: String, file: String = #fileID, line: Int = #line) {
    #if DEBUG
    debugLog("ERROR: \(message)", file: file, line: line)
    #endif
    let timestamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withFullTime, .withFractionalSeconds])
    let entry = "[\(timestamp)] \(file):\(line) \(message)\n"
    ErrorLogConfig.queue.async {
        guard let data = entry.data(using: .utf8) else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: ErrorLogConfig.url.path) {
            // Trim oldest half if over max size
            if let attrs = try? fm.attributesOfItem(atPath: ErrorLogConfig.url.path),
               let size = attrs[.size] as? Int, size > ErrorLogConfig.maxSize,
               let existing = try? String(contentsOf: ErrorLogConfig.url, encoding: .utf8) {
                let lines = existing.components(separatedBy: "\n")
                let kept = lines.suffix(lines.count / 2).joined(separator: "\n")
                try? kept.data(using: .utf8)?.write(to: ErrorLogConfig.url)
            }
            if let handle = try? FileHandle(forWritingTo: ErrorLogConfig.url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: ErrorLogConfig.url)
        }
    }
}

/// Returns the contents of the error log file, or nil if it doesn't exist.
nonisolated func readErrorLog() -> String? {
    try? String(contentsOf: ErrorLogConfig.url, encoding: .utf8)
}

/// Clears the error log file.
nonisolated func clearErrorLog() {
    ErrorLogConfig.queue.async {
        try? FileManager.default.removeItem(at: ErrorLogConfig.url)
    }
}
