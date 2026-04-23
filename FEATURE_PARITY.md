# LunaWatch Feature Parity (Android Decompiled -> iOS)

This document maps the decompiled Android app (`output/sources/com/vectorwatch/android`) to the current iOS `LunaWatch` app and explains how each feature works.

## Implemented in iOS (now)

- **BLE transport + protocol framing**
  - iOS has full CoreBluetooth scanning/connection, GATT discovery, notify/indicate subscriptions, and TX/RX logs.
  - Luna protocol framing/unframing is implemented for the data channel (`9E3B...`), including multi-packet BLE messages.

- **Watch handshake and baseline sync**
  - On connect, iOS now sends: `freshStart`, `syncTime`, `getSystemInfo`, `getBattery`, `getActivity`, `getSerialNumber`, `getUUID`.
  - After handshake, iOS pushes saved profile/settings, alarms, goals, and calendar events.

- **Settings sync (Android `SyncSettingsCommand` parity subset)**
  - iOS syncs hour mode, unit system, glance, DND, backlight, second hand, watch name, and notifications mode.
  - Uses settings IDs matching Android constants (`0`, `6`, `7`, `14`, `16`, `18`, `20`, `24`).

- **Alarms sync (Android `SyncAlarmsCommand`)**
  - iOS persists local alarms and sends them in the same wire shape: count, triplets `(hour, minute, enabled)`, then name lengths + names.
  - Enforced max of 8 alarms (watch limit).

- **Goals sync (Android `SyncGoalsCommand`)**
  - iOS now sends step/calorie/distance/sleep goals.
  - Sleep goal uses Android behavior (`minutes * 4`) before transmit.

- **Calendar sync (Android `SyncCalendarCommand`)**
  - iOS now requests EventKit access and pushes upcoming timed events for the next 7 days.
  - Payload format follows Android command behavior: index + start/end vector timestamps + null-terminated title/location.

- **Notification relay + detail handshake**
  - iOS sends notification headers on `81A50003`, responds to detail requests over `81A50002`, and stores pending notification bodies for lookup.

- **Health, feeds, and watch UX**
  - Existing iOS features already include HealthKit cards, weather/stocks/news feeds, watch preview, settings, and BLE debug tooling.

## Present in Decompiled Android, Not Yet Implemented on iOS

- **Cloud account system**
  - Login/recover password/account profile/cloud sync (`AccountHandler`, onboarding activities, cloud update services).

- **Store ecosystem**
  - Full watch app/store browse/search/rating/install workflows (`store/*`, app metadata fetchers, rating screens).

- **App install/VFTP management completeness**
  - iOS has protocol primitives for VFTP messages but no complete install/update UX and transfer state machine parity yet.

- **Incoming call/SMS/social auto-capture**
  - Android had OS-level receivers/services for system notifications and telephony; iOS sandbox limits this significantly.
  - iOS currently supports manual/foreground relay + deep links.

- **Background receivers/schedulers**
  - Android boot/time/network/bluetooth receivers and periodic triggers are not 1:1 portable to iOS app lifecycle.

- **Advanced activity graphing and historical cloud data**
  - Android has richer chart interactor/database stack and alert models that are only partially reflected in current iOS UI.

- **Watch cloud app management**
  - Streams/cloud apps install/settings/auth flow (`CloudAppsManager`, `StreamsManager`, auth async tasks) not yet ported.

## How Key Features Work in iOS

- **Connection**
  - `BLEManager` auto-reconnects saved peripheral UUID, falls back to scanning, discovers all services/chars, and auto-subscribes notify/indicate characteristics.

- **Protocol**
  - `LunaProtocol` serializes messages as `[type LE u16][version LE u16][payload]`.
  - `LunaFramer` splits payload into 20-byte BLE frames with Vector fragment headers; `LunaUnframer` reassembles incoming fragments.

- **Sync orchestration**
  - `WatchSyncManager` owns post-connect sequencing and incoming message dispatch.
  - It parses battery/system/activity/button/serial/uuid responses and updates published app state.

- **Settings + alarms + goals + calendar**
  - `SettingsView` edits persisted `LunaSettings`.
  - Sync actions call `WatchSyncManager` methods that build exact wire payloads and send them through `BLEManager`.

## Recommended Next Porting Milestones

1. Build a complete VFTP transfer manager with progress, retries, and ACK/state handling.
2. Add app/store metadata model + basic install queue (without ratings/auth first).
3. Expand settings parity to all Android dirty-field options and localization values.
4. Add background refresh strategy for feeds/health/calendar within iOS constraints.
5. Add integration tests for protocol builders against captured Android payload fixtures.

## Newly Added VFTP + Catalog + Designer (this pass)

- **VFTP queue manager in iOS**
  - Added `VFTPTransferManager` with 128-byte chunking, queued sends, state tracking, and status handling.
  - Supports `force` + `compressed` flags and file types for app/resource payload transfer.

- **Prebuilt package catalog integration**
  - Added `LunaPackageCatalogManager` to load/import offline catalogs and parse app/watchface package payloads.
  - Supports loading the decompiled offline JSON catalogs and converting entries into transfer payloads.

- **Install/import UI**
  - Added a new app tab `Library` for:
    - loading prebuilt round/square watchface/app catalogs,
    - importing catalog JSON files,
    - sending package payloads to the watch over VFTP,
    - viewing transfer queue/state.

- **In-app watchface designer scaffold**
  - Added `WatchFaceDesignerManager` with draft creation/edit/delete.
  - Drafts can be previewed in the Watch tab and exported to watch as rendered PNG resource via VFTP.
  - This is a practical designer MVP; full compiled-watchface binary generation is still future work.
