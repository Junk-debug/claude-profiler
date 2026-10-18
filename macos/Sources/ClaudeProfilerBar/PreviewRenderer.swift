import AppKit
import ProfilerBarCore
import SwiftUI

/// `ClaudeProfilerBar --render-png <path> [--detail] [--tab <name>] [--turn <n>] [--sheet] [--dark] [--fixture <dir>]`:
/// renders the popover, or a session's detail tab, from real collector data
/// to a PNG and exits — for checking a UI change and for README screenshots
/// without clicking through the menu bar. With `--fixture`, the data comes
/// from `<dir>/snapshot.json` and `<dir>/<session id>.profile.json` instead,
/// so a screenshot shows nobody's real sessions.
@MainActor
enum PreviewRenderer {
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard let flag = arguments.firstIndex(of: "--render-png"), flag + 1 < arguments.count else { return false }
        let path = arguments[flag + 1]
        let dark = arguments.contains("--dark")

        let fixture = value(after: "--fixture", in: arguments).map { URL(fileURLWithPath: $0) }
        let message = fixture.map { try? Data(contentsOf: $0.appendingPathComponent("snapshot.json")) }
            .map { $0.flatMap(LiveMessage.decode) }
            ?? (try? CollectorProcess.collectOnce(command: CollectorCommand.resolve()))
        guard case .snapshot(let snapshot) = message else {
            FileHandle.standardError.write(Data("render: the collector produced no snapshot\n".utf8))
            exit(1)
        }
        let wantsDetail = arguments.contains("--detail") || arguments.contains("--tab")
        let session = snapshot.sessions.first { $0.state.isLive } ?? snapshot.sessions.first

        let view: AnyView
        if wantsDetail, let session {
            let profile = fixture.map { loadProfile(from: $0.appendingPathComponent("\(session.id).profile.json")) }
                ?? (try? CollectorProcess.collectProfileOnce(command: CollectorCommand.resolve(), id: session.id))
            if profile == nil {
                FileHandle.standardError.write(Data("render: no profile came back for \(session.id)\n".utf8))
                exit(1)
            }
            let store = LiveStore(preview: snapshot, profile: profile.map { (session.id, $0) })
            var detail = SessionDetailView(sessionId: session.id)
            if let flag = arguments.firstIndex(of: "--tab"), flag + 1 < arguments.count,
               let tab = SessionDetailView.Tab(rawValue: arguments[flag + 1])
            {
                detail.initialTab = tab
            }
            if let flag = arguments.firstIndex(of: "--turn"), flag + 1 < arguments.count,
               let turn = Int(arguments[flag + 1])
            {
                detail.initialTurn = turn
                // A sheet is its own window, so the offscreen host below would
                // capture the tab underneath it and not the sheet. Draw the
                // sheet's own view instead, which is what a screenshot of it
                // is meant to show anyway.
                if arguments.contains("--sheet"), let profile,
                   let row = TimelineTurn.rows(from: profile).first(where: { $0.index == turn })
                {
                    return render(AnyView(TurnPromptSheet(turn: row) {}), to: path, dark: dark)
                }
            }
            return render(AnyView(detail.frame(width: 900, height: 680).environment(store)), to: path, dark: dark)
        }

        let store = LiveStore(preview: snapshot)
        view = AnyView(PopoverView())

        return render(AnyView(view.environment(store)), to: path, dark: dark)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// A fixture profile is the artifact `claude-profiler --json` writes, the
    /// same object the collector wraps in a `profile` message.
    private static func loadProfile(from url: URL) -> Profile? {
        guard let data = try? Data(contentsOf: url),
              let artifact = try? JSONSerialization.jsonObject(with: data),
              let line = try? JSONSerialization.data(withJSONObject: [
                  "v": supportedProtocolVersion, "type": "profile", "at": 0, "id": "fixture", "profile": artifact,
              ]),
              case .profile(_, let profile) = LiveMessage.decode(line)
        else { return nil }
        return profile
    }

    private static func render(_ view: AnyView, to path: String, dark: Bool) -> Bool {
        let content = view
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(dark ? Color(white: 0.16) : Color(white: 0.97))

        // ImageRenderer draws ScrollView and AppKit-backed controls as
        // placeholders, so the view goes into a real, off-screen window instead.
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            FileHandle.standardError.write(Data("render: could not rasterize the view\n".utf8))
            exit(1)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        window.orderOut(nil)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render: could not encode the PNG\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("render: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        return true
    }
}
