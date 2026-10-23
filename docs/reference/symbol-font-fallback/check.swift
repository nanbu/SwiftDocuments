import Foundation

@main enum ReferenceChecks {
    static func main() {
        precondition(SymbolMapper.map("\u{F0B7}", font: .symbol) == "•")
        precondition(SymbolMapper.map("\u{F0A7}", font: .wingdings) == "▪\u{FE0E}")
        precondition(SymbolMapper.map("\u{F0FC}", font: .wingdings) == "✓")
        precondition(SymbolMapper.map("l", font: .wingdings) == "⚫\u{FE0E}")
        precondition(SymbolMapper.map("\u{F052}", font: .wingdings2) == "☑\u{FE0E}")
        precondition(SymbolMapper.map("漢", font: .wingdings) == nil)
        let original = "\u{F0A7}漢字"
        let display = SymbolMapper.displayText(original, fontName: "Wingdings")
        precondition(original == "\u{F0A7}漢字" && display == "▪\u{FE0E}漢字")
        precondition(SymbolMapper.displayText(original, fontName: "Ordinary Text Font") == original)
        precondition(SymbolFont.allCases.count == 5)
        print("Symbol fallback reference: 9 checks passed; original source preserved")
    }
}
