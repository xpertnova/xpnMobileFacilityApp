# Reference Guide

## Purpose

This project intentionally uses three different kinds of reference material. They answer different questions and must not be used interchangeably:

| Source | Location | Use it for | Do not use it for |
| --- | --- | --- | --- |
| Existing SwiftUI MTFM app | `/Users/simenn/Swift Projects/mtfm_swiftui` | Primary source for feature behaviour, Swift architecture, local persistence, app routing, SAP service boundaries, validation, and current PDF implementations | Copying the old screen design unchanged |
| Legacy Cordova MTFM app | `/Users/simenn/ios` | Fallback for missing workflow details, legacy PDFs, synchronization/SQLite logic, scanner/RFID/printer integrations, and data-model clues | The first choice when the SwiftUI app already answers the question |
| MFM HTML prototype and screenshots | This directory | New visual direction, dashboard/navigation concepts, German terminology, screen states, and interaction ideas | Backend contracts, security, final permission rules, or proof of implemented functionality |

## Required lookup order

Before implementing behaviour, search the sources in this order:

1. Read the project decision in `../PROJECT.md`.
2. Inspect the equivalent feature in `mtfm_swiftui`.
3. If absent or incomplete, inspect the Cordova workflow.
4. Use `xpn-mfm-app.html` and screenshots to design the new SwiftUI screen.
5. Record a question rather than guessing if no source establishes the business/SAP rule.

## Existing SwiftUI MTFM application

**Path:** `/Users/simenn/Swift Projects/mtfm_swiftui`

This is the primary functional reference. Its product guide, startup flow, feature views, view models, repositories, SQLite implementation, tests, and PDF renderers are all useful evidence.

High-value areas include:

- `App/` and `SAPOnboardingHost.swift` for the required production-login versus demo-bypass route.
- `Features/Authentication/` for the current app-level login prototype. Its authentication mechanics are not automatically the final requirements for this project.
- `Features/Notifications/` and `Features/Rundgang/` for notification, technical-object, inspection, and review behaviour.
- `Features/TemporarySave/` plus `Core/Database/` for SQLite persistence and pending-work handling.
- `Features/Defects/` and `Features/ManualProcessing /` for creation and defect flows.
- `Features/FLEQAdministration/`, `Features/ElectricalSafety/`, `Features/FirePermit/`, and `Features/ProofOfQualification/` for forms, signatures, documents, and PDFs.
- `Features/Synchronization/` for synchronization UI/service boundaries.
- `Features/Scanning/` for scan-result flow. Actual scanner/RFID/printing integration remains deferred here.
- `mtfm_swiftuiTests/` for validation, persistence, PDF, and routing expectations that can be ported or adapted.

When reusing code, keep it scoped: port a model, repository contract, formatter, PDF renderer, or small component only after confirming it fits the new architecture and UI. Do not import a large old screen simply because its logic is useful.

## Legacy Cordova MTFM application

**Path:** `/Users/simenn/ios`

Use this only when the newer SwiftUI project lacks a feature or does not expose enough behaviour. Relevant areas include:

- `www/controller/` for form, notification, defect, technical-location, scan, and PDF workflows.
- `www/edata/` and `www/edata/luw/` for local SQLite data handling and synchronization sequences.
- `www/documents/`, `www/controller/PdfBuilder.js`, and form controllers for legacy document output and source content.
- `www/i18n/` for established German and English terminology.
- `www/manifest.json`, `www/serviceBinding.js`, and local service metadata for integration clues.
- `qMTFM/config.xml` and plugin wrappers for historical hardware capability evidence.

The legacy project contains plugin/vendor code and old platform patterns. Treat it as a behavioural reference; do not bring Cordova architecture, dependencies, or secrets into the new SwiftUI app.

## MFM visual and interaction reference

### HTML prototype

**File:** `xpn-mfm-app.html`

It presents the proposed iPad landscape experience, including:

- shared-device role selection;
- a persistent sidebar, dashboard metrics, quick actions, and status information;
- scanning, maintenance notifications, manual capture, temporary saves, defects, technical places, equipment, and forms;
- DIN-276 technical-place hierarchy and example equipment data;
- visual states for drafts, defects, pending synchronization, PDFs, and SAP handoff.

The prototype is valuable for information architecture and wording, but its data, toast messages, role permissions, SAP references, and simulated synchronization are illustrative. They are not backend contracts. Its role picker depicts all three planned roles; only the technician/worker role belongs to the initial implementation.

### Screenshots

`design_screenshots/` contains focused examples of the target visual language:

| Screenshot | Screen/concept |
| --- | --- |
| `start_login.png` | Shared-device role-selection presentation |
| `main_start.png` | Dashboard/sidebar, metrics, quick access, and activity feed |
| `scan_section.png` | QR/RFID scanning screen concept |
| `maintence_notifications_section.png` | Notification list/filter treatment |
| `temporary_save_section.png` | Pending offline work presentation |
| `defects_section.png`, `create_defects_section.png` | Defect overview and creation flow |
| `technical_objects_section.png` | Technical-place/equipment hierarchy |
| `create_forms_section.png` | Forms overview and safety-document direction |

Recreate the design in native SwiftUI with accessible, adaptive layout. The screenshots are not assets to embed in the shipped app.

## Reference-use rules

- **New appearance:** start from the HTML/screenshots.
- **Existing functionality:** start from `mtfm_swiftui`.
- **Missing functionality:** trace Cordova.
- **SAP writes and synchronization:** require verified reference code or backend evidence; never infer them from UI copy.
- **App Store demo:** use mock data only; after the demo route is chosen, do not read from SAP, write to SAP, or offer synchronization.
- **PDFs:** preserve old business content/output first, then style the new UI around the established flow.
- **Hardware:** document old integration evidence but leave implementation to the later hardware owner.
- **Sensitive information:** never copy credentials, configuration plist values, production payloads, or user data into docs, fixtures, screenshots, or commits.
