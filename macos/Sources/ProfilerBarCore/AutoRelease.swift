import Foundation

/// Picks the sessions to free on their own: idle for long enough, holding
/// enough memory to be worth it, and quiet. Only `.idle` counts — a busy
/// session or one waiting on approval is never freed.
public struct AutoRelease: Sendable {
    public enum Scope: String, CaseIterable, Identifiable, Sendable {
        /// Terminal sessions only: quitting one drops back to the shell, where
        /// `claude --resume` is one command away. An editor or the desktop app
        /// shows its own error for a process that went away under it.
        case terminal
        case all

        public var id: String { rawValue }
    }

    public struct Policy: Equatable, Sendable {
        public var idleAfter: TimeInterval
        public var minimumMb: Int
        public var scope: Scope

        public init(idleAfter: TimeInterval, minimumMb: Int, scope: Scope) {
            self.idleAfter = idleAfter
            self.minimumMb = minimumMb
            self.scope = scope
        }
    }

    /// CPU of the session's process tree that counts as work. An idle prompt
    /// still spikes for a sample now and then — MCP servers, Claude Code's own
    /// timers — so only load that lasts `busyFor` restarts the idle clock: a
    /// background build or test run keeps the session, a blip does not.
    public static let busyCpuPct = 10.0
    public static let busyFor: TimeInterval = 60

    /// When this app first saw each process idle and quiet. Its own clock,
    /// not the transcript's: typing a prompt writes nothing to the transcript,
    /// so `lastActivityAt` would call a session idle while someone is typing.
    private var idleSince: [Key: Date] = [:]
    /// When each idle process last went above `busyCpuPct`, while it stays there.
    private var loadedSince: [Key: Date] = [:]
    /// Processes already handed out once, so a release that failed is not
    /// retried every snapshot.
    private var attempted: Set<Key> = []

    /// A session id with its pid: `claude --resume` brings the same session
    /// back in a new process, which starts its idle clock from scratch.
    private struct Key: Hashable, Sendable {
        let id: String
        let pid: Int
    }

    public init() {}

    /// Records `snapshot` and returns the sessions due to be freed now, each
    /// once. Call it on every snapshot, enabled or not, so turning the setting
    /// on does not free a session that was only just seen. `excluding` holds
    /// ids that must stay, such as sessions whose detail window is open.
    public mutating func due(
        in snapshot: LiveSnapshot,
        policy: Policy?,
        excluding: Set<String> = [],
        now: Date = Date()
    ) -> [LiveSession] {
        var seen: Set<Key> = []
        var due: [LiveSession] = []

        for session in snapshot.sessions {
            guard let pid = session.pid else { continue }
            let key = Key(id: session.id, pid: pid)
            guard session.state == .idle, let cpu = session.cpuPct else { continue }
            seen.insert(key)
            let loaded = cpu > Self.busyCpuPct
            if loaded {
                let loadedFrom = loadedSince[key] ?? now
                loadedSince[key] = loadedFrom
                if now.timeIntervalSince(loadedFrom) >= Self.busyFor { idleSince[key] = now }
            } else {
                loadedSince.removeValue(forKey: key)
            }
            let since = idleSince[key] ?? now
            idleSince[key] = since

            guard let policy,
                  !loaded,
                  !attempted.contains(key),
                  !excluding.contains(session.id),
                  policy.scope == .all || session.source == .cli,
                  let rss = session.rssMb, rss >= policy.minimumMb,
                  now.timeIntervalSince(since) >= policy.idleAfter
            else { continue }
            attempted.insert(key)
            due.append(session)
        }

        // Anything not idle right now starts over next time.
        idleSince = idleSince.filter { seen.contains($0.key) }
        loadedSince = loadedSince.filter { seen.contains($0.key) }
        attempted = attempted.filter { seen.contains($0) }
        return due
    }
}
