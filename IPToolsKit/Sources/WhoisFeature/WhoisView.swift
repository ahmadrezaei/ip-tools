// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

/// Placeholder until the Whois UI lands.
public struct WhoisView: View {
    private let model: WhoisModel

    public init(model: WhoisModel) {
        self.model = model
    }

    public var body: some View {
        Text("Whois")
            .navigationTitle("Whois")
    }
}
