import CoreLocation
import Foundation

/// Port of LocationHelper: caches the last area name + coordinates, defaults to Bangalore.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []

    private(set) var areaName: String
    private(set) var hasCachedLocation: Bool

    var lat: Double { hasCachedLocation ? defaults.double(forKey: "loc_lat") : 12.9716 }
    var lng: Double { hasCachedLocation ? defaults.double(forKey: "loc_lng") : 77.5946 }

    private override init() {
        areaName = defaults.string(forKey: "loc_area") ?? ""
        hasCachedLocation = !(defaults.string(forKey: "loc_area") ?? "").isEmpty
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var headerText: String { areaName.isEmpty ? "Bangalore" : areaName }

    func clearCache() {
        defaults.removeObject(forKey: "loc_area")
        defaults.removeObject(forKey: "loc_lat")
        defaults.removeObject(forKey: "loc_lng")
        hasCachedLocation = false
        areaName = ""
    }

    /// Returns cached coordinates if present, otherwise asks for permission + a fresh fix.
    /// Returns nil when location is unavailable or denied.
    @discardableResult
    func current() async -> (lat: Double, lng: Double)? {
        if hasCachedLocation { return (lat, lng) }
        guard let loc = await requestLocation() else {
            if areaName.isEmpty { areaName = "Bangalore" }
            return nil
        }
        let area = await reverseGeocode(loc) ?? "Bangalore"
        defaults.set(area, forKey: "loc_area")
        defaults.set(loc.coordinate.latitude, forKey: "loc_lat")
        defaults.set(loc.coordinate.longitude, forKey: "loc_lng")
        areaName = area
        hasCachedLocation = true
        return (loc.coordinate.latitude, loc.coordinate.longitude)
    }

    private func requestLocation() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted: return nil
        default: break
        }
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            if waiters.count > 1 { return }
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ loc: CLLocation?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: loc) }
    }

    private func reverseGeocode(_ loc: CLLocation) async -> String? {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(loc).first else { return nil }
        return mark.subLocality ?? mark.locality
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if !self.waiters.isEmpty { manager.requestLocation() }
            case .denied, .restricted:
                self.finish(nil)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.finish(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
