import ApplicationServices

/// Process-local tag separates Autocomplete Everywhere's Unicode insertion from actual user input.
/// It is not an authorization mechanism; focus and selection checks still own writes.
enum SyntheticInsertionEvent {
    private static let marker = Int64.random(in: 1...Int64.max)

    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    static func isOwn(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }
}
