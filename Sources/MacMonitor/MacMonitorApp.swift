import SwiftUI

// Entrada pelo AppKit: uma cena SwiftUI obrigaria a existir uma janela (vazia) de Settings
@main
@MainActor
enum MacMonitorApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        // Sem Dock mesmo fora do .app (swift run), onde não há LSUIElement do Info.plist
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.mainMenu = mainMenu()
        app.run()
    }

    /// Menus do app (Sair) e Editar. Os atalhos do painel são tratados em
    /// `PanelWindow.performKeyEquivalent`, porque o app nunca fica ativo.
    private static func mainMenu() -> NSMenu {
        let appMenu = NSMenu(title: "MacMonitor")
        appMenu.addItem(withTitle: "Sair do MacMonitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Editar")
        edit.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Selecionar Tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let main = NSMenu()
        for submenu in [appMenu, edit] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        return main
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
        let parts = MenuBarItem.allCases.filter(items.contains).compactMap(part)
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

    private func part(_ item: MenuBarItem) -> Text? {
        switch item {
        case .cpu:
            return Text("\(Image(systemName: "cpu")) \(Format.percent(system.cpuUsage))")
        case .cpuTemperature:
            guard let temperature = system.cpuTemperature else { return nil }
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
