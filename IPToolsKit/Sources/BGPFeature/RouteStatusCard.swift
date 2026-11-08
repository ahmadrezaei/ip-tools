// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

/// Icon + title + subtitle above the chain, with Stop while measuring.
struct RouteStatusCard: View {
    let route: YourRouteModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.statusTitle).font(.headline).fixedSize(horizontal: false, vertical: true)
                if let subtitle = route.statusSubtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if route.isMeasuring {
                Button("Stop") { route.stop() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
        .onChange(of: route.announcement) { _, new in
            if let new { AccessibilityNotification.Announcement(new.text).post() }
        }
    }

    @ViewBuilder private var icon: some View {
        switch route.phase {
        case .locating, .measuring:
            ProgressView()
        case .partial, .stopped, .failed:
            Image(systemName: "exclamationmark.triangle").font(.title3).foregroundStyle(.orange)
        case .done where route.isBGPSourced:
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.title3).foregroundStyle(Color.accentColor)
        default:
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
        }
    }
}
