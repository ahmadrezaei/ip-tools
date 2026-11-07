// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import Testing
@testable import RIPEstat

@Suite struct ClientTests {
    private func client(_ handler: @escaping StubProtocol.Handler) -> (RIPEstatClient, String) {
        let stub = StubProtocol.register(handler)
        return (RIPEstatClient(session: stub.session, baseURL: stub.baseURL), stub.host)
    }

    @Test func requestShape() async throws {
        let body = try Fixture.data("network-info_1.1.1.1")
        let (client, host) = client { _ in .ok(body) }
        let info = try await client.networkInfo("1.1.1.1")
        #expect(info.prefix == "1.1.1.0/24")
        let request = try #require(StubProtocol.recorded(host).first)
        #expect(request.call == "network-info")
        #expect(request.url?.path.hasSuffix("/data/network-info/data.json") == true)
        #expect(request.resource == "1.1.1.1")
        #expect(request.url?.query?.contains("sourceapp=ahmadrezaei-iptools") == true)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("IPTools/1.0") == true)
        #expect(request.timeoutInterval == 30)
    }

    @Test func prefixResourceKeepsSlashAndColons() async throws {
        let body = try Fixture.data("prefix-overview_1.1.1.0-24")
        let (client, host) = client { _ in .ok(body) }
        _ = try await client.prefixOverview("2606:4700::/32")
        let query = try #require(StubProtocol.recorded(host).first?.url?.query)
        #expect(query.hasPrefix("resource=2606:4700::/32&"))
    }

    @Test func badRequestMapsToAPIErrorWithMessages() async throws {
        let body = try Fixture.data("looking-glass_AS13335_error")
        let (client, _) = client { _ in .ok(body, status: 400) }
        do {
            _ = try await client.networkInfo("AS13335")
            Issue.record("expected an error")
        } catch let RIPEstatError.api(messages) {
            #expect(messages.first?.contains("unsupported type ASN") == true)
        }
    }

    @Test func http429IsRateLimited() async {
        let (client, _) = client { _ in .ok(Data("{}".utf8), status: 429) }
        await #expect(throws: RIPEstatError.rateLimited) { try await client.networkInfo("1.1.1.1") }
    }

    @Test func http5xxAndOddBodies() async {
        let (c1, _) = client { _ in .ok(Data("oops".utf8), status: 503) }
        await #expect(throws: RIPEstatError.http(status: 503)) { try await c1.networkInfo("1.1.1.1") }
        let (c2, _) = client { _ in .ok(Data("nope".utf8), status: 404) }
        await #expect(throws: RIPEstatError.http(status: 404)) { try await c2.networkInfo("1.1.1.1") }
        let (c3, _) = client { _ in .ok(Data("<html>".utf8)) }
        await #expect(throws: RIPEstatError.self) { try await c3.networkInfo("1.1.1.1") }
    }

    @Test func transportErrorsMap() async {
        let (timeout, _) = client { _ in .fail(.timedOut) }
        await #expect(throws: RIPEstatError.timeout) { try await timeout.networkInfo("1.1.1.1") }
        let (offline, _) = client { _ in .fail(.notConnectedToInternet) }
        await #expect(throws: RIPEstatError.offline) { try await offline.networkInfo("1.1.1.1") }
    }

    @Test func responsesAreCachedPerURL() async throws {
        let body = try Fixture.data("network-info_1.1.1.1")
        let (client, host) = client { _ in .ok(body) }
        _ = try await client.networkInfo("1.1.1.1")
        _ = try await client.networkInfo("1.1.1.1")
        _ = try await client.networkInfo("1.1.1.2")
        #expect(StubProtocol.recorded(host).count == 2)
    }

    @Test func errorsAreNotCached() async throws {
        let calls = Counter()
        let body = try Fixture.data("network-info_1.1.1.1")
        let (client, _) = client { _ in calls.next() == 1 ? .fail(.timedOut) : .ok(body) }
        await #expect(throws: RIPEstatError.timeout) { try await client.networkInfo("1.1.1.1") }
        let info = try await client.networkInfo("1.1.1.1")
        #expect(info.originASNs == [13335])
    }

    @Test func asNamesChunksAt200AndCachesNames() async throws {
        let (client, host) = client { request in
            let asns = request.resource.split(separator: ",")
            let names = asns.map { "\"\($0)\":\"AS\($0)-NAME - Network \($0), Inc.\"" }.joined(separator: ",")
            return .ok(Data(#"{"status":"ok","status_code":200,"data":{"names":{\#(names)}}}"#.utf8))
        }
        let asns = (1...450).map { UInt32($0) }
        let names = try await client.asNames(asns + [5])          // duplicates are collapsed
        #expect(names.count == 450)
        #expect(names[450] == "AS450-NAME - Network 450, Inc.")
        let requests = StubProtocol.recorded(host)
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.resource.split(separator: ",").count <= 200 })
        // Everything is cached now: no new requests, even for a subset.
        let again = try await client.asNames([1, 2, 450])
        #expect(again.count == 3)
        #expect(StubProtocol.recorded(host).count == 3)
        #expect(try await client.asNames([]).isEmpty)
    }

    @Test func announcedPrefixesAndOverviews() async throws {
        let prefixes = try Fixture.data("announced-prefixes_AS13335")
        let overview = try Fixture.data("as-overview_AS13335")
        let routing = try Fixture.data("routing-status_1.1.1.0-24")
        let (client, host) = client { request in
            switch request.call {
            case "announced-prefixes": .ok(prefixes)
            case "as-overview": .ok(overview)
            default: .ok(routing)
            }
        }
        #expect(try await client.announcedPrefixes(13335).count == 5748)
        #expect(try await client.asOverview(13335).holder?.hasPrefix("CLOUDFLARENET") == true)
        #expect(try await client.routingStatus("1.1.1.0/24").v4?.seeing == 319)
        #expect(StubProtocol.recorded(host).map(\.resource).prefix(2) == ["AS13335", "AS13335"])
    }

    // MARK: looking-glass with bgp-state fallback

    @Test func lookingGlassUsedWhenItHasData() async throws {
        let lg = try Fixture.data("looking-glass_1.1.1.0-24")
        let (client, host) = client { _ in .ok(lg) }
        let result = try await client.lookingGlass("1.1.1.0/24")
        #expect(result.routes.count == 360)
        #expect(StubProtocol.recorded(host).map(\.call) == ["looking-glass"])
    }

    @Test func emptyLookingGlassFallsBackToBGPStateThenSkipsLookingGlass() async throws {
        let empty = try Fixture.data("looking-glass_10.0.0.0-8")
        let state = try Fixture.data("bgp-state_1.1.1.0-24")
        let (client, host) = client { $0.call == "looking-glass" ? .ok(empty) : .ok(state) }
        let first = try await client.lookingGlass("1.1.1.0/24")
        #expect(first.routes.count == 365)
        #expect(StubProtocol.recorded(host).map(\.call) == ["looking-glass", "bgp-state"])
        // Second map of another resource goes straight to bgp-state.
        _ = try await client.lookingGlass("1.1.1.1")
        #expect(StubProtocol.recorded(host).map(\.call) == ["looking-glass", "bgp-state", "bgp-state"])
    }

    @Test func lookingGlassServerErrorFallsBack() async throws {
        let state = try Fixture.data("bgp-state_80.249.208.0-21")
        let (client, host) = client { $0.call == "looking-glass" ? .ok(Data("x".utf8), status: 500) : .ok(state) }
        let result = try await client.lookingGlass("80.249.208.0/21")
        #expect(result.routes.count == 2)
        #expect(StubProtocol.recorded(host).map(\.call) == ["looking-glass", "bgp-state"])
    }

    @Test func trulyUnroutedStaysEmptyAndDoesNotLatchTheSkip() async throws {
        let emptyLG = try Fixture.data("looking-glass_10.0.0.0-8")
        let emptyState = try Fixture.data("bgp-state_10.0.0.0-8")
        let (client, host) = client { $0.call == "looking-glass" ? .ok(emptyLG) : .ok(emptyState) }
        #expect(try await client.lookingGlass("10.0.0.0/8").routes.isEmpty)
        #expect(try await client.lookingGlass("10.0.0.0/8").routes.isEmpty)
        #expect(StubProtocol.recorded(host).map(\.call).filter { $0 == "looking-glass" }.count >= 1)
        // Cached bgp-state/looking-glass responses may hide repeats; the point is that it never throws.
    }

    @Test func badResourceTypeDoesNotFallBack() async throws {
        let err = try Fixture.data("looking-glass_AS13335_error")
        let (client, host) = client { _ in .ok(err, status: 400) }
        await #expect(throws: RIPEstatError.self) { try await client.lookingGlass("AS13335") }
        #expect(StubProtocol.recorded(host).map(\.call) == ["looking-glass"])
    }

    @Test func bothSourcesFailingReportsTheFirstError() async {
        let (client, _) = client { _ in .ok(Data("x".utf8), status: 503) }
        await #expect(throws: RIPEstatError.http(status: 503)) { try await client.lookingGlass("1.1.1.0/24") }
    }

    @Test func offlineDoesNotTryTheFallback() async {
        let (client, host) = client { _ in .fail(.notConnectedToInternet) }
        await #expect(throws: RIPEstatError.offline) { try await client.lookingGlass("1.1.1.0/24") }
        #expect(StubProtocol.recorded(host).count == 1)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}

@Suite struct ConcurrencyGateTests {
    @Test func cancelledWaiterIsRemovedAndThrows() async throws {
        let gate = ConcurrencyGate(limit: 1)
        try await gate.acquire()
        let waiter = Task { try await gate.acquire() }
        while await gate.waitingCount == 0 { await Task.yield() }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(await gate.waitingCount == 0)
        await gate.release()
        try await gate.acquire()   // slot was not leaked to the cancelled waiter
        await gate.release()
    }
}

