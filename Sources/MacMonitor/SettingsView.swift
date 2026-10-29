import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(Preferences.layout) private var layout = PanelLayout.normal
    @AppStorage(Preferences.menuBarItems) private var storedMenuBarItems = MenuBarItem.defaultValue.stored
    @AppStorage(Preferences.hiddenSections) private var storedHiddenSections = ""

    var body: some View {
        VStack(spacing: 10) {
            Card(title: "Layout", symbol: "rectangle.split.1x2") {
                Picker("", selection: $layout) {
                    ForEach(PanelLayout.allCases, id: \.self) { Text($0.label) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                hint(layout == .normal
                     ? "Cards com gráficos e detalhes."
                     : "Blocos com os valores principais, sem precisar rolar.")
            }

            Card(title: "Barra de menus", symbol: "menubar.rectangle") {
                checkboxGrid(MenuBarItem.allCases, title: \.title) { item in
                    Binding {
                        Set<MenuBarItem>(stored: storedMenuBarItems).contains(item)
                    } set: { isOn in
                        var items = Set<MenuBarItem>(stored: storedMenuBarItems)
                        if isOn { items.insert(item) } else { items.remove(item) }
                        storedMenuBarItems = items.stored
                    }
                }
            }

            Card(title: "Painel", symbol: "rectangle.stack") {
                checkboxGrid(PanelSection.allCases, title: \.title) { section in
                    Binding {
                        !Set<PanelSection>(stored: storedHiddenSections).contains(section)
                    } set: { isOn in
                        var hidden = Set<PanelSection>(stored: storedHiddenSections)
                        if isOn { hidden.remove(section) } else { hidden.insert(section) }
                        storedHiddenSections = hidden.stored
                    }
                }
            }

            AlertsSettings()

            Card(title: "Geral", symbol: "power") {
                LaunchAtLoginToggle()
            }
        }
        .font(.caption)
    }

    private func checkboxGrid<Item: Hashable>(_ items: [Item], title: KeyPath<Item, String>,
                                              binding: @escaping (Item) -> Binding<Bool>) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Toggle(item[keyPath: title], isOn: binding(item))
                    .toggleStyle(.checkbox)
            }
        }
    }
}

// MARK: - Alertas

struct AlertsSettings: View {
    @AppStorage(AlertSettings.cpuEnabled) private var cpuEnabled = false
    @AppStorage(AlertSettings.cpuThreshold) private var cpuThreshold = AlertSettings.defaultCPUThreshold
    @AppStorage(AlertSettings.memoryEnabled) private var memoryEnabled = false
    @AppStorage(AlertSettings.temperatureEnabled) private var temperatureEnabled = false
    @AppStorage(AlertSettings.temperatureThreshold) private var temperatureThreshold = AlertSettings.defaultTemperatureThreshold

    @State private var isAuthorized = true

    var body: some View {
        Card(title: "Alertas", symbol: "bell") {
            Button("Testar") {
                Task {
                    isAuthorized = await AlertMonitor.requestAuthorization()
                    AlertMonitor.send(id: "test", title: "MacMonitor", body: "As notificações estão funcionando.")
                }
            }
            .controlSize(.small)
        } content: {
            Toggle("CPU acima de \(Format.percent(cpuThreshold))", isOn: $cpuEnabled)
            Slider(value: $cpuThreshold, in: 50...100, step: 5)
                .disabled(!cpuEnabled)

            Toggle("Pressão de memória alta", isOn: $memoryEnabled)

            Toggle("Temperatura da CPU acima de \(Format.temperature(temperatureThreshold))", isOn: $temperatureEnabled)
            Slider(value: $temperatureThreshold, in: 60...105, step: 5)
                .disabled(!temperatureEnabled)

            hint("CPU e temperatura avisam depois de 30 segundos acima do limite. Um mesmo alerta espera 10 min para repetir.")

            if !isAuthorized {
                Divider()
                hint("As notificações do MacMonitor estão desativadas.")
                Button("Abrir Ajustes de Notificações") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .task { isAuthorized = await AlertMonitor.isAuthorized() || !anyEnabled }
        .onChange(of: anyEnabled) { _, enabled in
            guard enabled else { return }
            Task { isAuthorized = await AlertMonitor.requestAuthorization() }
        }
    }

    private var anyEnabled: Bool {
        cpuEnabled || memoryEnabled || temperatureEnabled
    }
}

// MARK: - Geral

struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Abrir ao iniciar sessão", isOn: $launchAtLogin)
            .toggleStyle(.checkbox)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

private func hint(_ text: String) -> some View {
    Text(text)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}
