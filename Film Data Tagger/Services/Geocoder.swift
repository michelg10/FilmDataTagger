//
//  Geocoder.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import CoreLocation
import MapKit

struct GeocodingResult {
    let placeName: String?
    let cityName: String?
}

@available(iOS 26, *)
private enum Geocoder_iOS26 {
    @concurrent static func geocode(_ location: CLLocation) async -> GeocodingResult {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return GeocodingResult(placeName: nil, cityName: nil)
        }
        do {
            let mapItems = try await request.mapItems
            guard let mapItem = mapItems.first else { return GeocodingResult(placeName: nil, cityName: nil) }
            let placeName: String? = if let name = mapItem.name, !name.isEmpty {
                name
            } else {
                mapItem.address?.shortAddress
            }
            let cityName = mapItem.addressRepresentations?.cityName?.nilIfEmpty
            return GeocodingResult(placeName: placeName, cityName: cityName)
        } catch {
            errorLog("Geocoding error: \(error.localizedDescription)")
            return GeocodingResult(placeName: nil, cityName: nil)
        }
    }
}

private enum Geocoder_Legacy {
    @concurrent static func geocode(_ location: CLLocation) async -> GeocodingResult {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return GeocodingResult(placeName: nil, cityName: nil) }
            let placeName: String? = if let name = placemark.name, !name.isEmpty {
                name
            } else {
                [placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                    .nilIfEmpty
            }
            let cityName = placemark.locality?.nilIfEmpty
            return GeocodingResult(placeName: placeName, cityName: cityName)
        } catch {
            errorLog("Geocoding error: \(error.localizedDescription)")
            return GeocodingResult(placeName: nil, cityName: nil)
        }
    }
}

// MARK: - Cache

/// Deduplicates in-flight geocoding requests and caches resolved results for the app session.
/// Keyed by exact (latitude, longitude) — callers sharing the same CLLocation get the same result.
private actor GeocodingCache {
    private enum Entry {
        case inflight(Task<GeocodingResult, Never>)
        case resolved(GeocodingResult)
    }

    private struct Key: Hashable {
        let latitude: Double
        let longitude: Double
    }

    private var entries: [Key: Entry] = [:]

    func geocode(_ location: CLLocation) async -> GeocodingResult {
        let key = Key(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        switch entries[key] {
        case .inflight(let task):
            return await task.value
        case .resolved(let result):
            return result
        case nil:
            break
        }
        let task = Task { await Geocoder.performGeocode(location) }
        entries[key] = .inflight(task)
        let result = await task.value
        if result.placeName != nil || result.cityName != nil {
            entries[key] = .resolved(result)
        } else {
            entries[key] = nil  // failed — allow retry
        }
        return result
    }
}

// MARK: - Public API

enum Geocoder {
    private static let cache = GeocodingCache()

    /// Geocode a location, deduplicating in-flight requests and caching results.
    @concurrent static func geocode(_ location: CLLocation) async -> GeocodingResult {
        await cache.geocode(location)
    }

    /// Geocode a batch of locations sequentially with rate-limiting delays.
    /// Shared by all backfill paths to avoid concurrent CLGeocoder requests.
    @concurrent static func geocodeBatch(_ items: [(UUID, CLLocation)]) async -> [(UUID, GeocodingResult)] {
        var results: [(UUID, GeocodingResult)] = []
        for (id, location) in items {
            guard !Task.isCancelled else { break }
            let result = await geocode(location)
            if result.placeName != nil || result.cityName != nil {
                results.append((id, result))
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return results
    }

    /// Raw geocode — no caching. Called by the cache actor.
    fileprivate static func performGeocode(_ location: CLLocation) async -> GeocodingResult {
        if #available(iOS 26, *) {
            return await Geocoder_iOS26.geocode(location)
        } else {
            return await Geocoder_Legacy.geocode(location)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
