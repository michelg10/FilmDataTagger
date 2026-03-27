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
    static func geocode(_ location: CLLocation) async -> GeocodingResult {
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
            debugLog("Geocoding error: \(error.localizedDescription)")
            return GeocodingResult(placeName: nil, cityName: nil)
        }
    }
}

private enum Geocoder_Legacy {
    static func geocode(_ location: CLLocation) async -> GeocodingResult {
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
            debugLog("Geocoding error: \(error.localizedDescription)")
            return GeocodingResult(placeName: nil, cityName: nil)
        }
    }
}

enum Geocoder {
    static func geocode(_ location: CLLocation) async -> GeocodingResult {
        if #available(iOS 26, *) {
            return await Geocoder_iOS26.geocode(location)
        } else {
            return await Geocoder_Legacy.geocode(location)
        }
    }

    /// Geocode a batch of locations sequentially with rate-limiting delays.
    /// Shared by all backfill paths to avoid concurrent CLGeocoder requests.
    static func geocodeBatch(_ items: [(UUID, CLLocation)]) async -> [(UUID, GeocodingResult)] {
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
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
