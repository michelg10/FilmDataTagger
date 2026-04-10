//
//  DebugReport.swift
//  Film Data Tagger
//

import Foundation
import UIKit
import AVFoundation
import CoreLocation
import CloudKit
import StoreKit

/// Generates a debug report file containing device info, app settings, and the error log.
enum DebugReport {

    /// Generate the report on a background thread and return the file URL.
    static func generate(cameras: [CameraSnapshot]) async -> URL? {
        // Gather main-thread-only values first
        let device = await MainActor.run { UIDevice.current }
        let screen = await MainActor.run { UIScreen.main }

        let batteryEnabled = await MainActor.run {
            device.isBatteryMonitoringEnabled = true
            return true
        }
        _ = batteryEnabled

        let info = await MainActor.run {
            DeviceInfo(
                model: device.model,
                modelIdentifier: modelIdentifier(),
                systemVersion: device.systemVersion,
                name: device.name,
                batteryLevel: device.batteryLevel,
                batteryState: device.batteryState,
                thermalState: ProcessInfo.processInfo.thermalState,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                processorCount: ProcessInfo.processInfo.processorCount,
                physicalMemory: ProcessInfo.processInfo.physicalMemory,
                systemUptime: ProcessInfo.processInfo.systemUptime,
                screenBounds: screen.bounds,
                screenScale: screen.nativeScale,
                locale: Locale.current,
                timeZone: TimeZone.current,
                preferredLanguages: Locale.preferredLanguages,
                contentSizeCategory: UIApplication.shared.preferredContentSizeCategory,
                isReduceMotionEnabled: UIAccessibility.isReduceMotionEnabled,
                isBoldTextEnabled: UIAccessibility.isBoldTextEnabled,
                cameraAuthStatus: AVCaptureDevice.authorizationStatus(for: .video),
                locationAuthStatus: CLLocationManager().authorizationStatus,
                locationAccuracyAuth: CLLocationManager().accuracyAuthorization,
                availableCameras: AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
                    mediaType: .video, position: .unspecified
                ).devices.map { "\($0.localizedName) (\($0.position == .front ? "front" : "back"))" }
            )
        }

        let settings = await MainActor.run { settingsDump() }
        let appInfo = await MainActor.run { appInfoDump(cameras: cameras) }
        let iCloudStatus: CKAccountStatus
        if let status = (try? await withTimeout(seconds: 5) { try await CKContainer.default().accountStatus() }) {
            iCloudStatus = status
        } else {
            errorLog("DebugReport: iCloud status timed out")
            iCloudStatus = .couldNotDetermine
        }
        let storageInfo = storageDump()

        // Build the report string
        var report = ""
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withFullTime, .withTimeZone]
        let now = iso.string(from: Date())

        report += "=== Sprokbook Debug Report ===\n"
        report += "Generated: \(now)\n\n"

        // App info
        report += "--- App ---\n"
        report += appInfo
        report += "\n"

        // Device info
        report += "--- Device ---\n"
        report += "Model: \(info.modelIdentifier) (\(info.model))\n"
        report += "iOS: \(info.systemVersion)\n"
        report += "Screen: \(Int(info.screenBounds.width))x\(Int(info.screenBounds.height)) @\(info.screenScale)x\n"
        report += "Processors: \(info.processorCount)\n"
        report += "RAM: \(info.physicalMemory / 1024 / 1024) MB\n"
        report += storageInfo
        report += "Battery: \(info.batteryLevel < 0 ? "unknown" : "\(Int(info.batteryLevel * 100))%") (\(batteryStateString(info.batteryState)))\n"
        report += "Low power mode: \(info.isLowPowerMode)\n"
        report += "Thermal state: \(thermalStateString(info.thermalState))\n"
        report += "Uptime: \(formatDuration(info.systemUptime))\n"
        report += "\n"

        // Locale
        report += "--- Locale ---\n"
        report += "Locale: \(info.locale.identifier)\n"
        report += "Region: \(info.locale.region?.identifier ?? "unknown")\n"
        report += "Time zone: \(info.timeZone.identifier) (UTC\(info.timeZone.abbreviation() ?? "?"))\n"
        report += "Languages: \(info.preferredLanguages.joined(separator: ", "))\n"
        report += "\n"

        // Accessibility
        report += "--- Accessibility ---\n"
        report += "Content size: \(info.contentSizeCategory.rawValue)\n"
        report += "Reduce motion: \(info.isReduceMotionEnabled)\n"
        report += "Bold text: \(info.isBoldTextEnabled)\n"
        report += "\n"

        // Permissions
        report += "--- Permissions ---\n"
        report += "Camera: \(authStatusString(info.cameraAuthStatus))\n"
        report += "Location: \(locationAuthString(info.locationAuthStatus))\n"
        report += "Precise location: \(info.locationAccuracyAuth == .fullAccuracy ? "yes" : "no (reduced)")\n"
        report += "iCloud: \(iCloudStatusString(iCloudStatus))\n"
        report += "Available cameras: \(info.availableCameras.joined(separator: ", "))\n"
        report += "\n"

        // Settings
        report += "--- Settings ---\n"
        report += settings
        report += "\n"

        // Distribution channel
        report += "--- Distribution ---\n"
        report += "Channel: \(await distributionChannel())\n"
        report += "\n"

        // Error log
        report += "--- Error Log ---\n"
        if let errorLog = readErrorLog(), !errorLog.isEmpty {
            report += errorLog
            if !errorLog.hasSuffix("\n") { report += "\n" }
        } else {
            report += "(empty)\n"
        }

        // Write to temp file
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "sprokbook-debug-\(formatter.string(from: Date())).log"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try report.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            errorLog("DebugReport: failed to write report: \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    private struct DeviceInfo {
        let model: String
        let modelIdentifier: String
        let systemVersion: String
        let name: String
        let batteryLevel: Float
        let batteryState: UIDevice.BatteryState
        let thermalState: ProcessInfo.ThermalState
        let isLowPowerMode: Bool
        let processorCount: Int
        let physicalMemory: UInt64
        let systemUptime: TimeInterval
        let screenBounds: CGRect
        let screenScale: CGFloat
        let locale: Locale
        let timeZone: TimeZone
        let preferredLanguages: [String]
        let contentSizeCategory: UIContentSizeCategory
        let isReduceMotionEnabled: Bool
        let isBoldTextEnabled: Bool
        let cameraAuthStatus: AVAuthorizationStatus
        let locationAuthStatus: CLAuthorizationStatus
        let locationAccuracyAuth: CLAccuracyAuthorization
        let availableCameras: [String]
    }

    private static func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "unknown"
            }
        }
    }

    @MainActor
    private static func appInfoDump(cameras: [CameraSnapshot]) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let install = AppInstallTracker.shared
        let versionTracker = AppVersionTracker.shared
        let totalRolls = cameras.reduce(0) { $0 + $1.rollCount }
        let totalExposures = cameras.reduce(0) { $0 + $1.totalExposureCount }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withFullTime, .withTimeZone]
        let lastLaunch = AppSettings.shared.lastAppLaunchDate.map { iso.string(from: $0) } ?? "unknown"

        var s = ""
        s += "Version: \(version) (build \(build))\n"
        s += "Device UUID: \(install.deviceID ?? "loading")\n"
        s += "First opened (this device): \(install.thisDeviceFirstOpened.map { iso.string(from: $0) } ?? "loading")\n"
        s += "First opened (any device): \(install.firstEverOpened.map { iso.string(from: $0) } ?? "loading")\n"
        s += "Previous build: \(versionTracker.previousBuild.map(String.init) ?? "none")\n"
        s += "Last launch: \(lastLaunch)\n"
        s += "Data: \(cameras.count) cameras, \(totalRolls) rolls, \(totalExposures) exposures\n"
        return s
    }

    @MainActor
    private static func settingsDump() -> String {
        let s = AppSettings.shared
        var d = ""
        d += "Reference photos: \(s.referencePhotosEnabled)\n"
        d += "Reference photo startup: \(s.referencePhotoStartup.rawValue)\n"
        d += "Photo quality: \(s.photoQuality.rawValue)\n"
        d += "Preferred camera: \(s.preferredCamera.rawValue)\n"
        d += "Location enabled: \(s.locationEnabled)\n"
        d += "Location accuracy: \(s.locationAccuracy.rawValue)\n"
        d += "Reduce haptics: \(s.reduceHaptics)\n"
        d += "Capture controls: \(s.captureControlsPreference.rawValue)\n"
        d += "Create roll upon finish: \(s.createRollUponFinish)\n"
        d += "Hide finish until last shot: \(s.hideFinishUntilLastShot)\n"
        d += "Pre-frames enabled: \(s.preFramesEnabled)\n"
        d += "Hold capture placeholders: \(s.holdCapturePlaceholders)\n"
        d += "Hold capture lost frames: \(s.holdCaptureLostFrames)\n"
        return d
    }

    private static func storageDump() -> String {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = attrs[.systemSize] as? Int64,
              let free = attrs[.systemFreeSize] as? Int64 else {
            return "Storage: unknown\n"
        }
        return "Storage: \(free / 1024 / 1024 / 1024) GB free / \(total / 1024 / 1024 / 1024) GB total\n"
    }

    private static func distributionChannel() async -> String {
        do {
            let result = try await AppTransaction.shared
            let appTransaction: AppTransaction
            switch result {
            case .verified(let tx), .unverified(let tx, _):
                appTransaction = tx
            }
            switch appTransaction.environment {
            case .production: return "App Store"
            case .sandbox:    return "TestFlight"
            case .xcode:      return "Xcode"
            default:          return "Unknown"
            }
        } catch {
            return "Failed: \(error)"
        }
    }

    private static func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unplugged: "unplugged"
        case .charging: "charging"
        case .full: "full"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }

    private static func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func authStatusString(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }

    private static func locationAuthString(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedWhenInUse: "when in use"
        case .authorizedAlways: "always"
        @unknown default: "unknown"
        }
    }

    private static func iCloudStatusString(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: "available"
        case .noAccount: "no account"
        case .restricted: "restricted"
        case .couldNotDetermine: "could not determine"
        case .temporarilyUnavailable: "temporarily unavailable"
        @unknown default: "unknown"
        }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
