// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public enum IPVersion: String, Sendable, Hashable, CaseIterable { case v4, v6 }

public enum PublicIPError: Error, Sendable, Equatable {
    case noRoute(IPVersion), timeout(IPVersion), tls, badResponse(status: Int)
}

public struct WhoisField: Sendable, Hashable {
    public let key: String
    public let value: String
    public let link: URL?

    public init(key: String, value: String, link: URL?) {
        self.key = key
        self.value = value
        self.link = link
    }
}

public struct WhoisRecord: Sendable, Hashable, Identifiable {
    public let id: Int                                  // index in the response
    public let fields: [WhoisField]

    public init(id: Int, fields: [WhoisField]) {
        self.id = id
        self.fields = fields
    }

    public var primaryKey: String { fields.first?.key ?? "" }
    public var primaryValue: String { fields.first?.value ?? "" }
    /// "ARIN", "RIPE", "RADB"…
    public var source: String? { first("source") }
    /// A "No match found for …" line (or a `%` comment) the registry sent instead of an object.
    public var isNoMatchMarker: Bool { primaryKey.hasPrefix("No match found") || primaryKey.hasPrefix("%") }
    /// Case-sensitive (ARIN keys are CamelCase, RPSL lower-case).
    public func first(_ key: String) -> String? { fields.first { $0.key == key }?.value }
    public func all(_ key: String) -> [String] { fields.filter { $0.key == key }.map(\.value) }
}

public struct WhoisResponse: Sendable, Hashable {
    public let resource: String
    public let authorities: [String]                    // lower-case RIR ids
    public let records: [WhoisRecord]
    public let irrRecords: [WhoisRecord]                // de-duplicated
    public let warnings: [String]
    public let queryTime: Date?

    public init(resource: String, authorities: [String], records: [WhoisRecord], irrRecords: [WhoisRecord],
                warnings: [String], queryTime: Date?) {
        self.resource = resource
        self.authorities = authorities
        self.records = records
        self.irrRecords = irrRecords
        self.warnings = warnings
        self.queryTime = queryTime
    }

    /// True when the registry answered but only with no-match markers. An empty list (LACNIC) is not a no-match:
    /// there is nothing to retry.
    public var isNoMatch: Bool { !records.isEmpty && records.allSatisfy(\.isNoMatchMarker) }
    /// "Authoritative RIR could not be identified. Best match is returned!"
    public var isLowConfidence: Bool { warnings.contains { $0.localizedCaseInsensitiveContains("could not be identified") } }
}

public struct AbuseContacts: Sendable, Hashable {
    public let emails: [String]
    public let authoritativeRIR: String?

    public init(emails: [String], authoritativeRIR: String?) {
        self.emails = emails
        self.authoritativeRIR = authoritativeRIR
    }
}

public struct GeoLocation: Sendable, Hashable {
    public let country: String?
    public let city: String?
    public let coveredFraction: Double?

    public init(country: String?, city: String?, coveredFraction: Double?) {
        self.country = country
        self.city = city
        self.coveredFraction = coveredFraction
    }
}
