import AppKit
import SwiftUI

/// Ícone na barra de menus e o painel que abre ao clicar nele.
///
/// Substitui o MenuBarExtra do SwiftUI, que não lida com o painel mudando de
/// tamanho: ele mantinha a borda de baixo fixa (descolando o painel da barra) e
/// desfazia qualquer ajuste de posição. Aqui a janela é nossa: abre logo abaixo
/// do ícone e, ao mudar de altura, mantém o topo no lugar.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let system: SystemMonitor
    private let panel = PanelWindow()
    private let panelContent: NSHostingView<PanelView>
    private var clickOutsideMonitor: Any?
    private var layout = PanelLayout.current
    private var defaultsObserver: NSObjectProtocol?

    init(system: SystemMonitor, weather: WeatherService) {
        self.system = system
        panelContent = NSHostingView(rootView: PanelView(system: system, weather: weather))
        super.init()
        setUpStatusItem(weather: weather)
        setUpPanel()

        // O tamanho do painel vem do layout escolhido, não de medir o SwiftUI
        // (que não avisa de forma confiável quando o conteúdo muda de tamanho)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main garante a thread principal
            MainActor.assumeIsolated {
                self?.layoutPreferenceChanged()
            }
        }
    }

    private func setUpStatusItem(weather: WeatherService) {
        guard let button = statusItem.button else { return }

        let label = PassthroughHostingView(rootView: StatusLabel(system: system, weather: weather) { [weak self] width in
            self?.statusItem.length = ceil(width) + 10
        })
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])

        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    private func setUpPanel() {
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        // Sem restrições de tamanho vindas do SwiftUI: quem dimensiona a janela somos nós
        panelContent.sizingOptions = []
        panelContent.autoresizingMask = [.width, .height]
        background.addSubview(panelContent)

        panel.contentView = background
        panel.onClose = { [weak self] in self?.hidePanel() }
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        positionBelowStatusItem()
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        system.panelOpened()

        // Clique fora do app (outra janela, mesa, outro ícone da barra) fecha o painel
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        system.panelClosed()
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
        }
        clickOutsideMonitor = nil
    }

    private var contentSize: NSSize {
        NSSize(width: PanelLayout.panelWidth, height: layout.panelHeight)
    }

    private func layoutPreferenceChanged() {
        let current = PanelLayout.current
        guard current != layout else { return }
        layout = current
        fitPanelKeepingTop()
    }

    /// Topo logo abaixo do ícone, alinhado à esquerda dele, sem sair da tela.
    private func positionBelowStatusItem() {
        guard let buttonWindow = statusItem.button?.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let size = contentSize
        let visible = screen.visibleFrame
        let x = max(visible.minX + 8, min(buttonWindow.frame.minX, visible.maxX - size.width - 8))
        let top = buttonWindow.frame.minY - 4
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    /// Ao trocar de layout com o painel aberto, a altura muda e o topo fica onde está.
    private func fitPanelKeepingTop() {
        guard panel.isVisible else { return }
        let size = contentSize
        let frame = panel.frame
        guard size != frame.size else { return }
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
                       display: true)
        panel.invalidateShadow()
    }
}

/// Janela do painel: sem borda, não ativa o app (como um menu), mas aceita teclado
/// para o campo de cidade.
final class PanelWindow: NSPanel {
    var onClose: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }

    /// O app nunca fica ativo, então o menu Editar pode não receber os atalhos;
    /// eles vão direto para o campo em foco. Desfazer/Refazer chegam ao `undoManager` da janela.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let action: Selector? = switch (flags, event.charactersIgnoringModifiers?.lowercased()) {
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        case (.command, "q"): #selector(NSApplication.terminate(_:))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Esc fecha o painel.
    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }
}

/// Deixa o clique passar para o botão da barra de menus.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Rótulo da barra de menus, informando a largura para o ícone acompanhar o texto.
struct StatusLabel: View {
    let system: SystemMonitor
    let weather: WeatherService
    let onWidthChange: (CGFloat) -> Void

    var body: some View {
        MenuBarLabel(system: system, weather: weather)
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { onWidthChange(proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, width in onWidthChange(width) }
            })
    }
}
