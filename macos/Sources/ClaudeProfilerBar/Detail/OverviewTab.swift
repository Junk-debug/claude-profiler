import ProfilerBarCore
import SwiftUI

/// Where the session's wall clock went, and what the four buckets contain —
/// the same six panels, in the same order, as the terminal UI's Overview tab
/// and its four drill-downs (Model, Tools, You, Unaccounted).
struct OverviewTab: View {
    let profile: Profile
    /// Clicking a bucket in the split bar, or "See all" under the tool list,
    /// goes to the tab that owns it.
    var selectTab: (SessionDetailView.Tab) -> Void = { _ in }

    /// `x` in the terminal UI: drop the stalled time and read the split over
    /// the working span only. Off by default — the first thing a session with
    /// an eleven-hour sleep in it has to say is that the sleep is there.
    @State private var excludeStalled = false
    @State private var openedPrompt: IdentifiedGap?

    private var stalledMs: Double { profile.modelBreakdown.suspectMs }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                timeSplit
                if let phases = profile.phases, !phases.phases.isEmpty { resumes(phases) }
                prompts
                unaccounted
                tools
                tokens
            }
            .padding(20)
        }
        .sheet(item: $openedPrompt) { prompt in
            PromptDetailSheet(gap: prompt.gap, index: prompt.id, total: profile.timeline.userGaps.count) {
                openedPrompt = nil
            }
        }
    }

    // MARK: Where the time went

    private var timeSplit: some View {
        Panel(
            title: "Where the time went",
            note: profile.timeline.precision == "exact"
                ? "exact, from hooks"
                : "derived from the transcript — Tools includes your approvals"
        ) {
            TimeSplitBar(
                split: profile.timeline,
                phases: profile.phases,
                stalledMs: stalledMs,
                excludeStalled: excludeStalled,
                onSelect: selectTab
            )
            if stalledMs > 0 {
                Button(excludeStalled ? "Show stalled time" : "Hide stalled time") {
                    excludeStalled.toggle()
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    private func resumes(_ phases: PhaseSplit) -> some View {
        Panel(title: "Resumes", note: "time the session sat closed, taken out of You") {
            ForEach(Array(phases.phases.enumerated()), id: \.offset) { _, resume in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                    Text(resume.resumedAt.clockTime).monospacedDigit()
                    Text("· idle \(Format.ms(resume.idleMs))").foregroundStyle(.secondary)
                    if let usd = resume.cacheWriteUsd, usd > 0 {
                        Text("· re-cached for \(Format.usd(usd))").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .font(.system(size: 11))
            }
        }
    }

    // MARK: You

    /// The terminal UI's You drill-down: one row per prompt, with how long it
    /// took to write — the gap between the previous reply ending and the
    /// prompt landing. Not a histogram, so a specific slow reply can be found
    /// rather than just counted.
    @ViewBuilder
    private var prompts: some View {
        let gaps = profile.timeline.userGaps
        if !gaps.isEmpty {
            Panel(title: "You", note: "\(gaps.count) prompt\(gaps.count == 1 ? "" : "s") that followed a reply · click one for its full text") {
                ForEach(Array(gaps.enumerated().sorted { $0.element.gapMs > $1.element.gapMs }.prefix(8)), id: \.offset) { index, gap in
                    Button {
                        openedPrompt = IdentifiedGap(id: index, gap: gap)
                    } label: {
                        HStack(spacing: 10) {
                            Text("#\(index + 1)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                                .frame(width: 34, alignment: .leading)
                            Text(gap.preview)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Format.ms(gap.gapMs))
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if gaps.count > 8 {
                    Text("Slowest 8 of \(gaps.count); the Timeline tab has them all, in order.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Unaccounted

    /// The parts of the bucket the transcript can name, then whatever is left
    /// as a row of its own. The remainder is always shown, even at zero, so
    /// the list can never be misread as a full decomposition of a bucket whose
    /// whole point is that its contents are unknown.
    private var unaccounted: some View {
        let timeline = profile.timeline
        let causes = timeline.unaccountedCauses
        let named = causes.reduce(0) { $0 + $1.ms }
        let span = max(1, timeline.spanMs)
        return Panel(
            title: "Unaccounted",
            note: causes.isEmpty ? "no known cause" : "that no bucket may claim"
        ) {
            HStack(spacing: 28) {
                KeyValue(label: "Total", value: Format.ms(timeline.unaccountedMs))
                KeyValue(label: "Share of the session", value: Format.percent(ratio: timeline.unaccountedMs / span))
            }
            ForEach(causes, id: \.label) { cause in
                BarRow(
                    label: cause.count > 1 ? "\(cause.label) (\(cause.count)×)" : cause.label,
                    value: Format.ms(cause.ms),
                    fraction: cause.ms / max(1, timeline.unaccountedMs),
                    color: .secondary
                )
            }
            if !causes.isEmpty {
                BarRow(
                    label: "no known cause",
                    value: Format.ms(max(0, timeline.unaccountedMs - named)),
                    fraction: max(0, timeline.unaccountedMs - named) / max(1, timeline.unaccountedMs),
                    color: .secondary.opacity(0.5)
                )
            }
            Text(unmatchedNote)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unmatchedNote: String {
        let unmatched = profile.diagnostics?.unmatchedToolUses ?? 0
        if unmatched > 0 {
            return "\(unmatched) tool call\(unmatched == 1 ? "" : "s") started but never recorded a result — an "
                + "interrupted or still-running session — and some of that time likely ended up here."
        }
        return profile.timeline.unaccountedCauses.isEmpty
            ? "No incomplete tool calls in this session; the rest is rounding and gaps between recorded events."
            : "No incomplete tool calls in this session."
    }

    // MARK: Tools

    private var tools: some View {
        Panel(
            title: "Tools",
            note: "\(profile.tools.count) tools · \(profile.tools.reduce(0) { $0 + $1.calls }) calls"
        ) {
            let peak = max(1, profile.tools.map(\.totalMs).max() ?? 1)
            ForEach(profile.tools.prefix(8)) { tool in
                BarRow(
                    label: tool.name,
                    value: Format.ms(tool.totalMs),
                    fraction: tool.totalMs / peak,
                    color: .teal,
                    detail: "\(tool.calls)×"
                )
            }
            if profile.tools.count > 8 {
                Button("See all \(profile.tools.count) tools") { selectTab(.tools) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
    }

    // MARK: Tokens

    /// What the model read and what it produced, on two scales rather than one.
    ///
    /// Input and output are not the same quantity: input counts the same
    /// context re-read on every request, output counts what was written, once.
    /// On a single scale output is a fraction of a percent and thinking is
    /// invisible inside it — which is the one thing this panel exists to show.
    private var tokens: some View {
        let bucket = profile.tokens.totals
        let output = bucket.output
        let thinking = min(bucket.thinking, output)
        let contextRows = TokenRow.context(of: bucket)
        let contextTotal = contextRows.reduce(0) { $0 + $1.count }
        let requests = profile.modelBreakdown.requests.count

        return VStack(alignment: .leading, spacing: 20) {
            Panel(title: "Output", note: "\(Format.tokens(output)) written · measured over \(requests) request\(requests == 1 ? "" : "s")") {
                BarRow(
                    label: "Thinking",
                    value: Format.tokens(thinking),
                    fraction: output > 0 ? Double(thinking) / Double(output) : 0,
                    color: .purple
                )
                BarRow(
                    label: "Generating",
                    value: Format.tokens(output - thinking),
                    fraction: output > 0 ? Double(output - thinking) / Double(output) : 0,
                    color: .teal
                )
            }

            if contextTotal > 0 {
                Panel(
                    title: "Context read back",
                    note: "\(Format.tokens(contextTotal)) over the session"
                        + (requests > 0 ? ", \(Format.tokens(contextTotal / requests)) per request" : "")
                ) {
                    ForEach(contextRows) { row in
                        BarRow(
                            label: row.label,
                            value: Format.tokens(row.count),
                            fraction: Double(row.count) / Double(contextTotal),
                            color: row.color
                        )
                    }
                }
            }
        }
    }
}

/// A prompt plus its position in the session, so a sheet can be presented for it.
struct IdentifiedGap: Identifiable {
    let id: Int
    let gap: UserGap
}

/// One prompt's full text, up to what the artifact kept, plus how long it took
/// to write — the terminal UI's PromptDetail screen.
struct PromptDetailSheet: View {
    let gap: UserGap
    let index: Int
    let total: Int
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Prompt \(index + 1) of \(total)").font(.headline)
            ScrollView {
                Text(gap.full.isEmpty ? gap.preview : gap.full)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            Text("Took \(Format.ms(gap.gapMs)) to write, since the previous reply ended.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// The context rows a session actually has. A kind that never occurred is left
/// out rather than shown at 0.0%: fresh input is a rounding error next to cache
/// reads on every real session, and a permanent empty row teaches the reader to
/// skip the block it sits in.
struct TokenRow: Identifiable {
    let id: String
    let label: String
    let count: Int
    let color: Color

    static func context(of bucket: TokenBucket) -> [TokenRow] {
        [
            TokenRow(id: "cacheRead", label: "Cache read", count: bucket.cacheRead, color: .blue),
            TokenRow(id: "cacheWrite", label: "Cache write", count: bucket.cacheCreate, color: .yellow),
            TokenRow(id: "freshInput", label: "Fresh input", count: bucket.input, color: .green),
        ].filter { $0.count > 0 }
    }
}
