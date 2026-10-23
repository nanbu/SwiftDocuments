import Foundation
import Testing
import SwiftDocuments

private func fieldParagraph(_ contents: String) -> String { "<w:p><w:r>\(contents)</w:r></w:p>" }
private func marker(_ kind: String, _ attributes: String = "") -> String { "<w:fldChar w:fldCharType=\"\(kind)\" \(attributes)/>" }
private func fieldValues(_ inlines: [Inline]) -> [Field] {
    inlines.flatMap { inline -> [Field] in
        switch inline {
        case .field(let field): [field] + fieldValues(field.codeContent) + fieldValues(field.result)
        case .hyperlink(let link): fieldValues(link.inlines)
        case .contentControl(let control): if case .inlines(let values) = control.content { fieldValues(values) } else { [] }
        case .ruby(let ruby): fieldValues(ruby.base) + fieldValues(ruby.annotation)
        default: []
        }
    }
}
private func fieldValues(_ document: Document) -> [Field] { document.paragraphs.flatMap { fieldValues($0.inlines) } }

@Suite struct FieldTests {
    @Test func crossParagraphFieldsKeepIdentityAndImmutableScanFragments() throws {
        let first = fieldParagraph(marker("begin", "w:fldLock=\"true\" w:dirty=\"1\"") + "<w:instrText> TO</w:instrText>")
        let second = fieldParagraph("<w:instrText>C </w:instrText>" + marker("separate") + "<w:t>First entry</w:t>")
        let third = fieldParagraph("<w:t>Second entry</w:t>" + marker("end") + "<w:t>After</w:t>")
        let data = makeDocument(first + second + third)
        var delivered: [Block] = []
        let scan = try Document.scan(data) { block in
            // The first paragraph must arrive before later instructions have been parsed.
            if delivered.isEmpty {
                let value = try #require(fieldValues(block.paragraphs.flatMap(\.inlines)).first)
                #expect(value.instruction == " TO")
                #expect(value.fragment?.startsHere == true && value.fragment?.endsHere == false)
            }
            delivered.append(block)
        }
        let document = try Document(data: data)
        let definition = try #require(document.fieldDefinitions.first)
        #expect(document.fieldDefinitions.count == 1)
        #expect(definition.instruction == " TOC " && definition.hasSeparator && definition.isComplete)
        #expect(definition.isLocked == true && definition.isDirty == true)
        #expect(definition.sourcePart == "word/document.xml")
        #expect(document.plainText == "\nFirst entry\nSecond entryAfter")
        let fragments = fieldValues(document)
        #expect(fragments.count == 3)
        #expect(fragments.allSatisfy { $0.fragment?.definitionID == definition.id })
        #expect(fragments[1].fragment?.containsSeparator == true)
        #expect(fragments[2].fragment?.endsHere == true)
        #expect(fragments[0].instruction == " TO")
        #expect(scan.document.blocks.isEmpty && scan.blocksRead == 3)
        #expect(scan.document.fieldDefinitions == document.fieldDefinitions)
        #expect(delivered.map(\.plainText) == document.blocks.map(\.plainText))
        #expect(fieldValues(delivered.flatMap(\.paragraphs).flatMap(\.inlines)).map(\.fragment) == fragments.map(\.fragment))
        #expect(scan.warnings == document.readWarnings && document.readWarnings.isEmpty)
    }

    @Test func nestedInstructionFieldsStayOutOfCachedDisplay() throws {
        let contents = marker("begin") + "<w:instrText> IF </w:instrText>" + marker("begin") +
            "<w:instrText> PAGE </w:instrText>" + marker("separate") + "<w:t>2</w:t>" + marker("end") +
            "<w:instrText> = 2 </w:instrText>" + marker("separate") + "<w:t>Yes</w:t>" + marker("end")
        let document = try Document(data: makeDocument(fieldParagraph(contents)))
        #expect(document.plainText == "Yes" && document.paragraphs[0].runs.map(\.text) == ["Yes"])
        let definitions = document.fieldDefinitions
        #expect(definitions.count == 2 && definitions[1].parentID == definitions[0].id)
        #expect(definitions[0].instruction == " IF  = 2 ")
        let outer = try #require(fieldValues(document).first)
        #expect(fieldValues(outer.codeContent).first?.instruction == " PAGE ")
        #expect(outer.codeContent.map(\.plainText).joined() == " IF 2 = 2 ")
        #expect(document.readWarnings.isEmpty)
    }

    @Test func nestedResultFieldsContinueAcrossParagraphs() throws {
        let body = fieldParagraph(marker("begin") + "<w:instrText> OUTER </w:instrText>" + marker("separate") + "<w:t>A</w:t>" + marker("begin") + "<w:instrText> INNER </w:instrText>" + marker("separate") + "<w:t>B</w:t>") +
            fieldParagraph("<w:t>C</w:t>" + marker("end") + "<w:t>D</w:t>" + marker("end"))
        let document = try Document(data: makeDocument(body))
        #expect(document.plainText == "AB\nCD")
        #expect(document.fieldDefinitions.count == 2 && document.fieldDefinitions.allSatisfy(\.isComplete))
        let values = fieldValues(document)
        #expect(values.count == 4)
        #expect(values.map { $0.fragment?.endsHere } == [false, false, true, true])
        #expect(document.readWarnings.isEmpty)
    }

    @Test func fieldsCrossControlsTablesAndHyperlinksWithoutMovingContent() throws {
        let body = fieldParagraph(marker("begin") + "<w:instrText> TOC </w:instrText>" + marker("separate")) +
            "<w:sdt><w:sdtPr><w:tag w:val=\"cached\"/></w:sdtPr><w:sdtContent>" + paragraph("Control") + "</w:sdtContent></w:sdt>" +
            "<w:tbl><w:tr><w:tc>" + paragraph("Cell") + "</w:tc></w:tr></w:tbl>" +
            "<w:p><w:hyperlink w:anchor=\"target\"><w:r><w:t>Linked</w:t>" + marker("end") + "<w:t>Outside</w:t></w:r></w:hyperlink></w:p>"
        let data = makeDocument(body), document = try Document(data: data)
        #expect(document.blocks.count == 4 && document.tables.count == 1)
        #expect(document.plainText == "\nControl\nCell\nLinkedOutside")
        let link = try #require(document.paragraphs.last?.inlines.compactMap { if case .hyperlink(let value) = $0 { value } else { nil } }.first)
        #expect(link.anchor == "target" && link.inlines.map(\.plainText).joined() == "LinkedOutside")
        #expect(fieldValues(link.inlines).last?.fragment?.endsHere == true)
        #expect(document.fieldDefinitions.count == 1 && document.fieldDefinitions[0].isComplete)
        var blocks: [Block] = []
        let scan = try Document.scan(data) { blocks.append($0) }
        #expect(scan.document.fieldDefinitions == document.fieldDefinitions)
        #expect(scan.warnings == document.readWarnings && document.readWarnings.isEmpty)
        #expect(blocks.map(\.plainText) == document.blocks.map(\.plainText))
    }

    @Test func inlineWrapperBoundariesRetainStartEndAndInstructionPhases() throws {
        let body = "<w:p><w:hyperlink w:anchor=\"a\"><w:r>" + marker("begin") + "<w:instrText> REF </w:instrText></w:r></w:hyperlink>" +
            "<w:sdt><w:sdtContent><w:r><w:instrText>target </w:instrText>" + marker("separate") + "<w:t>Cached</w:t></w:r></w:sdtContent></w:sdt>" +
            "<w:r>" + marker("end") + "<w:t>After</w:t></w:r></w:p>"
        let document = try Document(data: makeDocument(body))
        #expect(document.plainText == "CachedAfter")
        #expect(document.fieldDefinitions[0].instruction == " REF target ")
        let fragments = fieldValues(document)
        #expect(fragments.filter { $0.fragment?.startsHere == true }.count == 1)
        #expect(fragments.filter { $0.fragment?.endsHere == true }.count == 1)
        #expect(fragments.filter { $0.fragment?.containsSeparator == true }.count == 1)
        #expect(document.readWarnings.isEmpty)
    }

    @Test func codeOnlyAndSimpleNestedFieldsDoNotInventDisplay() throws {
        let body = "<w:p><w:r>" + marker("begin") + "<w:instrText> SET </w:instrText></w:r>" +
            "<w:fldSimple w:instr=\"PAGE\"><w:r><w:t>3</w:t></w:r></w:fldSimple><w:r>" + marker("end") + "</w:r></w:p>"
        let document = try Document(data: makeDocument(body))
        #expect(document.plainText.isEmpty && document.paragraphs[0].runs.isEmpty)
        #expect(document.fieldDefinitions.count == 2)
        #expect(document.fieldDefinitions[1].kind == .simple)
        #expect(document.fieldDefinitions[1].parentID == document.fieldDefinitions[0].id)
        #expect(document.fieldDefinitions.allSatisfy { $0.isComplete && !$0.hasSeparator })
        #expect(fieldValues(document).count == 2 && document.readWarnings.isEmpty)
    }

    @Test func unclosedFieldsWarnOnlyAtStoryEndWithoutInventingEndMarkers() throws {
        let body = fieldParagraph(marker("begin") + "<w:instrText> TOC </w:instrText>" + marker("separate") + "<w:t>First</w:t>") + paragraph("Second") + paragraph("Third")
        let data = makeDocument(body), document = try Document(data: data)
        #expect(document.plainText == "First\nSecond\nThird")
        #expect(!document.fieldDefinitions[0].isComplete)
        #expect(fieldValues(document).allSatisfy { $0.fragment?.endsHere == false })
        let warnings = document.readWarnings.filter { $0.code == .incompleteField }
        #expect(warnings.count == 1 && warnings[0].count == 1)
        #expect(try Document.scan(data) { _ in }.warnings == document.readWarnings)
    }

    @Test func notesAndBodyCannotCloseEachOthersFields() throws {
        let notes = "<w:footnotes xmlns:w=\"\(wordNS)\"><w:footnote w:id=\"1\">" + fieldParagraph(marker("begin") + "<w:instrText> PAGE </w:instrText>" + marker("separate") + "<w:t>Note1</w:t>") +
            "</w:footnote><w:footnote w:id=\"2\">" + fieldParagraph("<w:t>Note2</w:t>" + marker("end")) + "</w:footnote></w:footnotes>"
        let body = fieldParagraph(marker("begin") + "<w:instrText> TOC </w:instrText>" + marker("separate") + "<w:t>Body</w:t>")
        let data = makeDocument(body, extra: ["word/footnotes.xml": notes], relations: [("notes", "footnotes", "footnotes.xml", false)])
        let document = try Document(data: data)
        #expect(document.fieldDefinitions.count == 2 && document.fieldDefinitions.allSatisfy { !$0.isComplete && $0.parentID == nil })
        #expect(document.stories.map(\.plainText) == ["Note1", "Note2"])
        #expect(fieldValues(document.stories[1].blocks.flatMap(\.paragraphs).flatMap(\.inlines)).isEmpty)
        #expect(document.readWarnings.filter { $0.code == .incompleteField }.reduce(0) { $0 + $1.count } == 3)
        let omitted = try Document(data: data, options: .init(includeRelatedStories: false))
        #expect(omitted.fieldDefinitions.count == 1 && omitted.stories.isEmpty)
    }

    @Test func invalidMarkersAndSourceExtensionsRemainDiagnosed() throws {
        let body = fieldParagraph(marker("end") + "<w:instrText>Orphan</w:instrText>" + marker("separate") + marker("begin", "w:fldLock=\"maybe\" w:dirty=\"later\" x:flag=\"source\"") +
            "<w:instrText> PAGE </w:instrText>" + marker("separate") + marker("separate") + "<w:t>3</w:t>" + marker("end"))
        let document = try Document(data: makeDocument(body))
        #expect(document.plainText == "Orphan3")
        #expect(document.fieldDefinitions[0].isLocked == nil && document.fieldDefinitions[0].isDirty == nil)
        #expect(document.fieldDefinitions[0].source?.attributes["urn:foreign|flag"] == "source")
        #expect(document.readWarnings.contains { $0.code == .uninterpretedFormatting && $0.element == "fldChar" })
        #expect(document.readWarnings.filter { $0.code == .incompleteField }.reduce(0) { $0 + $1.count } == 4)
    }

    @Test func revisionViewsUseOnlyTheirVisibleFieldMarkers() throws {
        let field = fieldParagraph(marker("begin") + "<w:instrText> PAGE </w:instrText>" + marker("separate") + "<w:t>1</w:t>" + marker("end"))
        let data = makeDocument("<w:del w:id=\"1\">" + field + "</w:del><w:ins w:id=\"2\">" + field + "</w:ins>")
        for view in [ReadOptions.RevisionView.final, .original, .all] {
            let document = try Document(data: data, options: .init(revisions: view))
            #expect(document.fieldDefinitions.count == (view == .all ? 2 : 1))
            #expect(document.fieldDefinitions.allSatisfy(\.isComplete) && document.readWarnings.isEmpty)
        }
    }

    @Test func textBoxesHaveIndependentFieldsAndResumeTheEnclosingStory() throws {
        let inner = fieldParagraph(marker("end") + marker("begin") + "<w:instrText> INNER </w:instrText>" + marker("separate") + "<w:t>Box</w:t>" + marker("end"))
        let drawing = """
        <w:drawing xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
        <wp:inline><wp:extent cx="12700" cy="12700"/><a:graphic><a:graphicData><wps:wsp><wps:txbx><w:txbxContent>\(inner)</w:txbxContent></wps:txbx></wps:wsp></a:graphicData></a:graphic></wp:inline></w:drawing>
        """
        let body = fieldParagraph(marker("begin") + "<w:instrText> OUTER </w:instrText>" + marker("separate") + drawing + "<w:t>Body</w:t>" + marker("end"))
        let document = try Document(data: makeDocument(body))
        #expect(document.fieldDefinitions.map(\.instruction) == [" OUTER ", " INNER "])
        #expect(document.fieldDefinitions.allSatisfy { $0.isComplete && $0.parentID == nil })
        #expect(document.plainText == "BoxBody")
        #expect(document.readWarnings.filter { $0.code == .incompleteField }.reduce(0) { $0 + $1.count } == 1)
    }

    @Test func semanticFieldDepthCannotBypassTheXMLDepthLimit() throws {
        let body = String(repeating: fieldParagraph(marker("begin")), count: 17)
        #expect(throws: DocumentError.limitExceeded("field nesting")) {
            try Document(data: makeDocument(body), options: .init(limits: .init(maxXMLDepth: 16)))
        }
    }

    @Test func missingOrForeignSimpleInstructionsNeverBecomeEmptySuccess() throws {
        for attributes in ["", "x:instr=\"PAGE\""] {
            #expect(throws: DocumentError.self) {
                try Document(data: makeDocument("<w:p><w:fldSimple \(attributes)><w:r><w:t>Cached</w:t></w:r></w:fldSimple></w:p>"))
            }
        }
    }

    @Test func strictFieldsAndFormExtensionsKeepTheirSource() throws {
        let body = "<w:p><w:r><w:fldChar w:fldCharType=\"begin\"><w:ffData><w:name w:val=\"Source form\"/></w:ffData></w:fldChar><w:instrText> FORMTEXT </w:instrText>" +
            marker("separate") + "<w:t>Cached</w:t>" + marker("end") + "</w:r></w:p>"
        var parts = documentParts(body)
        parts["word/document.xml"] = Data(String(decoding: parts["word/document.xml"]!, as: UTF8.self).replacingOccurrences(of: wordNS, with: "http://purl.oclc.org/ooxml/wordprocessingml/main").utf8)
        let document = try Document(data: makeZIP(parts.sorted { $0.key < $1.key }))
        #expect(document.plainText == "Cached" && document.fieldDefinitions[0].isComplete)
        #expect(document.fieldDefinitions[0].source?.descendants(named: "ffData", namespace: "http://purl.oclc.org/ooxml/wordprocessingml/main").count == 1)
        #expect(document.readWarnings.contains { $0.code == .unsupportedContent && $0.element.hasSuffix("ffData") })
    }

    @Test func largeCachedFieldStreamsEveryBlockBeforeItsEnd() throws {
        let count = 2_000
        let body = fieldParagraph(marker("begin") + "<w:instrText> TOC </w:instrText>" + marker("separate") + "<w:t>First</w:t>") +
            String(repeating: paragraph("Entry"), count: count) + fieldParagraph(marker("end"))
        var delivered = 0
        let scan = try Document.scan(makeDocument(body)) { block in
            let fragments = fieldValues(block.paragraphs.flatMap(\.inlines))
            #expect(fragments.count == 1)
            #expect(fragments[0].fragment?.endsHere == (delivered == count + 1))
            delivered += 1
        }
        #expect(delivered == count + 2 && scan.blocksRead == delivered)
        #expect(scan.document.blocks.isEmpty && scan.document.fieldDefinitions.count == 1)
        #expect(scan.document.fieldDefinitions[0].isComplete && scan.warnings.isEmpty)
    }
}
