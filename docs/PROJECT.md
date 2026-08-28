# Mobile Facility App — Project Guide

## 1. Purpose and delivery approach

Mobile Facility App is a new, iPad-only SwiftUI frontend for maintenance and facility-management work. It is not a greenfield product-definition exercise: the existing MTFM SwiftUI and Cordova applications define the established business workflows, while this repository delivers a new visual experience and a more maintainable SwiftUI implementation.

The first goal is deliberately pragmatic:

1. Build the raw, high-quality frontend in the new MFM design.
2. Reproduce the relevant behaviour from the older MTFM applications.
3. Connect features to the backend only when the old apps or verified SAP material establish the contract.
4. Support local temporary storage and later SAP synchronization for work performed without Wi-Fi.

The application must not silently invent maintenance, authorization, or SAP business rules. When the newer app needs a rule, first trace it in `mtfm_swiftui`; use the Cordova code only when that SwiftUI project does not cover it.

## 2. Current implementation boundary

This repository currently provides the platform foundation, not the complete MFM product.

| Area | Current state |
| --- | --- |
| iPad target | Implemented; iPad-only and landscape-only build settings |
| Minimum platform | iOS 17 |
| SwiftUI application entry | Implemented |
| SAP Fiori onboarding | Implemented, including restoration and recoverable errors |
| Demo route | Implemented as a basic route; the required App Store mock-data composition is not yet implemented |
| Production app login / role selection | Not implemented; initial scope is the technician/worker role only |
| Dashboard and feature navigation | Starter placeholder only |
| MVVM feature architecture | Target architecture; not yet present beyond the onboarding state |
| SQLite temporary storage | Required but not yet implemented here |
| Maintenance, form, defect, and technical-object workflows | Not yet implemented here |
| SAP domain data integration | Not yet implemented here; SAP SDK frameworks are linked |
| QR, RFID, and label-printer integration | Deferred to a later developer |

Treat a screen, screenshot, or HTML interaction as a product reference unless it is implemented in this repository. Do not describe a reference feature as already shipped.

## 3. Source-of-truth hierarchy

Use the following precedence when sources disagree:

1. A confirmed product decision recorded in this document or explicitly supplied by the project owner.
2. The existing SwiftUI MTFM application at `/Users/simenn/Swift Projects/mtfm_swiftui` for functional behaviour, validation, local persistence patterns, backend composition, and PDF logic.
3. The legacy Cordova application at `/Users/simenn/ios` for a workflow or integration missing from `mtfm_swiftui`.
4. `docs/references/xpn-mfm-app.html` and `docs/references/design_screenshots/` for information architecture, interaction intent, wording, and visual direction.
5. The code in this repository for the actual implementation state.

The reference HTML is intentionally not the final design. It should inspire the new MFM experience but must not force a pixel-for-pixel copy or replace verified legacy business logic.

See [Reference Guide](references/REFERENCES.md) for a task-by-task lookup map.

## 4. Product decisions known today

### 4.1 Users and device context

- The primary working persona is a maintenance worker/technician using a shared iPad.
- Three roles are planned: technician/worker, external service provider, and central control.
- The first implementation supports only the technician/worker role. It must not block a later expansion to the other two roles.
- A worker must be able to create a briefing form and have it move to SAP after synchronization.
- The definitive permissions for the three roles are not yet known. The initial technical role should use only the capabilities verified in the older applications.

### 4.2 Production and demo startup routes

```text
App launch
   |
   v
SAP Fiori onboarding
   |\
   | \-- User chooses Demo --> demo dashboard
   |
   \---- Onboarding succeeds --> app-level login / role selection --> production dashboard
```

Rules:

- SAP onboarding and app-level authentication are separate stages.
- A successful SAP onboarding must lead to a login/role-selection screen in production.
- The production login mechanism is not yet defined. Do not choose passwords, SSO reuse, role persistence, or authorization behaviour without reference evidence or an explicit decision.
- The SAP demo choice must bypass that second login and enter a demo dashboard directly.
- Demo data and demo services must be isolated from production SAP services. A presentation `isDemo` flag alone is not enough to protect production data.

### 4.3 Demo mode for App Store review

Demo mode is the App Store submission and review experience. Once a user selects **Demo** in SAP onboarding, the application must:

- display deterministic, realistic mock data for all available demo features;
- not create, initialize, or call a production SAP provider, feature repository, or synchronization service;
- not download from SAP, upload to SAP, or offer an SAP synchronization action;
- bypass the app-level login/role-selection screen; and
- keep any editable demo data local and resettable, clearly separated from production data.

Demo mode may use in-memory services or a dedicated demo-only local store. It must never reuse a persisted production onboarding identity or make a domain-data request to SAP. The SAP welcome flow is solely the entry point through which the user selects this isolated experience.

### 4.4 Offline-first work

The worker should be comfortable working without Wi-Fi. For supported workflows, forms and filled maintenance notifications must be saved locally in SQLite and made available for a later synchronization with SAP.

The required product outcome is clear; the detailed sync semantics still require reference tracing:

- what data is downloaded before offline work;
- which temporary records are editable or deletable;
- attachment and generated-PDF storage rules;
- retry and duplicate-submit handling;
- conflict resolution and its user-facing wording;
- completion and failure states after SAP receives a change.

The previous apps are the initial source for these answers. Until a concrete rule is verified, represent the state visibly as a draft or pending synchronization rather than claiming it is complete in SAP.

### 4.5 Documents and PDFs

Form and PDF outcomes should follow the older applications. This includes briefing workflows, document content, signatures where applicable, generated PDF output, local temporary saves, and later SAP handoff.

The new app may redesign the form UI, but should not redesign the legal/business content or generated-document semantics on its own. A migrated PDF flow needs a visual comparison against the established legacy output and a testable data mapping.

### 4.6 Deferred integrations

QR camera scanning, RFID, and mobile label printing appear in both the reference material and legacy solutions. They are intentionally outside the current frontend scope and will be implemented by another developer. The new UI should therefore use separable service boundaries and avoid coupling core workflows to hardware SDKs.

## 5. Functional scope and reference mapping

The new navigation and visual design can differ from the older application. The expected behaviours map as follows:

| New MFM concept | Functional reference in `mtfm_swiftui` | Legacy fallback | Notes |
| --- | --- | --- | --- |
| Dashboard | `Features/Dashboard` | `controller/Main.controller.js`, `controller/Overview.controller.js` | New dashboard layout should use the HTML/screenshots as visual direction. |
| Production app login | `Features/Authentication` | Legacy logon/auth setup | Initial scope is technician/worker; preserve room for two later roles. |
| SAP onboarding and demo route | `App/AppRootView.swift`, `SAPOnboardingHost.swift` | Hybrid logon flow | Production goes to app login; App Store demo bypasses it and uses mock-only services. |
| Maintenance notifications and inspections | `Features/Notifications`, `Features/Rundgang` | `WartungsPlan.controller.js`, `Rundgang.controller.js` | Copy data/review logic before recreating views. |
| Manual processing | `Features/ManualProcessing ` | `CreateNewForm.controller.js`, `SelectionCreate.controller.js` | Includes creating/handling work outside a preloaded notification. |
| Temporary saves | `Features/TemporarySave`, `Core/Database` | `OverviewTemp.controller.js`, `edata/luw/` | SQLite is mandatory for supported offline work. |
| Defects | `Features/Defects` | `DefectOverview.controller.js` | Reference HTML adds a newer defects presentation. |
| Technical places and equipment | `Features/FLEQAdministration` | `FuncLocMgnt.controller.js`, `MasterDataForm.controller.js` | New UI may use the HTML DIN-276 hierarchy concept. |
| Briefings and safety forms | `Features/FLEQAdministration/Briefing`, `Features/ElectricalSafety`, `Features/FirePermit`, `Features/ProofOfQualification` | Corresponding form controllers and `PdfBuilder.js` | Preserve legacy content/PDF behaviour; recreate views. |
| Scan | `Features/Scanning` | Barcode/RFID plugins and scan controllers | UI can be prepared now; hardware implementation is deferred. |
| Synchronization | `Features/Synchronization`, `Core/Database` | `edata/luw/synchronize*.js` and related LUW modules | Verify operation order and errors before connecting the new feature. |

The trailing space in the existing `Features/ManualProcessing ` directory is part of that reference repository’s filesystem. Do not copy the path convention into this repository; use `Features/ManualProcessing/` here.

## 6. Recommended frontend migration sequence

The detailed migration plan lives in [Feature Migration Guide](FEATURE_MIGRATION.md). The intended order is:

1. Root routing, production login placeholder, and safe demo composition.
2. New iPad landscape design system, sidebar, dashboard, and stateful navigation shell.
3. SQLite infrastructure and explicit temporary-save/synchronization status.
4. Notifications and inspections, including the minimum verified SAP read integration.
5. Offline drafts, defects, and manual-processing flows.
6. Briefing and safety-form flows with PDF parity.
7. Technical-place/equipment administration and association workflows.
8. Hardware integrations when their owner begins the dedicated work.

Each migration slice must deliver a complete, testable vertical flow rather than an unconnected screen. For example, a notification slice includes its domain model, repository protocol, demo implementation, view model, SwiftUI state, localization, SQLite/draft behaviour when required, and focused tests.

## 7. Target architecture

The present starter uses `App/`, `SAP/`, and `Resources/`. As features arrive, organize the application around responsibilities rather than a single large view tree:

```text
mobileFacilityApp/
├── App/                         # app entry, composition, root route
├── Core/
│   ├── DesignSystem/            # colours, spacing, reusable surfaces and navigation
│   ├── Database/                # SQLite schema, migration, scoped storage
│   └── Services/                # shared protocols and cross-feature infrastructure
├── Features/
│   └── <Feature>/
│       ├── <Feature>View.swift
│       ├── <Feature>ViewModel.swift
│       ├── Components/
│       └── Models/
├── SAP/                         # SAP Fiori onboarding and SAP-specific adapters
└── Resources/                   # String Catalog and app assets
```

### Responsibilities

- **Views** render state and send user actions. They do not encode SAP calls, SQL, or maintenance rules.
- **View models** use `@MainActor @Observable`, own user-visible state, validation, and async orchestration.
- **Domain models** describe notifications, forms, technical objects, drafts, and sync records without SAP SDK imports.
- **Repositories/services** provide small feature operations and adapt SAP or demo data to domain models.
- **SQLite storage** persists only approved offline data and exposes a testable interface. It should not be accessed directly by SwiftUI views.
- **App composition** selects SAP-backed services for production and deterministic in-memory/demo services for demo mode.
- **SAP adapters** contain generated OData and SAP SDK types, provider setup, payload mapping, and technical error translation.

Use iOS 17 Swift Observation for UI state. Keep UIKit restricted to SDK or platform boundaries such as SAP onboarding and future scanner/printer wrappers.

## 8. SAP and backend integration policy

The app already links SAP Foundation, Fiori, Fiori Flows, and OData SDK frameworks, and its onboarding configuration is local and ignored by Git. This proves the SAP platform boundary is present; it does not prove that a maintenance operation has a verified endpoint or payload.

For any backend feature:

1. Trace the old SwiftUI app’s repository/service and data mapping.
2. If that does not answer the contract, inspect the Cordova flow and its metadata/payload handling.
3. Only then define a narrow service protocol and map it to a new app domain model.
4. Keep generated SAP/OData entities out of SwiftUI view APIs.
5. Provide loading, empty, failure, retry, and duplicate-submit states.
6. Never log or document credentials, tokens, configuration values, production payloads, or personally sensitive work data.

No developer should infer a production SAP mutation merely from a field name, a prototype toast message, or the reference HTML.

## 9. UI, layout, and localization

### UI direction

The new MFM reference establishes a desktop-like iPad landscape experience with a persistent navigation area, dashboard summary, card/list surfaces, clear work status, and German field terminology. Recreate those ideas in SwiftUI; do not transplant the HTML implementation itself.

Screens must be usable in both landscape directions and reduced iPad window widths. Validate long German strings, keyboard presentation, Dynamic Type, accessibility labels, focus order, and at least 44-point interactive targets.

### Localization

- Support German and English through `Resources/Localizable.xcstrings`.
- German is the product-default language and the primary visual review language.
- English remains the String Catalog source language; this is compatible with German-first product UX.
- Every new user-facing string needs both translations.
- The exact technical policy for forcing German independently of device language is not yet specified. Until it is, preserve normal system-language selection while ensuring German is complete and visually verified.

## 10. Current unresolved decisions

These are intentionally documented as open, not guessed:

| Decision | Current position | Needed before production enforcement |
| --- | --- | --- |
| Role permissions | Three roles are planned; technician/worker is the only initial implementation | Product/SAP authorization decision or verified old-app behaviour for the two later roles |
| App-level login mechanics | Required after successful production onboarding | Confirmed identity, role, password/SSO, and persistence policy |
| SAP entities and write payloads | Must be traced from earlier applications | Verified service contract and sanitized examples where necessary |
| Sync conflict policy | Offline temporary save is required | Rules for conflicts, retries, duplicates, and server rejections |
| Legal/PDF retention policy | Existing PDF logic/output should be reused | Confirmation of archive, retention, signature, and email requirements |
| Hardware SDKs | Deferred to another developer | Hardware owner’s integration plan and supported devices |

## 11. Development checks for each feature

A frontend slice is ready to hand off when, as applicable:

- production and demo composition use separate service implementations;
- demo mode bypasses the app login, contains deterministic mock data, and makes no SAP reads or writes;
- new business logic lives outside the SwiftUI view body;
- the feature shows loading, empty, failure, retry, and pending-sync states where relevant;
- offline work is safely persisted and visibly marked until SAP synchronization succeeds;
- English and German strings exist and German layout has been checked;
- the feature works in both iPad landscape directions;
- focused unit tests cover the model/view-model rules and service boundary;
- the project builds for an available target; and
- no local SAP configuration or sensitive data is included in the change.

## 12. Related documents

- [README](../README.md) — concise project entry point.
- [Feature Migration Guide](FEATURE_MIGRATION.md) — scope-to-reference mapping and recommended implementation sequence.
- [Reference Guide](references/REFERENCES.md) — how to use the older apps and visual assets.
