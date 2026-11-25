import Foundation

/// Text mit HTML-Zeichen wie „&lt;“ oder „&#228;“ in normale Zeichen umwandeln
/// (Ticket-Betreffe aus ManageEngine, frühere Anfragen von Claude).
public enum HTMLText {
    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß"]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        // numerisch: &#228; oder &#xE4;
        while let start = result.range(of: "&#"), let end = result.range(of: ";", range: start.upperBound..<result.endIndex),
              result.distance(from: start.upperBound, to: end.lowerBound) <= 7 {
            let body = result[start.upperBound..<end.lowerBound]
            let scalar = body.hasPrefix("x") || body.hasPrefix("X")
                ? UInt32(body.dropFirst(), radix: 16)
                : UInt32(body)
            let replacement = scalar.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) } ?? ""
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: replacement)
        }
        return result
    }
}
