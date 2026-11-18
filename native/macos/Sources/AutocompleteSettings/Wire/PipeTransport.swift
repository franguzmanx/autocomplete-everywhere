import Foundation

/// Abstraction over the stdin/stdout pipes so the store can be exercised in tests.
protocol SettingsTransport: AnyObject, Sendable {
    func send(_ envelope: RequestEnvelope) throws
    func startReading(
        onLine: @escaping @Sendable (String) -> Void,
        onEnd: @escaping @Sendable () -> Void
    )
}

/// Line-delimited JSON over the process pipes. Only JSON goes to stdout; diagnostics use short
/// codes on stderr and never include message content, entries or account data.
final class PipeTransport: SettingsTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let output = FileHandle.standardOutput
    private let errorOutput = FileHandle.standardError

    func send(_ envelope: RequestEnvelope) throws {
        var data = try encoder.encode(envelope)
        data.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        output.write(data)
    }

    func startReading(
        onLine: @escaping @Sendable (String) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        let thread = Thread {
            while let line = readLine(strippingNewline: true) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                onLine(trimmed)
            }
            onEnd()
        }
        thread.name = "com.autocompletion.settings.stdin"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func diagnostic(_ code: String) {
        guard let data = "settings:\(code)\n".data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        errorOutput.write(data)
    }
}
