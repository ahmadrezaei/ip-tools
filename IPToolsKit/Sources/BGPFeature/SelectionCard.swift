// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SwiftUI

struct SelectionCard: View {
    let node: GraphNode

    var body: some View {
        Text(String(describing: node.id))
    }
}
