import Foundation
import Testing
import SwiftDocuments

@Suite struct ODTTypographyTests {
    @Test func odtRubyKeepsBaseAndAnnotationStylesWithoutDuplicatingDisplayText() throws {
        let styles = """
        <office:styles>
        <style:style style:name="Ruby" style:family="ruby"><style:ruby-properties style:ruby-align="center" style:ruby-position="above"/></style:style>
        <style:style style:name="Annotation" style:family="text"><style:text-properties fo:font-size="6pt" fo:language="ja"/></style:style>
        <style:style style:name="Body" style:family="paragraph"><style:text-properties fo:font-size="12pt"/></style:style>
        </office:styles>
        """
        let body = "<text:p text:style-name=\"Body\">A<text:ruby text:style-name=\"Ruby\"><text:ruby-base>東京</text:ruby-base><text:ruby-text text:style-name=\"Annotation\">とうきょう</text:ruby-text></text:ruby>B</text:p>"
        let data = odtPackage(body, styles: styles), result = try Document.read(data), paragraph = result.document.paragraphs[0]
        #expect(paragraph.plainText == "A東京B" && paragraph.runs.map(\.text) == ["A", "東京", "B"])
        guard case .ruby(let ruby) = paragraph.inlines[1] else { Issue.record("Expected ruby"); return }
        #expect(ruby.annotation.map(\.plainText).joined() == "とうきょう")
        #expect(ruby.alignment == "center" && ruby.position == "above" && ruby.baseSize == 12 && ruby.annotationSize == 6 && ruby.language == "ja")
        #expect(ruby.annotation.flatMap(\.runs).first?.formatting.fontSize == 6)
        #expect(ruby.rawProperties[0].contains("ruby-text"))
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }

    @Test(arguments: ["<text:ruby-base>A</text:ruby-base>", "<text:ruby-base>A</text:ruby-base><text:ruby-base>B</text:ruby-base><text:ruby-text>C</text:ruby-text>", "<x:ruby-base>A</x:ruby-base><text:ruby-text>B</text:ruby-text>"])
    func odtRubyRejectsMissingDuplicateAndForeignRequiredChildren(_ content: String) throws {
        #expect(throws: DocumentError.self) { try Document.read(odtPackage("<text:p><text:ruby>\(content)</text:ruby></text:p>")) }
    }

    @Test func odtParagraphTabsAndCommentAttributionRemainTyped() throws {
        let styles = """
        <office:styles><style:style style:name="Tabs" style:family="paragraph"><style:paragraph-properties><style:tab-stops>
        <style:tab-stop style:position="1in" style:type="center" style:leader-text="."/>
        <style:tab-stop style:position="3cm" style:type="right"/>
        </style:tab-stops></style:paragraph-properties></style:style></office:styles>
        """
        let body = """
        <text:p text:style-name="Tabs">A<office:annotation office:name="comment" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>Sample Author</dc:creator><dc:date>2026-01-01T00:00:00Z</dc:date><text:p>Comment body</text:p></office:annotation>B<office:annotation-end office:name="comment"/></text:p>
        """
        let data = odtPackage(body, styles: styles), result = try Document.read(data), document = result.document
        let tabs = try #require(document.paragraphs[0].formatting.tabs)
        #expect(tabs[0] == TabStop(position: 72, alignment: "center", leader: "."))
        #expect(abs(tabs[1].position - 3 * 72 / 2.54) < 0.000001 && tabs[1].alignment == "right")
        #expect(document.plainText == "AB" && document.stories[0].plainText == "Comment body")
        #expect(document.stories[0].author == "Sample Author" && document.stories[0].date == "2026-01-01T00:00:00Z")
        guard case .commentReference(let end) = document.paragraphs[0].inlines.last else { Issue.record("Expected annotation end"); return }
        #expect(end.id == "comment" && end.boundary == .end)
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
        let omitted = try Document.read(data, options: .init(includeRelatedStories: false))
        #expect(omitted.document.stories.isEmpty && omitted.document.plainText == "AB")
        #expect(omitted.warnings.contains { $0.code == .storiesOmitted })
    }

    @Test func odtUnknownRubyAndTabPropertiesStaySourceAndWarn() throws {
        let styles = """
        <office:styles><style:style style:name="Tabs" style:family="paragraph"><style:paragraph-properties><style:tab-stops>
        <style:tab-stop style:position="invalid"/><style:tab-stop style:position="10pt" style:type="future"/><style:tab-stop style:position="20pt" style:type="char" style:char=","/>
        </style:tab-stops></style:paragraph-properties></style:style></office:styles>
        """
        let data = odtPackage("<text:p text:style-name=\"Tabs\"><text:ruby x:extra=\"1\"><text:ruby-base>A</text:ruby-base><text:ruby-text>B</text:ruby-text><x:extra/></text:ruby></text:p>", styles: styles)
        let result = try Document.read(data), paragraph = result.document.paragraphs[0]
        #expect(paragraph.plainText == "A" && paragraph.formatting.tabs?.count == 1)
        #expect(paragraph.formatting.tabs?.first?.position == 20 && paragraph.formatting.tabs?.first?.alignment == "decimal")
        #expect(paragraph.formatting.rawProperties.contains { $0.contains("invalid") })
        #expect(result.warnings.first { $0.element.hasSuffix("tab-stop") }?.count == 3)
        #expect(result.warnings.contains { $0.element.hasSuffix("ruby") })
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }
}
