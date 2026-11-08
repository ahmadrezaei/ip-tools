// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

public struct PingView: View {
    @Bindable private var model: PingModel
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var showSettings = false

    public init(model: PingModel) {
        self.model = model
    }

    private var isRegular: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    public var body: some View {
        VStack(spacing: 0) {
            TargetInputBar(
                text: $model.targetText, placeholder: "IP address or hostname",
                systemImage: "dot.radiowaves.left.and.right", mode: .host, primaryTitle: "Start",
                isRunning: model.isBusy, isEnabled: true, recents: model.recentsStore,
                onSubmit: { model.start() }, onStop: { model.stop() })
            optionsRow
            content
        }
        .background(Color.screenBackground)
        .navigationTitle("Ping")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareTextButton(text: model.exportText, subject: "Ping \(model.runTarget)")
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet { PingSettingsView(settings: model.settings) }
        }
        .onAppear { model.consumePendingRequest() }
        .onChange(of: model.router?.requestTick) { model.consumePendingRequest() }
    }

    private var optionsRow: some View {
        let settings = model.settings
        let options = settings.ping
        let count = Binding<Int?>(get: { settings.ping.count }, set: { settings.ping.count = $0 })
        return HStack(spacing: 10) {
            PingCountMenu(count: count, isDisabled: model.isBusy)
            Button { showSettings = true } label: {
                Text("every \(options.interval, format: .number) s · \(options.payloadSize) bytes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Ping Settings")
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var content: some View {
        if model.phase == .idle && model.samples.isEmpty {
            ScrollView {
                ToolEmptyState(
                    title: "Ping a Host", systemImage: "dot.radiowaves.left.and.right",
                    message: "Measure round-trip time to any IPv4 or IPv6 address or hostname.",
                    examples: ["1.1.1.1", "2606:4700:4700::1111", "apple.com"],
                    onExample: { model.targetText = $0; model.start() },
                    recents: model.recentsStore, onRecent: { model.targetText = $0.display })
            }
        } else if case .failed = model.phase, model.samples.isEmpty, let error = model.error {
            ErrorStateView(error) { model.retry() }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if !model.samples.isEmpty { results }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            RunHeader(text: headerText, isLive: model.phase == .running, showsProgress: model.phase == .resolving)
            if model.canMapInBGP {
                Button { model.mapInBGP() } label: {
                    Label("Map in BGP", systemImage: "point.3.connected.trianglepath.dotted").font(.footnote)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    @ViewBuilder private var results: some View {
        if isRegular {
            HStack(alignment: .top, spacing: 12) {
                PingStatsGrid(stats: model.stats).frame(maxWidth: 360)
                chartCard
            }
        } else {
            PingStatsGrid(stats: model.stats)
            chartCard
        }
        LazyVStack(spacing: 0) {
            ForEach(model.samples.reversed()) { sample in
                PingRow(sample: sample)
                if sample.sequence != model.samples.first?.sequence { Divider() }
            }
        }
        .cardStyle(padding: 12)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Round-trip time").font(.footnote.weight(.semibold))
                Spacer()
                Text("last \(min(model.samples.count, PingChart.window)) · ms").font(.caption).foregroundStyle(.secondary)
            }
            PingChart(samples: model.samples, average: model.stats.avg)
        }
        .cardStyle()
    }

    private var headerText: AttributedString {
        let target = model.resolved
        let name = target?.input ?? model.runTarget
        switch model.phase {
        case .idle:
            return AttributedString()
        case .resolving:
            return AttributedString(segments: [(String(localized: "Resolving \(name)…"), false)])
        case .running:
            var parts: [(text: String, bold: Bool)] = [(String(localized: "Pinging "), false), (name, true)]
            if let target {
                if target.hostname != nil {
                    let version = target.address.family == .v6 ? "IPv6" : "IPv4"
                    parts.append((" → \(target.address) (\(version))", false))
                }
                parts.append((" · " + PingCount.progress(sent: model.stats.sent, count: model.runCount), false))
                parts.append((" · " + String(localized: "\(model.payloadSize) bytes"), false))
            }
            return AttributedString(segments: parts)
        case .finished:
            return AttributedString(segments: [(String(localized: "Finished · \(model.stats.sent) sent, \(model.stats.received) received"), false)])
        case .stopped(let reason):
            if let reason { return AttributedString(segments: [(String(localized: "Stopped — \(reason)"), false)]) }
            return AttributedString(segments: [(String(localized: "Stopped after \(model.stats.sent) pings"), false)])
        case .failed(let message):
            return AttributedString(segments: [(String(localized: "Stopped — \(message)"), false)])
        }
    }
}

#if DEBUG
@MainActor private func previewModel(_ configure: (PingModel) -> Void = { _ in }) -> PingModel {
    let defaults = UserDefaults(suiteName: "preview.ping") ?? .standard
    let model = PingModel(
        service: MockPingService(script: PingPreviewData.script, interval: .milliseconds(400)),
        settings: SettingsStore(defaults: defaults), recents: RecentsStore(defaults: defaults))
    configure(model)
    return model
}

enum PingPreviewData {
    static let cloudflare = IPAddress("1.1.1.1")!
    static let script: [PingSample.Outcome] = [
        .reply(rtt: 0.0123, bytes: 64, ttl: 58, from: cloudflare), .reply(rtt: 0.0141, bytes: 64, ttl: 58, from: cloudflare),
        .timeout, .reply(rtt: 0.0362, bytes: 64, ttl: 58, from: cloudflare),
        .reply(rtt: 0.121, bytes: 64, ttl: 58, from: cloudflare), .reply(rtt: 0.0131, bytes: 64, ttl: 58, from: cloudflare),
    ]
    static var samples: [PingSample] {
        script.enumerated().map { PingSample(sequence: $0.offset, sentAt: Date(), outcome: $0.element) }
    }
    static var target: ResolvedTarget {
        ResolvedTarget(input: "one.one.one.one", address: cloudflare, hostname: "one.one.one.one", allAddresses: [cloudflare])
    }
}

#Preview("Empty") { NavigationStack { PingView(model: previewModel()) } }

#Preview("Running (live mock)") {
    NavigationStack {
        PingView(model: previewModel { $0.targetText = "1.1.1.1"; $0.start() })
    }
}

#Preview("Resolving") {
    NavigationStack {
        PingView(model: previewModel { $0.runTarget = "apple.com"; $0.phase = .resolving })
    }
}

#Preview("Finished") {
    NavigationStack {
        PingView(model: previewModel {
            $0.resolved = PingPreviewData.target; $0.samples = PingPreviewData.samples
            $0.stats = PingStatistics(samples: PingPreviewData.samples); $0.phase = .finished
        })
    }
}

#Preview("Stopped by background") {
    NavigationStack {
        PingView(model: previewModel {
            $0.resolved = PingPreviewData.target; $0.samples = PingPreviewData.samples
            $0.stats = PingStatistics(samples: PingPreviewData.samples)
            $0.phase = .stopped(reason: "app moved to background")
        })
    }
}

#Preview("Resolve error") {
    NavigationStack {
        PingView(model: previewModel {
            $0.runTarget = "apple.cmo"
            $0.error = ToolError(.resolutionFailed(host: "apple.cmo", reason: ""))
            $0.phase = .failed("Couldn't Resolve apple.cmo")
        })
    }
}

#Preview("Local network denied") {
    NavigationStack {
        PingView(model: previewModel {
            $0.error = ToolError(.localNetworkDenied); $0.phase = .failed("Local Network access is off")
        })
    }
}

#Preview("Offline") {
    NavigationStack { PingView(model: previewModel { $0.targetText = "1.1.1.1" }) }
        .environment(\.isOnline, false)
}
#endif
