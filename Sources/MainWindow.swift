import Cocoa
import SwiftUI

/// The main window for a menu-bar app.
///
/// Activation policy flips to `.regular` while the window is open. An
/// `.accessory` app has no main menu, which means no ⌘C / ⌘V / ⌘A / ⌘Z in the
/// history search box or any settings field — unacceptable for a window whose
/// main control is a search field.
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()
    private var window: NSWindow?

    func show(section: Section = .history) {
        if window == nil { build() }
        AppState.shared.section = section

        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to menu-bar-only: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
    }

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "Yapperroni"
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 720, height: 460)
        w.delegate = self
        w.contentView = NSHostingView(rootView: ContentView())
        window = w
    }

    /// `.regular` without a main menu means no edit commands at all. Build the
    /// minimum that makes text fields behave.
    private func installMainMenu() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Yapperroni", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Yapperroni", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Yapperroni", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}

enum Section: String, CaseIterable, Identifiable {
    case history, settings, stats
    var id: String { rawValue }
    var label: String {
        switch self {
        case .history:  return "History"
        case .settings: return "Settings"
        case .stats:    return "Stats"
        }
    }
    var icon: String {
        switch self {
        case .history:  return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .stats:    return "chart.bar"
        }
    }
}

/// Live state the window shows but the dictation engine owns.
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var section: Section = .history
    @Published var tapActive = false
    @Published var accessibilityGranted = false
    @Published var modelReady = false
    @Published var lastError: String?
    /// True while the recorder owns the input node.
    @Published var dictating = false
    /// First-run permission and privacy screen, shown instead of the sidebar.
    @Published var showWelcome = false
    private init() {}
}
