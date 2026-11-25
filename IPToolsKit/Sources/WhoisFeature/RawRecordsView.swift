// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import RIPEstat
import SharedUI
import SwiftUI

/// The raw registry and routing registry objects behind a summary. Pushed on iPhone, the inspector on iPad.
struct RawRecordsView: View {
    enum Section: String, Hashable { case registry, irr }

    let result: WhoisResult
    var scrollTo: Section?
    /// A link to `stat.ripe.net/<resource>` looks that resource up in place.
    var onLookUp: (String) -> Void = { _ in }
    /// The inspector has its own heading.
    var embedded = false

    private var objects: [WhoisRecord] { result.raw?.records.filter { !$0.isNoMatchMarker } ?? [] }
    private var hasMarker: Bool { result.raw?.records.contains { $0.isNoMatchMarker } ?? false }
    private var irr: [WhoisRecord] { result.raw?.irrRecords ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if embedded { Text("Raw records").font(.title3.bold()).accessibilityAddTraits(.isHeader) }
                    registrySection
                    irrSection
                    if objects.isEmpty, irr.isEmpty, !hasMarker {
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
            return .handled
        })
        .navigationTitle("Raw Records")
        .inlineNavigationTitle()
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
        return path.isEmpty || path.hasPrefix("app/") ? nil : path
    }

    @ViewBuilder private var registrySection: some View {
        if !objects.isEmpty || hasMarker {
            VStack(alignment: .leading, spacing: 8) {
                Text(registryHeader).font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                if hasMarker { Text(markerText).font(.footnote).foregroundStyle(.secondary) }
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
