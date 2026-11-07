// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

public struct OfflineBanner: View {
    public init() {}

    public var body: some View {
        Label("No internet connection", systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(.orange.opacity(0.2))
    }
}
