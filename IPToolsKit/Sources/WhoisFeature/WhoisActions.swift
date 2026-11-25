// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

/// Ping, Traceroute and Map in BGP as equal-width buttons with the icon above the label. At accessibility sizes
/// the row becomes a vertical list.
struct WhoisActions: View {
    var showsPing = true
    var showsTrace = true
    var showsMap = true
    var onPing: () -> Void = {}
    var onTrace: () -> Void = {}
    var onMap: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize >= .accessibility1 {
            VStack(spacing: 8) { buttons }.padding(.horizontal)
        } else {
            HStack(spacing: 8) { buttons }.padding(.horizontal)
        }
    }

    @ViewBuilder private var buttons: some View {
        if showsPing { action("Ping", Tool.ping.systemImage, onPing) }
        if showsTrace { action("Traceroute", Tool.traceroute.systemImage, onTrace) }
        if showsMap { action("Map in BGP", Tool.bgp.systemImage, onMap) }
    }

    private func action(_ title: LocalizedStringKey, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Group {
                if typeSize >= .accessibility1 {
                    Label(title, systemImage: symbol)
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: symbol).font(.title3)
                        Text(title).font(.footnote)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}

#Preview("Actions") {
    VStack(spacing: 16) {
        WhoisActions()
        WhoisActions(showsPing: false, showsTrace: false)
    }
    .padding(.vertical)
    .background(Color.screenBackground)
}
