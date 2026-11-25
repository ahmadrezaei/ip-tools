// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI
import SwiftUI

/// Fixed sample data for previews: 8.8.8.8 at ARIN, and the RIPE NCC addresses as "your" IP.
enum WhoisPreviewData {
    enum Scenario {
        case myIP, checking, v4Only, v6Only, mismatch, oneFailed, bothFailed, offline
        case google, `operator`, lacnic, notAnnounced, autonomousSystem, partial
        case resolving, loading, privateAddress, mapped, notFound, busy, timeout, unresolved, backgrounded
    }

    static let myV4 = IPAddress("193.0.6.139")!
    static let myV6 = IPAddress("2001:67c:2e8:22::c100:696")!
    static let googleDNS = IPAddress("8.8.8.8")!

    static let localAddresses = [
        LocalAddress(interface: .wifi, name: "en0", address: IPAddress("192.168.1.23")!),
        LocalAddress(interface: .cellular, name: "pdp_ip0", address: IPAddress("10.172.4.18")!),
        LocalAddress(interface: .vpn, name: "utun4", address: IPAddress("10.8.0.2")!),
    ]

    private static let fetched = Date(timeIntervalSince1970: 1_795_700_000)

    private static func date(_ iso: String) -> Date? { ISO8601DateFormatter().date(from: iso + "T00:00:00Z") }

    private static func record(_ id: Int, _ pairs: [(String, String)]) -> WhoisRecord {
        WhoisRecord(id: id, fields: pairs.map { WhoisField(key: $0.0, value: $0.1, link: nil) })
    }

    // MARK: Results

    static let googleSummary = WhoisSummary(
        subject: .network, query: "8.8.8.8", cidrs: ["8.8.8.0/24"], range: "8.8.8.0 - 8.8.8.255", name: "GOGL",
        handle: "NET-8-8-8-0-2", organization: "Google LLC", organizationProvenance: .registry, orgHandle: "GOGL",
        country: "US", countryProvenance: .registry, rir: .arin, status: "Direct Allocation", routedPrefix: "8.8.8.0/24",
        originASNs: [15169], registeredOrigins: [15169], announced: true, abuseEmails: ["network-abuse@google.com"],
        registered: date("2023-12-28"), summaryRecordID: 0)

    static let googleRaw = WhoisResponse(
        resource: "8.8.8.8", authorities: ["arin"],
        records: [
            record(0, [("NetRange", "8.8.8.0 - 8.8.8.255"), ("CIDR", "8.8.8.0/24"), ("NetName", "GOGL"),
                       ("NetHandle", "NET-8-8-8-0-2"), ("NetType", "Direct Allocation"), ("OriginAS", ""),
                       ("Organization", "Google LLC (GOGL)"), ("RegDate", "2023-12-28")]),
            record(1, [("OrgName", "Google LLC"), ("OrgId", "GOGL"), ("Country", "US"),
                       ("Comment", "Please note that the recommended way to file abuse complaints are located in the following links."),
                       ("Comment", ""), ("Comment", "To report abuse and illegal activity: https://www.google.com/contact/")]),
        ],
        irrRecords: [record(2, [("route", "8.8.8.0/24"), ("origin", "AS15169"), ("source", "RADB")])],
        warnings: [], queryTime: fetched)

    static func result(_ subject: WhoisSubject, _ summary: WhoisSummary, raw: WhoisResponse? = nil, reverse: String? = nil,
                       location: GeoLocation? = nil, names: [UInt32: String] = [:]) -> WhoisResult {
        WhoisResult(subject: subject, summary: summary, raw: raw, retriedWith: nil, reverseName: reverse, location: location,
                    fetchedAt: fetched, asNames: names)
    }

    static let google = result(.address(googleDNS, hostname: nil), googleSummary, raw: googleRaw, reverse: "dns.google",
                               names: [15169: "GOOGLE - Google LLC"])

    static let mine = result(
        .address(myV4, hostname: nil),
        WhoisSummary(
            subject: .network, query: myV4.description, cidrs: ["193.0.0.0/21"], range: "193.0.0.0 - 193.0.7.255",
            name: "RIPE-NCC", descriptions: ["RIPE Network Coordination Centre", "Amsterdam, Netherlands"],
            organization: "RIPE Network Coordination Centre", organizationProvenance: .description, orgHandle: "ORG-RIEN1-RIPE",
            country: "NL", countryProvenance: .registry, rir: .ripe, status: "ASSIGNED PA", routedPrefix: "193.0.0.0/21",
            originASNs: [3333], registeredOrigins: [3333], announced: true, abuseEmails: ["abuse@ripe.net"],
            registered: date("2003-03-17"), lastModified: date("2026-03-19"), summaryRecordID: 0),
        raw: WhoisResponse(
            resource: myV4.description, authorities: ["ripe"],
            records: [record(0, [("inetnum", "193.0.0.0 - 193.0.7.255"), ("netname", "RIPE-NCC"),
                                 ("descr", "RIPE Network Coordination Centre"), ("country", "NL"), ("org", "ORG-RIEN1-RIPE"),
                                 ("status", "ASSIGNED PA"), ("source", "RIPE")])],
            irrRecords: [record(1, [("route", "193.0.0.0/21"), ("origin", "AS3333"), ("source", "RIPE")])],
            warnings: [], queryTime: fetched),
        reverse: "www.ripe.net", location: GeoLocation(country: "NL", city: "Amsterdam", coveredFraction: 1),
        names: [3333: "RIPE-NCC-AS Reseaux IP Europeens Network Coordination Centre (RIPE NCC)"])

    static let operatorResult = result(
        .address(IPAddress("95.216.0.10")!, hostname: nil),
        WhoisSummary(
            subject: .network, query: "95.216.0.10", cidrs: ["95.216.0.0/16"], range: "95.216.0.0 - 95.216.255.255",
            name: "EXAMPLE-NET", organization: "Hetzner Online GmbH", organizationProvenance: .asHolder(24940), country: "DE",
            countryProvenance: .registry, rir: .ripe, status: "ASSIGNED PA", routedPrefix: "95.216.0.0/16",
            originASNs: [24940], registeredOrigins: [24940], announced: true, abuseEmails: ["abuse@hetzner.com"],
            registered: date("2012-05-02")),
        names: [24940: "HETZNER-AS Hetzner Online GmbH"])

    static let lacnicResult = result(
        .address(IPAddress("200.160.2.3")!, hostname: nil),
        WhoisSummary(
            subject: .network, query: "200.160.2.3", cidrs: ["200.160.0.0/20"], organization: "Nucleo de Inf. e Coord. do Ponto BR",
            organizationProvenance: .asHolder(22548), country: "BR", countryProvenance: .rirStatistics, rir: .lacnic,
            routedPrefix: "200.160.0.0/20", originASNs: [22548], registeredOrigins: [22548], announced: true,
            notes: [.registryRecordsUnavailable(.lacnic)]),
        names: [22548: "NICBR-AS - Nucleo de Inf. e Coord. do Ponto BR - NIC.BR"])

    static let notAnnouncedResult = result(
        .prefix(IPAddress("203.0.113.0")!, length: 24),
        WhoisSummary(
            subject: .network, query: "203.0.113.0/24", cidrs: ["203.0.113.0/24"], range: "203.0.113.0 - 203.0.113.255",
            name: "EXAMPLE-NET", organization: "Example Networks Ltd", organizationProvenance: .registry, country: "AU",
            countryProvenance: .registry, rir: .apnic, status: "ALLOCATED PORTABLE", announced: false,
            abuseEmails: [], notes: [.notAnnounced]))

    static let asResult = result(
        .asn(13335),
        WhoisSummary(
            subject: .autonomousSystem(13335), query: "AS13335", name: "CLOUDFLARENET", organization: "Cloudflare, Inc.",
            organizationProvenance: .registry, country: "US", countryProvenance: .registry, rir: .arin, announced: true,
            abuseEmails: ["abuse@cloudflare.com"], registered: date("2010-07-14")))

    static let partialResult = result(
        .address(googleDNS, hostname: nil),
        WhoisSummary(
            subject: .network, query: "8.8.8.8", cidrs: ["8.8.8.0/24"], country: "US", countryProvenance: .rirStatistics,
            routedPrefix: "8.8.8.0/24", originASNs: [15169], announced: true, abuseEmails: ["network-abuse@google.com"],
            notes: [.missing(.registry)]),
        names: [15169: "GOOGLE - Google LLC"])

    // MARK: Own addresses

    static func snapshot(v4: MyIPSnapshot.Slot, v6: MyIPSnapshot.Slot) -> MyIPSnapshot {
        MyIPSnapshot(v4: v4, v6: v6, viaVPN: false, generation: 1, fetchedAt: fetched)
    }

    static let found4 = MyIPSnapshot.Slot.found(myV4, reverseName: "www.ripe.net")
    static let found6 = MyIPSnapshot.Slot.found(myV6, reverseName: nil)

    // MARK: Models and views

    @MainActor static func model(_ scenario: Scenario) -> WhoisModel {
        let defaults = UserDefaults(suiteName: "preview.whois") ?? .standard
        let model = WhoisModel(api: MockRIPEstat(fixtureBundle: .main, latency: .zero),
                               recents: RecentsStore(defaults: defaults), router: AppRouter(selectedTool: .whois),
                               settings: SettingsStore(defaults: defaults), localAddresses: { localAddresses })
        configure(model, scenario)
        return model
    }

    @MainActor private static func configure(_ model: WhoisModel, _ scenario: Scenario) {
        let both = snapshot(v4: found4, v6: found6)
        let loadedMine: [IPVersion: WhoisLoad] = [.v4: .loaded(mine)]
        switch scenario {
        case .myIP: model.applyPreview(myIP: both, myWhois: loadedMine, localAddresses: localAddresses)
        case .checking: model.applyPreview(myIP: snapshot(v4: .checking, v6: .checking), localAddresses: localAddresses)
        case .v4Only:
            model.applyPreview(myIP: snapshot(v4: found4, v6: .unavailable(.noRoute)), myWhois: loadedMine,
                               localAddresses: localAddresses)
        case .v6Only:
            model.myFamily = .v6
            model.applyPreview(myIP: snapshot(v4: .unavailable(.ipv6OnlyNetwork), v6: found6), myWhois: [.v6: .loaded(mine)],
                               localAddresses: localAddresses)
        case .mismatch:
            model.applyPreview(myIP: snapshot(v4: found4, v6: .unavailable(.mismatch)), myWhois: loadedMine,
                               localAddresses: localAddresses)
        case .oneFailed:
            model.applyPreview(myIP: snapshot(v4: found4, v6: .failed("RIPEstat didn't answer.")), myWhois: loadedMine,
                               localAddresses: localAddresses)
        case .bothFailed:
            let message = String(localized: "RIPEstat didn't answer. Check your connection and try again.")
            model.applyPreview(myIP: snapshot(v4: .failed(message), v6: .failed(message)), localAddresses: localAddresses)
        case .offline:
            model.applyPreview(myIP: snapshot(v4: .unavailable(.offline), v6: .unavailable(.offline)), localAddresses: localAddresses)
        case .google: model.applyPreview(phase: .loaded(google), myIP: both, localAddresses: localAddresses)
        case .operator: model.applyPreview(phase: .loaded(operatorResult), myIP: both)
        case .lacnic: model.applyPreview(phase: .loaded(lacnicResult), myIP: both)
        case .notAnnounced: model.applyPreview(phase: .loaded(notAnnouncedResult), myIP: both)
        case .autonomousSystem: model.applyPreview(phase: .loaded(asResult), myIP: both)
        case .partial: model.applyPreview(phase: .loaded(partialResult), myIP: both)
        case .resolving: model.applyPreview(phase: .resolving("apple.com"), myIP: both)
        case .loading: model.applyPreview(phase: .loading(.address(googleDNS, hostname: nil)), myIP: both)
        case .privateAddress:
            let range = SpecialPurposeRange(network: IPAddress("192.168.0.0")!, length: 16, kind: .privateUse,
                                            name: "Private use", rfc: "RFC 1918")
            model.applyPreview(phase: .local(LocalVerdict(input: "192.168.1.1", reason: .address(range), embeddedIPv4: nil)),
                               myIP: both)
        case .mapped:
            let range = SpecialPurposeRange(network: IPAddress("::ffff:0:0")!, length: 96, kind: .ipv4Mapped,
                                            name: "IPv4-mapped", rfc: "RFC 4291")
            model.applyPreview(phase: .local(LocalVerdict(input: "::ffff:8.8.8.8", reason: .address(range),
                                                          embeddedIPv4: googleDNS)), myIP: both)
        case .notFound: model.applyPreview(phase: .failed(.notFound("2001:db9::1")), myIP: both)
        case .busy: model.applyPreview(phase: .failed(.busyFailure), myIP: both)
        case .timeout: model.applyPreview(phase: .failed(.timeoutFailure), myIP: both)
        case .unresolved:
            model.applyPreview(phase: .failed(WhoisFailure(kind: .unresolved, message: "Couldn't find apple.cmo. Check the name and try again.")),
                               myIP: both)
        case .backgrounded: model.applyPreview(phase: .failed(.backgrounded), myIP: both)
        }
    }

    @MainActor static func view(_ scenario: Scenario) -> some View {
        NavigationStack { WhoisView(model: model(scenario)) }
    }
}
