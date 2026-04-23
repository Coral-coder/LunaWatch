import SwiftUI
import CoreBluetooth

struct BLEDebugView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var selectedTab: DebugTab = .gatt
    @State private var showHexSheet = false
    @State private var targetChar: CBCharacteristic?

    private let bg     = Color(red: 0.05, green: 0.05, blue: 0.07)
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let green  = Color(red: 0.2,  green: 0.9,  blue: 0.5)
    private let mono   = Font.system(.caption, design: .monospaced)

    enum DebugTab { case gatt, log }

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Header strip
                    HStack(spacing: 10) {
                        Circle()
                            .fill(ble.isConnected ? green : .red)
                            .frame(width: 8, height: 8)
                            .shadow(color: (ble.isConnected ? green : .red).opacity(0.7), radius: 5)
                        Text(ble.isConnected
                             ? (ble.connectedDevice?.name ?? "R33K0")
                             : ble.state.rawValue.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(ble.isConnected ? green : .secondary)
                        if ble.isConnected {
                            Text("RSSI \(ble.rssi) dBm")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if ble.isConnected {
                            Button("DISCONNECT") { ble.disconnect() }
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.red.opacity(0.8))
                        } else {
                            Toggle("ALL", isOn: $ble.showAllDevices)
                                .font(.system(size: 10, design: .monospaced))
                                .toggleStyle(.button)
                                .tint(accent.opacity(0.4))
                            Button("SCAN") { ble.startScanning() }
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.04))

                    // Tab bar
                    HStack(spacing: 0) {
                        tabBtn("GATT TREE", tab: .gatt)
                        tabBtn("EVENT LOG (\(ble.bleLog.count))", tab: .log)
                    }
                    .background(Color.white.opacity(0.03))

                    Divider().background(Color.white.opacity(0.08))

                    // Quick-fire command strip (only when connected)
                    if ble.isConnected {
                        QuickCommandBar()
                    }

                    // Content
                    if selectedTab == .gatt {
                        GATTTreeView(onWrite: { char in
                            targetChar = char
                            showHexSheet = true
                        })
                    } else {
                        EventLogView()
                    }
                }
            }
            .navigationTitle("BLE Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showHexSheet) {
            HexWriteSheet(characteristic: targetChar)
                .environmentObject(ble)
        }
    }

    @ViewBuilder
    private func tabBtn(_ label: String, tab: DebugTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(selectedTab == tab ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selectedTab == tab
                    ? Color(red: 0.38, green: 0.49, blue: 1.0).opacity(0.15)
                    : Color.clear)
        }
    }
}

// MARK: - GATT Tree

struct GATTTreeView: View {
    @EnvironmentObject var ble: BLEManager
    let onWrite: (CBCharacteristic) -> Void

    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let green  = Color(red: 0.2,  green: 0.9,  blue: 0.5)

    var body: some View {
        ScrollView {
            if ble.services.isEmpty {
                VStack(spacing: 16) {
                    if !ble.isConnected && !ble.discoveredDevices.isEmpty {
                        deviceList
                    } else if !ble.isConnected {
                        Text(ble.state == .scanning ? "Scanning…" : "Not connected")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.top, 60)
                    } else {
                        Text("Discovering services…")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.top, 60)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(ble.services) { svc in
                        ServiceRow(service: svc, onWrite: onWrite)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FOUND DEVICES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            ForEach(ble.discoveredDevices, id: \.identifier) { dev in
                Button { ble.connect(dev) } label: {
                    HStack {
                        Image(systemName: "wave.3.right").foregroundColor(accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dev.name ?? "Unknown")
                                .font(.system(size: 13, weight: .semibold))
                            Text(dev.identifier.uuidString.prefix(18))
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
                .padding(.horizontal, 16)
            }
        }
    }
}

struct ServiceRow: View {
    let service: DiscoveredService
    let onWrite: (CBCharacteristic) -> Void
    @State private var expanded = true
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var isLunaService: Bool {
        let u = service.id.uuidString.prefix(8).uppercased()
        return u == "81A50000" || u == "9E3B0000"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Service header
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isLunaService ? accent : Color.gray.opacity(0.4))
                        .frame(width: 3, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(service.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(isLunaService ? .white : .secondary)
                        Text(service.id.uuidString)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(isLunaService ? 0.06 : 0.02))
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(service.characteristics) { char in
                    CharacteristicRow(char: char, onWrite: onWrite)
                        .padding(.leading, 20)
                }
            }
        }
    }
}

struct CharacteristicRow: View {
    let char: DiscoveredCharacteristic
    let onWrite: (CBCharacteristic) -> Void
    @EnvironmentObject var ble: BLEManager

    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let green  = Color(red: 0.2,  green: 0.9,  blue: 0.5)
    private let orange = Color.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Property badges
                Text(char.propertySummary)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(badgeColor)
                    .cornerRadius(4)

                Text(char.id.uuidString)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                // Action buttons
                HStack(spacing: 6) {
                    if char.canRead {
                        iconBtn("arrow.down.circle", color: .cyan) {
                            ble.readValue(for: char.characteristic)
                        }
                    }
                    if char.canSubscribe {
                        iconBtn(char.isSubscribed ? "bell.fill" : "bell",
                                color: char.isSubscribed ? green : .secondary) {
                            ble.toggleNotify(for: char.characteristic)
                        }
                    }
                    if char.canWrite {
                        iconBtn("pencil.circle", color: accent) {
                            onWrite(char.characteristic)
                        }
                    }
                }
            }

            // Last received value
            if let val = char.lastValue, !val.isEmpty {
                let hex = val.map { String(format: "%02X", $0) }.joined(separator: " ")
                let ascii = String(val.map { ($0 >= 32 && $0 < 127) ? Character(UnicodeScalar($0)) : "." })
                VStack(alignment: .leading, spacing: 2) {
                    Text("HEX  \(hex)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(green)
                    Text("STR  \(ascii)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(green.opacity(0.7))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(green.opacity(0.07))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.02))
    }

    private var badgeColor: Color {
        if char.canSubscribe { return .green.opacity(0.8) }
        if char.canWrite     { return .orange.opacity(0.8) }
        return .gray.opacity(0.6)
    }

    @ViewBuilder
    private func iconBtn(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
        }
    }
}

// MARK: - Event Log

struct EventLogView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var autoScroll = true

    private let green  = Color(red: 0.2,  green: 0.9,  blue: 0.5)
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .font(.system(size: 10, design: .monospaced))
                    .toggleStyle(.button)
                    .tint(accent.opacity(0.3))
                Spacer()
                Button("CLEAR") { ble.clearLog() }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.red.opacity(0.7))
                Button {
                    let text = ble.bleLog.map { e in
                        "[\(e.timeString)] \(dirTag(e.direction)) \(e.shortUUID) \(e.hexString) \(e.message)"
                    }.joined(separator: "\n")
                    UIPasteboard.general.string = text
                } label: {
                    Label("COPY", systemImage: "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(ble.bleLog) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: ble.bleLog.count) { _ in
                    if autoScroll, let last = ble.bleLog.last {
                        withAnimation(.none) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func dirTag(_ d: BLELogDirection) -> String {
        switch d { case .rx: return "RX"; case .tx: return "TX"; case .info: return "--" }
    }
}

struct LogRow: View {
    let entry: BLELogEntry

    private var dirColor: Color {
        switch entry.direction {
        case .rx:   return Color(red: 0.2, green: 0.9, blue: 0.5)
        case .tx:   return Color(red: 0.38, green: 0.49, blue: 1.0)
        case .info: return Color.secondary
        }
    }
    private var dirLabel: String {
        switch entry.direction { case .rx: return "RX"; case .tx: return "TX"; case .info: return "--" }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.timeString)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 72, alignment: .leading)

            Text(dirLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(dirColor)
                .frame(width: 18)

            if let uuid = entry.charUUID {
                Text(uuid.uuidString.prefix(8))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 58, alignment: .leading)
            } else {
                Spacer().frame(width: 58)
            }

            VStack(alignment: .leading, spacing: 1) {
                if !entry.hexString.isEmpty {
                    Text(entry.hexString)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(dirColor)
                }
                if !entry.asciiString.isEmpty && entry.asciiString != entry.hexString {
                    Text(entry.asciiString)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(dirColor.opacity(0.6))
                }
                if !entry.message.isEmpty {
                    Text(entry.message)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(entry.direction == .rx ? Color.green.opacity(0.03) :
                    entry.direction == .tx ? Color.blue.opacity(0.03) : Color.clear)
    }
}

// MARK: - Hex Write Sheet

struct HexWriteSheet: View {
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) var dismiss
    let characteristic: CBCharacteristic?

    @State private var hexInput = ""
    @State private var errorMsg: String?
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    // These are raw hex payloads for the DATA TX channel (9e3b0001), framed automatically.
    // Format: [type LE u16][version LE u16][payload...]
    // type=0 COMMAND, type=1 TIME, type=9 SYSTEM_INFO, type=18 FRESH_START, etc.
    var presets: [(String, String)] = [
        ("Sys Info",    "00 00 02 00 02 00 02 00"),  // COMMAND v2, subcommand 2+2
        ("Battery",     "00 00 02 00 0D 00 01 00"),  // COMMAND v2, subcommand 13+1
        ("Fresh Start", "12 00 00 00"),               // FRESH_START v0
        ("Serial #",    "1A 00 00 00"),               // SERIAL_NUMBER v0
        ("Get UUID",    "17 00 00 00"),               // UUID v0
        ("Req Data",    "1D 00 00 00"),               // REQUEST_DATA v0
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {

                    if let char = characteristic {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TARGET CHARACTERISTIC")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(char.uuid.uuidString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(accent)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("HEX BYTES (space-separated)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        TextField("e.g.  01 02 FF A3", text: $hexInput)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(12)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(10)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                        if let err = errorMsg {
                            Text(err).font(.system(size: 11)).foregroundColor(.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRESETS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(presets, id: \.0) { label, hex in
                                Button {
                                    hexInput = hex
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(label)
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        Text(hex)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(accent.opacity(0.3), lineWidth: 1))
                                }
                                .foregroundColor(.white)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        send()
                    } label: {
                        Text("SEND")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(accent.opacity(0.2))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(accent.opacity(0.5), lineWidth: 1))
                    }
                    .foregroundColor(accent)
                }
                .padding(20)
            }
            .navigationTitle("Write Bytes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(accent)
                }
            }
        }
    }

    private func send() {
        errorMsg = nil
        let tokens = hexInput.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { errorMsg = "Enter at least one byte"; return }
        var bytes: [UInt8] = []
        for t in tokens {
            guard let b = UInt8(t, radix: 16) else {
                errorMsg = "Invalid hex token: \(t)"; return
            }
            bytes.append(b)
        }
        let data = Data(bytes)
        if let char = characteristic {
            // Targeted write to a specific char — send raw
            ble.send(data, to: char)
        } else {
            // No target — route through framing protocol on DATA TX channel
            if let msg = LunaMessage(raw: data) {
                ble.sendMessage(msg)
            } else {
                errorMsg = "Need ≥4 bytes for a framed message (type u16 + version u16 + payload)"
                return
            }
        }
        dismiss()
    }
}

// MARK: - Quick Command Bar

struct QuickCommandBar: View {
    @EnvironmentObject var ble: BLEManager
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    private let commands: [(String, () -> LunaMessage)] = [
        ("SYS INFO",    { .getSystemInfo() }),
        ("BATTERY",     { .getBattery() }),
        ("TIME SYNC",   { .syncTime() }),
        ("FRESH START", { .freshStart() }),
        ("SERIAL #",    { .getSerialNumber() }),
        ("UUID",        { .getUUID() }),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(commands, id: \.0) { label, builder in
                    Button {
                        ble.sendMessage(builder())
                    } label: {
                        Text(label)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(accent.opacity(0.1))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(accent.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.white.opacity(0.03))
    }
}
