import Foundation

struct ProofOfQualificationDraftPayload: Codable, Equatable, Sendable {
  static let legacyDocumentID = "TFM016"

  var template: SAPBriefingTemplate
  var context: SafetyFormContext?
  var instructorFirstName: String
  var instructorLastName: String
  var organizationUnit: String
  var contactPerson: String
  var coordinator: String
  var partner: SAPBriefingPartner?
  var partnerEmail: String
  var workLocation: String
  var taskDescription: String
  var executionStart: Date
  var executionEnd: Date
  var answerKeysByItemID: [String: String]
  var commentsByItemID: [String: String]
  var coordinatorSignature: Data?
  var instructedPersonSignature: Data?
  var pdfData: Data?
  var completedAt: Date?

  var instructorName: String {
    [instructorFirstName, instructorLastName]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

enum ProofOfQualificationValidationIssue: Hashable, Sendable {
  case template
  case context
  case contactPerson
  case partner
  case taskDescription
  case executionRange
  case coordinatorSignature
  case instructedPersonSignature
}

struct ProofOfQualificationSource: Sendable {
  let isDemo: Bool
  let contexts: [SafetyFormContext]
  let partners: [SAPBriefingPartner]
  let template: SAPBriefingTemplate?
  let instructorFirstName: String
  let instructorLastName: String
  let organizationUnit: String

  @MainActor
  static func make(for workspace: FacilityDemoViewModel) -> Self {
    if workspace.isDemoMode {
      return .demo(workerName: workspace.effectiveWorkerDisplayName)
    }

    let profile = workspace.sapDataStore.workerProfile
    let contextSource = SafetyFormSource.make(for: workspace)
    return Self(
      isDemo: false,
      contexts: contextSource.contexts,
      partners: workspace.sapDataStore.cachedData.briefingPartners,
      template: workspace.sapDataStore.cachedData.briefingTemplates.first(
        where: \.isQualificationTemplate),
      instructorFirstName: profile?.firstName ?? "",
      instructorLastName: profile?.lastName ?? workspace.effectiveWorkerDisplayName,
      organizationUnit: profile?.organizationUnit ?? ""
    )
  }

  private static func demo(workerName: String) -> Self {
    let nameParts = workerName.split(separator: " ", maxSplits: 1).map(String.init)
    let context = SafetyFormContext(
      businessEntityID: "DE-ESS-11248",
      businessEntityTitle: "DE-ESS-11248",
      buildingCode: "A",
      buildingTitle: "A · Baumstr. 25",
      functionalLocationID: "DE-ESS-11248-A",
      functionalLocationTitle: "Baumstr. 25"
    )
    let partner = SAPBriefingPartner(
      id: "1000001",
      client: "100",
      function: "ZT",
      name: "Westnetz Service GmbH",
      contactName: "Demo contact",
      searchTerm1: "Westnetz",
      searchTerm2: "",
      street: "Florianstraße",
      houseNumber: "15",
      postalCode: "44139",
      city: "Dortmund",
      country: "DE",
      email: "service@westnetz.example"
    )
    let answers = [
      SAPBriefingAnswerOption(key: "J", title: "Ja")
    ]
    let template = SAPBriefingTemplate(
      id: "TFMINSTRUC|I3|A|TFMQ_001",
      equipmentType: "TFMINSTRUC",
      plannerGroup: "I3",
      planType: "A",
      planNumber: "TFMQ_001",
      sections: [
        SAPBriefingTemplateSection(
          id: "qualification-general",
          title: "Qualifikationsnachweise",
          isOptional: false,
          items: [
            SAPBriefingTemplateItem(
              id: "TFMQ0010",
              orderIdentifier: "0010",
              rowType: .position,
              title: "Qualifikationsnachweis wurde im Original vorgelegt.",
              answerOptions: answers,
              documentSymbolID: "7",
              warningSymbolID: nil
            ),
            SAPBriefingTemplateItem(
              id: "TFMQ0020",
              orderIdentifier: "0020",
              rowType: .position,
              title: "Gültigkeit und Umfang entsprechen der beauftragten Tätigkeit.",
              answerOptions: answers,
              documentSymbolID: nil,
              warningSymbolID: nil
            ),
          ]
        )
      ]
    )
    return Self(
      isDemo: true,
      contexts: [context],
      partners: [partner],
      template: template,
      instructorFirstName: nameParts.first ?? "",
      instructorLastName: nameParts.dropFirst().first ?? "",
      organizationUnit: "XPN Facility Management"
    )
  }
}

extension SAPBriefingTemplate {
  var isQualificationTemplate: Bool {
    equipmentType.caseInsensitiveCompare("TFMINSTRUC") == .orderedSame
      && planNumber.caseInsensitiveCompare("TFMQ_001") == .orderedSame
  }
}
