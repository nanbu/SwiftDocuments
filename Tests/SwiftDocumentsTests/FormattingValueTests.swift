import Testing
import SwiftDocuments

@Suite struct FormattingValueTests {
    @Test func sectionCopiesKeepIndependentDictionariesColumnsAndSourceProperties() {
        var section = Section()
        section.headers["default"] = "source.xml"; section.margins["top"] = 72
        section.columns = [SectionColumn(width: 100)]; section.rawProperties = ["source"]
        let original = section
        section.headers["default"] = "changed.xml"; section.margins["top"] = 36
        section.columns[0].width = 200; section.rawProperties.append("changed")
        #expect(original.headers["default"] == "source.xml" && original.margins["top"] == 72)
        #expect(original.columns[0].width == 100 && original.rawProperties == ["source"])
        #expect(Section().headers.isEmpty && Section().columns.isEmpty && Section().columnCount == 1)
    }
    @Test func revisionAndHistoryCopiesKeepIndependentAttributionAndProperties() {
        let original = Revision(id: "source", kind: .formatting, author: "Sample Author", date: "2026-01-01")
        var revision = original
        revision.id = "changed"; revision.author = "Changed Author"; revision.kind = .insertion; revision.date = nil
        #expect(original.id == "source" && original.author == "Sample Author" && original.kind == .formatting && original.date == "2026-01-01")
        var formatting = TextFormatting(); formatting.fontName = "Source"
        var history = TextFormattingChange(revision: original, previous: formatting)
        let snapshot = history
        history.revision.author = "Changed Author"; history.previous.fontName = "Changed"
        #expect(snapshot.revision.author == "Sample Author" && snapshot.previous.fontName == "Source")
        var paragraph = ParagraphFormatting(); paragraph.spacingBefore = 12
        var paragraphHistory = ParagraphFormattingChange(revision: original, previous: paragraph)
        let paragraphSnapshot = paragraphHistory
        paragraphHistory.revision.id = "changed"; paragraphHistory.previous.spacingBefore = 24
        #expect(paragraphSnapshot.revision.id == "source" && paragraphSnapshot.previous.spacingBefore == 12)
    }
    @Test func changingCopiedFormattingDoesNotChangeItsSourceOrEmptyDefaults() {
        var text = TextFormatting()
        text.bold = true; text.fontName = "Source Font"; text.rawProperties = ["source"]
        let source = text
        text.bold = false; text.fontName = "Changed Font"; text.rawProperties.append("changed")
        #expect(source.bold == true && source.fontName == "Source Font" && source.rawProperties == ["source"])
        #expect(text.bold == false && text.rawProperties == ["source", "changed"])
        #expect(TextFormatting().bold == nil && TextFormatting().rawProperties.isEmpty)
        var paragraph = ParagraphFormatting()
        paragraph.tabs = [TabStop(position: 12, alignment: "left")]
        paragraph.rawProperties = ["source"]
        let original = paragraph
        paragraph.tabs?[0].position = 24
        paragraph.rawProperties.append("changed")
        #expect(original.tabs?[0].position == 12 && original.rawProperties == ["source"])
        #expect(paragraph.tabs?[0].position == 24 && ParagraphFormatting().tabs == nil)
    }
    @Test func mergingFormattingCopiesPreservesToggleRulesAndIndependentArrays() {
        var base = TextFormatting(); base.bold = true; base.rawProperties = ["base"]
        let source = base
        var next = TextFormatting(); next.bold = true; next.italic = true; next.rawProperties = ["next"]
        base.merge(next, toggling: true)
        #expect(base.bold == false && base.italic == true && base.rawProperties == ["base", "next"])
        #expect(source.bold == true && source.italic == nil && source.rawProperties == ["base"])
        let merged = base
        base.merge(TextFormatting())
        #expect(base == merged)
    }
    @Test func formattingCopiesCanBeMutatedIndependentlyInConcurrentTasks() async {
        var initial = TextFormatting(); initial.fontName = "Source"; initial.rawProperties = ["source"]
        let source = initial
        let values = await withTaskGroup(of: TextFormatting.self, returning: [TextFormatting].self) { group in
            for index in 0..<32 {
                group.addTask {
                    var local = source
                    local.fontName = "Font \(index)"
                    local.rawProperties.append(String(index))
                    return local
                }
            }
            var output: [TextFormatting] = []
            for await value in group { output.append(value) }
            return output
        }
        #expect(source.fontName == "Source" && source.rawProperties == ["source"])
        #expect(Set(values.compactMap(\.fontName)).count == 32)
        #expect(values.allSatisfy { $0.rawProperties.count == 2 })
    }
}
