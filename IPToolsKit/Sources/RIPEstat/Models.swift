// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct NetworkInfo: Sendable, Hashable {
    public let prefix: String?; public let originASNs: [UInt32]   // "" → nil
    public init(prefix: String?, originASNs: [UInt32]) {
        self.prefix = prefix
        self.originASNs = originASNs
    }
}

public struct WhatsMyIP: Sendable, Hashable {
    public let ip: String
    public init(ip: String) { self.ip = ip }
}

public struct ASHolder: Sendable, Hashable {
    public let asn: UInt32; public let holder: String
    public var shortName: String { ASName.short(holder) }
    public init(asn: UInt32, holder: String) {
        self.asn = asn
        self.holder = holder
    }
}

public struct PrefixOverview: Sendable, Hashable {
    public let resource: String; public let announced: Bool; public let origins: [ASHolder]
    public init(resource: String, announced: Bool, origins: [ASHolder]) {
        self.resource = resource
        self.announced = announced
        self.origins = origins
    }
}

public struct ASOverview: Sendable, Hashable {
    public let asn: UInt32; public let holder: String?; public let announced: Bool
    public init(asn: UInt32, holder: String?, announced: Bool) {
        self.asn = asn
        self.holder = holder
        self.announced = announced
    }
}

public struct RoutingStatus: Sendable, Hashable {
    public struct Visibility: Sendable, Hashable {
        public let seeing: Int; public let total: Int
        public init(seeing: Int, total: Int) {
            self.seeing = seeing
            self.total = total
        }
    }
    public let v4: Visibility?, v6: Visibility?
    public let origins: [UInt32]
    public init(v4: Visibility?, v6: Visibility?, origins: [UInt32]) {
        self.v4 = v4
        self.v6 = v6
        self.origins = origins
    }
}

public struct LookingGlass: Sendable, Hashable {
    public struct Route: Sendable, Hashable {
        public let collector: String          // "RRC01"
        public let peerIP: String
        public let prefix: String
        public let asPath: [UInt32]           // AS_SET tokens removed, order preserved (peer first, origin last)
        public let hadASSet: Bool
        public let rawASPath: String
        public let lastUpdated: Date?
        public init(collector: String, peerIP: String, prefix: String, asPath: [UInt32],
                    hadASSet: Bool, rawASPath: String, lastUpdated: Date?) {
            self.collector = collector
            self.peerIP = peerIP
            self.prefix = prefix
            self.asPath = asPath
            self.hadASSet = hadASSet
            self.rawASPath = rawASPath
            self.lastUpdated = lastUpdated
        }
    }
    public struct Collector: Sendable, Hashable {
        public let id: String; public let location: String
        public init(id: String, location: String) {
            self.id = id
            self.location = location
        }
    }
    public let collectors: [Collector]
    public let routes: [Route]
    public let latestTime: Date?
    public init(collectors: [Collector], routes: [Route], latestTime: Date?) {
        self.collectors = collectors
        self.routes = routes
        self.latestTime = latestTime
    }
}
