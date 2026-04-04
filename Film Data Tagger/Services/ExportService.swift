//
//  ExportService.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/8/26.
//

import Foundation
import SwiftData

/// Ordered key-value pairs for JSON serialization with guaranteed key order.
private typealias JObj = [(String, Any)]

enum ExportError: Error {
    case encodingFailed
}

nonisolated struct ExportService {
    private static let exportVersion = 1

    // MARK: - JSON

    @concurrent static func exportJSON(context: ModelContext) async throws -> URL {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cameras = try context.fetch(FetchDescriptor<Camera>())
        let rolls = try context.fetch(FetchDescriptor<Roll>())
        let exposures = try context.fetch(FetchDescriptor<LogItem>())

        let root: JObj = [
            ("metadata", [
                ("exportVersion", exportVersion),
                ("appVersion", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"),
                ("buildNumber", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"),
                ("exportDate", iso8601.string(from: Date())),
                ("counts", [
                    ("cameras", cameras.count),
                    ("rolls", rolls.count),
                    ("exposures", exposures.count),
                ] as JObj),
            ] as JObj),
            ("cameras", cameras.map { jsonCamera($0, iso8601: iso8601) }),
            ("rolls", rolls.map { jsonRoll($0, iso8601: iso8601) }),
            ("exposures", exposures.map { jsonExposure($0, iso8601: iso8601) }),
        ]

        let json = serializeJSON(root, indent: 0)
        let url = tempURL(ext: "json")
        guard let data = json.data(using: .utf8) else {
            errorLog("exportJSON: UTF-8 encoding failed")
            throw ExportError.encodingFailed
        }
        try data.write(to: url)
        return url
    }

    private static func jsonCamera(_ c: Camera, iso8601: ISO8601DateFormatter) -> JObj {
        [
            ("id", c.id.uuidString),
            ("name", c.name),
            ("createdAt", iso8601.string(from: c.createdAt)),
            ("listOrder", c.listOrder),
        ]
    }

    private static func jsonRoll(_ r: Roll, iso8601: ISO8601DateFormatter) -> JObj {
        var obj: JObj = [
            ("id", r.id.uuidString),
        ]
        if let cameraID = r.camera?.id { obj.append(("cameraID", cameraID.uuidString)) }
        obj.append(("filmStock", r.filmStock))
        obj.append(("capacity", r.capacity))
        obj.append(("extraExposures", r.extraExposures))
        obj.append(("isActive", r.isActive))
        obj.append(("createdAt", iso8601.string(from: r.createdAt)))
        if let date = (r.logItems ?? []).filter(\.hasRealCreatedAt).map(\.createdAt).max() {
            obj.append(("lastExposureDate", iso8601.string(from: date)))
        }
        return obj
    }

    private static func jsonExposure(_ e: LogItem, iso8601: ISO8601DateFormatter) -> JObj {
        var obj: JObj = [
            ("id", e.id.uuidString),
        ]
        if let rollID = e.roll?.id { obj.append(("rollID", rollID.uuidString)) }
        obj.append(("createdAt", iso8601.string(from: e.createdAt)))
        obj.append(("hasRealCreatedAt", e.hasRealCreatedAt))
        obj.append(("isPlaceholder", e.isPlaceholder))
        if let notes = e.notes { obj.append(("notes", notes)) }
        if let lat = e.latitude { obj.append(("latitude", lat)) }
        if let lon = e.longitude { obj.append(("longitude", lon)) }
        if let alt = e.altitude { obj.append(("altitude", alt)) }
        if let h = e.horizontalAccuracy { obj.append(("horizontalAccuracy", h)) }
        if let v = e.verticalAccuracy { obj.append(("verticalAccuracy", v)) }
        if let course = e.course { obj.append(("course", course)) }
        if let speed = e.speed { obj.append(("speed", speed)) }
        if let ts = e.locationTimestamp { obj.append(("locationTimestamp", iso8601.string(from: ts))) }
        if let place = e.placeName { obj.append(("placeName", place)) }
        if let city = e.cityName { obj.append(("cityName", city)) }
        if let tz = e.timeZoneIdentifier { obj.append(("timeZoneIdentifier", tz)) }
        if let source = e.source { obj.append(("source", source)) }
        return obj
    }

    // MARK: - CSV

    @concurrent static func exportCSV(context: ModelContext) async throws -> URL {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let exposures = try context.fetch(FetchDescriptor<LogItem>())

        var csv = "id,rollID,cameraID,cameraName,filmStock,createdAt,isPlaceholder,notes,"
        csv += "latitude,longitude,altitude,horizontalAccuracy,verticalAccuracy,"
        csv += "course,speed,locationTimestamp,placeName,cityName,timeZoneIdentifier,source\n"

        for e in exposures {
            var row = [String]()
            row.append(e.id.uuidString)
            row.append(e.roll?.id.uuidString ?? "")
            row.append(e.roll?.camera?.id.uuidString ?? "")
            row.append(csvEscape(e.roll?.camera?.name ?? ""))
            row.append(csvEscape(e.roll?.filmStock ?? ""))
            row.append(iso8601.string(from: e.createdAt))
            row.append(e.isPlaceholder ? "true" : "false")
            row.append(csvEscape(e.notes ?? ""))
            row.append(e.latitude.map { "\($0)" } ?? "")
            row.append(e.longitude.map { "\($0)" } ?? "")
            row.append(e.altitude.map { "\($0)" } ?? "")
            row.append(e.horizontalAccuracy.map { "\($0)" } ?? "")
            row.append(e.verticalAccuracy.map { "\($0)" } ?? "")
            row.append(e.course.map { "\($0)" } ?? "")
            row.append(e.speed.map { "\($0)" } ?? "")
            row.append(e.locationTimestamp.map { iso8601.string(from: $0) } ?? "")
            row.append(csvEscape(e.placeName ?? ""))
            row.append(csvEscape(e.cityName ?? ""))
            row.append(csvEscape(e.timeZoneIdentifier ?? ""))
            row.append(csvEscape(e.source ?? ""))
            csv += row.joined(separator: ",") + "\n"
        }

        let url = tempURL(ext: "csv")
        guard let data = csv.data(using: .utf8) else {
            errorLog("exportCSV: UTF-8 encoding failed")
            throw ExportError.encodingFailed
        }
        // UTF-8 BOM so Excel correctly interprets non-ASCII characters
        let bom = Data([0xEF, 0xBB, 0xBF])
        try (bom + data).write(to: url)
        return url
    }

    // MARK: - JSON Serializer

    private static func serializeJSON(_ value: Any, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)

        if let obj = value as? JObj, !obj.isEmpty {
            let entries = obj.map { key, val in
                "\(innerPad)\(escapeString(key)): \(serializeJSON(val, indent: indent + 1))"
            }
            return "{\n\(entries.joined(separator: ",\n"))\n\(pad)}"
        }
        if let array = value as? [Any] {
            if array.isEmpty { return "[]" }
            let items = array.map { "\(innerPad)\(serializeJSON($0, indent: indent + 1))" }
            return "[\n\(items.joined(separator: ",\n"))\n\(pad)]"
        }
        if let string = value as? String {
            return escapeString(string)
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let int = value as? Int {
            return "\(int)"
        }
        if let double = value as? Double {
            if double.isNaN || double.isInfinite { return "null" }
            return "\(double)"
        }
        return "null"
    }

    private static func escapeString(_ s: String) -> String {
        var result = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if ch.value < 0x20 {
                    result += String(format: "\\u%04X", ch.value)
                } else {
                    result += String(ch)
                }
            }
        }
        result += "\""
        return result
    }

    // MARK: - Helpers

    private static func csvEscape(_ value: String) -> String {
        // Prevent spreadsheet formula injection — prefix before quoting
        var sanitized = value
        if let first = sanitized.first, "=+−-@|".contains(first) {
            sanitized = "'" + sanitized
        }
        if sanitized.contains(",") || sanitized.contains("\"") || sanitized.contains("\n") || sanitized.contains("\r") || sanitized.contains("\t") {
            return "\"" + sanitized.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return sanitized
    }

    // Same-day exports intentionally overwrite — the file is temporary and
    // only needs to live long enough for the share sheet to consume it.
    private static func tempURL(ext: String) -> URL {
        let now = Date()
        let cal = Calendar.current
        let date = String(format: "%04d-%02d-%02d",
                          cal.component(.year, from: now),
                          cal.component(.month, from: now),
                          cal.component(.day, from: now))
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("sprokbook-export-\(date).\(ext)")
    }
}
