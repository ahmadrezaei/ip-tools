// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation

public struct ICMPPacket: Sendable {
    public let message: ICMPMessage
    public let from: IPAddress
    public let ttl: Int?
    /// Raw datagram length as received (on IPv4 this includes the IP header).
    public let byteCount: Int
    public let receivedAt: ContinuousClock.Instant

    public init(message: ICMPMessage, from: IPAddress, ttl: Int?, byteCount: Int, receivedAt: ContinuousClock.Instant) {
        self.message = message
        self.from = from
        self.ttl = ttl
        self.byteCount = byteCount
        self.receivedAt = receivedAt
    }
}

/// Unprivileged ICMP datagram socket (`SOCK_DGRAM` + `IPPROTO_ICMP[V6]`), nonblocking and
/// driven by a `DispatchSourceRead` on a private serial queue.
public final class ICMPSocket: @unchecked Sendable {
    private let family: IPAddress.Family
    private let queue = DispatchQueue(label: "com.ahmadrezaei.iptools.icmp-socket")
    private let fd: Int32
    private var source: (any DispatchSourceRead)?
    private var closed = false
    private var currentHopLimit: Int?
    private var buffer = [UInt8](repeating: 0, count: 4096)
    private let stream: AsyncStream<ICMPPacket>
    private let continuation: AsyncStream<ICMPPacket>.Continuation

    public init(family: IPAddress.Family) throws {
        let fd = socket(family == .v4 ? AF_INET : AF_INET6,
                        SOCK_DGRAM,
                        family == .v4 ? IPPROTO_ICMP : IPPROTO_ICMPV6)
        guard fd >= 0 else { throw NetError.socketUnavailable(errno: errno) }
        let flags = fcntl(fd, F_GETFL)
        if flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 {
            let e = errno
            Darwin.close(fd)
            throw NetError.socketUnavailable(errno: e)
        }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var rcvbuf: Int32 = 256 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, socklen_t(MemoryLayout<Int32>.size))

        self.family = family
        self.fd = fd
        (stream, continuation) = AsyncStream.makeStream(of: ICMPPacket.self, bufferingPolicy: .unbounded)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
    }

    deinit { close() }

    /// Sends one datagram. On the same serial queue the hop limit is set immediately before `sendto`,
    /// so a probe can never go out with the wrong TTL.
    public func send(_ bytes: [UInt8], to: IPAddress, hopLimit: Int? = nil) throws -> ContinuousClock.Instant {
        try queue.sync {
            guard !closed else { throw NetError.sendFailed(errno: EBADF) }
            if let hop = hopLimit ?? (currentHopLimit == nil ? nil : 64), hop != currentHopLimit {
                var value = Int32(hop)
                let rc: Int32
                if family == .v4 {
                    rc = setsockopt(fd, IPPROTO_IP, IP_TTL, &value, socklen_t(MemoryLayout<Int32>.size))
                } else {
                    rc = setsockopt(fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &value, socklen_t(MemoryLayout<Int32>.size))
                }
                if rc != 0 { throw NetError.sendFailed(errno: errno) }
                currentHopLimit = hop
            }
            var storage = sockaddr_storage()
            let length = Self.fill(&storage, with: to)
            let start = ContinuousClock.now
            let sent = withUnsafePointer(to: &storage) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    bytes.withUnsafeBytes { raw in
                        sendto(fd, raw.baseAddress, raw.count, 0, sa, length)
                    }
                }
            }
            if sent < 0 {
                let e = errno
                switch e {
                case ENETUNREACH, EHOSTUNREACH, ENETDOWN, EADDRNOTAVAIL:
                    if to.scopeLabel != nil && to.scopeLabel != "Loopback" && e == EHOSTUNREACH { throw NetError.localNetworkDenied }
                    throw NetError.networkUnreachable(family: family)
                case EPERM, EACCES:
                    throw NetError.localNetworkDenied
                default:
                    throw NetError.sendFailed(errno: e)
                }
            }
            return start
        }
    }

    /// Single consumer. Finishes when the socket is closed.
    public var packets: AsyncStream<ICMPPacket> { stream }

    public func close() {
        queue.sync {
            guard !closed else { return }
            closed = true
            source?.cancel()   // the cancel handler closes the descriptor
            source = nil
        }
        continuation.finish()
    }

    // MARK: - Private

    private func drain() {
        while !closed {
            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let n = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &storage) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(fd, raw.baseAddress, raw.count, 0, sa, &length)
                    }
                }
            }
            let now = ContinuousClock.now
            if n < 0 { return }   // EAGAIN (drained) or a transient error
            guard let from = Self.address(from: storage),
                  let parsed = ICMPCodec.parse(Array(buffer[0..<n]), family: family) else { continue }
            continuation.yield(ICMPPacket(message: parsed.message, from: from, ttl: parsed.ttl,
                                          byteCount: n, receivedAt: now))
        }
    }

    private static func fill(_ storage: inout sockaddr_storage, with address: IPAddress) -> socklen_t {
        switch address.family {
        case .v4:
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            withUnsafeMutableBytes(of: &sin.sin_addr) { $0.copyBytes(from: address.bytes) }
            withUnsafeMutableBytes(of: &storage) { $0.copyBytes(from: withUnsafeBytes(of: &sin) { $0 }) }
            return socklen_t(MemoryLayout<sockaddr_in>.size)
        case .v6:
            var sin6 = sockaddr_in6()
            sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            sin6.sin6_family = sa_family_t(AF_INET6)
            withUnsafeMutableBytes(of: &sin6.sin6_addr) { $0.copyBytes(from: address.bytes) }
            withUnsafeMutableBytes(of: &storage) { $0.copyBytes(from: withUnsafeBytes(of: &sin6) { $0 }) }
            return socklen_t(MemoryLayout<sockaddr_in6>.size)
        }
    }

    private static func address(from storage: sockaddr_storage) -> IPAddress? {
        var storage = storage
        switch Int32(storage.ss_family) {
        case AF_INET:
            return withUnsafeBytes(of: &storage) { raw in
                let sin = raw.load(as: sockaddr_in.self)
                return IPAddress(bytes: withUnsafeBytes(of: sin.sin_addr) { Array($0) })
            }
        case AF_INET6:
            return withUnsafeBytes(of: &storage) { raw in
                let sin6 = raw.load(as: sockaddr_in6.self)
                return IPAddress(bytes: withUnsafeBytes(of: sin6.sin6_addr) { Array($0) })
            }
        default:
            return nil
        }
    }
}
