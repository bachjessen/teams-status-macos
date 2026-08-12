import XCTest
@testable import MSTeamsStatusSender

private actor Provider: MeetingStateProviding {
    var states: [MeetingState]; var delay: UInt64
    init(_ states: [MeetingState], delay: UInt64 = 0) { self.states = states; self.delay = delay }
    func currentState() async throws -> MeetingState { if delay > 0 { try await Task.sleep(nanoseconds: delay) }; return states.count > 1 ? states.removeFirst() : states[0] }
}
private actor Sender: StatusSending {
    var values: [MeetingState] = []; var shouldFail = false
    func send(_ state: MeetingState) async throws { if shouldFail { throw AppError.httpStatus(500) }; values.append(state) }
    func count() -> Int { values.count }; func fail(_ value: Bool) { shouldFail = value }
}
private actor MemoryStore: StatePersisting { var value = RuntimeState(); private(set) var loads = 0; private(set) var saves = 0; func load() -> RuntimeState { loads += 1; return value }; func save(_ state: RuntimeState) { saves += 1; value = state }; func counts() -> (Int, Int) { (loads, saves) } }
private actor MemoryLogger: Logging { private(set) var messages: [String] = []; func log(_ message: String) { messages.append(message) }; func count() -> Int { messages.count } }
private struct StubExecutor: ProcessExecuting {
    let result: Result<ProcessExecutionResult, Error>
    func execute(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> ProcessExecutionResult { try result.get() }
}
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var value = Date(timeIntervalSince1970: 0)
    func now() -> Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}

final class CoreTests: XCTestCase {
    func testEnvParsingAndQuotedValues() { let c = Configuration.parse("token='abc def'\nlocal_url=\"http://ha.local:8123/\"\nwebhook_url=https://example.test/hook\n"); XCTAssertEqual(c.localToken, "abc def"); XCTAssertEqual(c.localBaseURL?.host, "ha.local"); XCTAssertTrue(c.issues.isEmpty) }
    func testMalformedURLs() { let c = Configuration.parse("local_url=hello\nwebhook_url=ftp://example.test/a\n"); XCTAssertNil(c.localBaseURL); XCTAssertNil(c.externalWebhookURL); XCTAssertEqual(c.issues.count, 2) }
    func testMissingSettings() { XCTAssertEqual(Configuration.parse("").missingSettings, ["local_url", "token", "webhook_url"]) }
    func testTeamsLogParsing() { XCTAssertEqual(TeamsLogParser.parse("x Microsoft Teams Call in progress Created"), .inMeeting); XCTAssertEqual(TeamsLogParser.parse("x Microsoft Teams Call in progress Released"), .notInMeeting); XCTAssertEqual(TeamsLogParser.parse("none"), .unknown) }
    func testInitialDeliveryAndStateChanges() async {
        let l = Sender(), e = Sender(), p = Provider([.notInMeeting, .notInMeeting, .inMeeting]); let clock = TestClock()
        let c = Coordinator(configuration: Configuration(externalInterval: 300), provider: p, local: l, external: e, store: MemoryStore(), logger: MemoryLogger(), now: { clock.now() })
        _ = await c.check(); clock.advance(30); _ = await c.check(); clock.advance(30); _ = await c.check()
        let localCount = await l.count(); let externalCount = await e.count()
        XCTAssertEqual(localCount, 2); XCTAssertEqual(externalCount, 2)
    }
    func testExactExternalBoundaryAndFailedAttemptThrottle() async {
        let e = Sender(), p = Provider([.notInMeeting]); let clock = TestClock()
        let c = Coordinator(configuration: Configuration(externalInterval: 300), provider: p, external: e, store: MemoryStore(), logger: MemoryLogger(), now: { clock.now() })
        await e.fail(true); _ = await c.check(); clock.advance(30); _ = await c.check(); let failedCount = await e.count(); XCTAssertEqual(failedCount, 0)
        clock.advance(270); await e.fail(false); _ = await c.check(); let recoveredCount = await e.count(); XCTAssertEqual(recoveredCount, 1)
    }
    func testIndependentHealth() async {
        let l = Sender(), e = Sender(); await e.fail(true)
        let c = Coordinator(configuration: Configuration(), provider: Provider([.inMeeting]), local: l, external: e, store: MemoryStore(), logger: MemoryLogger())
        let s = await c.check(); XCTAssertEqual(s.runtime.localState, .healthy); XCTAssertEqual(s.runtime.externalState, .failing)
    }
    func testPowerdProviderSuccessfulProcessCompletion() async throws {
        let output = Data("x Microsoft Teams Call in progress Created\n".utf8)
        let executor = StubExecutor(result: .success(ProcessExecutionResult(terminationStatus: 0, standardOutput: output, standardError: Data(), processIdentifier: 10)))
        let state = try await PowerdProvider(executor: executor, timeout: 1).currentState()
        XCTAssertEqual(state, .inMeeting)
    }

    func testPowerdProviderUnsuccessfulExitDoesNotExposeOutput() async {
        let secret = Data("private unified log content".utf8)
        let executor = StubExecutor(result: .success(ProcessExecutionResult(terminationStatus: 7, standardOutput: secret, standardError: secret, processIdentifier: 10)))
        do {
            _ = try await PowerdProvider(executor: executor, timeout: 1).currentState()
            XCTFail("Expected unsuccessful exit")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Teams detection command exited with status 7")
            XCTAssertFalse(error.localizedDescription.contains("private unified log content"))
        }
    }

    func testTimeoutFollowedByImmediateSIGTERMExitReturnsTimeout() async {
        do {
            _ = try await BoundedProcessExecutor().execute(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "trap 'exit 0' TERM; while true; do sleep 0.01; done"], timeout: 0.05)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? AppError, .processTimeout)
        }
    }

    func testTimeoutRequiringSIGKILLReturnsTimeout() async {
        do {
            _ = try await BoundedProcessExecutor(terminationGracePeriod: 0.05).execute(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "trap '' TERM; while true; do sleep 0.01; done"], timeout: 0.05)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? AppError, .processTimeout)
        }
    }

    func testNormalExitImmediatelyBeforeTimeoutReturnsResult() async throws {
        let result = try await BoundedProcessExecutor().execute(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 0.02; exit 7"], timeout: 0.2)
        XCTAssertEqual(result.terminationStatus, 7)
    }

    func testBoundedExecutorDrainsLargeStdoutAndStderr() async throws {
        let script = "head -c 200000 /dev/zero; head -c 200000 /dev/zero >&2"
        let result = try await BoundedProcessExecutor().execute(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], timeout: 5)
        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.standardOutput.count, 200_000)
        XCTAssertEqual(result.standardError.count, 200_000)
    }

    func testTrailingOutputAndErrorBeforeExitAreRetained() async throws {
        let result = try await BoundedProcessExecutor().execute(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf trailing-out; printf trailing-error >&2"], timeout: 1)
        XCTAssertEqual(String(decoding: result.standardOutput, as: UTF8.self), "trailing-out")
        XCTAssertEqual(String(decoding: result.standardError, as: UTF8.self), "trailing-error")
    }

    func testStartFailureClosesReadersAndReturnsError() async {
        do {
            _ = try await BoundedProcessExecutor().execute(executableURL: URL(fileURLWithPath: "/path/that/does/not/exist"), arguments: [], timeout: 1)
            XCTFail("Expected start failure")
        } catch {
            XCTAssertFalse(error is AppError && (error as? AppError) == .processTimeout)
        }
    }

    func testExitTimeoutRacesCompleteExactlyOnce() async {
        for _ in 0..<30 {
            do {
                _ = try await BoundedProcessExecutor(terminationGracePeriod: 0.02).execute(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 0.02"], timeout: 0.02)
            } catch {
                XCTAssertEqual(error as? AppError, .processTimeout)
            }
        }
    }

    func testTestsUseInjectedLoggerAndStateStore() async {
        let logger = MemoryLogger(), store = MemoryStore(), sender = Sender()
        await sender.fail(true)
        let coordinator = Coordinator(configuration: Configuration(), provider: Provider([.inMeeting]), local: sender, store: store, logger: logger)
        _ = await coordinator.check()
        let logCount = await logger.count(), counts = await store.counts()
        XCTAssertEqual(logCount, 1)
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 1)
    }
    func testOverlappingChecksArePrevented() async {
        let l = Sender(); let c = Coordinator(configuration: Configuration(), provider: Provider([.unknown], delay: 200_000_000), local: l, store: MemoryStore(), logger: MemoryLogger())
        async let first = c.check(); try? await Task.sleep(nanoseconds: 20_000_000); let second = await c.check(); _ = await first
        let localCount = await l.count()
        XCTAssertTrue(second.isChecking); XCTAssertEqual(localCount, 1)
    }
}
