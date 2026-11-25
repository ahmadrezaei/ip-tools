// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

/// iPad (regular width): one column with your address tiles on top, and the raw records in an inspector.
struct WhoisPadLayout: View {
    @Bindable var model: WhoisModel

    /// Detail columns at least this wide open with the inspector shown (a 1100 pt window leaves about 800 pt
    /// next to the sidebar).
    static let inspectorWidth: CGFloat = 760

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    column
                }
                .padding(.vertical, 8)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .refreshable { if model.isMyIPMode { await model.refreshMyIPAndWait() } }
            .background(Color.screenBackground)
            .onAppear { decideInspector(width: proxy.size.width) }
            .onChange(of: proxy.size.width) { _, width in decideInspector(width: width) }
        }
        .inspector(isPresented: $model.inspectorShown) {
            inspector.inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
    }

    /// The default is applied once; after that the user's choice stands for the session.
    private func decideInspector(width: CGFloat) {
        guard !model.inspectorDecided else { return }
        model.inspectorDecided = true
        model.inspectorShown = width >= Self.inspectorWidth
    }

    @ViewBuilder private var column: some View {
        if model.isMyIPMode {
            WhoisMyIPContent(model: model, wide: true)
        } else {
            tilesAboveResult
        }
    }

    /// Your address tiles stay on top in result mode too.
    @ViewBuilder private var tilesAboveResult: some View {
        if let snapshot = model.myIP, snapshot.foundAny {
            MyIPCard(model: model, snapshot: snapshot, tiles: true)
        }
        WhoisSubjectContent(model: model, showsRecordLinks: !model.inspectorShown)
    }

    @ViewBuilder private var inspector: some View {
        if let result = model.currentResult {
            RawRecordsView(result: result, onLookUp: { model.lookUp($0) }, embedded: true)
        } else {
            ContentUnavailableView("No Records Yet", systemImage: "doc.text.magnifyingglass",
                                   description: Text("Raw registry records appear here once a lookup finishes."))
        }
    }
}
