# RFID scanner

Status: lookup, scan screen, reader settings and the Socket Mobile driver are implemented and
compile against CaptureSDK 2.1.22. **Nothing has been verified on hardware yet.**

## Legacy reference

| Cordova / Socket Mobile | This app |
|---|---|
| `qMTFM/Plugins/cordova-plugin-xpertnova-rfid/DurascanController.swift` (CaptureSDK 1.8.34) | `Core/Services/SocketMobileRFIDReaderDriver.swift` (CaptureSDK 2.x) |
| Socket Mobile sample [capturesingleentryswift-ios](https://github.com/SocketMobile/capturesingleentryswift-ios) (`DevicesViewController`) | `Features/ProfileSettings/RFIDReaderSettingsSection.swift` |
| `Navigate.controller.js` `onRfidPress` / `_afterGetItem4Rfid` | `ScanViewModel.startRFIDScan()` |
| `edata/luw/rfidTable.js`, `select.js` `getItem4Rfid` | `RFIDTagLookup` (`Features/Scan/RFIDTagModels.swift`) |
| `select.js` `getMeldungen4QROverview` | `RFIDTagLookup.notifications(_:matching:)` |

Lookup, as in Cordova:

1. Strip the reader's NUL padding.
2. `FROM_T0212 WHERE RFIDTAG = <tag>`, last row.
3. Otherwise `RFIDTAG = <first 13 characters>`, first row (tags written before the DuraScan readers).
4. Open notifications at that `STRNO`: `EQUNR` `%` = only without equipment, empty = any equipment,
   otherwise suffix match; `STEUS` filters by the first operation when set. No `FROM_T0213` remapping.

Not ported: Cordova rewrote a 13-character tag to the full tag and queued it for SAP (`TO_T0212`).
Tag assignment (`RfidTagging.controller.js`) and QR label printing (Bixolon) are not part of this app yet.

## Architecture

- `RFIDReaderService` (`@Observable`, one per workspace on `FacilityDemoViewModel.rfidReader`):
  connected and discovered readers, Bluetooth state, one-shot tag callback, diagnostic log
  (also written to OSLog, category `RFID`).
- `RFIDReaderDriver`: the only code that touches an SDK.
  - `DemoRFIDReaderDriver`: demo mode only. One paired reader, one to find by searching, one from
    the Classic picker; returns tag `5E68688B29DB11`.
  - `SocketMobileRFIDReaderDriver`: CaptureSDK's `CaptureHelper`.
  - Without `SocketMobileCapture.plist` the reader shows as unavailable and scanning explains why.
- `CoreBluetoothAccess`: the Bluetooth prompt appears only when the technician turns to RFID
  (RFID mode on the scan screen, or *RFID-Scanner einrichten* in Settings).

Readers are managed under **Einstellungen → RFID-Scanner**:

- Connected readers with battery level and *Entfernen* (unpairs, stops automatic reconnection).
- *Nach Bluetooth-LE-Scannern suchen* → found readers → *Verbinden*.
- *Bluetooth-Classic-Scanner koppeln* opens the iOS accessory picker. Classic readers (DuraScan D600)
  must be in Application Mode.

## Setup

1. **CaptureSDK** comes from the Swift package `https://github.com/SocketMobile/swift-package-capturesdk`
   (up to next major from 2.1.22); Xcode resolves it on first build.
2. **Credentials.** `mobileFacilityApp/SocketMobileCapture.plist` (gitignored, share it privately):

   ```xml
   <dict>
       <key>AppID</key><string>ios:de.xpertnova.pm.mtfm.test</string>
       <key>AppKey</key><string>…</string>
       <key>DeveloperID</key><string>…</string>
   </dict>
   ```

   The AppKey is issued per AppID on the Socket Mobile developer portal; the Cordova keys belong to
   `de.xpertnova.mtfm.*` and do not work here.
3. **Info.plist** (done): `NSBluetoothAlwaysUsageDescription`, `UISupportedExternalAccessoryProtocols` =
   `com.socketmobile.chs`, `LSApplicationQueriesSchemes` = `sktcompanion`, `CFBundleAllowMixedLocalizations`.
   **Before an App Store or external TestFlight review**, the app must be whitelisted for the external
   accessory protocol (MFi) in the Socket Mobile developer portal.

## Hardware test checklist

Run a Debug build: the Scan screen in RFID mode shows **RFID diagnostics (debug)** with the event log, *Copy log*
and a manual tag field that runs the same lookup without the reader.

- [ ] Settings → *RFID-Scanner einrichten* → iOS Bluetooth prompt. Declined → "Bluetooth-Zugriff nicht erlaubt"
      + *Einstellungen öffnen*; Bluetooth off → "Bluetooth ist ausgeschaltet".
- [ ] *Bluetooth-Classic-Scanner koppeln* → iOS picker → D600 appears under *Verbundene Scanner* with battery.
- [ ] *Nach Bluetooth-LE-Scannern suchen* → BLE reader listed → *Verbinden* → moves to *Verbundene Scanner*.
- [ ] Reader switched off and on → disappears and reconnects by itself.
- [ ] *Entfernen* → reader unpaired, does not reconnect.
- [ ] Scan screen device card shows the reader and battery, badge *bereit*; *RFID-Scanner verwalten* opens Settings.
- [ ] Tag of a technical place with one notification → notification opens.
- [ ] Tag with several notifications → result list.
- [ ] Unknown tag → "kein technisches Objekt zugeordnet".
- [ ] 13-character legacy tag → found (log says "13-character legacy tag").
- [ ] Cancel while waiting → no lookup when a tag is read afterwards.
- [ ] App to background and back → reader reconnects, scanning works.
- [ ] Same tags in the Cordova app → same notifications.

Send the copied diagnostic log with every failed item.
