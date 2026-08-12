import Foundation
import Darwin

public struct ProcessExecutionResult: Sendable, Equatable {
    public let terminationStatus: Int32
    public let standardOutput: Data
    public let standardError: Data
    public let processIdentifier: Int32

    public init(terminationStatus: Int32, standardOutput: Data, standardError: Data, processIdentifier: Int32) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.processIdentifier = processIdentifier
    }
}

public protocol ProcessExecuting: Sendable {
    func execute(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> ProcessExecutionResult
}

public struct BoundedProcessExecutor: ProcessExecuting {
    private let terminationGracePeriod: TimeInterval

    public init(terminationGracePeriod: TimeInterval = 0.25) {
        self.terminationGracePeriod = terminationGracePeriod
    }

    public func execute(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> ProcessExecutionResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            let state = ProcessExecutionState(process: process, output: output, errors: errors, continuation: continuation, gracePeriod: terminationGracePeriod)
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { process in state.processDidExit(status: process.terminationStatus) }
            state.startReaders()
            do {
                try process.run()
                try? output.fileHandleForWriting.close()
                try? errors.fileHandleForWriting.close()
                state.processDidStart(identifier: process.processIdentifier, timeout: timeout)
            } catch {
                state.startFailed(error)
            }
        }
    }
}

private final class ProcessExecutionState: @unchecked Sendable {
    private enum Winner { case pending, exit, timeout, startFailure }

    private let stateLock = NSLock()
    private let process: Process
    private let outputPipe: Pipe
    private let errorPipe: Pipe
    private let gracePeriod: TimeInterval
    private let outputQueue = DispatchQueue(label: "dk.bachjessen.msteamsstatussender.process-stdout")
    private let errorQueue = DispatchQueue(label: "dk.bachjessen.msteamsstatussender.process-stderr")
    private let cleanupQueue = DispatchQueue(label: "dk.bachjessen.msteamsstatussender.process-cleanup")
    private let readerGroup = DispatchGroup()
    private var continuation: CheckedContinuation<ProcessExecutionResult, Error>?
    private var output = Data()
    private var errors = Data()
    private var identifier: Int32 = 0
    private var winner: Winner = .pending
    private var terminationStatus: Int32?
    private var startError: Error?
    private var timeoutWorkItem: DispatchWorkItem?
    private var killWorkItem: DispatchWorkItem?
    private var terminationObserved = false
    private var cleanupScheduled = false

    init(process: Process, output: Pipe, errors: Pipe, continuation: CheckedContinuation<ProcessExecutionResult, Error>, gracePeriod: TimeInterval) {
        self.process = process
        self.outputPipe = output
        self.errorPipe = errors
        self.continuation = continuation
        self.gracePeriod = gracePeriod
    }

    func startReaders() {
        readerGroup.enter()
        outputQueue.async {
            self.output = self.outputPipe.fileHandleForReading.readDataToEndOfFile()
            self.readerGroup.leave()
        }
        readerGroup.enter()
        errorQueue.async {
            self.errors = self.errorPipe.fileHandleForReading.readDataToEndOfFile()
            self.readerGroup.leave()
        }
    }

    func processDidStart(identifier: Int32, timeout: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in self?.timeoutExpired() }
        stateLock.withLock {
            self.identifier = identifier
            timeoutWorkItem = item
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout), execute: item)
    }

    func startFailed(_ error: Error) {
        let won = stateLock.withLock { () -> Bool in
            guard winner == .pending else { return false }
            winner = .startFailure
            startError = error
            terminationObserved = true
            return true
        }
        guard won else { return }
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()
        scheduleCleanupWhenReady()
    }

    func processDidExit(status: Int32) {
        stateLock.withLock {
            if winner == .pending { winner = .exit }
            terminationStatus = status
            terminationObserved = true
        }
        scheduleCleanupWhenReady()
    }

    private func timeoutExpired() {
        let won = stateLock.withLock { () -> Bool in
            guard winner == .pending else { return false }
            winner = .timeout
            return true
        }
        guard won else { return }
        if process.isRunning { process.terminate() }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let pid = self.stateLock.withLock { self.identifier }
            if self.process.isRunning, pid > 0 { Darwin.kill(pid, SIGKILL) }
        }
        stateLock.withLock { killWorkItem = item }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + gracePeriod, execute: item)
    }

    private func scheduleCleanupWhenReady() {
        let shouldSchedule = stateLock.withLock { () -> Bool in
            guard terminationObserved, !cleanupScheduled else { return false }
            cleanupScheduled = true
            timeoutWorkItem?.cancel()
            killWorkItem?.cancel()
            return true
        }
        guard shouldSchedule else { return }
        readerGroup.notify(queue: cleanupQueue) { self.finishCleanup() }
    }

    private func finishCleanup() {
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
        process.terminationHandler = nil

        let completion = stateLock.withLock { () -> (CheckedContinuation<ProcessExecutionResult, Error>?, Winner, Int32?, Int32, Error?) in
            timeoutWorkItem = nil
            killWorkItem = nil
            let value = continuation
            continuation = nil
            return (value, winner, terminationStatus, identifier, startError)
        }
        guard let continuation = completion.0 else { return }
        switch completion.1 {
        case .timeout:
            continuation.resume(throwing: AppError.processTimeout)
        case .exit:
            continuation.resume(returning: ProcessExecutionResult(terminationStatus: completion.2 ?? -1, standardOutput: output, standardError: errors, processIdentifier: completion.3))
        case .startFailure:
            continuation.resume(throwing: completion.4 ?? AppError.command("Unable to start Teams detection command"))
        case .pending:
            continuation.resume(throwing: AppError.command("Process completed without a terminal state"))
        }
    }
}
