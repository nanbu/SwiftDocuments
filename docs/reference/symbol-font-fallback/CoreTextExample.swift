// Reference adapter for a viewer/rendering library; not a SwiftDocuments target.
#if canImport(CoreText)
import Foundation
import CoreText

public enum NativeSymbolExample {
    /// Return a display scalar only when the explicitly supplied font contains its glyph.
    /// This does not edit source text or register/install a font.
    public static func sourceGlyph(_ scalar: Unicode.Scalar, font: CTFont, legacyFont: SymbolFont) -> Unicode.Scalar? {
        // CTFontCreateWithName can silently return a different installed font.
        guard SymbolFont(name: CTFontCopyFamilyName(font) as String) == legacyFont ||
              SymbolFont(name: CTFontCopyPostScriptName(font) as String) == legacyFont else { return nil }
        guard (0x20...0xFF).contains(scalar.value) || (0xF020...0xF0FF).contains(scalar.value) else { return nil }
        func contains(_ value: Unicode.Scalar) -> Bool {
            let units = Array(String(value).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) && glyphs.contains { $0 != 0 }
        }
        if contains(scalar) { return scalar }
        if (0x20...0xFF).contains(scalar.value), let alias = Unicode.Scalar(0xF000 + scalar.value), contains(alias) { return alias }
        if (0xF020...0xF0FF).contains(scalar.value), let byte = Unicode.Scalar(scalar.value & 255), contains(byte) { return byte }
        return nil
    }
    /// Match an explicitly requested family/name before trusting CTFontCreateWithName's fallback.
    public static func availableFontNames() -> Set<String> {
        Set((CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []) + (CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []))
    }
}
#endif
