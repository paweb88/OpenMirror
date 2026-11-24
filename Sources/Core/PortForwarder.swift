import Foundation
import Network

/// Listens on 127.0.0.1:`localPort` and tunnels each connection over USB to `remotePort` on the device.
final class PortForwarder {
    private let udid: String
    private let remotePort: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "openmirror.forwarder")

    init(udid: String, localPort: UInt16, remotePort: UInt16) throws {
        self.udid = udid
        self.remotePort = remotePort
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: localPort)!)
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in self?.bridge(connection) }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    private func bridge(_ connection: NWConnection) {
        let deviceSocket: Int32
        do {
            // usbmuxd assigns a new DeviceID whenever the phone re-attaches, so resolve it each time
            let devices = try UsbmuxClient().listDevices().filter { $0.udid == udid }
            guard let device = devices.first(where: { $0.connectionType == "USB" }) ?? devices.first else {
                throw UsbmuxError.protocolError("iPhone \(udid) is not connected")
            }
            let client = try UsbmuxClient()
            try client.connect(deviceID: device.deviceID, port: remotePort)
            deviceSocket = client.detachSocket()
        } catch {
            NSLog("OpenMirror: tunnel to port \(remotePort) failed: \(error.localizedDescription)")
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        pumpToDevice(connection, deviceSocket)
        pumpFromDevice(connection, deviceSocket)
    }

    private func pumpToDevice(_ connection: NWConnection, _ socket: Int32) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                let ok = data.withUnsafeBytes { buffer -> Bool in
                    var offset = 0
                    while offset < buffer.count {
                        let written = write(socket, buffer.baseAddress! + offset, buffer.count - offset)
                        if written <= 0 { return false }
                        offset += written
                    }
                    return true
                }
                if !ok { connection.cancel(); return }
            }
            if isComplete || error != nil {
                shutdown(socket, SHUT_WR)
                return
            }
            self?.pumpToDevice(connection, socket)
        }
    }

    private func pumpFromDevice(_ connection: NWConnection, _ socket: Int32) {
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = read(socket, &buffer, buffer.count)
                if count <= 0 { break }
                let semaphore = DispatchSemaphore(value: 0)
                connection.send(content: Data(buffer[0..<count]), completion: .contentProcessed { _ in semaphore.signal() })
                semaphore.wait()
            }
            Darwin.close(socket)
            connection.cancel()
        }
    }
}
