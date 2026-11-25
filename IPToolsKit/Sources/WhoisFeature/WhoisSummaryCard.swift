// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI
import SwiftUI

/// The normalised summary of a network or AS (DESIGN §14.3.3). Missing values are left out; only Abuse says so.
struct WhoisSummaryCard: View {
    let result: WhoisResult
    /// Result mode shows the reverse name of an address here; My IP shows it in the address row.
    var showsReverseName = false
    var onLookUp: (String) -> Void = { _ in }
    var onRetry: () -> Void = {}

    private var summary: WhoisSummary { result.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch summary.subject {
                case .network: networkRows
                case .autonomousSystem: asRows
                }
            }
            WhoisNotesStrip(summary: summary, resource: result.subject.resource, onRetry: onRetry)
        }
        .padding(.bottom, 4)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: Header

    private var title: String {
        switch summary.subject {
        case let .autonomousSystem(number): return "AS\(number)"
        case .network:
            guard let first = summary.cidrs.first ?? summary.routedPrefix else { return summary.query }
            return summary.cidrs.count > 1 ? "\(first) +\(summary.cidrs.count - 1)" : first
        }
    }

    private var subtitle: String? {
        let parts = [summary.name, summary.organization].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 20, weight: .bold, design: .monospaced)).textSelection(.enabled)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Network rows

    @ViewBuilder private var networkRows: some View {
        organizationRow
        rangeRow
        countryRow
        registryRow
        originRow
        abuseRow
        locationRow
        registeredRow
        reverseRow
    }

    @ViewBuilder private var asRows: some View {
        organizationRow
        if let name = summary.name { WhoisRow("AS name", text: name) }
        countryRow
        registryRow
        if let announced = summary.announced {
            WhoisRow("Announcing", text: announced ? String(localized: "Yes, in BGP now") : String(localized: "No"))
        }
        abuseRow
        registeredRow
    }

    @ViewBuilder private var organizationRow: some View {
        if let organization = summary.organization {
            let label = organizationLabel
            WhoisRow(label.key, spoken: organizationSpoken(label.text, organization)) {
                VStack(alignment: .leading, spacing: 1) {
                    WhoisValue(text: organization, caption: label.caption)
                    if let handle = summary.orgHandle, showsOrgHandle {
                        Text(handle).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var showsOrgHandle: Bool {
        switch summary.organizationProvenance {
        case nil, .registry?, .description?: true
        default: false
        }
    }

    private var organizationLabel: (key: LocalizedStringKey, text: String, caption: String?) {
        switch summary.organizationProvenance {
        case .description?:
            (key: "Holder", text: String(localized: "Holder"), caption: String(localized: "from description"))
        case let .asHolder(number)?:
            (key: "Network operator", text: String(localized: "Network operator"),
             caption: String(localized: "from AS\(String(number))"))
        default:
            (key: "Organization", text: String(localized: "Organization"), caption: nil)
        }
    }

    private func organizationSpoken(_ label: String, _ organization: String) -> String {
        switch summary.organizationProvenance {
        case .description?: String(localized: "\(label), \(organization), from description")
        case let .asHolder(number)?: String(localized: "\(label), \(organization), from AS \(String(number))")
        default: "\(label), \(organization)"
        }
    }

    @ViewBuilder private var rangeRow: some View {
        if let range = summary.range, summary.cidrs.count != 1 || summary.cidrs[0].contains(".") {
            WhoisRow("Range", text: range.replacingOccurrences(of: " - ", with: " – "))
        }
    }

    @ViewBuilder private var countryRow: some View {
        if let code = summary.country {
            let name = CountryFormat.name(code)
            WhoisRow("Country", spoken: String(localized: "Country, \(name)")) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let flag = CountryFormat.flag(code) { Text(flag).accessibilityHidden(true) }
                    WhoisValue(text: name, caption: summary.countryProvenance == .rirStatistics
                               ? String(localized: "from RIR statistics") : nil)
                }
            }
        }
    }

    @ViewBuilder private var registryRow: some View {
        let parts = [summary.rir?.displayName, summary.status].compactMap { $0 }
        if !parts.isEmpty {
            let text = parts.joined(separator: " · ")
            WhoisRow("Registry", spoken: String(localized: "Registry, \(text)")) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    WhoisValue(text: text)
                    if summary.status != nil { InfoPopoverButton(title: "Registry statuses", message: Self.statusGlossary) }
                }
            }
        }
    }

    static let statusGlossary: LocalizedStringKey = """
        Allocated PA: a block given to a registry member to hand out.
        Assigned PA: a block a member assigned to an end user.
        Assigned PI: a block held directly by an end user, independent of any provider.
        Direct Allocation: a block allocated straight from the registry.
        Reallocated: a part of a block passed on to another organisation to hand out.
        Reassigned: a part of a block assigned to an end user.
        """

    // MARK: Origin AS

    @ViewBuilder private var originRow: some View {
        if !summary.originASNs.isEmpty {
            WhoisRow("Origin AS", interactive: true) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.originASNs, id: \.self) { asn in originButton(asn) }
                    registeredOriginCaption
                }
            }
        } else if summary.announced == false || summary.notes.contains(.notAnnounced) {
            WhoisRow("Origin AS", spoken: String(localized: "Origin AS, not announced in BGP")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not announced in BGP").foregroundStyle(.orange)
                    registeredOriginCaption
                }
            }
        }
    }

    private func originButton(_ asn: UInt32) -> some View {
        let name = result.asNames[asn].map { ASName.short($0) } ?? ""
        return Button { onLookUp("AS\(asn)") } label: {
            HStack(spacing: 6) {
                ASNBadge(asn: asn)
                if !name.isEmpty { Text(name).foregroundStyle(.primary) }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name.isEmpty ? IPSpeech.asn(asn) : "\(IPSpeech.asn(asn)), \(name)")
        .accessibilityHint(String(localized: "Looks up \(IPSpeech.asn(asn))"))
    }

    @ViewBuilder private var registeredOriginCaption: some View {
        let registered = summary.registeredOrigins.filter { !summary.originASNs.contains($0) }
        if !registered.isEmpty {
            let list = registered.map { "AS\($0)" }.joined(separator: ", ")
            Text("Registered route object: \(list)").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Abuse, location, dates

    @ViewBuilder private var abuseRow: some View {
        if summary.abuseEmails.isEmpty {
            WhoisRow("Abuse", text: String(localized: "Not listed"))
        } else {
            WhoisRow("Abuse", interactive: true) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(summary.abuseEmails.prefix(3), id: \.self) { email in
                        if let url = URL(string: "mailto:\(email)") {
                            Link(email, destination: url).copyContextMenu(email)
                        }
                    }
                    if summary.abuseEmails.count > 3 {
                        Text("+\(summary.abuseEmails.count - 3) more in the raw records").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var locationRow: some View {
        if let location = result.location, let text = Self.locationText(location) {
            WhoisRow("Location", spoken: String(localized: "Location, \(text), approximate")) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(text) · approx.")
                    InfoPopoverButton(title: "About location", message: """
                        Estimated by MaxMind GeoLite2 (via RIPEstat). Often wrong for mobile, VPN and cloud addresses.
                        """)
                }
            }
        }
    }

    /// "Nuremberg, DE" or "United States".
    static func locationText(_ location: GeoLocation) -> String? {
        switch (location.city?.nilIfEmpty, location.country?.nilIfEmpty) {
        case let (city?, country?): "\(city), \(country)"
        case let (city?, nil): city
        case let (nil, country?): CountryFormat.name(country)
        case (nil, nil): nil
        }
    }

    @ViewBuilder private var registeredRow: some View {
        if let registered = summary.registered {
            let date = registered.formatted(date: .abbreviated, time: .omitted)
            let changed = summary.lastModified.map { String(localized: " · changed \($0.formatted(date: .abbreviated, time: .omitted))") } ?? ""
            WhoisRow("Registered", text: date + changed)
        }
    }

    @ViewBuilder private var reverseRow: some View {
        if showsReverseName, let name = result.reverseName {
            WhoisRow("Reverse DNS", text: name)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Short sentences under the rows: LACNIC, low confidence, registry record missing.
struct WhoisNotesStrip: View {
    let summary: WhoisSummary
    let resource: String
    var onRetry: () -> Void = {}

    private enum Item: Hashable { case unavailable(RIR?), lowConfidence, registryMissing }

    private var items: [Item] {
        summary.notes.compactMap { note in
            switch note {
            case let .registryRecordsUnavailable(rir): .unavailable(rir)
            case .lowConfidence: .lowConfidence
            case .missing(.registry): .registryMissing
            case .notAnnounced, .missing: nil
            }
        }
    }

    var body: some View {
        let items = items
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text(for: item)).font(.caption).foregroundStyle(.secondary)
                        action(for: item)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    private func text(for item: Item) -> String {
        switch item {
        case let .unavailable(rir):
            rir == .lacnic
                ? String(localized: "LACNIC doesn't share whois records through RIPEstat. Showing BGP and registry statistics.")
                : String(localized: "RIPEstat has no registry record for this one. Showing BGP and registry statistics.")
        case .lowConfidence:
            String(localized: "RIPEstat couldn't identify the responsible registry; this is the best match.")
        case .registryMissing:
            String(localized: "Registry record unavailable right now.")
        }
    }

    @ViewBuilder private func action(for item: Item) -> some View {
        switch item {
        case .unavailable:
            if let url = URL(string: "https://stat.ripe.net/\(resource)") {
                Link("Open in RIPEstat", destination: url).font(.caption.weight(.semibold))
            }
        case .registryMissing:
            Button("Try Again", action: onRetry).font(.caption.weight(.semibold))
        case .lowConfidence:
            EmptyView()
        }
    }
}

/// Redacted stand-in while a summary loads.
struct WhoisSummarySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "8.8.8.0/24").font(.system(size: 20, weight: .bold, design: .monospaced))
                Text(verbatim: "GOGL · Google LLC").font(.subheadline)
            }
            .padding(14)
            ForEach(["Organization", "Country", "Registry", "Origin AS", "Abuse"], id: \.self) { key in
                WhoisRow(LocalizedStringKey(key), text: "Placeholder value")
            }
        }
        .padding(.bottom, 4)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Loading"))
    }
}
