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
        if let name = mapItem.name, !name.isEmpty {
            return name
        }
        return mapItem.address?.shortAddress
    }
}
