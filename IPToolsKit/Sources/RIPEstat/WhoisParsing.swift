// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

/// Decoding of the `whois`, `abuse-contact-finder`, `rir-stats-country` and `maxmind-geo-lite` envelopes (DESIGN §14.9).
enum WhoisParsing {
    // MARK: whois

    struct FieldDTO: Decodable, Sendable {
        let key: String?
        let value: String?
        let detailsLink: String?

        enum CodingKeys: String, CodingKey {
            case key, value
            case detailsLink = "details_link"
        }
    }

    struct WhoisDTO: Decodable, Sendable {
        let records: [Lossy<[Lossy<FieldDTO>]>]?
        let irrRecords: [Lossy<[Lossy<FieldDTO>]>]?
        let authorities: [String]?
        let resource: String?
        let queryTime: String?

        enum CodingKeys: String, CodingKey {
            case records, authorities, resource
            case irrRecords = "irr_records"
            case queryTime = "query_time"
        }
    }

    /// Cleans a raw `whois` response: trims keys and values (ARIN pads them), keeps empty values and repeated keys,
    /// keeps only http(s)/mailto links, and collapses duplicate IRR objects.
    static func whois(_ data: Data, resource: String) throws -> WhoisResponse {
        let dto = try RIPEstatParsing.payload(data, as: WhoisDTO.self)
        let probe = try? JSONDecoder().decode(EnvelopeProbe.self, from: data)
        let warnings = (probe?.messages ?? []).filter { $0.first == "warning" && $0.count > 1 }.map { $0[1] }
        let records = buildRecords(from: dto.records ?? [], firstID: 0)
        let irr = deduplicated(buildRecords(from: dto.irrRecords ?? [], firstID: records.count), firstID: records.count)
        return WhoisResponse(resource: dto.resource ?? resource,
                             authorities: (dto.authorities ?? []).map { $0.trimmingCharacters(in: .whitespaces).lowercased() },
                             records: records,
                             irrRecords: irr,
                             warnings: warnings,
                             queryTime: DateParsing.parse(dto.queryTime))
    }

    private static func buildRecords(from raw: [Lossy<[Lossy<FieldDTO>]>], firstID: Int) -> [WhoisRecord] {
        raw.compactMap(\.value).enumerated().map { offset, fields in
            WhoisRecord(id: firstID + offset, fields: fields.compactMap { $0.value }.compactMap(field))
        }
    }

    private static func field(_ dto: FieldDTO) -> WhoisField? {
        guard let key = dto.key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        let value = dto.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return WhoisField(key: key, value: value, link: link(dto.detailsLink))
    }

    private static func link(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else { return nil }
        return url
    }

    /// RIPE often returns the same route object twice, the second time with a privacy banner in `remarks`.
    /// Objects are the same when their fields match, ignoring `remarks`. The first one wins.
    private static func deduplicated(_ records: [WhoisRecord], firstID: Int) -> [WhoisRecord] {
        var seen = Set<[String]>()
        var kept: [WhoisRecord] = []
        for record in records {
            let signature = record.fields.filter { $0.key != "remarks" }.map { "\($0.key)\u{1}\($0.value)" }
            if seen.insert(signature).inserted { kept.append(record) }
        }
        return kept.enumerated().map { WhoisRecord(id: firstID + $0.offset, fields: $0.element.fields) }
    }

    // MARK: abuse-contact-finder

    struct AbuseDTO: Decodable, Sendable {
        let abuseContacts: [String]?
        let authoritativeRIR: String?

        enum CodingKeys: String, CodingKey {
            case abuseContacts = "abuse_contacts"
            case authoritativeRIR = "authoritative_rir"
        }
    }

    static func abuse(_ data: Data) throws -> AbuseContacts {
        let dto = try RIPEstatParsing.payload(data, as: AbuseDTO.self)
        var emails: [String] = []
        for email in (dto.abuseContacts ?? []).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        where !email.isEmpty && !emails.contains(email) {
            emails.append(email)
        }
        let rir = dto.authoritativeRIR?.trimmingCharacters(in: .whitespaces).lowercased()
        return AbuseContacts(emails: emails, authoritativeRIR: (rir?.isEmpty ?? true) ? nil : rir)
    }

    // MARK: rir-stats-country

    struct CountryDTO: Decodable, Sendable {
        struct Located: Decodable, Sendable { let location: String? }
        let locatedResources: [Lossy<Located>]?

        enum CodingKeys: String, CodingKey { case locatedResources = "located_resources" }
    }

    static func country(_ data: Data) throws -> String? {
        let dto = try RIPEstatParsing.payload(data, as: CountryDTO.self)
        return (dto.locatedResources ?? []).compactMap { $0.value?.location }
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .first { !$0.isEmpty }
    }

    // MARK: maxmind-geo-lite

    struct GeoDTO: Decodable, Sendable {
        struct Location: Decodable, Sendable {
            let country: String?
            let city: String?
            let coveredPercentage: Double?

            enum CodingKeys: String, CodingKey {
                case country, city
                case coveredPercentage = "covered_percentage"
            }
        }

        struct Located: Decodable, Sendable { let locations: [Lossy<Location>]? }
        let locatedResources: [Lossy<Located>]?

        enum CodingKeys: String, CodingKey { case locatedResources = "located_resources" }
    }

    /// The first location of the first located resource. Empty strings become nil; no usable field gives nil.
    static func geolocation(_ data: Data) throws -> GeoLocation? {
        let dto = try RIPEstatParsing.payload(data, as: GeoDTO.self)
        let first = (dto.locatedResources ?? []).compactMap { $0.value }
            .flatMap { ($0.locations ?? []).compactMap { $0.value } }.first
        guard let first else { return nil }
        func clean(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespaces) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        let country = clean(first.country)?.uppercased()
        let city = clean(first.city)
        guard country != nil || city != nil else { return nil }
        return GeoLocation(country: country, city: city, coveredFraction: first.coveredPercentage.map { $0 / 100 })
    }
}
