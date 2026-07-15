import Foundation

public enum ClaudeCLIError: Error, LocalizedError, Equatable {
    /// No `claude` executable could be located on this machine.
    case notInstalled
    /// The process could not be spawned.
    case launchFailed(String)
    /// The run exceeded its time budget and was terminated.
    case timedOut
    /// The CLI exited non-zero and produced no usable result.
    case nonZeroExit(code: Int32, stderr: String)
    /// Output could not be parsed into a result.
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The `claude` command isn't installed or isn't on PATH. Install Claude Code and try again."
        case .launchFailed(let m):
            return "Couldn't start Claude Code: \(m)"
        case .timedOut:
            return "Claude Code took too long and was stopped."
        case .nonZeroExit(let code, let stderr):
            let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Claude Code exited with code \(code)." + (tail.isEmpty ? "" : "\n\(tail)")
        case .decodeFailed(let raw):
            return "Couldn't read Claude Code's response.\n\(raw.prefix(400))"
        }
    }
}

/// Drives the *local* `claude` CLI in headless (`--print`) mode. This is the
/// one place AgentKit executes anything — everything else in the package is
/// strictly read-only. It shells out to the binary the user already installed
/// and authenticated, so there is no API key and no network code here: the CLI
/// uses its own credentials.
public struct ClaudeCLI: Sendable {
    public let executableURL: URL?

    public init(executableURL: URL? = ClaudeCLI.resolveExecutable()) {
        self.executableURL = executableURL
    }

    public var isAvailable: Bool { executableURL != nil }

    /// Locates the `claude` binary. Honors `AGENTBAR_CLAUDE_BIN`, then PATH,
    /// then the usual install locations. Fully injectable so it's unit-testable
    /// without touching the real filesystem.
    public static func resolveExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let override = environment["AGENTBAR_CLAUDE_BIN"], !override.isEmpty, isExecutable(override) {
            return URL(fileURLWithPath: override)
        }
        var candidates: [String] = []
        if let path = environment["PATH"] {
            for dir in path.split(separator: ":") where !dir.isEmpty {
                candidates.append("\(dir)/claude")
            }
        }
        candidates += [
            home.appendingPathComponent(".claude/local/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/opt/node22/bin/claude",
        ]
        for c in candidates where isExecutable(c) {
            return URL(fileURLWithPath: c)
        }
        return nil
    }

    // MARK: - One-shot

    /// Runs the request to completion and returns the final result. The prompt
    /// is delivered over stdin, so length is not a concern.
    public func run(_ req: ClaudeRequest, timeout: TimeInterval? = 180) async throws -> ClaudeResult {
        guard let exe = executableURL else { throw ClaudeCLIError.notInstalled }
        let args = req.arguments(streaming: false)
        let prompt = req.prompt
        let cwd = req.cwd

        let outcome: ProcessOutcome = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let r = try ClaudeCLI.runProcess(exe: exe, args: args, cwd: cwd,
                                                     stdin: prompt, timeout: timeout, onLine: nil)
                    cont.resume(returning: r)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        // The CLI can exit non-zero yet still emit a well-formed error result;
        // prefer parsing the JSON, and only fall back to the exit code.
        if let parsed = try? ClaudeResult.parse(json: outcome.stdout) { return parsed }
        if outcome.status != 0 {
            throw ClaudeCLIError.nonZeroExit(code: outcome.status,
                                             stderr: String(data: outcome.stderr, encoding: .utf8) ?? "")
        }
        return try ClaudeResult.parse(json: outcome.stdout) // throws decodeFailed with the raw bytes
    }

    // MARK: - Streaming

    /// Streams events as the run progresses (system init, assistant text chunks,
    /// tool calls, and the final result). Ideal for a live UI. Cancelling the
    /// consuming task terminates the child process.
    public func stream(_ req: ClaudeRequest, timeout: TimeInterval? = 600)
        -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let exe = executableURL else {
                continuation.finish(throwing: ClaudeCLIError.notInstalled)
                return
            }
            let args = req.arguments(streaming: true)
            let prompt = req.prompt
            let cwd = req.cwd

            DispatchQueue.global(qos: .userInitiated).async {
                var sawResult = false
                do {
                    let r = try ClaudeCLI.runProcess(exe: exe, args: args, cwd: cwd,
                                                     stdin: prompt, timeout: timeout) { line in
                        for ev in ClaudeStreamEvent.parse(line: line) {
                            if case .result = ev { sawResult = true }
                            continuation.yield(ev)
                        }
                    }
                    if !sawResult, r.status != 0 {
                        let err = String(data: r.stderr, encoding: .utf8) ?? ""
                        continuation.finish(throwing: ClaudeCLIError.nonZeroExit(code: r.status, stderr: err))
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Process plumbing

    private struct ProcessOutcome {
        let stdout: Data
        let stderr: Data
        let status: Int32
    }

    /// Launches the process, feeds `stdin`, and collects output. When `onLine`
    /// is provided, stdout is delivered line-by-line as it arrives (streaming);
    /// otherwise it is buffered to completion. stderr is always drained on a
    /// separate queue so a large error stream can't deadlock the child.
    private static func runProcess(exe: URL, args: [String], cwd: URL?, stdin: String,
                                   timeout: TimeInterval?,
                                   onLine: ((String) -> Void)?) throws -> ProcessOutcome {
        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        if let cwd { proc.currentDirectoryURL = cwd }

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let errQueue = DispatchQueue(label: "agentbar.claude.stderr")
        let errBox = DataBox()
        errQueue.async { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile() }

        do { try proc.run() } catch { throw ClaudeCLIError.launchFailed(error.localizedDescription) }

        let writeHandle = inPipe.fileHandleForWriting
        writeHandle.write(Data(stdin.utf8))
        try? writeHandle.close()

        let timedOut = FlagBox()
        var watchdog: DispatchWorkItem?
        if let timeout {
            let item = DispatchWorkItem { timedOut.value = true; proc.terminate() }
            watchdog = item
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        }

        let stdout: Data
        if let onLine {
            stdout = readLines(from: outPipe.fileHandleForReading, onLine: onLine)
        } else {
            stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
        }

        proc.waitUntilExit()
        watchdog?.cancel()
        errQueue.sync {} // ensure stderr capture has completed

        if timedOut.value { throw ClaudeCLIError.timedOut }
        return ProcessOutcome(stdout: stdout, stderr: errBox.data, status: proc.terminationStatus)
    }

    /// Reads a file handle to EOF, invoking `onLine` for each complete
    /// newline-terminated line as it arrives, and returns the full bytes read.
    private static func readLines(from handle: FileHandle, onLine: (String) -> Void) -> Data {
        var buffer = Data()
        var all = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break } // EOF
            all.append(chunk)
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8) { onLine(line) }
            }
        }
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) { onLine(line) }
        return all
    }
}

/// Tiny reference boxes so background closures can hand values back without
/// tripping the concurrency checker on captured `var`s.
private final class DataBox: @unchecked Sendable { var data = Data() }
private final class FlagBox: @unchecked Sendable { var value = false }
