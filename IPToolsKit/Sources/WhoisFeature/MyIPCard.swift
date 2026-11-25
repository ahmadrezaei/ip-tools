// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import RIPEstat
import SharedUI
import SwiftUI

/// Shown when neither family could be checked.
struct MyIPFailure: DisplayableError {
    let message: String
    var title: String { String(localized: "Couldn't Find Your IP") }
    var systemImage: String { "network.slash" }
    var action: ErrorAction? { .retry }
}

extension MyIPSnapshot.Slot {
    /// Plain text for a row that has no address.
    func unavailableText(_ version: IPVersion) -> String? {
        switch self {
        case .found: nil
        case .checking: String(localized: "Checking…")
        case .failed: String(localized: "Couldn't check")
        case let .unavailable(reason):
            switch reason {
            case .offline: String(localized: "Connect to the Internet to see your public IP")
            case .mismatch: String(localized: "No IPv6 through this connection")
            case .ipv6OnlyNetwork: String(localized: "IPv4 not available (IPv6-only network)")
            case .noRoute: version == .v6 ? String(localized: "No IPv6 on this network") : String(localized: "No IPv4 on this network")
            }
        }
    }
}

/// Your public IPv4 and IPv6, one row each (iPhone) or one tile each (iPad).
struct MyIPCard: View {
    @Bindable var model: WhoisModel
    var snapshot: MyIPSnapshot
    var tiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if tiles { tileLayout } else { rowLayout }
            MyIPFootnote(snapshot: snapshot)
            if !tiles, snapshot.address(.v4) != nil, snapshot.address(.v6) != nil { familyPicker }
        }
    }

    private var rowLayout: some View {
        VStack(spacing: 0) {
            row(.v4)
            Divider().padding(.leading, 14)
            row(.v6)
        }
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private var tileLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { tile(.v4); tile(.v6) }
                .frame(minWidth: 500)
            VStack(spacing: 12) { tile(.v4); tile(.v6) }
        }
        .padding(.horizontal)
    }

    private func row(_ version: IPVersion) -> some View {
        MyIPRow(model: model, snapshot: snapshot, version: version)
    }

    private func tile(_ version: IPVersion) -> some View {
        MyIPRow(model: model, snapshot: snapshot, version: version)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity)
    }

    private var familyPicker: some View {
        HStack(spacing: 10) {
            Text("Whois for").font(.footnote).foregroundStyle(.secondary)
            Picker("Whois for", selection: $model.myFamily) {
                Text("IPv4").tag(IPVersion.v4)
                Text("IPv6").tag(IPVersion.v6)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

struct MyIPRow: View {
    @Bindable var model: WhoisModel
    let snapshot: MyIPSnapshot
    let version: IPVersion

    @Environment(\.dynamicTypeSize) private var typeSize

    private var slot: MyIPSnapshot.Slot { snapshot.slot(version) }
    private var isSelected: Bool { model.myFamily == version && snapshot.address(version) != nil }
    private var badge: String { version == .v4 ? "IPv4" : "IPv6" }

    var body: some View {
        HStack(spacing: 10) {
            Text(badge)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.fieldFill, in: Capsule())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            content
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3).padding(.vertical, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if snapshot.address(version) != nil { model.myFamily = version } }
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text("Copy")) { copy() }
        .modifier(MyIPAccessibilityActions(model: model, snapshot: snapshot, version: version, isSelected: isSelected))
    }

    @ViewBuilder private var content: some View {
        switch slot {
        case let .found(address, name):
            VStack(alignment: .leading, spacing: 1) {
                Text(address.description)
                    .font(.system(size: version == .v4 ? 17 : 15, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.8)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(name ?? String(localized: "No reverse DNS")).font(.footnote).foregroundStyle(.secondary)
            }
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .failed:
            Text("Couldn't check").foregroundStyle(.secondary)
        case .unavailable:
            Label(slot.unavailableText(version) ?? "", systemImage: "network.slash")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch slot {
        case .found:
            Button { copy() } label: {
                Image(systemName: "doc.on.doc").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        case .failed:
            Button("Retry") { model.refreshMyIP() }.buttonStyle(.bordered).controlSize(.small)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var menu: some View {
        if let address = snapshot.address(version) {
            Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
            ShareLink(item: address.description) { Label("Share", systemImage: "square.and.arrow.up") }
            Button { model.mapMyIP(version) } label: { Label("Map in BGP", systemImage: Tool.bgp.systemImage) }
        }
    }

    private func copy() {
        if let address = snapshot.address(version) { Clipboard.copy(address.description) }
    }

    private var spokenLabel: Text {
        let family = version == .v4 ? String(localized: "IPv4 address") : String(localized: "IPv6 address")
        guard case let .found(address, name) = slot else {
            return Text("\(family), \(slot.unavailableText(version) ?? "")")
        }
        var text = AttributedString("\(family), ")
        text.append(address.family == .v4 ? AttributedString(IPSpeech.plain(address)) : IPSpeech.label(address))
        var tail = ", \(name ?? String(localized: "No reverse DNS"))."
        if isSelected { tail += " " + String(localized: "Selected for whois.") }
        text.append(AttributedString(tail))
        return Text(text)
    }
}

/// Show whois / Map in BGP / Retry as VoiceOver actions.
private struct MyIPAccessibilityActions: ViewModifier {
    let model: WhoisModel
    let snapshot: MyIPSnapshot
    let version: IPVersion
    let isSelected: Bool

    func body(content: Content) -> some View {
        let found = snapshot.address(version) != nil
        content
            .accessibilityAction(named: Text("Show whois")) { if found, !isSelected { model.myFamily = version } }
            .accessibilityAction(named: Text("Map in BGP")) { if found { model.mapMyIP(version) } }
            .accessibilityAction(named: Text("Retry")) { model.refreshMyIP() }
    }
}

/// "As RIPEstat sees this app's connection · 9:41", and the VPN line.
struct MyIPFootnote: View {
    let snapshot: MyIPSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if snapshot.foundAny {
                Text("As RIPEstat sees this app's connection · \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                if snapshot.viaVPN { Text("A VPN is active, so this is the VPN's address.") }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
