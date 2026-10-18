import AppKit
import ProfilerBarCore

enum Actions {
    /// Opens the full terminal profiler for a session. A `.command` file makes
    /// Terminal run it without asking for Automation permission, and the
    /// interactive login shell finds `claude-profiler` wherever nvm put it.
    static func openInProfiler(_ session: LiveSession) {
        let script = """
        #!/bin/zsh -il
        clear
        if command -v claude-profiler >/dev/null 2>&1; then
          claude-profiler \(session.id)
        else
          npx --yes claude-profiler \(session.id)
        fi
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cprof-\(session.id.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
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
