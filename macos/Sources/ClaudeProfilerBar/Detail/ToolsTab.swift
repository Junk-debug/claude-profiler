import ProfilerBarCore
import SwiftUI

/// The tool table and, under it, the selected tool's calls — the terminal
/// UI's Tools → tool → call drill-down, in one view.
///
/// Bash gets the same three lenses the terminal UI offers: by recipe (each
/// call counted once, under everything it ran, so the totals reconcile to
/// 100%), by command (each call counted under every command it ran, so they
/// knowingly over-sum), and the flat call list.
struct ToolsTab: View {
    let profile: Profile
    /// A `Task`/`Agent` call that spawned a subagent opens that subagent
    /// rather than a call detail: the subagent is the interesting thing, and
    /// only the Subagents tab can show it.
    var openSubagent: (String) -> Void = { _ in }

    @State private var sortOrder = [KeyPathComparator(\ToolStat.totalMs, order: .reverse)]
    @State private var selection: ToolStat.ID?
    @State private var filter = ""
    @State private var lens: Lens = .recipe
    @State private var openedGroup: BashGroupStat?
    @State private var openedCall: IdentifiedCall?

    enum Lens: String, CaseIterable, Identifiable {
        case recipe, command, calls

        var id: String { rawValue }

        var label: String {
            switch self {
            case .recipe: "By recipe"
            case .command: "By command"
            case .calls: "Calls"
            }
        }

        var note: String {
            switch self {
            case .recipe: "Each call counts once, under everything it ran; totals add up to 100%."
            case .command: "Each call counts under every command it ran; totals add up past 100%."
            case .calls: "Every call, slowest first."
            }
        }
    }

    private var tools: [ToolStat] {
        let matched = filter.isEmpty
            ? profile.tools
            : profile.tools.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        return matched.sorted(using: sortOrder)
    }

    private var selectedTool: ToolStat? {
        tools.first { $0.id == selection }
    }

    /// Only Bash, and only when it ran more than one kind of command, has
    /// anything to switch between.
    private var hasLenses: Bool {
        (selectedTool?.bashGroups?.count ?? 0) > 1
    }

    private var subagentsByCallId: [String: SubagentStat] {
        Dictionary(uniqueKeysWithValues: profile.subagents.map { ($0.parentToolCallId, $0) })
    }

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                    TextField("Filter tools", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                table
            }
            .frame(minHeight: 200)

            detail
                .frame(minHeight: 160)
        }
        .sheet(item: $openedCall) { call in
            CallDetailSheet(call: call.call, toolName: call.toolName) { openedCall = nil }
        }
        .sheet(item: $openedGroup) { group in
            BashGroupSheet(
                group: group,
                calls: callsIn(group),
                onOpenCall: { call in
                    openedGroup = nil
                    openedCall = IdentifiedCall(call: call, toolName: selectedTool?.name ?? "Bash")
                },
                dismiss: { openedGroup = nil }
            )
        }
    }

    private var table: some View {
        Table(tools, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Tool", value: \.name) { tool in
                HStack(spacing: 6) {
                    Text(tool.name).lineLimit(1)
                    if tool.kind == "mcp", let server = tool.mcpServer {
                        Text(server).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("Calls", value: \.calls) { Text("\($0.calls)").monospacedDigit() }
                .width(52)
            TableColumn("Total", value: \.totalMs) { Text(Format.ms($0.totalMs)).monospacedDigit() }
                .width(70)
            TableColumn("Share", value: \.pctOfSession) {
                Text(Format.percent(ratio: $0.pctOfSession)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(60)
            TableColumn("Median", value: \.medianMs) { Text(Format.ms($0.medianMs)).monospacedDigit() }
                .width(70)
            TableColumn("p90", value: \.p90Ms) { Text(Format.ms($0.p90Ms)).monospacedDigit() }
                .width(70)
            TableColumn("Max", value: \.maxMs) { Text(Format.ms($0.maxMs)).monospacedDigit() }
                .width(70)
            TableColumn("Failed") { tool in
                Text(tool.failedCalls.map { "\($0)" } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle((tool.failedCalls ?? 0) > 0 ? .orange : .secondary)
            }
            .width(56)
            TableColumn("Result bytes") { tool in
                Text(tool.responseBytes.map(Format.bytes) ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(90)
        }
    }

    // MARK: The selected tool

    @ViewBuilder
    private var detail: some View {
        if let tool = selectedTool {
            VStack(alignment: .leading, spacing: 0) {
                header(for: tool)
                Divider()
                if hasLenses, lens != .calls {
                    groupList(tool: tool, groups: lens == .recipe ? (tool.bashGroups ?? []) : (tool.bashCommands ?? []))
                } else {
                    callList(tool: tool)
                }
            }
        } else {
            EmptyTabNote(symbol: "hand.tap", text: "Select a tool to see its calls")
        }
    }

    private func header(for tool: ToolStat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(tool.name) · \(tool.calls) call\(tool.calls == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                Text(
                    "\(Format.ms(tool.totalMs)) total · median \(Format.ms(tool.medianMs))"
                        + " · p90 \(Format.ms(tool.p90Ms)) · max \(Format.ms(tool.maxMs))"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                if let approval = tool.approvalMs, approval > 0 {
                    Text("· \(Format.ms(approval)) waiting for you")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                if let failed = tool.failedCalls, failed > 0 {
                    Text("· \(failed) failed").font(.system(size: 11)).foregroundStyle(.orange)
                }
                Spacer()
            }
            if hasLenses {
                HStack(spacing: 10) {
                    Picker("", selection: $lens) {
                        ForEach(Lens.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                    Text(lens.note).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func groupList(tool: ToolStat, groups: [BashGroupStat]) -> some View {
        List(groups) { group in
            Button {
                openedGroup = group
            } label: {
                HStack(spacing: 10) {
                    Text(group.group).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    Spacer()
                    Text("\(group.calls)×").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(Format.ms(group.totalMs)).font(.system(size: 11)).monospacedDigit()
                    Text(Format.percent(ratio: group.pctOfBash))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                    Text("median \(Format.ms(group.medianMs))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func callList(tool: ToolStat) -> some View {
        let subagents = subagentsByCallId
        // Slowest first: a single outlier sorts to the top instead of hiding
        // among the fast ones. Unfinished calls sort last rather than first.
        let calls = tool.callRefs.sorted { ($0.durationMs ?? -1) > ($1.durationMs ?? -1) }
        return List(calls) { call in
            Button {
                if let subagent = subagents[call.id] {
                    openSubagent(subagent.agentId)
                } else {
                    openedCall = IdentifiedCall(call: call, toolName: tool.name)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(call.turnIndex)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                        .help("Turn")
                    Text(Format.clock(call.startedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 60, alignment: .leading)
                    if let subagent = subagents[call.id] {
                        Text("[subagent \(subagent.agentId)]")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.purple)
                    }
                    Text(call.inputPreview.summarized)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(call.durationMs.map(Format.ms) ?? "unfinished")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func callsIn(_ group: BashGroupStat) -> [ToolCall] {
        let ids = Set(group.callIds)
        guard let tool = selectedTool else { return [] }
        return tool.callRefs
            .filter { ids.contains($0.id) }
            .sorted { ($0.durationMs ?? -1) > ($1.durationMs ?? -1) }
    }
}

/// A call plus the tool it belongs to, so a sheet can be presented for it.
struct IdentifiedCall: Identifiable {
    let call: ToolCall
    let toolName: String

    var id: String { call.id }
}

/// One command group's own calls — the terminal UI's BashGroupCalls screen.
struct BashGroupSheet: View {
    let group: BashGroupStat
    let calls: [ToolCall]
    let onOpenCall: (ToolCall) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.group).font(.system(size: 13, weight: .semibold, design: .monospaced)).lineLimit(2)
            Text(
                "\(group.calls) call\(group.calls == 1 ? "" : "s") · \(Format.ms(group.totalMs)) total"
                    + " · median \(Format.ms(group.medianMs)) · max \(Format.ms(group.maxMs))"
                    + " · \(Format.percent(ratio: group.pctOfBash)) of Bash"
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            List(calls) { call in
                Button { onOpenCall(call) } label: {
                    HStack(spacing: 10) {
                        Text(Format.clock(call.startedAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(call.inputPreview.summarized)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(call.durationMs.map(Format.ms) ?? "unfinished")
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 280)

            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640)
    }
}

/// Everything the artifact kept about one call — the terminal UI's CallDetail
/// screen, with the same pretty-printed input.
struct CallDetailSheet: View {
    let call: ToolCall
    let toolName: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(toolName) · call \(call.id)").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 28) {
                KeyValue(label: "Turn", value: "\(call.turnIndex)")
                KeyValue(label: "Started", value: Format.dateTime(call.startedAt))
                KeyValue(
                    label: "Duration",
                    value: call.durationMs.map(Format.ms) ?? "unfinished (no matching tool_result)"
                )
            }
            Text("Input").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                Text(call.inputPreview.prettyJSON)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}

extension String {
    /// `inputPreview` is minified JSON, truncated at the source, so parsing can
    /// fail on a very large input — in which case the raw text is the honest
    /// thing to show.
    var prettyJSON: String {
        guard let data = data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: parsed,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: pretty, encoding: .utf8)
        else { return self }
        return text
    }

    /// The terminal UI's `summarizeInput`: a single-field input collapses to
    /// its bare value, several fields join as `key=value`, and anything that
    /// is not a JSON object falls back to the raw preview.
    var summarized: String {
        guard let data = data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return self }
        if object.isEmpty { return "{}" }
        let entries = object.sorted { $0.key < $1.key }
        if entries.count == 1, let first = entries.first {
            return Self.scalar(first.value)
        }
        return entries.map { "\($0.key)=\(Self.scalar($0.value))" }.joined(separator: " ")
    }

    private static func scalar(_ value: Any) -> String {
        let text: String
        if let string = value as? String {
            text = string
        } else if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
                  let encoded = String(data: data, encoding: .utf8) {
            text = encoded
        } else {
            text = "\(value)"
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
