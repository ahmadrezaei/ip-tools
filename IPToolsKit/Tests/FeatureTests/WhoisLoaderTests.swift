// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import Testing
@testable import WhoisFeature

@Suite struct WhoisLoaderTests {
    private func loader(_ api: WhoisFakeAPI, location: Bool = true) -> WhoisLoader {
        WhoisLoader(api: api, reverseName: { _ in "dns.example" }, includeLocation: location, seams: .stub)
    }

    private func failure(_ block: () async throws -> WhoisResult) async -> WhoisFailure? {
        do { _ = try await block() } catch let error as WhoisFailure { return error } catch {}
        return nil
    }

    // MARK: Plans

    @Test func addressPlanCallsEachEndpointOnce() async throws {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        api.geoByIP["8.8.8.8"] = GeoLocation(country: "US", city: nil, coveredFraction: 1)
        let result = try await loader(api).load(.address(ip("8.8.8.8"), hostname: nil))
        #expect(Set(api.calls) == ["whois:8.8.8.8", "network-info:8.8.8.8", "abuse:8.8.8.8", "country:8.8.8.8",
                                   "as-names:15169", "geo:8.8.8.8"])
        #expect(api.calls.count == 6)
        #expect(result.reverseName == "dns.example")
        #expect(result.asNames[15169] == "GOOGLE - Google LLC")
        #expect(result.location?.country == "US")
        #expect(result.retriedWith == nil)
    }

    @Test func locationIsSkippedWhenDisabled() async throws {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        let result = try await loader(api, location: false).load(.address(ip("8.8.8.8"), hostname: nil))
        #expect(api.calls("geo").isEmpty)
        #expect(result.location == nil)
    }

    @Test func prefixPlanKnownHoldersNeedNoNameCall() async throws {
        let api = WhoisFakeAPI()
        api.whoisByResource["1.1.1.0/24"] = objectResponse("1.1.1.0/24")
        api.overviewByPrefix["1.1.1.0/24"] = PrefixOverview(resource: "1.1.1.0/24", announced: true,
                                                            origins: [ASHolder(asn: 13335, holder: "CLOUDFLARENET - Cloudflare")])
        api.abuseByResource["1.1.1.0/24"] = AbuseContacts(emails: [], authoritativeRIR: nil)
        let result = try await loader(api).load(.prefix(ip("1.1.1.0"), length: 24))
        #expect(Set(api.calls) == ["whois:1.1.1.0/24", "prefix-overview:1.1.1.0/24", "abuse:1.1.1.0/24", "country:1.1.1.0/24"])
        #expect(result.asNames[13335] == "CLOUDFLARENET - Cloudflare")
    }

    @Test func prefixPlanFetchesNamesOnlyForOriginsWithoutHolder() async throws {
        let api = WhoisFakeAPI()
        api.whoisByResource["1.1.1.0/24"] = objectResponse("1.1.1.0/24", irr: [whoisRecord([("route", "1.1.1.0/24"), ("origin", "AS64000")])])
        api.overviewByPrefix["1.1.1.0/24"] = PrefixOverview(resource: "1.1.1.0/24", announced: true,
                                                            origins: [ASHolder(asn: 13335, holder: "")])
        api.holders = [13335: "X - Cloudflare", 64000: "Y - Other"]
        let result = try await loader(api).load(.prefix(ip("1.1.1.0"), length: 24))
        #expect(api.calls("as-names") == ["as-names:13335,64000"])
        #expect(result.asNames.count == 2)
    }

    @Test func asPlanSkipsNamesWhenOverviewHasHolder() async throws {
        let api = WhoisFakeAPI()
        api.whoisByResource["AS13335"] = whoisResponse("AS13335", records: [whoisRecord([("ASNumber", "13335"), ("ASName", "CLOUDFLARENET")])])
        api.asOverviewByNumber[13335] = ASOverview(asn: 13335, holder: "CLOUDFLARENET - Cloudflare", announced: true)
        let result = try await loader(api).load(.asn(13335))
        #expect(Set(api.calls) == ["whois:AS13335", "as-overview:AS13335", "abuse:AS13335", "country:AS13335"])
        #expect(result.asNames[13335] == "CLOUDFLARENET - Cloudflare")
        if case .autonomousSystem(13335) = result.summary.subject {} else { Issue.record("wrong subject kind") }
    }

    @Test func asPlanAsksForNameWhenOverviewHasNone() async throws {
        let api = WhoisFakeAPI()
        api.whoisByResource["AS22548"] = whoisResponse("AS22548", records: [whoisRecord([("ASNumber", "22548")])])
        api.asOverviewByNumber[22548] = ASOverview(asn: 22548, holder: nil, announced: true)
        api.holders[22548] = "NICBR-AS - NIC.BR"
        _ = try await loader(api).load(.asn(22548))
        #expect(api.calls("as-names") == ["as-names:22548"])
    }

    // MARK: ARIN IPv6 retry

    @Test func noMatchRetriesWithTheRoutedPrefixOnce() async throws {
        let api = WhoisFakeAPI()
        let address = "2001:4860:4860::8888"
        api.whoisByResource[address] = noMatchResponse(address)
        api.whoisByResource["2001:4860::/32"] = objectResponse("2001:4860::/32")
        api.networkByIP[address] = NetworkInfo(prefix: "2001:4860::/32", originASNs: [15169])
        api.holders[15169] = "GOOGLE - Google LLC"
        let result = try await loader(api).load(.address(ip(address), hostname: nil))
        #expect(api.calls("whois") == ["whois:\(address)", "whois:2001:4860::/32"])
        #expect(result.retriedWith == "2001:4860::/32")
        #expect(result.raw?.resource == "2001:4860::/32")
    }

    @Test func noRetryWithoutAPrefixOrWhenTheMatchIsFine() async throws {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        _ = try await loader(api).load(.address(ip("8.8.8.8"), hostname: nil))
        #expect(api.calls("whois") == ["whois:8.8.8.8"])

        let noPrefix = WhoisFakeAPI()
        noPrefix.whoisByResource["8.8.4.4"] = noMatchResponse("8.8.4.4")
        noPrefix.networkByIP["8.8.4.4"] = NetworkInfo(prefix: nil, originASNs: [])
        noPrefix.countryByResource["8.8.4.4"] = "US"
        _ = try await loader(noPrefix).load(.address(ip("8.8.4.4"), hostname: nil))
        #expect(noPrefix.calls("whois") == ["whois:8.8.4.4"])
    }

    @Test func failedRetryKeepsTheFirstResponse() async throws {
        let api = WhoisFakeAPI()
        let address = "2001:4860:4860::8888"
        api.whoisByResource[address] = noMatchResponse(address)
        api.networkByIP[address] = NetworkInfo(prefix: "2001:4860::/32", originASNs: [15169])
        api.holders[15169] = "GOOGLE - Google LLC"
        // No stored response for the prefix, so the retry fails.
        let result = try await loader(api).load(.address(ip(address), hostname: nil))
        #expect(result.retriedWith == nil)
        #expect(result.raw?.resource == address)
        #expect(result.summary.notes.contains(.missing(.registry)))
    }

    // MARK: Failure policy

    @Test func whoisFailingAloneStillGivesACard() async throws {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        api.failing = ["whois"]
        let result = try await loader(api).load(.address(ip("8.8.8.8"), hostname: nil))
        #expect(result.summary.notes.contains(.missing(.registry)))
        #expect(result.summary.routedPrefix == "8.8.8.0/24")
        #expect(result.raw == nil)
    }

    @Test func whoisAndRoutingFailingFailsTheLookup() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        api.failing = ["whois", "network-info"]
        let failed = await failure { try await loader(api).load(.address(ip("8.8.8.8"), hostname: nil)) }
        #expect(failed?.kind == .busy)
    }

    @Test func otherHelperFailuresOnlyRemoveTheirRows() async throws {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        api.failing = ["abuse", "country", "as-names", "geo"]
        let result = try await loader(api).load(.address(ip("8.8.8.8"), hostname: nil))
        #expect(result.summary.abuseEmails.isEmpty)
        #expect(result.summary.country == nil)
        #expect(result.summary.notes.contains(.missing(.abuse)))
        #expect(result.summary.notes.contains(.missing(.names)))
        #expect(result.location == nil)
    }

    @Test func emptySummaryIsNotFoundWhenEverythingAnswered() async {
        let api = WhoisFakeAPI()
        api.whoisByResource["8.8.8.8"] = whoisResponse("8.8.8.8", records: [])
        api.networkByIP["8.8.8.8"] = NetworkInfo(prefix: nil, originASNs: [])
        api.abuseByResource["8.8.8.8"] = AbuseContacts(emails: [], authoritativeRIR: nil)
        let failed = await failure { try await loader(api).load(.address(ip("8.8.8.8"), hostname: nil)) }
        #expect(failed?.kind == .notFound)
    }

    @Test func emptySummaryAfterAFailureIsNotReportedAsNotFound() async {
        let api = WhoisFakeAPI()
        api.networkByIP["8.8.8.8"] = NetworkInfo(prefix: nil, originASNs: [])
        api.abuseByResource["8.8.8.8"] = AbuseContacts(emails: [], authoritativeRIR: nil)
        api.failing = ["whois"]
        api.failureError = RIPEstatError.timeout
        let failed = await failure { try await loader(api).load(.address(ip("8.8.8.8"), hostname: nil)) }
        #expect(failed?.kind == .timeout)
    }

    @Test func cancellationGivesNoResult() async {
        let api = WhoisFakeAPI()
        sampleNetwork(api)
        api.delay = .seconds(5)
        let loader = loader(api)
        let task = Task { try await loader.load(.address(ip("8.8.8.8"), hostname: nil)) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func irrOriginsAcceptBothSpellings() {
        let response = whoisResponse("x", records: [], irr: [
            whoisRecord([("route", "1.0.0.0/8"), ("origin", "AS8966")]),
            whoisRecord([("route", "1.0.0.0/8"), ("origin", "3333")]),
            whoisRecord([("route", "1.0.0.0/8"), ("origin", "junk")]),
        ])
        #expect(WhoisLoader.irrOrigins(response) == [8966, 3333])
        #expect(WhoisLoader.irrOrigins(nil).isEmpty)
    }
}
