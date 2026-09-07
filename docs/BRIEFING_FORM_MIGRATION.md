# Briefing Form Migration Brief

## Implementation status

Implemented in the Mobile Facility App:

- the Forms-library briefing route and the card-based landscape workflow;
- the legacy SAP inbound mappings for `T_0298` partners and `T_0267` briefing templates, persisted in the worker-scoped SAP cache;
- dynamic, non-localized SAP rows, answer keys, optional sections, document links, and safety-sign assets;
- validation, temporary `NEU…` partner creation, two signatures, PDF preview/share, and worker-scoped draft/pending persistence with reopening from Local work.

The feature intentionally does not upload a completed briefing to SAP: neither source application provides a verified write contract or server acknowledgement for that document.

## Objective

Replace the current Forms-screen preview for the **Briefing** card with the complete, working briefing workflow from `mtfm_swiftui`, rendered in the current Mobile Facility App design system. This is a functional migration, not a copy of the old orange, table-first screen.

The briefing is a standalone form. Its creation context stops at **business entity** and **building**; unlike the other safety forms, it does not require a functional location. Per the current product-owner decision, the briefing opens directly in the shell detail area. Business entity and building are selected inside the form rather than on a separate creation screen.

## What the existing Mobile Facility App has today

- `Features/Forms/FormsView.swift` displays a card grid and a read-only sheet. Selecting the briefing card does not collect data, load SAP master data, save a draft, capture signatures, produce a PDF, or synchronize anything.
- `App/AppRootView.swift` composes production and demo workspaces separately. That separation must be retained: demo may use deterministic briefing fixtures only and must not initialize or call SAP.
- `SAP/SAPNotificationRefreshService.swift` already performs the legacy authenticated SAP download lifecycle and persists the result through `SAPDataStore` and `SQLiteSAPDataCacheRepository`.
- The current inbound parser only keeps notification rows from `T_0271` and the worker profile from `T_0153`. Its `SAPReadSnapshot` and SQLite cache have no briefing-partner or briefing-template fields/tables yet.
- `OfflineWorkStore` and its repository already have explicit worker-scoped draft/status handling, but support only manual captures and notification reviews. A briefing needs its own payload and work type.

## Verified behaviour in `mtfm_swiftui`

### Legacy entry and current context selection

The old app opens `FLEQBriefingCreationView`, backed by `FLEQBriefingCreationViewModel`.

The legacy app used a separate context screen before opening `FLEQBriefingFormView`. The current Mobile Facility App deliberately removes that intermediate screen:

1. The worker opens the briefing card and immediately sees the form beside the persistent sidebar.
2. The worker selects a business entity through the same value-help modal pattern as partner-company selection.
3. The worker selects a dependent building inside the form; changing the business entity clears the building.
4. PDF creation remains unavailable until the required context, form fields, and both signatures are present.

The legacy picker values are demo placeholders in the creation view. The new app should instead derive selectable business entities/buildings from cached SAP data where the payload gives enough hierarchy data. It already extracts country, location, business entity, building, trade, and form codes from `T_0271` for notification filtering. That is a useful starting point, but it is not proof that notification hierarchy is the authoritative briefing value-help contract; retain the source IDs alongside display labels.

### Form content and validation

`FLEQBriefingFormViewModel` establishes the functional contract:

- Instructor name and organisation come from the synchronized `T_0153` worker profile in production; demo uses fixed demo data.
- The worker enters coordinator, instructed person, task description, and a start/end date range.
- A partner company is selected from SAP `T_0298` master data. Selection fills its email and makes the address available for display/PDF output.
- A temporary local partner can be added for the current form. It requires company, contact, email, telephone, street, house number, postal code, city, and country. The old app gives it a `NEU…` ID and deliberately does **not** send it to SAP because the write payload is unverified.
- Required fields are coordinator, instructed person (maximum 29 characters), partner, syntactically valid partner email, task description (maximum 300 characters), and an end date that is not before the start date.
- Checklist answers and comments are optional; unanswered items are represented as not applicable in the PDF.
- The worker can enable optional checklist sections supplied by the SAP template.
- Every checklist item supports a yes/no answer, a comment editor, an optional linked document preview, and an optional safety-symbol icon.

### Completion and PDF behaviour

Completion is not just a toast:

1. Validate the required form fields.
2. Capture the instructor signature.
3. Capture the instructed-person signature.
4. Render the document off the main actor.
5. Lock the form and show a non-dismissible PDF preview.
6. Allow sharing a temporary PDF file, then clean up that temporary file.
7. Only after the worker presses Finish in the preview does the old view report completion.

The PDF includes the briefing header, selected optional sections, all visible checklist items, their original SAP answer keys/comments, safety signs, both signatures, timestamps, and the delivered-copy declaration. It paginates the checklist and has unit coverage for multi-page output and rendering failures. A rendering failure clears both signatures and does not complete the briefing.

## Verified SAP inbound flow

The old app’s `SAPNotificationRepository` uses the legacy request sequence:

```text
SAP onboarding session
  -> password check (M0153003)
  -> outgoing metadata/post/acknowledgement
  -> prepare incoming package (MMTFM004)
  -> poll preparation (MMTFM003)
  -> fetch each package (M0002003)
  -> decode legacy envelope and cache mapped rows
```

The relevant decoded tables are:

| SAP table | Use in briefing | Mapping evidence |
| --- | --- | --- |
| `T_0153` | Instructor and organisation unit | `PERSNR`, `VORNAME`, `NAME`, `GESELLSCHAFT`, and other profile fields map to the worker profile. |
| `T_0298` | Partner-company value help | `ADDRNUMBER`, `NAME1`, `NAME2`, `PARVW`, address fields, and `SMTP_ADDR` map to a briefing partner. If `FELDWERT` is present, the decoded object supplements the row. |
| `T_0267` | Briefing template / checklist | The outer row selects the template with `EQART`, `INGRP`, `PLNTY`, and `PLNNR`. `FELDWERT` contains either a `T_PLPOD` object or a direct position array. |

For the standard briefing, the old view selects the template with `EQART = TFMINSTRUC` and `PLNNR = TFMB_001` (case-insensitive). The `T_0267` rows are ordered by `VORNR`; `HEADER` rows start checklist sections, `USR10 = X` marks an optional section, and position/subposition rows become checklist entries. The mapper preserves document/safety-symbol references and SAP answer keys.

`FELDWERT` follows the legacy layered decoding route: Base64, DEFLATE/gzip, Base64, then JSON. The current app already implements the equivalent decoder for notification `T_0271.FELDWERT`; the briefing mapper should reuse that verified utility rather than introduce another decompressor.

## Important limitation: no verified completed-briefing SAP write

Neither the old briefing view model nor the old synchronization service submits a completed briefing, checklist result, signature, PDF, or temporary partner to SAP. The old implementation renders/shares a PDF and reports local completion. The current Mobile Facility App’s outgoing call intentionally posts an empty payload to enable the inbound download lifecycle.

Therefore, this migration can truthfully show a briefing as **draft** or **pending synchronization**, but must not label it synchronized or claim it reached SAP until the backend owner supplies a sanctioned outbound contract and acknowledgement semantics. In particular, do not infer an outbound request from `T_PARTNER_NEW`, `M0002001`, `M0002021`, or a UI field name.

### Confirmed PDF transport format

The project owner has confirmed that every generated form PDF must cross the
upload boundary as a raw Base64 string. The Cordova fallback corroborates the
format: `PdfBuilder.getPdfDocument` calls pdfmake's `getBase64`, and
`BaseFormController.closeProcess` assigns that value directly to
`T_0282.FELDWERT`. It is not a `data:application/pdf;base64,...` URL.

All four Swift renderers return the shared `BriefingPDFArtifact`, whose
`uploadPayload` now contains `application/pdf`, the file name, and raw Base64
content. This confirms document encoding only; the app must remain in pending
synchronization until the complete outbound form envelope and SAP
acknowledgement have been implemented and verified.

## Design direction for this app

Use the existing Mobile Facility App visual language rather than the legacy form chrome:

- Open the briefing from the existing Forms library and replace the current preview sheet with a full-screen/detail route in the persistent landscape shell.
- Use `PageHeader`, `FacilityTheme`, card surfaces, clear status pills, flexible `ViewThatFits`/grid layout, and 44-point controls.
- Present context, people/work details, partner, optional sections, checklist, and two inline legacy-style signature fields as smooth card surfaces in the shell detail area. Keep the checklist dense enough for iPad landscape but switch to a stacked row at reduced widths.
- Compose the form header as a compact template-style field grid: partner company and the combined instructor name, full-width business entity, date/time and work location, work description, instructed person, email, and address. Preserve the organisation unit as secondary instructor information.
- Present optional briefing sections through one full-width, expandable multi-select field instead of a stack of individual switches. Keep SAP section titles verbatim and show the current selection in the collapsed field.
- Put a visible draft/pending state and primary Continue/Complete action in a persistent bottom action area.
- Keep signature capture and PDF preview as focused modal experiences; do not let an interactive dismissal discard a partly completed signature sequence.
- Preserve the legacy PDF output semantics and validate representative new-app PDFs against the legacy document before calling the migration complete.

## Row language decision

Per the request, **no localization work is required for briefing rows**:

- Render SAP-provided section titles, checklist titles, linked-document titles, safety references, and answer labels verbatim.
- Do not add String Catalog entries for dynamic briefing rows or translate mixed-language SAP content.
- Preserve SAP answer keys separately from the labels, so a later verified outbound payload does not depend on display text.

This deliberately differs from the old view’s yes/no label normalization. The new row control should display the supplied SAP answer labels as-is (with a deterministic demo fixture when in demo mode), while still preserving their exact keys.

## Proposed feature slice

```text
Features/Briefing/
  Models/BriefingModels.swift
  BriefingRepository.swift
  BriefingViewModel.swift
  BriefingSelectionView.swift
  BriefingFormView.swift
  Components/BriefingContextCard.swift
  Components/BriefingPartnerPicker.swift
  Components/BriefingChecklistRow.swift
  Components/BriefingSignatureSheet.swift
  BriefingPDFRenderer.swift
  BriefingPDFPreview.swift

SAP/
  SAPBriefingMasterDataMapper.swift     # T_0298/T_0267 parsing behind the existing refresh transport

Core/Database/
  SAPCacheModels.swift                  # briefing master-data cache models
  SQLiteSAPDataCacheRepository.swift    # user-scoped master-data tables/migration
  OfflineWorkModels.swift               # briefing draft/pending payload
```

Recommended implementation order:

1. Extend the existing SAP inbound pack, `SAPReadSnapshot`, data store, and user-scoped SQLite cache to retain `T_0298` partners and `T_0267` templates alongside the existing `T_0153` profile. Handle empty/malformed rows as a visible unavailable/empty state, not an invented checklist.
2. Add a `BriefingRepository` protocol with separate production cache-backed and deterministic demo implementations. Production reads only locally cached master data after refresh; the SwiftUI views must not decode SAP data directly.
3. Add worker-scoped briefing draft persistence to `OfflineWorkStore`, including selections, entered header values, selected optional sections, checklist answer keys/comments, local partner draft, signature data/storage references, PDF metadata, and explicit sync state. Decide image/PDF retention before persisting raw signature/PDF bytes broadly.
4. Implement selection, form validation, partner editing, checklist, signatures, and PDF parity in the new design.
5. Add a narrow outbound synchronization protocol only once SAP provides the exact request payload, PDF/signature transport rules, duplicate handling, and server acknowledgement. Until then, retain a pending record and omit any SAP upload action.

## Acceptance criteria

- Production receives its worker profile, partners, and template from the cached SAP refresh; demo receives only deterministic fixtures and makes no SAP request.
- The briefing opens directly in the shell detail area; business entity and building are selected inside the form and no functional location is required.
- All verified legacy header fields, validation, optional sections, rows, comments, document links, safety icons, answer keys, two signatures, and PDF behaviour are represented.
- Instructor first and last name appear in one field, and optional sections can be selected independently from one full-width multi-select dropdown.
- Dynamic briefing rows are shown from SAP/demo payload without String Catalog localization.
- A reopened draft restores the form with its original data under the correct worker scope.
- The form cannot complete if required data is invalid, if a signature sequence is cancelled, or if PDF rendering fails.
- Completion cannot be presented as SAP synchronization without a confirmed backend write acknowledgement.
- Focused tests cover `T_0298`, both supported `T_0267.FELDWERT` shapes, section ordering/optionality, validation limits, raw answer-key preservation, draft round-trip, signature/PDF failure, demo isolation, and production cache scoping.

## Reference files inspected

- Legacy workflow: `/Users/simenn/Swift Projects/mtfm_swiftui/mtfm_swiftui/Features/FLEQAdministration/FLEQBriefingCreationView.swift`, `FLEQBriefingCreationViewModel.swift`, and `Briefing/`.
- Legacy SAP mapping: `/Users/simenn/Swift Projects/mtfm_swiftui/mtfm_swiftui/Features/Notifications/SAPNotificationTestSync.swift` and `Features/Synchronization/Models/BriefingMasterData.swift`.
- Legacy test evidence: `/Users/simenn/Swift Projects/mtfm_swiftui/mtfm_swiftuiTests/FLEQAdministration/FLEQBriefingViewModelTests.swift`, `FLEQBriefingPDFExportTests.swift`, and `FLEQBriefingSafetySymbolTests.swift`.
- Current migration target: `mobileFacilityApp/Features/Forms/FormsView.swift`, `SAP/SAPNotificationRefreshService.swift`, `Core/Services/SAPDataStore.swift`, `Core/Database/SQLiteSAPDataCacheRepository.swift`, and `Core/Services/OfflineWorkStore.swift`.
