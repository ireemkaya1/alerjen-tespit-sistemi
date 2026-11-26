import Foundation

struct AllergenDetector {
    private struct Entry {
        let groupID: String?
        let name: String
        let memberID: String?
        let term: String
        let isCategory: Bool
        let needsContext: Bool
    }

    private struct Hit {
        let entry: Entry
        let range: NSRange
    }

    private let entries: [String: [Entry]]
    private let matcher: NSRegularExpression

    private static let negativePredicates = ["icermez", "icermiyor", "icermemektedir"]
    private static let positivePredicates = ["icermektedir", "icerir"]
    private static let predicate = #"\b(?:"# +
        (negativePredicates + positivePredicates + ["icerebilir"]).joined(separator: "|") + #")\b"#
    private static let glutenFreeClaims = ["glutensiz", "glutensizdir", "gluten free"]
    private static let trace = #"\b(?:eser|iz) miktarda\b"#
    private static let shortItem = #"\p{L}+(?:\s+\p{L}+)?"#
    private static let headings = #"\bal[ae]rjen uyarisi\b[ \t]*[:–—-]?|\buyari[ \t]*[:–—-]|\b(?:icindekiler|bilesenler|alerjen bilgisi|besin degeri|besin degerleri|beslenme bildirimi|besin ogeleri|enerji ve besin ogeleri|saklama kosullari|saklama talimati|muhafaza kosullari|kullanim talimati|uretici firma|uretici bilgileri|gida isletmecisi|mense ulke|ingredients|allergen information|nutrition facts)\b[ \t]*:?|\b(?:alerjenler|alerjen|uretici|storage)[ \t]*:"#
    private static let sectionBoundary = headings + #"|[\n;!?]|(?<![0-9])\.|\.(?![0-9])"#
    private static let unrelated = #"\b(?:ambalaj|muhafaza|saklayiniz|saklama|tuketiniz|intoleransi|uygundur|urunlerle|aromali|aromasi)\b"#
    private static let qualifiers = [
        "milk": #"\b(?:(?:soya|yulaf|badem|pirinc|hindistan cevizi|bitkisel) (?:bazli )?sutu?|(?:soy|soya|oat|almond|rice|coconut|plant|plant-based) milk|(?:peanut|almond|cocoa) butter|(?:soy|oat|coconut|plant|plant-based|vegan|bitkisel) (?:cream|cheese|yogurt|yoghurt|krema|peynir))\b"#,
        "gluten-cereals": #"\bmisir irmi(?:gi|k)\b"#,
        "fish": #"\bmurekkep bali(?:gi|k)\b"#,
        "tree-nuts": #"\bhindistan cevi(?:zi|z)\b"#
    ]

    init(catalog: AllergenCatalog) throws {
        var terms: [Entry] = []
        for group in catalog.allergens {
            for (memberID, items) in [(nil as String?, group.terms)] +
                group.members.map({ (Optional($0.id), $0.terms) }) {
                for term in items {
                    terms.append(Entry(
                        groupID: group.id, name: group.name, memberID: memberID, term: term.value,
                        isCategory: term.kind == "group",
                        needsContext: ["arachis", "tofu", "tempeh", "tahin", "tahini", "scallop", "cream", "krema",
                                       "balik jelatini", "fish gelatin"].contains(term.value)
                    ))
                }
            }
        }
        if let gluten = catalog.allergens.first(where: { $0.id == "gluten-cereals" }) {
            for term in Self.glutenFreeClaims {
                terms.append(Entry(groupID: gluten.id, name: gluten.name, memberID: nil,
                                   term: term, isCategory: true, needsContext: false))
            }
        }
        for term in ["fistik", "fistigi"] {
            terms.append(Entry(groupID: nil, name: "Türü belirlenemeyen fıstık", memberID: nil,
                               term: term, isCategory: false, needsContext: true))
        }

        entries = Dictionary(grouping: terms, by: \.term)
        let alternatives = entries.keys.sorted {
            $0.count == $1.count ? $0 < $1 : $0.count > $1.count
        }.map(NSRegularExpression.escapedPattern(for:))
        let patterns = alternatives + [#"e[ -](?:220|221|222|223|224|226|227|228)"#]
        matcher = try NSRegularExpression(pattern: #"\b(?:"# + patterns.joined(separator: "|") + #")\b"#)
    }

    func detect(in text: String) -> [AllergenDetection] {
        let input = text as NSString
        var grouped: [String?: [AllergenEvidence]] = [:]
        var names: [String?: String] = [:]
        var order: [String?] = []
        var ingredients = false
        var cursor = 0

        func inspect(_ range: NSRange) {
            for (entry, evidence) in inspectStatement(input.substring(with: range), offset: range.location,
                                                      ingredients: ingredients) {
                if grouped[entry.groupID] == nil {
                    order.append(entry.groupID)
                    names[entry.groupID] = entry.name
                }
                grouped[entry.groupID, default: []].append(evidence)
            }
        }

        let boundaries = Self.matches(Self.sectionBoundary, in: text)
        for (index, boundary) in boundaries.enumerated() {
            let before = NSRange(location: cursor, length: boundary.range.location - cursor)
            let label = input.substring(with: boundary.range).trimmingCharacters(in: .whitespaces)
            if label == "\n" {
                let nextStart = NSMaxRange(boundary.range)
                let nextEnd = index + 1 < boundaries.count ? boundaries[index + 1].range.location : input.length
                let left = input.substring(with: before)
                let right = input.substring(with: NSRange(location: nextStart, length: nextEnd - nextStart))
                if continuesAllergenList(before: left, after: right) { continue }
            }
            inspect(before)
            let delimiter = label.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            switch delimiter {
            case "icindekiler", "bilesenler":
                let end = NSMaxRange(boundary.range)
                ingredients = label.hasSuffix(":") ||
                    (end < input.length && input.character(at: end) == 10)
            case "\n":
                let line = input.substring(with: before).trimmingCharacters(in: .whitespaces)
                ingredients = ingredients && (line.isEmpty || line.hasSuffix(","))
            default:
                ingredients = false
            }
            cursor = NSMaxRange(boundary.range)
        }
        inspect(NSRange(location: cursor, length: input.length - cursor))

        return order.compactMap { id in
            guard let name = names[id], let items = grouped[id] else { return nil }
            let ranked = items.sorted {
                if $0.strength != $1.strength { return $0.strength.rawValue > $1.strength.rawValue }
                return $0.range.location < $1.range.location
            }
            var distinct: [AllergenEvidence] = []
            for item in ranked where !distinct.contains(where: {
                $0.term == item.term && $0.memberID == item.memberID &&
                $0.classification == item.classification && $0.context == item.context
            }) {
                distinct.append(item)
            }
            return AllergenDetection(groupID: id, name: name, evidence: distinct)
        }
    }

    private func continuesAllergenList(before left: String, after right: String) -> Bool {
        let leftLine = left.components(separatedBy: "\n").last ?? ""
        let leftSource = leftLine as NSString
        let rightSource = right as NSString
        guard let last = matcher.matches(in: leftLine, range: NSRange(location: 0, length: leftSource.length)).last else {
            return false
        }

        let trailing = leftSource.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
        let positive = #"\b(?:"# + Self.positivePredicates.joined(separator: "|") + #")\b"#
        if ["ve", ", ve"].contains(trailing),
           !Self.matches(#"^\s*"# + Self.shortItem + #"\s+"# + positive, in: right).isEmpty {
            return true
        }
        guard let first = matcher.firstMatch(in: right, range: NSRange(location: 0, length: rightSource.length)) else {
            return false
        }
        let leading = rightSource.substring(to: first.range.location).trimmingCharacters(in: .whitespaces)
        let joiners = [",", "ve", "veya", ", ve", ", veya"]
        // Preserve the original newline and offsets. Only an explicit joiner can bridge it.
        return (trailing.isEmpty && joiners.contains(leading)) ||
            (joiners.contains(trailing) && (leading.isEmpty || ["ve", "veya"].contains(leading)))
    }

    private func inspectStatement(_ statement: String, offset: Int, ingredients: Bool) -> [(Entry, AllergenEvidence)] {
        let source = statement as NSString
        // A parenthetical declaration has its own scope within the surrounding ingredient list.
        let declarations = Self.matches(#"\([^()]*"# + Self.predicate + #"[^()]*\)"#, in: statement)
            .filter { matcher.firstMatch(in: statement, range: $0.range) != nil }
        var scopes: [NSRange] = []
        var start = 0
        for declaration in declarations {
            scopes.append(NSRange(location: start, length: declaration.range.location - start))
            scopes.append(declaration.range)
            start = NSMaxRange(declaration.range)
        }
        scopes.append(NSRange(location: start, length: source.length - start))

        return scopes.flatMap { scope in
            let local = source.substring(with: scope)
            let localSource = local as NSString
            let entire = NSRange(location: 0, length: localSource.length)
            let qualifiedRanges = Self.qualifiers.mapValues { Self.matches($0, in: local).map(\.range) }
            let hits: [Hit] = matcher.matches(in: local, range: entire).flatMap { match in
                let value = localSource.substring(with: match.range)
                let key = value.hasPrefix("e ") || value.hasPrefix("e-")
                    ? value.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
                    : value
                return (entries[key] ?? []).compactMap { entry -> Hit? in
                    if let id = entry.groupID,
                       qualifiedRanges[id]?.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) == true {
                        return nil
                    }
                    return Hit(entry: entry, range: match.range)
                }
            }
            let predicates = Self.matches(Self.predicate, in: local)
            return hits.map { hit in
                let (classification, strength, reason, threshold) = classify(
                    hit, hits: hits, predicates: predicates, local: local, ingredients: ingredients
                )
                return (hit.entry, AllergenEvidence(
                    memberID: hit.entry.memberID, term: hit.entry.term,
                    range: NSRange(location: offset + scope.location + hit.range.location, length: hit.range.length),
                    context: statement.trimmingCharacters(in: .whitespacesAndNewlines),
                    classification: classification, strength: strength, reason: reason, sulfiteThreshold: threshold
                ))
            }
        }
    }

    private func classify(
        _ hit: Hit, hits: [Hit], predicates: [NSTextCheckingResult], local: String, ingredients: Bool
    ) -> (AllergenClassification, AllergenEvidenceStrength, String, SulfiteThreshold?) {
        let entry = hit.entry
        let source = local as NSString
        let unresolved: AllergenClassification = .unresolved

        if entry.groupID == nil {
            return (unresolved, .mention, "İfade fıstığın türünü belirtmiyor.", nil)
        }
        if entry.groupID == "gluten-cereals", Self.glutenFreeClaims.contains(entry.term) {
            let claim = local.trimmingCharacters(in: .whitespacesAndNewlines)
            let productPrefixes = ["", "bu urun ", "urun ", "this product is "]
            if productPrefixes.contains(where: { claim == $0 + entry.term }) {
                return (.negativeClaim, .explicitStatement, "Gluten için açık bir yokluk beyanı var.", nil)
            }
            return (unresolved, .mention, "Gluten yokluğu ifadesinin ürüne ait açık bir beyan olduğu doğrulanamadı.", nil)
        }
        let claim = Self.linkedClaim(for: hit, hits: hits, predicates: predicates, in: source)
        if entry.groupID == "sulfur-dioxide-sulfites" {
            let threshold = Self.sulfiteThreshold(in: local)
            if claim == .negativeClaim {
                return (.negativeClaim, .explicitStatement, "Etikette sülfit bulunmadığı beyan ediliyor.", threshold)
            }
            if threshold == .exceeded, claim != .mayContain {
                return (.contains, .explicitStatement, "Tüketime hazır ürün için belirtilen toplam SO₂, bildirim eşiğini aşıyor.", threshold)
            }
            if claim == .mayContain {
                return (.mayContain, .explicitStatement, "İhtiyati sülfit beyanı var. Bu beyan tek başına konsantrasyonu göstermez.", threshold)
            }
            let reason = threshold == .atOrBelow
                ? "Belirtilen toplam SO₂, bildirim eşiğini aşmıyor."
                : "Sülfit adı veya E kodu bulundu. Tüketime hazır ürünün toplam SO₂ konsantrasyonu doğrulanamadı."
            if claim == .contains {
                return (.contains, .explicitStatement, "Etikette sülfit bulunduğu beyan ediliyor. " + reason, threshold)
            }
            return (unresolved, .mention, reason, threshold)
        }
        if let claim {
            let reason: String
            switch claim {
            case .contains: reason = "Terim açık bir içerik beyanına bağlı."
            case .mayContain: reason = "Terim ihtiyati veya eser miktar beyanına bağlı."
            case .negativeClaim: reason = "Terim açık bir yokluk beyanına bağlı."
            case .unresolved: reason = "Beyanın kapsamı belirlenemedi."
            }
            return (claim, .explicitStatement, reason, nil)
        }
        if ingredients, predicates.isEmpty, !entry.isCategory, !entry.needsContext,
           Self.matches(Self.trace + "|" + Self.unrelated +
                        #"|\b(?:free|without|vegan|bitkisel|glutensiz|icermeyen|bulunmaz|yok|yoktur)\b"#,
                        in: local).isEmpty,
           !Self.needsExceptionReview(entry, in: local) {
            return (.contains, .ingredientList, "Terim, belirlenen içindekiler bölümünde bileşen olarak geçiyor.", nil)
        }
        return (unresolved, .mention, "Terimin bileşen veya açık bir alerjen beyanı olduğu doğrulanamadı.", nil)
    }

    private static func linkedClaim(
        for hit: Hit, hits: [Hit], predicates: [NSTextCheckingResult], in source: NSString
    ) -> AllergenClassification? {
        guard let next = predicates.first(where: { $0.range.location >= NSMaxRange(hit.range) }) else {
            return nil
        }
        let previousEnd = predicates.last(where: { NSMaxRange($0.range) <= hit.range.location })
            .map { NSMaxRange($0.range) } ?? 0
        let end = next.range.location
        let list = NSMutableString(string: source.substring(
            with: NSRange(location: previousEnd, length: end - previousEnd)
        ))
        // Remove only whole matched terms. What remains must look like a declaration list.
        let positions = Set(hits.map(\.range)).filter {
            $0.location >= previousEnd && NSMaxRange($0) <= end
        }.sorted { $0.location < $1.location }
        for range in positions.reversed() {
            list.replaceCharacters(in: NSRange(location: range.location - previousEnd, length: range.length),
                                   with: " ")
        }
        let remaining = list as String
        let allowed = #"\b(?:bu urun|urun|alerjenler|veya|ve|ancak|fakat|eser miktarda|iz miktarda)\b|[\s,:()/]"#
        let word = source.substring(with: next.range)
        let allItemsRecognized = remaining.replacingOccurrences(of: allowed, with: "", options: .regularExpression).isEmpty
        guard allItemsRecognized || (
            positivePredicates.contains(word) &&
            hasRecognizedListBeforeUnknown(positions, start: previousEnd, end: end, in: source)
        ) else {
            return nil
        }
        let tail = source.substring(from: NSMaxRange(next.range))
        let startsNewTraceClause = !matches(#"^[\s)]*(?:,|\b(?:ve|ancak|fakat)\b)\s*"# + trace, in: tail).isEmpty
        if !startsNewTraceClause {
            guard matches(#"\b(?:eger|halinde|durumunda)\b"#, in: tail).isEmpty else { return nil }
            if let following = predicates.first(where: { $0.range.location > next.range.location }),
               !hits.contains(where: {
                   $0.range.location >= NSMaxRange(next.range) && NSMaxRange($0.range) <= following.range.location
               }) {
                return nil
            }
        }
        guard tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !matches(#"^[\s)]*(?:$|,|\b(?:ve|ancak|fakat)\b)"#, in: tail).isEmpty ||
            predicates.contains(where: { $0.range.location > next.range.location }) else {
            return nil
        }
        if negativePredicates.contains(word) { return .negativeClaim }
        if word == "icerebilir" || !matches(trace, in: remaining).isEmpty { return .mayContain }
        return .contains
    }

    private static func hasRecognizedListBeforeUnknown(
        _ terms: [NSRange], start: Int, end: Int, in source: NSString
    ) -> Bool {
        guard terms.count >= 2, let first = terms.first, let last = terms.last else { return false }
        let prefix = source.substring(with: NSRange(location: start, length: first.location - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["", "bu urun", "urun"].contains(prefix) else { return false }
        for (left, right) in zip(terms, terms.dropFirst()) {
            let gap = source.substring(with: NSRange(location: NSMaxRange(left), length: right.location - NSMaxRange(left)))
            guard !matches(#"^\s*(?:,\s*(?:ve\s+)?|\bve\s+)$"#, in: gap).isEmpty else { return false }
        }
        // One short, explicitly conjoined item may be unreadable. Only exact hits get evidence.
        let tail = source.substring(with: NSRange(location: NSMaxRange(last), length: end - NSMaxRange(last)))
        guard let match = matches(#"^\s*,?\s+ve\s+("# + shortItem + #")\s*$"#, in: tail).first else { return false }
        let unknown = (tail as NSString).substring(with: match.range(at: 1))
        return matches(trace + "|" + unrelated + #"|\b(?:eger|halinde|durumunda|degil|yok|olabilir|bitkisel|ve|veya)\b"#,
                       in: unknown).isEmpty
    }

    private static func needsExceptionReview(_ entry: Entry, in text: String) -> Bool {
        let pattern: String
        switch entry.groupID {
        case "gluten-cereals": pattern = #"\b(?:glukoz|glikoz|maltodekstrin|distilat|distile)\b"#
        case "soybeans": pattern = #"\b(?:yagi|yag|rafine|tokoferol|sterol|stanol)\b"#
        case "milk", "tree-nuts": pattern = #"\b(?:distilat|distile)\b"#
        default: return false
        }
        return !matches(pattern, in: text).isEmpty
    }

    private static func sulfiteThreshold(in text: String) -> SulfiteThreshold {
        let ready = #"\b(?:tuketime hazir|uretici talimat(?:ina|larina) gore hazirlanmis)\b"#
        let amount = #"\btoplam so[2₂][ \t]*(?::|=)?[ \t]*([0-9]+(?:[.,][0-9]+)?)[ \t]*mg[ \t]*/[ \t]*(?:kg|l)\b[ \t)]*$"#
        let measurements = matches(amount, in: text)
        guard !matches(ready, in: text).isEmpty, measurements.count == 1,
              matches(#"\b(?:en fazla|en az|yaklasik|kadar|asmaz|gecmez|sinir|limit|ornegin|varsayilan|olabilir|icerebilir)\b|[<>≤≥~]"#, in: text).isEmpty,
              let match = measurements.first, let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range].replacingOccurrences(of: ",", with: ".")) else {
            return .unresolved
        }
        return value > 10 ? .exceeded : .atOrBelow
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
