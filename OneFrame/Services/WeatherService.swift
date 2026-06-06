//
//  WeatherService.swift
//  OneFrame
//
//  天气信息服务 - 获取当前天气用于水印
//

import Foundation

final class WeatherService {

    static let shared = WeatherService()

    private(set) var currentWeather: String?

    /// 获取天气信息 (简化版，使用 Open-Meteo 免费 API)
    func fetchWeather(latitude: Double, longitude: Double, completion: @escaping (String?) -> Void) {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code"

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let current = json["current"] as? [String: Any] {
                    let temp = current["temperature_2m"] as? Double ?? 0
                    let code = current["weather_code"] as? Int ?? 0
                    let weather = self?.weatherDescription(for: code) ?? "Unknown"
                    let result = "\(weather) \(Int(temp))°C"
                    self?.currentWeather = result
                    DispatchQueue.main.async { completion(result) }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }

    private func weatherDescription(for code: Int) -> String {
        switch code {
        case 0: return "☀️"
        case 1, 2: return "🌤"
        case 3: return "☁️"
        case 45, 48: return "🌫"
        case 51, 53, 55: return "🌦"
        case 61, 63, 65: return "🌧"
        case 71, 73, 75: return "🌨"
        case 80, 81, 82: return "⛈"
        case 95, 96, 99: return "⚡️"
        default: return "🌈"
        }
    }
}
