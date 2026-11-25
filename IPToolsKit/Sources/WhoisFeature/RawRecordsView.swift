// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI
import SwiftUI

/// The raw registry and routing registry objects behind a summary. Pushed on iPhone, the inspector on iPad.
struct RawRecordsView: View {
    enum Section: String, Hashable { case registry, irr }

    let result: WhoisResult
    @Environment(\.dismiss) private var dismiss
    var scrollTo: Section?
    /// A link to `stat.ripe.net/<resource>` looks that resource up in place.
    var onLookUp: (String) -> Void = { _ in }
    /// The inspector has its own heading.
    var embedded = false

    private var objects: [WhoisRecord] { result.raw?.records.filter { !$0.isNoMatchMarker } ?? [] }
    private var hasMarker: Bool { result.raw?.records.contains { $0.isNoMatchMarker } ?? false }
    /// The registry had no match for the address itself: either the marker is in the data, or the covering prefix was used.
    private var showsMarker: Bool { hasMarker || result.retriedWith != nil }
    private var irr: [WhoisRecord] { result.raw?.irrRecords ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if embedded { Text("Raw records").font(.title3.bold()).accessibilityAddTraits(.isHeader) }
                    registrySection
                    irrSection
                    if objects.isEmpty, irr.isEmpty, !showsMarker {
                        Text("No raw records for this lookup.").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(embedded ? Color.clear : Color.screenBackground)
            .task { if let scrollTo { proxy.scrollTo(scrollTo, anchor: .top) } }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let resource = Self.statResource(url) else { return .systemAction }
            onLookUp(resource)
            if !embedded { dismiss() }
            return .handled
        })
        .modifier(RawRecordsTitle(enabled: !embedded))
        .toolbar {
            if !embedded {
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: WhoisExport.full(result, now: Date())) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { Clipboard.copy(WhoisExport.full(result, now: Date())) } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }

    /// "193.0.0.0/21" for `https://stat.ripe.net/193.0.0.0/21`; nil for any other link.
    static func statResource(_ url: URL) -> String? {
        guard url.scheme == "https", url.host == "stat.ripe.net" else { return nil }
        let path = (url.path.removingPercentEncoding ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty, !path.hasPrefix("app/") else { return nil }
        // Handles ("ORG-…", maintainers) and other pages are not lookups: leave those to Safari.
        switch TargetParser.parse(path, mode: .bgp) {
        case .ip?, .prefix?, .asn?: return path
        case .hostname?, nil: return nil
        }
    }

    @ViewBuilder private var registrySection: some View {
        if !objects.isEmpty || showsMarker {
            VStack(alignment: .leading, spacing: 8) {
                Text(registryHeader).font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                if showsMarker { Text(markerText).font(.footnote).foregroundStyle(.secondary) }
                ForEach(objects) { record in
                    RawRecordCard(record: record, isUsedInSummary: record.id == result.summary.summaryRecordID)
                }
            }
            .id(Section.registry)
        }
    }

    @ViewBuilder private var irrSection: some View {
        if !irr.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Routing registry (IRR)").font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                ForEach(irr) { record in
                    RawRecordCard(record: record, headerSuffix: record.source)
                }
            }
            .id(Section.irr)
        }
    }

    private var registryHeader: String {
        let count = objects.count
        let noun = count == 1 ? String(localized: "object") : String(localized: "objects")
        let name = result.summary.rir?.displayName
        return [name, "\(count) \(noun)"].compactMap { $0 }.joined(separator: " · ")
    }

    private var markerText: String {
        let name = result.summary.rir?.displayName ?? String(localized: "The registry")
        if let prefix = result.retriedWith {
            return String(localized: "\(name) had no match for the address; showing the covering prefix \(prefix).")
        }
        return String(localized: "\(name) had no match for this lookup.")
    }
}

private struct RawRecordsTitle: ViewModifier {
    let enabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.navigationTitle("Raw Records").inlineNavigationTitle()
        } else {
            content
        }
    }
}
