import SwiftUI

// MARK: - Alarm model

struct LunaAlarm: Identifiable, Codable {
    var id     = UUID()
    var hour:   Int
    var minute: Int
    var label:  String
    var enabled: Bool

    var timeString: String { String(format: "%02d:%02d", hour, minute) }

    static func loadAll() -> [LunaAlarm] {
        guard let data   = UserDefaults.standard.data(forKey: "luna.alarms"),
              let alarms = try? JSONDecoder().decode([LunaAlarm].self, from: data)
        else { return [] }
        return alarms
    }
    static func saveAll(_ alarms: [LunaAlarm]) {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: "luna.alarms")
        }
    }
}

// MARK: - Settings model

final class LunaSettings: ObservableObject {

    static let shared = LunaSettings()
    private let ud    = UserDefaults.standard

    // ── User Profile
    @Published var userName:  String
    @Published var userAge:   Int
    @Published var userGender: Int   // 0 = Male, 1 = Female
    @Published var weightKg:  Double
    @Published var heightCm:  Double

    // ── Display
    @Published var hour24Mode:      Bool
    @Published var metricUnits:     Bool
    @Published var showSecondHand:  Bool
    @Published var backlightLevel:  Int
    @Published var backlightTimeout: Int
    @Published var invertDisplay:   Bool

    // ── Watch Preferences
    @Published var glanceMode:      Bool
    @Published var dndEnabled:      Bool
    @Published var morningGreet:    Bool
    @Published var autoSleepDetect: Bool
    @Published var activityAlerts:  Bool
    @Published var notificationsMode: Int  // 0 = All, 1 = Priority, 2 = None

    // ── Watch Face
    @Published var faceMode:    Int   // 0 = Digital, 1 = Analog
    @Published var showDate:    Bool
    @Published var showWeather: Bool

    // ── Alarms
    @Published var alarms: [LunaAlarm]

    private init() {
        let ud = UserDefaults.standard
        userName       = ud.string(forKey:  "luna.profile.name")    ?? ""
        userAge        = ud.integer(forKey: "luna.profile.age")
        userGender     = ud.integer(forKey: "luna.profile.gender")
        weightKg       = ud.double(forKey:  "luna.profile.weight")
        heightCm       = ud.double(forKey:  "luna.profile.height")

        hour24Mode      = ud.bool(forKey: "luna.disp.hour24")
        metricUnits     = ud.object(forKey: "luna.disp.imperial") == nil ? true
                          : !ud.bool(forKey: "luna.disp.imperial")
        showSecondHand  = ud.object(forKey: "luna.disp.seconds")   == nil ? true
                          : ud.bool(forKey: "luna.disp.seconds")
        backlightLevel  = ud.object(forKey: "luna.disp.backlight") == nil ? 3
                          : ud.integer(forKey: "luna.disp.backlight")
        backlightTimeout = ud.object(forKey: "luna.disp.bltimeout") == nil ? 5
                          : ud.integer(forKey: "luna.disp.bltimeout")
        invertDisplay   = ud.bool(forKey: "luna.disp.invert")

        glanceMode      = ud.object(forKey: "luna.pref.glance")        == nil ? true
                          : ud.bool(forKey: "luna.pref.glance")
        dndEnabled      = ud.bool(forKey: "luna.pref.dnd")
        morningGreet    = ud.object(forKey: "luna.pref.morning")       == nil ? true
                          : ud.bool(forKey: "luna.pref.morning")
        autoSleepDetect = ud.object(forKey: "luna.pref.autosleep")     == nil ? true
                          : ud.bool(forKey: "luna.pref.autosleep")
        activityAlerts  = ud.object(forKey: "luna.pref.activityalerts") == nil ? true
                          : ud.bool(forKey: "luna.pref.activityalerts")
        notificationsMode = ud.integer(forKey: "luna.pref.notifmode")

        faceMode    = ud.integer(forKey: "luna.face.mode")
        showDate    = ud.object(forKey: "luna.face.showdate")    == nil ? true
                      : ud.bool(forKey: "luna.face.showdate")
        showWeather = ud.object(forKey: "luna.face.showweather") == nil ? true
                      : ud.bool(forKey: "luna.face.showweather")

        alarms = LunaAlarm.loadAll()
    }

    // ── Persist helpers

    func save<T>(_ key: String, _ value: T) {
        ud.set(value, forKey: key)
    }

    func persistProfile() {
        ud.set(userName,   forKey: "luna.profile.name")
        ud.set(userAge,    forKey: "luna.profile.age")
        ud.set(userGender, forKey: "luna.profile.gender")
        ud.set(weightKg,   forKey: "luna.profile.weight")
        ud.set(heightCm,   forKey: "luna.profile.height")
    }

    func persistDisplay() {
        ud.set(hour24Mode,       forKey: "luna.disp.hour24")
        ud.set(!metricUnits,     forKey: "luna.disp.imperial")
        ud.set(showSecondHand,   forKey: "luna.disp.seconds")
        ud.set(backlightLevel,   forKey: "luna.disp.backlight")
        ud.set(backlightTimeout, forKey: "luna.disp.bltimeout")
        ud.set(invertDisplay,    forKey: "luna.disp.invert")
    }

    func persistPrefs() {
        ud.set(glanceMode,        forKey: "luna.pref.glance")
        ud.set(dndEnabled,        forKey: "luna.pref.dnd")
        ud.set(morningGreet,      forKey: "luna.pref.morning")
        ud.set(autoSleepDetect,   forKey: "luna.pref.autosleep")
        ud.set(activityAlerts,    forKey: "luna.pref.activityalerts")
        ud.set(notificationsMode, forKey: "luna.pref.notifmode")
    }

    func persistFace() {
        ud.set(faceMode,    forKey: "luna.face.mode")
        ud.set(showDate,    forKey: "luna.face.showdate")
        ud.set(showWeather, forKey: "luna.face.showweather")
    }

    func persistAlarms() {
        LunaAlarm.saveAll(alarms)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss)   private var dismiss
    @EnvironmentObject var watchSync: WatchSyncManager
    @StateObject private var settings = LunaSettings.shared

    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let dark   = Color(red: 0.07, green: 0.07, blue: 0.10)

    var body: some View {
        NavigationStack {
            ZStack {
                dark.ignoresSafeArea()
                List {
                    watchInfoSection
                    userProfileSection
                    displaySection
                    watchPrefsSection
                    watchFaceSection
                    alarmsSection
                    syncSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(accent)
                }
            }
        }
    }

    // MARK: - Watch Info

    private var watchInfoSection: some View {
        Section {
            // Connection card
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "applewatch")
                        .font(.system(size: 22))
                        .foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vector Luna")
                        .font(.headline)
                    Text(watchSync.syncStatus.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let pct = watchSync.batteryPercentage {
                    VStack(spacing: 2) {
                        Image(systemName: batteryIcon(pct))
                            .foregroundColor(batteryColor(pct))
                            .font(.system(size: 20))
                        Text("\(pct)%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(accent.opacity(0.08))

            if let info = watchSync.systemInfo {
                SettingsInfoRow(label: "Firmware",  value: info.kernelVersion)
                SettingsInfoRow(label: "Boot ROM",  value: info.bootVersion)
            }
            if let sn = watchSync.serialNumber {
                SettingsInfoRow(label: "Serial",    value: sn)
            }
            if let uid = watchSync.watchUUID {
                SettingsInfoRow(label: "Watch UUID", value: uid)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = uid
                        } label: { Label("Copy UUID", systemImage: "doc.on.doc") }
                    }
            }
            if let btn = watchSync.lastButtonPress {
                SettingsInfoRow(label: "Last button",
                                value: "\(btn.button) — \(btn.event)")
            }
        } header: {
            sectionHeader("WATCH INFO")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: - User Profile

    private var userProfileSection: some View {
        Section {
            HStack {
                Text("Name").foregroundColor(.primary)
                Spacer()
                TextField("Your name", text: $settings.userName)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(accent)
                    .onSubmit { settings.persistProfile() }
            }

            Picker("Gender", selection: $settings.userGender) {
                Text("Male").tag(0)
                Text("Female").tag(1)
            }
            .onChange(of: settings.userGender) { _ in settings.persistProfile() }

            IntStepperRow(label: "Age",
                          value: $settings.userAge,
                          range: 10...120,
                          unit: "yr",
                          onChange: settings.persistProfile)

            IntStepperRow(label: "Weight",
                          value: Binding(
                              get: { Int(settings.metricUnits
                                         ? settings.weightKg
                                         : settings.weightKg * 2.20462) },
                              set: { v in
                                  settings.weightKg = settings.metricUnits
                                      ? Double(v)
                                      : Double(v) / 2.20462
                              }),
                          range: 20...500,
                          unit: settings.metricUnits ? "kg" : "lb",
                          onChange: settings.persistProfile)

            IntStepperRow(label: "Height",
                          value: Binding(
                              get: { Int(settings.metricUnits
                                         ? settings.heightCm
                                         : settings.heightCm * 0.393701) },
                              set: { v in
                                  settings.heightCm = settings.metricUnits
                                      ? Double(v)
                                      : Double(v) / 0.393701
                              }),
                          range: 50...300,
                          unit: settings.metricUnits ? "cm" : "in",
                          onChange: settings.persistProfile)
        } header: {
            sectionHeader("USER PROFILE")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: - Display

    private var displaySection: some View {
        Section {
            Toggle("24-Hour Clock",   isOn: $settings.hour24Mode)
                .onChange(of: settings.hour24Mode)     { _ in settings.persistDisplay(); pushWatchSettings() }
            Toggle("Metric Units",    isOn: $settings.metricUnits)
                .onChange(of: settings.metricUnits)    { _ in settings.persistDisplay(); pushWatchSettings() }
            Toggle("Second Hand",     isOn: $settings.showSecondHand)
                .onChange(of: settings.showSecondHand) { _ in settings.persistDisplay(); pushWatchSettings() }
            Toggle("Invert Display",  isOn: $settings.invertDisplay)
                .onChange(of: settings.invertDisplay)  { _ in settings.persistDisplay(); pushWatchSettings() }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Backlight Level")
                    Spacer()
                    Text("\(settings.backlightLevel)")
                        .foregroundColor(accent)
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: Binding(
                           get: { Double(settings.backlightLevel) },
                           set: { settings.backlightLevel = Int($0) }),
                       in: 1...5, step: 1)
                    .tint(accent)
                    .onChange(of: settings.backlightLevel) { _ in
                        settings.persistDisplay()
                        pushWatchSettings()
                    }
            }

            Picker("Backlight Timeout", selection: $settings.backlightTimeout) {
                Text("3 sec").tag(3)
                Text("5 sec").tag(5)
                Text("10 sec").tag(10)
                Text("20 sec").tag(20)
                Text("Always On").tag(0)
            }
            .onChange(of: settings.backlightTimeout) { _ in
                settings.persistDisplay()
                pushWatchSettings()
            }
        } header: {
            sectionHeader("DISPLAY")
        }
        .listRowBackground(Color.white.opacity(0.05))
        .tint(accent)
    }

    // MARK: - Watch Preferences

    private var watchPrefsSection: some View {
        Section {
            Toggle("Raise to Wake",      isOn: $settings.glanceMode)
                .onChange(of: settings.glanceMode)      { _ in settings.persistPrefs(); pushWatchSettings() }
            Toggle("Do Not Disturb",     isOn: $settings.dndEnabled)
                .onChange(of: settings.dndEnabled)      { _ in settings.persistPrefs(); pushWatchSettings() }
            Toggle("Morning Greeting",   isOn: $settings.morningGreet)
                .onChange(of: settings.morningGreet)    { _ in settings.persistPrefs() }
            Toggle("Auto Sleep Detect",  isOn: $settings.autoSleepDetect)
                .onChange(of: settings.autoSleepDetect) { _ in settings.persistPrefs() }
            Toggle("Activity Alerts",    isOn: $settings.activityAlerts)
                .onChange(of: settings.activityAlerts)  { _ in settings.persistPrefs() }

            Picker("Notifications", selection: $settings.notificationsMode) {
                Text("All").tag(0)
                Text("Priority Only").tag(1)
                Text("Off").tag(2)
            }
            .onChange(of: settings.notificationsMode) { _ in settings.persistPrefs() }
        } header: {
            sectionHeader("WATCH PREFERENCES")
        }
        .listRowBackground(Color.white.opacity(0.05))
        .tint(accent)
    }

    // MARK: - Watch Face

    private var watchFaceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Face Style")
                    .font(.subheadline)
                Picker("", selection: $settings.faceMode) {
                    Label("Digital", systemImage: "textformat.123").tag(0)
                    Label("Analog",  systemImage: "clock").tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.faceMode) { _ in settings.persistFace() }
            }
            .listRowBackground(Color.white.opacity(0.05))

            Toggle("Show Date",    isOn: $settings.showDate)
                .onChange(of: settings.showDate)    { _ in settings.persistFace() }
            Toggle("Show Weather", isOn: $settings.showWeather)
                .onChange(of: settings.showWeather) { _ in settings.persistFace() }
        } header: {
            sectionHeader("WATCH FACE")
        }
        .listRowBackground(Color.white.opacity(0.05))
        .tint(accent)
    }

    // MARK: - Alarms

    @State private var showAddAlarm = false

    private var alarmsSection: some View {
        Section {
            if settings.alarms.isEmpty {
                Text("No alarms set")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                ForEach($settings.alarms) { $alarm in
                    Toggle(isOn: $alarm.enabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alarm.timeString)
                                .font(.system(size: 22, weight: .light, design: .monospaced))
                            if !alarm.label.isEmpty {
                                Text(alarm.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onChange(of: alarm.enabled) { _ in
                        settings.persistAlarms()
                        pushAlarms()
                    }
                }
                .onDelete { idx in
                    settings.alarms.remove(atOffsets: idx)
                    settings.persistAlarms()
                    pushAlarms()
                }
            }

            Button {
                showAddAlarm = true
            } label: {
                Label("Add Alarm", systemImage: "plus.circle.fill")
                    .foregroundColor(accent)
            }
        } header: {
            sectionHeader("ALARMS")
        }
        .listRowBackground(Color.white.opacity(0.05))
        .tint(accent)
        .sheet(isPresented: $showAddAlarm) {
            AddAlarmSheet { alarm in
                settings.alarms.append(alarm)
                settings.persistAlarms()
                pushAlarms()
            }
        }
    }

    // MARK: - Sync Actions

    private var syncSection: some View {
        Section {
            Button {
                watchSync.performInitialSync()
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundColor(isConnected ? accent : .secondary)
            }
            .disabled(!isConnected)

            Button {
                pushWatchSettings()
            } label: {
                Label("Push Settings to Watch", systemImage: "arrow.up.to.line")
                    .foregroundColor(isConnected ? accent : .secondary)
            }
            .disabled(!isConnected)

            Button {
                watchSync.syncDefaultGoals()
            } label: {
                Label("Sync Goals", systemImage: "target")
                    .foregroundColor(isConnected ? accent : .secondary)
            }
            .disabled(!isConnected)

            Button {
                watchSync.syncUpcomingCalendarEvents()
            } label: {
                Label("Sync Calendar (7 days)", systemImage: "calendar.badge.clock")
                    .foregroundColor(isConnected ? accent : .secondary)
            }
            .disabled(!isConnected)

            if !isConnected {
                Label("Connect your Luna watch in the Watch tab.",
                      systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            }
        } header: {
            sectionHeader("SYNC")
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    // MARK: - Private helpers

    private var isConnected: Bool { watchSync.ble?.isConnected == true }

    private func pushWatchSettings() {
        guard isConnected else { return }
        watchSync.pushWatchName(settings.userName)
        watchSync.syncSettings(
            hourMode24h:    settings.hour24Mode,
            metricUnits:    settings.metricUnits,
            glance:         settings.glanceMode,
            dnd:            settings.dndEnabled,
            backlightLevel: UInt8(min(settings.backlightLevel, 5)),
            showSecondHand: settings.showSecondHand
        )
        watchSync.syncNotificationMode(settings.notificationsMode)
    }

    private func pushAlarms() {
        guard isConnected else { return }
        watchSync.syncAlarms(settings.alarms)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(accent.opacity(0.85))
    }

    private func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case 75...100: return "battery.100"
        case 50..<75:  return "battery.75"
        case 25..<50:  return "battery.25"
        default:       return "battery.0"
        }
    }

    private func batteryColor(_ pct: Int) -> Color {
        pct > 40 ? .green : pct > 20 ? .orange : .red
    }
}

// MARK: - Reusable sub-views

struct SettingsInfoRow: View {
    let label: String
    let value: String
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }
}

struct IntStepperRow: View {
    let label:    String
    @Binding var value: Int
    let range:    ClosedRange<Int>
    let unit:     String
    let onChange: () -> Void
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("\(value) \(unit)", value: $value, in: range)
                .fixedSize()
                .onChange(of: value) { _ in onChange() }
        }
    }
}

// MARK: - Add Alarm Sheet

struct AddAlarmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (LunaAlarm) -> Void

    @State private var time  = Date()
    @State private var label = ""
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        NavigationStack {
            Form {
                Section("ALARM TIME") {
                    DatePicker("Time", selection: $time,
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.white.opacity(0.05))

                Section("LABEL (OPTIONAL)") {
                    TextField("e.g. Wake up", text: $label)
                }
                .listRowBackground(Color.white.opacity(0.05))

                Section {
                    Button("Add Alarm") {
                        let cal = Calendar.current
                        let h   = cal.component(.hour,   from: time)
                        let m   = cal.component(.minute, from: time)
                        onAdd(LunaAlarm(hour: h, minute: m,
                                        label: label, enabled: true))
                        dismiss()
                    }
                    .foregroundColor(accent)
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("New Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(accent)
                }
            }
        }
    }
}
