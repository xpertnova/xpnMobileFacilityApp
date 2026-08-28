# Mobile Facility App

`mobileFacilityApp` is a new iPad-only SwiftUI frontend for Mobile Facility Management (MFM). It is a frontend-first rewrite: reproduce the useful workflows and selected backend integrations from the existing MTFM applications, while recreating the UI in the new MFM design direction.

The current app is a starter. It already provides SAP Fiori onboarding, onboarding restoration, an isolated demo route, basic localization, and an iPad landscape target. The maintenance-domain screens, offline store, and SAP feature integrations remain to be built.

## Product direction

- Target user: primarily a maintenance worker or technician on a shared iPad. Three roles are planned, but the first release implements only the technician/worker role.
- Production path: SAP onboarding succeeds, then the app shows an app-level login/role-selection screen, then the dashboard.
- Demo path: choosing **Demo** in SAP onboarding opens the demo dashboard directly. It is the App Store submission/review experience: show deterministic mock data, never show the app-level login screen, and never read from or write to SAP.
- Offline principle: workers must be able to complete supported forms and maintenance notifications without Wi-Fi. Those changes are temporarily stored locally in SQLite and later synchronized with SAP.
- Design principle: reuse established logic and selected small components from the older apps, but recreate screens in the new design. The HTML prototype and screenshots are visual/product references, not final implementation specifications.

## Documentation

- [Project guide](docs/PROJECT.md) — product boundaries, routing, architecture, offline rules, and development constraints.
- [Feature migration guide](docs/FEATURE_MIGRATION.md) — the recommended order for carrying old-app behaviour into the new frontend.
- [Reference guide](docs/references/REFERENCES.md) — which source to consult for each type of decision.
- [`xpn-mfm-app.html`](docs/references/xpn-mfm-app.html) and `docs/references/design_screenshots/` — visual and interaction reference material.

## Current source layout

```text
mobileFacilityApp/
├── App/                 # Application entry point and root route
├── SAP/                 # SwiftUI-to-SAP Fiori onboarding bridge
├── Resources/           # English and German String Catalog
└── ConfigurationProvider.plist  # Local SAP configuration; ignored by Git
```

## Local SAP setup

The project links local SAP SDK XCFrameworks in `Release-xcframework/`. `mobileFacilityApp/ConfigurationProvider.plist` contains landscape-specific configuration and is intentionally ignored by Git. Obtain valid values through the approved secure channel; never commit tenant configuration, credentials, tokens, or production payloads.

## Scope boundaries

Hardware work such as QR/RFID scanner integration and mobile label printing is explicitly deferred to a later developer. The present focus is the SwiftUI frontend, core maintenance workflows, SQLite-based temporary persistence, and verified SAP integration slices.
