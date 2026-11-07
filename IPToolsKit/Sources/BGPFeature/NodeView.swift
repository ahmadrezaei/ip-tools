// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import SwiftUI

struct NodeView: View {
    let node: GraphNode
    let name: String?

    var body: some View {
        VStack {
            if case let .asn(asn) = node.id { Text("AS\(asn)").font(.caption.bold()) }
            if let name { Text(name).font(.caption2).lineLimit(1) }
        }
        .frame(width: 112, height: 44)
    }
}
