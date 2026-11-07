// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Darwin
import Testing
@testable import NetCore

@Suite struct IPAddressTests {
    @Test func parsesAndFormats() {
        #expect(IPAddress("1.1.1.1")?.description == "1.1.1.1")
        #expect(IPAddress("[2606:4700:4700::1111]")?.description == "2606:4700:4700::1111")
        #expect(IPAddress("not an ip") == nil)
    }

    @Test func checksum() {
        #expect(ICMPCodec.checksum([0x08, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01]) != 0)
    }

    @Test func keepsNumericZone() {
        let ip = IPAddress("fe80::1%1")
        #expect(ip?.scopeID == 1)
        #expect(ip?.description == "fe80::1")
        #expect(IPAddress("fe80::1")?.scopeID == 0)
        #expect(IPAddress("1.1.1.1%5")?.scopeID == 0)
    }

    @Test func resolvesZoneByInterfaceName() {
        var names = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(1, &names) != nil else { return }
        let name = String(cString: names)
        #expect(IPAddress("fe80::1%\(name)")?.scopeID == 1)
    }

    @Test func sockaddrCarriesScope() {
        let ip = IPAddress("fe80::1%7")!
        ip.withSockaddr { sa, len in
            #expect(len == socklen_t(MemoryLayout<sockaddr_in6>.size))
            sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                #expect($0.pointee.sin6_scope_id == 7)
                #expect($0.pointee.sin6_family == sa_family_t(AF_INET6))
            }
        }
        IPAddress("10.0.0.1")!.withSockaddr { sa, len in
            #expect(len == socklen_t(MemoryLayout<sockaddr_in>.size))
            sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                #expect($0.pointee.sin_family == sa_family_t(AF_INET))
            }
        }
    }

    @Test func sendErrorMapping() {
        let linkLocal = IPAddress("fe80::1%1")!, priv = IPAddress("192.168.1.1")!, pub = IPAddress("8.8.8.8")!
        #expect(ICMPSocket.mapSendError(EHOSTUNREACH, target: linkLocal) == .localNetworkDenied)
        #expect(ICMPSocket.mapSendError(EHOSTUNREACH, target: priv) == .localNetworkDenied)
        #expect(ICMPSocket.mapSendError(EHOSTUNREACH, target: pub) == .sendFailed(errno: EHOSTUNREACH))
        #expect(ICMPSocket.mapSendError(ENETUNREACH, target: priv) == .networkUnreachable(family: .v4))
        #expect(ICMPSocket.mapSendError(EPERM, target: pub) == .sendFailed(errno: EPERM))
    }

    @Test func socketDeinitDoesNotHang() {
        for _ in 0..<20 { _ = try? ICMPSocket(family: .v4) }
    }
}
