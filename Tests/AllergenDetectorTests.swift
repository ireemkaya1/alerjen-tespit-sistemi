import Foundation

let data = try Data(contentsOf: URL(fileURLWithPath: "AlerjenTespitSistemi/Data/allergens.json"))
let catalog = try JSONDecoder().decode(AllergenCatalog.self, from: data)
try AllergenStore.validate(catalog)
let detector = try AllergenDetector(catalog: catalog)

func inspect(_ text: String) -> [AllergenDetection] {
    detector.detect(in: TextPrep.normalize(text))
}

func evidence(_ results: [AllergenDetection], _ group: String?) -> [AllergenEvidence] {
    results.first(where: { $0.groupID == group })?.evidence ?? []
}

func expect(_ outcome: Bool, _ message: String) {
    guard outcome else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let ingredients = inspect("icindekiler: bugday unu (gluten icerir), sut tozu.")
expect(evidence(ingredients, "gluten-cereals").contains { $0.classification == .contains }, "A: gluten")
expect(evidence(ingredients, "milk").map(\.term) == ["sut tozu"], "A: longest milk match")
expect(evidence(ingredients, "milk").first?.classification == .contains, "A: milk powder")

let nuts = evidence(inspect("alerjen uyarisi: eser miktarda findik ve badem icerebilir."), "tree-nuts")
expect(Set(nuts.compactMap(\.memberID)) == ["hazelnut", "almond"], "B: both nut members")
expect(nuts.allSatisfy { $0.classification == .mayContain }, "B: precaution")
let commas = evidence(inspect("iz miktarda findik, badem, susam icerebilir."), "tree-nuts")
expect(commas.count == 2 && commas.allSatisfy { $0.classification == .mayContain }, "comma-separated list")

let negative = evidence(inspect("alerjen uyarisi: gluten icermez."), "gluten-cereals")
expect(negative.map(\.classification) == [.negativeClaim], "C: only negative evidence")
expect(evidence(inspect("gluten icerir"), "gluten-cereals").map(\.classification) == [.contains],
       "explicit contains")
let mixed = inspect("sut icermektedir ancak gluten icermez.")
expect(evidence(mixed, "milk").map(\.classification) == [.contains] &&
       evidence(mixed, "gluten-cereals").map(\.classification) == [.negativeClaim], "mixed statement scope")
expect(evidence(inspect("iz miktarda susam icerebilir"), "sesame").map(\.classification) == [.mayContain],
       "iz miktarda")
expect(evidence(inspect("glutensiz"), "gluten-cereals").map(\.classification) == [.negativeClaim], "explicit gluten-free")
expect(evidence(inspect("glutensiz urunlerle saklayiniz"), "gluten-cereals").map(\.classification) == [.unresolved],
       "gluten-free wording about another product")

let mentions = evidence(inspect("gluten intoleransi olan bireyler icin uygundur. ambalaj acildiktan sonra gluten iceren urunlerle ayni ortamda muhafaza etmeyiniz."), "gluten-cereals")
expect(mentions.count == 2 && mentions.allSatisfy { $0.classification == .unresolved }, "D: contextual mentions")
expect(evidence(inspect("icindekiler: misir irmigi."), "gluten-cereals").isEmpty, "E: corn semolina")
expect(evidence(inspect("icindekiler: hindistan cevizi."), "tree-nuts").isEmpty, "F: coconut")

let soy = inspect("icindekiler: soya sutu.")
expect(evidence(soy, "soybeans").map(\.term) == ["soya sutu"], "G: soy milk phrase")
expect(evidence(soy, "milk").isEmpty, "G: no dairy")

let pistachio = inspect("eser miktarda antep fistigi icerebilir.")
expect(evidence(pistachio, "tree-nuts").first?.memberID == "pistachio", "H: pistachio group and member")
expect(evidence(pistachio, "tree-nuts").first?.classification == .mayContain, "H: precaution")
expect(evidence(pistachio, "peanuts").isEmpty, "H: no peanut")

let sulfites = evidence(inspect("sodyum metabisulfit (e223)"), "sulfur-dioxide-sulfites")
expect(Set(sulfites.map(\.term)) == ["sodyum metabisulfit", "e223"], "I: both sulfite mentions")
expect(sulfites.allSatisfy { $0.sulfiteThreshold == .unresolved && $0.classification == .unresolved },
       "I: unknown total SO2")
for (amount, threshold): (String, SulfiteThreshold) in [("10", .atOrBelow), ("10,1", .exceeded)] {
    let measured = evidence(inspect("e-223, tuketime hazir urunde toplam so2: \(amount) mg/kg."), "sulfur-dioxide-sulfites")
    expect(measured.first?.sulfiteThreshold == threshold, "strict threshold at \(amount)")
}
let missingBasis = evidence(inspect("e 223, toplam so2: 15 mg/l."), "sulfur-dioxide-sulfites")
expect(missingBasis.first?.sulfiteThreshold == .unresolved, "measurement basis required")

let conflicting = evidence(inspect("icindekiler: sut tozu, sut tozu. alerjen uyarisi: sut icermez."), "milk")
expect(conflicting.count == 2 && Set(conflicting.map(\.classification)) == [.contains, .negativeClaim],
       "retain conflicting statements and deduplicate repeated terms")
let qualified = inspect("icindekiler: badem sut, vegan peynir, yer fistigi ezmesi.")
expect(evidence(qualified, "milk").allSatisfy { $0.classification != .contains }, "qualified dairy-like phrases")
expect(evidence(qualified, "peanuts").map(\.term) == ["yer fistigi ezmesi"], "longest peanut phrase")
expect(evidence(inspect("icindekiler: fistik"), nil).map(\.classification) == [.unresolved], "bare ambiguous nut")
expect(evidence(inspect("icindekiler: su, besin degerleri: sut"), "milk").map(\.classification) == [.unresolved],
       "stop at nutrition heading")
expect(evidence(inspect("icindekiler: su,\ningredients: milk"), "milk").map(\.classification) == [.unresolved],
       "stop at English heading")
expect(evidence(inspect("icindekiler:\nsu,\nsut tozu."), "milk").map(\.classification) == [.contains],
       "wrapped ingredient list")
expect(evidence(inspect("icindekiler: bugday glukoz surubu."), "gluten-cereals").map(\.classification) == [.unresolved],
       "possible labeling exception")
expect(evidence(inspect("icindekiler: sut icermeyen cikolata."), "milk").map(\.classification) == [.unresolved],
       "do not infer dairy from an unsupported negative formulation")
expect(evidence(inspect("icindekiler: findik (icerebilir)."), "tree-nuts").map(\.classification) == [.mayContain],
       "parenthetical predicate governs preceding term")
expect(evidence(inspect("gluten icerir, eger bugday unu eklenirse."), "gluten-cereals")
    .allSatisfy { $0.classification == .unresolved }, "conditional wording")
let rangeText = "🍽 alerjen uyarisi: eser miktarda susam icerebilir."
let sesame = evidence(inspect(rangeText), "sesame")
expect(sesame.first?.classification == .mayContain, "trace claim")
expect(sesame.first.map { (rangeText as NSString).substring(with: $0.range) } == "susam", "UTF-16 range")
expect(inspect("seker, sutlac, findikli").isEmpty, "whole-word boundaries")

let warningMembers: Set<String> = ["pistachio", "almond", "hazelnut", "walnut", "cashew"]
for warning in [
    "eser miktarda antep fistigi, badem, findik, ceviz, kaju fistigi icerebilir.",
    "eser miktarda antep fistigi, badem,\nfindik, ceviz, kaju fistigi icerebilir.",
    "eser miktarda antep fistigi, badem,\nfindik, ceviz\nve kaju fistigi icerebilir."
] {
    let items = evidence(inspect(warning), "tree-nuts")
    expect(Set(items.compactMap(\.memberID)) == warningMembers &&
           items.allSatisfy { $0.classification == .mayContain }, "coordinated warning A")
    expect(items.allSatisfy { (warning as NSString).substring(with: $0.range) == $0.term },
           "coordinated warning preserves original ranges")
}

let peanut = inspect("icindekiler: kavrulmus yer fistigi, tuz.\nyer fistigi").first
expect(peanut?.groupID == "peanuts" && peanut?.primaryClassification == .contains &&
       peanut?.summary == "İçeriyor", "peanut summary B")
expect(peanut.map { Set($0.evidence.map(\.classification)) } == [.contains, .unresolved],
       "peanut summary B preserves both details")

let threeNuts = evidence(inspect("eser miktarda badem, findik ve ceviz icerebilir."), "tree-nuts")
expect(threeNuts.count == 3 && threeNuts.allSatisfy { $0.classification == .mayContain },
       "coordinated warning C")

for sample in [
    "badem. urunu serin yerde saklayiniz. findik icerebilir.",
    "badem\n\nfindik icerebilir.",
    "badem,\n\nfindik icerebilir.",
    "badem,\nbesin degerleri: findik icerebilir.",
    "badem,\nsaklama kosullari: findik icerebilir.",
    "badem,\nuretici firma: findik icerebilir."
] {
    let items = evidence(inspect(sample), "tree-nuts")
    expect(items.first(where: { $0.memberID == "almond" })?.classification == .unresolved &&
           items.first(where: { $0.memberID == "hazelnut" })?.classification == .mayContain,
           "statement boundary D: \(sample)")
}

let contradiction = inspect("icindekiler: sut tozu. sut icermez.").first
expect(contradiction?.summary == "İçeriyor · Çelişkili beyan" &&
       contradiction?.evidence.count == 2, "contradiction remains visible")
let differentMembers = inspect("icindekiler: badem. findik icermez.").first
expect(differentMembers?.hasConflictingEvidence == false, "different nut members are not contradictory")

for claim in [
    "alarjen uyarisi:gluten icermez.",
    "alarjen uyarisi: gluten icermez.",
    "alerjen uyarisi:gluten icermez.",
    "alerjen uyarisi: gluten icermez.",
    "uyari - gluten icermez.",
    "glutensiz.",
    "glutensizdir",
    "gluten free",
    "bu urun glutensiz",
    "this product is gluten free."
] {
    let groups = inspect(claim)
    expect(groups.map(\.groupID) == ["gluten-cereals"] &&
           groups.first?.evidence.map(\.classification) == [.negativeClaim] &&
           groups.first?.summary == "İçermediği beyan ediliyor", "gluten negative claim: \(claim)")
}

for claim in ["glutensiz fabrika", "gluten free factory"] {
    expect(evidence(inspect(claim), "gluten-cereals").map(\.classification) == [.unresolved],
           "ambiguous gluten claim: \(claim)")
}

for (claim, group) in [
    ("sut icermez", "milk"),
    ("sut icermiyor", "milk"),
    ("yer fistigi icermemektedir", "peanuts")
] {
    expect(evidence(inspect(claim), group).map(\.classification) == [.negativeClaim],
           "negative predicate: \(claim)")
}

let glutenConflict = inspect("icindekiler: bugday unu (gluten icerir). gluten icermez.").first
expect(glutenConflict?.groupID == "gluten-cereals" &&
       glutenConflict.map { Set($0.evidence.map(\.classification)) } == [.contains, .negativeClaim] &&
       glutenConflict?.summary == "İçeriyor · Çelişkili beyan", "opposing gluten declarations")

let storage = inspect("ambalaj acildiktan sonra gluten iceren urunlerle ayni ortamda muhafaza etmeyiniz.")
expect(evidence(storage, "gluten-cereals").map(\.classification) == [.unresolved],
       "storage mention does not assert gluten")

for predicate in ["icerir", "icermektedir"] {
    let items = inspect("yumurta, badem ve findik \(predicate).").flatMap(\.evidence)
    expect(Set(items.map(\.term)) == ["yumurta", "badem", "findik"] &&
           items.allSatisfy { $0.classification == .contains }, "Biscotti A: positive list with \(predicate)")
}

for label in [
    "yumurta, badem ve kukurt dioksit icerir, iz miktarda susam ve findik icerebilir.",
    "yumurta,\nbadem ve kukurt dioksit icerir,\niz miktarda susam ve\nfindik icerebilir.",
    "icindekiler: yumurta,\nbadem ve kukurt dioksit icerir,\niz miktarda susam ve findik icerebilir."
] {
    let items = inspect(label).flatMap(\.evidence)
    let positive: Set<String> = ["yumurta", "badem", "kukurt dioksit"]
    let precaution: Set<String> = ["susam", "findik"]
    expect(Set(items.filter { $0.classification == .contains }.map(\.term)) == positive &&
           Set(items.filter { $0.classification == .mayContain }.map(\.term)) == precaution,
           "Biscotti B/C: positive and precautionary scopes")
    expect(items.first(where: { $0.term == "kukurt dioksit" })?.sulfiteThreshold == .unresolved,
           "Biscotti B/C: sulfite presence claim does not establish its threshold")
    expect(items.allSatisfy { (label as NSString).substring(with: $0.range) == $0.term },
           "Biscotti B/C: preserve evidence ranges")
}

for label in [
    "yumurta, badem ve kukurt doksit icerir, iz miktarda stisam, f ... findik ...",
    "yumurta, badem ve\nkukurt doksit icermektedir, iz miktarda stisam, findik icerebilir.",
    "yumurta, badem ve kukurt doksit icerir, iz miktarda stisam icerebilir."
] {
    let items = inspect(label).flatMap(\.evidence)
    expect(Set(items.filter { $0.classification == .contains }.map(\.term)) == ["yumurta", "badem"],
           "Biscotti OCR: exact positives survive an unreadable final item")
    expect(Set(items.map(\.term)).isSubset(of: ["yumurta", "badem", "findik"]) &&
           items.filter { $0.term == "findik" }.allSatisfy { $0.classification == .unresolved },
           "Biscotti OCR: unknown terms stay unmatched and unclear precaution stays unresolved")
}

let recoveredWarning = inspect("yumurta, badem ve kukurt doksit icerir, iz miktarda findik icerebilir.")
expect(evidence(recoveredWarning, "tree-nuts").first(where: { $0.term == "findik" })?.classification == .mayContain,
       "Biscotti OCR: independently readable precaution")

for label in [
    "gluten intoleransi olan bireyler icin uygundur.",
    "ambalaj acildiktan sonra gluten iceren urunlerle ayni ortamda muhafaza etmeyiniz.",
    "badem ve yumurta aromali biscotti",
    "yumurta, badem ve ambalaj bilgisi icerir."
] {
    let items = inspect(label).flatMap(\.evidence)
    expect(!items.isEmpty && items.allSatisfy { $0.classification == .unresolved },
           "Biscotti D/E and ambiguous context: \(label)")
}

print("PASS: original detector and coordinated-context, negative-claim, and Biscotti regression checks")
