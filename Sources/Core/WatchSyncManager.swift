import Foundation
import UserNotifications
import UIKit
import EventKit

// MARK: - Pending notification (held for detail-request handshake)

struct PendingWatchNotification {
    let id: Int32
    let appName: String
    let title: String
    let message: String
    let kind: LunaNotification.Kind
}

// MARK: - WatchSyncManager

/// Central orchestrator between the iOS app and the Luna watch.
/// Owns the post-connect sync sequence, dispatches all incoming LunaMessages
/// to the right @Published properties, and relays iOS notifications to the watch.
class WatchSyncManager: ObservableObject {

    static let shared = WatchSyncManager()

    // MARK: - Published watch state

    @Published var batteryPercentage: Int?        = nil
    @Published var systemInfo: LunaSystemInfo?    = nil
    @Published var serialNumber: String?          = nil
    @Published var watchUUID: String?             = nil

    // Activity (from watch sensor data)
    @Published var todaySteps: Int       = 0
    @Published var todayCalories: Int    = 0
    @Published var todayDistanceKm: Double = 0
    @Published var todaySleepMinutes: Int  = 0
    @Published var activityBuckets: [LunaActivityBucket] = []

    // Sync state
    @Published var lastSyncDate: Date?    = nil
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastButtonPress: LunaButtonPress? = nil
    @Published private(set) var vftpStateLabel: String = "Idle"
    @Published private(set) var vftpQueueDepth: Int = 0

    // MARK: - Internal

    weak var ble: BLEManager?

    private var pendingNotifications: [Int32: PendingWatchNotification] = [:]
    private var notifIdCounter: Int32 = 1
    private var syncQueue = DispatchQueue(label: "com.lunawatch.sync", qos: .utility)
    private let eventStore = EKEventStore()
    let vftp = VFTPTransferManager()

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case synced(Date)
        case error(String)

        var label: String {
            switch self {
            case .idle:          return "Not synced"
            case .syncing:       return "Syncing…"
            case .synced(let d): return "Synced \(Self.relativeTime(d))"
            case .error(let e):  return "Error: \(e)"
            }
        }

        static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.syncing, .syncing): return true
            case (.synced(let a), .synced(let b)):     return a == b
            case (.error(let a), .error(let b)):       return a == b
            default: return false
            }
        }

        private static func relativeTime(_ date: Date) -> String {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: date, relativeTo: Date())
        }
    }

    private init() {
        vftp.onStateChanged = { [weak self] in
            DispatchQueue.main.async { self?.refreshVFTPStatus() }
        }
    }

    // MARK: - Connection lifecycle

    /// Called by BLEManager immediately after a successful connection.
    func onConnect() {
        syncStatus = .syncing
        vftp.ble = ble
        // Give the watch a moment to settle, then run the standard init sequence.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.performInitialSync() }
    }

    func onDisconnect() {
        syncStatus = .idle
        vftp.onDisconnect()
        refreshVFTPStatus()
    }

    /// Standard post-connect sequence (mirrors what the Android app does).
    func performInitialSync() {
        guard let ble = ble else { return }
        let steps: [(TimeInterval, LunaMessage)] = [
            (0.0,  .freshStart()),
            (0.6,  .syncTime()),
            (1.2,  .getSystemInfo()),
            (1.8,  .getBattery()),
            (2.4,  .getActivity()),
            (3.0,  .getSerialNumber()),
            (3.6,  .getUUID()),
        ]
        for (delay, msg) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ble.sendMessage(msg)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            self.pushSavedProfileAndPreferences()
            self.pushSavedAlarms()
            self.syncDefaultGoals()
            self.syncUpcomingCalendarEvents()
            self.lastSyncDate = Date()
            self.syncStatus   = .synced(Date())
        }
    }

    // MARK: - Incoming message dispatcher

    /// Called by BLEManager every time a complete framed message arrives on DATA RX (9e3b0002).
    func handle(_ message: LunaMessage) {
        DispatchQueue.main.async {
            switch message.type {
            case .battery:
                if let b = LunaBattery(message) {
                    self.batteryPercentage = Int(b.percentage)
                }
            case .systemInfo:
                self.systemInfo = LunaSystemInfo(message)
            case .activity:
                if let a = LunaActivity(message) {
                    self.activityBuckets = a.buckets
                    self.todaySteps    = a.buckets.reduce(0) { $0 + $1.steps }
                    self.todayCalories = a.buckets.reduce(0) { $0 + $1.calories }
                    self.todayDistanceKm = Double(a.buckets.reduce(0) { $0 + $1.distanceCm }) / 100_000
                }
            case .activityTotals:
                if let t = LunaActivityTotals(message) {
                    if self.todaySteps    == 0 { self.todaySteps    = t.steps }
                    if self.todayCalories == 0 { self.todayCalories = t.calories }
                    if self.todayDistanceKm == 0 { self.todayDistanceKm = Double(t.distanceCm) / 100_000 }
                    self.todaySleepMinutes = t.sleepMinutes
                }
            case .btnPress:
                self.lastButtonPress = LunaButtonPress(message)
            case .serialNumber:
                if let s = String(data: message.payload, encoding: .ascii) {
                    self.serialNumber = s.trimmingCharacters(in: .controlCharacters)
                }
            case .uuid:
                let hex = message.payload.map { String(format: "%02X", $0) }.joined()
                self.watchUUID = hex
            case .freshStart:
                // Watch asking us to re-init — comply
                self.performInitialSync()
            case .vftp:
                self.vftp.handleVFTPStatusPayload(message.payload)
                self.refreshVFTPStatus()
            default:
                break
            }
        }
    }

    // MARK: - Indicate handler (notification detail requests on 81A50001)

    /// Called by BLEManager when data arrives on BLE_SHIELD_RX (81A50001, Indicate).
    func handleIndicateData(_ raw: Data) {
        guard let req = LunaNotification.parseDetailRequest(raw),
              let pending = pendingNotifications[req.notificationId],
              let ble = ble else { return }

        let text: String
        switch req.fieldType {
        case 0: text = pending.appName
        case 1: text = pending.title
        case 3: text = pending.message
        default: return
        }

        let resp = LunaNotification.detailResponse(
            notificationId: req.notificationId,
            fieldType: req.fieldType,
            text: text
        )
        ble.send(resp, to: ble.characteristic(for: LunaGATT.writeCharUUID))
    }

    // MARK: - Send notification to watch

    func sendNotification(kind: LunaNotification.Kind = .sms,
                          appName: String, title: String, message: String) {
        guard let ble = ble, ble.isConnected else { return }

        let nid = notifIdCounter
        notifIdCounter += 1

        // Store for detail-request handshake
        pendingNotifications[nid] = PendingWatchNotification(
            id: nid, appName: appName, title: title, message: message, kind: kind
        )

        // Send 8-byte info header on BLE_SHIELD_TX_NOT_INFO (81A50003)
        let infoData = LunaNotification.infoMessage(kind: kind, notificationId: nid)
        ble.send(infoData, to: ble.characteristic(for: LunaGATT.write2CharUUID))

        // Clean up after 30 s if the watch never requested details
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.pendingNotifications.removeValue(forKey: nid)
        }
    }

    // MARK: - Settings sync helpers

    func syncSettings(
        hourMode24h: Bool    = true,
        metricUnits: Bool    = true,
        glance: Bool         = true,
        dnd: Bool            = false,
        backlightLevel: UInt8  = 1,   // 0–2 (watch hardware max = 2)
        backlightTimeout: UInt8 = 5,  // seconds: 2 | 5 | 10 | 20 | 30; 0 = always-on
        showSecondHand: Bool = true
    ) {
        guard let ble = ble else { return }
        // The watch uses setting types:
        //  6 = unit system (0=metric, 1=imperial)
        //  7 = hour mode   (0=24h, 1=12h)
        // 14 = DND         (1=on)
        // 16 = glance/raise-to-wake (1=on)
        // 18 = backlight intensity  (0–2)
        // 19 = backlight timeout    (seconds, per Android BACKLIGHT_TIMEOUT_DURATION_*)
        // 20 = show second hand     (1=on)
        let settings: [(UInt8, UInt8)] = [
            (7,  hourMode24h    ? 0 : 1),
            (6,  metricUnits    ? 0 : 1),
            (16, glance         ? 1 : 0),
            (14, dnd            ? 1 : 0),
            (18, min(backlightLevel, 2)),   // clamp to 0–2
            (19, backlightTimeout),
            (20, showSecondHand ? 1 : 0),
        ]
        ble.sendMessage(.syncSettings(settings))
    }

    func syncNotificationMode(_ mode: Int) {
        guard let ble = ble else { return }
        ble.sendMessage(.syncNotificationMode(UInt8(max(0, min(mode, 2)))))
    }

    func pushWatchName(_ name: String) {
        guard let ble = ble else { return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !trimmed.isEmpty else { return }
        ble.sendMessage(.syncSettingName(trimmed))
    }

    func syncGoals(steps: Int, calories: Int, distanceKm: Double, sleepMinutes: Int) {
        guard let ble = ble else { return }
        let distanceCm = Int((distanceKm * 100_000.0).rounded())
        ble.sendMessage(.syncGoals(
            steps: max(0, steps),
            calories: max(0, calories),
            distanceCm: max(0, distanceCm),
            sleepMinutes: max(0, sleepMinutes)
        ))
    }

    func syncDefaultGoals() {
        let settings = LunaSettings.shared
        // Keep defaults consistent with the in-app health goal card.
        syncGoals(steps: 10_000, calories: 500, distanceKm: 7.0, sleepMinutes: 8 * 60)
        syncNotificationMode(settings.notificationsMode)
    }

    func syncAlarms(_ alarms: [LunaAlarm]) {
        guard let ble = ble, ble.isConnected else { return }
        let payload = alarms.enumerated().compactMap { (i, alarm) -> (hour: UInt8, minute: UInt8, enabled: Bool, name: String)? in
            guard i < 8 else { return nil }
            return (hour: UInt8(alarm.hour), minute: UInt8(alarm.minute), enabled: alarm.enabled, name: alarm.label)
        }
        ble.sendMessage(.syncAlarms(payload))
    }

    func pushSavedAlarms() {
        syncAlarms(LunaSettings.shared.alarms)
    }

    func pushSavedProfileAndPreferences() {
        let s = LunaSettings.shared
        syncSettings(
            hourMode24h: s.hour24Mode,
            metricUnits: s.metricUnits,
            glance: s.glanceMode,
            dnd: s.dndEnabled,
            backlightLevel: UInt8(min(max(s.backlightLevel, 1), 5)),
            showSecondHand: s.showSecondHand
        )
        if !s.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pushWatchName(s.userName)
        }
        syncNotificationMode(s.notificationsMode)
    }

    func syncUpcomingCalendarEvents(limit: Int = 5) {
        let completion: (Bool) -> Void = { granted in
            guard granted else { return }
            let now = Date()
            guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
            let predicate = self.eventStore.predicateForEvents(withStart: now, end: end, calendars: nil)
            let events = self.eventStore.events(matching: predicate)
                .filter { !$0.isAllDay }
                .sorted { $0.startDate < $1.startDate }
            let top = Array(events.prefix(max(1, min(limit, 10))))

            if top.isEmpty {
                self.ble?.sendMessage(.syncCalendarEvent(index: 0, start: now, end: now, title: "", location: ""))
                return
            }
            for (idx, event) in top.enumerated() {
                self.ble?.sendMessage(.syncCalendarEvent(
                    index: UInt8(idx),
                    start: event.startDate,
                    end: event.endDate,
                    title: event.title,
                    location: event.location ?? ""
                ))
            }
        }
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { granted, _ in completion(granted) }
        } else {
            eventStore.requestAccess(to: .event) { granted, _ in completion(granted) }
        }
    }

    // MARK: - iOS notification relay

    /// Request iOS notification permission and start observing.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            if granted {
                // TODO: set up UNNotificationServiceExtension or use
                // CoreTelephony / CallKit for call notifications
            }
        }
    }

    // MARK: - Package install / VFTP

    func installPackage(_ pkg: LunaPackageDescriptor, catalog: LunaPackageCatalogManager) {
        let files = catalog.buildTransferPayloads(for: pkg)
        guard !files.isEmpty else { return }
        vftp.enqueue(files: files)
        refreshVFTPStatus()
    }

    func sendDesignedFaceImage(_ data: Data, fileId: Int32) {
        guard !data.isEmpty else { return }
        let payload = LunaVFTPFilePayload(
            fileId: fileId,
            fileType: .resource,
            data: data,
            uncompressedSize: UInt16(data.count),
            compressed: false,
            force: true
        )
        vftp.enqueue(file: payload)
        refreshVFTPStatus()
    }

    private func refreshVFTPStatus() {
        switch vftp.state {
        case .idle:
            vftpStateLabel = "Idle"
        case .sending(let fileId, let sent, let total):
            vftpStateLabel = "Sending \(fileId) [\(sent)/\(total)]"
        case .awaitingStatus(let fileId):
            vftpStateLabel = "Awaiting status for \(fileId)"
        case .completed(let fileId):
            vftpStateLabel = "Completed \(fileId)"
        case .failed(let msg):
            vftpStateLabel = "Failed: \(msg)"
        }
        vftpQueueDepth = vftp.queueDepth
    }
}
