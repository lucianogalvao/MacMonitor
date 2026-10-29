import SwiftUI
import ServiceManagement

struct PanelView: View {
    let system: SystemMonitor
    let weather: WeatherService

    enum Tab: String, CaseIterable {
        case system = "Sistema"
        case processes = "Processos"
        case weather = "Clima"
        case alerts = "Alertas"
    }

    static let contentHeight: CGFloat = 600

    @State private var tab: Tab = .system

    var body: some View {
        VStack(spacing: 12) {
            if let device = system.device {
                Label(device, systemImage: "laptopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Altura fixa: se o conteúdo muda de tamanho, a janela do MenuBarExtra
            // encolhe pela borda de cima e se descola da barra de menus.
            ScrollView {
                switch tab {
                case .system: SystemTab(system: system)
                case .processes: ProcessesTab(system: system)
                case .weather: WeatherTab(weather: weather)
                case .alerts: AlertsTab()
                }
            }
            .scrollIndicators(.never)
            .frame(height: Self.contentHeight)

            Divider()
            FooterView()
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { system.panelOpened() }
        .onDisappear { system.panelClosed() }
    }
}

// MARK: - Sistema

struct SystemTab: View {
    let system: SystemMonitor

    var body: some View {
        VStack(spacing: 10) {
            Card(title: "CPU", symbol: "cpu", trailing: Format.percent(system.cpuUsage)) {
                Sparkline(values: system.cpuHistory, maxValue: 100, color: .blue)
                CoreBars(values: system.cpuPerCore)
            }

            if !system.temperatures.isEmpty {
                TemperatureCard(groups: system.temperatures, battery: system.battery?.temperature)
            }

            if let memory = system.memory {
                Card(title: "Memória", symbol: "memorychip",
                     trailing: "\(Format.memory(memory.used)) de \(Format.memory(memory.total))") {
                    ProgressView(value: Double(memory.used), total: Double(memory.total))
                        .tint(memory.pressure.color)
                    StatRow("Pressão", memory.pressure.label)
                    StatRow("Apps", Format.memory(memory.app))
                    StatRow("Comprimida", Format.memory(memory.compressed))
                    StatRow("Swap", Format.memory(memory.swapUsed))
                }
            }

            Card(title: "Rede", symbol: "network") {
                MaskedIP(address: system.localIP)
            } content: {
                DualSparkline(first: system.downloadHistory, second: system.uploadHistory)
                HStack {
                    Label(Format.rate(system.download), systemImage: "arrow.down")
                        .foregroundStyle(.green)
                    Spacer()
                    Label(Format.rate(system.upload), systemImage: "arrow.up")
                        .foregroundStyle(.orange)
                }
                .font(.caption.monospacedDigit())
            }

            if let space = system.diskSpace {
                Card(title: "Disco", symbol: "internaldrive",
                     trailing: "\(Format.disk(space.free)) livres") {
                    ProgressView(value: Double(space.total - space.free), total: Double(space.total))
                    StatRow("Leitura", Format.rate(system.diskRead))
                    StatRow("Escrita", Format.rate(system.diskWrite))
                }
            }

            if let battery = system.battery {
                Card(title: "Bateria", symbol: battery.symbol, trailing: "\(battery.level)%") {
                    ProgressView(value: Double(battery.level), total: 100)
                        .tint(battery.level <= 20 && !battery.isOnAC ? .red : .green)
                    StatRow("Status", battery.status)
                    if let minutes = battery.minutesRemaining {
                        StatRow(battery.isCharging ? "Carga completa em" : "Tempo restante", Format.duration(minutes))
                    }
                    if let cycles = battery.cycleCount {
                        StatRow("Ciclos", "\(cycles)")
                    }
                    if let health = battery.health {
                        StatRow("Saúde", "\(health)%")
                    }
                }
            }
        }
    }
}

struct TemperatureCard: View {
    let groups: [TemperatureGroup]
    let battery: Double?

    var body: some View {
        let hottest = groups.map(\.maximum).max() ?? 0
        Card(title: "Temperaturas", symbol: "thermometer.medium", trailing: Format.temperature(hottest)) {
            HStack {
                Spacer()
                Text("média").frame(width: 44, alignment: .trailing)
                Text("máx").frame(width: 44, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            ForEach(groups) { group in
                HStack {
                    Text(group.id).foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.temperature(group.average))
                        .frame(width: 44, alignment: .trailing)
                    Text(Format.temperature(group.maximum))
                        .foregroundStyle(Format.temperatureColor(group.maximum))
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.caption.monospacedDigit())
            }

            if let battery {
                HStack {
                    Text("Bateria").foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.temperature(battery))
                        .foregroundStyle(Format.temperatureColor(battery))
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.caption.monospacedDigit())
            }
        }
    }
}

struct CoreBars: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Format.usageColor(value))
                    .frame(height: max(2, 22 * value / 100))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 22, alignment: .bottom)
    }
}

// MARK: - Processos

struct ProcessesTab: View {
    let system: SystemMonitor

    var body: some View {
        VStack(spacing: 10) {
            Card(title: "Mais usam CPU", symbol: "cpu") {
                ProcessList(processes: system.topProcesses, highlight: .cpu)
            }
            Card(title: "Mais usam memória", symbol: "memorychip") {
                ProcessList(processes: system.topMemoryProcesses, highlight: .memory)
            }
        }
    }
}

struct ProcessList: View {
    let processes: [ProcessUsage]
    let highlight: ProcessSort

    var body: some View {
        if processes.isEmpty {
            Text("Carregando…").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(processes) { process in
            HStack {
                Text(process.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Format.memory(process.memory))
                    .foregroundStyle(highlight == .memory ? .primary : .secondary)
                    .frame(width: 70, alignment: .trailing)
                Text(String(format: "%.1f%%", process.cpu))
                    .foregroundStyle(highlight == .cpu ? Format.usageColor(process.cpu) : Color.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
            .font(.caption.monospacedDigit())
        }
    }
}

// MARK: - Clima

struct WeatherTab: View {
    let weather: WeatherService

    @State private var isEditing = false
    @State private var cityQuery = ""

    var body: some View {
        VStack(spacing: 10) {
            if weather.location == nil || isEditing {
                citySearch
            }

            if let error = weather.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            if let location = weather.location, let forecast = weather.forecast {
                current(location: location, forecast: forecast)
                hourly(forecast)
                daily(forecast)
                updatedFooter
            } else if weather.isLoading {
                ProgressView().controlSize(.small)
            } else if let location = weather.location {
                failedState(location)
            }
        }
    }

    /// Cidade escolhida, mas a previsão não carregou: nunca deixa a aba vazia.
    private func failedState(_ location: WeatherLocation) -> some View {
        Card(title: location.name, symbol: "exclamationmark.triangle") {
            Text("Não foi possível carregar o clima.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Tentar novamente") {
                    Task { await weather.refresh() }
                }
                Spacer()
                if !isEditing {
                    Button("Alterar cidade") { isEditing = true }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
        }
    }

    private var citySearch: some View {
        HStack {
            TextField("Digite sua cidade", text: $cityQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit(search)
            Button("Buscar", action: search)
                .disabled(cityQuery.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func search() {
        Task {
            await weather.setCity(cityQuery)
            if weather.errorMessage == nil {
                isEditing = false
                cityQuery = ""
            }
        }
    }

    private func current(location: WeatherLocation, forecast: Forecast) -> some View {
        let current = forecast.current
        return Card(title: location.name, symbol: "location.fill") {
            HStack(spacing: 14) {
                Image(systemName: WeatherCode.symbol(current.weatherCode, isDay: current.isDay == 1))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(current.temperature2m.rounded()))°")
                        .font(.system(size: 34, weight: .light).monospacedDigit())
                    Text(WeatherCode.description(current.weatherCode))
                        .font(.callout)
                }
                Spacer()
                Button(isEditing ? "Cancelar" : "Alterar") { isEditing.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            StatRow("Sensação", "\(Int(current.apparentTemperature.rounded()))°")
            StatRow("Umidade", "\(current.relativeHumidity2m)%")
            StatRow("Vento", "\(Int(current.windSpeed10m.rounded())) km/h")
            if !location.region.isEmpty {
                Text(location.region).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func hourly(_ forecast: Forecast) -> some View {
        Card(title: "Próximas horas", symbol: "clock") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(forecast.nextHours) { hour in
                        VStack(spacing: 6) {
                            Text(hour.hour).font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: WeatherCode.symbol(hour.code, isDay: hour.isDay))
                                .symbolRenderingMode(.multicolor)
                                .frame(height: 18)
                            Text("\(Int(hour.temperature.rounded()))°").font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private func daily(_ forecast: Forecast) -> some View {
        Card(title: "7 dias", symbol: "calendar") {
            ForEach(forecast.days) { day in
                HStack {
                    Text(day.weekday).frame(width: 44, alignment: .leading)
                    Image(systemName: WeatherCode.symbol(day.code, isDay: true))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 24)
                    Text(day.rainChance.map { $0 > 0 ? "\($0)%" : "" } ?? "")
                        .foregroundStyle(.cyan)
                        .frame(width: 36, alignment: .trailing)
                    Spacer()
                    Text("\(Int(day.min.rounded()))°").foregroundStyle(.secondary)
                    Text("\(Int(day.max.rounded()))°").frame(width: 30, alignment: .trailing)
                }
                .font(.caption.monospacedDigit())
            }
        }
    }

    private var updatedFooter: some View {
        HStack {
            if let lastUpdate = weather.lastUpdate {
                Text("Atualizado às \(lastUpdate.formatted(date: .omitted, time: .shortened)) · Open-Meteo")
            }
            Spacer()
            Button {
                Task { await weather.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(weather.isLoading)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Alertas

struct AlertsTab: View {
    @AppStorage(AlertSettings.cpuEnabled) private var cpuEnabled = false
    @AppStorage(AlertSettings.cpuThreshold) private var cpuThreshold = AlertSettings.defaultCPUThreshold
    @AppStorage(AlertSettings.memoryEnabled) private var memoryEnabled = false
    @AppStorage(AlertSettings.temperatureEnabled) private var temperatureEnabled = false
    @AppStorage(AlertSettings.temperatureThreshold) private var temperatureThreshold = AlertSettings.defaultTemperatureThreshold

    @State private var isAuthorized = true

    var body: some View {
        VStack(spacing: 10) {
            Card(title: "CPU", symbol: "cpu") {
                Toggle("Avisar quando o uso passar de \(Format.percent(cpuThreshold))", isOn: $cpuEnabled)
                Slider(value: $cpuThreshold, in: 50...100, step: 5)
                    .disabled(!cpuEnabled)
                hint("Por mais de 30 segundos. O aviso mostra o app que mais está usando CPU.")
            }

            Card(title: "Memória", symbol: "memorychip") {
                Toggle("Avisar quando a pressão de memória ficar alta", isOn: $memoryEnabled)
                hint("É o sinal de que o Mac está ficando sem memória e começando a ficar lento.")
            }

            Card(title: "Temperatura", symbol: "thermometer.medium") {
                Toggle("Avisar quando a CPU passar de \(Format.temperature(temperatureThreshold))", isOn: $temperatureEnabled)
                Slider(value: $temperatureThreshold, in: 60...105, step: 5)
                    .disabled(!temperatureEnabled)
                hint("Por mais de 30 segundos.")
            }

            if !isAuthorized {
                Card(title: "Notificações desativadas", symbol: "bell.slash") {
                    hint("Permita as notificações do MacMonitor para receber os avisos.")
                    Button("Abrir Ajustes de Notificações") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
            }

            HStack {
                Text("Depois de um aviso, o mesmo alerta espera 10 min para repetir.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Testar") {
                    Task {
                        isAuthorized = await AlertMonitor.requestAuthorization()
                        AlertMonitor.send(id: "test", title: "MacMonitor", body: "As notificações estão funcionando.")
                    }
                }
                .controlSize(.small)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.caption)
        .task { isAuthorized = await AlertMonitor.isAuthorized() || !anyEnabled }
        .onChange(of: anyEnabled) { _, enabled in
            guard enabled else { return }
            Task { isAuthorized = await AlertMonitor.requestAuthorization() }
        }
    }

    private var anyEnabled: Bool {
        cpuEnabled || memoryEnabled || temperatureEnabled
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Rodapé

struct FooterView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack {
            Toggle("Abrir ao iniciar sessão", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
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
            Spacer()
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
    }
}

// MARK: - Componentes

struct Card<Accessory: View, Content: View>: View {
    let title: String
    let symbol: String
    let accessory: Accessory
    let content: Content

    init(title: String, symbol: String,
         @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                accessory
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension Card where Accessory == Text? {
    init(title: String, symbol: String, trailing: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, accessory: { trailing.map { Text($0) } }, content: content)
    }
}

/// IP escondido por padrão; o olho alterna e a escolha fica salva.
struct MaskedIP: View {
    let address: String?

    @AppStorage("network.showIP") private var isVisible = false

    var body: some View {
        if let address {
            HStack(spacing: 6) {
                Text(isVisible ? address : "•••.•••.•.•••")
                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isVisible ? "Esconder IP" : "Mostrar IP")
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

// MARK: - Apresentação

extension MemoryPressure {
    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Alta"
        case .critical: "Crítica"
        }
    }

    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

extension BatterySample {
    var status: String {
        if isCharging { return "Carregando" }
        return isOnAC ? "Na tomada" : "Na bateria"
    }

    var symbol: String {
        if isCharging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

enum Format {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    static func disk(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)min" : "\(minutes)min"
    }

    static func temperature(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°"
    }

    static func temperatureColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<75: .primary
        case ..<90: .orange
        default: .red
        }
    }

    static func usageColor(_ percent: Double) -> Color {
        switch percent {
        case ..<60: .blue
        case ..<85: .orange
        default: .red
        }
    }
}
