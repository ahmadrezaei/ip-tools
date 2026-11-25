// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public enum RIR: String, Sendable, Hashable, CaseIterable {
    case afrinic, apnic, arin, lacnic, ripe

    /// "ARIN", "arin", "RIPE", "RIPE-NONAUTH", "RIPE NCC", "AfriNIC"…
    public init?(identifier: String) { nil }

    /// "AFRINIC", "APNIC", "ARIN", "LACNIC", "RIPE NCC"
    public var displayName: String {
        switch self {
        case .afrinic: "AFRINIC"
        case .apnic: "APNIC"
        case .arin: "ARIN"
        case .lacnic: "LACNIC"
        case .ripe: "RIPE NCC"
        }
    }
}

public struct WhoisSummary: Sendable, Hashable {
    public enum Subject: Sendable, Hashable { case network, autonomousSystem(UInt32) }
    public enum Provenance: Sendable, Hashable { case registry, description, asHolder(UInt32), rirStatistics, bgp }
    public enum Part: Sendable, Hashable { case registry, routing, abuse, country, location, names }
    public enum Note: Sendable, Hashable { case registryRecordsUnavailable(RIR?), lowConfidence, notAnnounced, missing(Part) }
    public struct Contact: Sendable, Hashable {
        public let role: String
        public let handle: String

        public init(role: String, handle: String) {
            self.role = role
            self.handle = handle
        }
    }

    public let subject: Subject
    public let query: String
    public let cidrs: [String]
    public let range: String?
    public let name: String?
    public let handle: String?
    public let descriptions: [String]
    public let organization: String?
    public let organizationProvenance: Provenance?
    public let orgHandle: String?
    public let country: String?                       // ISO 3166-1 alpha-2 or region code, upper-case
    public let countryProvenance: Provenance?
    public let rir: RIR?
    public let status: String?
    public let parent: String?
    public let routedPrefix: String?
    public let originASNs: [UInt32]                   // BGP
    public let registeredOrigins: [UInt32]            // IRR / ARIN OriginAS
    public let announced: Bool?
    public let abuseEmails: [String]
    public let abuseProvenance: Provenance?           // .registry (whois) or nil when from abuse-contact-finder
    public let registered: Date?
    public let lastModified: Date?
    public let contacts: [Contact]
    public let summaryRecordID: Int?                  // WhoisRecord.id used ("Used in summary" tag)
    public let notes: [Note]

    /// Not-found rule, DESIGN §14.9.3.
    public var isEmpty: Bool { false }

    public init(subject: Subject, query: String, cidrs: [String] = [], range: String? = nil, name: String? = nil,
                handle: String? = nil, descriptions: [String] = [], organization: String? = nil,
                organizationProvenance: Provenance? = nil, orgHandle: String? = nil, country: String? = nil,
                countryProvenance: Provenance? = nil, rir: RIR? = nil, status: String? = nil, parent: String? = nil,
                routedPrefix: String? = nil, originASNs: [UInt32] = [], registeredOrigins: [UInt32] = [],
                announced: Bool? = nil, abuseEmails: [String] = [], abuseProvenance: Provenance? = nil,
                registered: Date? = nil, lastModified: Date? = nil, contacts: [Contact] = [],
                summaryRecordID: Int? = nil, notes: [Note] = []) {
        self.subject = subject
        self.query = query
        self.cidrs = cidrs
        self.range = range
        self.name = name
        self.handle = handle
        self.descriptions = descriptions
        self.organization = organization
        self.organizationProvenance = organizationProvenance
        self.orgHandle = orgHandle
        self.country = country
        self.countryProvenance = countryProvenance
        self.rir = rir
        self.status = status
        self.parent = parent
        self.routedPrefix = routedPrefix
        self.originASNs = originASNs
        self.registeredOrigins = registeredOrigins
        self.announced = announced
        self.abuseEmails = abuseEmails
        self.abuseProvenance = abuseProvenance
        self.registered = registered
        self.lastModified = lastModified
        self.contacts = contacts
        self.summaryRecordID = summaryRecordID
        self.notes = notes
    }
}

public struct WhoisInputs: Sendable {
    public var whois: WhoisResponse?
    public var network: NetworkInfo?
    public var prefixOverview: PrefixOverview?
    public var asOverview: ASOverview?
    public var abuse: AbuseContacts?
    public var country: String?
    public var names: [UInt32: String]
    public var failed: Set<WhoisSummary.Part>

    public init(whois: WhoisResponse? = nil, network: NetworkInfo? = nil, prefixOverview: PrefixOverview? = nil,
                asOverview: ASOverview? = nil, abuse: AbuseContacts? = nil, country: String? = nil,
                names: [UInt32: String] = [:], failed: Set<WhoisSummary.Part> = []) {
        self.whois = whois
        self.network = network
        self.prefixOverview = prefixOverview
        self.asOverview = asOverview
        self.abuse = abuse
        self.country = country
        self.names = names
        self.failed = failed
    }
}
