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
        self.ping = PingModel(service: pingService, settings: settings, recents: recents, router: router)
        self.trace = TraceModel(service: traceService, asnLookup: ASNLookup(api: api), settings: settings,
                                recents: recents, router: router)
        self.bgp = BGPMapModel(api: api, recents: recents, router: router, traceService: traceService,
                               settings: settings, network: network)
    }

    /// Pinger, Tracer, RIPEstatClient.
    public static func live() -> AppEnvironment {
        #if DEBUG
        if let mode = ScreenshotMode.current {
            let defaults = ScreenshotMode.isolatedDefaults()
            let env = AppEnvironment(router: AppRouter(), recents: RecentsStore(defaults: defaults),
                                     settings: SettingsStore(defaults: defaults), network: NetworkMonitor(),
                                     pingService: Pinger(), traceService: Tracer(), api: RIPEstatClient())
            mode.apply(to: env)
            return env
        }
        #endif
        return AppEnvironment(router: AppRouter(), recents: RecentsStore(), settings: SettingsStore(), network: NetworkMonitor(),
                              pingService: Pinger(), traceService: Tracer(), api: RIPEstatClient())
    }

    /// The 8.8.8.8 trace of DESIGN §6.11.6 (hop 10 silent). Other targets get the same script.
    static func googleTraceScript() -> [[ProbeResult]] {
        func hop(_ address: String, _ rtt: Double) -> [ProbeResult] {
            let ip = IPAddress(address)!
            return [.timeExceeded(from: ip, rtt: rtt), .timeExceeded(from: ip, rtt: rtt * 1.05), .timeExceeded(from: ip, rtt: rtt * 0.97)]
        }
        let google = IPAddress("8.8.8.8")!
        return [
            hop("192.168.70.1", 0.002), hop("172.16.21.1", 0.004), hop("10.99.7.1", 0.006),
            hop("104.28.0.0", 0.008), hop("172.71.133.1", 0.010), hop("141.101.67.186", 0.012), hop("141.101.67.57", 0.013),
            hop("108.170.255.223", 0.015), hop("72.14.237.93", 0.016),
            [.timeout, .timeout, .timeout],
            [.echoReply(from: google, rtt: 0.018), .echoReply(from: google, rtt: 0.017), .echoReply(from: google, rtt: 0.019)],
        ]
    }

    /// Mock services and an isolated UserDefaults suite (for previews).
    public static func preview() -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "com.ahmadrezaei.iptools.preview") ?? .standard
        let cloudflare = IPAddress("1.1.1.1")!
        let ping = MockPingService(script: [
            .reply(rtt: 0.0123, bytes: 64, ttl: 58, from: cloudflare),
            .reply(rtt: 0.0141, bytes: 64, ttl: 58, from: cloudflare),
            .timeout,
            .reply(rtt: 0.0362, bytes: 64, ttl: 58, from: cloudflare),
        ])
        let trace = MockTraceService(hops: Self.googleTraceScript())
        return AppEnvironment(router: AppRouter(), recents: RecentsStore(defaults: defaults),
                              settings: SettingsStore(defaults: defaults), network: NetworkMonitor(),
                              pingService: ping, traceService: trace, api: MockRIPEstat(fixtureBundle: .main))
    }
}
