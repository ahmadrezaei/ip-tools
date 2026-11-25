// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI
import SwiftUI

/// iPhone (compact width): one scrolling column. My IP on top, or the subject of a lookup.
struct WhoisPhoneLayout: View {
    @Bindable var model: WhoisModel
    @Environment(\.isOnline) private var isOnline

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if model.isMyIPMode { WhoisMyIPContent(model: model) } else { WhoisSubjectContent(model: model) }
            }
            .padding(.vertical, 8)
        }
        .refreshable { if model.isMyIPMode { await model.refreshMyIPAndWait() } }
        .background(Color.screenBackground)
    }
}

/// My IP mode: your addresses, the whois of the selected one, this device, and a way to look up something else.
struct WhoisMyIPContent: View {
    @Bindable var model: WhoisModel
    var wide = false
    @Environment(\.isOnline) private var isOnline

    private var snapshot: MyIPSnapshot {
        model.myIP ?? MyIPSnapshot(v4: .checking, v6: .checking, viaVPN: false, generation: 0, fetchedAt: Date())
    }

    var body: some View {
        if snapshot.bothFailed { failure } else { addresses }
        if !wide {
            DeviceAddressesCard(addresses: model.localAddresses, publicV4: snapshot.address(.v4),
                                publicV6: snapshot.address(.v6))
        } else {
            DeviceAddressesCard(addresses: model.localAddresses, publicV4: snapshot.address(.v4),
                                publicV6: snapshot.address(.v6), collapsible: true)
        }
        lookUpSomethingElse
    }

    private var failure: some View {
        let message: String
        if case let .failed(text) = snapshot.v4 { message = text } else if case let .failed(text) = snapshot.v6 { message = text } else { message = "" }
        return ErrorStateView(MyIPFailure(message: message)) { model.refreshMyIP() }
            .frame(minHeight: 220)
    }

    @ViewBuilder private var addresses: some View {
        VStack(alignment: .leading, spacing: 6) {
            WhoisSectionCaption("Your public IP")
            MyIPCard(model: model, snapshot: snapshot, tiles: wide)
        }
        if snapshot.address(model.myFamily) != nil || snapshot.isChecking {
            VStack(alignment: .leading, spacing: 6) {
                WhoisSectionCaption("Your network")
                WhoisMyWhoisSection(model: model, showsRecordLinks: !(wide && model.inspectorShown))
            }
        }
    }

    @ViewBuilder private var lookUpSomethingElse: some View {
        if !wide {
            VStack(spacing: 12) {
                Text("Look up something else").font(.footnote).foregroundStyle(.secondary)
                ExampleChips(["8.8.8.8", "2606:4700::/32", "AS13335"]) { example in
                    model.targetText = example
                    if isOnline { model.lookUp() }
                }
                RecentsList(recents: model.recentsStore) { item in
                    model.targetText = item.display
                    if isOnline { model.lookUp() }
                }
            }
        }
    }
}

/// The whois of the selected own address: skeleton, summary or an inline error.
struct WhoisMyWhoisSection: View {
    @Bindable var model: WhoisModel
    var showsRecordLinks = true

    var body: some View {
        switch model.myWhois[model.myFamily] {
        case nil, .loading?:
            WhoisSummarySkeleton()
        case let .failed(failure)?:
            VStack(spacing: 8) {
                Label(failure.title, systemImage: failure.systemImage).font(.headline)
                Text(failure.message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if failure.action != nil { Button("Try Again") { model.retryMyWhois() } }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
        case let .loaded(result)?:
            WhoisSummaryCard(result: result, onLookUp: { model.lookUp($0) }, onRetry: { model.retryMyWhois() })
            if showsRecordLinks { WhoisRecordsLinks(model: model, result: result) }
            WhoisSourceFootnote(result: result)
        }
    }
}

/// Everything below the target bar once a lookup has started.
struct WhoisSubjectContent: View {
    @Bindable var model: WhoisModel
    var showsRecordLinks = true

    var body: some View {
        switch model.phase {
        case .myIP:
            EmptyView()
        case let .resolving(host):
            WhoisContextLine(text: String(localized: "Resolving \(host)…"), showsProgress: true, onBack: { model.showMyIP() })
        case let .loading(subject):
            WhoisContextLine(text: String(localized: "Looking up \(subject.resource) at RIPEstat…"), showsProgress: true,
                             onBack: { model.showMyIP() })
            WhoisSummarySkeleton()
        case let .loaded(result):
            WhoisResultSection(model: model, result: result, showsRecordLinks: showsRecordLinks)
        case let .local(verdict):
            WhoisContextLine(text: "", onBack: { model.showMyIP() })
            LocalAddressCard(verdict: verdict, onPing: { model.ping() }, onTrace: { model.trace() },
                             onLookUpEmbedded: { model.lookUp($0.description) })
            if let address = model.myIP?.address(model.myFamily) ?? model.myIP?.address(.v4) ?? model.myIP?.address(.v6) {
                MyIPHintRow(address: address) { model.showMyIP() }
            }
        case let .failed(failure):
            WhoisContextLine(text: "", onBack: { model.showMyIP() })
            ErrorStateView(failure) { model.lookUp() }
                .frame(minHeight: 260)
        }
    }
}

/// "‹ My IP" and the line that says what was looked up.
struct WhoisContextLine: View {
    let text: String
    var secondary: String?
    var showsProgress = false
    let onBack: () -> Void
    var others: [IPAddress] = []
    var onPickOther: (IPAddress) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Label("My IP", systemImage: "chevron.left").font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .frame(minHeight: 44)
                if showsProgress { ProgressView().controlSize(.small) }
                Text(text).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                if others.count > 1 { otherMenu }
            }
            if let secondary {
                Text(secondary).font(.footnote).foregroundStyle(.secondary).padding(.leading, 2)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var otherMenu: some View {
        Menu {
            ForEach(others, id: \.self) { address in
                Button(address.description) { onPickOther(address) }
            }
        } label: {
            Text("Other addresses").font(.footnote)
        }
    }
}

/// A loaded lookup: context line, summary, actions, record links and the source line.
struct WhoisResultSection: View {
    @Bindable var model: WhoisModel
    let result: WhoisResult
    var showsRecordLinks = true

    var body: some View {
        WhoisContextLine(text: contextText, secondary: contextSecondary, onBack: { model.showMyIP() },
                         others: model.hostAddresses, onPickOther: { pickOther($0) })
        WhoisSummaryCard(result: result, showsReverseName: isAddress, onLookUp: { model.lookUp($0) },
                         onRetry: { model.lookUp() })
        WhoisActions(showsPing: result.subject.canProbe, showsTrace: result.subject.canProbe,
                     onPing: { model.ping() }, onTrace: { model.trace() }, onMap: { model.map() })
        if showsRecordLinks { WhoisRecordsLinks(model: model, result: result) }
        WhoisSourceFootnote(result: result)
    }

    private func pickOther(_ address: IPAddress) {
        if case let .address(_, host?) = result.subject { model.lookUp(address: address, hostname: host) }
    }

    private var isAddress: Bool { if case .address = result.subject { true } else { false } }

    private var contextText: String {
        let summary = result.summary
        switch result.subject {
        case let .address(ip, hostname):
            if let hostname { return "\(hostname) → \(ip.description)" }
            return [result.reverseName, summary.rir?.displayName].compactMap { $0 }.joined(separator: " · ")
        case .prefix:
            let shown = model.shownAs.map { String(localized: "Showing \($0). ") } ?? ""
            if let origin = summary.originASNs.first {
                return shown + String(localized: "Announced by AS\(String(origin))")
            }
            return shown + String(localized: "Not announced in BGP")
        case .asn:
            return summary.announced == false ? String(localized: "Not announcing any prefix") : String(localized: "Announcing prefixes")
        }
    }

    private var contextSecondary: String? {
        if case .address(_, _?) = result.subject {
            return String(localized: "This is the network that hosts the address, not the domain's registration.")
        }
        return nil
    }
}

/// "Registry records · 4 objects ›" and "Routing registry (IRR) · 1 route ›", pushing the raw view.
struct WhoisRecordsLinks: View {
    let model: WhoisModel
    let result: WhoisResult

    private var objects: Int { result.raw?.records.filter { !$0.isNoMatchMarker }.count ?? 0 }
    private var routes: Int { result.raw?.irrRecords.count ?? 0 }

    var body: some View {
        if objects > 0 || routes > 0 {
            VStack(spacing: 0) {
                if objects > 0 {
                    link(String(localized: "Registry records · \(objects) \(objects == 1 ? String(localized: "object") : String(localized: "objects"))"), .registry)
                }
                if objects > 0, routes > 0 { Divider().padding(.leading, 14) }
                if routes > 0 {
                    link(String(localized: "Routing registry (IRR) · \(routes) \(routes == 1 ? String(localized: "route") : String(localized: "routes"))"), .irr)
                }
            }
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
        }
    }

    private func link(_ title: String, _ section: RawRecordsView.Section) -> some View {
        NavigationLink {
            RawRecordsView(result: result, scrollTo: section, onLookUp: { model.lookUp($0) })
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "Source: ARIN whois via RIPEstat, updated 13:40 UTC. Registry data can be out of date."
struct WhoisSourceFootnote: View {
    let result: WhoisResult

    var body: some View {
        let date = result.raw?.queryTime ?? result.fetchedAt
        let rir = result.summary.rir.map { "\($0.displayName) " } ?? ""
        Text("Source: \(rir)whois via RIPEstat, updated \(Format.utcStamp(date)). Registry data can be out of date.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
