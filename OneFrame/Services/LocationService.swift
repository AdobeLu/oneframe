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

    /// 经纬度带 N/S E/W 后缀 (如 "31.2304° N, 121.4737° E")
    var coordinateString: String {
        guard let location = currentLocation else { return "" }
        let lat = abs(location.coordinate.latitude)
        let lon = abs(location.coordinate.longitude)
        let latDir = location.coordinate.latitude >= 0 ? "N" : "S"
        let lonDir = location.coordinate.longitude >= 0 ? "E" : "W"
        return String(format: "%.4f° %@, %.4f° %@", lat, latDir, lon, lonDir)
    }

    /// 城市名称 (如 "上海")
    var cityName: String {
        guard let placemark = currentPlacemark else { return "" }
        return [placemark.locality, placemark.subLocality].compactMap { $0 }.joined(separator: " ")
    }

    var locationInfoString: String {
        guard let location = currentLocation else {
            return OWLocalized("watermark.location_unknown")
        }

        let lat = String(format: "%.4f", location.coordinate.latitude)
        let lon = String(format: "%.4f", location.coordinate.longitude)

        var result = "\(lat), \(lon)"

        let city = cityName
        if !city.isEmpty {
            result += " | " + city
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
