import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var vibrateOnMessage = UserDefaults.standard.bool(forKey: "luna.vibrate.msg") {
        didSet { UserDefaults.standard.set(vibrateOnMessage, forKey: "luna.vibrate.msg") }
    }
    @State private var vibrateOnEmail = UserDefaults.standard.bool(forKey: "luna.vibrate.email") {
        didSet { UserDefaults.standard.set(vibrateOnEmail, forKey: "luna.vibrate.email") }
    }
    @State private var vibrateOnCall = UserDefaults.standard.bool(forKey: "luna.vibrate.call") {
        didSet { UserDefaults.standard.set(vibrateOnCall, forKey: "luna.vibrate.call") }
    }

    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let dark   = Color(red: 0.07, green: 0.07, blue: 0.10)

    var body: some View {
        NavigationStack {
            ZStack {
                dark.ignoresSafeArea()
                List {
                    // Info banner
                    Section {
                        AlertInfoBanner()
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    // Watch alerts
                    Section("WATCH ALERTS") {
                        Toggle("Vibrate on Message",  isOn: $vibrateOnMessage)
                        Toggle("Vibrate on Email",    isOn: $vibrateOnEmail)
                        Toggle("Vibrate on Phone Call", isOn: $vibrateOnCall)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    .tint(accent)

                    // Deep links
                    Section("OPEN APPS") {
                        AppDeepLinkRow(icon: "message.fill",   color: .green,
                                       label: "Messages", urlStr: "sms:")
                        AppDeepLinkRow(icon: "envelope.fill",  color: accent,
                                       label: "Mail",     urlStr: "message:")
                        AppDeepLinkRow(icon: "phone.fill",     color: .green,
                                       label: "Phone",    urlStr: "tel:")
                        AppDeepLinkRow(icon: "safari.fill",    color: .orange,
                                       label: "Safari",   urlStr: "https://")
                    }
                    .listRowBackground(Color.white.opacity(0.05))

                    // Manual buzz
                    Section("MANUAL TEST") {
                        Button {
                            // Send vibrate command over BLE — replace 0x01 0x01 with
                            // confirmed Luna watch vibrate opcode once protocol is known.
                            ble.send(Data([0x01, 0x01]))
                        } label: {
                            Label("Test Watch Vibration",
                                  systemImage: "iphone.radiowaves.left.and.right")
                                .foregroundColor(ble.isConnected ? accent : .secondary)
                        }
                        .disabled(!ble.isConnected)
                        .listRowBackground(Color.white.opacity(0.05))

                        if !ble.isConnected {
                            Label("Connect your Luna watch first.",
                                  systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    }

                    // Limitation note
                    Section {
                        Text("""
iOS does not allow third-party apps to read the content of iMessages, SMS, or Mail. \
Luna Watch can deep-link you directly to those apps and vibrate the watch while this \
app is in the foreground. For full notification mirroring, keep the app running.
""")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .listRowBackground(Color.white.opacity(0.03))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct AlertInfoBanner: View {
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 34))
                .foregroundColor(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notification Alerts").font(.headline)
                Text("Your Luna watch vibrates when messages, emails, or calls arrive.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(accent.opacity(0.1))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 4).padding(.vertical, 6)
    }
}

struct AppDeepLinkRow: View {
    let icon: String
    let color: Color
    let label: String
    let urlStr: String

    var body: some View {
        Button {
            if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
        } label: {
            HStack {
                Image(systemName: icon).foregroundColor(color).frame(width: 24)
                Text("Open \(label)")
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundColor(.secondary)
            }
        }
        .foregroundColor(.primary)
    }
}
