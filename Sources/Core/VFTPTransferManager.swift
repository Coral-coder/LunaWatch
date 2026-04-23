import Foundation

enum LunaVFTPFileType: UInt8, CaseIterable, Codable {
    case any = 0
    case resource = 1
    case application = 2
    case localeTmp = 3
    case locale = 4
    case tmp = 5
}

enum LunaVFTPState: Equatable {
    case idle
    case sending(fileId: Int32, sentPackets: Int, totalPackets: Int)
    case awaitingStatus(fileId: Int32)
    case completed(fileId: Int32)
    case failed(String)
}

struct LunaVFTPFilePayload: Identifiable {
    let id = UUID()
    let fileId: Int32
    let fileType: LunaVFTPFileType
    let data: Data
    let uncompressedSize: UInt16
    let compressed: Bool
    let force: Bool
}

final class VFTPTransferManager: ObservableObject {
    @Published private(set) var state: LunaVFTPState = .idle
    @Published private(set) var queueDepth: Int = 0

    weak var ble: BLEManager?
    var onStateChanged: (() -> Void)?

    private var queue: [LunaVFTPFilePayload] = []
    private var active: LunaVFTPFilePayload?
    private var activePacketIndex: UInt16 = 0
    private var activeTotalPackets: Int = 0
    private let chunkSize = 128

    func enqueue(file: LunaVFTPFilePayload) {
        queue.append(file)
        queueDepth = queue.count + (active == nil ? 0 : 1)
        onStateChanged?()
        startIfPossible()
    }

    func enqueue(files: [LunaVFTPFilePayload]) {
        queue.append(contentsOf: files)
        queueDepth = queue.count + (active == nil ? 0 : 1)
        onStateChanged?()
        startIfPossible()
    }

    func clearQueue() {
        queue.removeAll()
        active = nil
        activePacketIndex = 0
        activeTotalPackets = 0
        queueDepth = 0
        state = .idle
        onStateChanged?()
    }

    func onDisconnect() {
        if active != nil || !queue.isEmpty {
            state = .failed("Disconnected during VFTP transfer")
        } else {
            state = .idle
        }
        active = nil
        activePacketIndex = 0
        activeTotalPackets = 0
        queue.removeAll()
        queueDepth = 0
        onStateChanged?()
    }

    /// Watch sent VFTP status payload on DATA RX type .vftp.
    /// Expected format: [msgType=3][statusCode]
    func handleVFTPStatusPayload(_ payload: Data) {
        guard payload.count >= 2, payload[0] == 3 else { return }
        let status = payload[1]
        guard let current = active else { return }
        if status == 0 {
            finishCurrentFile(success: true, message: nil, fileId: current.fileId)
        } else {
            finishCurrentFile(success: false, message: "Watch status error \(status)", fileId: current.fileId)
        }
    }

    private func startIfPossible() {
        guard active == nil else { return }
        guard let ble, ble.isConnected else {
            if !queue.isEmpty { state = .failed("Watch not connected") }
            onStateChanged?()
            return
        }
        guard !queue.isEmpty else {
            state = .idle
            queueDepth = 0
            onStateChanged?()
            return
        }

        let next = queue.removeFirst()
        active = next
        activePacketIndex = 0
        activeTotalPackets = Int(ceil(Double(next.data.count) / Double(chunkSize)))
        queueDepth = queue.count + 1
        state = .sending(fileId: next.fileId, sentPackets: 0, totalPackets: max(activeTotalPackets, 1))
        onStateChanged?()

        ble.sendMessage(.vftpPut(
            fileId: next.fileId,
            fileType: next.fileType.rawValue,
            data: next.data,
            compressed: next.compressed,
            force: next.force,
            uncompressedSize: next.uncompressedSize
        ))

        sendNextChunk()
    }

    private func sendNextChunk() {
        guard let ble, let current = active else { return }

        let total = max(activeTotalPackets, 1)
        if Int(activePacketIndex) >= total {
            state = .awaitingStatus(fileId: current.fileId)
            onStateChanged?()
            return
        }

        let start = Int(activePacketIndex) * chunkSize
        let end = min(start + chunkSize, current.data.count)
        let chunk = current.data.subdata(in: start..<end)

        ble.sendMessage(.vftpData(packetIndex: activePacketIndex, chunk: chunk))
        activePacketIndex &+= 1
        state = .sending(fileId: current.fileId, sentPackets: Int(activePacketIndex), totalPackets: total)
        onStateChanged?()

        // Protocol behavior in the Android app streams chunks optimistically, then handles status.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.sendNextChunk()
        }
    }

    private func finishCurrentFile(success: Bool, message: String?, fileId: Int32) {
        active = nil
        activePacketIndex = 0
        activeTotalPackets = 0
        queueDepth = queue.count
        onStateChanged?()

        if success {
            state = .completed(fileId: fileId)
            onStateChanged?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.startIfPossible()
            }
        } else {
            state = .failed(message ?? "Transfer failed")
            onStateChanged?()
        }
    }
}
