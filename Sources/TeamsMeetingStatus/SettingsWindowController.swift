import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let local = NSTextField()
    private let token = NSSecureTextField()
    private let webhook = NSTextField()
    private let status = NSTextField(labelWithString: "")
    private let onSave: (Configuration) -> Void

    init(configuration: Configuration, onSave: @escaping (Configuration) -> Void) {
        self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Teams Meeting Status for Home Assistant"
        window.center()
        local.stringValue = configuration.localBaseURL?.absoluteString ?? ""
        token.stringValue = configuration.localToken ?? ""
        webhook.stringValue = configuration.externalWebhookURL?.absoluteString ?? ""
        local.placeholderString = "http://homeassistant.local:8123/"
        token.placeholderString = "Long-lived access token"
        webhook.placeholderString = "https://example.test/webhook"
        [local, token, webhook].forEach { field in
            field.usesSingleLineMode = true
            field.maximumNumberOfLines = 1
            field.lineBreakMode = .byClipping
            field.controlSize = .large
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
            field.focusRingType = .default
            field.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        build()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func build() {
        guard let view = window?.contentView else { return }
        let title = NSTextField(labelWithString: "Configuration")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Home Assistant destinations and credentials")
        subtitle.textColor = .secondaryLabelColor
        let grid = NSGridView(views: [[label("Local URL"), local], [label("Access token"), token], [label("Webhook URL"), webhook]])
        grid.column(at: 0).width = 100
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 360
        grid.rowSpacing = 12
        let save = NSButton(title: "Save", target: self, action: #selector(saveConfiguration))
        save.keyEquivalent = "\r"
        let close = NSButton(title: "Cancel", target: self, action: #selector(closeWindow))
        let buttons = NSStackView(views: [close, save])
        buttons.spacing = 8
        let stack = NSStackView(views: [title, subtitle, grid, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24), buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor)])
    }

    private func label(_ value: String) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.alignment = .right
        return field
    }

    @objc private func saveConfiguration() {
        let text = "local_url=\"\(local.stringValue)\"\ntoken=\"\(token.stringValue)\"\nwebhook_url=\"\(webhook.stringValue)\"\n"
        let candidate = Configuration.parse(text)
        guard candidate.issues.isEmpty else { status.textColor = .systemRed; status.stringValue = candidate.issues.joined(separator: ", "); return }
        do {
            try FileManager.default.createDirectory(at: AppPaths.applicationSupport, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: AppPaths.configurationFile, options: .atomic)
            onSave(candidate)
            close()
        } catch { status.textColor = .systemRed; status.stringValue = error.localizedDescription }
    }

    @objc private func closeWindow() { close() }
}
