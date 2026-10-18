import Darwin
import Foundation

/// Where a session's chat is on screen, and how to bring it forward. Every
/// front end is reached through a door it opens itself: the VS Code
/// extension's `/open` URI and the desktop app's `claude://code/continue`
/// link both reveal a tab that is already open instead of starting a second
/// one; a terminal tab is found by the tty its `claude` process writes to.
public enum ChatLocation: Equatable, Sendable {
    /// A VS Code-family editor (VS Code, Insiders, Cursor, Windsurf, VSCodium).
    case editor(appPath: String, scheme: String, folder: String?, sessionId: String)
    case desktop(sessionId: String)
    /// Terminal.app or iTerm2, whose tabs can be selected by tty.
    case terminalTab(bundleId: String, tty: String)
    /// Any other app: it can be brought forward, not a particular tab in it.
    case app(pid: Int32)
    /// No process to find: start the chat again where it ran.
    case resumeInTerminal(sessionId: String, cwd: String?)

    public struct Host: Equatable, Sendable {
        public let pid: Int32
        public let bundleId: String
        public let bundlePath: String

        public init(pid: Int32, bundleId: String, bundlePath: String) {
            self.pid = pid
            self.bundleId = bundleId
            self.bundlePath = bundlePath
        }
    }

    /// URL schemes of the editors that host the Claude Code extension.
    static let editorSchemes: [String: String] = [
        "com.microsoft.VSCode": "vscode",
        "com.microsoft.VSCodeInsiders": "vscode-insiders",
        "com.todesktop.230313mzl4w4u92": "cursor",
        "com.exafunction.windsurf": "windsurf",
        "com.vscodium": "vscodium",
    ]

    static let terminalsWithTabsByTTY: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2"]

    /// Decides from the session's front end and the app its process runs
    /// under. `host` is nil for an ended session or one with no app above it.
    public static func resolve(
        source: SessionSource,
        sessionId: String,
        cwd: String?,
        host: Host?,
        tty: String?
    ) -> ChatLocation? {
        if source == .desktop { return .desktop(sessionId: sessionId) }
        if let host, let scheme = editorSchemes[host.bundleId] {
            // A CLI session in the editor's own terminal still lands in the
            // right window, if not the right terminal tab.
            return .editor(appPath: host.bundlePath, scheme: scheme, folder: cwd, sessionId: sessionId)
        }
        if let host, let tty, terminalsWithTabsByTTY.contains(host.bundleId) {
            return .terminalTab(bundleId: host.bundleId, tty: tty)
        }
        if let host { return .app(pid: host.pid) }
        if source == .cli || source == .vscode { return .resumeInTerminal(sessionId: sessionId, cwd: cwd) }
        return nil
    }

    public static func editorURL(scheme: String, sessionId: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "anthropic.claude-code"
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "session", value: sessionId)]
        return components.url
    }

    public static func desktopURL(sessionId: String) -> URL? {
        var components = URLComponents(string: "claude://code/continue")
        components?.queryItems = [URLQueryItem(name: "session", value: sessionId)]
        return components?.url
    }

    /// AppleScript that selects the tab writing to `tty` and raises its window.
    public static func selectTabScript(bundleId: String, tty: String) -> String? {
        let tty = tty.replacingOccurrences(of: "\"", with: "")
        switch bundleId {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return
                  end if
                end repeat
              end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      tell t to select
                      tell s to select
                      activate
                      return
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            """
        default:
            return nil
        }
    }

    // MARK: Process table

    public static func parent(of pid: Int32) -> Int32? {
        guard let info = procInfo(pid) else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    /// `/dev/ttys012` for a process attached to a terminal, else nil.
    public static func tty(of pid: Int32) -> String? {
        guard let info = procInfo(pid) else { return nil }
        let device = info.kp_eproc.e_tdev
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// The process and its ancestors, nearest first, stopping before launchd.
    public static func ancestry(of pid: Int32) -> [Int32] {
        var chain: [Int32] = []
        var current: Int32? = pid
        while let next = current, next > 1, chain.count < 64 {
            chain.append(next)
            current = parent(of: next)
        }
        return chain
    }

    private static func procInfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
