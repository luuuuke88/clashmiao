import NetworkExtension
import XCTest
@testable import Runner

/// TunSpec（内核拍平的 JSON）→ NE 设置的逐字段映射（spec 2026-11-03 §4.3）。
final class TunSettingsTests: XCTestCase {

    /// 与 kernel/engine/tunspec.go 的输出同形（所有数组非 null）。
    private func spec(_ overrides: [String: Any] = [:]) throws -> TunSpec {
        var base: [String: Any] = [
            "mtu": 9000, "auto_route": true, "strict_route": false, "dns_mode": "hijack",
            "dns_servers": ["172.19.0.2"],
            "inet4_address": ["172.19.0.1/30"], "inet6_address": ["fdfe:dcba:9876::1/126"],
            "inet4_route": [], "inet6_route": [], "inet4_route_exclude": [], "inet6_route_exclude": [],
            "inet4_route_range": [], "inet6_route_range": [], "include_package": [], "exclude_package": [],
            "http_proxy": ["enabled": false, "server": "", "port": 0, "bypass": [], "match": []],
        ]
        overrides.forEach { base[$0.key] = $0.value }
        let data = try JSONSerialization.data(withJSONObject: base)
        return try JSONDecoder().decode(TunSpec.self, from: data)
    }

    func testAutoRouteDefaultsToFullTunnelWithDNSInside() throws {
        let s = try TunSettingsBuilder.settings(from: spec())
        XCTAssertEqual(s.mtu, 9000)
        XCTAssertEqual(s.dnsSettings?.servers, ["172.19.0.2"])
        XCTAssertEqual(s.dnsSettings?.matchDomains, [""], "全部查询都要走隧道里的 DNS")
        let v4 = try XCTUnwrap(s.ipv4Settings)
        XCTAssertEqual(v4.addresses, ["172.19.0.1"])
        XCTAssertEqual(v4.subnetMasks, ["255.255.255.252"])
        let v4Routes = (v4.includedRoutes ?? []).map { "\($0.destinationAddress)/\($0.destinationSubnetMask)" }
        XCTAssertEqual(v4Routes, ["0.0.0.0/0.0.0.0", "172.19.0.1/255.255.255.252"])
        let v6 = try XCTUnwrap(s.ipv6Settings)
        XCTAssertEqual(v6.addresses, ["fdfe:dcba:9876::1"])
        XCTAssertEqual(v6.networkPrefixLengths, [126])
        XCTAssertEqual(v6.includedRoutes?.first?.destinationAddress, "::")
        XCTAssertNil(s.proxySettings)
    }

    func testMissingDNSServerIsRejected() throws {
        XCTAssertThrowsError(try TunSettingsBuilder.settings(from: spec(["dns_servers": []]))) { error in
            guard case TunSpecError.noDNSServer = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testIPv4OnlyLeavesIPv6Unset() throws {
        let s = try TunSettingsBuilder.settings(from: spec(["inet6_address": []]))
        XCTAssertNotNil(s.ipv4Settings)
        XCTAssertNil(s.ipv6Settings, "没有 v6 地址就不写空的 v6 设置")
    }

    func testExplicitAndExcludedRoutes() throws {
        let s = try TunSettingsBuilder.settings(from: spec([
            "inet4_route": ["10.0.0.0/8"], "inet4_route_exclude": ["192.168.0.0/16"],
            "inet6_route": ["2000::/3"], "inet6_route_exclude": ["fc00::/7"],
        ]))
        let v4 = try XCTUnwrap(s.ipv4Settings)
        XCTAssertEqual(v4.includedRoutes?.first?.destinationAddress, "10.0.0.0")
        XCTAssertEqual(v4.includedRoutes?.first?.destinationSubnetMask, "255.0.0.0")
        XCTAssertEqual(v4.excludedRoutes?.map(\.destinationAddress), ["192.168.0.0"])
        XCTAssertEqual(v4.excludedRoutes?.map(\.destinationSubnetMask), ["255.255.0.0"])
        let v6 = try XCTUnwrap(s.ipv6Settings)
        XCTAssertEqual(v6.includedRoutes?.first?.destinationAddress, "2000::")
        XCTAssertEqual(v6.includedRoutes?.first?.destinationNetworkPrefixLength, 3)
        XCTAssertEqual(v6.excludedRoutes?.map(\.destinationAddress), ["fc00::"])
    }

    func testHTTPProxyMapsBypassAndMatch() throws {
        let s = try TunSettingsBuilder.settings(from: spec([
            "http_proxy": ["enabled": true, "server": "127.0.0.1", "port": 2080,
                           "bypass": ["localhost"], "match": ["example.com"]],
        ]))
        let p = try XCTUnwrap(s.proxySettings)
        XCTAssertEqual(p.httpServer?.address, "127.0.0.1")
        XCTAssertEqual(p.httpServer?.port, 2080)
        XCTAssertEqual(p.httpsServer?.port, 2080)
        XCTAssertTrue(p.httpEnabled)
        XCTAssertTrue(p.httpsEnabled)
        XCTAssertEqual(p.exceptionList, ["localhost"])
        XCTAssertEqual(p.matchDomains, ["example.com"])
    }

    func testNoAutoRouteOnlyAppliesProxy() throws {
        let s = try TunSettingsBuilder.settings(from: spec([
            "auto_route": false, "dns_servers": [],
            "http_proxy": ["enabled": true, "server": "127.0.0.1", "port": 2080, "bypass": [], "match": []],
        ]))
        XCTAssertNil(s.ipv4Settings)
        XCTAssertNil(s.dnsSettings)
        XCTAssertNotNil(s.proxySettings)
    }

    func testAndroidOnlyFieldsAreReportedNotApplied() throws {
        let ignored = TunSettingsBuilder.ignoredFields(try spec([
            "include_package": ["com.example"], "inet4_route_range": ["0.0.0.0/1"], "strict_route": true,
        ]))
        XCTAssertEqual(ignored, ["route_range", "include_package", "strict_route"])
        XCTAssertEqual(TunSettingsBuilder.ignoredFields(try spec()), [])
    }

    func testPrefixParsing() throws {
        XCTAssertEqual(TunSettingsBuilder.mask4(0), "0.0.0.0")
        XCTAssertEqual(TunSettingsBuilder.mask4(24), "255.255.255.0")
        XCTAssertEqual(TunSettingsBuilder.mask4(32), "255.255.255.255")
        XCTAssertThrowsError(try TunSettingsBuilder.split("10.0.0.1"))
        XCTAssertThrowsError(try TunSettingsBuilder.split("10.0.0.1/x"))
        XCTAssertThrowsError(try TunSettingsBuilder.settings(from: spec(["inet4_address": ["bogus"]])))
    }

    func testMissingKeysFallBackToDefaults() throws {
        let s = try JSONDecoder().decode(TunSpec.self, from: Data(#"{"mtu":1500}"#.utf8))
        XCTAssertFalse(s.autoRoute)
        XCTAssertEqual(s.dnsServers, [])
        XCTAssertFalse(s.httpProxy.enabled)
    }
}
