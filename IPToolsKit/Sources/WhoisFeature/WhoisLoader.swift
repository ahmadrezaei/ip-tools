// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat

public struct WhoisResult: Hashable, Sendable {
    public let subject: WhoisSubject
    public let summary: WhoisSummary
    public let raw: WhoisResponse?
    /// "2001:4860::/32" after the ARIN IPv6 retry.
    public let retriedWith: String?
    public let reverseName: String?
    public let location: GeoLocation?
    public let fetchedAt: Date
    /// Raw `as-names` holder strings of the origin ASes (BGP and routing registry), keyed by AS number.
    public let asNames: [UInt32: String]

    public init(subject: WhoisSubject, summary: WhoisSummary, raw: WhoisResponse?, retriedWith: String?,
                reverseName: String?, location: GeoLocation?, fetchedAt: Date, asNames: [UInt32: String] = [:]) {
        self.subject = subject
        self.summary = summary
        self.raw = raw
        self.retriedWith = retriedWith
        self.reverseName = reverseName
        self.location = location
        self.fetchedAt = fetchedAt
        self.asNames = asNames
    }
}

public enum WhoisLoad: Hashable, Sendable { case loading, loaded(WhoisResult), failed(WhoisFailure) }

/// The pure functions the loader leans on. Defaults are the real ones; tests swap them.
struct WhoisSeams: Sendable {
    var summarize: @Sendable (String, WhoisSummary.Subject, WhoisInputs) -> WhoisSummary
    var isNoMatch: @Sendable (WhoisResponse) -> Bool
    var isEmpty: @Sendable (WhoisSummary) -> Bool

    static let live = WhoisSeams(
        summarize: { WhoisSummarizer.summarize(query: $0, subject: $1, inputs: $2) },
        isNoMatch: { $0.isNoMatch },
        isEmpty: { $0.isEmpty })
}

/// Request plans of DESIGN §14.8.
struct WhoisLoader: Sendable {
    private let api: any RIPEstatAPI
    private let reverseName: @Sendable (IPAddress) async -> String?
    private let includeLocation: Bool
    private let seams: WhoisSeams

    init(api: any RIPEstatAPI, reverseName: @escaping @Sendable (IPAddress) async -> String?, includeLocation: Bool,
         seams: WhoisSeams = .live) {
        self.api = api
        self.reverseName = reverseName
        self.includeLocation = includeLocation
        self.seams = seams
    }

    /// Everything one plan collected before it is summarised.
    private struct Gathered {
        var inputs = WhoisInputs()
        var failed: Set<WhoisSummary.Part> = []
        var firstError: (any Error)?
        var retriedWith: String?
        var reverseName: String?
        var location: GeoLocation?
        var whoisFailed = false
        var bgpFailed = false

        mutating func record(_ error: any Error, part: WhoisSummary.Part) {
            failed.insert(part)
            if part == .registry { whoisFailed = true }
            if part == .routing { bgpFailed = true }
            if firstError == nil || part == .registry { firstError = error }
        }

        mutating func take<T>(_ result: Result<T, any Error>, part: WhoisSummary.Part, store: (inout WhoisInputs, T) -> Void) {
            switch result {
            case let .success(value): store(&inputs, value)
            case let .failure(error): record(error, part: part)
            }
        }

        func failIfBothFailed() throws {
            guard whoisFailed, bgpFailed, let firstError else { return }
            throw WhoisFailure.from(firstError)
        }
    }

    /// Throws `WhoisFailure` or `CancellationError`.
    func load(_ subject: WhoisSubject) async throws -> WhoisResult {
        switch subject {
        case let .address(ip, _): try await loadAddress(subject, ip)
        case let .prefix(ip, length): try await loadPrefix(subject, "\(ip)/\(length)")
        case let .asn(number): try await loadAS(subject, number)
        }
    }

    private func attempt<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, any Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }

    // MARK: Plans

    private func loadAddress(_ subject: WhoisSubject, _ ip: IPAddress) async throws -> WhoisResult {
        let resource = ip.description
        let api = api
        async let whois = attempt { try await api.whois(resource) }
        async let network = attempt { try await api.networkInfo(resource) }
        async let abuse = attempt { try await api.abuseContacts(resource) }
        async let country = attempt { try await api.registeredCountry(resource) }
        async let reverse = reverseName(ip)
        let (whoisResult, networkResult, abuseResult, countryResult, reverseResult) =
            await (whois, network, abuse, country, reverse)
        try Task.checkCancellation()

        var gathered = Gathered()
        gathered.reverseName = reverseResult
        gathered.take(networkResult, part: .routing) { $0.network = $1 }
        gathered.take(whoisResult, part: .registry) { $0.whois = $1 }
        gathered.take(abuseResult, part: .abuse) { $0.abuse = $1 }
        gathered.take(countryResult, part: .country) { $0.country = $1 }
        try gathered.failIfBothFailed()

        // ARIN refuses bare IPv6 addresses: ask again with the routed prefix.
        if let response = gathered.inputs.whois, seams.isNoMatch(response),
           let prefix = gathered.inputs.network?.prefix, prefix != resource {
            do {
                gathered.inputs.whois = try await api.whois(prefix)
                gathered.retriedWith = prefix
            } catch {
                try Task.checkCancellation()
                gathered.record(error, part: .registry)
            }
            try Task.checkCancellation()
        }

        var wanted = Set(gathered.inputs.network?.originASNs ?? [])
        wanted.formUnion(Self.irrOrigins(gathered.inputs.whois))
        // Names and location do not depend on each other: ask for both at once.
        let missing = wanted.sorted()
        async let namesFetch = fetchNamesResult(missing)
        async let locationFetch = fetchLocationResult(resource)
        let (namesResult, locationResult) = await (namesFetch, locationFetch)
        try Task.checkCancellation()
        let asNames = mergeNames(namesResult, known: [:], into: &gathered)
        if let locationResult {
            gathered.take(locationResult, part: .location) { _, _ in }
            if case let .success(value) = locationResult { gathered.location = value }
        }
        return try finish(subject, query: resource, gathered: gathered, asNames: asNames)
    }

    private func loadPrefix(_ subject: WhoisSubject, _ resource: String) async throws -> WhoisResult {
        let api = api
        async let whois = attempt { try await api.whois(resource) }
        async let overview = attempt { try await api.prefixOverview(resource) }
        async let abuse = attempt { try await api.abuseContacts(resource) }
        async let country = attempt { try await api.registeredCountry(resource) }
        let (whoisResult, overviewResult, abuseResult, countryResult) = await (whois, overview, abuse, country)
        try Task.checkCancellation()

        var gathered = Gathered()
        gathered.take(overviewResult, part: .routing) { $0.prefixOverview = $1 }
        gathered.take(whoisResult, part: .registry) { $0.whois = $1 }
        gathered.take(abuseResult, part: .abuse) { $0.abuse = $1 }
        gathered.take(countryResult, part: .country) { $0.country = $1 }
        try gathered.failIfBothFailed()

        var known: [UInt32: String] = [:]
        var wanted = Set<UInt32>()
        for origin in gathered.inputs.prefixOverview?.origins ?? [] {
            if origin.holder.isEmpty { wanted.insert(origin.asn) } else { known[origin.asn] = origin.holder }
        }
        wanted.formUnion(Self.irrOrigins(gathered.inputs.whois))
        let asNames = await fetchNames(wanted, known: known, into: &gathered)
        return try finish(subject, query: resource, gathered: gathered, asNames: asNames)
    }

    private func loadAS(_ subject: WhoisSubject, _ number: UInt32) async throws -> WhoisResult {
        let resource = "AS\(number)"
        let api = api
        async let whois = attempt { try await api.whois(resource) }
        async let overview = attempt { try await api.asOverview(number) }
        async let abuse = attempt { try await api.abuseContacts(resource) }
        async let country = attempt { try await api.registeredCountry(resource) }
        let (whoisResult, overviewResult, abuseResult, countryResult) = await (whois, overview, abuse, country)
        try Task.checkCancellation()

        var gathered = Gathered()
        gathered.take(overviewResult, part: .routing) { $0.asOverview = $1 }
        gathered.take(whoisResult, part: .registry) { $0.whois = $1 }
        gathered.take(abuseResult, part: .abuse) { $0.abuse = $1 }
        gathered.take(countryResult, part: .country) { $0.country = $1 }
        try gathered.failIfBothFailed()

        var known: [UInt32: String] = [:]
        var wanted = Set<UInt32>()
        if let holder = gathered.inputs.asOverview?.holder, !holder.isEmpty {
            known[number] = holder
        } else {
            wanted.insert(number)
        }
        let asNames = await fetchNames(wanted, known: known, into: &gathered)
        return try finish(subject, query: resource, gathered: gathered, asNames: asNames)
    }

    // MARK: Steps

    /// One bulk `as-names` call for the origins that have no holder yet. A failure only drops the names.
    private func fetchNames(_ wanted: Set<UInt32>, known: [UInt32: String], into gathered: inout Gathered) async -> [UInt32: String] {
        let missing = wanted.subtracting(known.keys).sorted()
        let result = await fetchNamesResult(missing)
        return mergeNames(result, known: known, into: &gathered)
    }

    private func fetchNamesResult(_ missing: [UInt32]) async -> Result<[UInt32: String], any Error> {
        guard !missing.isEmpty else { return .success([:]) }
        let api = api
        return await attempt { try await api.asNames(missing) }
    }

    private func mergeNames(_ result: Result<[UInt32: String], any Error>, known: [UInt32: String],
                            into gathered: inout Gathered) -> [UInt32: String] {
        var names = known
        switch result {
        case let .success(fetched): names.merge(fetched) { current, _ in current }
        case let .failure(error): gathered.record(error, part: .names)
        }
        gathered.inputs.names = names
        return names
    }

    /// `nil` when locations are switched off.
    private func fetchLocationResult(_ resource: String) async -> Result<GeoLocation?, any Error>? {
        guard includeLocation else { return nil }
        let api = api
        return await attempt { try await api.geolocation(resource) }
    }

    private func finish(_ subject: WhoisSubject, query: String, gathered: Gathered, asNames: [UInt32: String]) throws -> WhoisResult {
        try Task.checkCancellation()
        var inputs = gathered.inputs
        inputs.failed = gathered.failed
        let kind: WhoisSummary.Subject
        if case let .asn(number) = subject { kind = .autonomousSystem(number) } else { kind = .network }
        let summary = seams.summarize(query, kind, inputs)
        if seams.isEmpty(summary) {
            // A failed call must not look like "no record".
            if gathered.whoisFailed || gathered.bgpFailed, let error = gathered.firstError {
                throw WhoisFailure.from(error)
            }
            throw WhoisFailure.notFound(query)
        }
        return WhoisResult(subject: subject, summary: summary, raw: inputs.whois, retriedWith: gathered.retriedWith,
                           reverseName: gathered.reverseName, location: gathered.location, fetchedAt: Date(), asNames: asNames)
    }

    /// Distinct `origin` values of the route objects ("AS8966" or "8966").
    static func irrOrigins(_ response: WhoisResponse?) -> Set<UInt32> {
        guard let response else { return [] }
        let values = response.irrRecords.flatMap { $0.fields.filter { $0.key == "origin" }.map(\.value) }
        return Set(values.compactMap { value in
            let digits = value.uppercased().hasPrefix("AS") ? String(value.dropFirst(2)) : value
            return UInt32(digits.trimmingCharacters(in: .whitespaces))
        })
    }
}
