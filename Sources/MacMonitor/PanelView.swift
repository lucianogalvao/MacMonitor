import SwiftUI

struct PanelView: View {
    let system: SystemMonitor
    let weather: WeatherService

    enum Tab: String, CaseIterable {
        case system = "Sistema"
        case processes = "Processos"
        case weather = "Clima"
    }

    @AppStorage(Preferences.layout) private var layout = PanelLayout.normal
    @State private var tab: Tab = .system
    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 12) {
            header

            if !isShowingSettings {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ScrollView {
                if isShowingSettings {
                    SettingsView()
                } else {
                    switch tab {
                    case .system: SystemTab(system: system, compact: layout == .compact)
                    case .processes: ProcessesTab(system: system, compact: layout == .compact)
                    case .weather: WeatherTab(weather: weather, compact: layout == .compact)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)

            Divider()
            FooterView()
        }
        .padding(14)
        .frame(width: PanelLayout.panelWidth, height: layout.panelHeight)
    }

    private var header: some View {
        HStack {
            if isShowingSettings {
                Label("Configurações", systemImage: "gearshape")
                    .font(.subheadline.weight(.semibold))
            } else if let device = system.device {
                Label(device, systemImage: "laptopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                isShowingSettings.toggle()
            } label: {
                Image(systemName: isShowingSettings ? "xmark.circle.fill" : "gearshape")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(isShowingSettings ? "Fechar configurações" : "Configurações")
        }
    }
}

// MARK: - Sistema

struct SystemTab: View {
    let system: SystemMonitor
    let compact: Bool

    @AppStorage(Preferences.hiddenSections) private var storedHidden = ""

    var body: some View {
        let hidden = Set<PanelSection>(stored: storedHidden)
        if compact {
            CompactSystemView(system: system, sections: PanelSection.allCases.filter { !hidden.contains($0) })
        } else {
            cards(hidden: hidden)
        }
    }

    private func cards(hidden: Set<PanelSection>) -> some View {
        VStack(spacing: 10) {
            if !hidden.contains(.cpu) {
                Card(title: "CPU", symbol: "cpu", trailing: Format.percent(system.cpuUsage)) {
                    Sparkline(values: system.cpuHistory, maxValue: 100, color: .blue)
                    CoreBars(values: system.cpuPerCore)
                }
            }

            if !hidden.contains(.gpu), let gpu = system.gpu {
                Card(title: "GPU", symbol: "cube", trailing: Format.percent(gpu.utilization)) {
                    Sparkline(values: system.gpuHistory, maxValue: 100, color: .purple)
                    if let memory = gpu.memoryInUse {
                        StatRow("Memória em uso", Format.memory(memory))
                    }
                }
            }

            if !hidden.contains(.temperatures), !system.temperatures.isEmpty {
                TemperatureCard(groups: system.temperatures, battery: system.battery?.temperature)
            }

            if !hidden.contains(.memory), let memory = system.memory {
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

            if !hidden.contains(.network) {
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
            }

            if !hidden.contains(.disk), let space = system.diskSpace {
                Card(title: "Disco", symbol: "internaldrive",
                     trailing: "\(Format.disk(space.free)) livres") {
                    ProgressView(value: Double(space.total - space.free), total: Double(space.total))
                    StatRow("Leitura", Format.rate(system.diskRead))
                    StatRow("Escrita", Format.rate(system.diskWrite))
                }
            }

            if !hidden.contains(.battery), let battery = system.battery {
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

/// Layout compacto: blocos quadrados em grade de 3 colunas, sem rolagem.
struct CompactSystemView: View {
    let system: SystemMonitor
    let sections: [PanelSection]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(sections, id: \.self) { section in
                tile(section)
            }
        }
    }

    @ViewBuilder
    private func tile(_ section: PanelSection) -> some View {
        switch section {
        case .cpu:
            Tile(symbol: "cpu", title: "CPU", value: Format.percent(system.cpuUsage),
                 valueColor: Format.usageColor(system.cpuUsage)) {
                Sparkline(values: system.cpuHistory, maxValue: 100, color: .blue, height: 18)
            }
        case .gpu:
            if let gpu = system.gpu {
                Tile(symbol: "cube", title: "GPU", value: Format.percent(gpu.utilization),
                     valueColor: Format.usageColor(gpu.utilization)) {
                    Sparkline(values: system.gpuHistory, maxValue: 100, color: .purple, height: 18)
                }
            }
        case .temperatures:
            if let cpu = system.cpuTemperature {
                Tile(symbol: "thermometer.medium", title: "Temperatura", value: Format.temperature(cpu),
                     valueColor: Format.temperatureColor(cpu)) {
                    detail(otherTemperatures)
                }
            }
        case .memory:
            if let memory = system.memory, memory.total > 0 {
                Tile(symbol: "memorychip", title: "Memória",
                     value: Format.percent(Double(memory.used) / Double(memory.total) * 100),
                     valueColor: memory.pressure == .normal ? .primary : memory.pressure.color) {
                    detail(Format.memory(memory.used))
                }
            }
        case .network:
            Tile(symbol: "network", title: "Rede", value: Format.rate(system.download)) {
                detail("↑ \(Format.rate(system.upload))")
            }
        case .disk:
            if let space = system.diskSpace {
                Tile(symbol: "internaldrive", title: "Disco", value: Format.disk(space.free)) {
                    detail("livres")
                }
            }
        case .battery:
            if let battery = system.battery {
                Tile(symbol: battery.symbol, title: "Bateria", value: "\(battery.level)%",
                     valueColor: battery.level <= 20 && !battery.isOnAC ? .red : .primary) {
                    detail(battery.status)
                }
            }
        }
    }

    /// "GPU 30° · SSD 40°": a CPU já é o valor principal do bloco.
    private var otherTemperatures: String {
        ["GPU", "SSD"].compactMap { name in
            system.temperatures.first { $0.id == name }.map { "\(name) \(Format.temperature($0.maximum))" }
        }
        .joined(separator: " · ")
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Tile<Footer: View>: View {
    let symbol: String
    let title: String
    let value: String
    var valueColor: Color = .primary
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            footer
                .frame(height: 18)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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
    let compact: Bool

    var body: some View {
        let limit = compact ? 5 : .max
        VStack(spacing: 10) {
            Card(title: "Mais usam CPU", symbol: "cpu") {
                ProcessList(processes: Array(system.topProcesses.prefix(limit)), highlight: .cpu)
            }
            Card(title: "Mais usam memória", symbol: "memorychip") {
                ProcessList(processes: Array(system.topMemoryProcesses.prefix(limit)), highlight: .memory)
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
    let compact: Bool

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
            if compact {
                Text("Sensação \(Format.temperature(current.apparentTemperature)) · Umidade \(current.relativeHumidity2m)% · Vento \(Int(current.windSpeed10m.rounded())) km/h")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                StatRow("Sensação", "\(Int(current.apparentTemperature.rounded()))°")
                StatRow("Umidade", "\(current.relativeHumidity2m)%")
                StatRow("Vento", "\(Int(current.windSpeed10m.rounded())) km/h")
            }
            if !compact, !location.region.isEmpty {
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
        let days = compact ? Array(forecast.days.prefix(4)) : forecast.days
        return Card(title: "\(days.count) dias", symbol: "calendar") {
            ForEach(days) { day in
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

// MARK: - Rodapé

struct FooterView: View {
    var body: some View {
        HStack {
            Text("MacMonitor \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
