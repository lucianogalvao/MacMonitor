import Foundation
import Observation

@MainActor @Observable
final class SystemMonitor {
    static let historyLength = 60
    static let interval: Duration = .seconds(2)

    private(set) var device: String?

    private(set) var cpuUsage: Double = 0
    private(set) var cpuPerCore: [Double] = []
    private(set) var cpuHistory: [Double] = []

    private(set) var gpu: GPUSample?
    private(set) var gpuHistory: [Double] = []

    private(set) var memory: MemorySample?

    private(set) var download: Double = 0
    private(set) var upload: Double = 0
    private(set) var downloadHistory: [Double] = []
    private(set) var uploadHistory: [Double] = []
    private(set) var localIP: String?

    private(set) var diskSpace: (free: Int64, total: Int64)?
    private(set) var diskRead: Double = 0
    private(set) var diskWrite: Double = 0

    private(set) var temperatures: [TemperatureGroup] = []

    /// Maior leitura entre os núcleos de desempenho e de eficiência.
    var cpuTemperature: Double? {
        temperatures.filter { $0.id.hasPrefix("CPU") }.map(\.maximum).max()
    }

    private(set) var battery: BatterySample?
    private(set) var topProcesses: [ProcessUsage] = []
    private(set) var topMemoryProcesses: [ProcessUsage] = []

    @ObservationIgnored private let cpuReader = CPUReader()
    @ObservationIgnored private let networkReader = NetworkReader()
    @ObservationIgnored private let diskReader = DiskReader()
    @ObservationIgnored private let temperatureReader = TemperatureReader()
    @ObservationIgnored private let alerts = AlertMonitor()
    @ObservationIgnored private var isPanelVisible = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastDiskSpaceRead = Date.distantPast

    init() {
        Task.detached(priority: .utility) {
            let device = DeviceInfo.summary()
            await MainActor.run { self.device = device }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// A lista de processos só é atualizada com o painel aberto, porque roda o `ps`.
    func panelOpened() {
        isPanelVisible = true
        refreshProcesses()
    }

    func panelClosed() {
        isPanelVisible = false
    }

    private func sample() {
        if let cpu = cpuReader.read() {
            cpuUsage = cpu.total
            cpuPerCore = cpu.perCore
            append(cpu.total, to: &cpuHistory)
        }

        gpu = GPUReader.read()
        if let gpu {
            append(gpu.utilization, to: &gpuHistory)
        }

        memory = MemoryReader.read()

        if let network = networkReader.read() {
            download = network.down
            upload = network.up
            append(network.down, to: &downloadHistory)
            append(network.up, to: &uploadHistory)
        }
        localIP = NetworkReader.localIPv4()

        // O espaço livre muda devagar, e cada consulta gera dezenas de linhas no log do sistema
        if diskSpace == nil || Date().timeIntervalSince(lastDiskSpaceRead) >= 60 {
            diskSpace = DiskReader.space()
            lastDiskSpaceRead = Date()
        }
        if let disk = diskReader.activity() {
            diskRead = disk.read
            diskWrite = disk.write
        }

        temperatures = temperatureReader.read()
        battery = BatteryReader.read()

        alerts.evaluate(cpuUsage: cpuUsage, pressure: memory?.pressure, cpuTemperature: cpuTemperature)

        if isPanelVisible {
            refreshProcesses()
        }
    }

    private func refreshProcesses() {
        Task.detached(priority: .utility) {
            let byCPU = ProcessReader.top(by: .cpu, limit: 8)
            let byMemory = ProcessReader.top(by: .memory, limit: 10)
            await MainActor.run {
                self.topProcesses = byCPU
                self.topMemoryProcesses = byMemory
            }
        }
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength {
            history.removeFirst(history.count - Self.historyLength)
        }
    }
}
