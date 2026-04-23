import Foundation

// Vector Luna BLE protocol — reverse engineered from VectorWatch Android APK v2.0.2.
//
// DATA channel (9e3b0001 TX / 9e3b0002 RX):
//   All messages are framed in 20-byte BLE packets.
//   Header byte: (transmissionId << 2) | frameStatus
//     frameStatus: 0=single, 1=first, 2=middle, 3=last
//   First packet of multi-packet frames: bytes 1-2 = numPackets (LE uint16)
//
// Wire format after unframing: [type: LE uint16][version: LE uint16][payload…]
//
// Time epoch: seconds since 2000-01-01 00:00:00 UTC (Y2K, not Unix).

// MARK: - Message Types

enum LunaMsgType: UInt16 {
    case command          = 0
    case time             = 1
    case battery          = 2
    case activity         = 4
    case activityTotals   = 5
    case btnPress         = 6
    case systemUpdate     = 8
    case systemInfo       = 9
    case alarm            = 10
    case bleSpeed         = 11
    case trulyConnected   = 12
    case goal             = 14
    case appInstall       = 15
    case watchfaceOrder   = 16
    case push             = 17
    case freshStart       = 18
    case settings         = 19
    case calendarEvents   = 20
    case uuid             = 23
    case changeComp       = 24
    case sendLogs         = 25
    case serialNumber     = 26
    case requestData      = 29
    case vftp             = 30
    case alert            = 31
    case watchfaceData    = 32
    case unknown          = 0xFFFF
}

// MARK: - LunaMessage

struct LunaMessage {
    let type: LunaMsgType
    let version: UInt16
    let payload: Data

    var serialized: Data {
        var d = Data(capacity: 4 + payload.count)
        d.appendLE(type.rawValue)
        d.appendLE(version)
        d.append(payload)
        return d
    }

    init(type: LunaMsgType, version: UInt16 = 2, payload: Data = Data()) {
        self.type = type
        self.version = version
        self.payload = payload
    }

    init?(raw: Data) {
        guard raw.count >= 4 else { return nil }
        let t = raw.leUInt16(at: 0)
        let v = raw.leUInt16(at: 2)
        self.type    = LunaMsgType(rawValue: t) ?? .unknown
        self.version = v
        self.payload = raw.count > 4 ? Data(raw[4...]) : Data()
    }
}

// MARK: - Built-in message constructors

extension LunaMessage {

    // Ask watch for system info (firmware version, hw rev, etc.)
    static func getSystemInfo() -> LunaMessage {
        var p = Data(capacity: 4)
        p.appendLE(UInt16(2))   // subcommand 2 = system info request
        p.appendLE(UInt16(2))
        return LunaMessage(type: .command, version: 2, payload: p)
    }

    // Ask watch for battery level.
    static func getBattery() -> LunaMessage {
        var p = Data(capacity: 4)
        p.appendLE(UInt16(13))  // subcommand 13 = battery request
        p.appendLE(UInt16(1))
        return LunaMessage(type: .command, version: 2, payload: p)
    }

    // Sync current time to watch.
    // vectorTime = unix seconds - 946684800 (Y2K epoch)
    static func syncTime() -> LunaMessage {
        let unix = Int32(Date().timeIntervalSince1970)
        let vectorTime = unix - 946_684_800
        let tz = TimeZone.current
        let offsetMinutes = Int16(tz.secondsFromGMT() / 60)

        var p = Data(capacity: 16)
        p.appendLE(vectorTime)          // 4 bytes: current time (Y2K secs)
        p.appendLE(offsetMinutes)       // 2 bytes: tz offset in minutes
        p.appendLE(Int32(0))            // 4 bytes: DST start (0 = no DST)
        p.appendLE(Int32(0))            // 4 bytes: DST end
        p.appendLE(Int16(0))            // 2 bytes: DST offset
        return LunaMessage(type: .time, version: 2, payload: p)
    }

    // Trigger a fresh start / reconnect handshake.
    static func freshStart() -> LunaMessage {
        return LunaMessage(type: .freshStart, version: 0)
    }

    // Request serial number.
    static func getSerialNumber() -> LunaMessage {
        return LunaMessage(type: .serialNumber, version: 0)
    }

    // Request UUID from watch.
    static func getUUID() -> LunaMessage {
        return LunaMessage(type: .uuid, version: 0)
    }
}

// MARK: - Framer

/// Splits a serialized LunaMessage into 20-byte BLE packets using the Vector framing protocol.
/// transmissionId: 0–63, increments per message.
struct LunaFramer {
    private static var lastId: UInt8 = 0

    static func frame(_ message: LunaMessage) -> [Data] {
        let raw = message.serialized
        let txId = nextId()
        return frame(raw: raw, txId: txId)
    }

    static func frame(raw: Data, txId: UInt8) -> [Data] {
        let maxPayload = 19
        let maxFirst   = 17  // first packet in multi-frame: 2 bytes for numPackets, 17 for data

        if raw.count <= maxPayload {
            // Single packet: header byte = (txId << 2) | 0 (NO_FRAGMENTS)
            var pkt = Data(capacity: raw.count + 1)
            pkt.append((txId << 2) | 0)
            pkt.append(raw)
            return [pkt]
        }

        // Multi-packet
        let numPackets = UInt16(ceil(Double(raw.count + 2) / Double(maxPayload)))
        var packets: [Data] = []
        var offset = 0

        // First packet: (txId << 2) | 1 + numPackets (2 bytes LE) + up to 17 data bytes
        var first = Data(capacity: 20)
        first.append((txId << 2) | 1)
        first.appendLE(numPackets)
        let firstLen = min(maxFirst, raw.count)
        first.append(raw[0..<firstLen])
        packets.append(first)
        offset = firstLen

        while offset < raw.count {
            let remaining = raw.count - offset
            let chunkLen  = min(maxPayload, remaining)
            let isLast    = (offset + chunkLen) >= raw.count
            var pkt = Data(capacity: chunkLen + 1)
            pkt.append((txId << 2) | (isLast ? 3 : 2))
            pkt.append(raw[offset..<(offset + chunkLen)])
            packets.append(pkt)
            offset += chunkLen
        }

        return packets
    }

    private static func nextId() -> UInt8 {
        lastId = (lastId + 1) % 64
        return lastId
    }
}

// MARK: - Unframer

/// Reassembles incoming 20-byte BLE packets back into a LunaMessage.
class LunaUnframer {
    private var buffer: Data = Data()
    private var expectedPackets: UInt16 = 0
    private var receivedPackets: UInt16 = 0
    private var activeId: UInt8 = 0xFF

    /// Feed a raw BLE notify packet. Returns a complete LunaMessage when all fragments arrive.
    func feed(_ raw: Data) -> LunaMessage? {
        guard !raw.isEmpty else { return nil }
        let header     = raw[0]
        let txId       = (header >> 2) & 0x3F
        let frameStatus = header & 0x03

        switch frameStatus {
        case 0: // NO_FRAGMENTS — single packet
            let payload = raw.dropFirst()
            return LunaMessage(raw: Data(payload))

        case 1: // FIRST_FRAGMENT
            guard raw.count >= 3 else { return nil }
            expectedPackets = Data(raw[1...2]).leUInt16(at: 0)
            receivedPackets = 1
            activeId        = txId
            buffer          = Data(raw[3...])
            return nil

        case 2: // MORE_FRAGMENTS
            guard txId == activeId else { return nil }
            buffer.append(raw.dropFirst())
            receivedPackets += 1
            return nil

        case 3: // LAST_FRAGMENT
            guard txId == activeId else { return nil }
            buffer.append(raw.dropFirst())
            receivedPackets += 1
            if receivedPackets == expectedPackets {
                let complete = buffer
                reset()
                return LunaMessage(raw: complete)
            }
            return nil

        default:
            return nil
        }
    }

    func reset() {
        buffer = Data()
        expectedPackets = 0
        receivedPackets = 0
        activeId = 0xFF
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func appendLE(_ v: UInt16) {
        var le = v.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &le, Array.init))
    }
    mutating func appendLE(_ v: Int16) {
        var le = v.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &le, Array.init))
    }
    mutating func appendLE(_ v: Int32) {
        var le = v.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &le, Array.init))
    }
    mutating func appendLE(_ v: UInt32) {
        var le = v.littleEndian
        append(contentsOf: Swift.withUnsafeBytes(of: &le, Array.init))
    }

    func leUInt16(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
}

// MARK: - Parsed Responses

// MARK: Battery

struct LunaBattery {
    let voltage: UInt16
    let percentage: UInt8
    let status: UInt8?  // version 1+

    init?(_ msg: LunaMessage) {
        guard msg.type == .battery, msg.payload.count >= 3 else { return nil }
        voltage    = msg.payload.leUInt16(at: 0)
        percentage = msg.payload[2]
        status     = msg.payload.count >= 4 ? msg.payload[3] : nil
    }
}

// MARK: System Info

struct LunaSystemInfo {
    let kernelMajor: UInt8
    let kernelMinor: UInt8
    let kernelBuild: UInt8?   // version 2 (3-decimal) only
    let bootMajor: UInt8
    let bootMinor: UInt8
    let bootBuild: UInt8?

    var kernelVersion: String {
        if let b = kernelBuild { return "\(kernelMajor).\(kernelMinor).\(b)" }
        return "\(kernelMajor).\(kernelMinor)"
    }
    var bootVersion: String {
        if let b = bootBuild { return "\(bootMajor).\(bootMinor).\(b)" }
        return "\(bootMajor).\(bootMinor)"
    }

    init?(_ msg: LunaMessage) {
        guard msg.type == .systemInfo else { return nil }
        let p = msg.payload
        if msg.version == 2 {   // 3-decimal format
            guard p.count >= 6 else { return nil }
            kernelMajor = p[0]; kernelMinor = p[1]; kernelBuild = p[2]
            bootMajor   = p[3]; bootMinor   = p[4]; bootBuild   = p[5]
        } else {
            guard p.count >= 4 else { return nil }
            kernelMajor = p[0]; kernelMinor = p[1]; kernelBuild = nil
            bootMajor   = p[2]; bootMinor   = p[3]; bootBuild   = nil
        }
    }
}

// MARK: Activity Bucket (15-minute interval)

struct LunaActivityBucket {
    let timestamp: Date
    let steps: Int
    let effectiveMinutes: Int
    let avgAmplitude: Int
    let avgPeriod: Int
    let calories: Int
    let distanceCm: Int
}

struct LunaActivity {
    let buckets: [LunaActivityBucket]

    init?(_ msg: LunaMessage) {
        guard msg.type == .activity, msg.payload.count >= 5 else { return nil }
        let p = msg.payload
        let baseVector = Int32(bitPattern: UInt32(p[0]) | UInt32(p[1]) << 8 |
                                           UInt32(p[2]) << 16 | UInt32(p[3]) << 24)
        let baseUnix = TimeInterval(Int(baseVector) + 946_684_800)
        let count = Int(p[4])
        guard p.count >= 5 + count * 16 else { return nil }

        var result: [LunaActivityBucket] = []
        for i in 0..<count {
            let o = 5 + i * 16
            let ts  = Date(timeIntervalSince1970: baseUnix + TimeInterval(i * 900))
            let steps = Int(Int16(bitPattern: UInt16(p[o]) | UInt16(p[o+1]) << 8))
            let eff   = Int(Int16(bitPattern: UInt16(p[o+2]) | UInt16(p[o+3]) << 8))
            let amp   = Int(Int16(bitPattern: UInt16(p[o+4]) | UInt16(p[o+5]) << 8))
            let per   = Int(Int16(bitPattern: UInt16(p[o+6]) | UInt16(p[o+7]) << 8))
            let cal   = Int(Int32(bitPattern: UInt32(p[o+8])  | UInt32(p[o+9])  << 8 |
                                              UInt32(p[o+10]) << 16 | UInt32(p[o+11]) << 24))
            let dist  = Int(Int32(bitPattern: UInt32(p[o+12]) | UInt32(p[o+13]) << 8 |
                                              UInt32(p[o+14]) << 16 | UInt32(p[o+15]) << 24))
            result.append(LunaActivityBucket(timestamp: ts, steps: steps,
                effectiveMinutes: eff, avgAmplitude: amp, avgPeriod: per,
                calories: cal, distanceCm: dist))
        }
        buckets = result
    }
}

// MARK: Activity Totals

struct LunaActivityTotals {
    let steps: Int
    let calories: Int
    let distanceCm: Int
    let sleepMinutes: Int

    init?(_ msg: LunaMessage) {
        guard msg.type == .activityTotals, msg.payload.count >= 8 else { return nil }
        let p = msg.payload
        steps        = Int(Int16(bitPattern: UInt16(p[0]) | UInt16(p[1]) << 8))
        calories     = Int(Int16(bitPattern: UInt16(p[2]) | UInt16(p[3]) << 8))
        distanceCm   = Int(Int16(bitPattern: UInt16(p[4]) | UInt16(p[5]) << 8))
        sleepMinutes = Int(Int16(bitPattern: UInt16(p[6]) | UInt16(p[7]) << 8))
    }
}

// MARK: Button Press

enum LunaWatchButton: UInt8 {
    case up     = 0
    case middle = 1
    case down   = 2
}

enum LunaButtonEvent: UInt8 {
    case press       = 0
    case doublePress = 1
    case longPress   = 2
}

struct LunaButtonPress {
    let appId: Int32
    let watchfaceId: UInt8
    let button: LunaWatchButton
    let event: LunaButtonEvent
    let identifier: Int32
    let value: Int32

    init?(_ msg: LunaMessage) {
        guard msg.type == .btnPress, msg.payload.count >= 14 else { return nil }
        let p = msg.payload
        appId       = Int32(bitPattern: UInt32(p[0]) | UInt32(p[1]) << 8 | UInt32(p[2]) << 16 | UInt32(p[3]) << 24)
        watchfaceId = p[4]
        button      = LunaWatchButton(rawValue: p[5]) ?? .middle
        event       = LunaButtonEvent(rawValue: p[6]) ?? .press
        identifier  = Int32(bitPattern: UInt32(p[7]) | UInt32(p[8]) << 8 | UInt32(p[9]) << 16 | UInt32(p[10]) << 24)
        value       = Int32(bitPattern: UInt32(p[11]) | UInt32(p[12]) << 8 | UInt32(p[13]) << 16 | UInt32(p[14 < p.count ? 14 : p.count - 1]) << 24)
    }
}

// MARK: - Additional message builders

extension LunaMessage {

    static func getActivity() -> LunaMessage {
        var p = Data(capacity: 2)
        p.appendLE(UInt16(12))  // subcommand 12
        return LunaMessage(type: .command, version: 0, payload: p)
    }

    static func syncSettings(_ settings: [(UInt8, UInt8)]) -> LunaMessage {
        var p = Data()
        p.append(UInt8(settings.count))
        for (type, value) in settings {
            p.append(type)
            p.append(value)
        }
        return LunaMessage(type: .settings, version: 0, payload: p)
    }

    static func syncSettingName(_ name: String) -> LunaMessage {
        var p = Data()
        p.append(UInt8(1))        // 1 change
        p.append(UInt8(0))        // type 0 = NAME
        let bytes = Array(name.utf8.prefix(30))
        p.append(UInt8(bytes.count))
        p.append(contentsOf: bytes)
        return LunaMessage(type: .settings, version: 0, payload: p)
    }

    static func syncAlarms(_ alarms: [(hour: UInt8, minute: UInt8, enabled: Bool, name: String)]) -> LunaMessage {
        var p = Data()
        p.append(UInt8(alarms.count))
        for a in alarms { p.append(a.hour); p.append(a.minute); p.append(a.enabled ? 1 : 0) }
        for a in alarms {
            let bytes = Array(a.name.utf8.prefix(20))
            p.append(UInt8(bytes.count))
            p.append(contentsOf: bytes)
        }
        return LunaMessage(type: .alarm, version: 1, payload: p)
    }

    static func pushText(appId: Int32, watchfaceId: UInt8, elementId: UInt8,
                         text: String, ttl: Int32 = 300) -> LunaMessage {
        var p = Data()
        p.appendLE(appId)
        p.append(watchfaceId)
        p.append(elementId)
        p.append(UInt8(1))        // elementType TEXT
        p.appendLE(ttl)
        p.appendLE(Int32(Int.random(in: 1..<Int(Int32.max))))  // dataId
        p.append(UInt8(0))        // ttlType
        let bytes = Array(text.utf8.prefix(32))
        p.append(UInt8(bytes.count))
        p.append(contentsOf: bytes)
        return LunaMessage(type: .push, version: 3, payload: p)
    }

    static func syncCalendarEvent(index: UInt8, start: Date, end: Date,
                                  title: String, location: String = "") -> LunaMessage {
        var p = Data()
        p.append(index)
        let startV = Int32(start.timeIntervalSince1970) - 946_684_800
        let endV   = Int32(end.timeIntervalSince1970)   - 946_684_800
        p.appendLE(startV)
        p.appendLE(endV)
        let t = Array(title.utf8.prefix(39)) + [0]
        let l = Array(location.utf8.prefix(39)) + [0]
        p.append(contentsOf: t)
        p.append(contentsOf: l)
        return LunaMessage(type: .calendarEvents, version: 0, payload: p)
    }

    // Sync goals to watch. Payload format mirrors Android SyncGoalsCommand:
    // [count][goalType:u8 + value:i32 LE]...
    // goalType: 0=steps, 1=calories, 2=distance(cm), 3=sleep(15-min buckets)
    static func syncGoals(steps: Int? = nil,
                          calories: Int? = nil,
                          distanceCm: Int? = nil,
                          sleepMinutes: Int? = nil) -> LunaMessage {
        var goals: [(UInt8, Int32)] = []
        if let steps { goals.append((0, Int32(steps))) }
        if let calories { goals.append((1, Int32(calories))) }
        if let distanceCm { goals.append((2, Int32(distanceCm))) }
        if let sleepMinutes {
            // Android multiplies sleep goal by 4 (15-minute slots).
            goals.append((3, Int32(sleepMinutes * 4)))
        }

        var p = Data(capacity: 1 + goals.count * 5)
        p.append(UInt8(goals.count))
        for (type, value) in goals {
            p.append(type)
            p.appendLE(UInt32(bitPattern: value))
        }
        return LunaMessage(type: .goal, version: 0, payload: p)
    }

    // Dedicated "notifications mode" setting update (Android uses SettingsType 24).
    // mode: 0=off, 1=show contents, 2=show alert only
    static func syncNotificationMode(_ mode: UInt8) -> LunaMessage {
        let clamped = min(mode, 2)
        return .syncSettings([(24, clamped)])
    }

    // VFTP: initiate a file transfer (phone → watch)
    // Payload:
    // [msgType=1][realSize:u16][flags:u8][compressedSize:u16][fileType:u8][fileId:u32]
    // flags bit0=compressed, bit1=force overwrite
    static func vftpPut(fileId: Int32,
                        fileType: UInt8,
                        data: Data,
                        compressed: Bool = false,
                        force: Bool = true,
                        uncompressedSize: UInt16? = nil) -> LunaMessage {
        let realSize = uncompressedSize ?? UInt16(data.count)
        var p = Data(capacity: 8)
        p.append(UInt8(1))           // PUT
        p.appendLE(realSize)
        var flags: UInt8 = 0
        if compressed { flags |= 1 }
        if force { flags |= 2 }
        p.append(flags)
        p.appendLE(realSize)         // compressedSize = realSize (uncompressed)
        p.append(fileType)
        p.appendLE(UInt32(bitPattern: fileId))
        return LunaMessage(type: .vftp, version: 0, payload: p)
    }

    // VFTP: send a data chunk
    static func vftpData(packetIndex: UInt16, chunk: Data) -> LunaMessage {
        var p = Data(capacity: 3 + chunk.count)
        p.append(UInt8(2))           // DATA
        p.appendLE(packetIndex)
        p.append(chunk)
        return LunaMessage(type: .vftp, version: 0, payload: p)
    }

    // VFTP: send status response
    static func vftpStatus(_ code: UInt8) -> LunaMessage {
        var p = Data(capacity: 2)
        p.append(UInt8(3))           // STATUS
        p.append(code)
        return LunaMessage(type: .vftp, version: 0, payload: p)
    }
}

// MARK: - Notification messages (Service 1 — raw, no framing)

struct LunaNotification {

    enum Kind {
        case incomingCall, removeCall
        case sms, removeSms
        case social, removeSocial
        case missedCall, removeMissedCall
        case remove
    }

    static func infoMessage(kind: Kind, notificationId: Int32) -> Data {
        var d = Data(capacity: 8)
        switch kind {
        case .incomingCall:    d += [0x00, 0x00, 0x01, 0x01]
        case .removeCall:      d += [0x02, 0x00, 0x01, 0x00]
        case .sms:             d += [0x00, 0x00, 0x04, 0x01]
        case .removeSms:       d += [0x02, 0x00, 0x04, 0x00]
        case .social:          d += [0x00, 0x00, 0x04, 0x01]
        case .removeSocial:    d += [0x02, 0x00, 0x04, 0x00]
        case .missedCall:      d += [0x00, 0x00, 0x02, 0x01]
        case .removeMissedCall:d += [0x02, 0x00, 0x02, 0x00]
        case .remove:          d += [0x02, 0x00, 0x04, 0x00]
        }
        var idLE = notificationId.littleEndian
        d.append(contentsOf: Swift.withUnsafeBytes(of: &idLE, Array.init))
        return d
    }

    // Parse a detail request that arrives on 81A50001 (Indicate)
    struct DetailRequest {
        let notificationId: Int32
        let fieldType: UInt8   // 0=APP_ID  1=TITLE  3=MESSAGE
    }

    static func parseDetailRequest(_ raw: Data) -> DetailRequest? {
        guard raw.count >= 6 else { return nil }
        let nid = Int32(bitPattern: UInt32(raw[1]) | UInt32(raw[2]) << 8 |
                                    UInt32(raw[3]) << 16 | UInt32(raw[4]) << 24)
        return DetailRequest(notificationId: nid, fieldType: raw[5])
    }

    // Build a detail response sent back on 81A50002
    static func detailResponse(notificationId: Int32, fieldType: UInt8, text: String) -> Data {
        let bytes = Array(text.utf8.prefix(fieldType == 0 ? 30 : 255))
        var d = Data(capacity: 8 + bytes.count)
        d.append(UInt8(0))  // unknown leading byte
        var idLE = notificationId.littleEndian
        d.append(contentsOf: Swift.withUnsafeBytes(of: &idLE, Array.init))
        d.append(fieldType)
        var sizeLE = UInt16(bytes.count).littleEndian
        d.append(contentsOf: Swift.withUnsafeBytes(of: &sizeLE, Array.init))
        d.append(contentsOf: bytes)
        return d
    }
}

private extension Data {
    static func += (lhs: inout Data, rhs: [UInt8]) { lhs.append(contentsOf: rhs) }
}
