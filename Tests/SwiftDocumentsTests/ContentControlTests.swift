import Foundation
import Testing
import SwiftDocuments

private func control(_ properties: String, _ content: String) -> String {
    "<w:sdt xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\"><w:sdtPr>\(properties)</w:sdtPr><w:sdtContent>\(content)</w:sdtContent></w:sdt>"
}
private func cell(_ text: String) -> String { "<w:tc>\(paragraph(text))</w:tc>" }

@Suite struct ContentControlTests {
    @Test func nestedBlockAndInlineControlsKeepMetadataCachedContentAndTraversal() throws {
        let inline = control("<w:id w:val=\"43\"/><w:text w:multiLine=\"1\"/>", "<w:r><w:t>cached inline</w:t></w:r>")
        let body = control("<w:id w:val=\"42\"/><w:alias w:val=\"Source title\"/><w:tag w:val=\"source-tag\"/><w:lock w:val=\"sdtContentLocked\"/><w:richText/>", paragraph("first") + "<w:p>\(inline)</w:p>")
        let bytes = makeDocument(body), read = try Document.read(bytes)
        guard case .contentControl(let value) = read.document.blocks[0] else { Issue.record("Expected control wrapper"); return }
        #expect(value.descriptor.id == "42" && value.descriptor.title == "Source title" && value.descriptor.tag == "source-tag")
        #expect(value.descriptor.editingLock == .contentAndControl && value.descriptor.kind == .richText)
        #expect(read.document.paragraphs.count == 2 && read.document.plainText == "first\ncached inline")
        #expect(read.document.paragraphs[1].runs.map(\.text) == ["cached inline"])
        guard case .contentControl(let nested) = read.document.paragraphs[1].inlines[0] else { Issue.record("Expected inline wrapper"); return }
        #expect(nested.descriptor.kind == .plainText && nested.descriptor.isMultiline == true)
        #expect(value.descriptor.sourceHeader?.descendants(named: "sdtContent").isEmpty == true)
        #expect(value.descriptor.sourceHeader?.text.contains("cached inline") == false)
        var blocks: [Block] = []
        let scan = try Document.scan(bytes) { blocks.append($0) }
        #expect(scan.blocksRead == 1 && scan.warnings == read.warnings && blocks[0].plainText == value.plainText)
    }
    @Test func checkboxStateNeverSubstitutesItsOriginalSymbolText() throws {
        let source = "\u{F052}"
        let metadata = "<w14:checkbox><w14:checked w14:val=\"1\"/><w14:checkedState w14:font=\"Wingdings 2\" w14:val=\"F052\"/><w14:uncheckedState w14:font=\"Wingdings 2\" w14:val=\"F0A3\"/></w14:checkbox>"
        let bytes = makeDocument("<w:p>\(control(metadata, "<w:r><w:t>\(source)</w:t></w:r>"))</w:p>")
        let document = try Document(data: bytes)
        guard case .contentControl(let value) = document.paragraphs[0].inlines[0] else { Issue.record("Expected checkbox"); return }
        #expect(value.descriptor.kind == .checkBox && value.descriptor.isChecked == true)
        #expect(value.descriptor.checkedSymbol == SymbolCharacter(fontName: "Wingdings 2", characterCode: 0xF052))
        #expect(value.plainText == source && document.plainText == source)
        #expect(document.readWarnings.isEmpty)
    }
    @Test func bindingsAndListEntriesStayMetadataWithoutReplacingCachedDisplay() throws {
        let metadata = "<w:dataBinding w:storeItemID=\"{SOURCE}\" w:xpath=\"/s:root/s:value\" w:prefixMappings=\"xmlns:s='https://example.invalid/source'\"/><w:dropDownList w:lastValue=\"b\"><w:listItem w:displayText=\"Choice A\" w:value=\"a\"/><w:listItem w:displayText=\"Choice B\" w:value=\"b\"/></w:dropDownList>"
        let read = try Document.read(makeDocument(control(metadata, paragraph("Original cached display"))))
        guard case .contentControl(let value) = read.document.blocks[0] else { Issue.record("Expected bound control"); return }
        #expect(value.descriptor.kind == .dropDownList && value.descriptor.selectedValue == "b")
        #expect(value.descriptor.items.map(\.value) == ["a", "b"])
        #expect(value.descriptor.binding?.storeID == "{SOURCE}" && value.descriptor.binding?.pathQuery == "/s:root/s:value")
        #expect(value.descriptor.binding?.namespaceMappings == "xmlns:s='https://example.invalid/source'")
        #expect(value.plainText == "Original cached display")
        #expect(read.warnings.contains { $0.element == "dataBinding" })
    }
    @Test func dateAndRepeatingControlsPreserveLocaleSourceAndNestedCachedText() throws {
        let date = control("<w:date w:fullDate=\"2026-10-16T00:00:00Z\"><w:dateFormat w:val=\"ggge年M月d日\"/><w:lid w:val=\"ja-JP\"/><w:calendar w:val=\"japan\"/></w:date>", paragraph("令和8年10月16日"))
        let items = control("<w15:repeatingSectionItem xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\"/>", date)
        let repeating = control("<w15:repeatingSection xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\"/>", items)
        let document = try Document(data: makeDocument(repeating))
        guard case .contentControl(let outer) = document.blocks[0], case .blocks(let outerBlocks) = outer.content,
              case .contentControl(let item) = outerBlocks[0], case .blocks(let itemBlocks) = item.content,
              case .contentControl(let value) = itemBlocks[0] else { Issue.record("Expected nested controls"); return }
        #expect(outer.descriptor.kind == .repeatingSection && item.descriptor.kind == .repeatingItem)
        #expect(value.descriptor.kind == .date && value.descriptor.dateValue == "2026-10-16T00:00:00Z")
        #expect(value.descriptor.dateLanguage == "ja-JP" && value.descriptor.dateFormat == "ggge年M月d日" && value.descriptor.dateCalendar == "japan")
        #expect(document.plainText == "令和8年10月16日" && document.paragraphs.count == 1)
    }
    @Test func tableControlsReferencePhysicalRangesWithoutDuplicatingGridContent() throws {
        let controlledCells = control("<w:id w:val=\"cells\"/>", cell("D") + cell("E"))
        let nestedRow = control("<w:id w:val=\"nested\"/>", "<w:tr>\(cell("C"))\(controlledCells)</w:tr>")
        let controlledRows = control("<w:id w:val=\"rows\"/>", "<w:tr>\(cell("B"))</w:tr>" + nestedRow)
        let document = try Document(data: makeDocument("<w:tbl><w:tr>\(cell("A"))</w:tr>\(controlledRows)</w:tbl>"))
        let table = document.tables[0]
        #expect(table.rows.count == 3 && table.rows[2].cells.count == 3)
        #expect(table.rowControls.map(\.range) == [1..<3, 2..<3])
        #expect(table.rowControls.map { $0.descriptor.id } == ["rows", "nested"])
        #expect(table.rows[2].cellControls[0].range == 1..<3 && table.rows[2].cellControls[0].descriptor.id == "cells")
        #expect(table.plainText == "A\nB\nC\tD\tE")
        #expect(document.paragraphs.map(\.plainText) == ["A", "B", "C", "D", "E"])
    }
    @Test func foreignControlPropertiesStaySourceAndWarn() throws {
        let metadata = "<x:alias xmlns:x=\"urn:future\" x:val=\"Foreign title\"/><w:richText/>"
        let document = try Document(data: makeDocument(control(metadata, paragraph("Cached"))))
        guard case .contentControl(let value) = document.blocks[0] else { Issue.record("Expected control"); return }
        #expect(value.descriptor.title == nil && value.descriptor.sourceHeader?.descendants(named: "alias", namespace: "urn:future").count == 1)
        #expect(document.readWarnings.contains { $0.element == "alias" && $0.code == .uninterpretedFormatting })
    }
    @Test func invalidControlBooleanDoesNotInventAState() throws {
        let metadata = "<w14:checkbox><w14:checked w14:val=\"invalid\"/></w14:checkbox>"
        let document = try Document(data: makeDocument("<w:p>\(control(metadata, "<w:r><w:t>Cached</w:t></w:r>"))</w:p>"))
        guard case .contentControl(let value) = document.paragraphs[0].inlines[0] else { Issue.record("Expected control"); return }
        #expect(value.descriptor.isChecked == nil && document.plainText == "Cached")
        #expect(document.readWarnings.contains { $0.element == "checked" })
    }
    @Test func conflictingControlTypesAndDuplicateContentThrow() throws {
        #expect(throws: DocumentError.self) { try Document.read(makeDocument(control("<w:text/><w:date/>", paragraph("Cached")))) }
        let body = "<w:sdt><w:sdtContent>\(paragraph("A"))</w:sdtContent><w:sdtContent>\(paragraph("B"))</w:sdtContent></w:sdt>"
        #expect(throws: DocumentError.self) { try Document.read(makeDocument(body)) }
    }
    @Test func crossControlParagraphMarkJoinsAreRetainedAndDiagnosed() throws {
        let source = "<w:p><w:pPr><w:rPr><w:del w:id=\"1\"/></w:rPr></w:pPr><w:r><w:t>A</w:t></w:r></w:p>"
        let read = try Document.read(makeDocument(control("<w:richText/>", source) + paragraph("B")))
        #expect(read.document.plainText == "A\nB")
        #expect(read.document.paragraphs[0].paragraphMarkRevision?.kind == .deletion)
        #expect(read.warnings.contains { $0.element == "controlParagraphMarkJoin" })
    }
}
