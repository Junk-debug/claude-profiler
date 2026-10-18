import AppKit
import ProfilerBarCore

enum Actions {
    /// Opens the full terminal profiler for a session.
    static func openInProfiler(_ session: LiveSession) {
        runInTerminal(name: "cprof-\(session.id.prefix(8))", script: """
        if command -v claude-profiler >/dev/null 2>&1; then
          claude-profiler \(session.id)
        else
          npx --yes claude-profiler \(session.id)
        fi
        """)
    }

    /// Brings the session's chat forward wherever it lives — the editor tab,
    /// the desktop app, the terminal tab — or, for a session whose process
    /// is gone, resumes it.
    static func goToChat(_ session: LiveSession) {
        guard let location = chatLocation(session) else {
            NSSound.beep()
            return
        }
        switch location {
        case .editor(let appPath, let scheme, let folder, let sessionId):
            let app = URL(fileURLWithPath: appPath)
            let configuration = NSWorkspace.OpenConfiguration()
            let reveal = {
                guard let url = ChatLocation.editorURL(scheme: scheme, sessionId: sessionId) else { return }
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
            }
            guard let folder else { return reveal() }
            // The editor hands a URI to its last active window, so first raise
            // the window that has the session's folder open.
            NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: app, configuration: configuration) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: reveal)
            }
        case .desktop(let sessionId):
            if let url = ChatLocation.desktopURL(sessionId: sessionId) { NSWorkspace.shared.open(url) }
        case .terminalTab(let bundleId, let tty):
            guard let script = ChatLocation.selectTabScript(bundleId: bundleId, tty: tty) else { return }
            // osascript, not NSAppleScript: no Apple Events entitlement needed
            // under the hardened runtime. If Automation is denied the app is
            // still brought forward.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.terminationHandler = { done in
                guard done.terminationStatus != 0 else { return }
                DispatchQueue.main.async {
                    NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.activate()
                }
            }
            try? process.run()
        case .app(let pid):
            NSRunningApplication(processIdentifier: pid)?.activate()
        case .resumeInTerminal(let sessionId, let cwd):
            let cd = cwd.map { "cd \(shellQuote($0)) && " } ?? ""
            runInTerminal(name: "claude-\(sessionId.prefix(8))", script: "\(cd)claude --resume \(sessionId)")
        }
    }

    private static func chatLocation(_ session: LiveSession) -> ChatLocation? {
        var host: ChatLocation.Host?
        var tty: String?
        if session.state.isLive, let pid = session.pid.map(Int32.init) {
            tty = ChatLocation.tty(of: pid)
            // The nearest ancestor that is a regular app — not the editor's
            // extension-host helper, not a shell.
            for ancestor in ChatLocation.ancestry(of: pid).dropFirst() {
                guard let app = NSRunningApplication(processIdentifier: ancestor),
                      app.activationPolicy == .regular,
                      let bundleId = app.bundleIdentifier,
                      let bundleURL = app.bundleURL
                else { continue }
                host = ChatLocation.Host(pid: ancestor, bundleId: bundleId, bundlePath: bundleURL.path)
                break
            }
        } else if session.source == .vscode,
                  let vscode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            host = ChatLocation.Host(pid: 0, bundleId: "com.microsoft.VSCode", bundlePath: vscode.path)
        }
        return ChatLocation.resolve(source: session.source, sessionId: session.id, cwd: session.cwd, host: host, tty: tty)
    }

    /// A `.command` file makes Terminal run a script without asking for
    /// Automation permission, and the interactive login shell finds tools
    /// wherever nvm or Homebrew put them.
    private static func runInTerminal(name: String, script: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).command")
        do {
            try "#!/bin/zsh -il\nclear\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func revealTranscript(_ session: LiveSession) {
        guard let path = session.transcriptPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func reportReleaseFailure(_ failure: SessionRelease.Failure) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch failure {
        case .notThisSession:
            alert.messageText = "The session has already ended"
            alert.informativeText = "Its process is gone, or the process id now belongs to another program, so nothing was quit."
        case .signalFailed(let code):
            alert.messageText = "Could not quit the session"
            alert.informativeText = String(cString: strerror(code))
        }
        alert.runModal()
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
