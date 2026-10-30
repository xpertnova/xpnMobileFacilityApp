# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`mobileFacilityApp` is an iPad-only, landscape-only SwiftUI frontend for Mobile Facility Management (MFM) — a maintenance/facility-management app for technicians on a shared iPad. It is a frontend-first rewrite of two existing apps (see "Reference apps" below), not a greenfield design: business behaviour, validation, persistence patterns, and PDF output should be traced from those apps rather than invented. iOS 17 minimum, Swift Observation (`@Observable`) for state, SAP Fiori/OData SDKs linked as local XCFrameworks in `Release-xcframework/`.

Read [docs/PROJECT.md](docs/PROJECT.md) before implementing any new feature — it defines product boundaries, the production-vs-demo routing rule, offline/sync rules, and the source-of-truth hierarchy. [docs/FEATURE_MIGRATION.md](docs/FEATURE_MIGRATION.md) gives the recommended build-out order and a status vocabulary (draft / pending sync / synchronizing / synchronized / failed / conflict) that must not be collapsed into a single "complete" state. [docs/references/REFERENCES.md](docs/references/REFERENCES.md) says which of the three reference sources to consult for a given question.

## Reference apps (source of truth for behaviour, not code to copy verbatim)

When implementing or changing a workflow, trace it in this order:
1. A confirmed decision in `docs/PROJECT.md`.
2. `/Users/simenn/Swift Projects/mtfm_swiftui` — the existing SwiftUI app; primary source for feature behaviour, validation, persistence, routing, SAP service boundaries, and PDF logic.
3. `/Users/simenn/ios` — the legacy Cordova app; fallback only for gaps not covered by `mtfm_swiftui` (`www/controller/`, `www/edata/luw/` for sync, `www/controller/PdfBuilder.js` for PDFs).
4. `docs/references/xpn-mfm-app.html` and `docs/references/design_screenshots/` — visual/interaction direction only. Never treat these as backend contracts, permission rules, or proof that a feature is implemented.

Never infer a production SAP read/write from a field name, prototype toast message, or the reference HTML — it must trace to verified code in one of the reference apps.

## Build, test, run

Open in Xcode (`mobileFacilityApp.xcodeproj`) or use `xcodebuild` from the repo root. Scheme and targets are both named `mobileFacilityApp` (test target: `mobileFacilityAppTests`).

```bash
# Build for a simulator
xcodebuild -project mobileFacilityApp.xcodeproj -scheme mobileFacilityApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build

# Run the full test suite
xcodebuild -project mobileFacilityApp.xcodeproj -scheme mobileFacilityApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test

# Run a single test class or method
xcodebuild -project mobileFacilityApp.xcodeproj -scheme mobileFacilityApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -only-testing:mobileFacilityAppTests/MobileLadderTests test
xcodebuild ... -only-testing:mobileFacilityAppTests/MobileLadderTests/testSomething test
```

There is no SPM `Package.swift` and no CocoaPods/Carthage. External dependencies are the SAP XCFrameworks under `Release-xcframework/`, linked directly in the Xcode project, and Socket Mobile's CaptureSDK for the RFID readers, added to the Xcode project as a Swift package (see [docs/RFID.md](docs/RFID.md)). SQLite access goes through the system `sqlite3` C library (see `SQLiteC` in `Core/Database/SQLiteOfflineWorkRepository.swift`), not a Swift package.

`mobileFacilityApp/ConfigurationProvider.plist` holds the SAP landscape configuration and is tracked in Git on purpose. Without it, SAP onboarding cannot complete, but the app still builds and the demo route still works.

### Legacy SQLite schema generator

`scripts/generate-legacy-schema.js` (Node) regenerates `mobileFacilityApp/Core/Database/LegacySQLiteSchema.generated.swift` and the golden manifest used by `mobileFacilityAppTests/LegacySQLiteSchemaTests.swift`, by evaluating the legacy Cordova app's `www/edata/createTypes.js`/`create.js` (path defaults to `/Users/simenn/ios/www/edata`, overridable via argv). Re-run it only when the legacy schema itself changes — the generated Swift file and `Fixtures/legacy-schema.json` must be regenerated together; do not hand-edit `LegacySQLiteSchema.generated.swift`.

## Architecture

### Startup routing (`App/AppRootView.swift`, `App/AppPhase.swift`)

`AppPhase` drives a strict state machine: `launching → authentication → ready`, or `launching → demo`.

```
App launch → SAP Fiori onboarding (SAPOnboardingHost)
                ├─ user picks Demo  → .demo   → demo dashboard (mock-only, no SAP)
                └─ onboarding succeeds → .authentication → RoleSelectionView (login) → .ready → production dashboard
```

- **Demo mode** must never construct a production SAP repository, refresh service, or sync coordinator — `AppRootView` wires demo/authentication phases to `InMemoryOfflineWorkRepository` / `InMemorySAPDataCacheRepository` with no `refreshService`. Any new demo wiring must preserve this isolation; it's an App Store review requirement, not a convenience default.
- **Production mode** wires `SQLiteOfflineWorkRepository` / `SQLiteSAPDataCacheRepository`, a `KeychainSAPSyncTokenStore`, and `SAPInboundNotificationRefreshService`, scoped to the worker ID entered at login (`FacilityUserSession.workerID` — this is the legacy MTFM sync identity, e.g. `S50828`, distinct from `displayName`).
- Both phases converge on the same `FacilityShellView`, parameterized by a `FacilityDemoViewModel` (despite the name, this is the shared app view model for both demo and production — not demo-only) and an `isDemoMode` flag.

### Layered structure

```
App/            entry point, root phase/routing state
Core/
  DesignSystem/ FacilityTheme, shared surfaces/popovers
  Database/     SQLite schema + repositories (offline work queue, SAP data cache)
  Services/     view models / stores sitting between views and repositories (OfflineWorkStore, SAPDataStore, ...)
Features/<Feature>/   one folder per screen/workflow (View + ViewModel + Models)
SAP/            SAP Fiori onboarding host, OData/SDK adapters, upload builders, CSRF handling
Resources/      Localizable.xcstrings (en/de String Catalog), bundled PDFs
```

Dependency direction: Views → ViewModels/Stores → Repositories/Services → SAP or SQLite. Views must not call SAP or SQL directly; domain models must not import the SAP SDK. Every repository/store has a production implementation (SQLite- or SAP-backed) and an in-memory/demo implementation behind the same protocol (`OfflineWorkRepository`, `SAPDataCacheRepository`, `PhotoAttachmentStore`) — when adding a feature that persists data or reads SAP data, add both.

### Offline work model

`OfflineWorkStore` (`Core/Services/OfflineWorkStore.swift`) is the `@MainActor @Observable` aggregate over everything a worker has saved locally but not yet confirmed by SAP — notification reviews, elevator inspections, briefings, electrical safety/fire permit forms, technical-object edits, defects, meter readings, proof-of-qualification records, photo collections. `OfflineWorkItem.status` distinguishes `draft` from `synchronized`; a "local work" or "temporary save" list must filter on that status (or a workflow-specific `isClosedLocally` flag), never assume anything not `.synchronized` is safe to treat as complete. Follow this same status vocabulary (draft / pending / synchronizing / synchronized / failed / conflict) for any new offline-capable feature.

### SAP integration

`SAP/` holds the Fiori onboarding bridge (`SAPOnboardingHost.swift`), the notification refresh/sync service, upload builders (e.g. `SAPEquipmentInspectionUploadBuilder.swift`), and CSRF token handling for OData writes. Generated SAP/OData types must stay behind this layer — they should not leak into `Features/` view code or domain models. New SAP reads/writes need a narrow protocol here, backed by a verified contract from the reference apps (see above), never guessed from UI copy.

### Localization

`Resources/Localizable.xcstrings` is the single String Catalog for German (product-default) and English (source language for the catalog). Every new user-facing string needs both translations; German strings should be checked for layout/wrap in the iPad landscape UI, not just translated.

### Adaptive layout

The app runs in any window size from an iPad Pro 13" down to a 700 × 500 pt window (iPad mini, Split View, Stage Manager). `UIRequiresFullScreen = YES` is set only because App Store validation (ITMS-90474) rejects a landscape-only iPad app that allows multitasking; iPadOS 26+ ignores it, so layouts must still adapt to any window size. Remove it once portrait orientations are supported. `facilityLayoutRoot()` in `AppRootView` measures the window, sets that minimum window size and publishes `FacilityLayoutMetrics` as `@Environment(\.facilityLayout)`: `regular` keeps the original 13" values, `compact` applies below 1180 × 800 pt.

- Put sizes that depend on the window into `FacilityLayoutMetrics`, not inline numbers. Screens use `facilityPageContent()` for their content column, `facilityPageHorizontalPadding()` for pinned headers and action bars, and `facilityPageTitleFont()` for titles.
- Centered dialogs use `facilityDialogFrame(width:padding:)`, which caps them to the available space and scrolls when the keyboard leaves too little height.
- To switch between side-by-side and stacked, use `FacilityColumnsLayout` or `FacilitySideColumnLayout`. Avoid `ViewThatFits` or an `if` on a measured width around text inputs: both rebuild the fields and drop focus when the width changes.
- Inspection checklist tables (`InspectionFormTable`) intentionally scroll sideways when too narrow.
- Check new screens in the `FacilityShellView` previews at 1376 × 1032, 1133 × 744 and 700 × 744 pt.
