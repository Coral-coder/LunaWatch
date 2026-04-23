import Foundation
import CoreBluetooth

// Real GATT UUIDs confirmed via nRF Connect scan (device advertises as "R33K0").
enum LunaGATT {
    // Primary service (advertised)
    static let serviceUUID    = CBUUID(string: "81A50000-9EBD-0436-3358-BB370C7DA4C5")
    // Commands → watch (write without response)
    static let writeCharUUID  = CBUUID(string: "81A50002-9EBD-0436-3358-BB370C7DA4C5")
    // Responses ← watch (indicate)
    static let indicateCharUUID = CBUUID(string: "81A50001-9EBD-0436-3358-BB370C7DA4C5")
    // Secondary write channel (purpose TBD)
    static let write2CharUUID = CBUUID(string: "81A50003-9EBD-0436-3358-BB370C7DA4C5")

    // Secondary service (streaming / data — purpose TBD)
    static let service2UUID   = CBUUID(string: "9E3B0000-D7AB-ADF3-F683-BAA2A0E81612")
    static let notifyCharUUID = CBUUID(string: "9E3B0002-D7AB-ADF3-F683-BAA2A0E81612")
    static let write3CharUUID = CBUUID(string: "9E3B0001-D7AB-ADF3-F683-BAA2A0E81612") // Write (with response)
}

enum BLEState: String {
    case idle         = "Idle"
    case scanning     = "Scanning…"
    case connecting   = "Connecting…"
    case connected    = "Connected"
    case disconnected = "Disconnected"
}

enum BLELogDirection { case rx, tx, info }

struct BLELogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let direction: BLELogDirection
    let charUUID: CBUUID?
    let data: Data?
    let message: String

    var hexString: String {
        data?.map { String(format: "%02X", $0) }.joined(separator: " ") ?? ""
    }
    var asciiString: String {
        guard let d = data else { return "" }
        return String(d.map { ($0 >= 32 && $0 < 127) ? Character(UnicodeScalar($0)) : "." })
    }
    var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f.string(from: timestamp)
    }
    var shortUUID: String { charUUID?.uuidString.prefix(8).description ?? "" }
}

struct DiscoveredCharacteristic: Identifiable {
    let id: CBUUID
    let characteristic: CBCharacteristic
    var isSubscribed: Bool = false
    var lastValue: Data?

    var propertySummary: String {
        let p = characteristic.properties
        var tags: [String] = []
        if p.contains(.read)                 { tags.append("R") }
        if p.contains(.write)                { tags.append("W") }
        if p.contains(.writeWithoutResponse) { tags.append("W!") }
        if p.contains(.notify)               { tags.append("N") }
        if p.contains(.indicate)             { tags.append("I") }
        return tags.joined(separator: "/")
    }

    var canWrite: Bool {
        characteristic.properties.contains(.write) ||
        characteristic.properties.contains(.writeWithoutResponse)
    }
    var canSubscribe: Bool {
        characteristic.properties.contains(.notify) ||
        characteristic.properties.contains(.indicate)
    }
    var canRead: Bool { characteristic.properties.contains(.read) }
}

struct DiscoveredService: Identifiable {
    let id: CBUUID
    let service: CBService
    var characteristics: [DiscoveredCharacteristic] = []

    var displayName: String {
        let known: [String: String] = [
            "1800": "Generic Access",
            "1801": "Generic Attribute",
            "1804": "Tx Power",
            "180A": "Device Information",
            "81A50000": "Luna Primary",
            "9E3B0000": "Luna Secondary",
        ]
        let short = id.uuidString.prefix(8).uppercased()
        return known[short] ?? known[id.uuidString.prefix(4).uppercased()] ?? id.uuidString
    }
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    @Published var state: BLEState = .idle
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var isConnected = false
    @Published var rssi: Int = 0
    @Published var lastReceivedHex = ""
    @Published var showAllDevices = false

    @Published var services: [DiscoveredService] = []
    @Published var bleLog: [BLELogEntry] = []
    @Published var lastLunaMessage: LunaMessage?

    private var central: CBCentralManager!
    private let unframer = LunaUnframer()
    private static let logLimit = 400

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scanning

    func startScanning() {
        guard central.state == .poweredOn else { return }
        discoveredDevices = []
        state = .scanning
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if self?.state == .scanning { self?.stopScanning() }
        }
        log(.info, nil, nil, "Scan started (showAll=\(showAllDevices))")
    }

    func stopScanning() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ peripheral: CBPeripheral) {
        stopScanning()
        state = .connecting
        central.connect(peripheral, options: nil)
        log(.info, nil, nil, "Connecting → \(peripheral.name ?? peripheral.identifier.uuidString)")
    }

    func disconnect() {
        guard let dev = connectedDevice else { return }
        central.cancelPeripheralConnection(dev)
    }

    // MARK: - Write / Read / Subscribe

    /// Send raw bytes to a specific characteristic, or the primary write char if nil.
    func send(_ data: Data, to characteristic: CBCharacteristic? = nil) {
        guard let peripheral = connectedDevice else { return }
        let target = characteristic ?? primaryWriteChar()
        guard let char = target else {
            log(.info, nil, nil, "TX failed – no writable characteristic found")
            return
        }
        let wType: CBCharacteristicWriteType = char.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: char, type: wType)
        log(.tx, char.uuid, data, "")
    }

    /// Send a high-level LunaMessage using the framing protocol on the DATA TX channel (9e3b0001).
    func sendMessage(_ message: LunaMessage) {
        guard let peripheral = connectedDevice else { return }
        guard let dataTXChar = characteristic(for: LunaGATT.write3CharUUID) else {
            log(.info, nil, nil, "DATA TX char not found — is watch connected?")
            return
        }
        let packets = LunaFramer.frame(message)
        log(.info, nil, nil, "→ LunaMsg type=\(message.type) v=\(message.version) [\(packets.count) pkt(s)]")
        for pkt in packets {
            peripheral.writeValue(pkt, for: dataTXChar, type: .withResponse)
            log(.tx, LunaGATT.write3CharUUID, pkt, "")
        }
    }

    func readValue(for characteristic: CBCharacteristic) {
        connectedDevice?.readValue(for: characteristic)
        log(.info, characteristic.uuid, nil, "Read requested")
    }

    func toggleNotify(for characteristic: CBCharacteristic) {
        guard let peripheral = connectedDevice else { return }
        let next = !characteristic.isNotifying
        peripheral.setNotifyValue(next, for: characteristic)
        log(.info, characteristic.uuid, nil, next ? "Subscribing…" : "Unsubscribing…")
    }

    func clearLog() { bleLog = [] }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log(.info, nil, nil, "BT state → \(central.state.rawValue)")
        if central.state == .poweredOn { startScanning() }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        let isLuna = name.lowercased().contains("luna") ||
                     name.lowercased().contains("vector") ||
                     name.lowercased() == "r33k0"
        guard showAllDevices || isLuna else { return }
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
            log(.info, nil, nil, "Found: \(name.isEmpty ? peripheral.identifier.uuidString : name)  RSSI=\(RSSI)")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDevice = peripheral
        isConnected = true
        state = .connected
        services = []
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        peripheral.readRSSI()
        log(.info, nil, nil, "Connected – discovering all services…")
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        log(.info, nil, nil, "Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedDevice = nil
        isConnected = false
        services = []
        state = .disconnected
        unframer.reset()
        log(.info, nil, nil, "Disconnected")
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        rssi = RSSI.intValue
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error { log(.info, nil, nil, "Service discovery error: \(e)"); return }
        let svcs = peripheral.services ?? []
        log(.info, nil, nil, "── \(svcs.count) service(s) found ──")
        services = svcs.map { DiscoveredService(id: $0.uuid, service: $0) }
        svcs.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let e = error { log(.info, nil, nil, "Char error (\(service.uuid)): \(e)"); return }
        let chars = service.characteristics ?? []
        log(.info, nil, nil, "  SVC \(service.uuid.uuidString.prefix(8)) → \(chars.count) char(s)")
        for c in chars {
            let props = propertiesLabel(c.properties)
            log(.info, c.uuid, nil, "    \(c.uuid.uuidString.prefix(8))  [\(props)]")
        }
        if let idx = services.firstIndex(where: { $0.id == service.uuid }) {
            services[idx].characteristics = chars.map { DiscoveredCharacteristic(id: $0.uuid, characteristic: $0) }
        }
        // Auto-subscribe to indicate/notify characteristics on the Luna services
        for c in chars where c.properties.contains(.indicate) || c.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: c)
            log(.info, c.uuid, nil, "    Auto-subscribed (indicate/notify)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        lastReceivedHex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        log(.rx, characteristic.uuid, data, "")
        updateLastValue(uuid: characteristic.uuid, data: data)

        // Reassemble framed DataMessages from the DATA RX channel
        if characteristic.uuid == LunaGATT.notifyCharUUID {
            if let msg = unframer.feed(data) {
                let desc = "← LunaMsg type=\(msg.type) v=\(msg.version) payload=\(msg.payload.map { String(format: "%02X", $0) }.joined(separator: " "))"
                log(.info, characteristic.uuid, nil, desc)
                DispatchQueue.main.async { self.lastLunaMessage = msg }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            log(.info, characteristic.uuid, nil, "Write error: \(e.localizedDescription)")
        } else {
            log(.info, characteristic.uuid, nil, "Write ACK ✓")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            log(.info, characteristic.uuid, nil, "Notify state error: \(e.localizedDescription)")
        } else {
            let on = characteristic.isNotifying
            log(.info, characteristic.uuid, nil, "Notify \(on ? "ON" : "OFF")")
            for si in services.indices {
                if let ci = services[si].characteristics.firstIndex(where: { $0.id == characteristic.uuid }) {
                    services[si].characteristics[ci].isSubscribed = on
                }
            }
        }
    }

    // MARK: - Helpers

    func characteristic(for uuid: CBUUID) -> CBCharacteristic? {
        services.flatMap(\.characteristics).first { $0.id == uuid }?.characteristic
    }

    private func primaryWriteChar() -> CBCharacteristic? {
        services.flatMap(\.characteristics)
            .first { $0.canWrite }?.characteristic
    }

    private func log(_ dir: BLELogDirection, _ uuid: CBUUID?, _ data: Data?, _ msg: String) {
        let entry = BLELogEntry(timestamp: Date(), direction: dir, charUUID: uuid, data: data, message: msg)
        DispatchQueue.main.async {
            self.bleLog.append(entry)
            if self.bleLog.count > Self.logLimit { self.bleLog.removeFirst() }
        }
    }

    private func updateLastValue(uuid: CBUUID, data: Data) {
        for si in services.indices {
            if let ci = services[si].characteristics.firstIndex(where: { $0.id == uuid }) {
                services[si].characteristics[ci].lastValue = data
            }
        }
    }

    private func propertiesLabel(_ p: CBCharacteristicProperties) -> String {
        var t: [String] = []
        if p.contains(.read)                 { t.append("read") }
        if p.contains(.write)                { t.append("write") }
        if p.contains(.writeWithoutResponse) { t.append("writeNoRsp") }
        if p.contains(.notify)               { t.append("notify") }
        if p.contains(.indicate)             { t.append("indicate") }
        return t.joined(separator: "|")
    }
}
