import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

// MARK: General

struct GeneralTab: View {
    @AppStorage(Appearance.key) private var appearance = "system"
    @AppStorage("watchedFolder") private var watchedFolder = ""
    @AppStorage("openEditorAfterRecording") private var openAfterRecording = true
    @AppStorage("closeAfterAction") private var closeAfterAction = true
    @AppStorage("recordMicrophone") private var recordMicrophone = false
    @AppStorage("recordSystemAudio") private var recordSystemAudio = false
    @AppStorage("clickColor") private var clickColor = "yellow"
    @AppStorage("clickSize") private var clickSize = 36.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("set.appearance")).font(.headline)
                HStack(spacing: 18) {
                    ForEach(["system", "light", "dark"], id: \.self) { theme in
                        ThemeCard(theme: theme, selected: appearance == theme) {
                            appearance = theme
                            Appearance.apply()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            Form {
                LabeledContent(L("set.folder")) {
                    Button { chooseFolder() } label: {
                        Text(LatestRecording.watchedFolder().path)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(width: 270, alignment: .leading)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(L("set.audio.mic"), isOn: $recordMicrophone)
                    Toggle(L("set.audio.system"), isOn: $recordSystemAudio)
                }
                .labeledContent(L("set.audio"))

                HStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(ClickStyleStore.presets, id: \.name) { preset in
                            Button { clickColor = preset.name } label: {
                                Circle().fill(preset.color.color)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.8))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Color.accentColor, lineWidth: clickColor == preset.name ? 2 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    WedgeSlider(value: $clickSize, range: 16...80, width: 110)
                }
                .labeledContent(L("set.clicks"))

                Divider()

                Toggle(L("set.after_recording.open"), isOn: $openAfterRecording)
                    .labeledContent(L("set.after_recording"))
                Toggle(L("set.after_action.close"), isOn: $closeAfterAction)
                    .labeledContent(L("set.after_action"))

                Divider()

                Toggle(L("set.startup.launch"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                .labeledContent(L("set.startup"))
            }
            .formStyle(.columns)
        }
        .formStyle(.columns)
        .padding(24)
        .frame(width: 560)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { watchedFolder = url.path }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private extension View {
    /// Classic Mac preferences layout: a right-aligned label, then the control.
    func labeledContent(_ label: String) -> some View {
        LabeledContent(label) { self }
    }
}

/// A small mock window in light, dark, or split (system), like the picker in Shottr's preferences.
private struct ThemeCard: View {
    let theme: String
    let selected: Bool
    let action: () -> Void

    private var title: String { L("set.theme.\(theme)") }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if theme == "system" {
                        MockWindow(dark: false)
                        MockWindow(dark: true).mask(LowerRightHalf())
                    } else {
                        MockWindow(dark: theme == "dark")
                    }
                }
                .frame(width: 132, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 3 : 1)
                )
                Text(title).font(.system(size: 13))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MockWindow: View {
    let dark: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            (dark ? Color(white: 0.23) : Color(white: 0.9))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(dark ? Color(white: 0.12) : Color.white)
                .frame(width: 104, height: 66)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .offset(x: 14, y: 12)
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 5, height: 5) }
            }
            .offset(x: 21, y: 19)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill((dark ? Color.white : Color.black).opacity(0.22)).frame(width: 64, height: 4)
                Capsule().fill((dark ? Color.white : Color.black).opacity(0.14)).frame(width: 82, height: 4)
                Capsule().fill((dark ? Color.white : Color.black).opacity(0.14)).frame(width: 50, height: 4)
            }
            .offset(x: 22, y: 36)
        }
    }
}

private struct LowerRightHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: Hotkeys

struct HotkeysTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Form {
                KeyboardShortcuts.Recorder(L("settings.record"), name: .record)
                KeyboardShortcuts.Recorder(L("settings.open_editor"), name: .openEditor)
            }
            Text(L("set.hk.hint"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Form {
                Text(L("settings.section.editor")).font(.headline).foregroundStyle(.secondary)
                ForEach(EditorShortcuts.all, id: \.keys) { item in
                    LabeledContent(L(item.action)) {
                        Text(item.keys)
                            .font(.system(size: 12, design: .rounded).weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
                    }
                }
            }
        }
        .formStyle(.columns)
        .padding(24)
        .frame(width: 560)
    }
}

// MARK: Advanced

struct AdvancedTab: View {
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            Toggle(L("set.adv.ontop.label"), isOn: $alwaysOnTop)
                .labeledContent(L("set.adv.ontop"))
            Button(L("set.adv.welcome.button")) { OnboardingWindowController.shared.show() }
                .labeledContent(L("set.adv.welcome"))
            if updater.isAvailable {
                Toggle(L("set.adv.updates.auto"), isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                    .labeledContent(L("set.adv.updates"))
                HStack {
                    Button(L("menu.updates")) { updater.checkForUpdates() }
                    Text(L("set.adv.version", updater.versionLabel)).foregroundStyle(.secondary)
                }
                .labeledContent(" ")
            }
            MCPSettings()
        }
        .formStyle(.columns)
        .padding(24)
        .frame(width: 560)
    }
}

/// Optional: lets an AI app drive the editor. Everything stays off until the user turns it on.
/// The panel says what is going on: waiting, connected (and who), working (and on what), last action.
private struct MCPSettings: View {
    @ObservedObject private var server = MCPServer.shared
    @State private var enabled = MCPServer.enabled
    @State private var copiedID: String?
    @State private var everCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("set.adv.mcp.label"), isOn: $enabled)
                .onChange(of: enabled) { _, on in server.setEnabled(on) }
            Text(L("set.adv.mcp.hint"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let failure = server.failure {
                Text(L("set.adv.mcp.failed", failure)).font(.callout).foregroundStyle(.red)
            } else if enabled && server.running {
                status
                Text(server.url).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 5) {
                    step(done: everCopied, L("set.adv.mcp.step1"))
                    step(done: server.clientName != nil, L("set.adv.mcp.step2"))
                    step(done: server.lastToolAt != nil, L("set.adv.mcp.step3"))
                }
                .padding(.vertical, 2)
                HStack {
                    copyButton("cmd", L("set.adv.mcp.copy_cmd"), server.claudeCodeCommand)
                    copyButton("url", L("set.adv.mcp.copy_url"), server.urlWithKey)
                }
                HStack {
                    copyButton("json", L("set.adv.mcp.copy_json"), server.jsonConfig)
                    Button(L("set.adv.mcp.new_key")) { server.regenerateToken(); everCopied = false }
                }
            }
        }
        .labeledContent(L("set.adv.mcp"))
    }

    /// One line that always tells the truth: refused, working, connected, or waiting.
    @ViewBuilder
    private var status: some View {
        if let tool = server.busyTool {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("set.adv.mcp.working", server.clientName ?? L("ai.default_client"), pretty(tool)))
                    .font(.callout).foregroundStyle(.green)
            }
        } else if let name = server.clientName {
            VStack(alignment: .leading, spacing: 2) {
                dot(.green, L("set.adv.mcp.connected", name))
                if let tool = server.lastTool, let at = server.lastToolAt {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        Text(L("set.adv.mcp.last", pretty(tool), relative(at)))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            dot(.orange, L("set.adv.mcp.waiting"))
            if let refused = server.rejectedAt, Date().timeIntervalSince(refused) < 120 {
                Text(L("set.adv.mcp.refused")).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dot(_ color: Color, _ text: String) -> some View {
        Label(text, systemImage: "circle.fill")
            .font(.callout)
            .symbolRenderingMode(.palette).foregroundStyle(color, color)
    }

    private func step(done: Bool, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(text).foregroundStyle(done ? .secondary : .primary)
        }
        .font(.callout)
        .animation(.easeInOut(duration: 0.2), value: done)
    }

    private func copyButton(_ id: String, _ title: String, _ text: String) -> some View {
        Button(copiedID == id ? "✓ " + L("set.adv.mcp.copied") : title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedID = id
            everCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if copiedID == id { copiedID = nil } }
        }
    }

    private func pretty(_ tool: String) -> String { tool.replacingOccurrences(of: "_", with: " ") }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
