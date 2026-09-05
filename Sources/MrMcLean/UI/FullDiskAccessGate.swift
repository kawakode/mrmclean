import SwiftUI
import AppKit
import MrMcLeanCore

/// First-run screen shown until MrMcLean holds Full Disk Access. It explains the
/// grant, opens the right System Settings pane, and re-checks on a timer so it
/// disappears on its own once access is given.
struct FullDiskAccessGate: View {
    @Environment(Store.self) private var store
    @State private var pulse = false
    @State private var justChecked = false

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 22) {
                icon
                VStack(spacing: 8) {
                    Text("MrMcLean needs Full Disk Access")
                        .font(.title.weight(.semibold))
                    Text("""
                    macOS keeps caches, logs, Mail, Messages and Safari data hidden from \
                    apps that don't hold Full Disk Access. Without it MrMcLean can't measure \
                    your storage accurately or clean it.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
                }

                steps

                waitingIndicator

                VStack(spacing: 10) {
                    Button {
                        openSettings()
                    } label: {
                        Text("Open Full Disk Access Settings")
                            .frame(maxWidth: 300)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    HStack(spacing: 14) {
                        Button("Check Again") {
                            store.refreshAccess()
                            withAnimation { justChecked = true }
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation { justChecked = false }
                            }
                        }
                        if isBundled {
                            Button("Quit & Reopen") { relaunch() }
                        }
                    }
                    .controlSize(.small)

                    Button("Continue with limited access") {
                        store.continueWithoutAccess()
                    }
                    .buttonStyle(.link)
                    .padding(.top, 2)
                }
            }
            .padding(40)
            .frame(maxWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await pollForAccess() }
        .onAppear { pulse = true }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor),
                     Color(nsColor: .underPageBackgroundColor)],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(alignment: .top) {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(y: -160)
        }
        .ignoresSafeArea()
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 96, height: 96)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)
            Image(systemName: "lock.shield")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            gateStep(1, "Click the button below to open System Settings.")
            gateStep(2, "Turn on the switch next to MrMcLean. Add it with \(Image(systemName: "plus")) if it isn't listed.")
            gateStep(3, "Come back here — this screen closes itself once access is on.")
        }
        .font(.callout)
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        )
    }

    private func gateStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
            Text(text).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var waitingIndicator: some View {
        HStack(spacing: 8) {
            if store.fullDiskAccess == .granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Access granted — starting…")
            } else {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .opacity(pulse ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text(justChecked ? "Still off — grant it in System Settings, then it updates here."
                                 : "Waiting for access…")
                    .contentTransition(.opacity)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    // MARK: Behaviour

    private func pollForAccess() async {
        while !Task.isCancelled {
            if store.refreshAccess() {
                store.applyActivationPolicy()
                await store.scan()
                return
            }
            if store.fullDiskAccess == .granted { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func openSettings() {
        if let url = URL(string: FullDiskAccess.settingsURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
