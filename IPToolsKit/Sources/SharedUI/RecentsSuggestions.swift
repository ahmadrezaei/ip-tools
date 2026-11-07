// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

/// Suggestion list shown under the target field while typing.
struct RecentsSuggestions: View {
    let suggestions: [RecentTarget]
    let onPick: (RecentTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { item in
                Button { onPick(item) } label: {
                    Label(item.display, systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
