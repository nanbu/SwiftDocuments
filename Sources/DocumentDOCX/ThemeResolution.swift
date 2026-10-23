import Foundation
import DocumentCore

extension Properties {
    func themeColor(_ reference: String, tint: String? = nil, shade: String? = nil) -> String? {
        let aliases = ["dark1": "dk1", "light1": "lt1", "dark2": "dk2", "light2": "lt2", "text1": "dk1", "background1": "lt1", "text2": "dk2", "background2": "lt2", "hyperlink": "hlink", "followedHyperlink": "folHlink"]
        let mappingKeys = ["text1": "t1", "text2": "t2", "background1": "bg1", "background2": "bg2", "hyperlink": "hyperlink", "followedHyperlink": "followedHyperlink"]
        let mapped = themeColorMapping[mappingKeys[reference] ?? reference] ?? reference
        guard let hex = theme?.colors[aliases[mapped] ?? mapped], hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        for value in [tint, shade].compactMap({ $0 }) where value.count != 2 || UInt8(value, radix: 16) == nil { return nil }
        guard tint != nil || shade != nil else { return hex }
        let r = Double((rgb >> 16) & 255) / 255, g = Double((rgb >> 8) & 255) / 255, b = Double(rgb & 255) / 255
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        let luminance = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * luminance - 1))
        var hue = 0.0
        if delta != 0 {
            if maximum == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue /= 6; if hue < 0 { hue += 1 }
        }
        let amount = Double(UInt8(tint ?? shade!, radix: 16)!) / 255
        let light = tint != nil ? 1 - (1 - luminance) * amount : luminance * amount
        let c = (1 - abs(2 * light - 1)) * saturation
        let x = c * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1)), m = light - c / 2
        let components: [Double]
        switch hue * 6 {
        case ..<1: components = [c, x, 0]
        case ..<2: components = [x, c, 0]
        case ..<3: components = [0, c, x]
        case ..<4: components = [0, x, c]
        case ..<5: components = [x, 0, c]
        default: components = [c, 0, x]
        }
        return components.map { String(format: "%02X", Int((($0 + m) * 255).rounded())) }.joined()
    }
    func resolveFonts(_ value: inout TextFormatting, node: MarkupNode?, part: String) {
        func font(_ reference: String?, script: String, language: String?) -> String? {
            guard let reference else { return nil }
            let major: Bool
            if reference.hasPrefix("major") { major = true }
            else if reference.hasPrefix("minor") { major = false }
            else { return nil }
            guard let theme else { return nil }
            let fonts = major ? theme.majorFonts : theme.minorFonts
            guard ["Ascii", "HAnsi", "EastAsia", "Bidi"].contains(String(reference.dropFirst(5))) else { return nil }
            let lang = (language ?? themeLanguages[script] ?? "").lowercased()
            let key: String?
            if script == "latin" { key = "latin" }
            else if script == "ea" {
                if lang.hasPrefix("ja") { key = "Jpan" }
                else if lang.hasPrefix("ko") { key = "Hang" }
                else if lang.hasPrefix("zh-tw") || lang.hasPrefix("zh-hk") || lang.hasPrefix("zh-hant") { key = "Hant" }
                else if lang.hasPrefix("zh") { key = "Hans" }
                else { key = nil }
            } else {
                let scripts = ["ar": "Arab", "fa": "Arab", "ur": "Arab", "he": "Hebr", "hi": "Deva", "th": "Thai"]
                key = scripts[String(lang.prefix(2))]
            }
            return key.flatMap { fonts[$0] } ?? fonts[script]
        }
        var unresolved = false
        if let ref = value.fontTheme {
            if let resolved = font(ref, script: "latin", language: value.language) { value.fontName = resolved } else { unresolved = true }
        }
        if let ref = value.fontThemeEastAsia {
            if let resolved = font(ref, script: "ea", language: value.languageEastAsia) { value.fontNameEastAsia = resolved } else { unresolved = true }
        }
        if let ref = value.fontThemeComplexScript {
            if let resolved = font(ref, script: "cs", language: value.languageComplexScript) { value.fontNameComplexScript = resolved } else { unresolved = true }
        }
        if unresolved, let source = node?.child("rFonts") ?? node?.child("lang") { value.rawProperties.append(source.xml); unparsed(source, part: part) }
    }
}
