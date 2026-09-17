import SwiftUI
import AppKit

@main
struct AmpRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel(preview: CommandLine.arguments.contains { $0.hasPrefix("--preview") })
    @AppStorage("appearance") private var appearance = "system"

    private static let menuIcon: NSImage = {
        let image = Bundle.main.url(forResource: "AmpRunnerMenu", withExtension: "pdf")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: "Amp Runner")!
        image.size = NSSize(width: 24, height: 18)
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        Window(model.preview ? "Amp Runner — Preview (sample data)" : "Amp Runner", id: "projects") {
            ProjectsView(model: model)
                .frame(minWidth: 820, minHeight: 520)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .background(.ultraThinMaterial)
                .background(InitialWindowFocus())
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: model.chooseFolders) { Label("Add Folders…", systemImage: "plus") }
                            .help("Add Projects… (⌘N)").disabled(!model.configurationReadable)
                    }
                }
        }
        .defaultSize(width: 880, height: 560)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Project…") { model.chooseFolders() }.keyboardShortcut("n")
                Button("Add Folders…") { model.chooseFolders() }.keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Zoom In") { model.zoom.increase() }
                    .keyboardShortcut("=", modifiers: .command).disabled(!model.zoom.canIncrease)
                Button("Zoom In (+)") { model.zoom.increase() }
                    .keyboardShortcut("+", modifiers: .command).disabled(!model.zoom.canIncrease)
                Button("Zoom Out") { model.zoom.decrease() }
                    .keyboardShortcut("-", modifiers: .command).disabled(!model.zoom.canDecrease)
                Button("Actual Size") { model.zoom.reset() }.keyboardShortcut("0", modifiers: .command)
            }
        }

        MenuBarExtra {
            RunnerMenu(model: model)
        } label: {
            Image(nsImage: Self.menuIcon)
                .accessibilityLabel("Amp Runner: \(model.title)")
        }
    }
}

private struct InitialWindowFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusView { FocusView() }
    func updateNSView(_ view: FocusView, context: Context) {}

    final class FocusView: NSView {
        private var needsInitialFocus = true
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            window.initialFirstResponder = self
            NotificationCenter.default.addObserver(self, selector: #selector(opened), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(closed), name: NSWindow.willCloseNotification, object: window)
            if window.isKeyWindow { opened() }
        }

        @objc private func opened() {
            guard needsInitialFocus else { return }
            needsInitialFocus = false
            window?.makeFirstResponder(self)
        }

        @objc private func closed() { needsInitialFocus = true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 48 {
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) }
                else { window?.selectNextKeyView(nil) }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
        return true
    }
}

struct RunnerMenu: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text("Amp Runner · \(model.title)")
        Text("\(model.configuration.directories.count) folders saved")
        Divider()
        Button("Manage Projects…") {
            openWindow(id: "projects")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Manager (runner keeps running)") { NSApp.terminate(nil) }
    }
}
