//
//  Geocoder.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import CoreLocation
import MapKit

@available(iOS 26, *)
private enum Geocoder_iOS26 {
    static func placeName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }
        do {
            let mapItems = try await request.mapItems
            guard let mapItem = mapItems.first else { return nil }
            if let name = mapItem.name, !name.isEmpty {
                return name
            }
            return mapItem.address?.shortAddress
        } catch {
            print("Geocoding error: \(error.localizedDescription)")
            return nil
        }
    }
}

private enum Geocoder_Legacy {
    static func placeName(for location: CLLocation) async -> String? {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            if let name = placemark.name, !name.isEmpty {
                return name
            }
            return [placemark.locality, placemark.administrativeArea]
                .compactMap { $0 }
                .joined(separator: ", ")
                .nilIfEmpty
        } catch {
            print("Geocoding error: \(error.localizedDescription)")
            return nil
        }
    }
}

enum Geocoder {
    static func placeName(for location: CLLocation) async -> String? {
        if #available(iOS 26, *) {
            return await Geocoder_iOS26.placeName(for: location)
        } else {
            return await Geocoder_Legacy.placeName(for: location)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
