// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPFeature
import Foundation
import NetCore
import PingFeature
import RIPEstat
import SharedUI
import TraceFeature

@MainActor public final class AppEnvironment {
    public let router: AppRouter, recents: RecentsStore, settings: SettingsStore, network: NetworkMonitor
    public let ping: PingModel, trace: TraceModel, bgp: BGPMapModel

    private init(router: AppRouter, recents: RecentsStore, settings: SettingsStore, network: NetworkMonitor,
                 pingService: any PingService, traceService: any TraceService, api: any RIPEstatAPI) {
        self.router = router
        self.recents = recents
        self.settings = settings
        self.network = network
        self.ping = PingModel(service: pingService, settings: settings, recents: recents)
        self.trace = TraceModel(service: traceService, asnLookup: ASNLookup(api: api), settings: settings,
                                recents: recents, router: router)
        self.bgp = BGPMapModel(api: api, recents: recents, router: router)
    }

    /// Pinger, Tracer, RIPEstatClient.
    public static func live() -> AppEnvironment {
        AppEnvironment(router: AppRouter(), recents: RecentsStore(), settings: SettingsStore(), network: NetworkMonitor(),
                       pingService: Pinger(), traceService: Tracer(), api: RIPEstatClient())
    }

    /// Mock services and an isolated UserDefaults suite (for previews).
    public static func preview() -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "com.ahmadrezaei.iptools.preview") ?? .standard
        let cloudflare = IPAddress("1.1.1.1")!
        let hop1 = IPAddress("192.168.1.1")!, hop2 = IPAddress("10.20.0.1")!, hop3 = IPAddress("141.101.65.1")!
        let ping = MockPingService(script: [
            .reply(rtt: 0.0123, bytes: 64, ttl: 58, from: cloudflare),
            .reply(rtt: 0.0141, bytes: 64, ttl: 58, from: cloudflare),
            .timeout,
            .reply(rtt: 0.0362, bytes: 64, ttl: 58, from: cloudflare),
        ])
        let trace = MockTraceService(hops: [
            [.timeExceeded(from: hop1, rtt: 0.002), .timeExceeded(from: hop1, rtt: 0.002), .timeExceeded(from: hop1, rtt: 0.003)],
            [.timeExceeded(from: hop2, rtt: 0.009), .timeout, .timeExceeded(from: hop2, rtt: 0.010)],
            [.timeExceeded(from: hop3, rtt: 0.021), .timeExceeded(from: hop3, rtt: 0.020), .timeExceeded(from: hop3, rtt: 0.022)],
            [.echoReply(from: cloudflare, rtt: 0.024), .echoReply(from: cloudflare, rtt: 0.023), .echoReply(from: cloudflare, rtt: 0.025)],
        ])
        return AppEnvironment(router: AppRouter(), recents: RecentsStore(defaults: defaults),
                              settings: SettingsStore(defaults: defaults), network: NetworkMonitor(),
                              pingService: ping, traceService: trace, api: MockRIPEstat(fixtureBundle: .main))
    }
}
