import Foundation

/// Runs a `command` module: one process per request, request on stdin, text streamed from stdout.
///
/// The process starts in the module folder with the user's login-shell PATH, so tools installed by
/// Homebrew, npm or pipx resolve the same way they do in Terminal. It runs in its own process group;
/// cancelling (closing the popup) or timing out stops the whole group.
struct CommandRunner {
    var home: YisiHome = .shared
    static let outputLimit = 1_048_576

    func run(_ handler: CommandHandler, module: Module, request: ModuleRequest,
             secret: @escaping ModuleRunner.Secret) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let execution = Execution()
            continuation.onTermination = { _ in execution.stop() }
            do {
                let executable = try Self.resolve(handler.program, in: module)
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = LoginEnvironment.path
                environment["YISI_MODULE_DIR"] = module.folder.path
                environment["YISI_ROLE"] = module.role.rawValue
                for (key, template) in handler.env ?? [:] {
                    environment[key] = try ModuleTemplate.render(template) { token in try secret(token.argument ?? "") }
                }
                var imageFile: URL?
                if let image = request.image {
                    let file = home.scratch.appendingPathComponent(UUID().uuidString + ".png")
                    try FileManager.default.createDirectory(at: home.scratch, withIntermediateDirectories: true)
                    try image.write(to: file, options: .atomic)
                    imageFile = file
                }
                let input: Data
                switch handler.stdinFormat {
                case .text: input = Data(request.plainText(for: module.role).utf8)
                case .json: input = try JSONSerialization.data(withJSONObject: request.contract(role: module.role, image: imageFile?.path),
                                                               options: [.sortedKeys])
                }
                try execution.start(executable: executable, arguments: handler.arguments, directory: module.folder,
                                    environment: environment, input: input, timeout: handler.timeoutInterval,
                                    output: { continuation.yield($0) },
                                    completion: { result in
                                        if let imageFile { try? FileManager.default.removeItem(at: imageFile) }
                                        switch result {
                                        case .success: continuation.finish()
                                        case .failure(let error): continuation.finish(throwing: error)
                                        }
                                    })
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    static func resolve(_ command: String, in module: Module) throws -> URL {
        let manager = FileManager.default
        if command.contains("/") || command.hasPrefix("~") {
            let url = module.resolve(command)
            guard manager.isExecutableFile(atPath: url.path) else { throw ModuleError.commandNotFound(command) }
            return url
        }
        let local = module.folder.appendingPathComponent(command)
        if manager.isExecutableFile(atPath: local.path) { return local }
        for directory in LoginEnvironment.path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(command)
            if manager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw ModuleError.commandNotFound(command)
    }
}

/// One child process and everything that can end it.
private final class Execution: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var finished = false
    private var stopped = false

    func start(executable: URL, arguments: [String], directory: URL, environment: [String: String], input: Data,
               timeout: TimeInterval, output: @escaping (String) -> Void,
               completion: @escaping (Result<Void, Error>) -> Void) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let decoder = UTF8Stream()
        var produced = 0
        var produceFailure: Error?
        var errorTail = Data()
        let outputDone = DispatchSemaphore(value: 0)
        let errorDone = DispatchSemaphore(value: 0)

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if let rest = decoder.flush(), !rest.isEmpty { output(rest) }
                outputDone.signal()
                return
            }
            produced += chunk.count
            if produced > CommandRunner.outputLimit {
                produceFailure = ModuleError.responseTooLarge
                self?.stop()
                return
            }
            if let text = decoder.append(chunk), !text.isEmpty { output(text) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                errorDone.signal()
                return
            }
            errorTail.append(chunk)
            if errorTail.count > 4096 { errorTail = errorTail.suffix(4096) }
        }

        process.terminationHandler = { [weak self] process in
            // Let both pipes drain before deciding what happened.
            _ = outputDone.wait(timeout: .now() + 2)
            _ = errorDone.wait(timeout: .now() + 1)
            guard let self else { return }
            self.lock.lock()
            let wasStopped = self.stopped
            self.finished = true
            self.lock.unlock()
            if let produceFailure {
                completion(.failure(produceFailure))
            } else if wasStopped {
                completion(.failure(self.timedOut ? ModuleError.timeout : CancellationError()))
            } else if process.terminationStatus != 0 {
                let detail = String(decoding: errorTail, as: UTF8.self)
                    .split(separator: "\n").suffix(3).joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completion(.failure(ModuleError.commandFailed(process.terminationStatus, String(detail.prefix(400)))))
            } else if produced == 0 {
                completion(.failure(ModuleError.emptyResult))
            } else {
                completion(.success(()))
            }
        }

        lock.lock()
        self.process = process
        lock.unlock()
        try process.run()
        // Own process group, so stopping also reaches anything the command spawned.
        setpgid(process.processIdentifier, process.processIdentifier)

        DispatchQueue.global(qos: .userInitiated).async {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.timedOut = true
            self?.stop()
        }
    }

    private var _timedOut = false
    private var timedOut: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _timedOut }
        set {
            lock.lock()
            if !finished { _timedOut = newValue }
            lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        guard let process, !finished, !stopped else { lock.unlock(); return }
        stopped = true
        lock.unlock()
        let pid = process.processIdentifier
        if killpg(pid, SIGTERM) != 0 { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let done = self.finished
            self.lock.unlock()
            if !done { if killpg(pid, SIGKILL) != 0 { kill(pid, SIGKILL) } }
        }
    }
}

/// Decodes UTF-8 across chunk boundaries without splitting a character.
private final class UTF8Stream {
    private var pending = Data()

    func append(_ data: Data) -> String? {
        pending.append(data)
        for cut in 0...min(3, pending.count) {
            let prefix = pending.prefix(pending.count - cut)
            if let text = String(data: prefix, encoding: .utf8) {
                pending = Data(pending.suffix(cut))
                return text
            }
        }
        return nil
    }

    func flush() -> String? {
        defer { pending = Data() }
        return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
    }
}

/// The PATH a Terminal session would have. GUI apps inherit only the system default.
enum LoginEnvironment {
    static let path: String = {
        let fallback = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                        NSHomeDirectory() + "/.local/bin"].joined(separator: ":")
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "printf '\\n__YISI_PATH__%s__YISI_END__' \"$PATH\""]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return fallback }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return fallback }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let start = text.range(of: "__YISI_PATH__"), let end = text.range(of: "__YISI_END__", range: start.upperBound..<text.endIndex) else {
            return fallback
        }
        let path = String(text[start.upperBound..<end.lowerBound])
        return path.isEmpty ? fallback : path
    }()
}
