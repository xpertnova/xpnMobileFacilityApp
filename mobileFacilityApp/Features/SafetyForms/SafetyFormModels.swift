import Foundation

struct SafetyFormContext: Codable, Equatable, Hashable, Identifiable, Sendable {
    let businessEntityID: String
    let businessEntityTitle: String
    let buildingCode: String
    let buildingTitle: String
    let functionalLocationID: String
    let functionalLocationTitle: String

    var id: String {
        [businessEntityID, buildingCode, functionalLocationID].joined(separator: "|")
    }
}

struct SafetyFormSource: Sendable {
    let contexts: [SafetyFormContext]
    let partners: [SAPBriefingPartner]
    let instructorName: String
    let organizationUnit: String

    @MainActor
    static func make(for workspace: FacilityDemoViewModel) -> Self {
        guard !workspace.isDemoMode else {
            return Self(contexts: [], partners: [], instructorName: "", organizationUnit: "")
        }

        let notifications = workspace.sapDataStore.notifications
        let contexts = workspace.notificationFilterMetadata.map { metadata in
            let notification = notifications.first { $0.structuralFilterMetadata == metadata }
            let locationID = notification?.functionalLocationID.nonEmpty
                ?? metadata.functionalLocationName.nonEmpty
                ?? metadata.id
            let locationTitle = notification?.functionalLocationName.nonEmpty
                ?? metadata.functionalLocationName.nonEmpty
                ?? locationID
            return SafetyFormContext(
                businessEntityID: metadata.businessEntityID,
                businessEntityTitle: metadata.businessEntityID,
                buildingCode: metadata.buildingCode,
                buildingTitle: metadata.buildingCode,
                functionalLocationID: locationID,
                functionalLocationTitle: locationTitle
            )
        }

        return Self(
            contexts: Array(Set(contexts)).sorted { $0.id < $1.id },
            partners: workspace.sapDataStore.cachedData.briefingPartners,
            instructorName: workspace.effectiveWorkerDisplayName,
            organizationUnit: workspace.sapDataStore.workerProfile?.organizationUnit ?? ""
        )
    }
}

enum FirePermitWorkType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case weldingCutting
    case grinding
    case soldering
    case thawing
    case hotGlue

    var id: Self { self }
    var titleKey: String { "firePermit.workType.\(rawValue)" }
}

enum FirePermitMeasure: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case removeCombustibles
    case removeCombustibleCoverings
    case coverFixedCombustibles
    case sealOpenings
    case water
    case foam
    case powder
    case carbonDioxide
    case connectedWaterHose
    case waterFilledBucket
    case notifyFireBrigade
    case fireAlarmLoopsOutOfService
    case fireWatchDuringWork
    case fireWatchAfterWork
    case removeExplosives
    case removePipelineExplosionHazard
    case sealFixedContainers
    case ventilationMeasures
    case gasDetectors

    var id: Self { self }
    var titleKey: String { "firePermit.measure.\(rawValue)" }
}

enum FirePermitSignatureSlot: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fireHazardMeasures
    case extinguishingMedia
    case fireAlarmSystem
    case explosionHazardMeasures
    case permitIssuer
    case contractor
    case onSiteWorker

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .fireHazardMeasures: "firePermit.subsection.fireHazard"
        case .extinguishingMedia: "firePermit.subsection.extinguishing"
        case .fireAlarmSystem: "firePermit.subsection.fireAlarm"
        case .explosionHazardMeasures: "firePermit.subsection.explosionHazard"
        case .permitIssuer: "firePermit.permitIssuer"
        case .contractor: "firePermit.contractor"
        case .onSiteWorker: "firePermit.onSiteWorkerConfirmation"
        }
    }
}

struct SafetyFormSignature: Codable, Equatable, Sendable {
    var signerName: String
    var capturedAt: Date
    var pngData: Data
}

struct FirePermitRecord: Equatable, Sendable {
    var context: SafetyFormContext?
    var instructorName: String
    var organizationUnit: String
    var instructedPerson = ""
    var partner: SAPBriefingPartner?
    var partnerEmail = ""
    var coordinator = ""
    var workDescription = ""
    var executionStart: Date
    var executionEnd: Date

    var workTypes: Set<FirePermitWorkType> = []
    var hasOtherWorkType = false
    var otherWorkType = ""
    var radiusMetres = ""
    var heightMetres = ""
    var depthMetres = ""
    var onSiteWorkerName = ""

    var measures = Dictionary(uniqueKeysWithValues: FirePermitMeasure.allCases.map { ($0, false) })
    var otherFireHazardEnabled = false
    var otherFireHazard = ""
    var fireHazardPerformer = ""
    var fireHazardCompletedOn: Date
    var otherExtinguishingEnabled = false
    var otherExtinguishing = ""
    var extinguishingPerformer = ""
    var extinguishingCompletedOn: Date
    var fireAlarmPerformer = ""
    var fireWatchName = ""
    var fireWatchDurationHours = ""
    var afterWorkFireWatchName = ""

    var gasDetectorDetails = ""
    var otherExplosionEnabled = false
    var otherExplosion = ""
    var explosionPerformer = ""
    var explosionCompletedOn: Date
    var monitoringContractorName = ""

    var manualCallPointLocation = ""
    var telephone = ""
    var mobileTelephone = ""
    var permitIssuerName = ""
    var permitIssuedOn: Date
    var contractorName = ""
    var contractorSignedOn: Date
    var signatures: [FirePermitSignatureSlot: SafetyFormSignature] = [:]

    init(source: SafetyFormSource, now: Date = .now) {
        instructorName = source.instructorName
        organizationUnit = source.organizationUnit
        executionStart = now
        executionEnd = now
        fireHazardCompletedOn = now
        extinguishingCompletedOn = now
        explosionCompletedOn = now
        permitIssuedOn = now
        contractorSignedOn = now
    }
}

enum FirePermitValidationIssue: Hashable, Sendable {
    case context
    case instructedPerson
    case partner
    case coordinator
    case workDescription
    case signerName(FirePermitSignatureSlot)
    case signature(FirePermitSignatureSlot)
}

enum ElectricalSafetySignatureSlot: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case handoverSystemResponsible
    case handoverWorkResponsible
    case returnSystemResponsible
    case returnWorkResponsible

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .handoverSystemResponsible, .returnSystemResponsible: "electricalSafety.systemResponsible"
        case .handoverWorkResponsible, .returnWorkResponsible: "electricalSafety.workResponsible"
        }
    }
}

struct ElectricalSafetyDraftPayload: Codable, Equatable, Sendable {
    struct ResponsiblePerson: Codable, Equatable, Sendable {
        var name = ""
        var company = ""
        var telephone = ""
    }

    var context: SafetyFormContext?
    var instructorName: String
    var organizationUnit: String
    var instructedPerson = ""
    var partner: SAPBriefingPartner?
    var partnerEmail = ""
    var coordinator = ""
    var workDescription = ""
    var executionStart: Date
    var executionEnd: Date
    var workplace = ""
    var electricalWork = ""
    var systemResponsible = ResponsiblePerson()
    var workResponsible = ResponsiblePerson()
    var workDeEnergized = false
    var workLive = false
    var workNearLiveParts = false
    var instructedWorkResponsible = false
    var instructedAdditionalWorkers = false
    var instructionNotes = ""
    var handoverDate: Date
    var returnDate: Date
    var signatures: [ElectricalSafetySignatureSlot: SafetyFormSignature] = [:]
    var completedAt: Date?

    init(source: SafetyFormSource, now: Date = .now) {
        instructorName = source.instructorName
        organizationUnit = source.organizationUnit
        executionStart = now
        executionEnd = now
        handoverDate = now
        returnDate = now
    }
}

enum ElectricalSafetyValidationIssue: Hashable, Sendable {
    case context
    case instructedPerson
    case partner
    case coordinator
    case workDescription
    case executionRange
    case systemResponsibleName
    case workResponsibleName
    case signature(ElectricalSafetySignatureSlot)
}

extension String {
    fileprivate var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
