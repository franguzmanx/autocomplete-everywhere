import AppKit
import SwiftUI

/// A flush AppKit split pane. A regular split item deliberately avoids Tahoe's
/// floating sidebar card; the native sidebar material fills the column instead.
struct SettingsSplitView: NSViewControllerRepresentable {
    let store: SettingsStore

    func makeNSViewController(context: Context) -> SettingsSplitController {
        SettingsSplitController(store: store)
    }

    func updateNSViewController(_ controller: SettingsSplitController, context: Context) {}
}

@MainActor
final class SettingsSplitController: NSSplitViewController {
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "AutocompleteSettingsSplit"

        let sidebar = NSSplitViewItem(viewController: SettingsSidebarController(store: store))
        sidebar.minimumThickness = 184
        sidebar.maximumThickness = 240
        sidebar.canCollapse = false
        sidebar.holdingPriority = .defaultHigh
        addSplitViewItem(sidebar)

        let detail = NSHostingController(rootView: SettingsDetailPane(store: store))
        detail.sizingOptions = []
        addSplitViewItem(NSSplitViewItem(viewController: detail))
        splitView.setPosition(208, ofDividerAt: 0)
    }

}

@MainActor
private final class SettingsSidebarController: NSViewController {
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        view = material

        let hosting = NSHostingController(rootView: SidebarPane(store: store))
        hosting.sizingOptions = []
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: material.safeAreaLayoutGuide.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
    }
}

private struct SidebarPane: View {
    let store: SettingsStore

    var body: some View {
        SidebarView()
            .environment(store)
            .environment(\.l10n, store.l10n)
    }
}

private struct SettingsDetailPane: View {
    let store: SettingsStore

    var body: some View {
        NavigationStack {
            DetailView()
        }
        .environment(store)
        .environment(\.l10n, store.l10n)
    }
}
