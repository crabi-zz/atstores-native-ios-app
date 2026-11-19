import CoreLocation

/// One-shot location + reverse geocoding for the store form (FusedLocationProvider + Geocoder on Android).
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    struct Place {
        var latitude: Double
        var longitude: Double
        var address: String?
        var city: String?
        var state: String?
        var pincode: String?
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Asks for permission when needed; returns nil when denied or unavailable.
    func currentPlace() async -> Place? {
        guard let loc = await currentLocation() else { return nil }
        var place = Place(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        if let mark = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
            let parts = [mark.subThoroughfare, mark.thoroughfare, mark.subLocality, mark.locality].compactMap { $0 }
            place.address = parts.isEmpty ? mark.name : parts.joined(separator: ", ")
            place.city = mark.locality ?? mark.subAdministrativeArea
            place.state = mark.administrativeArea
            place.pincode = mark.postalCode
        }
        return place
    }

    private func currentLocation() async -> CLLocation? {
        if continuation != nil { return nil }
        switch manager.authorizationStatus {
        case .denied, .restricted: return nil
        default: break
        }
        return await withCheckedContinuation { cont in
            continuation = cont
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ loc: CLLocation?) {
        continuation?.resume(returning: loc)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: finish(nil)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in finish(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(nil) }
    }
}
