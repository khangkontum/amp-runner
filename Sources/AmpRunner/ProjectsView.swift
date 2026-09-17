import SwiftUI
import RunnerCore

struct ProjectsView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false
    @State private var confirmStop = false
    @State private var removing: String?
    @State private var targeted = false
    @State private var search = ""
    @State private var runnerID = ""
    @State private var searchFocusRequest = 0
    @AppStorage("appearance") private var appearance = "system"

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filteredPaths: [String] {
        query.isEmpty ? model.paths : model.paths.filter { $0.localizedStandardContains(query) }
    }

    private var scale: Double { model.zoom.scale }
    private func type(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            projects
        }
        .font(type(13))
        .controlSize(model.zoom.percent >= 150 ? .large : .regular)
        .background {
            Button("Search Projects") { searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: .command).hidden()
        }
        .sheet(isPresented: $showSettings) { settings }
        .alert("Runner needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Stop the runner?", isPresented: $confirmStop) {
            Button("Cancel", role: .cancel) {}
            Button("Stop Runner", role: .destructive) { Task { await model.stop() } }
        } message: {
            Text("This can interrupt active Amp threads. Your folder list stays saved. Start at login will be turned off so the runner stays stopped.")
        }
        .alert("Remove folder from Amp?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Remove", role: .destructive) {
                if let path = removing { model.remove(path) }
                removing = nil
            }
        } message: {
            Text("Files will not be deleted. Existing threads may still have access. If the runner is stopped, unregistering will finish the next time it starts.")
        }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text("Projects").font(type(20, .semibold))
                Spacer(minLength: 0)
                ProjectSearchField(text: $search, focusRequest: searchFocusRequest, scale: scale)
                    .frame(width: 200 + 60 * (scale - 1), height: 24 * scale)
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            if !model.serviceMessage.isEmpty && model.loaded {
                Label(model.serviceMessage, systemImage: "exclamationmark.triangle")
                    .font(type(12)).foregroundStyle(.orange).lineLimit(3)
                    .textSelection(.enabled).padding(.horizontal, 24).padding(.bottom, 16)
            }
            if model.paths.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        Image(systemName: "folder.badge.plus").font(type(40, .light)).foregroundStyle(.blue)
                        Text("Add your first project").font(type(17, .semibold))
                        Text("Choose the folders Amp can work in. Git repositories and ordinary folders both work.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Choose Folders…", action: model.chooseFolders)
                            .runnerButton(prominent: true).disabled(!model.configurationReadable)
                        Text("or drop folders here").font(type(11)).foregroundStyle(.secondary)
                    }.padding(32).frame(maxWidth: .infinity)
                }.frame(maxHeight: .infinity).scrollBounceBehavior(.basedOnSize)
            } else if filteredPaths.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(type(24)).foregroundStyle(.secondary)
                    Text("No matching projects").font(type(15, .semibold))
                    Text("Try a project name or folder path.").font(type(12)).foregroundStyle(.secondary)
                    Button("Clear Search") { search = ""; searchFocusRequest += 1 }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredPaths, id: \.self) { path in
                            folderRow(path)
                            Divider().padding(.leading, 28 * scale)
                        }
                    }.padding(.horizontal, 16)
                }
            }
            HStack(spacing: 12) {
                Label(query.isEmpty
                      ? "\(model.paths.count) \(model.paths.count == 1 ? "folder" : "folders")"
                      : "\(filteredPaths.count) of \(model.paths.count) folders", systemImage: "folder")
                Spacer(minLength: 8)
            }.buttonStyle(.borderless).font(type(11)).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { if targeted { RoundedRectangle(cornerRadius: 8).stroke(.blue, lineWidth: 3).padding(8) } }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.preview else { return false }
            model.addFolders(urls)
            return true
        } isTargeted: { targeted = $0 }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "desktopcomputer").font(type(24)).foregroundStyle(.blue).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("This Mac").font(type(14, .semibold))
                        Text(model.configuration.runnerID).font(type(11)).foregroundStyle(.secondary)
                            .lineLimit(2).textSelection(.enabled)
                    }
                    HStack(spacing: 7) {
                        Circle().fill(model.running ? Color.green : model.loaded ? .orange : .secondary).frame(width: 7, height: 7)
                        Text(model.title).font(type(12, .medium))
                        Spacer(minLength: 4)
                        if model.busy { ProgressView().controlSize(.small) }
                        Button {
                            if model.loaded { confirmStop = true } else { Task { await model.start() } }
                        } label: {
                            Image(systemName: model.loaded ? "stop.fill" : "play.fill")
                                .font(type(10, .semibold))
                                .frame(width: 24 * scale, height: 24 * scale)
                                .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .controlSize(.regular)
                        .help(model.loaded ? "Stop Runner…" : "Start Runner")
                        .accessibilityLabel(model.loaded ? "Stop Runner" : "Start Runner")
                        .disabled(model.busy || !model.configurationReadable)
                    }
                    Divider()
                    Toggle("Start at login", isOn: Binding(get: { model.configuration.startAtLogin }, set: { model.setLogin($0) }))
                        .toggleStyle(.switch).controlSize(model.zoom.percent >= 150 ? .regular : .small).font(type(12))
                        .disabled(model.busy || !model.configurationReadable)
                    Text(model.loaded ? "The runner keeps working when you close this window." : "Start the runner to make your saved folders available.")
                        .font(type(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize)
            Button { showSettings = true } label: { Label("Runner Settings", systemImage: "gearshape") }
                .buttonStyle(.plain).font(type(12)).padding(16)
        }
        .frame(width: 208 + 56 * (scale - 1))
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func folderRow(_ path: String) -> some View {
        let state = model.folderState(path)
        return HStack(alignment: .center, spacing: 9) {
            Image(systemName: "folder.fill").font(type(19)).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: path).lastPathComponent).font(type(13, .medium)).lineLimit(1)
                Text(path).font(type(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(path).textSelection(.enabled)
                if let error = model.status.errors[path] {
                    Text(error).font(type(11)).foregroundStyle(.orange).lineLimit(2).help(error)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            folderStatus(state)
            Menu {
                Button("Show in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
                Button("Locate Folder…") { model.locate(path) }
                Divider()
                if model.configuration.directories.contains(path) {
                    Button("Remove from Amp…", role: .destructive) { removing = path }
                } else {
                    Button("Cancel Removal") { model.addFolders([URL(fileURLWithPath: path)]) }
                }
            } label: { Image(systemName: "ellipsis").font(type(13)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
            .disabled(model.preview || !model.configurationReadable)
            .accessibilityLabel("Actions for \(URL(fileURLWithPath: path).lastPathComponent)")
        }.padding(.vertical, 7 + 2 * (scale - 1)).padding(.horizontal, 2)
    }

    private func folderStatus(_ state: (String, String)) -> some View {
        Circle()
            .fill(state.0 == "Registered" ? Color.green : state.0 == "Unavailable" || state.0 == "Needs attention" ? .orange : .secondary)
            .frame(width: 7 * scale, height: 7 * scale)
            .help(state.0)
            .accessibilityLabel(state.0)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Runner Settings").font(type(17, .semibold))
            Picker("Theme", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }.pickerStyle(.segmented).accessibilityLabel("Theme")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text("Runner ID").font(type(12, .semibold))
                    TextField("mac-mini", text: $runnerID)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Runner ID")
                        .disabled(model.loaded || model.busy || model.preview)
                    Button("Save") { Task { await model.renameRunner(runnerID) } }
                        .disabled(model.loaded || model.busy || model.preview || !model.configurationReadable || runnerID == model.configuration.runnerID)
                }
                Text(model.loaded ? "Stop the runner to rename it. Existing threads keep the old ID." : "Use a unique hostname. Saved folders follow the new ID on next start.")
                    .font(type(10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Amp CLI").font(type(12, .semibold))
                    Text(model.configuration.ampPath.isEmpty ? "Amp not found" : model.configuration.ampPath)
                        .font(type(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled).help(model.configuration.ampPath)
                }
                Spacer(minLength: 0)
                Button("Choose…", action: model.chooseAmp).disabled(model.loaded || model.preview)
                    .help(model.loaded ? "Stop the runner to change the Amp executable." : "Choose the Amp CLI executable.")
            }
            Text("Uses your Amp sign-in. Run amp login in Terminal to sign in.")
                .font(type(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 10) {
                Button("Open Logs", action: model.openLogs).disabled(model.preview)
                Button("Help") { NSWorkspace.shared.open(URL(string: "https://ampcode.com/docs/cli/runners")!) }
                Spacer()
                Button("Done") { showSettings = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .font(type(12))
        .controlSize(model.zoom.percent >= 150 ? .large : .regular)
        .frame(width: 500 + 120 * (scale - 1))
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { runnerID = model.configuration.runnerID }
        .onChange(of: model.configuration.runnerID) { _, value in runnerID = value }
    }
}

private struct ProjectSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let scale: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchField {
        let field = SearchField()
        field.placeholderString = "Search projects"
        field.setAccessibilityLabel("Search projects by name or path")
        field.sendsSearchStringImmediately = true
        field.maximumRecents = 0
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: SearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.font = .systemFont(ofSize: 12 * scale)
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.allowsFocus = true
            field.window?.makeFirstResponder(field)
        }
    }

    final class SearchField: NSSearchField {
        // AppKit otherwise picks the first text field as the window's initial responder.
        var allowsFocus = false
        override var acceptsFirstResponder: Bool { allowsFocus }
        override func mouseDown(with event: NSEvent) {
            allowsFocus = true
            super.mouseDown(with: event)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ProjectSearchField
        var focusRequest: Int
        init(_ parent: ProjectSearchField) {
            self.parent = parent
            focusRequest = parent.focusRequest
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            parent.text = ""
            control.stringValue = ""
            (control as? SearchField)?.allowsFocus = false
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}
