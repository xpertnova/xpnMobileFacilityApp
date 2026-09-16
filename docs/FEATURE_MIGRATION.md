# Feature Migration Guide

## Purpose

This guide turns the product direction into an implementation sequence. The goal is not to clone either older application. It is to take their verified workflow and data behaviour into a new SwiftUI frontend whose navigation and visual language follow the MFM HTML reference and screenshots.

The source order is always:

1. confirmed project decision;
2. `/Users/simenn/Swift Projects/mtfm_swiftui` for behaviour and existing Swift implementation;
3. `/Users/simenn/ios` Cordova code only for gaps; and
4. this repository’s HTML/screenshots for visual direction.

## Migration principles

- Copy behaviour, data semantics, validation, and PDF output—not the old screen design.
- Migrate one user outcome at a time. A tappable mock screen is not a completed feature.
- Build demo and production services separately at the application root. Demo is the App Store review experience and must use deterministic mock data with no SAP reads or writes.
- Preserve offline work locally before attempting SAP writes.
- Trace backend contracts from working code. Never infer a production write request from a UI label.
- Defer scanner, RFID, and label-printer SDK work to the designated hardware developer, behind protocols that UI code can call later.

## Recommended phases

### Phase 0 — App foundation

**Outcome:** a safe, navigable application shell.

| Deliverable | Existing reference | New-app requirement |
| --- | --- | --- |
| SAP onboarding and restore | `mtfm_swiftui/SAPOnboardingHost.swift` | Preserve the existing onboarding host and one-shot completion handling. |
| Root state machine | `mtfm_swiftui/App/AppRootView.swift`, `AppPhase.swift` | Production onboarding reaches app login; SAP demo selection reaches dashboard directly. |
| App login/role selection | `Features/Authentication` | Build a frontend frame based on the new reference. Implement the technician/worker role first while preserving a model that can add external service provider and central control later. |
| Demo isolation | Root composition in the SwiftUI reference | Supply deterministic App Store demo services; never initialize or call a production SAP service, repository, or synchronization operation in demo. |
| Navigation and design primitives | `Core/DesignSystem`, dashboard; HTML/screenshots | Build a new sidebar, header, surfaces, status chips, empty/loading/error patterns, and dashboard. |

**Exit criteria:** both launch routes work; all app navigation is reachable from a new landscape shell; login/role UI does not pretend to be the final authorization system; demo can be reviewed without SAP access.

### Phase 1 — Local persistence and synchronization foundation

**Outcome:** the app can safely tell the difference between local work and SAP-confirmed work.

| Deliverable | Existing reference | New-app requirement |
| --- | --- | --- |
| SQLite layer | `Core/Database/SQLite*.swift` | Define schema migrations, user/worker scope, repository interfaces, and test isolation. |
| Temporary-save model | `Features/TemporarySave` | Persist drafts and pending work with timestamps, type, context, and synchronization state. |
| Sync UI states | `Features/Synchronization` and legacy `edata/luw/` | Display idle, pending, in-progress, completed, and failed states. |
| SAP service boundary | Existing SAP sync/repository code | Build narrow feature protocols only after verifying the particular read/write contract. |

**Exit criteria:** app restart preserves supported drafts; the UI cannot mark a record as synchronized without confirmed service success; demo mode persists only resettable mock/demo data and never offers SAP synchronization.

### Phase 2 — Maintenance notifications and inspection results

**Outcome:** a worker can find, review, fill out, save, and later synchronize a maintenance workflow.

| Deliverable | Existing reference | New UI target |
| --- | --- | --- |
| Notification overview | `Features/Notifications` | `Wartungsmeldungen` list/search/filter presentation. |
| Inspection/review | `Features/Rundgang` | Notification detail with checklist, result, note, and photo affordances. |
| Review persistence | `NotificationReviewRepository`, SQLite review storage | Local records tied to the appropriate notification/object and worker scope. |
| Defect handoff | `Features/Defects` | A failed inspection item can lead to a visibly pending defect record, subject to verified legacy semantics. |

**Exit criteria:** users can complete a realistic reference notification offline; reopening it restores the saved data; verified synchronization sends it only once.

#### Shared inspection checklist

Every form that records inspection points renders them through one component,
`Features/Shared/InspectionForm`, not through a per-form copy. The legacy
Cordova client already worked this way: `view/Rundgang.view.xml`,
`view/Aufzugskontrolle.view.xml`, `view/WartungsPlan.view.xml` and
`view/MasterDataForm.view.xml` all declare the same `formPositionTable`, and
every controller builds its rows on top of one `BaseFormController`. The forms
differ only in which columns exist and which control the result column uses.

`InspectionFormVariant.forFormCode(_:)` is the single place that expresses
those differences, and it is traced to the legacy controllers:

| Form | Result control | Action | Material | Date | Header status |
| --- | --- | --- | --- | --- | --- |
| `TFM1` Wartungsplan | segmented | – | – | – | – |
| `TFM2` Aufzugskontrolle | dropdown | yes | yes | yes | Außer Betrieb |
| `TFM3` Rundgang | segmented | – | – | yes | – |
| `TFM4` Steigleitern | dropdown | yes | – | yes | Außer Betrieb |
| `TFM5` Mobile Leiter | dropdown | yes | – | yes | Demontiert |
| `TFM6` Feststellanlage | dropdown | yes | yes | yes | Außer Betrieb |
| `TFM7` Unterverteilung | dropdown | yes | – | yes | Außer Betrieb |
| `TFM8` Dachanlagen | dropdown | yes | – | yes | – |

- The result control is a variant, never a per-form design. A two-value
  decision renders as the segmented buttons `Rundgang`/`WartungsPlan` build
  from `T_PROPS[0]`; a longer SAP value help renders as the anchored code list
  the `DBOX` branch of the other controllers builds. Column widths live in
  `InspectionFormMetrics`.
- The execution date and the status share one toolbar band directly above the
  checklist, never a separate card. The legacy `form.date` and
  `form.outOfOrder` controls live together in the table's header toolbar
  (`www/fragment/TableFormHeader.fragment.xml`, `SpaceBetween`), and only TFM1
  hides the date.
- `T_PLPOD` rows with `USR00 == "HEADER"` or `"U1"` are group bands, not
  positions: `bindTableItems` routes them to `getGroupHeaderListItem` and does
  not advance the position number. They carry through to the offline snapshot
  so reopening a draft keeps them.
- Column labels come from one vocabulary, `InspectionFormColumn`, matching the
  legacy `tabelle.column.header.*` texts. The result column reads
  "Befund" / "Result" on every form.
- The header "Außer Betrieb" / "Demontiert" status belongs to the forms
  `BaseFormController.buildDefaultElements` builds it for — every code except
  `TFM1`, `TFM3`, `TFM8`, `TFM9` and `TFMQ`. It is a header property, not a
  checklist row: it posts as `<FORM>-0000-1` with its comment in
  `<FORM>-0000-9B`, it locks and clears the positions while it is set, and it
  cannot be closed without a comment.
- Result semantics live in `InspectionFormRules`, traced from
  `HeaderFormBuilder.checkInputConstraints` and the `checkInputConstraints`
  overrides in `Rundgang`/`WartungsPlan`. A new offline-capable inspection
  form adds a variant and reuses those rules; it does not restate them.

### Phase 3 — Manual processing, defects, and temporary-save overview

**Outcome:** workers can record work that did not begin with a synchronized notification.

| Deliverable | Existing reference | New UI target |
| --- | --- | --- |
| Manual processing | `Features/ManualProcessing ` | `Manuelle Erfassung` entry point and focused creation flows. |
| Defects | `Features/Defects` | Defect list, details, photos, and status display. |
| Temporary saves | `Features/TemporarySave` | Unified `Zwischengespeichert` view that makes pending SAP handoff obvious. |
| Legacy feature fallback | Cordova creation/defect controllers | Use only when the SwiftUI project lacks a required behaviour. |

**Exit criteria:** all three areas present one consistent pending-sync model, use the same local-storage conventions, and expose appropriate recovery paths after a failed sync.

### Phase 4 — Forms and PDF parity

**Outcome:** a worker can complete a form offline and produce the same business result as the older MTFM apps.

| Form/workflow family | SwiftUI reference | Cordova fallback |
| --- | --- | --- |
| Briefings | `Features/FLEQAdministration/Briefing` | `InstructFormCreate.controller.js` |
| Electrical safety | `Features/ElectricalSafety` | `ElektrischenFormCreate.controller.js` |
| Fire permit | `Features/FirePermit` | `FeuererlaubnisscheinFormCreate.controller.js` |
| Proof of qualification | `Features/ProofOfQualification` | Form/document resources and related controllers |
| PDF output | Reference PDF exporters/renderers | `PdfBuilder.js` and legacy form outputs |

The new app should share visual components where that is useful, but each form needs its own validation, local draft representation, and output tests. For each migrated form, compare a representative PDF against the legacy output before treating it as compatible.

**Exit criteria:** an offline form can be saved, reopened, completed, exported with the established logic, and synchronized following the verified older-app flow.

### Phase 5 — Technical places, equipment, and administrative workflows

**Outcome:** workers can navigate and act on technical objects in the new design.

| Deliverable | Existing reference | New UI target |
| --- | --- | --- |
| FL/EQ administration | `Features/FLEQAdministration` | `Technische Plätze` hierarchy and equipment details. |
| Technical-object association | Recording models/repositories | Verified relationship behaviour, not merely a visual tree. |
| Create/maintain records | Existing creation view models | New manual-capture and technical-object screens. |
| DIN-276 representation | HTML reference | Hierarchy and naming context, validated against the intended SAP structure. |

**Exit criteria:** the view does not create or edit a technical object until its exact SAP semantics are traced. Read-only hierarchy can be delivered earlier when backend reads are verified.

### Phase 6 — Hardware integration (deferred)

**Outcome:** the frontend adopts the hardware owner’s scanner/RFID/printer implementations without redesigning the core workflows.

| Integration | Existing evidence | Present frontend responsibility |
| --- | --- | --- |
| QR scanning | `Features/Scanning`, Cordova barcode plugin | Keep an injectable scan-result service and UI states. |
| RFID | Cordova RFID plugin and legacy tagging flow | Keep tag actions isolated behind a protocol. |
| QR label printing | Existing printer references | Provide an action/service boundary; do not link vendor SDKs in feature views. |

## Status vocabulary

Use a consistent set of visible states across features. The final backend names must follow verified SAP/legacy terminology, but the frontend must distinguish these meanings:

| State | Meaning |
| --- | --- |
| Draft / temporary saved | Stored locally; user may continue editing. |
| Pending synchronization | Local work is ready to send but SAP has not confirmed it. |
| Synchronizing | A transfer is active; duplicate actions are blocked. |
| Synchronized | SAP confirmed the applicable operation. |
| Failed | The operation did not complete; user receives an actionable retry/recovery path. |
| Conflict / review needed | Local and server state need a verified resolution rule. |

Do not collapse draft, submitted, and synchronized into a single “complete” label.

## Definition of done for a migrated feature

- Existing business behaviour has a named source in the reference apps.
- The new screen follows the new MFM visual direction rather than the old layout.
- The feature has production and demo service implementations or is explicitly frontend-only; its demo implementation uses mock data and makes no SAP requests.
- Local data is saved before a user can lose offline work.
- Pending/failed/synchronized state is accurate and visible.
- PDF/document outputs have parity checks when the flow creates them.
- English and German translations are complete and German layout is reviewed.
- The feature is tested at the model/view-model or repository boundary and builds for a supported iPad target.
