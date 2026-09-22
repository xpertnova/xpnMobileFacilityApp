import Foundation
import Observation

@MainActor
@Observable
final class ProofOfQualificationViewModel {
  let source: ProofOfQualificationSource
  private(set) var contexts: [SafetyFormContext]
  private(set) var partners: [SAPBriefingPartner]
  private(set) var template: SAPBriefingTemplate?

  var instructorFirstName: String
  var instructorLastName: String
  var organizationUnit: String
  var contactPerson = ""
  var coordinator = ""
  var selectedPartnerID = ""
  var partnerEmail = ""
  var selectedBusinessEntityID: String?
  var selectedBuildingCode: String?
  var selectedContext: SafetyFormContext?
  var workLocation = ""
  var taskDescription = ""
  var executionStart: Date
  var executionEnd: Date
  var answerKeysByItemID: [String: String] = [:]
  var commentsByItemID: [String: String] = [:]
  var coordinatorSignature: Data?
  var instructedPersonSignature: Data?
  var pdfArtifact: BriefingPDFArtifact?
  var validationMessage: String?
  var hasAttemptedCompletion = false
  var isRenderingPDF = false
  var isSaving = false

  private(set) var itemStatus: OfflineWorkStatus?
  private var savedWorkID: UUID?

  init(
    source: ProofOfQualificationSource,
    existingDraft: OfflineWorkItem? = nil,
    draftID: UUID? = nil,
    now: Date = .now
  ) {
    self.source = source
    contexts = source.contexts
    partners = source.partners
    template = source.template
    instructorFirstName = source.instructorFirstName
    instructorLastName = source.instructorLastName
    organizationUnit = source.organizationUnit
    executionStart = now
    executionEnd = now
    savedWorkID = existingDraft?.id ?? draftID
    itemStatus = existingDraft?.status

    guard let existingDraft, let draft = existingDraft.payload.proofOfQualification else { return }
    template = draft.template
    instructorFirstName = draft.instructorFirstName
    instructorLastName = draft.instructorLastName
    organizationUnit = draft.organizationUnit
    selectedContext = draft.context
    selectedBusinessEntityID = draft.context?.businessEntityID
    selectedBuildingCode = draft.context?.buildingCode
    contactPerson = draft.contactPerson
    coordinator = draft.coordinator
    selectedPartnerID = draft.partner?.id ?? ""
    partnerEmail = draft.partnerEmail
    workLocation = draft.workLocation
    taskDescription = draft.taskDescription
    executionStart = draft.executionStart
    executionEnd = draft.executionEnd
    answerKeysByItemID = draft.answerKeysByItemID
    commentsByItemID = draft.commentsByItemID
    coordinatorSignature = draft.coordinatorSignature
    instructedPersonSignature = draft.instructedPersonSignature
    if let savedContext = draft.context,
      !contexts.contains(where: { $0.id == savedContext.id })
    {
      contexts.append(savedContext)
      contexts.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
    if let savedPartner = draft.partner,
      !partners.contains(where: { $0.id == savedPartner.id })
    {
      partners.append(savedPartner)
      partners.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
  }

  var selectedPartner: SAPBriefingPartner? {
    partners.first { $0.id == selectedPartnerID }
  }

  /// Pending local work is closed for editing until a verified follow-up
  /// workflow exists. Only temporary drafts can be changed.
  var isReadOnly: Bool {
    guard let itemStatus else { return false }
    return itemStatus != .draft
  }

  var businessEntities: [SafetyFormContext] {
    Dictionary(grouping: contexts, by: \.businessEntityID)
      .values.compactMap(\.first)
      .sorted { $0.businessEntityTitle < $1.businessEntityTitle }
  }

  var buildings: [SafetyFormContext] {
    Dictionary(
      grouping: contexts.filter { $0.businessEntityID == selectedBusinessEntityID },
      by: \.buildingCode
    )
    .values.compactMap(\.first)
    .sorted { $0.buildingTitle < $1.buildingTitle }
  }

  var instructorName: String {
    [instructorFirstName, instructorLastName]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  var hasRequiredMasterData: Bool {
    template != nil && !contexts.isEmpty && !partners.isEmpty
  }

  var validationIssues: Set<ProofOfQualificationValidationIssue> {
    var issues: Set<ProofOfQualificationValidationIssue> = []
    if template == nil { issues.insert(.template) }
    if selectedContext == nil { issues.insert(.context) }
    if contactPerson.trimmedForQualification.isEmpty { issues.insert(.contactPerson) }
    if selectedPartner == nil { issues.insert(.partner) }
    if taskDescription.trimmedForQualification.isEmpty { issues.insert(.taskDescription) }
    if executionEnd < executionStart { issues.insert(.executionRange) }
    if coordinatorSignature == nil { issues.insert(.coordinatorSignature) }
    if instructedPersonSignature == nil { issues.insert(.instructedPersonSignature) }
    return issues
  }

  var firstValidationIssue: ProofOfQualificationValidationIssue? {
    let order: [ProofOfQualificationValidationIssue] = [
      .template,
      .context,
      .partner,
      .contactPerson,
      .taskDescription,
      .executionRange,
      .coordinatorSignature,
      .instructedPersonSignature,
    ]
    return order.first { validationIssues.contains($0) }
  }

  func isInvalid(_ issue: ProofOfQualificationValidationIssue) -> Bool {
    hasAttemptedCompletion && validationIssues.contains(issue)
  }

  func selectPartner(_ partner: SAPBriefingPartner) {
    selectedPartnerID = partner.id
    partnerEmail = partner.email
  }

  func selectBusinessEntity(_ id: String) {
    guard selectedBusinessEntityID != id else { return }
    selectedBusinessEntityID = id
    selectedBuildingCode = nil
    selectedContext = nil
    workLocation = ""
    selectedPartnerID = ""
    partnerEmail = ""
  }

  /// The building is the work location (`SelectionCreate`).
  func selectBuilding(_ context: SafetyFormContext) {
    selectedBusinessEntityID = context.businessEntityID
    selectedBuildingCode = context.buildingCode
    selectedContext = context
    workLocation = context.functionalLocationTitle
  }

  func setContactPerson(_ value: String) {
    contactPerson = String(value.prefix(29))
  }

  func setTaskDescription(_ value: String) {
    taskDescription = String(value.prefix(300))
  }

  func setExecutionStart(_ value: Date) {
    executionStart = value
    if executionEnd < value { executionEnd = value }
  }

  func setAnswer(_ key: String, itemID: String) {
    answerKeysByItemID[itemID] = key
  }

  func setComment(_ comment: String, itemID: String) {
    commentsByItemID[itemID] = comment
  }

  func setSignature(_ data: Data?, for role: ProofOfQualificationSignatureRole) {
    switch role {
    case .coordinator:
      coordinatorSignature = data
    case .instructedPerson:
      instructedPersonSignature = data
    }
  }

  func number(for item: SAPBriefingTemplateItem, in section: SAPBriefingTemplateSection) -> String {
    guard item.rowType != .subposition, let template else { return "" }
    let itemIndex = section.items.firstIndex(where: { $0.id == item.id }) ?? 0
    let position = section.items.prefix(itemIndex + 1).filter { $0.rowType != .subposition }.count
    let sectionNumber =
      template.sections.firstIndex(where: { $0.id == section.id }).map { $0 + 1 } ?? 1
    return "\(sectionNumber).\(String(format: "%02d", position))"
  }

  func requestCompletion() {
    guard !isReadOnly, !isRenderingPDF, !isSaving else { return }
    Task { @MainActor [weak self] in
      await Task.yield()
      self?.finishCompletionRequest()
    }
  }

  func markPendingSynchronization(using store: OfflineWorkStore) async -> Bool {
    guard !isReadOnly,
      !isSaving,
      let artifact = pdfArtifact,
      var payload = makePayload(pdfData: artifact.data, completedAt: artifact.createdAt)
    else { return false }
    // Legacy `_additionalDocs`: only a final close sends the documents.
    payload.additionalDocumentSymbolIDs = InstructionFormReferenceDocuments.symbolIDs(
      sections: payload.template.sections,
      answerKeysByItemID: payload.answerKeysByItemID
    )
    isSaving = true
    defer { isSaving = false }
    do {
      let item = try await store.saveProofOfQualification(
        id: savedWorkID,
        payload: payload,
        status: .pendingSynchronization
      )
      savedWorkID = item.id
      itemStatus = item.status
      return true
    } catch {
      validationMessage = String(localized: "qualification.completed.saveFailed")
      return false
    }
  }

  private func finishCompletionRequest() {
    hasAttemptedCompletion = true
    guard validationIssues.isEmpty else {
      validationMessage =
        template == nil
        ? String(localized: "qualification.masterData.unavailable.message")
        : String(localized: "qualification.validation.message")
      return
    }
    guard let payload = makePDFPayload() else {
      validationMessage = String(localized: "qualification.pdf.failure")
      return
    }

    isRenderingPDF = true
    Task {
      let artifact = await Task.detached(priority: .userInitiated) {
        try? ProofOfQualificationPDFRenderer().render(payload)
      }.value
      isRenderingPDF = false
      guard let artifact else {
        validationMessage = String(localized: "qualification.pdf.failure")
        return
      }
      pdfArtifact = artifact
    }
  }

  private func makePayload(pdfData: Data?, completedAt: Date?) -> ProofOfQualificationDraftPayload?
  {
    guard let template else { return nil }
    return ProofOfQualificationDraftPayload(
      template: template,
      context: selectedContext,
      instructorFirstName: instructorFirstName,
      instructorLastName: instructorLastName,
      organizationUnit: organizationUnit,
      contactPerson: contactPerson,
      coordinator: coordinator,
      partner: selectedPartner,
      partnerEmail: partnerEmail,
      workLocation: workLocation,
      taskDescription: taskDescription,
      executionStart: executionStart,
      executionEnd: executionEnd,
      answerKeysByItemID: answerKeysByItemID,
      commentsByItemID: commentsByItemID,
      coordinatorSignature: coordinatorSignature,
      instructedPersonSignature: instructedPersonSignature,
      pdfData: pdfData,
      completedAt: completedAt
    )
  }

  private func makePDFPayload() -> ProofOfQualificationPDFPayload? {
    guard let template,
      let selectedContext,
      let partner = selectedPartner,
      let coordinatorSignature,
      let instructedPersonSignature
    else { return nil }
    return ProofOfQualificationPDFPayload(
      planNumber: template.planNumber,
      legacyDocumentID: ProofOfQualificationDraftPayload.legacyDocumentID,
      instructorName: instructorName,
      organizationUnit: organizationUnit,
      contactPerson: contactPerson,
      coordinator: coordinator,
      partner: partner,
      workLocation: [
        selectedContext.businessEntityTitle,
        selectedContext.buildingTitle,
        selectedContext.functionalLocationTitle,
      ].filter { !$0.isEmpty }.joined(separator: "\n"),
      taskDescription: taskDescription,
      executionStart: executionStart,
      executionEnd: executionEnd,
      sections: template.sections,
      answerKeysByItemID: answerKeysByItemID,
      commentsByItemID: commentsByItemID,
      coordinatorSignature: coordinatorSignature,
      instructedPersonSignature: instructedPersonSignature,
      completedAt: .now
    )
  }
}

enum ProofOfQualificationSignatureRole: String, Identifiable {
  case coordinator
  case instructedPerson

  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .coordinator: "qualification.signature.coordinator"
    case .instructedPerson: "qualification.signature.instructedPerson"
    }
  }
}

extension String {
  fileprivate var trimmedForQualification: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
