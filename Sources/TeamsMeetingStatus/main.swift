import AppKit
import Foundation
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var configuration = Configuration.load()
    private var coordinator: Coordinator!
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var settingsWindowController: SettingsWindowController?
    private let formatter: DateFormatter = { let value = DateFormatter(); value.dateStyle = .short; value.timeStyle = .medium; return value }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = Coordinator.make(configuration: configuration)
        item.button?.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Teams status pending")
        item.button?.image?.isTemplate = true
        rebuild(Snapshot(runtime: RuntimeState(), missingSettings: configuration.missingSettings, isChecking: false, transitions: []))
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let activeCoordinator = coordinator!
        task = Task { [weak self, activeCoordinator] in
            await activeCoordinator.restore()
            let snapshot = await activeCoordinator.check()
            self?.complete(snapshot)
        }
        timer = Timer.scheduledTimer(withTimeInterval: configuration.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.start(force: false) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); task?.cancel() }
    @objc private func checkNow() { start(force: true) }
    @objc private func openLogs() { NSWorkspace.shared.open(AppPaths.logDirectory) }
    @objc private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func openConfiguration() {
        if let settingsWindowController { settingsWindowController.present(); return }
        let controller = SettingsWindowController(configuration: configuration) { [weak self] candidate in
            guard let self else { return }
            configuration = candidate
            coordinator = Coordinator.make(configuration: candidate)
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: candidate.checkInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.start(force: false) }
            }
            start(force: true)
        }
        settingsWindowController = controller
        controller.present()
    }

    private func start(force: Bool) {
        guard task == nil else { return }
        let activeCoordinator = coordinator!
        task = Task { [weak self, activeCoordinator] in let snapshot = await activeCoordinator.check(force: force); self?.complete(snapshot) }
    }
    private func complete(_ snapshot: Snapshot) {
        task = nil; rebuild(snapshot)
        if Bundle.main.bundleURL.pathExtension == "app" {
            for transition in snapshot.transitions {
                let content = UNMutableNotificationContent(); content.title = "Teams Meeting Status for Home Assistant"
                content.body = "\(transition.destination) delivery \(transition.recovered ? "recovered" : "is failing")"
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }
    private func rebuild(_ snapshot: Snapshot) {
        let state = snapshot.runtime.teamsState ?? .unknown
        let symbolName: String
        switch state {
        case .inMeeting: symbolName = "video.fill"
        case .notInMeeting: symbolName = "video.slash"
        case .unknown: symbolName = "questionmark.circle"
        }
        item.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Teams: \(state.rawValue)")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Teams: \(state.rawValue)"

        let menu = NSMenu()
        if let detectionError = snapshot.runtime.detectionError {
            add(menu, "Status unavailable: \(detectionError)")
        } else {
            add(menu, "Status: \(state.rawValue)")
        }
        add(menu, "Home Assistant: \(destinationLabel(snapshot.runtime.localState))")
        if configuration.externalEnabled {
            add(menu, "External webhook: \(destinationLabel(snapshot.runtime.externalState))")
        }
        add(menu, "Last checked: \(relativeDate(snapshot.runtime.lastCheck))")
        if !snapshot.missingSettings.isEmpty {
            add(menu, "Configuration required")
        }
        menu.addItem(.separator())
        action(menu, "Check Now", #selector(checkNow), "r")
        action(menu, "Settings…", #selector(openConfiguration), ",")
        if snapshot.runtime.detectionError == "Log access denied" {
            action(menu, "Open Privacy Settings…", #selector(openPrivacySettings), "")
        }
        action(menu, "Open Logs", #selector(openLogs), "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }
    private func add(_ menu: NSMenu, _ title: String) { let entry = NSMenuItem(title: title, action: nil, keyEquivalent: ""); entry.isEnabled = false; menu.addItem(entry) }
    private func action(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String) { let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key); entry.target = self; menu.addItem(entry) }
    private func destinationLabel(_ state: DestinationState) -> String {
        switch state {
        case .healthy: return "Connected"
        case .failing: return "Error"
        case .unconfigured: return "Not configured"
        }
    }
    private func relativeDate(_ value: Date?) -> String {
        guard let value else { return "Never" }
        let elapsed = max(0, Date().timeIntervalSince(value))
        if elapsed < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: value, relativeTo: Date())
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)

    let mainMenu = NSMenu()
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenuItem.submenu = editMenu
    application.mainMenu = mainMenu
    application.run()
    withExtendedLifetime(delegate) {}
}
