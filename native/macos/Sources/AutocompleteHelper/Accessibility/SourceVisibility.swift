import Foundation

/// Read-only text is admitted only after the complete bounded ancestry reaches
/// a window. A clipped label requires an independently measured substring;
/// its full AX value is never treated as visible text.
enum SourceVisibility {
    // Includes native host containers as well as the document hierarchy.
    static let maximumAncestorCount = 32

    struct Ancestor {
        let frame: CGRect?
        let clips: Bool
        let hidden: Bool
        let isWindow: Bool
    }

    struct Excerpt {
        let frame: CGRect
        let read: () -> String?
    }

    static func readText(
        frame: CGRect, displays: [CGRect], ancestors: [Ancestor],
        readExcerpt: () -> Excerpt? = { nil },
        read: () -> String?
    ) -> String? {
        guard frame.width > 0, frame.height > 0,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              displays.contains(where: { $0.contains(frame) }),
              !ancestors.isEmpty, ancestors.count <= maximumAncestorCount,
              ancestors.last?.isWindow == true else { return nil }
        var visible = frame
        for ancestor in ancestors {
            guard !ancestor.hidden else { return nil }
            if ancestor.clips {
                guard let clip = ancestor.frame, clip.width > 0, clip.height > 0 else { return nil }
                visible = visible.intersection(clip)
                guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
            }
        }
        let text: String?
        if visible.contains(frame) {
            text = read()
        } else {
            guard let excerpt = readExcerpt(),
                  excerpt.frame.origin.x.isFinite, excerpt.frame.origin.y.isFinite,
                  excerpt.frame.width.isFinite, excerpt.frame.height.isFinite,
                  excerpt.frame.width > 0, excerpt.frame.height > 0,
                  visible.contains(excerpt.frame) else { return nil }
            text = excerpt.read()
        }
        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return BoundedText.prefix(text[...], maximumUTF16Units: 2_000)
    }
}
