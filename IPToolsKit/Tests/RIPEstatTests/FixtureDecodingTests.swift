// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

@Suite struct FixtureDecodingTests {
    @Test func fixturesAreBundled() {
        #expect(Bundle.module.url(forResource: "Fixtures", withExtension: nil) != nil)
    }

    @Test func networkInfoPublicIPv4() throws {
        let info = try RIPEstatParsing.networkInfo(Fixture.data("network-info_1.1.1.1"))
        #expect(info.prefix == "1.1.1.0/24")
        #expect(info.originASNs == [13335])   // the JSON has ["13335"]: strings normalise to UInt32
    }

    @Test func networkInfoIPv6() throws {
        let info = try RIPEstatParsing.networkInfo(Fixture.data("network-info_2606-4700-4700--1111"))
        #expect(info.prefix == "2606:4700:4700::/48")
        #expect(info.originASNs == [13335])
    }

    @Test func networkInfoUnroutedHasNilPrefix() throws {
        let info = try RIPEstatParsing.networkInfo(Fixture.data("network-info_10.0.0.1"))
        #expect(info.prefix == nil)
        #expect(info.originASNs.isEmpty)
    }

    @Test func prefixOverview() throws {
        let o = try RIPEstatParsing.prefixOverview(Fixture.data("prefix-overview_1.1.1.0-24"), resource: "x")
        #expect(o.announced)
        #expect(o.resource == "1.1.1.0/24")
        #expect(o.origins == [ASHolder(asn: 13335, holder: "CLOUDFLARENET - Cloudflare, Inc.")])
        #expect(o.origins[0].shortName == "Cloudflare")
    }

    @Test func prefixOverviewPrivate() throws {
        let o = try RIPEstatParsing.prefixOverview(Fixture.data("prefix-overview_10.0.0.0-8"), resource: "10.0.0.0/8")
        #expect(o.origins.isEmpty || !o.announced)
    }

    @Test func asOverview() throws {
        let o = try RIPEstatParsing.asOverview(Fixture.data("as-overview_AS13335"), asn: 13335)
        #expect(o.asn == 13335)
        #expect(o.holder == "CLOUDFLARENET - Cloudflare, Inc.")
        #expect(o.announced)
    }

    @Test func asNames() throws {
        let names = try RIPEstatParsing.asNames(Fixture.data("as-names_13335-6939-174"))
        #expect(names.count == 3)
        #expect(names[6939] == "HURRICANE - Hurricane Electric LLC")
        let big = try RIPEstatParsing.asNames(Fixture.data("as-names_bgp-state_1.1.1.0-24"))
        #expect(big.count >= 290)
        #expect(big[13335] != nil)
    }

    @Test func announcedPrefixesSortedIPv4First() throws {
        let prefixes = try RIPEstatParsing.announcedPrefixes(Fixture.data("announced-prefixes_AS13335"))
        #expect(prefixes.count == 5748)
        #expect(Set(prefixes).count == prefixes.count)
        let firstV6 = try #require(prefixes.firstIndex { $0.contains(":") })
        #expect(prefixes[..<firstV6].allSatisfy { !$0.contains(":") })
        #expect(prefixes[firstV6...].allSatisfy { $0.contains(":") })
        func length(_ p: String) -> Int { Int(p.split(separator: "/").last!)! }
        let v4 = prefixes[..<firstV6].map(length)
        #expect(v4 == v4.sorted())
    }

    @Test func routingStatus() throws {
        let s = try RIPEstatParsing.routingStatus(Fixture.data("routing-status_1.1.1.0-24"))
        #expect(s.v4 == .init(seeing: 319, total: 319))
        #expect(s.v6 == nil)   // 0/0 peers means no data
        #expect(s.origins == [13335])
    }

    @Test func lookingGlassSynthetic() throws {
        let lg = try RIPEstatParsing.lookingGlass(Fixture.data("looking-glass_1.1.1.0-24"))
        #expect(lg.collectors.count == 23)
        #expect(lg.routes.count == 360)
        #expect(lg.collectors.first?.id == "RRC00")
        #expect(lg.collectors.first?.location == "Amsterdam, NL")
        let r = lg.routes[0]
        #expect(r.asPath == [33555, 13335])
        #expect(r.collector == "RRC00")
        #expect(r.lastUpdated != nil)
        #expect(lg.routes.allSatisfy { $0.asPath.last == 13335 })
    }

    @Test func lookingGlassPrivateIsEmpty() throws {
        let lg = try RIPEstatParsing.lookingGlass(Fixture.data("looking-glass_10.0.0.0-8"))
        #expect(lg.routes.isEmpty && lg.collectors.isEmpty)
        #expect(lg.latestTime == nil)
    }

    @Test func bgpStateReal() throws {
        let lg = try RIPEstatParsing.bgpState(Fixture.data("bgp-state_1.1.1.0-24"))
        #expect(lg.routes.count == 365)
        #expect(lg.collectors.count == 23)
        let first = lg.routes[0]
        #expect(first.collector == "RRC00")
        #expect(first.peerIP == "102.208.105.2")
        #expect(first.prefix == "1.1.1.0/24")
        #expect(first.asPath == [328840, 327727, 174, 13335])
        #expect(first.rawASPath == "328840 327727 174 13335")
        #expect(!first.hadASSet)
        #expect(lg.routes.allSatisfy { $0.asPath.last == 13335 && !$0.asPath.isEmpty })
        let stamp = try #require(lg.latestTime)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: stamp)
        #expect([c.year, c.month, c.day, c.hour, c.minute, c.second] == [2026, 11, 7, 13, 59, 53])
        #expect(first.lastUpdated == stamp)
        #expect(lg.collectors.first { $0.id == "RRC00" }?.location == "Amsterdam, NL")
    }

    @Test func bgpStateFewPathsAndEmptyAndIPv6() throws {
        let few = try RIPEstatParsing.bgpState(Fixture.data("bgp-state_80.249.208.0-21"))
        #expect(few.routes.count == 2)
        #expect(few.routes.map(\.collector) == ["RRC13", "RRC23"])
        #expect(few.routes[1].asPath == [133210, 56308, 7713])

        let empty = try RIPEstatParsing.bgpState(Fixture.data("bgp-state_10.0.0.0-8"))
        #expect(empty.routes.isEmpty)

        let v6 = try RIPEstatParsing.bgpState(Fixture.data("bgp-state_2606-4700-4700---48"))
        #expect(v6.routes.count > 100)
        #expect(v6.routes.allSatisfy { $0.prefix == "2606:4700:4700::/48" })
    }

    @Test func mockServesFixtures() async throws {
        let mock = MockRIPEstat(fixtureBundle: Bundle.module, latency: .zero)
        let info = try await mock.networkInfo("1.1.1.1")
        #expect(info.prefix == "1.1.1.0/24")
        let lg = try await mock.lookingGlass("1.1.1.1")           // IP → prefix via network-info fixture
        #expect(lg.routes.count == 365)                            // real bgp-state preferred over synthetic
        let priv = try await mock.lookingGlass("10.0.0.0/8")
        #expect(priv.routes.isEmpty)
        let few = try await mock.lookingGlass("80.249.208.0/21")
        #expect(few.routes.count == 2)
        let prefixes = try await mock.announcedPrefixes(13335)
        #expect(prefixes.count == 5748)
        let names = try await mock.asNames([13335, 174, 7713])
        #expect(names[13335] == "CLOUDFLARENET - Cloudflare, Inc.")
        #expect(names[7713] != nil)
        let overview = try await mock.asOverview(13335)
        #expect(overview.holder?.hasPrefix("CLOUDFLARENET") == true)
        let status = try await mock.routingStatus("1.1.1.0/24")
        #expect(status.v4?.total == 319)
    }

    @Test func mockWorksWithoutFixtures() async throws {
        let mock = MockRIPEstat(fixtureBundle: Bundle(for: StubProtocol.self), latency: .zero)
        let lg = try await mock.lookingGlass("1.1.1.0/24")
        #expect(lg.routes.count == 48)
        let priv = try await mock.lookingGlass("10.1.2.3")
        #expect(priv.routes.isEmpty)
    }
}
