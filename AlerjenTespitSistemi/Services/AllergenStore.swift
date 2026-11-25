import Foundation

struct AllergenStore: Sendable {
    let catalog: AllergenCatalog

    var allergens: [Allergen] {
        catalog.allergens
    }

    static func load(from bundle: Bundle = .main) throws -> AllergenStore {
        guard let url = bundle.url(forResource: "allergens", withExtension: "json") else {
            throw AllergenStoreError.missingResource
        }

        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(AllergenCatalog.self, from: data)
            try validate(catalog)
            return AllergenStore(catalog: catalog)
        } catch let error as AllergenStoreError {
            throw error
        } catch let error as DecodingError {
            throw AllergenStoreError.decodingFailed(error.localizedDescription)
        } catch {
            throw AllergenStoreError.readFailed(error.localizedDescription)
        }
    }

    static func validate(_ catalog: AllergenCatalog) throws {
        guard catalog.schemaVersion > 0,
              !catalog.jurisdiction.isEmpty,
              !catalog.regulation.name.isEmpty,
              !catalog.sources.isEmpty else {
            throw AllergenStoreError.malformedRecord("Katalog üst bilgisi eksik.")
        }

        guard catalog.allergens.count == 14 else {
            throw AllergenStoreError.invalidGroupCount(catalog.allergens.count)
        }

        try ensureUnique(catalog.sources.map(\.id), label: "kaynak")
        try ensureUnique(catalog.allergens.map(\.id), label: "alerjen grubu")
        try ensureUnique(catalog.allergens.map(\.order), label: "düzenleyici sıra")

        let sourceIDs = Set(catalog.sources.map(\.id))

        for allergen in catalog.allergens {
            guard !allergen.id.isEmpty,
                  (1...14).contains(allergen.order),
                  !allergen.name.isEmpty,
                  !allergen.regulatoryName.isEmpty,
                  !allergen.description.isEmpty,
                  !allergen.terms.isEmpty,
                  !allergen.sourceIDs.isEmpty,
                  allergen.sourceIDs.allSatisfy(sourceIDs.contains) else {
                throw AllergenStoreError.malformedRecord(allergen.id)
            }

            try validateTerms(allergen.terms, owner: allergen.id)
            try ensureUnique(allergen.members.map(\.id), label: "\(allergen.id) üyesi")
            try ensureUnique(allergen.exceptions.map(\.id), label: "\(allergen.id) istisnası")
            try ensureUnique(allergen.conditions.map(\.id), label: "\(allergen.id) koşulu")

            for member in allergen.members {
                guard !member.id.isEmpty, !member.name.isEmpty, !member.terms.isEmpty else {
                    throw AllergenStoreError.malformedRecord("\(allergen.id)/\(member.id)")
                }
                try validateTerms(member.terms, owner: "\(allergen.id)/\(member.id)")
            }
        }

        try validatePeanutAndPistachio(in: catalog.allergens)
        try validateSulfiteThreshold(in: catalog.allergens)
    }

    private static func validateTerms(_ terms: [IngredientTerm], owner: String) throws {
        let values = terms.map(\.value)
        let turkishCharacters = CharacterSet(charactersIn: "çğıöşüÇĞİÖŞÜ")
        let languages = Set(["tr", "en", "und"])
        guard terms.allSatisfy({ term in
            !term.value.isEmpty &&
            term.value == term.value.trimmingCharacters(in: .whitespacesAndNewlines) &&
            term.value == term.value.lowercased(with: Locale(identifier: "tr_TR")) &&
            term.value.rangeOfCharacter(from: turkishCharacters) == nil &&
            !term.value.contains("  ") &&
            !term.value.contains("\n") &&
            languages.contains(term.language) &&
            !term.kind.isEmpty
        }) else {
            throw AllergenStoreError.malformedRecord("\(owner) eşleşme terimi")
        }
        try ensureUnique(values, label: "\(owner) eşleşme terimi")
    }

    private static func validatePeanutAndPistachio(in allergens: [Allergen]) throws {
        guard let peanut = allergens.first(where: { $0.id == "peanuts" }),
              let treeNuts = allergens.first(where: { $0.id == "tree-nuts" }),
              treeNuts.members.contains(where: { $0.id == "pistachio" }),
              !peanut.members.contains(where: { $0.id == "pistachio" }),
              !peanut.terms.contains(where: { $0.value.contains("antep fistigi") || $0.value == "pistachio" }) else {
            throw AllergenStoreError.peanutPistachioConflict
        }
    }

    private static func validateSulfiteThreshold(in allergens: [Allergen]) throws {
        guard let sulfites = allergens.first(where: { $0.id == "sulfur-dioxide-sulfites" }),
              sulfites.conditions.contains(where: {
                  $0.type == "threshold" &&
                  $0.basis == "total_so2" &&
                  $0.comparison == "greater_than" &&
                  $0.value == 10 &&
                  Set($0.units) == Set(["mg/kg", "mg/L"])
              }) else {
            throw AllergenStoreError.malformedRecord("Kükürt dioksit ve sülfit eşiği")
        }
    }

    private static func ensureUnique<T: Hashable>(_ values: [T], label: String) throws {
        guard Set(values).count == values.count else {
            throw AllergenStoreError.duplicateID(label)
        }
    }
}

enum AllergenStoreError: LocalizedError {
    case missingResource
    case readFailed(String)
    case decodingFailed(String)
    case invalidGroupCount(Int)
    case duplicateID(String)
    case malformedRecord(String)
    case peanutPistachioConflict

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "Alerjen bilgi tabanı uygulama paketinde bulunamadı."
        case .readFailed(let detail):
            "Alerjen bilgi tabanı okunamadı: \(detail)"
        case .decodingFailed(let detail):
            "Alerjen bilgi tabanı çözümlenemedi: \(detail)"
        case .invalidGroupCount(let count):
            "Alerjen bilgi tabanında 14 yerine \(count) grup var."
        case .duplicateID(let label):
            "Yinelenen kimlik bulundu: \(label)."
        case .malformedRecord(let id):
            "Eksik veya hatalı kayıt bulundu: \(id)."
        case .peanutPistachioConflict:
            "Yer fıstığı ile Antep fıstığı ayrı düzenleyici gruplarda tutulmalıdır."
        }
    }
}
