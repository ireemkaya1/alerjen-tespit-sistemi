import Foundation

struct TextPrep {
    nonisolated static func normalize(_ text: String) -> String {
        let lineNormalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "tr_TR"))

        let characterNormalized = String(lineNormalized.map { character in
            switch character {
            case "ç": return "c"
            case "ğ": return "g"
            case "ı": return "i"
            case "ö": return "o"
            case "ş": return "s"
            case "ü": return "u"
            default: return character
            }
        })

        var lines = characterNormalized
            .components(separatedBy: "\n")
            .map { line in
                line.split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
            }

        while lines.first?.isEmpty == true {
            lines.removeFirst()
        }

        while lines.last?.isEmpty == true {
            lines.removeLast()
        }

        return lines.joined(separator: "\n")
    }
}
