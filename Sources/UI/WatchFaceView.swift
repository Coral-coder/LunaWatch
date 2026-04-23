import SwiftUI
import PhotosUI

// MARK: - Main Watch Tab

struct WatchFaceView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var watchSync: WatchSyncManager
    @EnvironmentObject var faceManager: WatchFaceManager
    @EnvironmentObject var weather: WeatherManager

    @State private var showSettings = false
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let dark   = Color(red: 0.06, green: 0.06, blue: 0.09)

    var body: some View {
        NavigationStack {
            ZStack {
                dark.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {

                        // ── Status strip ──
                        HStack(spacing: 10) {
                            Circle()
                                .fill(ble.isConnected ? Color.green : Color(white: 0.3))
                                .frame(width: 8, height: 8)
                                .shadow(color: ble.isConnected ? .green.opacity(0.8) : .clear, radius: 5)
                            Text(ble.isConnected
                                 ? (ble.connectedDevice?.name ?? "R33K0")
                                 : ble.state.rawValue.uppercased())
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(ble.isConnected ? .green : .secondary)
                            Spacer()
                            if let pct = watchSync.batteryPercentage {
                                BatteryView(percentage: pct)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                        // ── Round watch preview ──
                        RoundWatchView(
                            mode: faceManager.settings.clockMode,
                            invertDisplay: faceManager.settings.invertDisplay,
                            backgroundPhotoData: faceManager.settings.backgroundPhotoData,
                            weatherText: faceManager.settings.showWeather ? weather.condition?.watchText : nil,
                            showDate: faceManager.settings.showDate,
                            now: tick
                        )

                        // ── Clock mode toggle ──
                        Picker("Mode", selection: $faceManager.settings.clockMode) {
                            ForEach(ClockMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 32)

                        // ── Sync status ──
                        if ble.isConnected {
                            Text(watchSync.syncStatus.label)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        // ── Action buttons ──
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                LunaActionButton(
                                    title: watchSync.syncStatus == .syncing ? "SYNCING…" : "SYNC WATCH",
                                    icon: "arrow.triangle.2.circlepath",
                                    color: accent,
                                    disabled: !ble.isConnected || watchSync.syncStatus == .syncing
                                ) { watchSync.performInitialSync() }

                                LunaActionButton(
                                    title: "SETTINGS",
                                    icon: "slider.horizontal.3",
                                    color: accent
                                ) { showSettings = true }
                            }

                            HStack(spacing: 10) {
                                if ble.isConnected {
                                    LunaActionButton(
                                        title: "DISCONNECT",
                                        icon: "antenna.radiowaves.left.and.right.slash",
                                        color: .red.opacity(0.9)
                                    ) { ble.disconnect() }
                                } else {
                                    LunaActionButton(
                                        title: ble.state == .scanning ? "SCANNING…" : "SCAN",
                                        icon: "antenna.radiowaves.left.and.right",
                                        color: accent,
                                        disabled: ble.state == .scanning
                                    ) { ble.startScanning() }
                                }

                                LunaActionButton(
                                    title: "VIBRATE",
                                    icon: "iphone.radiowaves.left.and.right",
                                    color: .orange,
                                    disabled: !ble.isConnected
                                ) {
                                    watchSync.sendNotification(
                                        kind: .sms,
                                        appName: "LunaWatch",
                                        title: "Test",
                                        message: "Buzz!"
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // ── Device picker (shown while scanning / not connected) ──
                        if !ble.discoveredDevices.isEmpty && !ble.isConnected {
                            DeviceListView()
                        }

                        // ── Watch info strip (when connected) ──
                        if ble.isConnected, let info = watchSync.systemInfo {
                            WatchInfoStrip(info: info)
                                .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 24)
                    }
                }
            }
            .navigationTitle("Luna Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(faceManager)
                    .environmentObject(watchSync)
                    .environmentObject(ble)
            }
            .onReceive(timer) { t in tick = t }
        }
    }
}

// MARK: - Round watch

struct RoundWatchView: View {
    let mode: ClockMode
    let invertDisplay: Bool
    let backgroundPhotoData: Data?
    let weatherText: String?
    let showDate: Bool
    let now: Date

    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        ZStack {
            // Outer metallic bezel
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.28), Color(white: 0.14), Color(white: 0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 244, height: 244)
                .shadow(color: .black.opacity(0.6), radius: 20, y: 10)

            // Inner bezel ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color(white: 0.5), Color(white: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: 232, height: 232)

            // Watch face
            ZStack {
                // Background
                Group {
                    if let data = backgroundPhotoData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .overlay(Color.black.opacity(0.45))
                    } else {
                        (invertDisplay ? Color.white : Color(red: 0.04, green: 0.04, blue: 0.06))
                    }
                }
                .clipShape(Circle())

                // Clock content
                if mode == .digital {
                    DigitalClockContent(invertDisplay: invertDisplay, now: now,
                                        weatherText: weatherText, showDate: showDate)
                } else {
                    AnalogClockContent(invertDisplay: invertDisplay, now: now,
                                       weatherText: weatherText)
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(Circle())

            // Crown
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.4), Color(white: 0.2)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 10, height: 28)
                .offset(x: 122, y: -18)
        }
    }
}

// MARK: - Digital face

struct DigitalClockContent: View {
    let invertDisplay: Bool
    let now: Date
    let weatherText: String?
    let showDate: Bool

    private var fg: Color { invertDisplay ? .black : .white }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: now)
    }
    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: now).uppercased()
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(timeString)
                .font(.system(size: 52, weight: .thin, design: .monospaced))
                .foregroundColor(fg)
            if showDate {
                Text(dateString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(fg.opacity(0.65))
            }
            if let wt = weatherText {
                Text(wt)
                    .font(.system(size: 11))
                    .foregroundColor(fg.opacity(0.45))
            }
        }
    }
}

// MARK: - Analog face

struct AnalogClockContent: View {
    let invertDisplay: Bool
    let now: Date
    let weatherText: String?

    private var fg: Color { invertDisplay ? .black : .white }

    private var components: (h: Double, m: Double, s: Double) {
        let c = Calendar.current
        return (Double(c.component(.hour,   from: now) % 12),
                Double(c.component(.minute, from: now)),
                Double(c.component(.second, from: now)))
    }

    var body: some View {
        GeometryReader { geo in
            let sz     = min(geo.size.width, geo.size.height)
            let cx     = geo.size.width  / 2
            let cy     = geo.size.height / 2
            let center = CGPoint(x: cx, y: cy)
            let r      = sz / 2 * 0.86
            let (h, m, s) = components

            ZStack {
                ForEach(0..<60, id: \.self) { i in
                    TickMark(center: center, radius: r,
                             angleDeg: Double(i) * 6 - 90,
                             length: i % 5 == 0 ? r * 0.12 : r * 0.06,
                             width:  i % 5 == 0 ? 2.5 : 1.0, color: fg)
                }
                HandView(center: center, angleDeg: (h + m / 60) * 30 - 90,
                         length: r * 0.50, width: 5.5, color: fg)
                HandView(center: center, angleDeg: (m + s / 60) * 6 - 90,
                         length: r * 0.72, width: 3, color: fg)
                HandView(center: center, angleDeg: s * 6 - 90,
                         length: r * 0.80, width: 1.5, color: .red)
                // Centre cap
                Circle()
                    .fill(fg)
                    .frame(width: 10, height: 10)
                    .position(center)
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                    .position(center)

                if let wt = weatherText {
                    Text(wt)
                        .font(.system(size: 10))
                        .foregroundColor(fg.opacity(0.55))
                        .position(x: cx, y: cy + r * 0.58)
                }
            }
        }
    }
}

struct TickMark: View {
    let center: CGPoint; let radius: CGFloat; let angleDeg: Double
    let length: CGFloat; let width: CGFloat; let color: Color
    var body: some View {
        let rad = angleDeg * .pi / 180
        let p1  = CGPoint(x: center.x + cos(rad) * (radius - length),
                          y: center.y + sin(rad) * (radius - length))
        let p2  = CGPoint(x: center.x + cos(rad) * radius,
                          y: center.y + sin(rad) * radius)
        return Path { p in p.move(to: p1); p.addLine(to: p2) }
            .stroke(color, lineWidth: width)
    }
}

struct HandView: View {
    let center: CGPoint; let angleDeg: Double
    let length: CGFloat; let width: CGFloat; let color: Color
    var body: some View {
        let rad  = angleDeg * .pi / 180
        let tip  = CGPoint(x: center.x + cos(rad) * length,
                           y: center.y + sin(rad) * length)
        let tail = CGPoint(x: center.x - cos(rad) * length * 0.18,
                           y: center.y - sin(rad) * length * 0.18)
        return Path { p in p.move(to: tail); p.addLine(to: tip) }
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

// MARK: - Watch info strip

struct WatchInfoStrip: View {
    let info: LunaSystemInfo
    var body: some View {
        HStack(spacing: 0) {
            infoCell(label: "KERNEL", value: info.kernelVersion)
            Divider().frame(height: 28).background(Color.white.opacity(0.1))
            infoCell(label: "BOOT",   value: info.bootVersion)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }
    @ViewBuilder
    private func infoCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.secondary)
            Text(value).font(.system(size: 13, weight: .medium, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared components

struct ConnectionBadge: View {
    @EnvironmentObject var ble: BLEManager
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ble.isConnected ? Color.green : Color.red)
                .frame(width: 7, height: 7)
                .shadow(color: (ble.isConnected ? Color.green : Color.red).opacity(0.6), radius: 4)
            Text(ble.state.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(ble.isConnected ? .green : .secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color.white.opacity(0.07))
        .cornerRadius(20)
    }
}

struct BatteryView: View {
    let percentage: Int
    private var color: Color { percentage > 50 ? .green : percentage > 20 ? .orange : .red }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon).font(.system(size: 13)).foregroundColor(color)
            Text("\(percentage)%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    private var batteryIcon: String {
        switch percentage {
        case 75...: return "battery.100"
        case 50...: return "battery.75"
        case 25...: return "battery.25"
        default:    return "battery.0"
        }
    }
}

struct LunaActionButton: View {
    let title: String; let icon: String; let color: Color
    var disabled: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(disabled ? Color.white.opacity(0.04) : color.opacity(0.13))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(disabled ? Color.white.opacity(0.08) : color.opacity(0.35), lineWidth: 1))
            .foregroundColor(disabled ? .gray : color)
        }
        .disabled(disabled)
    }
}

struct DeviceListView: View {
    @EnvironmentObject var ble: BLEManager
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEARBY DEVICES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            ForEach(ble.discoveredDevices, id: \.identifier) { dev in
                Button { ble.connect(dev) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 20))
                            .foregroundColor(accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dev.name ?? "Unknown Device")
                                .font(.system(size: 14, weight: .semibold))
                            Text(dev.identifier.uuidString.prefix(18))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
            }
        }
    }
}
