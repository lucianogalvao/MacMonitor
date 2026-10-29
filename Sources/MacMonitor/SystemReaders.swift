import Foundation
import Darwin
import IOKit
import IOKit.ps

// MARK: - CPU

struct CPUSample {
    let total: Double
    let perCore: [Double]
}

final class CPUReader {
    private var previous: [[UInt32]] = []

    /// Uso de CPU desde a última leitura. Retorna nil na primeira chamada.
    func read() -> CPUSample? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        let ticks = (0..<Int(cpuCount)).map { core in
            (0..<states).map { UInt32(bitPattern: info[core * states + $0]) }
        }
        defer { previous = ticks }
        guard previous.count == ticks.count else { return nil }

        var perCore: [Double] = []
        var busySum = 0.0, totalSum = 0.0
        for (current, last) in zip(ticks, previous) {
            // Os contadores são cumulativos e podem dar a volta, por isso &-
            let delta = zip(current, last).map { Double($0 &- $1) }
            let total = delta.reduce(0, +)
            let busy = total - delta[Int(CPU_STATE_IDLE)]
            perCore.append(total > 0 ? busy / total * 100 : 0)
            busySum += busy
            totalSum += total
        }
        return CPUSample(total: totalSum > 0 ? busySum / totalSum * 100 : 0, perCore: perCore)
    }
}

// MARK: - Memória

enum MemoryPressure {
    case normal, warning, critical
}

struct MemorySample {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let swapUsed: UInt64
    let pressure: MemoryPressure

    /// Mesmo critério do Monitor de Atividade: app + wired + comprimida.
    var used: UInt64 { app + wired + compressed }
}

enum MemoryReader {
    static func read() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = UInt64(getpagesize())
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let swap = sysctlValue("vm.swapusage", xsw_usage())

        let pressure: MemoryPressure
        switch sysctlValue("kern.memorystatus_vm_pressure_level", Int32(1)) {
        case 4: pressure = .critical
        case 2: pressure = .warning
        default: pressure = .normal
        }

        return MemorySample(
            total: ProcessInfo.processInfo.physicalMemory,
            app: (internalPages > purgeable ? internalPages - purgeable : 0) * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            swapUsed: swap?.xsu_used ?? 0,
            pressure: pressure
        )
    }
}

// MARK: - Rede

final class NetworkReader {
    private var previous: (received: UInt64, sent: UInt64, time: Date)?

    /// Velocidade em bytes/s desde a última leitura. Retorna nil na primeira chamada.
    func read() -> (down: Double, up: Double)? {
        let totals = Self.totals()
        let now = Date()
        defer { previous = (totals.received, totals.sent, now) }
        guard let previous else { return nil }
        let elapsed = now.timeIntervalSince(previous.time)
        guard elapsed > 0 else { return nil }
        let down = totals.received >= previous.received ? Double(totals.received - previous.received) : 0
        let up = totals.sent >= previous.sent ? Double(totals.sent - previous.sent) : 0
        return (down / elapsed, up / elapsed)
    }

    /// Soma dos bytes das interfaces físicas (en*), com contadores de 64 bits.
    private static func totals() -> (received: UInt64, sent: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        var received: UInt64 = 0, sent: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if interfaceName(index: message.ifm_index)?.hasPrefix("en") == true {
                        received += message.ifm_data.ifi_ibytes
                        sent += message.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (received, sent)
    }

    private static func interfaceName(index: UInt16) -> String? {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &name) != nil else { return nil }
        return cString(name)
    }

    static func localIPv4() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  String(cString: interface.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return cString(host)
            }
        }
        return nil
    }
}

// MARK: - Disco

final class DiskReader {
    private var previous: (read: UInt64, written: UInt64, time: Date)?

    /// Leitura e escrita em bytes/s desde a última chamada. Retorna nil na primeira chamada.
    func activity() -> (read: Double, write: Double)? {
        let totals = Self.totals()
        let now = Date()
        defer { previous = (totals.read, totals.written, now) }
        guard let previous else { return nil }
        let elapsed = now.timeIntervalSince(previous.time)
        guard elapsed > 0 else { return nil }
        let read = totals.read >= previous.read ? Double(totals.read - previous.read) : 0
        let write = totals.written >= previous.written ? Double(totals.written - previous.written) : 0
        return (read / elapsed, write / elapsed)
    }

    private static func totals() -> (read: UInt64, written: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, written: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statistics = registryProperty(service, "Statistics") as? [String: Any] {
                read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (read, written)
    }

    static func space() -> (free: Int64, total: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return (free, Int64(total))
    }
}

// MARK: - Bateria

struct BatterySample {
    let level: Int
    let isCharging: Bool
    let isOnAC: Bool
    /// Minutos até esvaziar (na bateria) ou até carregar (na tomada).
    let minutesRemaining: Int?
    let cycleCount: Int?
    /// Capacidade máxima atual em relação à de fábrica, em %.
    let health: Int?
    /// Em °C.
    let temperature: Double?
}

enum BatteryReader {
    static func read() -> BatterySample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery" else { continue }

            let current = description["Current Capacity"] as? Int ?? 0
            let max = description["Max Capacity"] as? Int ?? 100
            let isCharging = description["Is Charging"] as? Bool ?? false
            let isOnAC = description["Power Source State"] as? String == "AC Power"
            let minutes = description[isCharging ? "Time to Full Charge" : "Time to Empty"] as? Int
            let (cycles, health, temperature) = details()

            return BatterySample(
                level: max > 0 ? current * 100 / max : current,
                isCharging: isCharging,
                isOnAC: isOnAC,
                minutesRemaining: (minutes ?? -1) > 0 && (isCharging || !isOnAC) ? minutes : nil,
                cycleCount: cycles,
                health: health,
                temperature: temperature
            )
        }
        return nil
    }

    private static func details() -> (cycles: Int?, health: Int?, temperature: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil, nil) }
        defer { IOObjectRelease(service) }

        let cycles = registryProperty(service, "CycleCount") as? Int
        // Vem em centésimos de grau (3031 = 30,31 °C)
        let temperature = (registryProperty(service, "Temperature") as? Int).map { Double($0) / 100 }
        let design = registryProperty(service, "DesignCapacity") as? Int
        let maxCapacity = registryProperty(service, "AppleRawMaxCapacity") as? Int
            ?? registryProperty(service, "NominalChargeCapacity") as? Int
        guard let design, design > 0, let maxCapacity else { return (cycles, nil, temperature) }
        return (cycles, min(100, maxCapacity * 100 / design), temperature)
    }
}

// MARK: - Processos

struct ProcessUsage: Identifiable {
    let id: Int32
    let name: String
    let cpu: Double
    let memory: UInt64
}

enum ProcessSort {
    case cpu, memory

    /// Flag de ordenação do `ps`: -r por CPU, -m por memória.
    var flag: String {
        switch self {
        case .cpu: "-r"
        case .memory: "-m"
        }
    }
}

enum ProcessReader {
    /// Processos que mais usam CPU ou memória, via `ps`.
    static func top(by sort: ProcessSort, limit: Int) -> [ProcessUsage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pid=,pcpu=,rss=,comm=", sort.flag]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .lazy
            .compactMap { line -> ProcessUsage? in
                let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                guard parts.count == 4,
                      let pid = Int32(parts[0]),
                      let cpu = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                      let rss = UInt64(parts[2]) else { return nil }
                return ProcessUsage(id: pid, name: String(parts[3]), cpu: cpu, memory: rss * 1024)
            }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Modelo do Mac

enum DeviceInfo {
    /// Ex.: "Apple MacBook Air (M1, 2020) - macOS 26.6.2 Tahoe"
    static func summary() -> String {
        "Apple \(modelName()) - \(systemVersion())"
    }

    /// Nome comercial. O Sobre Este Mac guarda um cache com o nome completo;
    /// sem ele, cai para o system_profiler (só nome + chip, sem ano).
    private static func modelName() -> String {
        let cache = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/com.apple.SystemProfiler.plist")
        if let preferences = NSDictionary(contentsOf: cache),
           let names = preferences["CPU Names"] as? [String: String],
           let name = names.values.sorted().first {
            return name
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hardware = (json["SPHardwareDataType"] as? [[String: Any]])?.first,
               let name = hardware["machine_name"] as? String {
                let chip = (hardware["chip_type"] as? String)?.replacingOccurrences(of: "Apple ", with: "")
                return chip.map { "\(name) (\($0))" } ?? name
            }
        }

        return sysctlString("hw.model") ?? "Mac"
    }

    private static func systemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var number = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { number += ".\(version.patchVersion)" }
        let names = [26: "Tahoe", 15: "Sequoia", 14: "Sonoma"]
        return ["macOS", number, names[version.majorVersion]].compactMap { $0 }.joined(separator: " ")
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return cString(buffer)
    }
}

// MARK: - Utilidades

private func sysctlValue<T: BitwiseCopyable>(_ name: String, _ initial: T) -> T? {
    var value = initial
    var size = MemoryLayout<T>.size
    return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
}

private func registryProperty(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

private func cString(_ buffer: [CChar]) -> String {
    String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
