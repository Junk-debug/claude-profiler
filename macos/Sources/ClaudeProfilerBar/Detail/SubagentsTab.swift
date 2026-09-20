import ProfilerBarCore
import SwiftUI

/// Each subagent this session spawned, with its own time split, its own tool
/// table and its own calls — the same depth the terminal UI reaches by
/// drilling into a `Task` call.
///
/// A subagent's transcript carries no `cost-state` record, so cost is always
/// "—" here, never estimated from the parent session's cost.
struct SubagentsTab: View {
    let profile: Profile
    /// Opened from a Task call in the Tools tab: that subagent starts expanded
    /// and the list scrolls to it.
    var focused: String?

    @State private var expanded: Set<String> = []
    @State private var openedCall: IdentifiedCall?

    var body: some View {
        if profile.subagents.isEmpty {
            EmptyTabNote(symbol: "person.2.slash", text: "This session spawned no subagents")
        } else {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(profile.subagents) { subagent in
                            panel(for: subagent).id(subagent.agentId)
                        }
                    }
                    .padding(20)
                }
                .onAppear {
                    guard let focused else { return }
                    expanded.insert(focused)
                    scroller.scrollTo(focused, anchor: .top)
                }
            }
            .sheet(item: $openedCall) { call in
                CallDetailSheet(call: call.call, toolName: call.toolName) { openedCall = nil }
            }
        }
    }

    private func panel(for subagent: SubagentStat) -> some View {
        let isOpen = expanded.contains(subagent.agentId)
        return Panel(
            title: subagent.agentId,
            note: "\(Format.ms(subagent.spanMs)) · \(Format.tokens(subagent.tokens.totals.total)) tokens · cost —"
        ) {
            TimeSplitBar(split: subagent.timeline)

            Text(subagent.transcriptPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)

            if !subagent.tools.isEmpty {
                let peak = max(1, subagent.tools.map(\.totalMs).max() ?? 1)
                ForEach(isOpen ? subagent.tools : Array(subagent.tools.prefix(6))) { tool in
                    BarRow(
                        label: tool.name,
                        value: Format.ms(tool.totalMs),
                        fraction: tool.totalMs / peak,
                        color: .teal,
                        detail: "\(tool.calls)×"
                    )
                }

                Button(isOpen ? "Hide its calls" : "Show its calls") {
                    if isOpen { expanded.remove(subagent.agentId) } else { expanded.insert(subagent.agentId) }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))

                if isOpen { calls(of: subagent) }
            }
        }
    }

    /// Every call the subagent made, slowest first, across all of its tools —
    /// the same order the terminal UI's call list uses.
    private func calls(of subagent: SubagentStat) -> some View {
        let calls = subagent.tools
            .flatMap { tool in tool.callRefs.map { (tool: tool.name, call: $0) } }
            .sorted { ($0.call.durationMs ?? -1) > ($1.call.durationMs ?? -1) }
            .prefix(40)

        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(calls), id: \.call.id) { entry in
                Button {
                    openedCall = IdentifiedCall(call: entry.call, toolName: entry.tool)
                } label: {
                    HStack(spacing: 10) {
                        Text(Format.clock(entry.call.startedAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .leading)
                        Text(entry.tool)
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 90, alignment: .leading)
                            .lineLimit(1)
                        Text(entry.call.inputPreview.summarized)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(entry.call.durationMs.map(Format.ms) ?? "unfinished")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}
