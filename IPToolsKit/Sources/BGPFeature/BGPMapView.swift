// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import BGPGraph
import NetCore
import SharedUI
import SwiftUI

public struct BGPMapView: View {
    @Bindable private var model: BGPMapModel

    @Environment(\.isOnline) private var isOnline
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showDetails = false
    @State private var appliedDefaultMode = false
    @State private var showLegend = false

    public init(model: BGPMapModel) {
        self.model = model
    }

    private var isRegular: Bool { sizeClass == .regular }
    private var isLoading: Bool { if case .loading = model.phase { true } else { false } }
    private var parsedOK: Bool { BGPMapModel.classify(model.targetText) != nil }

    public var body: some View {
        VStack(spacing: 0) {
            TargetInputBar(
                text: $model.targetText, placeholder: "IP, prefix, ASN or hostname",
                systemImage: "point.3.connected.trianglepath.dotted",
                mode: .bgp, primaryTitle: "Map", isRunning: isLoading,
                isEnabled: parsedOK && isOnline, recents: model.recentsStore,
                onSubmit: { model.map() }, onStop: { model.cancel() })
            content
        }
        .navigationTitle("BGP Map")
        .inlineNavigationTitle()
        .toolbar { toolbarContent }
        .sheet(isPresented: pickerBinding) { picker }
        .sheet(isPresented: detailsSheetBinding) { detailsSheet }
        .inspector(isPresented: inspectorBinding) {
            detailContent
                .inspectorColumnWidth(min: 280, ideal: 340, max: 420)
        }
        .sheet(isPresented: $showLegend) { GraphLegendSheet(showsYou: model.myASN != nil) }
        .task { model.consumeRouterRequest() }
        .onChange(of: model.router.selectedTool) { _, tool in if tool == .bgp { model.consumeRouterRequest() } }
        .onChange(of: model.router.requestTick) { model.consumeRouterRequest() }
        .onChange(of: model.detailsToken) { _, _ in if !isRegular { showDetails = true } }
        .onChange(of: model.selection) { _, new in if new == nil, model.route.selection == nil { showDetails = false } }
        .onChange(of: model.route.selection) { _, new in
            if new == nil, model.selection == nil { showDetails = false } else if new != nil, !isRegular { showDetails = true }
        }
        .onAppear {
            if voiceOver, !appliedDefaultMode { model.displayMode = .list }
            appliedDefaultMode = true
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .pickingPrefix:
            emptyState
        case .loading:
            VStack(spacing: 12) {
                PrefixHeaderCard(result: nil, isLoading: true)
                ProgressView("Fetching routes from RIPEstat…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 8)
        case .failed:
            if let failure = model.failure {
                ErrorStateView(failure) { model.map() }
            } else {
                ContentUnavailableView("Something went wrong", systemImage: "exclamationmark.triangle")
            }
        case .loaded:
            loaded
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label("Map BGP Paths", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("See how networks around the world reach an IP address, prefix or AS — live routes from RIPE RIS collectors.")
                }
                ExampleChips(["1.1.1.1", "8.8.8.0/24", "AS13335"]) { example in
                    model.targetText = example
                    if isOnline { model.map() }
                }
                let recents = Array(model.recentsStore.items.prefix(5))
                if !recents.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Recent").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal).padding(.bottom, 4)
                        ForEach(recents) { item in
                            Button { model.targetText = item.display } label: {
                                Label(item.display, systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8).padding(.horizontal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 480, alignment: .leading)
                }
            }
            .padding(.top, 8)
        }
    }

    private var loaded: some View {
        VStack(spacing: 8) {
            PrefixHeaderCard(result: model.result, hostLine: model.hostLine) { asn in
                model.requestDetails(for: .asn(asn))
            }
            Picker("View", selection: $model.view) {
                Text("Your route").tag(BGPView.yourRoute)
                Text("All routes").tag(BGPView.allRoutes).accessibilityLabel("All routes worldwide")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            switch model.view {
            case .yourRoute:
                YourRouteView(model: model)
            case .allRoutes:
                allRoutes
            }
        }
        .padding(.top, 8)
    }

    private var allRoutes: some View {
        ViewThatFits(in: .vertical) {
            allRoutesContent(scrolling: false)
            ScrollView {
                allRoutesContent(scrolling: true)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// `scrolling`: the content is taller than the screen, so the canvas keeps its minimum height and the page scrolls.
    private func allRoutesContent(scrolling: Bool) -> some View {
        let canvasMin: CGFloat = isRegular ? 360 : 300
        return VStack(spacing: 8) {
            if let result = model.result, let summary = model.summary {
                AllRoutesSummaryCard(result: result, summary: summary, myNetwork: model.myNetwork, mode: $model.displayMode,
                                     showUpdated: isRegular, compact: !isRegular) { model.view = .yourRoute }
            }
            if model.displayMode == .graph, typeSize >= .accessibility1 {
                Label("Larger text works best in List view", systemImage: "list.bullet")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ZStack(alignment: .bottom) {
                switch model.displayMode {
                case .graph:
                    VStack(spacing: 6) {
                        GraphCanvasView(model: model)
                            .frame(minHeight: canvasMin)
                            .layoutPriority(1)
                        GraphLegend(showsYou: model.myASN != nil, onFit: { model.requestFit() }) { showLegend = true }
                    }
                    .padding(.horizontal).padding(.bottom, 8)
                case .list:
                    BGPListView(model: model)
                        .frame(minHeight: scrolling ? 360 : 0)
                }
                if !isRegular, let selection = model.selection, let result = model.result,
                   let summary = model.stats?.summary(for: selection, graph: result.graph) {
                    SelectionCard(summary: summary, holder: summary.asn.flatMap { result.holder(of: $0) }) {
                        showDetails = true
                    }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.selection)
        }
    }

    /// What the sheet / inspector shows: the selected chain node in Your route, else the selected graph node.
    @ViewBuilder private var detailContent: some View {
        if model.view == .yourRoute, let id = model.route.selection,
           let node = model.route.chain?.nodes.first(where: { $0.id == id }) {
            ASDetailView(model: model, routeNode: node)
        } else if let selection = model.selection {
            ASDetailView(model: model, id: selection)
        }
    }

    private var hasDetailSelection: Bool {
        (model.view == .yourRoute && model.route.selection != nil) || model.selection != nil
    }

    // MARK: Sheets

    private var pickerBinding: Binding<Bool> {
        Binding(
            get: { if case .pickingPrefix = model.phase { true } else { false } },
            set: { if !$0 { model.dismissPicker() } })
    }

    @ViewBuilder private var picker: some View {
        if case let .pickingPrefix(asn, holder, prefixes) = model.phase {
            PrefixPickerView(asn: asn, holder: holder, prefixes: prefixes,
                             onPick: { model.choosePrefix($0) }, onCancel: { model.dismissPicker() })
        }
    }

    private var detailsSheetBinding: Binding<Bool> {
        Binding(get: { showDetails && !isRegular && hasDetailSelection },
                set: { showDetails = $0; if !$0 { model.route.selection = nil } })
    }

    @ViewBuilder private var detailsSheet: some View {
        detailContent
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(get: { isRegular && hasDetailSelection && model.phase == .loaded },
                set: { if !$0 { model.selection = nil; model.route.selection = nil } })
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Show per column", selection: $model.maxNodesPerLayer) {
                    Text("Top 6").tag(6)
                    Text("Top 12").tag(12)
                    Text("Top 30").tag(30)
                    if ![6, 12, 30].contains(model.maxNodesPerLayer) {
                        Text("Top \(model.maxNodesPerLayer)").tag(model.maxNodesPerLayer)
                    }
                }
            } label: {
                if isRegular {
                    Label("Top \(model.maxNodesPerLayer)", systemImage: "chevron.down")
                } else {
                    Label("Show per column", systemImage: "ellipsis.circle")
                }
            }
            .disabled(model.result == nil || model.view == .yourRoute)
            Menu {
                ShareLink(item: model.exportText) { Label("Share as text", systemImage: "text.alignleft") }
                if model.view == .allRoutes, let result = model.result, let layout = model.layout, !layout.frames.isEmpty {
                    ShareLink(item: GraphImageExport(result: result, layout: layout),
                              preview: SharePreview("BGP graph for \(result.prefix)")) {
                        Label("Share as image", systemImage: "photo")
                    }
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(model.result == nil || (model.view == .yourRoute && model.route.chain == nil))
        }
    }
}
