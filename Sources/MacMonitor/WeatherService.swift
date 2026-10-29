import Foundation
import Observation

struct WeatherLocation: Codable, Equatable {
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double

    private static let defaultsKey = "weather.location"

    static func load() -> WeatherLocation? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WeatherLocation.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Resposta da API de previsão do Open-Meteo. As chaves são explícitas porque o
/// .convertFromSnakeCase transforma "temperature_2m" em "temperature2M".
struct Forecast: Decodable {
    struct Current: Decodable {
        let time: String
        let temperature2m: Double
        let apparentTemperature: Double
        let relativeHumidity2m: Int
        let weatherCode: Int
        let windSpeed10m: Double
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity2m = "relative_humidity_2m"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
            case isDay = "is_day"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature2m: [Double]
        let weatherCode: [Int]
        let isDay: [Int]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]
        let precipitationProbabilityMax: [Int?]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }

    let current: Current
    let hourly: Hourly
    let daily: Daily
}

struct HourForecast: Identifiable {
    let id: String
    let hour: String
    let temperature: Double
    let code: Int
    let isDay: Bool
}

struct DayForecast: Identifiable {
    let id: String
    let weekday: String
    let code: Int
    let min: Double
    let max: Double
    let rainChance: Int?
}

extension Forecast {
    /// Próximas 24 horas a partir da hora atual (horário local da cidade).
    var nextHours: [HourForecast] {
        let currentHour = current.time.prefix(13) // "2026-10-29T14"
        guard let start = hourly.time.firstIndex(where: { $0.prefix(13) >= currentHour }) else { return [] }
        return (start..<min(start + 24, hourly.time.count)).map { i in
            HourForecast(
                id: hourly.time[i],
                hour: i == start ? "Agora" : String(hourly.time[i].dropFirst(11).prefix(2)) + "h",
                temperature: hourly.temperature2m[i],
                code: hourly.weatherCode[i],
                isDay: hourly.isDay[i] == 1
            )
        }
    }

    var days: [DayForecast] {
        daily.time.indices.map { i in
            DayForecast(
                id: daily.time[i],
                weekday: i == 0 ? "Hoje" : Self.weekday(daily.time[i]),
                code: daily.weatherCode[i],
                min: daily.temperature2mMin[i],
                max: daily.temperature2mMax[i],
                rainChance: daily.precipitationProbabilityMax[i]
            )
        }
    }

    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEE"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static func weekday(_ day: String) -> String {
        guard let date = dayParser.date(from: day) else { return day }
        return weekdayFormatter.string(from: date).replacingOccurrences(of: ".", with: "").capitalized
    }
}

@MainActor @Observable
final class WeatherService {
    static let refreshInterval: Duration = .seconds(15 * 60)

    private(set) var location = WeatherLocation.load()
    private(set) var forecast: Forecast?
    private(set) var lastUpdate: Date?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    static let errorDuration: Duration = .seconds(3)

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var errorDismissal: Task<Void, Never>?

    init() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    /// Aceita "Cidade" ou "Cidade, estado/país"; a parte depois da vírgula ajuda a escolher o resultado.
    func setCity(_ query: String) async {
        let parts = query.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let name = parts.first else { return }
        let hint = parts.dropFirst().joined(separator: " ").lowercased()
        isLoading = true
        clearError()
        defer { isLoading = false }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "pt"),
            URLQueryItem(name: "format", value: "json"),
        ]

        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let results = try decoder.decode(GeocodingResponse.self, from: data).results ?? []
            guard let result = results.first(where: { $0.matches(hint) }) ?? results.first else {
                show(error: "Cidade não encontrada")
                return
            }
            let newLocation = WeatherLocation(
                name: result.name,
                region: [result.admin1, result.country].compactMap { $0 }.joined(separator: ", "),
                latitude: result.latitude,
                longitude: result.longitude
            )
            newLocation.save()
            location = newLocation
            forecast = nil
        } catch {
            show(error: "Não foi possível buscar a cidade")
            return
        }
        await refresh()
    }

    /// A mensagem some sozinha depois de alguns segundos.
    private func show(error message: String) {
        errorMessage = message
        errorDismissal?.cancel()
        errorDismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.errorDuration)
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
        }
    }

    private func clearError() {
        errorDismissal?.cancel()
        errorMessage = nil
    }

    func refresh() async {
        guard let location else { return }
        isLoading = true
        defer { isLoading = false }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
        ]

        do {
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            forecast = try JSONDecoder().decode(Forecast.self, from: data)
            lastUpdate = Date()
            clearError()
        } catch {
            show(error: "Não foi possível atualizar o clima")
        }
    }
}

private struct GeocodingResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let countryCode: String?
        let admin1: String?

        func matches(_ hint: String) -> Bool {
            guard !hint.isEmpty else { return false }
            return [admin1, country, countryCode]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(hint) || hint.contains($0) }
        }
    }

    let results: [Result]?
}

/// Códigos de tempo WMO usados pelo Open-Meteo.
enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: "Céu limpo"
        case 1: "Predominantemente limpo"
        case 2: "Parcialmente nublado"
        case 3: "Nublado"
        case 45, 48: "Nevoeiro"
        case 51, 53, 55: "Garoa"
        case 56, 57: "Garoa congelante"
        case 61: "Chuva fraca"
        case 63: "Chuva"
        case 65: "Chuva forte"
        case 66, 67: "Chuva congelante"
        case 71, 73, 75, 77: "Neve"
        case 80, 81: "Pancadas de chuva"
        case 82: "Pancadas fortes de chuva"
        case 85, 86: "Pancadas de neve"
        case 95: "Trovoada"
        case 96, 99: "Trovoada com granizo"
        default: "—"
        }
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61, 63, 65: "cloud.rain.fill"
        case 66, 67: "cloud.sleet.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80...82: "cloud.heavyrain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}
