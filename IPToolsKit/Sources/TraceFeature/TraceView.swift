// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import RIPEstat
import SharedUI
import SwiftUI

public struct TraceView: View {
    @Bindable private var model: TraceModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    public init(model: TraceModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TargetInputBar(
                text: $model.targetText, placeholder: "IP address or hostname",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                mode: .host, primaryTitle: "Start", isRunning: model.isBusy, isEnabled: true,
                recents: model.recentsStore, onSubmit: { model.start() }, onStop: { model.stop() })
            content
        }
        .background(Color.screenBackground)
        .navigationTitle("Traceroute")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareTextButton(text: model.exportText, subject: "Traceroute \(model.runTarget)")
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet { TraceSettingsView(settings: model.settings) }
        }
        .onAppear { model.consumePendingRequest() }
        .onChange(of: model.router.requestTick) { model.consumePendingRequest() }
        .onChange(of: scenePhase) { if scenePhase != .active { model.stopForBackground() } }
    }

    @ViewBuilder private var content: some View {
        if model.phase == .idle && model.hops.isEmpty {
            ScrollView {
                ToolEmptyState(
                    title: "Trace a Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    message: "See every router between you and a host, with response times and the network (AS) each one belongs to.",
                    examples: ["8.8.8.8", "1.1.1.1", "apple.com"],
                    onExample: { model.targetText = $0; model.start() },
                    recents: model.recentsStore, onRecent: { model.targetText = $0.display })
            }
        } else if case .failed = model.phase, model.hops.isEmpty, let error = model.error {
            ErrorStateView(error) { model.retry() }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if case let .finished(completion) = model.phase {
                        TraceSummaryCard(completion: completion, target: model.resolved, hops: model.hops,
                                         maxHops: model.activeOptions.maxHops)
                    }
                    if !model.hops.isEmpty || model.currentTTL != nil { hopList }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                RunHeader(text: headerText, isLive: model.currentTTL != nil, showsProgress: model.phase == .resolving)
                if model.canMapTarget {
                    Button { model.mapTarget() } label: {
                        Label("Map in BGP", systemImage: Tool.bgp.systemImage).font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            if let ttl = model.currentTTL {
                ProgressView(value: Double(ttl), total: Double(max(model.activeOptions.maxHops, 1)))
                    .padding(.horizontal, 4)
            }
        }
    }

    private var hopList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOP · HOST · AVG · PROBES (MS)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            LazyVStack(spacing: 0) {
                ForEach(model.hops) { hop in
                    HopRow(hop: hop, isPending: hop.ttl == model.currentTTL,
                           onPing: { model.pingHop($0) }, onMap: { model.mapHop($0) })
                    if hop.ttl != model.hops.last?.ttl || showsPlaceholder { Divider() }
                }
                if showsPlaceholder, let ttl = model.currentTTL { HopPlaceholderRow(ttl: ttl) }
            }
            .cardStyle()
        }
    }

    /// The TTL being probed has no row yet.
    private var showsPlaceholder: Bool {
        guard let ttl = model.currentTTL else { return false }
        return !model.hops.contains { $0.ttl == ttl }
    }

    private var headerText: AttributedString {
        let name = model.resolved?.input ?? model.runTarget
        switch model.phase {
        case .idle:
            return AttributedString()
        case .resolving:
            return AttributedString(segments: [(String(localized: "Resolving \(name)…"), false)])
        case let .tracing(ttl):
            var parts: [(text: String, bold: Bool)] = [(String(localized: "Tracing "), false), (name, true)]
            if let target = model.resolved, target.hostname != nil { parts.append((" → \(target.address)", false)) }
            parts.append((" · " + String(localized: "hop \(ttl) of max \(model.activeOptions.maxHops)"), false))
            return AttributedString(segments: parts)
        case .finished:
            let count = model.hops.count
            return AttributedString(segments: [(String(localized: "Finished · \(count) hops"), false)])
        case .stopped(let reason):
            if let reason { return AttributedString(segments: [(String(localized: "Stopped — \(reason)"), false)]) }
            return AttributedString(segments: [(String(localized: "Stopped at hop \(model.hops.count)"), false)])
        case .failed(let message):
            return AttributedString(segments: [(String(localized: "Stopped — \(message)"), false)])
        }
    }
}

#if DEBUG
enum TracePreviewData {
    static let cloudflare = IPAddress("1.1.1.1")!
    static func hop(_ ttl: Int, _ address: String, host: String? = nil, asn: HopASN? = nil, dest: Bool = false,
                    rtts: [TimeInterval?] = [0.0094, 0.0089, 0.0102]) -> TraceHop {
        let ip = IPAddress(address)!
        let probes: [ProbeResult] = rtts.map { rtt in
            guard let rtt else { return .timeout }
            return dest ? .echoReply(from: ip, rtt: rtt) : .timeExceeded(from: ip, rtt: rtt)
        }
        return TraceHop(ttl: ttl, probes: probes, addresses: [ip], hostname: host, asn: asn, isDestination: dest)
    }
    static let comcast = HopASN(asn: 7922, name: "Comcast", prefix: "96.120.0.0/16")
    static var hops: [TraceHop] {
        [
            hop(1, "192.168.1.1", host: "router.lan", rtts: [0.0018, 0.0020, 0.0017]),
            hop(2, "96.120.24.29", asn: comcast),
            hop(3, "68.86.181.33", host: "po-303-1209-rur02.sanjose.ca.sfba.comcast.net", asn: comcast, rtts: [0.0101, 0.0098, nil]),
            TraceHop(ttl: 4, probes: [.timeout, .timeout, .timeout]),
            hop(5, "1.1.1.1", host: "one.one.one.one", asn: HopASN(asn: 13335, name: "Cloudflare", prefix: "1.1.1.0/24"), dest: true,
                rtts: [0.0129, 0.0126, 0.0131]),
        ]
    }
    static var target: ResolvedTarget {
        ResolvedTarget(input: "1.1.1.1", address: cloudflare, hostname: nil, allAddresses: [cloudflare])
    }
}

@MainActor private func previewModel(_ configure: (TraceModel) -> Void = { _ in }) -> TraceModel {
    let defaults = UserDefaults(suiteName: "preview.trace") ?? .standard
    let model = TraceModel(
        service: MockTraceService(hops: AppPreviewHops.hops), asnLookup: ASNLookup(api: MockRIPEstat(fixtureBundle: .main)),
        settings: SettingsStore(defaults: defaults), recents: RecentsStore(defaults: defaults), router: AppRouter())
    configure(model)
    return model
}

enum AppPreviewHops {
    static let hops: [[ProbeResult]] = TracePreviewData.hops.map { $0.probes }
}

#Preview("Empty") { NavigationStack { TraceView(model: previewModel()) } }

#Preview("Tracing (live mock)") {
    NavigationStack { TraceView(model: previewModel { $0.targetText = "1.1.1.1"; $0.start() }) }
}

#Preview("Tracing (static)") {
    NavigationStack {
        TraceView(model: previewModel {
            $0.resolved = TracePreviewData.target; $0.runTarget = "1.1.1.1"
            $0.hops = Array(TracePreviewData.hops.prefix(3)); $0.phase = .tracing(currentTTL: 4)
        })
    }
}

#Preview("Finished: reached") {
    NavigationStack {
        TraceView(model: previewModel {
            $0.resolved = TracePreviewData.target; $0.runTarget = "1.1.1.1"
            $0.hops = TracePreviewData.hops; $0.phase = .finished(.reachedDestination(hops: 5))
        })
    }
}

#Preview("Finished: not reached") {
    NavigationStack {
        TraceView(model: previewModel {
            $0.resolved = TracePreviewData.target; $0.runTarget = "1.1.1.1"
            $0.hops = Array(TracePreviewData.hops.prefix(4)); $0.phase = .finished(.maxHopsExceeded)
        })
    }
}

#Preview("Finished: unreachable") {
    NavigationStack {
        TraceView(model: previewModel {
            var hops = Array(TracePreviewData.hops.prefix(2))
            let ip = IPAddress("96.120.24.29")!
            hops.append(TraceHop(ttl: 3, probes: [.unreachable(from: ip, rtt: 0.01, code: 1)], addresses: [ip]))
            $0.resolved = TracePreviewData.target; $0.runTarget = "1.1.1.1"
            $0.hops = hops; $0.phase = .finished(.unreachable(atHop: 3, code: 1))
        })
    }
}

#Preview("Stopped") {
    NavigationStack {
        TraceView(model: previewModel {
            $0.resolved = TracePreviewData.target; $0.runTarget = "1.1.1.1"
            $0.hops = Array(TracePreviewData.hops.prefix(3)); $0.phase = .stopped(nil)
        })
    }
}

#Preview("Error") {
    NavigationStack {
        TraceView(model: previewModel {
            $0.runTarget = "apple.cmo"
            $0.error = ToolError(.resolutionFailed(host: "apple.cmo", reason: "")); $0.phase = .failed("Couldn't Resolve apple.cmo")
        })
    }
}

#Preview("Offline") {
    NavigationStack { TraceView(model: previewModel { $0.targetText = "1.1.1.1" }) }.environment(\.isOnline, false)
}
#endif
