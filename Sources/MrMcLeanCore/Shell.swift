import Foundation

/// Minimal `Process` wrapper. Runs a command off the calling thread, honours
/// task cancellation, and enforces a wall-clock timeout by terminating the child.
public enum Shell {
    public struct Result: Sendable {
        public var stdout: String
        public var stderr: String
        public var code: Int32
        public var timedOut: Bool
    }

    public static func run(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval = 60,
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) async -> String {
        await result(launchPath, arguments, timeout: timeout,
                     environment: environment, currentDirectory: currentDirectory).stdout
    }

    public static func result(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval = 60,
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) async -> Result {
        let box = ProcessBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard FileManager.default.isExecutableFile(atPath: launchPath) else {
                        continuation.resume(returning: Result(stdout: "", stderr: "not executable: \(launchPath)", code: -1, timedOut: false))
                        return
                    }
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: launchPath)
                    process.arguments = arguments
                    if let environment { process.environment = environment }
                    if let currentDirectory { process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory) }

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    box.attach(process)

                    var outData = Data()
                    var errData = Data()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global().async {
                        errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                        group.leave()
                    }

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(returning: Result(stdout: "", stderr: "\(error)", code: -1, timedOut: false))
                        return
                    }

                    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                    timer.schedule(deadline: .now() + timeout)
                    timer.setEventHandler {
                        if process.isRunning {
                            box.markTimedOut()
                            process.terminate()
                        }
                    }
                    timer.resume()

                    process.waitUntilExit()
                    timer.cancel()
                    group.wait()

                    continuation.resume(returning: Result(
                        stdout: String(decoding: outData, as: UTF8.self),
                        stderr: String(decoding: errData, as: UTF8.self),
                        code: process.terminationStatus,
                        timedOut: box.didTimeOut
                    ))
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var timedOut = false

    func attach(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
    }

    func terminate() {
        lock.lock(); defer { lock.unlock() }
        if process?.isRunning == true { process?.terminate() }
    }

    func markTimedOut() {
        lock.lock(); defer { lock.unlock() }
        timedOut = true
    }

    var didTimeOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return timedOut
    }
}
