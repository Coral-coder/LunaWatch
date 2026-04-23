# LunaWatch

An open-source iOS companion app for the **Vector Luna** smartwatch — fully reverse-engineered from the original Android APK, rebuilt from scratch in Swift/SwiftUI.

The Vector Watch company was acquired by Fitbit in 2017 and all cloud services were shut down. This project brings the Luna back to life on iPhone with no cloud dependency required.

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Background

The Vector Luna is a minimal e-ink smartwatch with a round display. It communicates over Bluetooth LE using a proprietary framing protocol discovered through:

- Live sniffing with **nRF Connect** (the watch advertises as `R33K0`, not "Vector" or "Luna")
- Decompilation of the original **VectorWatch Android APK v2.0.2** using jadx
- Analysis of `DefaultTransformer.java`, `DateTimeUtils.java`, `Constants.java`, and all BLE command classes

All protocol findings are documented in [`PROTOCOL.md`](PROTOCOL.md).

---

## Hardware

| Property | Value |
|---|---|
| Advertised Name | `R33K0` |
| Display | Round e-ink |
| BLE Service 1 | `81A50000-9EBD-0436-3358-BB370C7DA4C5` (notifications, raw) |
| BLE Service 2 | `9E3B0000-D7AB-ADF3-F683-BAA2A0E81612` (data, framed) |
| Time Epoch | Y2K — seconds since 2000-01-01 00:00:00 UTC |
| Backlight Levels | 3 (Low / Medium / High, values 0–2) |

---

## What's Working ✅

### Bluetooth
- Auto-connect to already-paired watch on app launch (no scan needed)
- Remembers last device UUID across launches
- Full framing protocol: 20-byte BLE packets, header byte, single/first/middle/last fragment states
- Rolling BLE event log with hex + ASCII display

### Watch Sync
- Time sync (Y2K epoch, timezone offset, DST)
- System info (firmware version, boot ROM version)
- Battery level
- Serial number + UUID retrieval
- Fresh start / reconnect handshake
- Activity data (steps, calories, distance, 15-minute buckets)
- Push settings to watch (see Settings below)

### Settings (pushed over BLE)
- 24-hour / 12-hour clock
- Metric / Imperial units
- Raise-to-wake (glance mode)
- Do Not Disturb
- Backlight intensity (Low / Medium / High — corrected 0–2 hardware range)
- Backlight timeout (2 / 5 / 10 / 20 / 30 seconds)
- Second hand on/off
- Notification mode (All / Priority / Off)
- Watch name / user profile sync
- Alarms (create, enable/disable, sync up to 8 to watch)
- Goals (steps, calories, distance, sleep)

### Notifications
- Relay custom notifications to watch over BLE (SMS, social, incoming call, missed call)
- Full detail-request handshake on the secondary channel (`81A50001` / `81A50002` / `81A50003`)
- Live display of last watch button press (up / middle / down, single / double / long)

### Health (HealthKit)
- Today's step count with goal ring
- Weekly steps bar chart
- Sleep sessions with duration
- Manual sleep logging to Apple Health
- Heart rate + active calories display
- Watch sensor data card (live steps, kcal, km, sleep from watch)
- Pull-to-refresh

### Watch Face (in-app preview)
- Round watch preview with metallic bezel + crown
- Digital and analog modes (analog includes second hand)
- Invert display toggle
- Date and weather overlays
- Syncs face preferences to watch

### Library & Package System
- Import watchface / app packages from local JSON catalogs
- Parse offline catalogs extracted from the original APK
- VFTP file transfer to watch (PUT → DATA chunks → STATUS handshake)
- Queue-based transfer manager with progress tracking
- Transfer watchface binaries and resource files directly to watch

### Feeds
- Live weather (current conditions, temperature)
- Stock prices
- News headlines

### Debug Tab
- Full GATT tree explorer (services + characteristics)
- Read / subscribe / write any characteristic
- Hex write sheet with preset quick commands
- Quick command bar (Sys Info, Battery, Time Sync, Fresh Start, Serial, UUID)
- Filterable event log with copy-all

---

## In Progress / Known Gaps 🔧

### Watch Face Designer
- UI for composing a custom watch face (clock mode, date, weather, invert) is built
- **Missing:** Rendering the design to a bitmap and pushing it to the watch via VFTP
- **Missing:** Full element-level designer (hands, fonts, backgrounds)

### App & Watchface Ordering
- Watch supports rearranging installed apps/watchfaces (BLE message type 16)
- **Missing:** UI to drag-reorder and push new order to watch

### App Management
- VFTP install works end-to-end
- **Missing:** Uninstall command
- **Missing:** App-specific settings UI (the original Android app had per-app settings screens)

### Activity Detail View
- Raw 15-minute activity buckets are received and stored
- **Missing:** Per-bucket chart, goal progress rings, daily breakdown screen

### Goal Setting UI
- Goals are pushed to the watch programmatically
- **Missing:** In-app screen to set custom step / calorie / sleep targets

### Calendar Sync
- `syncUpcomingCalendarEvents()` is implemented (reads next 7 days from EventKit)
- **Missing:** UI to trigger sync and show which events were sent

### Watch Logs
- The watch can send its own diagnostic logs over BLE
- **Missing:** Log retrieval command and viewer UI

### Firmware OTA
- VFTP protocol supports binary transfers large enough for firmware
- **Missing:** Bootloader / kernel update flow (requires finding firmware binaries)

### Streams & Complications
- The original Android app supported live data streams (weather, sports, etc.) placed as complications on watch faces
- **Status:** Not implemented — requires the defunct Vector cloud API

---

## Architecture

```
Sources/
├── App/
│   └── LunaWatchApp.swift          # App entry, environment object wiring
├── Core/
│   ├── BLEManager.swift            # CoreBluetooth, scanning, framing, auto-reconnect
│   ├── LunaProtocol.swift          # All message types, framer, unframer, parsed structs
│   ├── WatchSyncManager.swift      # Post-connect sync sequence, message dispatcher
│   ├── VFTPTransferManager.swift   # File transfer queue (watchfaces, apps)
│   ├── LunaPackageCatalogManager.swift  # Watchface/app catalog import + VFTP payload builder
│   ├── WatchFaceManager.swift      # Watch face settings + image renderer
│   ├── WatchFaceDesignerManager.swift  # Custom watch face draft persistence
│   ├── HealthKitManager.swift      # HealthKit read/write
│   ├── WeatherManager.swift        # Weather API
│   ├── StocksManager.swift         # Stock price feed
│   └── NewsManager.swift           # News feed
└── UI/
    ├── WatchFaceView.swift         # Main watch tab — round bezel preview, connect/scan
    ├── HealthView.swift            # Health tab — steps, sleep, metrics
    ├── LibraryAndDesignerView.swift # Library tab — catalog browser, install, designer
    ├── NotificationsView.swift     # Alerts tab — send notifications, button press display
    ├── SettingsView.swift          # Settings sheet — all watch preferences, alarms
    ├── DataFeedsView.swift         # Feeds tab — weather, stocks, news
    └── BLEDebugView.swift          # Debug tab — GATT tree, event log, hex writer
```

---

## Protocol Notes

See [`PROTOCOL.md`](PROTOCOL.md) for the complete reverse-engineered protocol including:
- All 26 BLE message types with exact wire format
- Framing algorithm (20-byte packets, header encoding)
- Notification detail-request handshake flow
- VFTP file transfer sub-protocol
- All known setting type IDs and value ranges
- Y2K time epoch conversion

---

## Building

1. Clone the repo
2. Open `LunaWatch.xcodeproj` in Xcode 15+
3. Set your development team in project settings
4. Build and run on a real device (Bluetooth does not work in Simulator)
5. Enable Bluetooth and HealthKit permissions when prompted

The watch will be discovered automatically if already paired to your iPhone's Bluetooth, or you can tap **Scan** to find it fresh. It advertises as `R33K0`.

---

## Contributing

This is a community reverse-engineering project. If you have a Vector Luna and can capture new BLE traffic, compare notes on protocol details, or implement any of the missing features above — PRs are very welcome.

The most impactful open items:
1. Watch face designer rendering + VFTP push
2. Activity detail + goal setting UI
3. App ordering and uninstall
4. Watch log retrieval

---

## Acknowledgements

- [vector-watch-hacking](https://github.com/deuill/vector-watch-hacking) — early hardware teardown and notes
- nRF Connect — live BLE sniffing
- jadx — Android APK decompilation
- The Vector Watch community for keeping interest in this hardware alive
