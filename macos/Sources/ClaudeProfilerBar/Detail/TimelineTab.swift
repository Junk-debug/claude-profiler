import ProfilerBarCore
import SwiftUI

/// Turn by turn: what you asked, how long the turn ran, how much of it was the
/// model and how much was tools, and every event inside it.
///
/// One row per user turn — `session.turnCount`, the same count the terminal UI
/// uses — not one per captured prompt. A turn whose prompt never made it into
/// the transcript still happened, and dropping it silently renumbers every
/// turn after it.
struct TimelineTab: View {
    let profile: Profile

    @State private var expanded: Set<Int> = []
    @State private var openedCall: IdentifiedCall?
    @State private var openedPoint: ContextPoint?

    private struct Turn: Identifiable {
        let index: Int
        var startMs: Double?
        var trigger: String?
        var modelMs: Double = 0
        var toolCalls: Int = 0
        var toolMs: Double = 0
        /// Wall clock to the next known turn start, or to the session end.
        var spanMs: Double?

        var id: Int { index }
    }

    /// The same derivation as `buildTurnRows` in src/tui/Timeline.tsx: what the
    /// artifact can honestly say about a turn, from the three series that carry
    /// a `turnIndex` — prompts, tool calls and per-request context points.
    private var turns: [Turn] {
        var rows = (0..<max(profile.session.turnCount, 0)).map { Turn(index: $0) }
        guard !rows.isEmpty else { return [] }

        func noteStart(_ index: Int, _ ms: Double?) {
            guard rows.indices.contains(index), let ms else { return }
            if rows[index].startMs == nil || ms < rows[index].startMs! { rows[index].startMs = ms }
        }

        for prompt in profile.prompts where rows.indices.contains(prompt.turnIndex) {
            rows[prompt.turnIndex].trigger = prompt.preview
            noteStart(prompt.turnIndex, prompt.at.epochMs)
        }
        for request in profile.modelBreakdown.requests where rows.indices.contains(request.turnIndex) {
            rows[request.turnIndex].modelMs += request.totalMs
            noteStart(request.turnIndex, request.at.epochMs)
        }
        for tool in profile.tools {
            for call in tool.callRefs where rows.indices.contains(call.turnIndex) {
                rows[call.turnIndex].toolCalls += 1
                rows[call.turnIndex].toolMs += call.durationMs ?? 0
                noteStart(call.turnIndex, call.startedAt.epochMs)
            }
        }
        for point in profile.context.turns where rows.indices.contains(point.turnIndex) {
            noteStart(point.turnIndex, point.at.epochMs)
        }

        let sessionEnd = profile.session.endedAt.epochMs
        for index in rows.indices {
            guard let start = rows[index].startMs else { continue }
            if let next = rows[(index + 1)...].first(where: { $0.startMs != nil })?.startMs {
                rows[index].spanMs = next - start
            } else if let sessionEnd {
                rows[index].spanMs = max(0, sessionEnd - start)
            }
        }
        return rows
    }

    var body: some View {
        let rows = turns
        if rows.isEmpty {
            EmptyTabNote(symbol: "text.append", text: "No turns recorded in this session yet")
        } else {
            let peak = max(1, rows.map { $0.modelMs + $0.toolMs }.max() ?? 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(rows) { turn in
                        row(turn, peak: peak)
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
            }
            .sheet(item: $openedCall) { call in
                CallDetailSheet(call: call.call, toolName: call.toolName) { openedCall = nil }
            }
            .sheet(item: $openedPoint) { point in
                ContextPointSheet(point: point) { openedPoint = nil }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Timeline — \(profile.session.turnCount) turns").font(.system(size: 11, weight: .semibold))
            Text("Span is wall clock to the next turn, so it also holds whatever idle time preceded that turn.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func row(_ turn: Turn, peak: Double) -> some View {
        let isOpen = expanded.contains(turn.index)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if isOpen { expanded.remove(turn.index) } else { expanded.insert(turn.index) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text("#\(turn.index)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(turn.startMs.map { Format.clock(Date(timeIntervalSince1970: $0 / 1_000).iso) } ?? "—")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(turn.trigger ?? "(no prompt captured)")
                            .font(.system(size: 12))
                            .foregroundStyle(turn.trigger == nil ? .secondary : .primary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(turn.spanMs.map { "span \(Format.ms($0))" } ?? "span —")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("\(turn.toolCalls) tools")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 2) {
                        Rectangle().fill(Color.purple).frame(width: barWidth(turn.modelMs, peak: peak), height: 6)
                        Rectangle().fill(Color.teal).frame(width: barWidth(turn.toolMs, peak: peak), height: 6)
                        Text("\(Format.ms(turn.modelMs)) model · \(Format.ms(turn.toolMs)) tools")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .padding(.leading, 6)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen { events(of: turn.index) }
        }
        .padding(.vertical, 8)
    }

    /// Every tool call and assistant-message token point in this turn, merged
    /// into one time-ordered list — the closest honest substitute for "the
    /// turn's events" the artifact can produce, since no raw event log is kept.
    private func events(of turnIndex: Int) -> some View {
        let calls = profile.tools.flatMap { tool in
            tool.callRefs.filter { $0.turnIndex == turnIndex }.map { (at: $0.startedAt.epochMs, tool: tool.name, call: $0, point: ContextPoint?.none) }
        }
        let points = profile.context.turns.filter { $0.turnIndex == turnIndex }.map {
            (at: $0.at.epochMs, tool: "", call: ToolCall?.none, point: Optional($0))
        }
        let merged = (calls.map { (at: $0.at, tool: $0.tool, call: Optional($0.call), point: $0.point) } + points)
            .sorted { ($0.at ?? 0) < ($1.at ?? 0) }

        return VStack(alignment: .leading, spacing: 2) {
            if merged.isEmpty {
                Text("No events recorded in this turn.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(Array(merged.enumerated()), id: \.offset) { _, event in
                Button {
                    if let call = event.call {
                        openedCall = IdentifiedCall(call: call, toolName: event.tool)
                    } else if let point = event.point {
                        openedPoint = point
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(event.at.map { Format.clock(Date(timeIntervalSince1970: $0 / 1_000).iso) } ?? "—")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .leading)
                        if let call = event.call {
                            Text(event.tool).font(.system(size: 10, weight: .medium)).frame(width: 90, alignment: .leading).lineLimit(1)
                            Text(call.inputPreview.summarized).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(call.durationMs.map(Format.ms) ?? "unfinished").font(.system(size: 11)).monospacedDigit()
                        } else if let point = event.point {
                            Text("assistant").font(.system(size: 10, weight: .medium)).frame(width: 90, alignment: .leading)
                            Text(
                                "cache read \(Format.tokens(point.cacheReadTokens)) · output \(Format.tokens(point.outputTokens))"
                                    + " · thinking \(Format.tokens(point.thinkingTokens))"
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 26)
        .padding(.top, 4)
    }

    private func barWidth(_ ms: Double, peak: Double) -> CGFloat {
        guard ms > 0 else { return 0 }
        return max(2, CGFloat(ms / peak) * 320)
    }
}

/// One assistant message's token point — the terminal UI's PromptPointDetail.
struct ContextPointSheet: View {
    let point: ContextPoint
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Turn \(point.turnIndex) · assistant message").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 28) {
                KeyValue(label: "At", value: Format.dateTime(point.at))
                KeyValue(label: "Cache read", value: Format.tokens(point.cacheReadTokens))
                KeyValue(label: "Cache create", value: Format.tokens(point.cacheCreateTokens))
                KeyValue(label: "Output", value: Format.tokens(point.outputTokens))
                KeyValue(label: "Thinking", value: Format.tokens(point.thinkingTokens))
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

extension ContextPoint: Identifiable {
    public var id: String { "\(turnIndex):\(at ?? "?")" }
}

extension Optional where Wrapped == String {
    /// Epoch milliseconds, for the arithmetic the turn rows do on timestamps.
    var epochMs: Double? {
        guard let self, let date = ISO8601DateFormatter.parser.dateOrPlain(from: self) else { return nil }
        return date.timeIntervalSince1970 * 1_000
    }
}

extension Date {
    /// Back to the string form the formatters take, so a derived timestamp
    /// renders through exactly the same path as one read from the artifact.
    var iso: String { ISO8601DateFormatter.parser.string(from: self) }
}
