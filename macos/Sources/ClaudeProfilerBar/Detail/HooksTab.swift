import ProfilerBarCore
import SwiftUI

/// What only hooks can measure: your approval time, failed calls, how much
/// tool output went into the context window, what a resume cost to re-cache,
/// and what the session's own lifecycle looked like.
///
/// The same eleven sections as the terminal UI's Hooks tab, in the same order
/// and under the same headings, and with the same rule for showing them: a
/// section a session carried no data for is left out entirely, so the tab
/// reads as a list of what was measured rather than a grid of dashes.
struct HooksTab: View {
    let profile: Profile

    var body: some View {
        if let hooks = profile.hooks {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    measuredFrom(hooks)
                    approval(hooks.approval)
                    if let reliability = shownReliability(hooks) { self.reliability(reliability) }
                    if let pollution = hooks.contextPollution { self.pollution(pollution) }
                    if let parallelism = shownParallelism(hooks) { self.parallelism(parallelism) }
                    if let waste = hooks.cacheWaste { cacheWaste(waste) }
                    lifecycle(hooks)
                    if let commands = hooks.commands, !commands.isEmpty { self.commands(commands) }
                    if let subagents = hooks.subagents, !subagents.isEmpty { self.subagents(subagents) }
                    if let streaming = hooks.streaming { self.streaming(streaming) }
                    if let instructions = hooks.instructions, !instructions.files.isEmpty {
                        self.instructions(instructions)
                    }
                }
                .padding(20)
            }
        } else {
            VStack(spacing: 10) {
                EmptyTabNote(
                    symbol: "bolt.slash",
                    text: "This session ran without the profiler hooks, so approval time,\nfailed calls and result sizes were never recorded."
                )
                Button("Copy install command") { Actions.copy("npx claude-profiler install-hooks") }
                    .buttonStyle(.link)
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: Which sections this session earned

    /// Hidden when nothing failed: a retry tax of zero is not a finding.
    private func shownReliability(_ hooks: HookInsights) -> HookInsights.Reliability? {
        let reliability = hooks.reliability
        return reliability.failedCalls == 0 && reliability.deniedCalls == 0 ? nil : reliability
    }

    /// Hidden when no batch held more than one call — nothing could have run
    /// in parallel, so there is no saving to report either way.
    private func shownParallelism(_ hooks: HookInsights) -> HookInsights.Parallelism? {
        guard let parallelism = hooks.parallelism, parallelism.multiCallBatches > 0 else { return nil }
        return parallelism
    }

    // MARK: Sections

    private func measuredFrom(_ hooks: HookInsights) -> some View {
        Text(
            "From \(Format.tokens(hooks.callsWithTiming)) measured call\(hooks.callsWithTiming == 1 ? "" : "s")"
                + (hooks.sidecarVersion.map { " · sidecar v\($0)" } ?? "")
        )
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func approval(_ approval: HookInsights.Approval) -> some View {
        if approval.precision == "unsplit" {
            Panel(title: "Approval", note: "v1 sidecar") {
                HStack(spacing: 28) {
                    KeyValue(label: "Wait around calls", value: Format.ms(approval.totalWaitMs))
                    KeyValue(label: "Prompted", value: "\(approval.promptedCalls)")
                    KeyValue(label: "Auto-approved", value: "\(approval.autoApprovedCalls)")
                    KeyValue(label: "Denied", value: "\(approval.deniedCalls)")
                }
                Text(
                    "This sidecar predates PermissionRequest, so the wait cannot be split into your "
                        + "decision and the profiler's own dispatch overhead. Re-run install-hooks to "
                        + "measure them separately on future sessions."
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Panel(title: "Approval", note: "your decision split from dispatch overhead") {
                HStack(spacing: 28) {
                    KeyValue(label: "Your decisions", value: Format.ms(approval.decisionMs ?? 0))
                    KeyValue(label: "Median decision", value: Format.ms(approval.medianDecisionMs))
                    KeyValue(label: "Slowest", value: Format.ms(approval.slowestDecisionMs))
                    KeyValue(label: "Dispatch overhead", value: Format.ms(approval.overheadMs ?? 0))
                    KeyValue(label: "Prompted", value: "\(approval.promptedCalls)")
                    KeyValue(label: "Auto-approved", value: "\(approval.autoApprovedCalls)")
                    KeyValue(label: "Denied", value: "\(approval.deniedCalls)")
                }
                Text("Dispatch overhead is hook spawns and CC dispatch, not you waiting.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reliability(_ reliability: HookInsights.Reliability) -> some View {
        Panel(title: "Retry tax", note: "time spent on calls that did not succeed") {
            HStack(spacing: 28) {
                KeyValue(label: "Failed", value: "\(reliability.failedCalls)")
                KeyValue(label: "of which interrupts", value: "\(reliability.interruptedCalls)")
                KeyValue(label: "Denied", value: "\(reliability.deniedCalls)")
                KeyValue(label: "Wasted", value: Format.ms(reliability.wastedMs))
            }
            ForEach(reliability.byTool.prefix(6)) { failure in
                HStack(spacing: 8) {
                    Text(failure.name).font(.system(size: 11, weight: .medium)).frame(width: 110, alignment: .leading)
                    Text("\(failure.failedCalls) failed · \(failure.interruptedCalls) interrupted")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let preview = failure.errorPreview, !preview.isEmpty {
                        Text(preview).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer()
                    Text(Format.ms(failure.wastedMs)).font(.system(size: 11)).monospacedDigit()
                }
            }
        }
    }

    private func pollution(_ pollution: HookInsights.ContextPollution) -> some View {
        Panel(title: "Context pollution", note: "tool result bytes, re-billed as cache read on every later turn") {
            HStack(spacing: 28) {
                KeyValue(label: "Total result bytes", value: Format.bytes(pollution.totalBytes))
                KeyValue(label: "Largest single result", value: Format.bytes(pollution.maxBytes))
            }
            let peak = max(1, pollution.byTool.map(\.totalBytes).max() ?? 1)
            ForEach(pollution.byTool.prefix(8)) { tool in
                BarRow(
                    label: tool.name,
                    value: Format.bytes(tool.totalBytes),
                    fraction: tool.totalBytes / peak,
                    color: .orange,
                    detail: "\(tool.calls)×"
                )
                .help("median \(Format.bytes(tool.medianBytes)) · max \(Format.bytes(tool.maxBytes))")
            }
        }
    }

    private func parallelism(_ parallelism: HookInsights.Parallelism) -> some View {
        Panel(title: "Parallelism") {
            HStack(spacing: 28) {
                KeyValue(label: "Batches", value: "\(parallelism.batches)")
                KeyValue(label: "With >1 call", value: "\(parallelism.multiCallBatches)")
                KeyValue(label: "Largest", value: "\(parallelism.largestBatch)")
                KeyValue(label: "Saved by batching", value: Format.ms(parallelism.savedMs))
            }
            if let saved = parallelism.savedMs {
                Text(
                    "\(Format.ms(parallelism.serialMs ?? 0)) of work in "
                        + "\(Format.ms(parallelism.wallMs ?? 0)) of wall clock — \(Format.ms(saved)) saved."
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            } else {
                Text("A batch member never reported its duration, so the saving cannot be measured.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cacheWaste(_ waste: HookInsights.CacheWaste) -> some View {
        Panel(title: "Cache rewrites", note: "what a cold context window cost to re-cache") {
            HStack(spacing: 28) {
                KeyValue(label: "Resumes", value: "\(waste.resumes)")
                KeyValue(label: "After resume", value: Format.usd(waste.resumeUsd))
                KeyValue(label: "Model switches", value: "\(waste.modelSwitches)")
                KeyValue(label: "After model switch", value: Format.usd(waste.modelSwitchUsd))
                KeyValue(label: "Total", value: Format.usd(waste.totalUsd))
            }
            Text(cacheWasteNote(waste))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cacheWasteNote(_ waste: HookInsights.CacheWaste) -> String {
        guard waste.totalUsd != nil else { return "CC priced none of these, so no estimate is reported." }
        var note = "CC's own estimate"
        if let pricing = waste.pricing, !pricing.isEmpty {
            note += " (\(pricing.joined(separator: ", ")) pricing)"
        }
        if waste.switchesForfeitingWarmCache > 0 {
            note += " · \(waste.switchesForfeitingWarmCache) switch"
                + (waste.switchesForfeitingWarmCache == 1 ? "" : "es")
                + " threw away a warm cache"
        }
        return note + "."
    }

    private func lifecycle(_ hooks: HookInsights) -> some View {
        let lifecycle = hooks.lifecycle
        return Panel(title: "Session", note: lifecycle.idleMs > 0 ? "\(Format.ms(lifecycle.idleMs)) closed between runs" : nil) {
            HStack(spacing: 28) {
                if lifecycle.idleMs > 0 {
                    KeyValue(label: "Closed between runs", value: Format.ms(lifecycle.idleMs))
                }
                if let human = lifecycle.humanPrompts {
                    KeyValue(label: "Your prompts", value: "\(human)")
                }
                if let machine = lifecycle.machinePrompts, machine > 0 {
                    KeyValue(label: "Machine-injected", value: "\(machine)")
                }
                if let waiting = lifecycle.turnsWaitingOnBackground, waiting > 0 {
                    KeyValue(label: "Turns left waiting", value: "\(waiting)")
                }
                if let compaction = hooks.compaction {
                    KeyValue(label: "Compactions", value: "\(compaction.count) (\(compaction.autoCount) auto)")
                }
                if let reason = lifecycle.endReason {
                    KeyValue(label: "Ended by", value: reason)
                }
            }
            if !lifecycle.injectedSources.isEmpty {
                Text(
                    "Injected by: "
                        + lifecycle.injectedSources.map { "\($0.key)×\($0.count)" }.joined(separator: ", ")
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            if let compaction = hooks.compaction, let totalMs = compaction.totalMs {
                Text("\(Format.ms(totalMs)) spent compacting.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(Array(lifecycle.starts.enumerated()), id: \.offset) { _, start in
                HStack(spacing: 8) {
                    Image(systemName: start.source == "resume" ? "arrow.clockwise" : "power")
                        .foregroundStyle(.secondary)
                    Text(start.at.clockTime).monospacedDigit()
                    Text(start.source).foregroundStyle(.secondary)
                    if let idle = start.idleMs { Text("· idle \(Format.ms(idle))").foregroundStyle(.secondary) }
                    if start.cacheLikelyExpired == true {
                        Text("· cache expired").foregroundStyle(.orange)
                    }
                    if let usd = start.cacheWriteUsd, usd > 0 {
                        Text("· re-cached for \(Format.usd(usd))").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .font(.system(size: 11))
            }
        }
    }

    private func commands(_ commands: [HookInsights.CommandCost]) -> some View {
        Panel(title: "Cost per slash command", note: "tool execution time, by what invoked it") {
            let peak = max(1, commands.map(\.toolExecMs).max() ?? 1)
            ForEach(commands.prefix(8)) { command in
                BarRow(
                    label: "/\(command.commandName)",
                    value: Format.ms(command.toolExecMs),
                    fraction: command.toolExecMs / peak,
                    color: .indigo,
                    detail: "\(command.runs)×"
                )
                .help("\(command.runs) run\(command.runs == 1 ? "" : "s") · \(command.toolCalls) tool calls")
            }
        }
    }

    private func subagents(_ subagents: [HookInsights.SubagentSpan]) -> some View {
        Panel(title: "Subagents", note: "as the hook trace saw them") {
            ForEach(subagents.prefix(8)) { subagent in
                HStack(spacing: 8) {
                    Text(subagent.subagentType ?? subagent.subagentId)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 140, alignment: .leading)
                        .lineLimit(1)
                    Text("\(subagent.toolCalls) calls · \(Format.ms(subagent.toolExecMs)) of tool time")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(subagent.spanMs.map(Format.ms) ?? "still running")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
            }
        }
    }

    private func streaming(_ streaming: HookInsights.Streaming) -> some View {
        Panel(title: "Streaming", note: "first to last visible flush") {
            HStack(spacing: 28) {
                KeyValue(label: "Messages", value: "\(streaming.messages)")
                KeyValue(label: "Median", value: Format.ms(streaming.medianStreamMs))
                KeyValue(label: "p90", value: Format.ms(streaming.p90StreamMs))
                KeyValue(label: "Visible output", value: Format.bytes(streaming.totalDeltaBytes))
            }
        }
    }

    private func instructions(_ instructions: HookInsights.Instructions) -> some View {
        Panel(title: "Instructions loaded", note: "\(instructions.totalLoads) loads") {
            ForEach(instructions.files.prefix(8)) { file in
                HStack(spacing: 8) {
                    Text(file.memoryType ?? "?")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Text(file.filePath).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Text(file.loadReason ?? "?").font(.system(size: 10)).foregroundStyle(.tertiary)
                    if file.loads > 1 {
                        Text("×\(file.loads)").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }
}
