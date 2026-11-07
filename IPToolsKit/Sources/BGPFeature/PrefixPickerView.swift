// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SwiftUI

struct PrefixPickerView: View {
    let prefixes: [String]
    let onPick: (String) -> Void

    var body: some View {
        List(prefixes, id: \.self) { prefix in
            Button(prefix) { onPick(prefix) }
        }
    }
}
