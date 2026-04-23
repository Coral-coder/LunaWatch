import SwiftUI

struct HealthView: View {
    @EnvironmentObject var health: HealthKitManager
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let dark   = Color(red: 0.07, green: 0.07, blue: 0.10)

    var body: some View {
        NavigationStack {
            ZStack {
                dark.ignoresSafeArea()
                if !health.isAuthorized {
                    HealthAuthView()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            StepRingCard()
                            WeeklyStepsCard()
                            SleepCard()
                            HealthMetricsRow()
                        }
                        .padding()
                        .padding(.bottom, 30)
                    }
                    .refreshable { health.fetchAll() }
                }
            }
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Auth prompt

struct HealthAuthView: View {
    @EnvironmentObject var health: HealthKitManager
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(accent)
            Text("Apple Health Access")
                .font(.title2.bold())
            Text("Luna Watch reads your steps and sleep from Apple Health and can write activity back to your Health profile.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            if let err = health.authError {
                Text(err).font(.caption).foregroundColor(.red).padding(.horizontal)
            }
            Button("Authorize Health Access") { health.requestAuthorization() }
                .font(.headline)
                .padding(.horizontal, 32).padding(.vertical, 14)
                .background(accent)
                .foregroundColor(.white)
                .cornerRadius(14)
        }
        .padding()
    }
}

// MARK: - Step ring

struct StepRingCard: View {
    @EnvironmentObject var health: HealthKitManager
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let goal = 10_000

    private var progress: Double { min(Double(health.todaySteps) / Double(goal), 1.0) }

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.15), lineWidth: 14)
                    .frame(width: 108, height: 108)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: 108, height: 108)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.0), value: progress)
                VStack(spacing: 0) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("goal").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(health.todaySteps.formatted())
                    .font(.system(size: 40, weight: .thin, design: .monospaced))
                Text("steps today")
                    .font(.subheadline).foregroundColor(.secondary)
                Text("Daily goal: \(goal.formatted())")
                    .font(.caption).foregroundColor(accent.opacity(0.8))
            }
            Spacer()
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - Weekly bar chart

struct WeeklyStepsCard: View {
    @EnvironmentObject var health: HealthKitManager
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)
    private let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private var maxCount: Int { max(health.weekSteps.map(\.count).max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THIS WEEK")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(health.weekSteps, id: \.date) { item in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(accent.opacity(item.count == 0 ? 0.15 : 0.75))
                            .frame(width: 32,
                                   height: max(CGFloat(item.count) / CGFloat(maxCount) * 72, 4))
                        Text(dayFmt.string(from: item.date))
                            .font(.system(size: 8)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90, alignment: .bottom)
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - Sleep

struct SleepCard: View {
    @EnvironmentObject var health: HealthKitManager
    @State private var showWriteSleep = false
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("SLEEP", systemImage: "bed.double.fill")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Log Sleep") { showWriteSleep = true }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent)
            }

            if let last = health.lastSleep {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(last.hoursMinutes)
                        .font(.system(size: 40, weight: .thin, design: .monospaced))
                    Text("last night")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                ForEach(health.recentSleep.prefix(5)) { session in
                    SleepRowView(session: session)
                }
            } else {
                Text("No sleep data found for the last 7 days.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .sheet(isPresented: $showWriteSleep) { WriteSleepSheet() }
    }
}

struct SleepRowView: View {
    let session: SleepRecord
    private let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE HH:mm"; return f }()
    private let endFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        HStack(spacing: 6) {
            Text(fmt.string(from: session.start))
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            Text("→").foregroundColor(.secondary)
            Text(endFmt.string(from: session.end))
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            Spacer()
            Text(session.hoursMinutes)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(accent)
        }
    }
}

struct WriteSleepSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var health: HealthKitManager
    @State private var sleepStart = Calendar.current.date(byAdding: .hour, value: -8,
                                                           to: Date()) ?? Date()
    @State private var sleepEnd = Date()
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        NavigationStack {
            Form {
                Section("SLEEP WINDOW") {
                    DatePicker("Fell Asleep", selection: $sleepStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Woke Up",     selection: $sleepEnd,   displayedComponents: [.date, .hourAndMinute])
                }
                .listRowBackground(Color.white.opacity(0.05))
                Section {
                    Button("Save to Apple Health") {
                        health.writeSleep(start: sleepStart, end: sleepEnd)
                        health.fetchSleep()
                        dismiss()
                    }
                    .foregroundColor(accent)
                    .listRowBackground(Color.white.opacity(0.05))
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Log Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.foregroundColor(accent)
            }}
        }
    }
}

// MARK: - Metrics row

struct HealthMetricsRow: View {
    @EnvironmentObject var health: HealthKitManager

    var body: some View {
        HStack(spacing: 12) {
            HealthTile(icon: "heart.fill",
                       label: "Heart Rate",
                       value: health.heartRate > 0 ? "\(Int(health.heartRate)) BPM" : "—",
                       color: .red)
            HealthTile(icon: "flame.fill",
                       label: "Active Cal",
                       value: health.activeCalories > 0
                           ? "\(Int(health.activeCalories)) kcal" : "—",
                       color: .orange)
        }
    }
}

struct HealthTile: View {
    let icon: String; let label: String; let value: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundColor(color).font(.title2)
            Text(value).font(.system(.headline, design: .monospaced))
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }
}
