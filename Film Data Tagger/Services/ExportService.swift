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

nonisolated struct ExportService {
    private static let exportVersion = 1

    // MARK: - JSON

    static func exportJSON(context: ModelContext) throws -> URL {
        let iso8601 = ISO8601DateFormatter()
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
        try json.data(using: .utf8)?.write(to: url)
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
        if let cameraId = r.camera?.id { obj.append(("cameraId", cameraId.uuidString)) }
        obj.append(("filmStock", r.filmStock))
        obj.append(("capacity", r.capacity))
        obj.append(("extraExposures", r.extraExposures))
        obj.append(("isActive", r.isActive))
        obj.append(("createdAt", iso8601.string(from: r.createdAt)))
        if let date = r.lastExposureDate { obj.append(("lastExposureDate", iso8601.string(from: date))) }
        return obj
    }

    private static func jsonExposure(_ e: LogItem, iso8601: ISO8601DateFormatter) -> JObj {
        var obj: JObj = [
            ("id", e.id.uuidString),
        ]
        if let rollId = e.roll?.id { obj.append(("rollId", rollId.uuidString)) }
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
        if let tz = e.timeZoneIdentifier { obj.append(("timeZoneIdentifier", tz)) }
        return obj
    }

    // MARK: - CSV

    static func exportCSV(context: ModelContext) throws -> URL {
        let iso8601 = ISO8601DateFormatter()
        let exposures = try context.fetch(FetchDescriptor<LogItem>())

        var csv = "id,rollId,cameraId,cameraName,filmStock,createdAt,isPlaceholder,notes,"
        csv += "latitude,longitude,altitude,horizontalAccuracy,verticalAccuracy,"
        csv += "course,speed,locationTimestamp,placeName,timeZoneIdentifier\n"

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
            row.append(e.timeZoneIdentifier ?? "")
            csv += row.joined(separator: ",") + "\n"
        }

        let url = tempURL(ext: "csv")
        try csv.data(using: .utf8)?.write(to: url)
        return url
    }

    // MARK: - JSON Serializer

    private static func serializeJSON(_ value: Any, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)

        if let obj = value as? JObj {
            if obj.isEmpty { return "{}" }
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
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // Same-day exports intentionally overwrite — the file is temporary and
    // only needs to live long enough for the share sheet to consume it.
    private static func tempURL(ext: String) -> URL {
        let date = dateFormatter.string(from: Date())
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("sprokbook-export-\(date).\(ext)")
    }
}
