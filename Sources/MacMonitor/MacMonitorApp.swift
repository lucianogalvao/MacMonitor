import SwiftUI

@main
struct MacMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // O ícone e o painel são do StatusBarController; o SwiftUI só precisa de uma cena
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(system: SystemMonitor(), weather: WeatherService())
    }
}

struct MenuBarLabel: View {
    let system: SystemMonitor
    let weather: WeatherService

    @AppStorage(Preferences.menuBarItems) private var storedItems = MenuBarItem.defaultValue.stored

    var body: some View {
        let items = Set<MenuBarItem>(stored: storedItems)
        let parts = MenuBarItem.allCases.filter(items.contains).compactMap { part($0, items: items) }
        Group {
            if parts.isEmpty {
                // Sem nada escolhido, o app continua acessível pelo ícone
                Image(systemName: "gauge.with.dots.needle.67percent")
            } else {
                parts.dropFirst().reduce(parts[0]) { $0 + Text("  ") + $1 }
            }
        }
        .font(Font(NSFont.menuBarFont(ofSize: 0)))
    }

    private func part(_ item: MenuBarItem, items: Set<MenuBarItem>) -> Text? {
        switch item {
        case .cpu:
            var text = Text("\(Image(systemName: "cpu")) \(Format.percent(system.cpuUsage))")
            // Junto do uso, a temperatura fica colada a ele em vez de virar um item separado
            if items.contains(.cpuTemperature), let temperature = system.cpuTemperature {
                text = text + Text(" \(Format.temperature(temperature))")
            }
            return text
        case .cpuTemperature:
            guard !items.contains(.cpu), let temperature = system.cpuTemperature else { return nil }
            return Text("\(Image(systemName: "thermometer.medium")) \(Format.temperature(temperature))")
        case .gpu:
            guard let gpu = system.gpu else { return nil }
            return Text("\(Image(systemName: "cube")) \(Format.percent(gpu.utilization))")
        case .memory:
            guard let memory = system.memory, memory.total > 0 else { return nil }
            return Text("\(Image(systemName: "memorychip")) \(Format.percent(Double(memory.used) / Double(memory.total) * 100))")
        case .network:
            return Text("\(Image(systemName: "arrow.down")) \(Format.rate(system.download))")
        case .weather:
            guard let current = weather.forecast?.current else { return nil }
            let symbol = WeatherCode.symbol(current.weatherCode, isDay: current.isDay == 1)
            return Text("\(Image(systemName: symbol)) \(Format.temperature(current.temperature2m))")
        }
    }
}
