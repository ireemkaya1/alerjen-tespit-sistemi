import Foundation

struct AllergenCatalog: Codable, Sendable {
    let schemaVersion: Int
    let jurisdiction: String
    let regulation: RegulationInfo
    let sources: [AllergenSource]
    let allergens: [Allergen]
}

struct RegulationInfo: Codable, Sendable {
    let name: String
    let section: String
}

struct AllergenSource: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
    let note: String
}

struct Allergen: Codable, Identifiable, Sendable {
    let id: String
    let order: Int
    let name: String
    let regulatoryName: String
    let description: String
    let terms: [IngredientTerm]
    let members: [AllergenMember]
    let exceptions: [LegalException]
    let conditions: [SpecialCondition]
    let sourceIDs: [String]
}

struct IngredientTerm: Codable, Sendable {
    let value: String
    let language: String
    let kind: String
}

struct AllergenMember: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let scientificName: String?
    let terms: [IngredientTerm]
}

struct LegalException: Codable, Identifiable, Sendable {
    let id: String
    let description: String
    let condition: String?
}

struct SpecialCondition: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let description: String
    let basis: String?
    let comparison: String?
    let value: Double?
    let units: [String]
}
