import Foundation
import UserNotifications

/// Chaves no UserDefaults, compartilhadas com a aba Alertas (@AppStorage).
enum AlertSettings {
    static let cpuEnabled = "alerts.cpu.enabled"
    static let cpuThreshold = "alerts.cpu.threshold"
    static let memoryEnabled = "alerts.memory.enabled"
    static let temperatureEnabled = "alerts.temperature.enabled"
    static let temperatureThreshold = "alerts.temperature.threshold"

    static let defaultCPUThreshold = 90.0
    static let defaultTemperatureThreshold = 90.0

    static func register() {
        UserDefaults.standard.register(defaults: [
            cpuThreshold: defaultCPUThreshold,
            temperatureThreshold: defaultTemperatureThreshold,
        ])
    }
}

/// Dispara quando a condição se mantém por `sustain` segundos. Só volta a
/// disparar depois que o valor baixa de vez (`isClear`) e passado o `cooldown`,
/// para não repetir o aviso enquanto o valor oscila perto do limite.
private struct Trigger {
    let sustain: TimeInterval
    let cooldown: TimeInterval = 10 * 60

    private var since: Date?
    private var armed = true
    private var lastFired: Date?

    init(sustain: TimeInterval) {
        self.sustain = sustain
    }

    mutating func update(isHigh: Bool, isClear: Bool, now: Date = Date()) -> Bool {
        if isClear {
            since = nil
            armed = true
            return false
        }
        guard isHigh else {
            since = nil
            return false
        }
        let start = since ?? now
        since = start
        guard armed,
              now.timeIntervalSince(start) >= sustain,
              lastFired.map({ now.timeIntervalSince($0) >= cooldown }) ?? true else { return false }
        armed = false
        lastFired = now
        return true
    }
}

@MainActor
final class AlertMonitor: NSObject, UNUserNotificationCenterDelegate {
    private var cpu = Trigger(sustain: 30)
    private var memory = Trigger(sustain: 10)
    private var temperature = Trigger(sustain: 30)

    override init() {
        super.init()
        AlertSettings.register()
        UNUserNotificationCenter.current().delegate = self
    }

    func evaluate(cpuUsage: Double, pressure: MemoryPressure?, cpuTemperature: Double?) {
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: AlertSettings.cpuEnabled) {
            let threshold = defaults.double(forKey: AlertSettings.cpuThreshold)
            if cpu.update(isHigh: cpuUsage >= threshold, isClear: cpuUsage < threshold - 10) {
                notifyHighCPU(usage: cpuUsage)
            }
        }

        if defaults.bool(forKey: AlertSettings.memoryEnabled), let pressure {
            if memory.update(isHigh: pressure != .normal, isClear: pressure == .normal) {
                Self.send(id: "memory", title: "Pressão de memória \(pressure.label.lowercased())",
                          body: "O Mac está ficando sem memória. Feche apps que não está usando.")
            }
        }

        if defaults.bool(forKey: AlertSettings.temperatureEnabled), let cpuTemperature {
            let threshold = defaults.double(forKey: AlertSettings.temperatureThreshold)
            if temperature.update(isHigh: cpuTemperature >= threshold, isClear: cpuTemperature < threshold - 5) {
                Self.send(id: "temperature", title: "CPU a \(Format.temperature(cpuTemperature))",
                          body: "A temperatura está acima de \(Format.temperature(threshold)) há mais de 30 segundos.")
            }
        }
    }

    /// Inclui no aviso o processo que mais está usando CPU.
    private func notifyHighCPU(usage: Double) {
        Task.detached(priority: .utility) {
            let body = ProcessReader.top(by: .cpu, limit: 1).first
                .map { "\($0.name) está usando \(Int($0.cpu.rounded()))% de CPU." }
                ?? "O uso está alto há mais de 30 segundos."
            Self.send(id: "cpu", title: "CPU em \(Format.percent(usage))", body: body)
        }
    }

    nonisolated static func send(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Mesmo id: um aviso novo substitui o anterior do mesmo tipo
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    nonisolated static func isAuthorized() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// Mostra o aviso mesmo com o painel aberto (app ativo).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
