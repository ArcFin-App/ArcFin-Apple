// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct DiscoveredServer: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let address: String

    public init(id: String, name: String, address: String) {
        self.id = id
        self.name = name
        self.address = address
    }
}

private struct DiscoveryResponse: Decodable {
    let id: String
    let name: String
    let address: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case address = "Address"
    }
}

public enum ServerDiscovery {

    /// Sends a UDP broadcast to 255.255.255.255:7359 ("Who is JellyfinServer?")
    /// and collects JSON responses for `timeout` seconds.
    public static func discover(timeout: TimeInterval = 3.0) async -> [DiscoveredServer] {
        await Task.detached(priority: .userInitiated) {
            udpDiscover(timeout: timeout)
        }.value
    }

    private static func udpDiscover(timeout: TimeInterval) -> [DiscoveredServer] {
        var discovered: [DiscoveredServer] = []

        let sockfd = socket(AF_INET, SOCK_DGRAM, 0)
        guard sockfd >= 0 else { return discovered }
        defer { close(sockfd) }

        var broadcast: Int32 = 1
        setsockopt(sockfd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval()
        tv.tv_sec = Int(timeout)
        tv.tv_usec = 0
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let msg = "Who is JellyfinServer?"
        let msgBytes = Array(msg.utf8)
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(7359).bigEndian
        dest.sin_addr.s_addr = INADDR_BROADCAST
        withUnsafePointer(to: &dest) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                _ = sendto(sockfd, msgBytes, msgBytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(sockfd, &buffer, buffer.count, 0)
            guard n > 0 else { break }
            let data = Data(buffer[0..<Int(n)])
            if let resp = try? JSONDecoder().decode(DiscoveryResponse.self, from: data) {
                let server = DiscoveredServer(id: resp.id, name: resp.name, address: resp.address)
                if !discovered.contains(server) { discovered.append(server) }
            }
        }
        return discovered
    }
}
