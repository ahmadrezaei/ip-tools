// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

struct AboutView: View {
    let environment: AppEnvironment

    var body: some View {
        Form {
            Text("IP Tools")
            Button("Clear History", role: .destructive) { environment.recents.clear() }
        }
        .navigationTitle("About")
    }
}
