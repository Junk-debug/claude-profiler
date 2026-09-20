import ProfilerBarCore
import SwiftUI

/// One row per API request, with the rollups by cause, model and effort above
/// it — the terminal UI's Model → requests drill-down, plus its request detail
/// screen behind a click.
struct ModelTab: View {
    let profile: Profile

    @State private var sortOrder = [KeyPathComparator(\ModelRequest.totalMs, order: .reverse)]
    @State private var grouping: Grouping = .cause
    @State private var openedRequest: ModelRequest?

    enum Grouping: String, CaseIterable, Identifiable {
        case cause, model, effort

        var id: String { rawValue }
        var label: String {
            switch self {
            case .cause: "By cause"
            case .model: "By model"
            case .effort: "By effort"
            }
        }
    }

    private var rollups: [ModelRollup] {
        switch grouping {
        case .cause: profile.modelBreakdown.byCause
        case .model: profile.modelBreakdown.byModel
        case .effort: profile.modelBreakdown.byEffort
        }
    }

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("", selection: $grouping) {
                        ForEach(Grouping.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                    Spacer()
                    if profile.modelBreakdown.suspectMs > 0 {
                        Label(
                            "\(Format.ms(profile.modelBreakdown.suspectMs)) stalled",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help("Requests that produced tokens far below this session's median rate, or failed outright.")
                    }
                }

                Text("The same \(Format.ms(profile.modelBreakdown.totalMs)), grouped by what caused each request")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                let total = max(1, profile.modelBreakdown.totalMs)
                ForEach(rollups.prefix(6)) { rollup in
                    BarRow(
                        label: rollup.key,
                        value: Format.ms(rollup.ms),
                        fraction: rollup.ms / total,
                        color: .purple,
                        detail: "\(rollup.requests) req"
                    )
                }
            }
            .padding(16)
            .frame(minHeight: 200)

            requestTable
                .frame(minHeight: 200)
        }
        .sheet(item: $openedRequest) { request in
            ModelRequestSheet(request: request, breakdown: profile.modelBreakdown) { openedRequest = nil }
        }
    }

    private var requestTable: some View {
        Table(profile.modelBreakdown.requests.sorted(using: sortOrder), selection: selectionBinding, sortOrder: $sortOrder) {
            TableColumn("#", value: \.index) { Text("\($0.index + 1)").monospacedDigit().foregroundStyle(.secondary) }
                .width(40)
            TableColumn("Started") { Text(Format.clock($0.at)).monospacedDigit() }
                .width(70)
            TableColumn("Total", value: \.totalMs) { Text(Format.ms($0.totalMs)).monospacedDigit() }
                .width(66)
            TableColumn("1st block", value: \.firstBlockMs) { Text(Format.ms($0.firstBlockMs)).monospacedDigit() }
                .width(70)
            TableColumn("Later", value: \.continuationMs) {
                Text(Format.ms($0.continuationMs)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(62)
            TableColumn("Out", value: \.outputTokens) { Text(Format.tokens($0.outputTokens)).monospacedDigit() }
                .width(56)
            TableColumn("Think", value: \.thinkingTokens) {
                Text(Format.tokens($0.thinkingTokens)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(56)
            TableColumn("tok/s") { request in
                Text(Format.rate(request.tokensPerSec))
                    .monospacedDigit()
                    .foregroundStyle(request.suspect == nil ? Color.primary : Color.orange)
            }
            .width(56)
            TableColumn("Context", value: \.contextTokens) {
                Text(Format.tokens($0.contextTokens)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(70)
            TableColumn("Cause") { request in
                HStack(spacing: 6) {
                    Text(request.cause?.label ?? "—").lineLimit(1).foregroundStyle(.secondary)
                    if let suspect = request.suspect {
                        Label(suspect == "api_error" ? "api error" : "stalled", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    /// The table's selection is only ever used to open a row's detail, so it
    /// is a binding that acts rather than state that accumulates.
    private var selectionBinding: Binding<ModelRequest.ID?> {
        Binding(
            get: { openedRequest?.id },
            set: { id in
                openedRequest = id.flatMap { key in profile.modelBreakdown.requests.first { $0.id == key } }
            }
        )
    }
}

/// Everything the transcript knows about one API request. The point of the
/// sheet is the pair of numbers at the top: a slow request is either one that
/// produced a lot (high tok/s, long) or one that was waiting (low tok/s) — the
/// same duration means two completely different things.
struct ModelRequestSheet: View {
    let request: ModelRequest
    let breakdown: ModelBreakdown
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Request #\(request.index + 1) — \(Format.ms(request.totalMs))")
                    .font(.system(size: 13, weight: .semibold))
                if let suspect = request.suspect {
                    Label(suspectNote(suspect), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    KeyValue(label: "Started", value: Format.dateTime(request.at))
                    KeyValue(label: "Request id", value: request.requestId ?? "—")
                    KeyValue(label: "Turn", value: "\(request.turnIndex + 1)")
                    KeyValue(label: "Caused by", value: request.cause?.label ?? "—")
                }
                VStack(alignment: .leading, spacing: 6) {
                    KeyValue(label: "Model", value: request.model.map(Format.model) ?? "—")
                    KeyValue(label: "Effort", value: request.effort ?? "—")
                    KeyValue(label: "Stop reason", value: request.stopReason ?? "—")
                    KeyValue(label: "Blocks", value: blocks)
                }
                VStack(alignment: .leading, spacing: 6) {
                    KeyValue(label: "First block", value: Format.ms(request.firstBlockMs))
                    KeyValue(label: "Later blocks", value: Format.ms(request.continuationMs))
                    KeyValue(
                        label: "Output",
                        value: "\(Format.tokens(request.outputTokens)) (\(Format.tokens(request.thinkingTokens)) thinking)"
                    )
                    KeyValue(label: "Context carried", value: Format.tokens(request.contextTokens))
                }
            }

            Text(throughputNote)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let full = request.full, !full.isEmpty {
                Text("What it wrote").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ScrollView {
                    Text(full)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }

            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720)
    }

    private var blocks: String {
        guard !request.blocks.isEmpty else { return "—" }
        var counts: [String: Int] = [:]
        for kind in request.blocks { counts[kind, default: 0] += 1 }
        return counts.sorted { $0.key < $1.key }.map { "\($0.value)× \($0.key)" }.joined(separator: ", ")
    }

    private var throughputNote: String {
        let rate = request.tokensPerSec == nil ? "no measurable rate" : "\(Format.rate(request.tokensPerSec)) tok/s"
        guard let threshold = breakdown.stallThresholdTokensPerSec else {
            return "First block is queue + reading the prompt back in + the block itself. Throughput: \(rate)."
        }
        return "First block is queue + reading the prompt back in + the block itself. Throughput: \(rate)"
            + " — the session median sets a \(String(format: "%.1f", threshold)) tok/s floor."
    }

    private func suspectNote(_ suspect: String) -> String {
        if suspect == "api_error" { return "CC wrote this record itself after the API call failed" }
        guard let threshold = breakdown.stallThresholdTokensPerSec else {
            return "below this session's stall floor for over a minute — probably waiting, not generating"
        }
        return "below \(String(format: "%.1f", threshold)) tok/s for over a minute — probably waiting, not generating"
    }
}
