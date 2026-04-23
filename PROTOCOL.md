# Vector Luna BLE Protocol — Reverse Engineering Notes

Community findings from reverse engineering the Vector Luna smartwatch (advertises as `R33K0`).  
Sources: nRF Connect live scan + full decompilation of **VectorWatch Android APK v2.0.2**.

---

## Hardware

| Component | Detail |
|-----------|--------|
| MCU | Atmel ATSAM4LC8BA-U (ARM Cortex-M4, low-power LCD-optimized) |
| BLE chip | Unknown (separate die, not identified from teardown photos) |
| USB | Vendor ID `03eb:2423` (Atmel Corp.) |
| Display | 160×160 pixels |

The firmware (bootloader + kernel) is embedded in the Android APK as Base64 blobs with a **permuted alphabet** (non-standard Base64 character order). Post-decode the binary is additionally compressed or encrypted — algorithm unknown.

---

## BLE Advertisement

The watch advertises as **`R33K0`** (not "Vector" or "Luna").  
Advertised service: `81A50000-9EBD-0436-3358-BB370C7DA4C5`

---

## GATT Table

### Standard Services

| Service | UUID |
|---------|------|
| Generic Access | `1800` |
| Generic Attribute | `1801` |
| Tx Power | `1804` |
| Device Information | `180A` |

### Service 1 — Command / Notification  (`81A50000-9EBD-0436-3358-BB370C7DA4C5`, advertised)

| Char name (APK) | UUID | Properties | Role |
|-----------------|------|------------|------|
| BLE_SHIELD_TX | `81A50002-…` | Write Without Response | Commands **phone → watch** |
| BLE_SHIELD_RX | `81A50001-…` | Indicate | Notification detail requests **watch → phone** |
| BLE_SHIELD_TX_NOT_INFO | `81A50003-…` | Write Without Response | Push notifications **phone → watch** |

> `81A50001` (Indicate) is used by the watch to request more details about a notification — it is **not** a general command-response channel.

### Service 2 — Framed Data  (`9E3B0000-D7AB-ADF3-F683-BAA2A0E81612`)

| Char name (APK) | UUID | Properties | Role |
|-----------------|------|------------|------|
| BLE_SHIELD_DATA_TX | `9E3B0001-…` | Write (with response) | Framed messages **phone → watch** |
| BLE_SHIELD_DATA_RX | `9E3B0002-…` | Notify | Framed messages **watch → phone** |

All structured bidirectional messages travel on this service using the framing protocol below.

---

## Framing Protocol (Data Service)

Every message on `9E3B0001` / `9E3B0002` is split into **20-byte BLE packets** with a 1-byte header.

```
header byte = (transmissionId << 2) | frameStatus
  transmissionId : 6-bit counter, 0–63, increments per message, wraps
  frameStatus    : 2-bit status (see below)
```

| `frameStatus` | Value | Meaning |
|---|---|---|
| `NO_FRAGMENTS` | `0` | Whole message in one packet |
| `FIRST_FRAGMENT` | `1` | First of multiple packets |
| `MORE_FRAGMENTS` | `2` | Middle packet |
| `LAST_FRAGMENT` | `3` | Final packet |

### Single-packet (payload ≤ 19 bytes)
```
[ header (1) ][ payload (1–19) ]
```

### Multi-packet
**First packet (always 20 bytes):**
```
[ header (1) ][ numPackets: uint16 LE (2) ][ first 17 bytes of payload ]
```
**Middle packets (always 20 bytes):**
```
[ header (1) ][ next 19 bytes of payload ]
```
**Last packet:**
```
[ header (1) ][ remaining payload bytes ]
```

---

## Message Wire Format

After unframing, every message has a 4-byte header:

```
Bytes 0–1 : type    (uint16 LE)
Bytes 2–3 : version (uint16 LE)
Bytes 4+  : payload (type-specific, documented below)
```

### All Message Types

| Value | Name | Direction |
|------:|------|-----------|
| 0 | COMMAND | phone → watch (request) |
| 1 | TIME | phone → watch |
| 2 | BATTERY | watch → phone (response) |
| 4 | ACTIVITY | watch → phone |
| 5 | ACTIVITY_TOTALS | watch → phone |
| 6 | BTN_PRESS | watch → phone |
| 8 | SYSTEM_UPDATE | watch → phone |
| 9 | SYSTEM_INFO | watch → phone (response) |
| 10 | ALARM | bidirectional |
| 11 | BLE_SPEED | phone → watch |
| 12 | BLE_TRULY_CONNECTED | phone → watch |
| 14 | GOAL | bidirectional |
| 15 | APP_INSTALL | bidirectional |
| 16 | WATCHFACE_ORDER | watch → phone |
| 17 | PUSH | phone → watch |
| 18 | FRESH_START | phone → watch |
| 19 | SETTINGS | phone → watch |
| 20 | CALENDAR_EVENTS | phone → watch |
| 23 | UUID | bidirectional |
| 24 | CHANGE_COMPLICATION | watch → phone |
| 25 | SEND_LOGS | watch → phone |
| 26 | SERIAL_NUMBER | bidirectional |
| 29 | REQUEST_DATA | watch → phone |
| 30 | VFTP | bidirectional |
| 31 | ALERT | phone → watch |
| 32 | WATCHFACE_DATA | bidirectional |

---

## Time Representation

Vector uses a **Y2K epoch**: seconds since 2000-01-01 00:00:00 UTC.

```
vectorTime = unixSeconds − 946_684_800
unixSeconds = vectorTime + 946_684_800
```

All timestamps in activity data, calendar events, alarms, and time sync use this format.

---

## Message Payloads

All multi-byte integers are **little-endian** unless noted.

---

### TYPE 0 — COMMAND (subcommands)

COMMAND messages are requests sent phone → watch. The payload encodes a subcommand short and optional arguments.

| Subcommand | Code | Payload | Description |
|-----------|------|---------|-------------|
| GET_SYSTEM_INFO | 2 | `02 00 02 00` | Request firmware/hw versions |
| GET_BATTERY | 13 | `0D 00` or `0D 00 01 00` | Request battery level |
| GET_SERIAL_NUMBER | 23 | `17 00` | Request serial number |
| GET_UUID | 15 | `0F 00` | Request CPU ID |
| GET_ACTIVITY | 12 | `0C 00` | Request activity data |
| GET_BLE_STATUS | 14 | `0E 00` | Request BLE speed info |
| REBOOT | 3 | `03 00` | Reboot watch |
| GET_APPS | 27 | `1B 00 00 00` | List installed watchfaces/apps |
| CHANGE_WATCHFACE | 18 | 11 bytes (see PUSH) | Switch active watchface |

Full framed hex for common requests:

| Request | Hex (type+version+payload) |
|---------|---------------------------|
| Get System Info | `00 00 02 00 02 00 02 00` |
| Get Battery | `00 00 02 00 0D 00 01 00` |
| Get Serial # | `00 00 00 00 17 00` |
| Get UUID | `00 00 00 00 0F 00` |
| Fresh Start | `12 00 00 00` |

---

### TYPE 1 — TIME SYNC

Payload: **16 bytes**

```
vectorTime    : int32    current time (Y2K epoch)
tzOffset      : int16    timezone offset in minutes
dstStart      : int32    DST start in Vector time ÷ 60
dstEnd        : int32    DST end in Vector time ÷ 60
dstOffset     : int16    DST offset in minutes
```

---

### TYPE 2 — BATTERY RESPONSE

**Version 0 (3 bytes):**
```
voltage     : uint16   raw ADC voltage
percentage  : uint8    0–100
```

**Version 1+ adds:**
```
status      : uint8    charging status
```

---

### TYPE 4 — ACTIVITY DATA

**Header (5 bytes):**
```
baseTimestamp : int32   Vector time of first bucket
structCount   : uint8   number of 15-minute activity buckets
```

**Each activity bucket (16 bytes):**
```
steps         : int16
effectiveTime : int16   active minutes in bucket
avgAmplitude  : int16   motion amplitude
avgPeriod     : int16   motion period
calories      : int32
distance      : int32   in cm
```

Each bucket covers a **15-minute interval** starting at `baseTimestamp + (index × 900)`.

**Version 1 appends a 20-byte diagnostic log (after all buckets):**
```
notificationsCount  : int16
glanceCount         : int16
rxPackets           : int16
txPackets           : int16
bleConnects         : uint8
bleDisconnects      : uint8
secsDisconnected    : int16
buttonPresses       : int16
backlightActivations: int16
shakerActivations   : int16
batteryVoltage      : int16
```

---

### TYPE 5 — ACTIVITY TOTALS

**Version 0 (8 bytes):**
```
steps    : int16
calories : int16
distance : int16   in cm
sleep    : int16   in minutes
```

---

### TYPE 6 — BUTTON PRESS

**Payload (14 bytes):**
```
appId       : int32
watchfaceId : uint8
buttonId    : uint8    0=UP  1=MIDDLE  2=DOWN
eventType   : uint8    0=PRESS  1=DOUBLE_PRESS  2=LONG_PRESS
identifier  : int32
value       : int32
```

---

### TYPE 9 — SYSTEM INFO RESPONSE

```
kernelMajor    : uint8
kernelMinor    : uint8
kernelBuild    : uint8   (version 2+ only)
bootMajor      : uint8
bootMinor      : uint8
bootBuild      : uint8   (version 2+ only)
```

Version field in header: `0` = 2-decimal format, `2` = 3-decimal format.

---

### TYPE 10 — ALARM SYNC (Version 1)

```
alarmCount : uint8
[for each alarm]:
  hours    : uint8
  minutes  : uint8
  enabled  : uint8    1=on  0=off
[for each alarm]:
  nameLen  : uint8
  name     : bytes[nameLen]
```

---

### TYPE 17 — PUSH DATA (Version 3)

Used to push live data (weather, stocks, notifications) into watchface elements.

```
appId       : int32
watchfaceId : uint8
elementId   : uint8
elementType : uint8    (see AppElementType below)
ttl         : int32    time-to-live in seconds
dataId      : int32    unique data identifier
ttlType     : uint8
[if elementType == TEXT_COMPLICATION]: 8 padding bytes
commandBytes: variable  element-specific data
```

**AppElementType:**

| Value | Name |
|------:|------|
| 0 | NONE |
| 1 | TEXT |
| 2 | LINE |
| 3 | IMAGE |
| 4 | RECTANGLE |
| 5 | NORMAL_HAND |
| 6 | BITMAP_HAND |
| 7 | TEXT_MULTIPLE_LINES |
| 8 | TEXT_COMPLICATION |
| 9 | LIST |
| 10 | GAUGE |
| 11 | DYNAMIC_IMAGE |

---

### TYPE 19 — SETTINGS SYNC (Version 0)

```
changeCount : uint8
[for each changed setting]:
  settingType : uint8
  [if NAME]: nameLen(uint8), nameBytes[nameLen]
  [else]:    value(uint8)
```

**Setting types:**

| Value | Name | Notes |
|------:|------|-------|
| 0 | NAME | string |
| 1 | AGE | byte |
| 2 | GENDER | byte |
| 3 | WEIGHT | byte |
| 4 | HEIGHT | byte |
| 5 | AF | byte |
| 6 | UNIT_SYSTEM | 0=metric 1=imperial |
| 7 | HOUR_MODE | 0=24h 1=12h |
| 8 | MORNING_GREET_ENABLE | 0/1 |
| 9 | AUTO_DISCREET_ENABLE | 0/1 |
| 10 | AUTO_SLEEP_ENABLE | 0/1 |
| 11 | DROP_MODE | 0/1 |
| 14 | DND | Do Not Disturb 0/1 |
| 16 | GLANCE | Raise-to-wake 0/1 |
| 18 | BACKLIGHT_LEVEL | byte |
| 19 | BACKLIGHT_TIMEOUT | byte |
| 20 | SHOW_SECOND_HAND | 0/1 |
| 21 | LOCALIZATION | language code |
| 22 | WARNING_OPTIONS | byte |
| 23 | ACTIVITY_ALERTS | byte |
| 24 | NOTIFICATIONS_MODE | byte |

---

### TYPE 20 — CALENDAR EVENTS (Version 0)

One message per event:

```
eventIndex  : uint8
startTime   : int32    Vector time
endTime     : int32    Vector time
title       : null-terminated string (max 40 bytes)
location    : null-terminated string (max 40 bytes)
```

---

### TYPE 26 — SERIAL NUMBER

Response payload: ASCII string, no terminator.

---

### TYPE 30 — VFTP (File Transfer Protocol)

Used for watchfaces, firmware updates, locale files. Sub-protocol inside the framing layer.

**VFTP message types:**

| Value | Name |
|------:|------|
| 0 | REQUEST |
| 1 | PUT |
| 2 | DATA |
| 3 | STATUS |

**VFTP file types:**

| Value | Name |
|------:|------|
| 0 | ANY |
| 1 | RESOURCE |
| 2 | APPLICATION |
| 3 | LOCALE_TMP |
| 4 | LOCALE |
| 5 | TMP |

**VFTP status codes:**

| Value | Name |
|------:|------|
| 0 | SUCCESS |
| 1 | NO_SPACE |
| 2 | FILE_NOT_FOUND |
| 3 | FILE_EXISTS |
| 4 | ERROR |

#### PUT (phone → watch, 8 bytes)
```
msgType        : uint8    = 1
realSize       : uint16   uncompressed file size
flags          : uint8    bit0=compressed  bit1=forced
compressedSize : uint16   compressed size (= realSize if uncompressed)
fileType       : uint8
fileId         : int32
```

#### DATA (phone → watch, variable)
```
msgType      : uint8    = 2
packetIndex  : uint16
fileData     : bytes    max 1016 bytes per packet
```

#### REQUEST (phone → watch, 6 bytes)
```
msgType  : uint8    = 0
fileType : uint8
fileId   : int32
```

#### STATUS (bidirectional, 2 bytes)
```
msgType : uint8    = 3
status  : uint8    (VftpStatus code above)
```

---

### TYPE 31 — ALERT

Variable-length alert/notification configuration payload. Exact structure not fully reversed — sent phone → watch to configure vibration patterns or on-watch alerts.

---

### TYPE 32 — WATCHFACE DATA

Watch → phone request/cancel:
```
messageType : uint8    0=REQUEST  1=CANCEL
appId       : int32
watchfaceId : uint8
```

The phone responds by initiating a VFTP transfer of the watchface file.

---

## Notification Flow (Service 1 — raw, not framed)

Notifications travel on `81A50003` (Write Without Response), **not** through the framing layer.

### NotificationInfoMessage (8 bytes, phone → watch)

```
byte0–3 : protocol header (depends on notification type)
byte4–7 : notificationId (int32 LE)
```

| Notification type | byte0 | byte1 | byte2 | byte3 |
|---|---|---|---|---|
| PHONE_CALL incoming | `00` | `00` | `01` | `01` |
| PHONE_CALL remove | `02` | `00` | `01` | `00` |
| SMS incoming | `00` | `00` | `04` | `01` |
| SMS remove | `02` | `00` | `04` | `00` |
| SOCIAL incoming | `00` | `00` | `04` | `01` |
| SOCIAL remove | `02` | `00` | `04` | `00` |
| MISSED_CALL | `00` | `00` | `02` | `01` |
| MISSED_CALL remove | `02` | `00` | `02` | `00` |
| Generic remove | `02` | `00` | `04` | `00` |

Phone calls are identified by `notificationId = [00 00 00 00]`.

### Detail Request (watch → phone, on `81A50001` Indicate)

Watch indicates it wants more info. Phone responds with `NotificationDetailsMessage`:

```
unknown     : uint8
notifId     : int32
fieldType   : uint8    0=APP_IDENTIFIER  1=TITLE  3=MESSAGE
size        : uint16
data        : bytes[size]
```

Field limits: APP_IDENTIFIER max 30 bytes, title and message variable.

### Button press response

After a notification, button presses come back as TYPE 6 (BTN_PRESS) on the DATA service.  
MIDDLE button = positive action (answer/open), DOWN button = negative action (dismiss/reject).

---

## Feature Set of Original Android App

For reference when building the iOS replacement:

| Feature | BLE messages used |
|---------|------------------|
| Time sync | TYPE 1 on connect |
| Battery level | TYPE 0 subcommand 13 → TYPE 2 response |
| Step count / calories / distance | TYPE 0 subcommand 12 → TYPE 4/5 response |
| Sleep tracking | Embedded in TYPE 5 |
| Alarm management | TYPE 10 |
| Notification relay | NotificationInfoMessage + detail handshake |
| Watchface installation | TYPE 32 handshake → VFTP (TYPE 30) |
| Live watchface data push (weather, stocks) | TYPE 17 (PUSH) |
| Calendar sync | TYPE 20 |
| User profile sync | TYPE 19 (SETTINGS) |
| Firmware OTA update | VFTP (TYPE 30) with APPLICATION file type |
| Serial number / UUID | TYPE 0 subcommands → TYPE 26/23 responses |
| System info / firmware version | TYPE 0 subcommand 2 → TYPE 9 response |
| Crash logs | TYPE 25 |
| Raise-to-wake (Glance) | Settings type 16 |
| Do Not Disturb | Settings type 14 |
| Backlight control | Settings types 18/19 |
| Second hand toggle | Settings type 20 |
| Unit system (metric/imperial) | Settings type 6 |
| Hour mode (12h/24h) | Settings type 7 |

---

## What Is Still Unknown

- [ ] Exact WATCHFACE image encoding / pixel format sent via VFTP
- [ ] Watchface file compression algorithm (zlib suspected but not confirmed)
- [ ] VFTP watchface file internal structure (header, resource manifest)
- [ ] PUSH (TYPE 17) exact command bytes per element type
- [ ] ALERT (TYPE 31) full payload layout
- [ ] BLE_SPEED (TYPE 11) payload
- [ ] SYSTEM_UPDATE (TYPE 8) progress payload
- [ ] GOAL (TYPE 14) payload
- [ ] CHANGE_COMPLICATION (TYPE 24) payload
- [ ] REQUEST_DATA (TYPE 29) payload
- [ ] Firmware Base64 alphabet permutation (needed for disassembly)
- [ ] BLE chip model

---

## Tools Used

- **nRF Connect** (iOS) — GATT discovery, live BLE scanning
- **jadx 1.5.5** — APK decompilation
- APK: `VectorWatch_2.0.2_APKPure.apk`

---

## References

- [vector-watch-hacking](https://github.com/deuill/vector-watch-hacking) — hardware teardown, firmware extraction attempts, Gitter community
- [Atmel ATSAM4LC8BA-U datasheet](http://ww1.microchip.com/downloads/en/DeviceDoc/Atmel-42023-ARM-Microcontroller-ATSAM4L-Low-Power-LCD_Datasheet.pdf)
- [VectorWatch Developer Portal (archived)](https://vector-watch-developers-portal.webflow.io/)
- [LunaWatch iOS companion app](https://github.com/arakirley/LunaWatch) — iOS replacement app being built from these findings
