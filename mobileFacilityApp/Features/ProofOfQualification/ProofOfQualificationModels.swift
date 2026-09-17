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

  static func demo(workerName: String) -> Self {
    let nameParts = workerName.split(separator: " ", maxSplits: 1).map(String.init)
    let context = SafetyFormContext(
      businessEntityID: "DE-ANR-17705-01",
      businessEntityTitle: "DE-ANR-17705-01",
      buildingCode: "GB01",
      buildingTitle: "GB01_Völlinghauser Str. 15_Büro-/H_(oA)",
      functionalLocationID: "DE-ANR-17705-01-GB01",
      functionalLocationTitle: "Völlinghauser Str. 15,\n59609, Anröchte (DE)"
    )
    let partner = SAPBriefingPartner(
      id: "1000001",
      client: "100",
      function: "ZT",
      name: "Test Adresse für IT Zwecke",
      contactName: "sdfsdfsdf",
      searchTerm1: "Westnetz",
      searchTerm2: "",
      street: "",
      houseNumber: "",
      postalCode: "",
      city: "",
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
          id: "0010",
          title: "Kontrolle Qualifikationsnachweis",
          subtitle: "Mit die Qualifikationsnachweise wird sichergestellt, dass die Partnerunternehmen, die vom Standortmanagement oder von der E.ON SE beauftragt wurden, sowie deren Subunternehmer, die erforderlichen Qualifikationen für die Tätigkeitsausübung besitzen. Zudem erfolgt eine Überprüfung ihrer Leistung und der Einhaltung der Regeln der Arbeitssicherheit und des Umweltschutzes.",
          isOptional: false,
          items: [
            SAPBriefingTemplateItem(
              id: "0010-01",
              orderIdentifier: "0010",
              rowType: .position,
              title: "Sicherheitspass o.Ä. vorgelegt Folgende\nPartnerfirma haben den Sicherheitspass oder vergleichbare Qualifikationsnachweise vorgelegt und bestätigen die Dokumentation aller wichtigen Informationen in Bezug auf Gesundheit und Arbeitssicherheit.",
              answerOptions: answers,
              documentSymbolID: nil,
              warningSymbolID: nil
            ),
            SAPBriefingTemplateItem(
              id: "0010-02",
              orderIdentifier: "0020",
              rowType: .position,
              title: "Sicherheitspass o.Ä. nicht vorgelegt Mit\nSicherheitspass oder vergleichbaren Qualifikationsnachweise angetroffen werden, oder deren Sicherheitspass veraltete Angaben enthält, können des Einsatzortes verwiesen werden. (Der Nachweis ist dem Prüfer des AG zeitnah vorzulegen).",
              answerOptions: answers,
              documentSymbolID: nil,
              warningSymbolID: nil
            ),
          ]
        ),
        SAPBriefingTemplateSection(
          id: "0020",
          title: "Hinweis Bei den am Standort tätigen Part",
          subtitle: "Subunternehmern) werden in die Qualifikationsnachweise (z. B. Sicherheitspass) stichprobenartig kontrolliert, wenn Bedenken an der Qualifikation bestehen. Sollte eine am Standort tätige Partnerfirma keinen Nachweis vorzeigen können, wird darauf hingewiesen, diesen kurzfristig nachzuliefern. Erfolgt das nicht, sind die Arbeiten einzustellen, bis die Nachweise vorgelegt werden. Im Nachgang sind unverzüglich die Verantwortlichen (Bauingenieure PM, Ansprechpartner des AN) zu Informieren.",
          isOptional: false,
          items: []
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
      organizationUnit: "e.on"
    )
  }
}

extension SAPBriefingTemplate {
  var isQualificationTemplate: Bool {
    equipmentType.caseInsensitiveCompare("TFMINSTRUC") == .orderedSame
      && planNumber.caseInsensitiveCompare("TFMQ_001") == .orderedSame
  }
}
