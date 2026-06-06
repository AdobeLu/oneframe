//
//  LocationService.swift
//  OneFrame
//
//  位置服务 - 获取经纬度和地点名称用于水印
//

import CoreLocation

final class LocationService: NSObject {

    static let shared = LocationService()

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

    private(set) var currentLocation: CLLocation?
    private(set) var currentPlacemark: CLPlacemark?
    private var updateHandler: ((CLLocation?, CLPlacemark?) -> Void)?

    var locationInfoString: String {
        guard let location = currentLocation else {
            return OWLocalized("watermark.location_unknown")
        }

        let lat = String(format: "%.4f", location.coordinate.latitude)
        let lon = String(format: "%.4f", location.coordinate.longitude)

        var result = "\(lat), \(lon)"

        if let placemark = currentPlacemark {
            let parts = [placemark.locality, placemark.subLocality].compactMap { $0 }
            if !parts.isEmpty {
                result += " | " + parts.joined(separator: " ")
            }
        }

        return result
    }

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdating(handler: @escaping (CLLocation?, CLPlacemark?) -> Void) {
        self.updateHandler = handler
        locationManager.startUpdatingLocation()
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
        updateHandler = nil
    }
}

// MARK: - CLLocationManagerDelegate

@available(iOS 14.0, *)
extension LocationService: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            updateHandler?(nil, nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            self?.currentPlacemark = placemarks?.first
            DispatchQueue.main.async {
                self?.updateHandler?(location, placemarks?.first)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        updateHandler?(nil, nil)
    }
}
