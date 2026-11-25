// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI

/// Plain-text exports (DESIGN §14.12). The approximate location is never part of them.
enum WhoisExport {
    private static let labelWidth = 12

    /// Share Summary.
    static func summary(_ result: WhoisResult, now: Date, holder: (String) -> String = { ASName.holderName($0) }) -> String {
        (summaryLines(result, holder: holder) + [Format.exportFooter(now)]).joined(separator: "\n")
    }

    /// Share Full Record: the summary, every object, then the routing registry objects.
    static func full(_ result: WhoisResult, now: Date, holder: (String) -> String = { ASName.holderName($0) }) -> String {
        var lines = summaryLines(result, holder: holder)
        lines.append("")
        lines.append(contentsOf: rawText(result))
        lines.append(Format.exportFooter(now))
        return lines.joined(separator: "\n")
    }

    /// The My IP text. `result` is the whois of the selected address, when loaded.
    static func myIP(_ snapshot: MyIPSnapshot, result: WhoisResult?, now: Date,
                     holder: (String) -> String = { ASName.holderName($0) }) -> String {
        var lines = ["My public IP — \(Format.utcStamp(now))"]
        let found: [(label: String, address: String, name: String?)] = IPVersion.allCases.compactMap { version in
            guard case let .found(address, name) = snapshot.slot(version) else { return nil }
            return (version == .v4 ? "IPv4" : "IPv6", address.description, name)
        }
        let width = (found.map(\.address.count).max() ?? 0) + 3
        for row in found {
            var line = "\(row.label)  \(row.address)"
            if let name = row.name { line = "\(row.label)  \(pad(row.address, width))\(name)" }
            lines.append(line)
        }
        if let result {
            let summary = result.summary
            var parts: [String] = []
            if let cidr = summary.cidrs.first ?? summary.routedPrefix { parts.append(cidr) }
            if let name = summary.name { parts.append(name) }
            if let origin = summary.originASNs.first {
                parts.append(originText(origin, names: result.asNames, holder: holder))
            }
            if let country = summary.country { parts.append(country) }
            if let rir = summary.rir { parts.append(rir.displayName) }
            if !parts.isEmpty { lines.append("Network  " + parts.joined(separator: " · ")) }
            if !summary.abuseEmails.isEmpty { lines.append("Abuse    " + summary.abuseEmails.joined(separator: ", ")) }
        }
        lines.append("— IP Tools for iOS")
        return lines.joined(separator: "\n")
    }

    // MARK: Summary

    static func summaryLines(_ result: WhoisResult, holder: (String) -> String) -> [String] {
        let summary = result.summary
        var lines = [header(result)]
        var rows: [(String, String)] = []
        switch summary.subject {
        case .network: networkRows(result, holder: holder, into: &rows)
        case .autonomousSystem: asRows(result, into: &rows)
        }
        lines.append(contentsOf: rows.map { pad($0.0, labelWidth) + $0.1 })
        lines.append(contentsOf: noteLines(summary))
        lines.append(sourceLine(result))
        return lines
    }

    private static func header(_ result: WhoisResult) -> String {
        var text = "WHOIS \(result.subject.resource)"
        if case let .address(_, hostname) = result.subject, let label = hostname ?? result.reverseName {
            text += " (\(label))"
        }
        return text
    }

    private static func networkRows(_ result: WhoisResult, holder: (String) -> String, into rows: inout [(String, String)]) {
        let summary = result.summary
        let cidr = summary.cidrs.isEmpty ? (summary.routedPrefix.map { [$0] } ?? []) : summary.cidrs
        if !cidr.isEmpty {
            rows.append(("Network", cidr.joined(separator: ", ") + (summary.range.map { "  (\($0))" } ?? "")))
        }
        appendCommon(result, into: &rows)
        let registry = registryText(summary)
        if let registry { rows.append(("Registry", registry)) }
        for origin in summary.originASNs {
            rows.append(("Origin AS", originText(origin, names: result.asNames, holder: holder) + "  (BGP)"))
        }
        appendTail(summary, into: &rows)
    }

    private static func asRows(_ result: WhoisResult, into rows: inout [(String, String)]) {
        let summary = result.summary
        appendCommon(result, into: &rows)
        if let registry = registryText(summary) { rows.append(("Registry", registry)) }
        if let announced = summary.announced { rows.append(("Announcing", announced ? "Yes, in BGP now" : "No")) }
        appendTail(summary, into: &rows)
    }

    /// Name, organisation and country, with their provenance.
    private static func appendCommon(_ result: WhoisResult, into rows: inout [(String, String)]) {
        let summary = result.summary
        if let name = summary.name { rows.append(("Name", name + (summary.handle.map { "  (\($0))" } ?? ""))) }
        if let organization = summary.organization {
            rows.append(("Org", organization + orgSuffix(summary)))
        }
        if let country = summary.country {
            rows.append(("Country", country + (summary.countryProvenance == .rirStatistics ? "  (RIR statistics)" : "")))
        }
    }

    private static func appendTail(_ summary: WhoisSummary, into rows: inout [(String, String)]) {
        rows.append(("Abuse", summary.abuseEmails.isEmpty ? "Not listed" : summary.abuseEmails.joined(separator: ", ")))
        if let registered = summary.registered { rows.append(("Registered", dateText(registered))) }
    }

    private static func registryText(_ summary: WhoisSummary) -> String? {
        let parts = [summary.rir?.displayName, summary.status].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func orgSuffix(_ summary: WhoisSummary) -> String {
        switch summary.organizationProvenance {
        case .description?: return "  (holder, from description)"
        case let .asHolder(number)?: return "  (network operator, from AS\(number))"
        case .rirStatistics?, .bgp?: return ""
        case .registry?, nil: return summary.orgHandle.map { "  (\($0))" } ?? ""
        }
    }

    private static func originText(_ asn: UInt32, names: [UInt32: String], holder: (String) -> String) -> String {
        guard let raw = names[asn], !raw.isEmpty else { return "AS\(asn)" }
        return "AS\(asn) \(holder(raw))"
    }

    private static func noteLines(_ summary: WhoisSummary) -> [String] {
        summary.notes.compactMap { note in
            switch note {
            case let .registryRecordsUnavailable(rir):
                rir == .lacnic ? "Note: LACNIC doesn't share whois records through RIPEstat." : "Note: Registry records weren't available."
            case .lowConfidence: "Note: RIPEstat couldn't identify the responsible registry; this is the best match."
            case .notAnnounced: "Note: Not announced in BGP."
            case .missing(.registry): "Note: Registry record unavailable."
            case .missing: nil
            }
        }
    }

    private static func sourceLine(_ result: WhoisResult) -> String {
        let stamp = Format.utcStamp(result.raw?.queryTime ?? result.fetchedAt)
        let name = result.summary.rir.map { "\($0.displayName) " } ?? ""
        return "Source: \(name)whois via RIPEstat, \(stamp)"
    }

    // MARK: Raw records

    /// Objects as `key:  value` lines (keys padded to the longest in the object), then the routing registry.
    static func rawText(_ result: WhoisResult) -> [String] {
        guard let raw = result.raw else { return [] }
        var lines: [String] = []
        let objects = raw.records.filter { !$0.isNoMatchMarker }
        for record in objects {
            lines.append(contentsOf: objectLines(record))
            lines.append("")
        }
        if !raw.irrRecords.isEmpty {
            lines.append("--- routing registry (IRR) ---")
            for record in raw.irrRecords {
                lines.append(contentsOf: objectLines(record))
                lines.append("")
            }
        }
        return lines
    }

    static func objectLines(_ record: WhoisRecord) -> [String] {
        let longest = record.fields.map(\.key.count).max() ?? 0
        return record.fields.map { field in
            let line = pad(field.key + ":", longest + 1) + "  " + field.value
            return line.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: Helpers

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
