import Foundation

struct DisplayGeometry: Equatable, Sendable {
    let accessibilityFrame: CGRect
    let appKitFrame: CGRect
    let backingScaleFactor: CGFloat

    init(
        accessibilityFrame: CGRect,
        appKitFrame: CGRect,
        backingScaleFactor: CGFloat = 1
    ) {
        self.accessibilityFrame = accessibilityFrame
        self.appKitFrame = appKitFrame
        self.backingScaleFactor = backingScaleFactor
    }
}

enum DisplayCoordinateConverter {
    static func appKitPoint(
        fromAccessibilityPoint point: CGPoint,
        displays: [DisplayGeometry]
    ) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite,
              let display = displays.first(where: {
                  $0.accessibilityFrame.contains(point)
              })
        else { return nil }
        let ax = display.accessibilityFrame
        let appKit = display.appKitFrame
        guard ax.width > 0, ax.height > 0,
              appKit.width > 0, appKit.height > 0
        else { return nil }
        let scaleX = appKit.width / ax.width
        let scaleY = appKit.height / ax.height
        return CGPoint(
            x: appKit.minX + ((point.x - ax.minX) * scaleX),
            y: appKit.maxY - ((point.y - ax.minY) * scaleY)
        )
    }

    static func appKitRect(
        fromAccessibilityRect rect: CGRect,
        displays: [DisplayGeometry]
    ) -> CGRect? {
        guard isValidAccessibilityRect(rect) else { return nil }
        guard let display = displays.first(where: {
            fullyContains($0.accessibilityFrame, rect)
        }) else { return nil }
        return appKitRect(fromAccessibilityRect: rect, on: display)
    }

    static func appKitRect(
        fromAccessibilityRect rect: CGRect,
        anchoredBy anchor: CGRect,
        displays: [DisplayGeometry]
    ) -> CGRect? {
        guard isValidAccessibilityRect(rect), isValidAccessibilityRect(anchor),
              let display = displays.first(where: {
                  fullyContains($0.accessibilityFrame, anchor)
              })
        else { return nil }
        return appKitRect(fromAccessibilityRect: rect, on: display)
    }

    private static func appKitRect(
        fromAccessibilityRect rect: CGRect,
        on display: DisplayGeometry
    ) -> CGRect? {
        let ax = display.accessibilityFrame
        let appKit = display.appKitFrame
        guard ax.width > 0, ax.height > 0, appKit.width > 0, appKit.height > 0 else {
            return nil
        }
        let scaleX = appKit.width / ax.width
        let scaleY = appKit.height / ax.height
        return CGRect(
            x: appKit.minX + ((rect.minX - ax.minX) * scaleX),
            y: appKit.maxY - ((rect.maxY - ax.minY) * scaleY),
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }

    private static func isValidAccessibilityRect(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.hasFiniteComponents
            && rect.size.width >= 0 && rect.size.height > 0
    }

    private static func fullyContains(_ frame: CGRect, _ rect: CGRect) -> Bool {
        rect.minX >= frame.minX && rect.maxX <= frame.maxX
            && rect.minY >= frame.minY && rect.maxY <= frame.maxY
    }
}

private extension CGRect {
    var hasFiniteComponents: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
    }
}
