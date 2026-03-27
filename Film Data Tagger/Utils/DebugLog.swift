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
