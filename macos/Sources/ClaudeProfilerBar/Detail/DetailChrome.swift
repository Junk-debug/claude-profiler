import ProfilerBarCore
import SwiftUI

/// A titled block, the unit every detail tab is built from.
struct Panel<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline)
                if let note {
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row of a proportion list: label, bar, value, share.
struct BarRow: View {
    let label: String
    let value: String
    let fraction: Double
    var color: Color = .accentColor
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 8)
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(2, geometry.size.width * min(1, max(0, fraction))), height: 8)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(width: 66, alignment: .trailing)
            Text(detail ?? Format.percent(ratio: fraction))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }
}

/// The buckets both UIs name, in the order both UIs show them, in one palette.
/// `idle` and `stalled` are deliberately not selectable: there is nothing
/// underneath idle but "the session was closed", and stalled time is already
/// itemised inside the Model tab.
enum TimeSplitSegment: String, Identifiable {
    case model, tools, you, idle, stalled, unaccounted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .model: "Model"
        case .tools: "Tools"
        case .you: "You"
        case .idle: "Idle"
        case .stalled: "Stalled"
        case .unaccounted: "Unaccounted"
        }
    }

    var color: Color {
        switch self {
        case .model: .purple
        case .tools: .teal
        case .you: .orange
        case .idle: .blue
        // Deliberately the quietest colour on the bar. The row can be three
        // quarters of a session, and a loud block that size reads as an alarm
        // about something the person did wrong, when all it says is that the
        // laptop was asleep.
        case .stalled: .gray
        case .unaccounted: .secondary
        }
    }

    /// Which tab answers "what is in this bucket", or nil when nothing does.
    var destination: SessionDetailView.Tab? {
        switch self {
        case .model: .model
        case .tools: .tools
        case .you, .unaccounted, .idle, .stalled: nil
        }
    }
}

/// The headline session split, always as percentages of the span so the rows
/// sum to 100% regardless of rounding on any individual bar.
///
/// Mirrors `src/tui/TimeSplitBar.tsx` exactly, including the two corrections
/// that only the terminal UI used to make: session-idle time comes out of
/// "You" (via `phases`) rather than being added beside an uncorrected "You",
/// and `stalledMs` — a request that ran for hours below a tenth of the
/// session's own token rate — comes out of Model into a row of its own.
struct TimeSplitBar: View {
    let split: TimeSplit
    /// `timeline` with known session-idle time carved out of "You".
    var phases: PhaseSplit?
    /// `ModelBreakdown.suspectMs`: model time that was probably not the model
    /// working. A subset of Model by construction, so it is only ever moved out
    /// of that one bucket, never invented or double-counted.
    var stalledMs: Double = 0
    /// Drop the stalled time from the span as well as from Model, so every
    /// percentage describes the time the session was demonstrably working.
    var excludeStalled = false
    var onSelect: ((SessionDetailView.Tab) -> Void)?

    /// Clamped to the bucket it comes out of: anything that broke that
    /// invariant should render a short bar rather than a negative one.
    private var stalled: Double { min(max(0, stalledMs), split.modelMs) }

    private var spanMs: Double {
        max(0, excludeStalled ? split.spanMs - stalled : split.spanMs)
    }

    private var segments: [(segment: TimeSplitSegment, ms: Double)] {
        var parts: [(TimeSplitSegment, Double)] = [
            (.model, split.modelMs - stalled),
            (.tools, split.toolsMs),
            (.you, phases?.userMs ?? split.userMs),
        ]
        if let idleMs = phases?.idleMs, idleMs > 0 { parts.append((.idle, idleMs)) }
        if stalled > 0, !excludeStalled { parts.append((.stalled, stalled)) }
        parts.append((.unaccounted, phases?.unaccountedMs ?? split.unaccountedMs))
        return parts.map { (segment: $0.0, ms: $0.1) }
    }

    var body: some View {
        let total = max(1, spanMs)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(segments, id: \.segment.id) { part in
                        part.segment.color
                            .frame(width: max(0, geometry.size.width * part.ms / total) - 2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 18)

            HStack(spacing: 14) {
                ForEach(segments, id: \.segment.id) { part in
                    legend(part.segment, ms: part.ms, total: total)
                }
            }

            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func legend(_ segment: TimeSplitSegment, ms: Double, total: Double) -> some View {
        let row = HStack(spacing: 4) {
            Circle().fill(segment.color).frame(width: 7, height: 7)
            Text(segment.label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(Format.ms(ms)).font(.system(size: 10, weight: .medium)).monospacedDigit()
            Text(Format.percent(ratio: ms / total))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        if let destination = segment.destination, let onSelect {
            Button { onSelect(destination) } label: { row }
                .buttonStyle(.plain)
                .help("Open the \(destination.label) tab")
        } else {
            row
        }
    }

    /// The same sentences the terminal UI prints under its own bar: a number
    /// this large has to say why it is large, or it reads as an accusation.
    private var notes: [String] {
        var notes: [String] = []
        if stalled > 0 {
            notes.append(
                excludeStalled
                    ? "Stalled: \(Format.ms(stalled)) excluded — the rows above are the \(Format.ms(spanMs)) this session spent working."
                    : "Stalled: \(Format.ms(stalled)) split out of Model — a call that produced almost nothing while the clock ran (a slept machine, a dropped stream, a failed request)."
            )
        }
        if let phases, phases.reclaimedFromUserMs > 0 {
            let times = phases.phases.count == 1 ? "once" : "\(phases.phases.count) times"
            notes.append(
                "Idle: \(Format.ms(phases.reclaimedFromUserMs)) moved out of You — this transcript was resumed \(times), and the time between runs was never someone thinking."
            )
        }
        return notes
    }
}

/// The terminal UI's timing caveat, shown above every tab there and now here
/// too (src/tui/App.tsx).
///
/// A missing hook install outranks anything about this particular session: it
/// is the one thing the user can still act on, and it holds for every session
/// they profile next, so it is a warning even when this session did get
/// measured. With hooks in place there is nothing left to do, so a session
/// that predates them is a quiet note and a measured one says nothing at all.
struct ToolTimingCaveat: View {
    let profile: Profile
    let hooksInstalled: Bool

    private static let derived =
        "Tool time lumps together execution, approval waits, and idle gaps — these are derived, not exact."

    var body: some View {
        if let message {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: hooksInstalled ? "info.circle" : "exclamationmark.triangle")
                Text(message).fixedSize(horizontal: false, vertical: true)
                if !hooksInstalled {
                    Button("Copy install command") { Actions.copy("npx claude-profiler install-hooks") }
                        .buttonStyle(.link)
                }
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundStyle(hooksInstalled ? Color.secondary : Color.orange)
        }
    }

    private var message: String? {
        let derived = profile.timeline.precision == "derived"
        if !hooksInstalled {
            let lead = derived
                ? Self.derived
                : "This session was measured with hooks, but they are no longer installed."
            return lead + " Run claude-profiler install-hooks to split execution, approval and idle time"
                + " precisely on future sessions."
        }
        guard derived else { return nil }
        return Self.derived + " This session predates your hook install, so it can't be re-measured;"
            + " sessions started from now on will split execution, approval and idle time precisely."
    }
}

/// A key/value pair, used in the header strip of each tab.
struct KeyValue: View {
    let label: String
    let value: String
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1)
        }
        .help(help ?? "")
    }
}

struct EmptyTabNote: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

extension String {
    /// "2026-09-19T21:16:05.426Z" → "21:16:05", for table columns.
    var clockTime: String { Format.clock(self) }

    /// The same timestamp with its date, for headers and detail panes.
    var stampTime: String { Format.dateTime(self) }
}
