import Foundation

enum AllergenClassification: String, Hashable, Sendable, CaseIterable {
    case contains
    case mayContain
    case negativeClaim
    case unresolved

    var title: String {
        switch self {
        case .contains: "İçeriyor"
        case .mayContain: "İçerebilir"
        case .negativeClaim: "İçermediği beyan ediliyor"
        case .unresolved: "Belirsiz"
        }
    }
}

enum AllergenEvidenceStrength: Int, Sendable {
    case mention
    case ingredientList
    case explicitStatement
}

enum SulfiteThreshold: Sendable {
    case unresolved
    case atOrBelow
    case exceeded
}

struct AllergenEvidence: Identifiable, Sendable {
    let memberID: String?
    let term: String
    // UTF-16 offsets in the supplied normalized OCR text.
    let range: NSRange
    let context: String
    let classification: AllergenClassification
    let strength: AllergenEvidenceStrength
    let reason: String
    let sulfiteThreshold: SulfiteThreshold?

    var id: Int { range.location }
}

struct AllergenDetection: Identifiable, Sendable {
    let groupID: String?
    let name: String
    let evidence: [AllergenEvidence]

    var id: String { groupID ?? "unidentified" }

    var primaryClassification: AllergenClassification {
        let precedence: [AllergenClassification] = [.contains, .mayContain, .negativeClaim, .unresolved]
        return precedence.first { classification in
            evidence.contains { $0.classification == classification }
        } ?? .unresolved
    }

    var hasConflictingEvidence: Bool {
        let negativeClaims = evidence.filter { $0.classification == .negativeClaim }
        return evidence.contains { positive in
            guard positive.classification == .contains || positive.classification == .mayContain else { return false }
            return negativeClaims.contains { negative in
                positive.memberID == nil || negative.memberID == nil || positive.memberID == negative.memberID
            }
        }
    }

    var summary: String {
        let title = primaryClassification.title
        return hasConflictingEvidence ? "\(title) · Çelişkili beyan" : title
    }
}
