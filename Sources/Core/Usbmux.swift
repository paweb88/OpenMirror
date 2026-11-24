import Foundation

/// A device visible to the system `usbmuxd` daemon (the same channel Finder and Xcode use).
struct UsbmuxDevice: Equatable {
    let deviceID: Int
    let udid: String
    let connectionType: String
}

enum UsbmuxError: LocalizedError {
    case socketFailed(String)
    case protocolError(String)
    case connectRefused(Int)

    var errorDescription: String? {
        switch self {
        case .socketFailed(let reason): return "usbmuxd: \(reason)"
        case .protocolError(let reason): return "usbmuxd protocol: \(reason)"
        case .connectRefused(let code): return "iPhone refused the connection (code \(code))."
        }
    }
}

/// Encodes and decodes usbmuxd plist packets (header: length, version=1, type=8, tag; little endian).
enum UsbmuxPacket {
    static let headerSize = 16
    static let plistMessageType: UInt32 = 8

    static func encode(_ payload: [String: Any], tag: UInt32) throws -> Data {
        let body = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        var data = Data()
        for value in [UInt32(headerSize + body.count), 1, plistMessageType, tag] {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(body)
        return data
    }

    /// Total packet length declared in a 16-byte header.
    static func length(fromHeader header: Data) throws -> Int {
        guard header.count >= headerSize else { throw UsbmuxError.protocolError("short header") }
        let length = header.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        guard length >= UInt32(headerSize), length < 1_000_000 else {
            throw UsbmuxError.protocolError("invalid packet length \(length)")
        }
        return Int(length)
    }

    static func decodeBody(_ body: Data) throws -> [String: Any] {
        guard let plist = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] else {
            throw UsbmuxError.protocolError("payload is not a dictionary")
        }
        return plist
    }

    static func devices(from reply: [String: Any]) -> [UsbmuxDevice] {
        let list = reply["DeviceList"] as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard let id = entry["DeviceID"] as? Int,
                  let props = entry["Properties"] as? [String: Any],
                  let serial = props["SerialNumber"] as? String else { return nil }
            return UsbmuxDevice(deviceID: id, udid: serial,
                                connectionType: props["ConnectionType"] as? String ?? "USB")
        }
    }

    /// usbmuxd expects the TCP port in network byte order inside a little-endian integer.
    static func portNumber(_ port: UInt16) -> Int { Int(port.bigEndian) }
}

/// Minimal blocking client for `/var/run/usbmuxd`. Each instance owns one socket.
final class UsbmuxClient {
    static let socketPath = "/var/run/usbmuxd"
    private(set) var fd: Int32 = -1

    init() throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UsbmuxError.socketFailed("cannot create socket") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            Self.socketPath.withCString { strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), $0, 103) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close()
            throw UsbmuxError.socketFailed("cannot connect to \(Self.socketPath)")
        }
    }

    deinit { close() }

    func close() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }

    /// Hands over the raw socket (now a tunnel to the device); the client no longer owns it.
    func detachSocket() -> Int32 {
        let handle = fd
        fd = -1
        return handle
    }

    func listDevices() throws -> [UsbmuxDevice] {
        let reply = try request(["MessageType": "ListDevices"])
        return UsbmuxPacket.devices(from: reply)
    }

    /// Turns this socket into a raw TCP tunnel to `port` on the device.
    func connect(deviceID: Int, port: UInt16) throws {
        let reply = try request(["MessageType": "Connect", "DeviceID": deviceID,
                                 "PortNumber": UsbmuxPacket.portNumber(port)])
        let code = reply["Number"] as? Int ?? -1
        guard code == 0 else { throw UsbmuxError.connectRefused(code) }
    }

    private func request(_ message: [String: Any]) throws -> [String: Any] {
        var payload = message
        payload["ClientVersionString"] = "OpenMirror"
        payload["ProgName"] = "OpenMirror"
        try writeAll(UsbmuxPacket.encode(payload, tag: 1))
        let header = try readExactly(UsbmuxPacket.headerSize)
        let length = try UsbmuxPacket.length(fromHeader: header)
        return try UsbmuxPacket.decodeBody(readExactly(length - UsbmuxPacket.headerSize))
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { throw UsbmuxError.socketFailed("write failed") }
                offset += written
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let received = read(fd, buffer.baseAddress! + offset, count - offset)
                guard received > 0 else { throw UsbmuxError.socketFailed("connection closed") }
                offset += received
            }
        }
        return data
    }
}
