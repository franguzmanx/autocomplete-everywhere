import AppKit

struct ApplicationStateMessage: Encodable {
    let protocolVersion = 5
    let type = "application_state"
    let payload: Payload
    struct Application: Encodable, Equatable {
        let id: String
        let name: String
    }
    struct Payload: Encodable, Equatable {
        let currentApplication: String?
        let applications: [Application]
        private enum CodingKeys: String, CodingKey { case currentApplication, applications }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(currentApplication, forKey: .currentApplication)
            try container.encode(applications, forKey: .applications)
        }
    }
}

/// Application metadata only. This monitor never reads a window or a text field.
@MainActor
final class ApplicationMonitor {
    private let parentPID: pid_t
    private let writer: MessageWriter
    private var observers: [NSObjectProtocol] = []
    private var previous: ApplicationStateMessage.Payload?

    init(parentPID: pid_t, writer: MessageWriter) { self.parentPID = parentPID; self.writer = writer }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.publish() }
            })
        }
        publish()
    }

    func stop() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    private func publish() {
        var byID: [String: ApplicationStateMessage.Application] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != parentPID {
            guard let id = app.bundleIdentifier, id.utf8.count <= 255 else { continue }
            byID[id] = .init(id: id, name: String((app.localizedName ?? id).prefix(255)))
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let current = frontmost?.processIdentifier == parentPID ? nil : frontmost?.bundleIdentifier
        let payload = ApplicationStateMessage.Payload(currentApplication: current, applications: Array(byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.prefix(500)))
        guard payload != previous else { return }
        previous = payload
        do { try writer.writeApplicationState(payload) }
        catch { writer.writeDiagnostic("application_state_write_failed") }
    }
}
