// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

public struct GraphBuildOptions: Hashable, Sendable {
    public var maxNodesPerLayer: Int = 6       // 6 / 12 / 30
    public init(maxNodesPerLayer: Int = 6) { self.maxNodesPerLayer = maxNodesPerLayer }
}

public enum GraphBuilder {
    /// Stub: returns an empty graph. The real rules (DESIGN §6.3) are owned by the graph agent.
    public static func build(from paths: [ObservedPath], options: GraphBuildOptions = .init()) -> ASGraph {
        ASGraph(nodes: [], edges: [], origins: [], totalPaths: paths.count, discardedPaths: paths.count,
                layerCount: 0, cleanedPaths: [])
    }
}
