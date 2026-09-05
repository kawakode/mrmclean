import SwiftUI
import MrMcLeanCore

/// Full-window overlay shown during and after a full clean: an animated run view
/// that steps through each phase, then a report.
struct FullCleanView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ZStack {
            AnimatedBackdrop()
            if let report = store.fullCleanReport {
                Group {
                    if report.isComplete {
                        FullCleanReportView(report: report) { store.dismissFullClean() }
                    } else {
                        FullCleanRunningView(report: report)
                    }
                }
                .frame(maxWidth: 520)
                .padding(40)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.4), value: store.fullCleanReport?.isComplete)
    }
}

// MARK: - Running

private struct FullCleanRunningView: View {
    let report: FullCleanReport

    private var runningPhase: FullCleanPhase? {
        report.phases.first { $0.status == .running }
    }

    private var subtitle: String {
        if let phase = runningPhase { return "Working on \(phase.title.lowercased())" }
        if report.resolvedPhaseCount == 0 { return "Measuring your disk…" }
        return "Finishing up"
    }

    var body: some View {
        VStack(spacing: 24) {
            CleanProgressRing(
                progress: report.progress,
                symbol: runningPhase?.symbol ?? "sparkles",
                running: true
            )

            VStack(spacing: 4) {
                Text("Cleaning up")
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            phaseList

            VStack(spacing: 2) {
                Text(Format.bytes(report.totalFreedBytes))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: report.totalFreedBytes)
                Text("freed so far")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Keep MrMcLean open until this finishes.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4))
        )
    }

    private var phaseList: some View {
        VStack(spacing: 10) {
            ForEach(report.phases) { phase in
                FullCleanPhaseRow(phase: phase)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Report

private struct FullCleanReportView: View {
    let report: FullCleanReport
    var onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            CompletionBadge(failed: report.anyFailed)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 6) {
                Text(report.anyFailed ? "Cleaned, with a hitch" : "All clean")
                    .font(.title.weight(.semibold))
                Text("Freed \(Format.bytes(report.headlineFreedBytes))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
                Text(summaryLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            diskCard
            breakdownCard

            Button {
                onDone()
            } label: {
                Text("Done").frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4))
        )
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
        }
    }

    private var summaryLine: String {
        var parts = ["\(report.totalRemoved) item\(report.totalRemoved == 1 ? "" : "s") removed"]
        parts.append("in \(formattedDuration)")
        if report.totalSkipped > 0 { parts.append("\(report.totalSkipped) skipped") }
        return parts.joined(separator: " · ")
    }

    private var formattedDuration: String {
        let seconds = Int(report.duration.rounded())
        if seconds < 60 { return "\(max(1, seconds))s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Disk").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Text("Before").foregroundStyle(.secondary)
                Spacer()
                Text(Format.bytes(report.diskBefore.availableBytes) + " free").monospacedDigit()
            }
            .font(.callout)
            if let after = report.diskAfter {
                UsageBar(fraction: after.usedFraction, threshold: nil, tint: .accentColor)
                HStack {
                    Text("Now").foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.bytes(after.availableBytes) + " free")
                        .monospacedDigit().foregroundStyle(.green)
                }
                .font(.callout)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var breakdownCard: some View {
        VStack(spacing: 8) {
            ForEach(report.phases) { phase in
                HStack(spacing: 10) {
                    Image(systemName: phaseSymbol(phase))
                        .foregroundStyle(phaseTint(phase))
                        .frame(width: 18)
                    Text(phase.title).font(.callout)
                    Spacer()
                    Text(phaseValue(phase))
                        .font(.callout).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func phaseSymbol(_ phase: FullCleanPhase) -> String {
        switch phase.status {
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle.fill"
        default: return "checkmark.circle.fill"
        }
    }

    private func phaseTint(_ phase: FullCleanPhase) -> Color {
        switch phase.status {
        case .failed: return .orange
        case .skipped: return .secondary
        default: return .green
        }
    }

    private func phaseValue(_ phase: FullCleanPhase) -> String {
        if phase.status == .failed { return "failed" }
        if phase.status == .skipped { return "skipped" }
        if phase.freedBytes > 0 {
            let suffix = phase.note?.contains("stimated") == true ? " est." : ""
            return Format.bytes(phase.freedBytes) + suffix
        }
        return phase.note ?? "—"
    }
}

// MARK: - Pieces

private struct CleanProgressRing: View {
    var progress: Double
    var symbol: String
    var running: Bool

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0.002, progress))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.cyan, .blue, .purple, .cyan]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: progress)
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, options: .repeating, isActive: running)
        }
        .frame(width: 150, height: 150)
    }
}

private struct FullCleanPhaseRow: View {
    var phase: FullCleanPhase

    var body: some View {
        HStack(spacing: 12) {
            statusIcon.frame(width: 20)
            Text(phase.title).font(.callout)
            Spacer()
            trailing
        }
        .opacity(phase.status == .pending ? 0.4 : 1)
        .animation(.smooth, value: phase.status)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch phase.status {
        case .pending:
            Image(systemName: phase.symbol).foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        case .skipped:
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if phase.freedBytes > 0 {
            Text(Format.bytes(phase.freedBytes))
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                .contentTransition(.numericText())
        } else if phase.status == .failed {
            Text(phase.note ?? "failed")
                .font(.caption).foregroundStyle(.orange).lineLimit(1)
        } else if let note = phase.note, phase.status != .running {
            Text(note).font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct CompletionBadge: View {
    var failed: Bool
    @State private var shimmer = false

    var body: some View {
        ZStack {
            Circle()
                .fill((failed ? Color.orange : Color.green).opacity(0.15))
                .frame(width: 92, height: 92)
            Image(systemName: failed ? "checkmark.circle.trianglebadge.exclamationmark" : "checkmark.circle.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(failed ? Color.orange : Color.green)
                .symbolEffect(.bounce, value: shimmer)

            if !failed {
                ForEach(Array(sparkleOffsets.enumerated()), id: \.offset) { index, offset in
                    Image(systemName: "sparkle")
                        .font(.system(size: index.isMultiple(of: 2) ? 12 : 8))
                        .foregroundStyle(Color.green.opacity(0.8))
                        .offset(offset)
                        .opacity(shimmer ? 0.9 : 0.2)
                        .scaleEffect(shimmer ? 1 : 0.5)
                        .animation(
                            .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(Double(index) * 0.12),
                            value: shimmer
                        )
                }
            }
        }
        .onAppear { shimmer = true }
    }

    private let sparkleOffsets: [CGSize] = [
        CGSize(width: 0, height: -62),
        CGSize(width: 59, height: -19),
        CGSize(width: 36, height: 50),
        CGSize(width: -36, height: 50),
        CGSize(width: -59, height: -19),
    ]
}

private struct AnimatedBackdrop: View {
    @State private var shift = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [Color.accentColor.opacity(0.16), Color.purple.opacity(0.10), .clear],
                startPoint: shift ? .topLeading : .bottomTrailing,
                endPoint: shift ? .bottomTrailing : .topLeading
            )
            .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: shift)
        }
        .ignoresSafeArea()
        .onAppear { shift = true }
    }
}

// MARK: - Setup sheet

struct FullCleanSetupSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var includeSystem = false
    @State private var includeSnapshots = true

    private var preview: (steps: [FullCleanStep], estimatedBytes: Int64) {
        store.fullCleanPreview(includeSystem: includeSystem, includeSnapshots: includeSnapshots)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text("Full Clean").font(.title3.weight(.semibold))
                    Text("Clears every safe category in one pass.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(preview.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 10) {
                        Image(systemName: step.symbol).frame(width: 18).foregroundStyle(.secondary)
                        Text(step.title).font(.callout)
                        Spacer()
                        Text(stepEstimate(step)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    if index < preview.steps.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            if store.enabledDevToolIDs.isEmpty {
                Text("Dev tool caches are cleaned only for tools you enable in Settings › Cleaners.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Toggle(isOn: $includeSystem) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also clean system caches & logs")
                    Text("Root-owned files. Asks for your administrator password once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if includeSystem {
                Toggle("Thin Time Machine local snapshots", isOn: $includeSnapshots)
                    .padding(.leading, 20)
            }

            HStack {
                Text("Estimated reclaim")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("~\(Format.bytes(preview.estimatedBytes))")
                    .font(.callout.weight(.semibold)).monospacedDigit()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start Full Clean") {
                    let system = includeSystem
                    let snapshots = includeSnapshots
                    dismiss()
                    Task { await store.performFullClean(includeSystem: system, includeSnapshots: snapshots) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func stepEstimate(_ step: FullCleanStep) -> String {
        switch step.work {
        case .userCategory(let id):
            return Format.bytes(store.snapshot?.category(id)?.totalBytes ?? 0)
        case .devTools:
            return Format.bytes(store.snapshot?.category("devTools")?.totalBytes ?? 0)
        case .system(let snapshots):
            let bytes = (store.snapshot?.category("systemCaches")?.totalBytes ?? 0)
                + (snapshots ? (store.snapshot?.category("snapshots")?.totalBytes ?? 0) : 0)
            return "~\(Format.bytes(bytes))"
        }
    }
}
