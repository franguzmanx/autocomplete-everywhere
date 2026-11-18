@preconcurrency import ApplicationServices
import Foundation

struct PointerInput: Equatable, Sendable {
    let location: CGPoint
}

enum PointerEventPhase: Equatable, Sendable {
    case leftMouseDown
    case leftMouseUp
    case scrollWheel
}

@MainActor
final class PointerMonitor {
    typealias HitRegionsProvider = @MainActor () -> [CGRect]
    typealias AcceptanceHandler = @MainActor () -> Bool
    typealias StateChangeHandler = @MainActor () -> Void
    typealias InputHandler = @MainActor (CGPoint) -> Void
    typealias GeometryDisturbedHandler = @MainActor () -> Void
    typealias DisplayGeometriesProvider = @MainActor () -> [DisplayGeometry]

    private let hitRegionsProvider: HitRegionsProvider
    private let acceptanceHandler: AcceptanceHandler
    private let stateChangeHandler: StateChangeHandler
    private let inputHandler: InputHandler
    private let geometryDisturbedHandler: GeometryDisturbedHandler
    private let displayGeometriesProvider: DisplayGeometriesProvider
    private var consumedLeftClick = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    init(
        hitRegionsProvider: @escaping HitRegionsProvider,
        acceptanceHandler: @escaping AcceptanceHandler,
        stateChangeHandler: @escaping StateChangeHandler = {},
        inputHandler: @escaping InputHandler = { _ in },
        geometryDisturbedHandler: @escaping GeometryDisturbedHandler = {},
        displayGeometriesProvider: @escaping DisplayGeometriesProvider = {
            SystemAccessibilityReader().displayGeometries()
        }
    ) {
        self.hitRegionsProvider = hitRegionsProvider
        self.acceptanceHandler = acceptanceHandler
        self.stateChangeHandler = stateChangeHandler
        self.inputHandler = inputHandler
        self.geometryDisturbedHandler = geometryDisturbedHandler
        self.displayGeometriesProvider = displayGeometriesProvider
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: pointerMonitorCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        ) else {
            CFMachPortInvalidate(tap)
            return false
        }

        let targetRunLoop = CFRunLoopGetMain()
        eventTap = tap
        runLoopSource = source
        runLoop = targetRunLoop
        CFRunLoopAddSource(targetRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoop, let runLoopSource {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        consumedLeftClick = false
    }

    @discardableResult
    func process(_ input: PointerInput, phase: PointerEventPhase) -> Bool {
        switch phase {
        case .scrollWheel:
            geometryDisturbedHandler()
            return false
        case .leftMouseUp:
            guard consumedLeftClick else { return false }
            consumedLeftClick = false
            return true
        case .leftMouseDown:
            if consumedLeftClick { return true }
            guard hitRegionsProvider().contains(where: {
                $0.width > 0 && $0.height > 0 && $0.contains(input.location)
            }) else {
                inputHandler(input.location)
                stateChangeHandler()
                return false
            }
            guard acceptanceHandler() else {
                inputHandler(input.location)
                stateChangeHandler()
                return false
            }
            consumedLeftClick = true
            return true
        }
    }

    func handle(_ event: CGEvent, type: CGEventType) -> Bool {
        let phase: PointerEventPhase
        switch type {
        case .leftMouseDown:
            phase = .leftMouseDown
        case .leftMouseUp:
            phase = .leftMouseUp
        case .scrollWheel:
            return process(PointerInput(location: .zero), phase: .scrollWheel)
        default:
            return false
        }
        guard let location = DisplayCoordinateConverter.appKitPoint(
            fromAccessibilityPoint: event.location,
            displays: displayGeometriesProvider()
        ) else {
            return false
        }
        return process(
            PointerInput(location: location),
            phase: phase
        )
    }

    fileprivate func enableAfterSystemDisable() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
}

private func pointerMonitorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<PointerMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            monitor.enableAfterSystemDisable()
        }
        return Unmanaged.passUnretained(event)
    }
    guard type == .leftMouseDown || type == .leftMouseUp || type == .scrollWheel else {
        return Unmanaged.passUnretained(event)
    }

    let consumed = MainActor.assumeIsolated {
        monitor.handle(event, type: type)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}
