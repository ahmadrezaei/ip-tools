// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import NetCore
import SharedUI
import SwiftUI

struct HopRow: View {
    let hop: TraceHop

    var body: some View {
        HStack {
            Text("\(hop.ttl)").monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading) {
                Text(hop.hostname ?? hop.addresses.first?.description ?? "*")
                if let asn = hop.asn { Text("AS\(asn.asn) \(asn.name ?? "")").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let rtt = hop.probes.compactMap(\.rtt).min() {
                Text(Format.rtt(rtt)).monospacedDigit().foregroundStyle(RTTColor.color(for: rtt))
            }
        }
    }
}
