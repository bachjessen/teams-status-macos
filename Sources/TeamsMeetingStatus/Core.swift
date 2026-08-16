import Foundation

public enum MeetingState: String, Codable, Sendable, Equatable {
    case inMeeting = "In meeting"
    case notInMeeting = "Not in meeting"
    case unknown = "Unknown"
}

public enum DestinationState: String, Codable, Sendable, Equatable {
    case unconfigured, healthy, failing
}

public struct Configuration: Sendable, Equatable {
    public var localBaseURL: URL?
    public var localToken: String?
    public var externalWebhookURL: URL?
    public var issues: [String]
    public var checkInterval: TimeInterval
    public var externalInterval: TimeInterval
    public var notificationsEnabled: Bool
    public var externalEnabled: Bool

    public init(localBaseURL: URL? = nil, localToken: String? = nil, externalWebhookURL: URL? = nil, issues: [String] = [], checkInterval: TimeInterval = 30, externalInterval: TimeInterval = 300, notificationsEnabled: Bool = true, externalEnabled: Bool = false) {
        self.localBaseURL = localBaseURL
        self.localToken = localToken
        self.externalWebhookURL = externalWebhookURL
        self.issues = issues
        self.checkInterval = min(300, max(5, checkInterval))
        self.externalInterval = externalInterval
        self.notificationsEnabled = notificationsEnabled
        self.externalEnabled = externalEnabled
    }

    public var missingSettings: [String] {
        var result = issues
        if localBaseURL == nil { result.append("local_url") }
        if localToken?.isEmpty != false { result.append("token") }
        if externalEnabled && externalWebhookURL == nil { result.append("webhook_url") }
        return Array(Set(result)).sorted()
    }

    public static func load(from url: URL = AppPaths.configurationFile) -> Configuration {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return Configuration(issues: ["Configuration file not found"])
        }
        return parse(text)
    }

    public static func parse(_ text: String) -> Configuration {
        var values: [String: String] = [:]
        var issues: [String] = []
        for (offset, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line.removeFirst(7) }
            guard let equal = line.firstIndex(of: "=") else {
                issues.append("Malformed line \(offset + 1)")
                continue
            }
            let key = line[..<equal].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, let last = value.last, (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst(); value.removeLast()
            } else if let hash = value.firstIndex(of: "#") {
                value = value[..<hash].trimmingCharacters(in: .whitespaces)
            }
            if ["token", "local_url", "webhook_url", "check_interval", "notifications_enabled", "external_enabled"].contains(String(key)) { values[String(key)] = String(value) }
        }
        func httpURL(_ key: String) -> URL? {
            guard let string = values[key], !string.isEmpty else { return nil }
            guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
                issues.append("Malformed \(key)")
                return nil
            }
            return url
        }
        let interval = values["check_interval"].flatMap(TimeInterval.init) ?? 30
        let notificationsEnabled = values["notifications_enabled"].map { $0.lowercased() != "false" } ?? true
        let externalEnabled = values["external_enabled"].map { $0.lowercased() == "true" } ?? false
        return Configuration(localBaseURL: httpURL("local_url"), localToken: values["token"], externalWebhookURL: httpURL("webhook_url"), issues: issues, checkInterval: interval, notificationsEnabled: notificationsEnabled, externalEnabled: externalEnabled)
    }
}

public enum AppPaths {
    public static var applicationSupport: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TeamsMeetingStatus", isDirectory: true) }
    public static var configurationFile: URL { applicationSupport.appendingPathComponent(".env") }
    public static var stateFile: URL { applicationSupport.appendingPathComponent("state.json") }
    public static var logDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TeamsMeetingStatus", isDirectory: true) }
    public static var logFile: URL { logDirectory.appendingPathComponent("app.log") }
}

public protocol Logging: Sendable { func log(_ message: String) async }

public actor AppLogger: Logging {
    public static let shared = AppLogger()
    private let maximumBytes = 1_000_000
    public init() {}
    public func log(_ message: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: AppPaths.logDirectory, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: AppPaths.logFile.path)[.size]) as? NSNumber, size.intValue >= maximumBytes {
            let old = AppPaths.logDirectory.appendingPathComponent("app.log.1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: AppPaths.logFile, to: old)
        }
        let safe = message.replacingOccurrences(of: #"https?://[^\s]+"#, with: "<redacted-url>", options: .regularExpression)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(safe)\n"
        let data = Data(line.utf8)
        if fm.fileExists(atPath: AppPaths.logFile.path), let handle = try? FileHandle(forWritingTo: AppPaths.logFile) {
            defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data)
        } else { try? data.write(to: AppPaths.logFile, options: .atomic) }
    }
}

public protocol MeetingStateProviding: Sendable { func currentState() async throws -> MeetingState }
public protocol StatusSending: Sendable { func send(_ state: MeetingState) async throws }

public enum AppError: LocalizedError, Sendable, Equatable {
    case invalidResponse, httpStatus(Int), command(String), processTimeout, logAccessDenied
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid HTTP response"
        case .httpStatus(let code): return "HTTP \(code)"
        case .command(let text): return text
        case .processTimeout: return "Teams detection timed out"
        case .logAccessDenied: return "Log access denied"
        }
    }
}

public enum TeamsLogParser {
    public static func parse(_ text: String) -> MeetingState {
        guard let event = text.split(separator: "\n").last(where: { $0.contains("Microsoft Teams Call in progress") }) else { return .unknown }
        if event.contains("Created") { return .inMeeting }
        if event.contains("Released") { return .notInMeeting }
        return .unknown
    }
}

public struct PowerdProvider: MeetingStateProviding {
    private let executor: any ProcessExecuting
    private let timeout: TimeInterval

    public init(executor: any ProcessExecuting = BoundedProcessExecutor(), timeout: TimeInterval = 10) {
        self.executor = executor
        self.timeout = timeout
    }

    public func currentState() async throws -> MeetingState {
        let result = try await executor.execute(
            executableURL: URL(fileURLWithPath: "/usr/bin/log"),
            arguments: ["show", "--style", "syslog", "--last", "30m", "--process", "powerd"],
            timeout: timeout
        )
        guard result.terminationStatus == 0 else {
            let errorText = String(decoding: result.standardError, as: UTF8.self)
            if errorText.localizedCaseInsensitiveContains("Could not open local log store") || errorText.localizedCaseInsensitiveContains("Operation not permitted") {
                throw AppError.logAccessDenied
            }
            throw AppError.command("Teams detection command exited with status \(result.terminationStatus)")
        }
        return TeamsLogParser.parse(String(decoding: result.standardOutput, as: UTF8.self))
    }
}

public struct HTTPSender: StatusSending {
    public enum Destination: Sendable { case local(URL, String), external(URL) }
    private let destination: Destination
    private let session: URLSession
    public init(destination: Destination, session: URLSession? = nil) {
        self.destination = destination
        if let session { self.session = session } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            self.session = URLSession(configuration: configuration)
        }
    }
    public func send(_ state: MeetingState) async throws {
        var request: URLRequest; var payload: [String: Any] = ["state": state.rawValue]
        switch destination {
        case .local(let base, let token):
            request = URLRequest(url: base.appendingPathComponent("api/states/input_text.teams_meeting_status"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            payload["attributes"] = ["friendly_name": "Teams Meeting Status"]
        case .external(let url): request = URLRequest(url: url)
        }
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw AppError.httpStatus(http.statusCode) }
    }
}

public struct RuntimeState: Codable, Sendable, Equatable {
    public var teamsState: MeetingState?
    public var lastCheck: Date?
    public var lastLocalSuccess: Date?
    public var lastExternalSuccess: Date?
    public var lastExternalAttempt: Date?
    public var localState: DestinationState
    public var externalState: DestinationState
    public var detectionError: String?
    public init(teamsState: MeetingState? = nil, lastCheck: Date? = nil, lastLocalSuccess: Date? = nil, lastExternalSuccess: Date? = nil, lastExternalAttempt: Date? = nil, localState: DestinationState = .unconfigured, externalState: DestinationState = .unconfigured, detectionError: String? = nil) {
        self.teamsState = teamsState; self.lastCheck = lastCheck; self.lastLocalSuccess = lastLocalSuccess; self.lastExternalSuccess = lastExternalSuccess; self.lastExternalAttempt = lastExternalAttempt; self.localState = localState; self.externalState = externalState; self.detectionError = detectionError
    }
}

public protocol StatePersisting: Sendable { func load() async -> RuntimeState; func save(_ state: RuntimeState) async }
public actor JSONStateStore: StatePersisting {
    public init() {}
    public func load() -> RuntimeState { (try? JSONDecoder().decode(RuntimeState.self, from: Data(contentsOf: AppPaths.stateFile))) ?? RuntimeState() }
    public func save(_ state: RuntimeState) {
        try? FileManager.default.createDirectory(at: AppPaths.applicationSupport, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: AppPaths.stateFile, options: .atomic) }
    }
}

public struct Snapshot: Sendable, Equatable { public let runtime: RuntimeState; public let missingSettings: [String]; public let isChecking: Bool; public let transitions: [HealthTransition] }
public struct HealthTransition: Sendable, Equatable { public let destination: String; public let recovered: Bool }

public actor Coordinator {
    private let configuration: Configuration; private let provider: any MeetingStateProviding
    private let local: (any StatusSending)?; private let external: (any StatusSending)?; private let store: any StatePersisting; private let logger: any Logging
    private let now: @Sendable () -> Date; private var runtime: RuntimeState; private var checking = false
    public init(configuration: Configuration, provider: any MeetingStateProviding, local: (any StatusSending)? = nil, external: (any StatusSending)? = nil, store: any StatePersisting = JSONStateStore(), logger: any Logging = AppLogger.shared, initialState: RuntimeState = RuntimeState(), now: @escaping @Sendable () -> Date = { Date() }) {
        var preparedRuntime = initialState
        if local != nil && preparedRuntime.localState == .unconfigured { preparedRuntime.localState = .healthy }
        if external != nil && preparedRuntime.externalState == .unconfigured { preparedRuntime.externalState = .healthy }
        self.configuration = configuration; self.provider = provider; self.local = local; self.external = external; self.store = store; self.logger = logger; self.runtime = preparedRuntime; self.now = now
    }
    public static func make(configuration: Configuration, provider: any MeetingStateProviding = PowerdProvider()) -> Coordinator {
        let local = configuration.localBaseURL.flatMap { url in configuration.localToken.map { HTTPSender(destination: .local(url, $0)) } }
        let external = configuration.externalEnabled ? configuration.externalWebhookURL.map { HTTPSender(destination: .external($0)) } : nil
        return Coordinator(configuration: configuration, provider: provider, local: local, external: external)
    }
    public func restore() async { runtime = await store.load() }
    public func check(force: Bool = false) async -> Snapshot {
        guard !checking else { return Snapshot(runtime: runtime, missingSettings: configuration.missingSettings, isChecking: true, transitions: []) }
        checking = true; defer { checking = false }
        var transitions: [HealthTransition] = []
        do {
            let detectedState = try await provider.currentState()
            let state = detectedState == .unknown ? runtime.teamsState ?? .unknown : detectedState
            let date = now(); let initial = runtime.teamsState == nil; let changed = runtime.teamsState != state
            runtime.lastCheck = date
            runtime.detectionError = nil
            if force || initial || changed { await attempt(local, name: "Local", state: state, date: date, transitions: &transitions) }
            let due = runtime.lastExternalAttempt.map { date.timeIntervalSince($0) >= configuration.externalInterval } ?? true
            if force || initial || changed || due { runtime.lastExternalAttempt = date; await attempt(external, name: "External", state: state, date: date, transitions: &transitions) }
            runtime.teamsState = state
        } catch {
            runtime.detectionError = error is AppError && error as? AppError == .logAccessDenied ? "Log access denied" : "Detection failed"
            await logger.log("Check failed: \(error.localizedDescription)")
        }
        await store.save(runtime)
        return Snapshot(runtime: runtime, missingSettings: configuration.missingSettings, isChecking: false, transitions: transitions)
    }
    private func attempt(_ sender: (any StatusSending)?, name: String, state: MeetingState, date: Date, transitions: inout [HealthTransition]) async {
        guard let sender else { return }
        let old = name == "Local" ? runtime.localState : runtime.externalState
        do {
            try await sender.send(state)
            if name == "Local" { runtime.localState = .healthy; runtime.lastLocalSuccess = date } else { runtime.externalState = .healthy; runtime.lastExternalSuccess = date }
            if old == .failing { transitions.append(HealthTransition(destination: name, recovered: true)) }
            await logger.log("\(name) delivery succeeded")
        } catch {
            if name == "Local" { runtime.localState = .failing } else { runtime.externalState = .failing }
            if old == .healthy { transitions.append(HealthTransition(destination: name, recovered: false)) }
            await logger.log("\(name) delivery failed: \(error.localizedDescription)")
        }
    }
}
