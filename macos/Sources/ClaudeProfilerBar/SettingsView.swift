import ProfilerBarCore
import ServiceManagement
import SwiftUI

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case tokensAndCount, tokens, count, iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tokensAndCount: "Working sessions + today's tokens"
        case .tokens: "Today's tokens"
        case .count: "Working sessions"
        case .iconOnly: "Icon only"
        }
    }
}

struct SettingsView: View {
    @AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.tokensAndCount
    @AppStorage(SettingsKey.notifyFinished) private var notifyFinished = true
    @AppStorage(SettingsKey.notifyPermission) private var notifyPermission = true
    @AppStorage(SettingsKey.finishedThresholdSeconds) private var finishedThreshold = 60.0
    @AppStorage(SettingsKey.autoFree) private var autoFree = false
    @AppStorage(SettingsKey.autoFreeIdleSeconds) private var autoFreeIdle = 3_600.0
    @AppStorage(SettingsKey.autoFreeMinimumMb) private var autoFreeMinimumMb = 500
    @AppStorage(SettingsKey.autoFreeScope) private var autoFreeScope = AutoRelease.Scope.terminal
    @AppStorage(SettingsKey.notifyAutoFree) private var notifyAutoFree = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @Environment(LiveStore.self) private var store

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
                }
                Text("""
                macOS hides menu bar items when the bar runs out of room, without saying so.                 If the icon is missing, pick "Icon only", quit another menu bar app, or open                 the session window with: open -a "Claude Profiler"
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("When Claude needs approval", isOn: $notifyPermission)
                Toggle("When Claude finishes a long run", isOn: $notifyFinished)
                if notifyFinished {
                    Picker("Long run means at least", selection: $finishedThreshold) {
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                    }
                }
                Text("Approval alerts need the profiler hooks: npx claude-profiler install-hooks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Memory") {
                Toggle("Free idle sessions automatically", isOn: $autoFree)
                if autoFree {
                    Picker("After idle for", selection: $autoFreeIdle) {
                        Text("30 minutes").tag(1_800.0)
                        Text("1 hour").tag(3_600.0)
                        Text("2 hours").tag(7_200.0)
                        Text("4 hours").tag(14_400.0)
                    }
                    Picker("Only if using at least", selection: $autoFreeMinimumMb) {
                        Text("200 MB").tag(200)
                        Text("500 MB").tag(500)
                        Text("1 GB").tag(1_000)
                    }
                    Picker("Sessions", selection: $autoFreeScope) {
                        Text("Terminal only").tag(AutoRelease.Scope.terminal)
                        Text("All").tag(AutoRelease.Scope.all)
                    }
                    Toggle("Notify when a session is freed", isOn: $notifyAutoFree)
                }
                Text("""
                Does what Free does on a session that sat idle that long: quits its Claude Code \
                process and keeps the chat, to continue with claude --resume. Idle time counts \
                while this app runs. Sessions with an open window are kept.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Collector", value: store.command.description)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Only works for the bundled app (scripts/bundle.sh): \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
