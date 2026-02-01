//
//  Geocoder.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import CoreLocation
import MapKit

enum Geocoder {
    /// Reverse geocode a location to a human-readable place name
    static func placeName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }

        do {
            let mapItems = try await request.mapItems
            guard let mapItem = mapItems.first else { return nil }
            return formatMapItem(mapItem)
        } catch {
            print("Geocoding error: \(error.localizedDescription)")
            return nil
        }
    }

    private static func formatMapItem(_ mapItem: MKMapItem) -> String? {
        // Try point of interest name first (e.g., "Dockweiler State Beach")
        if let name = mapItem.name, !name.isEmpty, !isStreetAddress(name) {
            return name
        }

        // Last resort: full address without region
        return mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: false)
    }

    /// Check if a string looks like a street address (e.g., "123 Main St")
    private static func isStreetAddress(_ string: String) -> Bool {
        guard let first = string.first else { return false }
        return first.isNumber
    }
}
