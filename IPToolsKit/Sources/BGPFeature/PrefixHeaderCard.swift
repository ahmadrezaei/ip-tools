// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

struct PrefixHeaderCard: View {
    let result: BGPResult?

    var body: some View {
        if let result { Text(result.prefix).font(.headline) }
    }
}
