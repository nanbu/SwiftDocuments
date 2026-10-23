import Foundation
import Testing
import SwiftDocuments

private func anchors(_ values: [(UInt64, UInt64)]) -> Data {
    values.reduce(into: Data()) { $0 += pbBytes(1, pbInt(1, $1.0) + pbRef(2, $1.1)) }
}
private func cell(_ kind: UInt8, flags: UInt32 = 0, values: Data = Data()) -> Data {
    var data = Data([5, kind, 0, 0, 0, 0, 0, 0]); data.append32(flags); return data + values
}
private func doubleBytes(_ value: Double) -> Data {
    var data = Data(); data.append64(value.bitPattern); return data
}
private func testTable(_ cells: [(Int, Data)], columns: Int = 3, wide: Bool = false,
                       rowIndex: UInt64 = 0, version: UInt64 = 5, extraStore: Data = Data(),
                       extraModel: Data = Data(), extraRecords: Data = Data(),
                       strings: Data = Data(), rich: Data = Data(), offsetOverride: Data? = nil) -> Data {
    var buffer = Data(), offsets = Data()
    for column in 0..<columns {
        if let value = cells.first(where: { $0.0 == column })?.1 {
            offsets.append16(UInt16(buffer.count / (wide ? 4 : 1))); buffer += value
            if wide { while buffer.count % 4 != 0 { buffer.append(0) } }
        } else { offsets.append16(0xFFFF) }
    }
    let row = pbInt(1, rowIndex) + pbInt(2, UInt64(cells.count)) + pbInt(5, version) + pbBytes(6, buffer) + pbBytes(7, offsetOverride ?? offsets) + pbInt(8, wide ? 1 : 0)
    let tile = iwaArchive(23, 6002, pbInt(6, 5) + pbBytes(5, row))
    let tileStorage = pbBytes(1, pbInt(1, 0) + pbRef(2, 23)) + pbInt(2, 256)
    let store = pbBytes(3, tileStorage) + pbRef(4, 24) + pbRef(17, 25) + extraStore
    let model = iwaArchive(22, 6001, pbInt(6, 1) + pbInt(7, UInt64(columns)) + pbBytes(4, store) + extraModel)
    let info = iwaArchive(21, 6000, pbRef(2, 22))
    let attachment = iwaArchive(20, 2003, pbRef(1, 21))
    return attachment + info + model + tile + iwaArchive(24, 6005, pbInt(1, 1) + strings)
        + iwaArchive(25, 6005, pbInt(1, 8) + rich) + extraRecords
}
private func tableBody(_ text: String = "\u{FFFC}", offset: UInt64 = 0) -> Data {
    iwaArchive(1, 10000, pbRef(4, 10)) + iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, text) + pbBytes(9, anchors([(offset, 20)])))
}
private func imageRecords(filename: String = "checker.png", duplicate: Bool = false, resource: UInt64 = 7) -> Data {
    let size = pbBytes(2, pbFloat(1, 72) + pbFloat(2, 36))
    let drawable = pbBytes(1, size) + pbText(8, "Fictional image")
    let image = iwaArchive(21, 3005, pbBytes(1, drawable) + pbRef(11, resource))
    let entry = pbBytes(4, pbInt(1, 7) + pbText(3, "Original checker") + pbText(4, filename))
    return iwaArchive(20, 2003, pbRef(1, 21)) + image + iwaArchive(2, 11006, entry + (duplicate ? entry : Data()))
}

@Suite struct PagesAttachmentTests {
    @Test func pagesCreatorStudioProducerReadsTablesImagesAndUnicodeInOrder() throws {
        let data = try fixture("pages-15.4.pages"), result = try Document.read(data), doc = result.document
        #expect(doc.blocks.map(\.plainText) == ["Synthetic Pages fixture", "A😀B 日本語", "Label\tValue\nOrbit\t42\nHarbor\t7.5", "After table", "", "After image"])
        let table = try #require(doc.tables.first)
        #expect(table.rows.map { $0.cells.map(\.plainText) } == [["Label", "Value"], ["Orbit", "42"], ["Harbor", "7.5"]])
        #expect(table.rows.map(\.isHeader) == [true, false, false])
        #expect(table.columnWidths == [150, 150] && table.rows.map(\.height) == [18, 18, 18])
        #expect(table.preferredWidth?.value == 300)
        #expect(table.rows[0].cells[0].blocks.flatMap(\.paragraphs).first?.runs.first?.formatting.fontName != nil)
        guard case .paragraph(let imageParagraph) = doc.blocks[4], case .image(let image) = imageParagraph.inlines.first else { Issue.record("Missing producer image"); return }
        #expect(image.assetPath == "Data/checker-31.png" && image.name == "checker.png")
        #expect(image.alternativeText == "Fictional checkerboard" && image.width == 72 && image.height == 72 && !image.isFloating)
        #expect(image.contentType == "image/png")
        let png = try doc.asset(at: #require(image.assetPath))
        #expect(png.count == 82 && png.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]))
        #expect(doc.sections.first?.pageWidth == 612 && doc.sections.first?.pageHeight == 792)
        #expect(doc.stories.count == 18 && doc.stories.allSatisfy { $0.plainText.isEmpty })
        #expect(Set(doc.stories.map(\.kind)) == [.header, .footer])
        #expect(result.warnings.contains { $0.element == "Pages.cellProperties" })
        var blocks: [String] = []
        let scan = try Document.scan(data) { blocks.append($0.plainText) }
        #expect(blocks == doc.blocks.map(\.plainText) && scan.blocksRead == 6 && scan.document.blocks.isEmpty && scan.warnings == result.warnings)
        let omitted = try Document.read(data, options: .init(includeRelatedStories: false))
        #expect(omitted.document.stories.isEmpty && omitted.warnings.contains { $0.code == .storiesOmitted })
        #expect(try Document.inspect(data).format == .pages)
    }

    @Test(arguments: [false, true]) func pagesSparseTileCellsAndCachedScalars(_ wide: Bool) throws {
        let textCell = cell(3, flags: 8, values: { var d = Data(); d.append32(9); return d }())
        let stringList = pbBytes(3, pbInt(1, 9) + pbText(3, "A😀B"))
        let table = testTable([(0, textCell), (2, cell(6, flags: 2, values: doubleBytes(1)))], wide: wide, strings: stringList)
        let result = try Document.read(pagesPackage(tableBody("Before\n\u{FFFC}\nAfter", offset: 7) + table))
        #expect(result.document.blocks.map(\.plainText) == ["Before", "A😀B\t\tTRUE", "After"])
        #expect(result.document.tables[0].rows[0].cells.count == 3)
        #expect(result.document.tables[0].rows[0].cells[1].blocks.isEmpty)
    }

    @Test func pagesDecimalCellsKeepExactCoefficientAndCachedFormulaWarnings() throws {
        // iWork decimal128: signed 113-bit coefficient 12345, exponent -2.
        var decimal = Data(repeating: 0, count: 16); decimal[0] = 0x39; decimal[1] = 0x30
        let biased = 0x1820 - 2; decimal[14] = UInt8((biased & 127) << 1); decimal[15] = UInt8(biased >> 7) | 0x80
        var formula = Data(); formula.append32(99)
        let table = testTable([(0, cell(2, flags: 1 | 512, values: decimal + formula)), (1, cell(2, flags: 2, values: doubleBytes(7.5)))])
        let result = try Document.read(pagesPackage(tableBody() + table))
        #expect(result.document.tables[0].plainText == "-123.45\t7.5\t")
        #expect(result.warnings.contains { $0.element == "Pages.cellProperties" })
    }

    @Test func pagesUnknownCellVersionsKindsAndRichRangesRemainExplicit() throws {
        for table in [testTable([(0, cell(99))]), testTable([(0, cell(3))], version: 4)] {
            let result = try Document.read(pagesPackage(tableBody() + table))
            guard case .unsupported = result.document.tables[0].rows[0].cells[0].blocks.first else { Issue.record("Unsupported cell became empty"); continue }
            #expect(result.warnings.contains { $0.element == "Pages.cellKind" || $0.element == "Pages.cellVersion" })
        }
        let payload = iwaArchive(30, 6218, pbRef(1, 31) + pbBytes(2, pbInt(1, 0) + pbInt(2, 1)))
        let storage = iwaArchive(31, 2001, pbInt(1, 5) + pbText(3, "Source"))
        let list = pbBytes(3, pbInt(1, 1) + pbRef(9, 30))
        var key = Data(); key.append32(1)
        let result = try Document.read(pagesPackage(tableBody() + testTable([(0, cell(9, flags: 16, values: key))], extraRecords: payload + storage, rich: list)))
        #expect(result.warnings.contains { $0.element == "Pages.richTextRange" })
        #expect(result.document.tables[0].plainText == "\t\t")
        let segmented = try Document.read(pagesPackage(tableBody() + testTable([(0, cell(3, flags: 8, values: key))], extraRecords: iwaArchive(99, 9999, Data()), strings: pbRef(4, 99))))
        #expect(segmented.warnings.contains { $0.element == "Pages.segmentedCellData" })
        guard case .unsupported = segmented.document.tables[0].rows[0].cells[0].blocks.first else { Issue.record("Segmented cell became empty"); return }
    }

    @Test func pagesTablesRejectMalformedDimensionsOffsetsPayloadsAndCycles() throws {
        let root = tableBody()
        let invalid = [
            testTable([(0, cell(3))]), // missing string key
            testTable([(0, cell(2, flags: 2))]), // truncated double
            testTable([(0, cell(0))], rowIndex: 1),
            testTable([(0, cell(0)), (0, cell(0))]), // count disagrees with physical offsets
            testTable([(0, cell(0))], extraModel: pbInt(9, 2)),
            testTable([(0, cell(0))], extraStore: pbRef(4, 999)),
        ]
        for table in invalid { #expect(throws: DocumentError.self) { try Document.read(pagesPackage(root + table)) } }
        for values: [UInt16] in [[0, 0, 0xFFFF], [0, 24, 0xFFFF], [0, 0x8000, 0xFFFF]] {
            var offsets = Data(); for value in values { offsets.append16(value) }
            let table = testTable([(0, cell(0)), (1, cell(0))], offsetOverride: offsets)
            #expect(throws: DocumentError.corruptedPackage("invalid Pages cell offset")) { try Document.read(pagesPackage(root + table)) }
        }
        // A rich-text cell points back through an attachment to its owning table.
        var key = Data(); key.append32(1)
        let rich = pbBytes(3, pbInt(1, 1) + pbRef(9, 30))
        let recursive = iwaArchive(30, 6218, pbRef(1, 31)) + iwaArchive(31, 2001, pbInt(1, 5) + pbText(3, "\u{FFFC}") + pbBytes(9, anchors([(0, 20)])))
        let table = testTable([(0, cell(9, flags: 16, values: key))], extraRecords: recursive, rich: rich)
        #expect(throws: DocumentError.corruptedPackage("Pages content reference cycle")) { try Document.read(pagesPackage(root + table)) }
        let huge = iwaArchive(20, 2003, pbRef(1, 21)) + iwaArchive(21, 6000, pbRef(2, 22)) + iwaArchive(22, 6001, pbInt(6, 1000) + pbInt(7, 1000))
        #expect(throws: DocumentError.limitExceeded("Pages table dimensions")) { try Document.read(pagesPackage(root + huge), options: .init(limits: .init(maxXMLNodes: 500))) }
        #expect(throws: DocumentError.limitExceeded("Pages content depth")) { try Document.read(pagesPackage(root + testTable([(0, cell(0))])), options: .init(limits: .init(maxXMLDepth: 1))) }
    }

    @Test func pagesMixedTableAndUnknownDrawablesRetainInlineMarkers() throws {
        for target in [testTable([(0, cell(0))]), iwaArchive(20, 2003, pbRef(1, 21)) + iwaArchive(21, 9999, pbText(1, "Opaque"))] {
            let result = try Document.read(pagesPackage(tableBody("A\u{FFFC}B", offset: 1) + target))
            #expect(result.document.plainText == "A\u{FFFC}B" && result.document.tables.isEmpty)
            #expect(result.warnings.contains { $0.element == "Pages.attachment" })
            #expect(result.document.paragraphs.first?.inlines.count == 3)
        }
    }

    @Test func pagesImagesUseMetadataAndKeepAssetCRCChecksLazy() throws {
        var data = pagesPackage(tableBody("A😀\u{FFFC}B", offset: 3) + imageRecords(), otherParts: [("Data/checker.png", Data("CHECKER".utf8))])
        let range = try #require(data.range(of: Data("CHECKER".utf8))); data[range.lowerBound] ^= 1
        let result = try Document.read(data)
        #expect(result.document.plainText == "A😀B")
        guard case .image(let image) = result.document.paragraphs[0].inlines[1] else { Issue.record("Missing inline image"); return }
        #expect(image.width == 72 && image.height == 36 && image.alternativeText == "Fictional image" && image.name == "Original checker")
        #expect(throws: DocumentError.corruptedPackage("CRC mismatch in Data/checker.png")) { try result.document.asset(at: #require(image.assetPath)) }
        #expect(try Document.inspect(data).format == .pages)
    }

    @Test func pagesImagesRejectMissingDuplicateUnsafeResourcesAndBrokenAnchors() throws {
        let asset = [("Data/checker.png", Data("Image".utf8))]
        #expect(throws: DocumentError.corruptedPackage("missing Pages image asset")) { try Document.read(pagesPackage(tableBody() + imageRecords())) }
        for (records, error) in [(imageRecords(duplicate: true), "duplicate / invalid Pages resource ID"), (imageRecords(filename: "../escape.png"), "unsafe Pages image resource path"), (imageRecords(resource: 99), "missing Pages image asset")] {
            #expect(throws: DocumentError.corruptedPackage(error)) { try Document.read(pagesPackage(tableBody() + records, otherParts: asset)) }
        }
        for offset: UInt64 in [2, 5, 99] {
            #expect(throws: DocumentError.self) { try Document.read(pagesPackage(tableBody("A😀\u{FFFC}B", offset: offset) + imageRecords(), otherParts: asset)) }
        }
        #expect(throws: DocumentError.self) { try Document.read(pagesPackage(tableBody() + iwaArchive(20, 2003, pbRef(1, 999)))) }
        let duplicate = iwaArchive(1, 10000, pbRef(4, 10)) + iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "\u{FFFC}") + pbBytes(9, anchors([(0, 20), (0, 20)])))
        #expect(throws: DocumentError.corruptedPackage("invalid Pages text boundary")) { try Document.read(pagesPackage(duplicate + imageRecords(), otherParts: asset)) }
    }
}
