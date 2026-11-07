// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public struct OfflineBanner: View {
    public init() {}

    public var body: some View {
        Label("You're offline. Connect to run Ping, Traceroute or BGP Map.", systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.yellow.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

#Preview { OfflineBanner().padding() }
