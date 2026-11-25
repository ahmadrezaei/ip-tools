// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Turns the raw `whois` objects and the helper calls into one `WhoisSummary` (DESIGN §14.9). Pure.
public enum WhoisSummarizer {
    public static func summarize(query: String, subject: WhoisSummary.Subject, inputs: WhoisInputs) -> WhoisSummary {
        var builder = SummaryBuilder(query: query, subject: subject, inputs: inputs)
        return builder.build()
    }

    /// DESIGN §14.9.2 most-specific rule: the network object with the longest prefix (ties: the later one); when
    /// there is no network object, the first AS object. Nil when there is neither (only markers, or nothing).
    public static func summaryRecord(in records: [WhoisRecord]) -> WhoisRecord? {
        var best: (record: WhoisRecord, length: Int)?
        for record in records where RecordClass(record) == .network {
            let length = prefixLength(of: record) ?? 0
            if best == nil || length >= best!.length { best = (record, length) }
        }
        if let best { return best.record }
        return records.first { RecordClass($0) == .autonomousSystem }
    }

    /// "193.0.0.0 - 193.0.7.255" -> ["193.0.0.0/21"]; minimal cover for non-aligned ranges.
    public static func cidrs(fromRange range: String) -> [String] {
        WhoisRange.cidrs(from: range)
    }

    /// Prefix length of a network object, from its CIDR or (smallest enclosing block of) its range.
    fileprivate static func prefixLength(of record: WhoisRecord) -> Int? {
        WhoisRange.prefixLength(of: record.primaryValue)
    }
}

/// How a record is used (DESIGN §14.9.2, by first key).
enum RecordClass: Equatable {
    case network, autonomousSystem, organization, abuseContact, otherContact, irrRoute, other

    init(_ record: WhoisRecord) {
        switch record.primaryKey {
        case "NetRange", "inetnum", "inet6num": self = .network
        case "ASNumber", "aut-num": self = .autonomousSystem
        case "OrgName": self = .organization
        case "OrgAbuseHandle", "RAbuseHandle": self = .abuseContact
        case "OrgTechHandle", "OrgNOCHandle", "OrgRoutingHandle", "RTechHandle", "RNOCHandle": self = .otherContact
        case "route", "route6": self = .irrRoute
        default: self = .other
        }
    }
}

private struct SummaryBuilder {
    let query: String
    let subject: WhoisSummary.Subject
    let inputs: WhoisInputs

    // Facts collected step by step.
    var cidrs: [String] = []
    var range: String?
    var name: String?
    var handle: String?
    var descriptions: [String] = []
    var organization: String?
    var organizationProvenance: WhoisSummary.Provenance?
    var orgHandle: String?
    var country: String?
    var countryProvenance: WhoisSummary.Provenance?
    var rir: RIR?
    var status: String?
    var parent: String?
    var routedPrefix: String?
    var originASNs: [UInt32] = []
    var registeredOrigins: [UInt32] = []
    var announced: Bool?
    var abuseEmails: [String] = []
    var abuseProvenance: WhoisSummary.Provenance?
    var registered: Date?
    var lastModified: Date?
    var contacts: [WhoisSummary.Contact] = []
    var summaryRecordID: Int?
    var notes: [WhoisSummary.Note] = []

    private var records: [WhoisRecord] { inputs.whois?.records ?? [] }
    private var isLowConfidence: Bool { inputs.whois?.isLowConfidence ?? false }

    init(query: String, subject: WhoisSummary.Subject, inputs: WhoisInputs) {
        self.query = query
        self.subject = subject
        self.inputs = inputs
    }

    mutating func build() -> WhoisSummary {
        collectRouting()
        let chosen = usableRecord()
        if let chosen {
            summaryRecordID = chosen.id
            readRegistry(chosen)
        }
        collectRegisteredOrigins()
        applyFallbacks()
        collectAbuse(chosen)
        collectNotes(chosen)
        return WhoisSummary(
            subject: subject, query: query, cidrs: cidrs, range: range, name: name, handle: handle,
            descriptions: descriptions, organization: organization, organizationProvenance: organizationProvenance,
            orgHandle: orgHandle, country: country, countryProvenance: countryProvenance, rir: rir, status: status,
            parent: parent, routedPrefix: routedPrefix, originASNs: originASNs, registeredOrigins: registeredOrigins,
            announced: announced, abuseEmails: abuseEmails, abuseProvenance: abuseProvenance, registered: registered,
            lastModified: lastModified, contacts: contacts, summaryRecordID: summaryRecordID, notes: notes)
    }

    // MARK: Chosen record

    /// The most specific object, minus the IANA catch-all (a huge block with a low-confidence warning).
    private func usableRecord() -> WhoisRecord? {
        guard let record = WhoisSummarizer.summaryRecord(in: records) else { return nil }
        guard RecordClass(record) == .network, isLowConfidence,
              let length = WhoisSummarizer.prefixLength(of: record) else { return record }
        let limit = WhoisRange.isIPv6(record.primaryValue) ? 12 : 8
        return length <= limit ? nil : record
    }

    // MARK: Routing (BGP)

    private mutating func collectRouting() {
        switch subject {
        case .network:
            if let network = inputs.network {
                routedPrefix = network.prefix
                originASNs = network.originASNs
                announced = network.prefix != nil && !network.originASNs.isEmpty
            }
            if let overview = inputs.prefixOverview {
                if routedPrefix == nil, overview.announced { routedPrefix = overview.resource }
                if originASNs.isEmpty { originASNs = overview.origins.map(\.asn) }
                announced = overview.announced
            }
        case .autonomousSystem:
            announced = inputs.asOverview?.announced
        }
    }

    // MARK: Registry object

    private mutating func readRegistry(_ record: WhoisRecord) {
        switch RecordClass(record) {
        case .network where record.primaryKey == "NetRange": readARINNetwork(record)
        case .network: readRPSLNetwork(record)
        case .autonomousSystem where record.primaryKey == "ASNumber": readARINAutNum(record)
        default: readRPSLAutNum(record)
        }
        rir = record.source.flatMap { RIR(identifier: $0) }
    }

    private mutating func readARINNetwork(_ record: WhoisRecord) {
        let listed = (record.first("CIDR") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        cidrs = listed.flatMap { WhoisRange.cidrs(from: $0) }
        range = record.first("NetRange").flatMap { WhoisRange.normalizedRange($0) ?? $0 }
        if cidrs.isEmpty, let range { cidrs = WhoisRange.cidrs(from: range) }
        name = nonEmpty(record.first("NetName"))
        handle = nonEmpty(record.first("NetHandle"))
        status = nonEmpty(record.first("NetType"))
        parent = meaningful(record.first("Parent"))
        registered = DateParsing.parse(record.first("RegDate"))
        lastModified = DateParsing.parse(record.first("Updated"))
        registeredOrigins = parseASNs(record.first("OriginAS") ?? "")
        readARINOrganization(owner: record.first("Organization") ?? record.first("Customer"))
        contacts = arinContacts()
    }

    private mutating func readARINAutNum(_ record: WhoisRecord) {
        name = nonEmpty(record.first("ASName"))
        handle = nonEmpty(record.first("ASHandle"))
        registered = DateParsing.parse(record.first("RegDate"))
        lastModified = DateParsing.parse(record.first("Updated"))
        readARINOrganization(owner: nil)
        contacts = arinContacts()
    }

    /// `Organization`/`Customer` is "Google LLC (GOGL)"; else the first `OrgName` object. Country comes from the
    /// organisation object with the matching `OrgId` (else the first one).
    private mutating func readARINOrganization(owner: String?) {
        let orgs = records.filter { RecordClass($0) == .organization }
        if let owner, !owner.isEmpty {
            let split = Self.splitHandle(owner)
            organization = split.name
            orgHandle = split.handle
            organizationProvenance = .registry
        } else if let first = orgs.first {
            organization = nonEmpty(first.primaryValue)
            orgHandle = nonEmpty(first.first("OrgId"))
            organizationProvenance = organization == nil ? nil : .registry
        }
        let match = orgs.first { orgHandle != nil && $0.first("OrgId") == orgHandle } ?? orgs.first
        if let match, let value = nonEmpty(match.first("Country")) {
            country = value.uppercased()
            countryProvenance = .registry
        }
    }

    private mutating func readRPSLNetwork(_ record: WhoisRecord) {
        let value = record.primaryValue
        cidrs = WhoisRange.cidrs(from: value)
        range = WhoisRange.normalizedRange(value) ?? WhoisRange.range(fromCIDR: value)
        name = nonEmpty(record.first("netname"))
        status = nonEmpty(record.first("status"))
        parent = nonEmpty(record.first("parent"))
        readRPSLCommon(record)
    }

    private mutating func readRPSLAutNum(_ record: WhoisRecord) {
        name = nonEmpty(record.first("as-name"))
        readRPSLCommon(record)
    }

    /// Fields shared by `inetnum`, `inet6num` and `aut-num`.
    private mutating func readRPSLCommon(_ record: WhoisRecord) {
        descriptions = record.all("descr").filter { !$0.isEmpty }
        orgHandle = nonEmpty(record.first("org"))
        if let value = nonEmpty(record.first("country")) {
            country = value.uppercased()
            countryProvenance = .registry
        }
        registered = DateParsing.parse(record.first("created"))
        lastModified = DateParsing.parse(record.first("last-modified"))
        if let orgName = nonEmpty(record.first("org-name")) ?? nonEmpty(record.first("owner")) {
            organization = orgName
            organizationProvenance = .registry
        } else if let holder = holderDescription(record) {
            organization = holder
            organizationProvenance = .description
        }
        contacts = rpslContacts(record)
    }

    // MARK: Contacts

    /// Resource-level handles (`R…`) when present, else the organisation's (`Org…`).
    private func arinContacts() -> [WhoisSummary.Contact] {
        let roles: [(role: String, resource: String, org: String)] = [
            ("Tech", "RTechHandle", "OrgTechHandle"),
            ("NOC", "RNOCHandle", "OrgNOCHandle"),
            ("Abuse", "RAbuseHandle", "OrgAbuseHandle"),
        ]
        var result: [WhoisSummary.Contact] = []
        for entry in roles {
            var handles = records.compactMap { $0.primaryKey == entry.resource ? nonEmpty($0.primaryValue) : nil }
            if handles.isEmpty {
                handles = records.compactMap { $0.primaryKey == entry.org ? nonEmpty($0.primaryValue) : nil }
            }
            for handle in handles where !result.contains(where: { $0.role == entry.role && $0.handle == handle }) {
                result.append(WhoisSummary.Contact(role: entry.role, handle: handle))
            }
        }
        return result
    }

    private func rpslContacts(_ record: WhoisRecord) -> [WhoisSummary.Contact] {
        let keys: [(role: String, key: String)] = [
            ("Admin", "admin-c"), ("Tech", "tech-c"), ("Abuse", "abuse-c"), ("Maintainer", "mnt-by"),
        ]
        return keys.flatMap { entry in
            record.all(entry.key).filter { !$0.isEmpty }.map { WhoisSummary.Contact(role: entry.role, handle: $0) }
        }
    }

    // MARK: Holder rule

    /// First `descr` line that is not the netname/as-name and does not look like a postal address.
    private func holderDescription(_ record: WhoisRecord) -> String? {
        let label = (record.first("netname") ?? record.first("as-name") ?? "").lowercased()
        return record.all("descr").first { line in
            !line.isEmpty && line.lowercased() != label && !Self.looksPostal(line)
        }
    }

    static func looksPostal(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        if tokens.contains(where: { $0.count >= 4 && $0.allSatisfy(\.isNumber) }) { return true }
        let tail = line.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return CountryNames.all.contains(tail)
    }

    // MARK: IRR / registered origins

    private mutating func collectRegisteredOrigins() {
        guard case .network = subject, let irr = inputs.whois?.irrRecords else { return }
        let reference = referencePrefix()
        for record in irr where RecordClass(record) == .irrRoute {
            if let reference, !WhoisRange.route(record.primaryValue, covers: reference) { continue }
            for origin in record.all("origin").compactMap(ASNText.parse) where !registeredOrigins.contains(origin) {
                registeredOrigins.append(origin)
            }
        }
    }

    /// The prefix IRR routes must cover (more specific routes of other networks are not this network's origins):
    /// the queried address or prefix, else the object's own block, else the BGP prefix.
    private func referencePrefix() -> (bytes: [UInt8], length: Int)? {
        if let address = WhoisRange.parseAddress(query) { return (address, address.count * 8) }
        let candidates: [String?] = [query, cidrs.first, routedPrefix]
        for candidate in candidates.compactMap({ $0 }) {
            if let parsed = WhoisRange.parseCIDR(candidate) { return parsed }
        }
        return nil
    }

    // MARK: Fallbacks (any RIR)

    private mutating func applyFallbacks() {
        if cidrs.isEmpty, let routedPrefix { cidrs = WhoisRange.cidrs(from: routedPrefix) }
        if range == nil, cidrs.count == 1 { range = WhoisRange.range(fromCIDR: cidrs[0]) }
        if country == nil, let stats = inputs.country, !stats.isEmpty {
            country = stats.uppercased()
            countryProvenance = .rirStatistics
        }
        if rir == nil {
            let authority = isLowConfidence ? nil : inputs.whois?.authorities.first
            rir = authority.flatMap { RIR(identifier: $0) } ?? inputs.abuse?.authoritativeRIR.flatMap { RIR(identifier: $0) }
        }
        if organization == nil { applyOperator() }
    }

    /// Network operator (network subjects) or holder (AS subjects) from `as-names` / `as-overview` / `prefix-overview`.
    private mutating func applyOperator() {
        let asn: UInt32?
        let holder: String?
        switch subject {
        case .network:
            asn = originASNs.first
            holder = asn.flatMap { number in
                inputs.names[number] ?? inputs.prefixOverview?.origins.first { $0.asn == number }?.holder
            }
        case .autonomousSystem(let number):
            asn = number
            holder = inputs.names[number] ?? inputs.asOverview?.holder
        }
        guard let asn, let holder, !holder.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        organization = ASName.holderName(holder)
        organizationProvenance = .asHolder(asn)
    }

    // MARK: Abuse

    private mutating func collectAbuse(_ chosen: WhoisRecord?) {
        if let emails = inputs.abuse?.emails, !emails.isEmpty {
            abuseEmails = emails
            abuseProvenance = nil
            return
        }
        var found = chosen == nil && !records.isEmpty ? [] : registryAbuseEmails()
        if found.isEmpty { found = remarkAbuseEmails(chosen) }
        abuseEmails = found
        abuseProvenance = found.isEmpty ? nil : .registry
    }

    private func registryAbuseEmails() -> [String] {
        var emails: [String] = []
        for key in ["RAbuseEmail", "OrgAbuseEmail", "abuse-mailbox"] {
            let values = records.flatMap { $0.all(key) }.filter { !$0.isEmpty }
            if !values.isEmpty {
                emails = values
                break
            }
        }
        var unique: [String] = []
        for email in emails where !unique.contains(email) { unique.append(email) }
        return unique
    }

    /// Last resort: an e-mail address in a `remarks`/`Comment`/`descr` line that mentions "abuse".
    private func remarkAbuseEmails(_ chosen: WhoisRecord?) -> [String] {
        guard let chosen else { return [] }
        let lines = ["remarks", "Comment", "descr"].flatMap { chosen.all($0) }
        for line in lines where line.localizedCaseInsensitiveContains("abuse") {
            if let email = Self.firstEmail(in: line) { return [email] }
        }
        return []
    }

    private static let emailPattern = try? NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")

    static func firstEmail(in text: String) -> String? {
        let full = NSRange(text.startIndex..., in: text)
        guard let match = emailPattern?.firstMatch(in: text, range: full), let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }

    // MARK: Notes

    private mutating func collectNotes(_ chosen: WhoisRecord?) {
        // A dropped IANA catch-all object means "no record", not "this registry doesn't share records".
        let droppedCatchAll = chosen == nil && WhoisSummarizer.summaryRecord(in: records) != nil
        if inputs.whois != nil, chosen == nil, !droppedCatchAll {
            notes.append(.registryRecordsUnavailable(rir))
        }
        if isLowConfidence { notes.append(.lowConfidence) }
        if announced == false, chosen != nil || !registeredOrigins.isEmpty || !cidrs.isEmpty {
            notes.append(.notAnnounced)
        }
        let order: [WhoisSummary.Part] = [.registry, .routing, .abuse, .country, .location, .names]
        for part in order where inputs.failed.contains(part) { notes.append(.missing(part)) }
    }

    // MARK: Small helpers

    private func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// ARIN prints "()" for a missing parent.
    private func meaningful(_ text: String?) -> String? {
        guard let value = nonEmpty(text), value.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return value
    }

    private func parseASNs(_ text: String) -> [UInt32] {
        var result: [UInt32] = []
        for token in text.split(whereSeparator: { $0 == "," || $0 == " " }) {
            if let asn = ASNText.parse(String(token)), !result.contains(asn) { result.append(asn) }
        }
        return result
    }

    /// "Google LLC (GOGL)" -> ("Google LLC", "GOGL"); no parenthetical -> (text, nil).
    static func splitHandle(_ text: String) -> (name: String, handle: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "(") else { return (trimmed, nil) }
        let handle = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        let name = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !handle.isEmpty else { return (trimmed, nil) }
        return (name, handle)
    }
}

/// English country names, for the "postal-looking line" test of the holder rule.
private enum CountryNames {
    static let all: Set<String> = {
        let locale = Locale(identifier: "en_US")
        var names = Set(Locale.Region.isoRegions.compactMap { locale.localizedString(forRegionCode: $0.identifier)?.lowercased() })
        names.formUnion(["usa", "uk", "russia", "south korea", "korea", "the netherlands", "czech republic",
                         "united states of america", "viet nam"])
        return names
    }()
}
