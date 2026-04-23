import Foundation
import CoreLocation

struct WeatherCondition {
    let temperature: Double
    let feelsLike: Double
    let weatherCode: Int
    let windspeed: Double
    let city: String
    let updatedAt: Date

    var description: String {
        switch weatherCode {
        case 0:       return "Clear"
        case 1, 2, 3: return "Cloudy"
        case 45, 48:  return "Foggy"
        case 51...55: return "Drizzle"
        case 61...65: return "Rain"
        case 71...75: return "Snow"
        case 80...82: return "Showers"
        case 95:      return "Storm"
        default:      return "Unknown"
        }
    }

    var symbolName: String {
        switch weatherCode {
        case 0:       return "sun.max.fill"
        case 1, 2:    return "cloud.sun.fill"
        case 3:       return "cloud.fill"
        case 45, 48:  return "cloud.fog.fill"
        case 51...55: return "cloud.drizzle.fill"
        case 61...65: return "cloud.rain.fill"
        case 71...75: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95:      return "cloud.bolt.rain.fill"
        default:      return "thermometer.medium"
        }
    }

    var tempDisplay: String { "\(Int(temperature.rounded()))°F" }
    var watchText:   String { "\(Int(temperature.rounded()))° \(description)" }
}

class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherManager()

    private let locationManager = CLLocationManager()
    private var activeTask: URLSessionDataTask?

    @Published var condition: WeatherCondition?
    @Published var isLoading = false
    @Published var error: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestLocationAndFetch() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        fetchWeather(for: loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.error = error.localizedDescription }
    }

    // MARK: - Private

    private func fetchWeather(for location: CLLocation) {
        activeTask?.cancel()
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlStr = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m"
            + "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto"
        guard let url = URL(string: urlStr) else { return }

        DispatchQueue.main.async { self.isLoading = true }

        CLGeocoder().reverseGeocodeLocation(location) { [weak self] marks, _ in
            guard let self else { return }
            let city = marks?.first?.locality ?? "Unknown"
            self.activeTask = URLSession.shared.dataTask(with: url) { data, _, err in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let err = err {
                        if (err as NSError).code != NSURLErrorCancelled {
                            self.error = err.localizedDescription
                        }
                        return
                    }
                    guard let data,
                          let resp = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                    else { self.error = "Parse error"; return }
                    self.condition = WeatherCondition(
                        temperature: resp.current.temperature_2m,
                        feelsLike:   resp.current.apparent_temperature,
                        weatherCode: resp.current.weather_code,
                        windspeed:   resp.current.wind_speed_10m,
                        city:        city,
                        updatedAt:   Date()
                    )
                    self.error = nil
                }
            }
            self.activeTask?.resume()
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: OMCurrent
}
private struct OMCurrent: Decodable {
    let temperature_2m: Double
    let apparent_temperature: Double
    let weather_code: Int
    let wind_speed_10m: Double
}
