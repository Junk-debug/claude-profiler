import Darwin
import Foundation

/// Ends a running Claude Code session's process so the OS takes its memory
/// back. The transcript is already on disk, so the chat itself survives and
/// `claude --resume <id>` picks it up again.
public enum SessionRelease {
    public enum Failure: Error, Equatable {
        /// The pid no longer belongs to this session — it exited, or the OS
        /// handed the number to another process. Nothing was signalled.
        case notThisSession
        case signalFailed(errno: Int32)
    }

    public static func resumeCommand(sessionId: String) -> String {
        "claude --resume \(sessionId)"
    }

    /// True when `registry` (the session's `~/.claude/sessions/<pid>.json`)
    /// names `sessionId` and its `startedAt` agrees with when the process
    /// actually started. A registry file outlives a crashed process, so the
    /// start time is what tells a recycled pid apart from the session.
    public static func registryMatches(
        _ registry: Data,
        sessionId: String,
        processStart: Date,
        tolerance: TimeInterval = 5
    ) -> Bool {
        guard let raw = try? JSONSerialization.jsonObject(with: registry) as? [String: Any],
              raw["sessionId"] as? String == sessionId,
              let startedAt = raw["startedAt"] as? Double
        else { return false }
        return abs(startedAt / 1_000 - processStart.timeIntervalSince1970) <= tolerance
    }

    /// When the kernel says `pid` started, or nil when there is no such process.
    public static func processStart(pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    public static func verify(
        pid: Int32,
        sessionId: String,
        registryDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    ) -> Bool {
        guard let start = processStart(pid: pid),
              let data = try? Data(contentsOf: registryDir.appendingPathComponent("\(pid).json"))
        else { return false }
        return registryMatches(data, sessionId: sessionId, processStart: start)
    }

    /// SIGTERM first, so Claude Code can flush the transcript and stop its MCP
    /// servers; SIGKILL only if it is still there after `grace`. Only the
    /// session's own pid is signalled, never its process group: a VS Code or
    /// desktop session shares its group with the editor that spawned it.
    /// Blocks for up to `grace`, so call it off the main thread.
    public static func release(pid: Int32, sessionId: String, grace: TimeInterval = 5) -> Result<Void, Failure> {
        guard verify(pid: pid, sessionId: sessionId) else { return .failure(.notThisSession) }
        let start = processStart(pid: pid)
        if kill(pid, SIGTERM) != 0 { return .failure(.signalFailed(errno: errno)) }

        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if processStart(pid: pid) != start { return .success(()) }
            usleep(100_000)
        }
        // Re-check the start time: the pid may have exited and been reused.
        if processStart(pid: pid) == start, kill(pid, SIGKILL) != 0, errno != ESRCH {
            return .failure(.signalFailed(errno: errno))
        }
        return .success(())
    }
}
