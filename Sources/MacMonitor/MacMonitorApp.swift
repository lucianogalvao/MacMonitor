import SwiftUI

@main
struct MacMonitorApp: App {
    @State private var system = SystemMonitor()
    @State private var weather = WeatherService()

    var body: some Scene {
        MenuBarExtra {
            PanelView(system: system, weather: weather)
        } label: {
            MenuBarLabel(system: system, weather: weather)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let system: SystemMonitor
    let weather: WeatherService

    var body: some View {
        let cpu = Int(system.cpuUsage.rounded())
        var label = Text("\(Image(systemName: "cpu")) \(cpu)%")
        if let temperature = system.cpuTemperature {
            label = label + Text(" \(Format.temperature(temperature))")
        }
        if let current = weather.forecast?.current {
            let symbol = WeatherCode.symbol(current.weatherCode, isDay: current.isDay == 1)
            label = label + Text("  \(Image(systemName: symbol)) \(Format.temperature(current.temperature2m))")
        }
        return label
    }
}
