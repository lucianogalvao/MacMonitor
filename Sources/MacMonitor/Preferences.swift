import Foundation

/// Chaves no UserDefaults das preferências do painel e da barra de menus.
enum Preferences {
    static let layout = "panel.layout"
    /// Itens exibidos na barra de menus, salvos como "cpu,weather".
    static let menuBarItems = "menubar.items"
    /// Seções escondidas do painel: guardamos as escondidas para que seções novas apareçam por padrão.
    static let hiddenSections = "panel.hiddenSections"
}

enum PanelLayout: String, CaseIterable {
    case normal, compact

    var label: String {
        switch self {
        case .normal: "Normal"
        case .compact: "Compacto"
        }
    }

    static let panelWidth: CGFloat = 340

    /// Altura fixa do painel, para ele não mudar de tamanho ao trocar de aba ou
    /// abrir as configurações. A janela (StatusBarController) usa o mesmo valor.
    var panelHeight: CGFloat {
        switch self {
        case .normal: 740
        case .compact: 500
        }
    }

    static var current: PanelLayout {
        UserDefaults.standard.string(forKey: Preferences.layout).flatMap(PanelLayout.init) ?? .normal
    }
}

enum MenuBarItem: String, CaseIterable {
    case cpu, cpuTemperature, gpu, memory, network, weather

    static let defaultValue: Set<MenuBarItem> = [.cpu, .cpuTemperature, .weather]

    var title: String {
        switch self {
        case .cpu: "Uso da CPU"
        case .cpuTemperature: "Temperatura da CPU"
        case .gpu: "Uso da GPU"
        case .memory: "Memória"
        case .network: "Rede"
        case .weather: "Clima"
        }
    }
}

enum PanelSection: String, CaseIterable {
    case cpu, gpu, temperatures, memory, network, disk, battery

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .temperatures: "Temperaturas"
        case .memory: "Memória"
        case .network: "Rede"
        case .disk: "Disco"
        case .battery: "Bateria"
        }
    }
}

extension Set where Element: RawRepresentable, Element.RawValue == String {
    init(stored: String) {
        self.init(stored.split(separator: ",").compactMap { Element(rawValue: String($0)) })
    }

    var stored: String {
        map(\.rawValue).sorted().joined(separator: ",")
    }
}
