import AppKit
import Foundation
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configuration = Configuration.load()
    private lazy var coordinator = Coordinator.make(configuration: configuration)
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private let formatter: DateFormatter = { let value = DateFormatter(); value.dateStyle = .short; value.timeStyle = .medium; return value }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.title = "Teams: …"
        rebuild(Snapshot(runtime: RuntimeState(), missingSettings: configuration.missingSettings, isChecking: false, transitions: []))
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        task = Task { [weak self, coordinator] in
            await coordinator.restore()
            let snapshot = await coordinator.check()
            self?.complete(snapshot)
        }
        timer = Timer.scheduledTimer(withTimeInterval: configuration.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.start(force: false) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); task?.cancel() }
    @objc private func checkNow() { start(force: true) }
    @objc private func openLogs() { NSWorkspace.shared.open(AppPaths.logDirectory) }
    @objc private func openConfiguration() { try? FileManager.default.createDirectory(at: AppPaths.applicationSupport, withIntermediateDirectories: true); NSWorkspace.shared.open(AppPaths.applicationSupport) }

    private func start(force: Bool) {
        guard task == nil else { return }
        task = Task { [weak self, coordinator] in let snapshot = await coordinator.check(force: force); self?.complete(snapshot) }
    }
    private func complete(_ snapshot: Snapshot) {
        task = nil; rebuild(snapshot)
        for transition in snapshot.transitions {
            let content = UNMutableNotificationContent(); content.title = "MSTeamsStatusSender"
            content.body = "\(transition.destination) delivery \(transition.recovered ? "recovered" : "is failing")"
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
    private func rebuild(_ snapshot: Snapshot) {
        item.button?.title = "Teams: \(snapshot.runtime.teamsState?.rawValue ?? "Unknown")"
        let menu = NSMenu()
        add(menu, "Teams state: \(snapshot.runtime.teamsState?.rawValue ?? "Unknown")")
        add(menu, "Local status: \(snapshot.runtime.localState.rawValue)")
        add(menu, "External status: \(snapshot.runtime.externalState.rawValue)")
        add(menu, "Last check: \(date(snapshot.runtime.lastCheck))")
        add(menu, "Last local success: \(date(snapshot.runtime.lastLocalSuccess))")
        add(menu, "Last external success: \(date(snapshot.runtime.lastExternalSuccess))")
        add(menu, "Missing configuration: \(snapshot.missingSettings.isEmpty ? "None" : snapshot.missingSettings.joined(separator: ", "))")
        menu.addItem(.separator())
        action(menu, "Check Now", #selector(checkNow), "r")
        action(menu, "Open Logs", #selector(openLogs), "")
        action(menu, "Open Configuration Folder", #selector(openConfiguration), "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }
    private func add(_ menu: NSMenu, _ title: String) { let entry = NSMenuItem(title: title, action: nil, keyEquivalent: ""); entry.isEnabled = false; menu.addItem(entry) }
    private func action(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String) { let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key); entry.target = self; menu.addItem(entry) }
    private func date(_ value: Date?) -> String { value.map(formatter.string) ?? "Never" }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
    withExtendedLifetime(delegate) {}
}
