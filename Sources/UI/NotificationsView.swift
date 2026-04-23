import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var ble:       BLEManager
    @EnvironmentObject var watchSync: WatchSyncManager

    @State private var customTitle   = ""
    @State private var customMessage = ""
    @State private var selectedKind  = 0   // index into kinds[]

    private let kinds: [(label: String, icon: String, kind: LunaNotification.Kind)] = [
        ("Message",     "message.fill",              .sms),
        ("Social",      "person.2.fill",             .social),
        ("Incoming",    "phone.fill",                .incomingCall),
        ("Missed Call", "phone.arrow.down.left.fill", .missedCall),
    ]

    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let dark   = Color(red: 0.07, green: 0.07, blue: 0.10)

    var body: some View {
        NavigationStack {
            ZStack {
                dark.ignoresSafeArea()
                List {
                    // Status banner
                    Section {
                        AlertInfoBanner(isConnected: ble.isConnected)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    // Last button press from watch
                    if let press = watchSync.lastButtonPress {
                        Section {
                            HStack(spacing: 14) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Last Watch Input")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(press.button) button — \(press.event)")
                                        .font(.system(.headline, design: .monospaced))
                                }
                            }
                            .padding(.vertical, 4)
                        } header: {
                            sectionHeader("WATCH INPUT")
                        }
                        .listRowBackground(accent.opacity(0.08))
                    }

                    // Send notification to watch
                    Section {
                        // Kind picker as icon row
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(kinds.indices, id: \.self) { i in
                                    let k = kinds[i]
                                    Button {
                                        selectedKind = i
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: k.icon)
                                                .font(.system(size: 20))
                                                .foregroundColor(selectedKind == i ? .white : accent)
                                            Text(k.label)
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(selectedKind == i ? .white : .secondary)
                                        }
                                        .frame(width: 68, height: 64)
                                        .background(selectedKind == i ? accent : accent.opacity(0.12))
                                        .cornerRadius(12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                        TextField("Title / Sender", text: $customTitle)
                        TextField("Message body",   text: $customMessage)

                        Button {
                            sendNotification()
                        } label: {
                            Label(ble.isConnected ? "Send to Watch" : "Watch Not Connected",
                                  systemImage: "applewatch.radiowaves.left.and.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .foregroundColor(ble.isConnected ? .white : .secondary)
                        }
                        .padding(.vertical, 4)
                        .disabled(!ble.isConnected)
                        .listRowBackground(ble.isConnected ? accent : Color.white.opacity(0.05))
                    } header: {
                        sectionHeader("SEND TO WATCH")
                    }
                    .listRowBackground(Color.white.opacity(0.05))

                    // Quick vibrate test
                    Section {
                        Button {
                            watchSync.sendNotification(
                                kind:    .sms,
                                appName: "Test",
                                title:   "Vibrate test",
                                message: "Luna Watch iOS"
                            )
                        } label: {
                            Label("Test Watch Vibration",
                                  systemImage: "iphone.radiowaves.left.and.right")
                                .foregroundColor(ble.isConnected ? accent : .secondary)
                        }
                        .disabled(!ble.isConnected)
                    } header: {
                        sectionHeader("QUICK TEST")
                    }
                    .listRowBackground(Color.white.opacity(0.05))

                    // Deep-link shortcuts
                    Section {
                        AppDeepLinkRow(icon: "message.fill",  color: .green,
                                       label: "Messages",  urlStr: "sms:")
                        AppDeepLinkRow(icon: "envelope.fill", color: accent,
                                       label: "Mail",      urlStr: "message:")
                        AppDeepLinkRow(icon: "phone.fill",    color: .green,
                                       label: "Phone",     urlStr: "tel:")
                        AppDeepLinkRow(icon: "safari.fill",   color: .orange,
                                       label: "Safari",    urlStr: "https://")
                    } header: {
                        sectionHeader("OPEN APPS")
                    }
                    .listRowBackground(Color.white.opacity(0.05))

                    // iOS limitation note
                    Section {
                        Text("""
iOS does not allow third-party apps to read iMessage, SMS, or Mail content. \
Luna Watch can deep-link to those apps and buzz the watch for any notification \
you manually send while the app is running.
""")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .listRowBackground(Color.white.opacity(0.03))
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Helpers

    private func sendNotification() {
        let k = kinds[selectedKind]
        watchSync.sendNotification(
            kind:    k.kind,
            appName: k.label,
            title:   customTitle.isEmpty   ? k.label        : customTitle,
            message: customMessage.isEmpty ? "Luna Watch iOS" : customMessage
        )
        customTitle   = ""
        customMessage = ""
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Color(red: 0.38, green: 0.49, blue: 1.0).opacity(0.85))
    }
}

// MARK: - Status banner

struct AlertInfoBanner: View {
    let isConnected: Bool
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isConnected ? accent.opacity(0.2) : Color.secondary.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: isConnected ? "applewatch.radiowaves.left.and.right"
                                              : "applewatch.slash")
                    .font(.system(size: 24))
                    .foregroundColor(isConnected ? accent : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(isConnected ? "Watch Connected" : "Watch Disconnected")
                    .font(.headline)
                Text(isConnected
                     ? "You can send notifications and vibrate the watch."
                     : "Connect your Luna watch in the Watch tab first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background((isConnected ? accent : Color.secondary).opacity(0.08))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke((isConnected ? accent : Color.secondary).opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 4).padding(.vertical, 6)
    }
}

// MARK: - App deep-link row

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
                Image(systemName: icon).foregroundColor(color).frame(width: 26)
                Text("Open \(label)")
                Spacer()
                Image(systemName: "arrow.up.right.square").foregroundColor(.secondary)
            }
        }
        .foregroundColor(.primary)
    }
}
