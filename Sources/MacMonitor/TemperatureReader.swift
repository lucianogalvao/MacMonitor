import Foundation

struct TemperatureGroup: Identifiable {
    let id: String
    let average: Double
    let maximum: Double
}

/// Temperaturas do Apple Silicon via IOHID. As funções de leitura de eventos
/// não estão nos headers públicos, então são carregadas com dlsym; se alguma
/// faltar (Mac Intel ou mudança do macOS), o leitor simplesmente não retorna nada.
final class TemperatureReader {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> OpaquePointer?
    private typealias ClientSetMatching = @convention(c) (OpaquePointer, CFDictionary) -> Int32
    private typealias ClientCopyServices = @convention(c) (OpaquePointer) -> Unmanaged<CFArray>?
    private typealias ServiceCopyProperty = @convention(c) (OpaquePointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias ServiceCopyEvent = @convention(c) (OpaquePointer, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias EventGetFloat = @convention(c) (OpaquePointer, Int32) -> Double

    private static let temperatureEvent: Int64 = 15 // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(temperatureEvent << 16)
    /// Alguns sensores devolvem lixo (ex.: -21 °C); fora dessa faixa é descartado.
    private static let validRange = 1.0..<130.0

    /// Categorias por prefixo do nome do sensor, na ordem em que aparecem no painel.
    private static let groups: [(name: String, prefixes: [String])] = [
        ("CPU desempenho", ["pACC"]),
        ("CPU eficiência", ["eACC"]),
        ("GPU", ["GPU"]),
        ("Chip", ["SOC MTR", "PMGR SOC"]),
        ("SSD", ["NAND"]),
    ]

    private let copyEvent: ServiceCopyEvent?
    private let getFloat: EventGetFloat?
    /// Mantém os serviços vivos enquanto o leitor existir.
    private let services: CFArray?
    private let sensors: [(group: String, service: OpaquePointer)]

    init() {
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func load<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(iokit, name).map { unsafeBitCast($0, to: type) }
        }

        copyEvent = load("IOHIDServiceClientCopyEvent", as: ServiceCopyEvent.self)
        getFloat = load("IOHIDEventGetFloatValue", as: EventGetFloat.self)

        guard let createClient = load("IOHIDEventSystemClientCreate", as: ClientCreate.self),
              let setMatching = load("IOHIDEventSystemClientSetMatching", as: ClientSetMatching.self),
              let copyServices = load("IOHIDEventSystemClientCopyServices", as: ClientCopyServices.self),
              let copyProperty = load("IOHIDServiceClientCopyProperty", as: ServiceCopyProperty.self),
              let client = createClient(kCFAllocatorDefault) else {
            services = nil
            sensors = []
            return
        }

        _ = setMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary)
        services = copyServices(client)?.takeRetainedValue()

        var sensors: [(group: String, service: OpaquePointer)] = []
        for service in (services as? [AnyObject]) ?? [] {
            let pointer = OpaquePointer(Unmanaged.passUnretained(service).toOpaque())
            guard let name = copyProperty(pointer, "Product" as CFString)?.takeRetainedValue() as? String,
                  let group = Self.groups.first(where: { group in group.prefixes.contains { name.hasPrefix($0) } })
            else { continue }
            sensors.append((group.name, pointer))
        }
        self.sensors = sensors
    }

    func read() -> [TemperatureGroup] {
        guard let copyEvent, let getFloat else { return [] }

        var values: [String: [Double]] = [:]
        for sensor in sensors {
            guard let event = copyEvent(sensor.service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let value = getFloat(OpaquePointer(Unmanaged.passUnretained(event).toOpaque()), Self.temperatureField)
            if Self.validRange.contains(value) {
                values[sensor.group, default: []].append(value)
            }
        }

        return Self.groups.compactMap { group in
            guard let readings = values[group.name], let maximum = readings.max() else { return nil }
            return TemperatureGroup(id: group.name,
                                    average: readings.reduce(0, +) / Double(readings.count),
                                    maximum: maximum)
        }
    }
}
