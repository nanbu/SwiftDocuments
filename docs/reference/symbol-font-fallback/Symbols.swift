import Foundation

/// Legacy single-byte fonts whose character codes are not ordinary Unicode text.
public enum SymbolFont: String, Sendable, CaseIterable, Codable {
    case symbol, webdings, wingdings, wingdings2, wingdings3
    public init?(name: String) {
        self.init(rawValue: name.lowercased().filter { !$0.isWhitespace && $0 != "-" })
    }
}

/// Portable display conversion. Source characters and font names are never overwritten.
public enum SymbolMapper {
    /// Map an encoded byte or U+F020...U+F0FF symbol scalar; unrelated Unicode stays unmapped.
    public static func map(_ scalar: Unicode.Scalar, font: SymbolFont, textPresentation: Bool = true) -> String? {
        let value = scalar.value
        guard (0x20...0xFF).contains(value) || (0xF020...0xF0FF).contains(value) else { return nil }
        let table: [UInt8: UInt32]
        switch font {
        case .symbol: table = SymbolMappingData.symbol
        case .webdings: table = SymbolMappingData.webdings
        case .wingdings: table = SymbolMappingData.wingdings
        case .wingdings2: table = SymbolMappingData.wingdings2
        case .wingdings3: table = SymbolMappingData.wingdings3
        }
        guard let mapped = table[UInt8(value & 255)], let output = Unicode.Scalar(mapped) else { return nil }
        return String(output) + (textPresentation && SymbolMappingData.textPresentation.contains(mapped) ? "\u{FE0E}" : "")
    }
    /// Mapping-only convenience after the caller has chosen fallback; this does not check fonts.
    /// Preserve unmapped characters; a renderer can additionally report unmapped legacy codes.
    public static func displayText(_ text: String, fontName: String?) -> String {
        guard let fontName, let font = SymbolFont(name: fontName) else { return text }
        return text.unicodeScalars.map { map($0, font: font) ?? String($0) }.joined()
    }
    /// Recommended portable cascade. Applications can bundle a licensed font and prepend its name.
    public static let fallbackFontNames = ["Noto Sans Symbols 2", "Noto Sans Symbols", "Apple Symbols", "Segoe UI Symbol", "DejaVu Sans", "sans-serif"]
}
