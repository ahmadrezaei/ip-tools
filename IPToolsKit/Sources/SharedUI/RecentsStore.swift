// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import NetCore
import Observation

public struct RecentTarget: Codable, Hashable, Identifiable, Sendable {
    public var id: String { key }
    public let key: String          // TargetParser.normalized
    public let display: String
    public let lastTool: Tool
    public let date: Date

    public init(key: String, display: String, lastTool: Tool, date: Date) {
        self.key = key
        self.display = display
        self.lastTool = lastTool
        self.date = date
    }
}

@MainActor @Observable public final class RecentsStore {
    public private(set) var items: [RecentTarget]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let limit: Int
    private static let storageKey = "recents.v1"

    public init(defaults: UserDefaults = .standard, limit: Int = 20) {
        self.defaults = defaults
        self.limit = limit
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([RecentTarget].self, from: data) {
            items = Array(decoded.prefix(limit))
        } else {
            items = []
        }
    }

    public func record(_ target: String, tool: Tool) {
        let display = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !display.isEmpty else { return }
        let key = TargetParser.normalized(display)
        items.removeAll { $0.key == key }
        items.insert(RecentTarget(key: key, display: display, lastTool: tool, date: Date()), at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        save()
    }

    public func remove(_ item: RecentTarget) {
        items.removeAll { $0.key == item.key }
        save()
    }

    public func clear() {
        items = []
        save()
    }

    public func suggestions(matching text: String, limit: Int = 5) -> [RecentTarget] {
        let needle = TargetParser.normalized(text)
        let matches = needle.isEmpty ? items : items.filter { $0.key.contains(needle) && $0.key != needle }
        return Array(matches.prefix(limit))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: Self.storageKey) }
    }
}
