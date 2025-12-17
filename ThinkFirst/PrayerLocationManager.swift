import Combine
import CoreLocation
import Foundation

@MainActor
final class PrayerLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = PrayerLocationManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastKnownCoordinate: CLLocationCoordinate2D?
    @Published private(set) var lastErrorDescription: String?

    private let manager: CLLocationManager

    private override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestAccessAndLocation() {
        lastErrorDescription = nil
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .notDetermined:
            // On macOS, requestAlwaysAuthorization is the supported prompt flow.
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined, .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastKnownCoordinate = locations.last?.coordinate
        lastErrorDescription = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastErrorDescription = error.localizedDescription
    }
}
