import SwiftUI
import PhotosUI

struct WatchFaceView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var faceManager: WatchFaceManager
    @EnvironmentObject var weather: WeatherManager

    @State private var showSettings = false
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let dark   = Color(red: 0.07, green: 0.07, blue: 0.10)

    var body: some View {
        NavigationStack {
            ZStack {
                dark.ignoresSafeArea()
                VStack(spacing: 20) {
                    // Status bar
                    HStack {
                        Spacer()
                        ConnectionBadge()
                    }
                    .padding(.horizontal, 20)

                    // Clock preview
                    ClockFaceView(
                        mode: faceManager.settings.clockMode,
                        invertDisplay: faceManager.settings.invertDisplay,
                        backgroundPhotoData: faceManager.settings.backgroundPhotoData,
                        weatherText: faceManager.settings.showWeather
                            ? weather.condition?.watchText : nil,
                        showDate: faceManager.settings.showDate,
                        now: tick
                    )
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: accent.opacity(0.25), radius: 24)

                    // Mode toggle
                    Picker("Clock Mode", selection: $faceManager.settings.clockMode) {
                        ForEach(ClockMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)

                    // Action grid
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            LunaButton(
                                title: "SYNC WATCH",
                                icon: "arrow.triangle.2.circlepath",
                                color: accent,
                                disabled: !ble.isConnected
                            ) {
                                let img = faceManager.renderFaceImage(
                                    weatherText: weather.condition?.watchText)
                                // Encode and transmit via BLE — protocol TBD
                                _ = img
                            }
                            LunaButton(title: "SETTINGS", icon: "slider.horizontal.3", color: accent) {
                                showSettings = true
                            }
                        }
                        HStack(spacing: 10) {
                            if ble.isConnected {
                                LunaButton(title: "DISCONNECT",
                                           icon: "antenna.radiowaves.left.and.right.slash",
                                           color: .red.opacity(0.8)) {
                                    ble.disconnect()
                                }
                            } else {
                                LunaButton(title: ble.state == .scanning ? "SCANNING…" : "SCAN",
                                           icon: "antenna.radiowaves.left.and.right",
                                           color: accent) {
                                    ble.startScanning()
                                }
                            }
                            if ble.isConnected {
                                LunaButton(title: "BUZZ WATCH",
                                           icon: "iphone.radiowaves.left.and.right",
                                           color: .orange) {
                                    ble.send(Data([0x01, 0x01]))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Discovered devices
                    if !ble.discoveredDevices.isEmpty && !ble.isConnected {
                        DeviceListView()
                    }

                    Spacer()
                }
            }
            .navigationTitle("Luna Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                WatchFaceSettingsSheet()
                    .environmentObject(faceManager)
            }
            .onReceive(timer) { t in tick = t }
        }
    }
}

// MARK: - Clock face SwiftUI component

struct ClockFaceView: View {
    let mode: ClockMode
    let invertDisplay: Bool
    let backgroundPhotoData: Data?
    let weatherText: String?
    let showDate: Bool
    let now: Date

    var body: some View {
        ZStack {
            Group {
                if let data = backgroundPhotoData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .overlay(Color.black.opacity(0.45))
                } else {
                    invertDisplay ? Color.white : Color.black
                }
            }

            if mode == .digital {
                DigitalClockContent(invertDisplay: invertDisplay, now: now,
                                    weatherText: weatherText, showDate: showDate)
            } else {
                AnalogClockContent(invertDisplay: invertDisplay, now: now,
                                   weatherText: weatherText)
            }
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
        VStack(spacing: 6) {
            Text(timeString)
                .font(.system(size: 56, weight: .thin, design: .monospaced))
                .foregroundColor(fg)
            if showDate {
                Text(dateString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(fg.opacity(0.7))
            }
            if let wt = weatherText {
                Text(wt)
                    .font(.system(size: 12))
                    .foregroundColor(fg.opacity(0.5))
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
            let r      = sz / 2 * 0.84
            let (h, m, s) = components

            ZStack {
                ForEach(0..<60, id: \.self) { i in
                    TickMark(center: center, radius: r, angleDeg: Double(i) * 6 - 90,
                             length: i % 5 == 0 ? r * 0.13 : r * 0.07,
                             width: i % 5 == 0 ? 2.5 : 1, color: fg)
                }
                HandView(center: center, angleDeg: (h + m / 60) * 30 - 90,
                         length: r * 0.50, width: 5, color: fg)
                HandView(center: center, angleDeg: (m + s / 60) * 6 - 90,
                         length: r * 0.72, width: 3, color: fg)
                HandView(center: center, angleDeg: s * 6 - 90,
                         length: r * 0.80, width: 1.5, color: .red)
                Circle().fill(fg).frame(width: 9, height: 9).position(center)

                if let wt = weatherText {
                    Text(wt)
                        .font(.system(size: 11))
                        .foregroundColor(fg.opacity(0.6))
                        .position(x: cx, y: cy + r * 0.62)
                }
            }
        }
    }
}

struct TickMark: View {
    let center: CGPoint
    let radius: CGFloat
    let angleDeg: Double
    let length: CGFloat
    let width: CGFloat
    let color: Color

    var body: some View {
        let rad = angleDeg * .pi / 180
        let p1  = CGPoint(x: center.x + CGFloat(cos(rad)) * (radius - length),
                          y: center.y + CGFloat(sin(rad)) * (radius - length))
        let p2  = CGPoint(x: center.x + CGFloat(cos(rad)) * radius,
                          y: center.y + CGFloat(sin(rad)) * radius)
        return Path { p in p.move(to: p1); p.addLine(to: p2) }
            .stroke(color, lineWidth: width)
    }
}

struct HandView: View {
    let center: CGPoint
    let angleDeg: Double
    let length: CGFloat
    let width: CGFloat
    let color: Color

    var body: some View {
        let rad  = angleDeg * .pi / 180
        let tip  = CGPoint(x: center.x + CGFloat(cos(rad)) * length,
                           y: center.y + CGFloat(sin(rad)) * length)
        let tail = CGPoint(x: center.x - CGFloat(cos(rad)) * length * 0.18,
                           y: center.y - CGFloat(sin(rad)) * length * 0.18)
        return Path { p in p.move(to: tail); p.addLine(to: tip) }
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

// MARK: - Shared sub-components

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

struct LunaButton: View {
    let title: String
    let icon: String
    let color: Color
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(disabled ? Color.white.opacity(0.05) : color.opacity(0.15))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(disabled ? Color.white.opacity(0.1) : color.opacity(0.4), lineWidth: 1))
            .foregroundColor(disabled ? .gray : color)
        }
        .disabled(disabled)
    }
}

struct DeviceListView: View {
    @EnvironmentObject var ble: BLEManager
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEARBY LUNA DEVICES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            ForEach(ble.discoveredDevices, id: \.identifier) { dev in
                Button { ble.connect(dev) } label: {
                    HStack {
                        Image(systemName: "applewatch").foregroundColor(accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dev.name ?? "Luna Watch")
                                .font(.system(size: 13, weight: .semibold))
                            Text(dev.identifier.uuidString.prefix(8))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Settings sheet

struct WatchFaceSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var faceManager: WatchFaceManager
    @State private var selectedPhoto: PhotosPickerItem?
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        NavigationStack {
            Form {
                Section("CLOCK STYLE") {
                    Picker("Mode", selection: $faceManager.settings.clockMode) {
                        ForEach(ClockMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.white.opacity(0.05))
                    Toggle("Invert Display", isOn: $faceManager.settings.invertDisplay)
                        .listRowBackground(Color.white.opacity(0.05))
                }

                Section("OVERLAYS") {
                    Toggle("Show Weather", isOn: $faceManager.settings.showWeather)
                    Toggle("Show Date",    isOn: $faceManager.settings.showDate)
                }
                .listRowBackground(Color.white.opacity(0.05))

                Section("BACKGROUND PHOTO") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(
                            faceManager.settings.backgroundPhotoData != nil
                                ? "Change Photo" : "Set Background Photo",
                            systemImage: "photo.on.rectangle.angled"
                        )
                        .foregroundColor(accent)
                    }
                    .onChange(of: selectedPhoto) { item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self) {
                                faceManager.settings.backgroundPhotoData = data
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))

                    if let data = faceManager.settings.backgroundPhotoData,
                       let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(height: 120).clipped()
                            .cornerRadius(8)
                            .listRowBackground(Color.clear)
                    }

                    if faceManager.settings.backgroundPhotoData != nil {
                        Button("Remove Photo", role: .destructive) {
                            faceManager.settings.backgroundPhotoData = nil
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Watch Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(accent)
                }
            }
        }
    }
}
