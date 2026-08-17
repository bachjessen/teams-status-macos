import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController {
    private let local = NSTextField()
    private let token = NSSecureTextField()
    private let webhook = NSTextField()
    private let externalEnabled = NSButton(checkboxWithTitle: "Send through external webhook", target: nil, action: nil)
    private let notificationsEnabled = NSButton(checkboxWithTitle: "Show delivery notifications", target: nil, action: nil)
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let onSave: (Configuration) -> Void
    private let checkInterval: TimeInterval

    init(configuration: Configuration, onSave: @escaping (Configuration) -> Void) {
        self.onSave = onSave
        self.checkInterval = configuration.checkInterval
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Teams Meeting Status for Home Assistant"
        window.center()
        local.stringValue = configuration.localBaseURL?.absoluteString ?? ""
        token.stringValue = configuration.localToken ?? ""
        webhook.stringValue = configuration.externalWebhookURL?.absoluteString ?? ""
        externalEnabled.state = configuration.externalEnabled ? .on : .off
        notificationsEnabled.state = configuration.notificationsEnabled ? .on : .off
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        local.placeholderString = "http://homeassistant.local/"
        token.placeholderString = "Long-lived access token"
        webhook.placeholderString = "https://hooks.nabu.casa/..."
        [local, token, webhook].forEach { field in
            field.usesSingleLineMode = true
            field.maximumNumberOfLines = 1
            field.lineBreakMode = .byClipping
            field.controlSize = .large
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
            field.focusRingType = .default
            field.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        externalEnabled.target = self
        externalEnabled.action = #selector(updateWebhookState)
        build()
        updateWebhookState()
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
        let subtitle = NSTextField(labelWithString: "Home Assistant destinations and app behavior")
        subtitle.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [label("Local URL"), local],
            [label("Access token"), token],
            [label("Webhook URL"), webhook]
        ])
        grid.column(at: 0).width = 110
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 410
        grid.rowSpacing = 12

        let webhookHelp = help("Use a Home Assistant Cloud (Nabu Casa) webhook URL when the Mac cannot reach the local Home Assistant URL.")
        let notificationHelp = help("Notifications are shown only when Home Assistant delivery begins failing or recovers. Meeting start and end events do not create notifications.")
        let loginHelp = help("Registers this app with macOS Login Items. You can also manage it in System Settings > General > Login Items.")

        let save = NSButton(title: "Save", target: self, action: #selector(saveConfiguration))
        save.keyEquivalent = "\r"
        let close = NSButton(title: "Cancel", target: self, action: #selector(closeWindow))
        let buttons = NSStackView(views: [close, save])
        buttons.spacing = 8

        let stack = NSStackView(views: [title, subtitle, grid, externalEnabled, webhookHelp, notificationsEnabled, notificationHelp, launchAtLogin, loginHelp, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }

    private func label(_ value: String) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.alignment = .right
        return field
    }

    private func help(_ value: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.maximumNumberOfLines = 2
        field.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return field
    }

    @objc private func updateWebhookState() {
        webhook.isEnabled = externalEnabled.state == .on
    }

    @objc private func saveConfiguration() {
        let text = "local_url=\"\(local.stringValue)\"\ntoken=\"\(token.stringValue)\"\nwebhook_url=\"\(webhook.stringValue)\"\ncheck_interval=\"\(checkInterval)\"\nnotifications_enabled=\"\(notificationsEnabled.state == .on)\"\nexternal_enabled=\"\(externalEnabled.state == .on)\"\n"
        let candidate = Configuration.parse(text)
        guard candidate.issues.isEmpty else {
            status.textColor = .systemRed
            status.stringValue = candidate.issues.joined(separator: ", ")
            return
        }
        do {
            try updateLaunchAtLogin()
            try FileManager.default.createDirectory(at: AppPaths.applicationSupport, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: AppPaths.configurationFile, options: .atomic)
            onSave(candidate)
            close()
        } catch {
            status.textColor = .systemRed
            status.stringValue = error.localizedDescription
        }
    }

    private func updateLaunchAtLogin() throws {
        let service = SMAppService.mainApp
        if launchAtLogin.state == .on, service.status != .enabled {
            try service.register()
        } else if launchAtLogin.state == .off, service.status == .enabled {
            try service.unregister()
        }
    }

    @objc private func closeWindow() { close() }
}
