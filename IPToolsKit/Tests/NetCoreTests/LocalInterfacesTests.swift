// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Testing
@testable import NetCore

@Suite struct LocalInterfacesTests {
    @Test func classification() {
        let table: [(String, Bool, LocalAddress.Interface)] = [
            ("en0", true, .wifi),
            ("en0", false, .wifi),
            ("en1", true, .wired),
            ("en5", false, .wired),
            ("pdp_ip0", true, .cellular),
            ("pdp_ip3", false, .cellular),
            ("utun3", true, .vpn),
            ("utun3", false, .other),
            ("ipsec0", true, .vpn),
            ("ipsec0", false, .other),
            ("awdl0", true, .other),
            ("bridge100", true, .other),
            ("lo0", true, .other),
            ("", true, .other),
        ]
        for (name, nonLinkLocal, expected) in table {
            #expect(LocalInterfaces.classify(name: name, hasNonLinkLocal: nonLinkLocal) == expected,
                    Comment(rawValue: "\(name) \(nonLinkLocal)"))
        }
    }

    private func entry(_ name: String, _ address: String) -> (name: String, address: IPAddress) {
        (name, IPAddress(address)!)
    }

    @Test func dropsLinkLocalAndNonGlobalV6() {
        let result = LocalInterfaces.assemble([
            entry("en0", "192.168.1.23"),
            entry("en0", "fe80::1"),
            entry("en0", "2001:db8::5"),
            entry("en0", "fd12:3456::7"),
            entry("en0", "ff02::1"),
            entry("en0", "::1"),
        ])
        #expect(result.map(\.address.description) == ["192.168.1.23", "2001:db8::5", "fd12:3456::7"])
    }

    @Test func idleTunnelsAreIgnoredAndActiveOnesAreVPN() {
        let result = LocalInterfaces.assemble([
            entry("utun0", "fe80::1"),
            entry("utun1", "fe80::2"),
            entry("utun4", "10.8.0.2"),
            entry("ipsec0", "169.254.1.1"),
        ])
        // ipsec0 only has a link-local IPv4 address (dropped), so only utun4 remains, as a VPN.
        #expect(result.map(\.name) == ["utun4"])
        #expect(result.first?.interface == .vpn)
    }

    @Test func sortOrder() {
        let result = LocalInterfaces.assemble([
            entry("utun4", "10.8.0.2"),
            entry("bridge0", "10.1.1.1"),
            entry("en0", "2001:db8::5"),
            entry("en2", "192.168.50.2"),
            entry("pdp_ip0", "100.72.13.5"),
            entry("en0", "192.168.1.23"),
        ])
        #expect(result.map(\.name) == ["en0", "en0", "pdp_ip0", "en2", "utun4", "bridge0"])
        #expect(result.map(\.interface) == [.wifi, .wifi, .cellular, .wired, .vpn, .other])
        #expect(result[0].address.family == .v4)
        #expect(result[1].address.family == .v6)
    }

    @Test func idIsNameAndAddress() {
        let address = LocalAddress(interface: .wifi, name: "en0", address: IPAddress("10.0.0.5")!)
        #expect(address.id == "en0|10.0.0.5")
    }

    @Test func currentReturnsUsableAddresses() {
        for item in LocalInterfaces.current() {
            #expect(item.address.family == .v4 || item.address.specialPurpose?.kind != .linkLocal)
            #expect(!item.name.isEmpty)
        }
    }
}
