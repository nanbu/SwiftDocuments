# Public API inventory

Generated from the current compiler symbol graph by `scripts/generate-api-index.py`.
This lists explicit public declarations in DocumentCore, DocumentDOCX, DocumentODT, DocumentPages and the
SwiftDocuments umbrella, including convenience extensions and enum cases.
Compiler-synthesized conformances are omitted. Use the DocC reference for
parameter documentation and the reading specification for support boundaries.

Explicit public declarations: 1210.

## Block

```swift
indirect enum Block
```

```swift
case contentControl(ContentControl)
```

```swift
case paragraph(Paragraph)
```

```swift
var paragraphs: [Paragraph] { get }
```

```swift
var plainText: String { get }
```

```swift
case table(Table)
```

```swift
var tables: [Table] { get }
```

```swift
case unsupported(UnsupportedContent)
```

## Bookmark

```swift
struct Bookmark
```

```swift
var id: String
```

```swift
init(id: String, name: String? = nil, isStart: Bool)
```

```swift
var isStart: Bool
```

```swift
var name: String?
```

## BreakKind

```swift
enum BreakKind
```

```swift
case column
```

```swift
init?(rawValue: String)
```

```swift
case line
```

```swift
case page
```

## CellMergeChange

```swift
struct CellMergeChange
```

```swift
init(revision: Revision, wasMergedWithPrevious: Bool, isMergedWithPrevious: Bool, source: SourceXMLNode? = nil)
```

```swift
var isMergedWithPrevious: Bool { get set }
```

```swift
var revision: Revision { get set }
```

```swift
var source: SourceXMLNode? { get set }
```

```swift
var wasMergedWithPrevious: Bool { get set }
```

## Chart

```swift
struct Chart
```

```swift
var axes: [ChartAxis]
```

```swift
var externalData: PartReference?
```

```swift
var groups: [ChartGroup]
```

```swift
init(from decoder: any Decoder) throws
```

```swift
init(part: PartReference, groups: [ChartGroup] = [], axes: [ChartAxis] = [], title: String? = nil, legendPosition: String? = nil, externalData: PartReference? = nil, properties: SourceXMLNode? = nil)
```

```swift
var legendPosition: String?
```

```swift
var part: PartReference
```

```swift
var properties: SourceXMLNode?
```

```swift
var title: String?
```

## ChartAxis

```swift
struct ChartAxis
```

```swift
var crossAxisID: String?
```

```swift
var id: String?
```

```swift
init(from decoder: any Decoder) throws
```

```swift
init(kind: String)
```

```swift
var isDeleted: Bool?
```

```swift
var kind: String
```

```swift
var logarithmicBase: Double?
```

```swift
var maximum: Double?
```

```swift
var minimum: Double?
```

```swift
var numberFormat: String?
```

```swift
var position: String?
```

```swift
var properties: SourceXMLNode?
```

## ChartData

```swift
struct ChartData
```

```swift
enum Source
```

```swift
init?(rawValue: String)
```

```swift
case multiLevelStringCache
```

```swift
case multiLevelStringReference
```

```swift
case numberCache
```

```swift
case numberLiteral
```

```swift
case numberReference
```

```swift
case stringCache
```

```swift
case stringLiteral
```

```swift
case stringReference
```

```swift
var formatCode: String?
```

```swift
var formula: String?
```

```swift
init(from decoder: any Decoder) throws
```

```swift
init(source: ChartData.Source, formula: String? = nil, pointCount: Int? = nil, formatCode: String? = nil, points: [ChartPoint] = [], levels: [[ChartPoint]]? = nil, properties: SourceXMLNode? = nil)
```

```swift
var levels: [[ChartPoint]]?
```

```swift
var pointCount: Int?
```

```swift
var points: [ChartPoint]
```

```swift
var properties: SourceXMLNode?
```

```swift
var source: ChartData.Source
```

## ChartGroup

```swift
struct ChartGroup
```

```swift
var axisIDs: [String]
```

```swift
var grouping: String?
```

```swift
init(from decoder: any Decoder) throws
```

```swift
init(kind: String, grouping: String? = nil, orientation: String? = nil, series: [ChartSeries] = [], axisIDs: [String] = [], properties: SourceXMLNode? = nil)
```

```swift
var kind: String
```

```swift
var orientation: String?
```

```swift
var properties: SourceXMLNode?
```

```swift
var series: [ChartSeries]
```

## ChartPoint

```swift
struct ChartPoint
```

```swift
var index: Int
```

```swift
init(from decoder: any Decoder) throws
```

```swift
init(index: Int, text: String)
```

```swift
var number: Double? { get }
```

```swift
var text: String
```

## ChartSeries

```swift
struct ChartSeries
```

```swift
var bubbleSizes: ChartData?
```

```swift
var categories: ChartData?
```

```swift
var index: Int?
```

```swift
init()
```

```swift
init(from decoder: any Decoder) throws
```

```swift
var order: Int?
```

```swift
var properties: SourceXMLNode?
```

```swift
var title: String?
```

```swift
var titleData: ChartData?
```

```swift
var values: ChartData?
```

```swift
var xValues: ChartData?
```

```swift
var yValues: ChartData?
```

## Codec

```swift
struct Codec
```

```swift
static let docm: Codec
```

```swift
static let docx: Codec
```

```swift
var format: DocumentFormat { get }
```

```swift
init(_ codec: any DocumentCodec)
```

```swift
static let odt: Codec
```

```swift
static let pages: Codec
```

## CodecSet

```swift
struct CodecSet
```

```swift
static let all: CodecSet
```

```swift
func codec(for format: DocumentFormat) throws -> Codec
```

```swift
func contains(_ format: DocumentFormat) -> Bool
```

```swift
let formats: [DocumentFormat]
```

```swift
init(_ codecs: [Codec])
```

```swift
@concurrent func inspect(_ data: Data, format: DocumentFormat? = nil, limits: PackageLimits = .init()) async throws -> DocumentSummary
```

```swift
func inspect(_ data: Data, format: DocumentFormat? = nil, limits: PackageLimits = .init()) throws -> DocumentSummary
```

```swift
@concurrent func inspect(contentsOf url: URL, format: DocumentFormat? = nil, limits: PackageLimits = .init()) async throws -> DocumentSummary
```

```swift
func inspect(contentsOf url: URL, format: DocumentFormat? = nil, limits: PackageLimits = .init()) throws -> DocumentSummary
```

```swift
@concurrent func read(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult
```

```swift
func read(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult
```

```swift
@concurrent func read(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult
```

```swift
func read(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult
```

```swift
@concurrent func readAll(contentsOf urls: [URL], options: ReadOptions = .init(), maxConcurrentReads: Int = 4) async throws -> [ReadResult]
```

```swift
func scan(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult
```

```swift
func scan(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult
```

## ColorTransform

```swift
struct ColorTransform
```

```swift
init(name: String, value: Double? = nil)
```

```swift
var name: String
```

```swift
var value: Double?
```

## CommentReference

```swift
struct CommentReference
```

```swift
enum Boundary
```

```swift
case end
```

```swift
init?(rawValue: String)
```

```swift
case reference
```

```swift
case start
```

```swift
var boundary: CommentReference.Boundary
```

```swift
var id: String
```

```swift
init(id: String, boundary: CommentReference.Boundary)
```

## ContentBinding

```swift
struct ContentBinding
```

```swift
init(storeID: String? = nil, pathQuery: String? = nil, namespaceMappings: String? = nil)
```

```swift
var namespaceMappings: String?
```

```swift
var pathQuery: String?
```

```swift
var storeID: String?
```

## ContentControl

```swift
struct ContentControl
```

```swift
indirect enum Content
```

```swift
case blocks([Block])
```

```swift
case inlines([Inline])
```

```swift
enum EditingLock
```

```swift
case content
```

```swift
case contentAndControl
```

```swift
case control
```

```swift
init?(rawValue: String)
```

```swift
case native
```

```swift
case unlocked
```

```swift
enum Kind
```

```swift
case bibliography
```

```swift
case checkBox
```

```swift
case citation
```

```swift
case comboBox
```

```swift
case date
```

```swift
case documentPart
```

```swift
case dropDownList
```

```swift
case equation
```

```swift
case group
```

```swift
init?(rawValue: String)
```

```swift
case picture
```

```swift
case plainText
```

```swift
case repeatingItem
```

```swift
case repeatingSection
```

```swift
case richText
```

```swift
var content: ContentControl.Content
```

```swift
var descriptor: ContentControlDescriptor
```

```swift
init(descriptor: ContentControlDescriptor = .init(), content: ContentControl.Content)
```

```swift
var paragraphs: [Paragraph] { get }
```

```swift
var plainText: String { get }
```

```swift
var runs: [TextRun] { get }
```

```swift
var tables: [Table] { get }
```

## ContentControlDescriptor

```swift
struct ContentControlDescriptor
```

```swift
var binding: ContentBinding?
```

```swift
var checkedSymbol: SymbolCharacter?
```

```swift
var dateCalendar: String?
```

```swift
var dateFormat: String?
```

```swift
var dateLanguage: String?
```

```swift
var dateValue: String?
```

```swift
var editingLock: ContentControl.EditingLock?
```

```swift
var endFormatting: TextFormatting?
```

```swift
var formatting: TextFormatting?
```

```swift
var id: String?
```

```swift
init(sourcePart: String = "")
```

```swift
var isChecked: Bool?
```

```swift
var isMultiline: Bool?
```

```swift
var isShowingPlaceholder: Bool?
```

```swift
var isTemporary: Bool?
```

```swift
var items: [ContentControlItem]
```

```swift
var kind: ContentControl.Kind
```

```swift
var placeholderName: String?
```

```swift
var selectedValue: String?
```

```swift
var sourceHeader: SourceXMLNode?
```

```swift
var sourcePart: String
```

```swift
var tag: String?
```

```swift
var title: String?
```

```swift
var uncheckedSymbol: SymbolCharacter?
```

## ContentControlItem

```swift
struct ContentControlItem
```

```swift
var displayText: String?
```

```swift
init(displayText: String? = nil, value: String? = nil)
```

```swift
var value: String?
```

## ContentControlRange

```swift
struct ContentControlRange
```

```swift
var descriptor: ContentControlDescriptor
```

```swift
init(range: Range<Int>, descriptor: ContentControlDescriptor)
```

```swift
var range: Range<Int>
```

## CustomGeometryEvaluation

```swift
struct CustomGeometryEvaluation
```

```swift
let adjustments: [String : Double]
```

```swift
let guides: [String : Double]
```

```swift
init(from decoder: any Decoder) throws
```

```swift
let paths: [EvaluatedGeometryPath]
```

## DOCXCodec

```swift
struct DOCXCodec
```

```swift
let format: DocumentFormat
```

```swift
init(macroEnabled: Bool = false)
```

```swift
func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentSummary
```

```swift
func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult
```

```swift
func scan(_ data: Data, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult
```

## Document

```swift
struct Document
```

```swift
@concurrent func asset(at path: String) async throws -> Data
```

```swift
func asset(at path: String) throws -> Data
```

```swift
var blocks: [Block]
```

```swift
var fieldDefinitions: [FieldDefinition]
```

```swift
var fonts: [DocumentFont]
```

```swift
init()
```

```swift
init(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws
```

```swift
init(data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws
```

```swift
@concurrent static func inspect(_ data: Data, format: DocumentFormat? = nil, limits: PackageLimits = .init()) async throws -> DocumentSummary
```

```swift
static func inspect(_ data: Data, format: DocumentFormat? = nil, limits: PackageLimits = .init()) throws -> DocumentSummary
```

```swift
@concurrent static func inspect(contentsOf url: URL, format: DocumentFormat? = nil, limits: PackageLimits = .init()) async throws -> DocumentSummary
```

```swift
static func inspect(contentsOf url: URL, format: DocumentFormat? = nil, limits: PackageLimits = .init()) throws -> DocumentSummary
```

```swift
var metadata: DocumentMetadata
```

```swift
var numbering: [String : NumberingDefinition]
```

```swift
var packageParts: [PackagePart]
```

```swift
var paragraphs: [Paragraph] { get }
```

```swift
var plainText: String { get }
```

```swift
@concurrent static func read(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult
```

```swift
static func read(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult
```

```swift
@concurrent static func read(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult
```

```swift
static func read(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult
```

```swift
@concurrent static func readAll(contentsOf urls: [URL], options: ReadOptions = .init(), maxConcurrentReads: Int = 4) async throws -> [ReadResult]
```

```swift
@concurrent func readSourceXML(at path: String) async throws -> SourceXMLReadResult
```

```swift
func readSourceXML(at path: String) throws -> SourceXMLReadResult
```

```swift
var readWarnings: [ReadWarning]
```

```swift
static func scan(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult
```

```swift
static func scan(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult
```

```swift
var sections: [Section]
```

```swift
var settings: [String : String]
```

```swift
var sourceFormat: DocumentFormat?
```

```swift
var stories: [Story]
```

```swift
var styles: [String : DocumentStyle]
```

```swift
var tables: [Table] { get }
```

```swift
var theme: DocumentTheme?
```

```swift
var uninterpretedContent: [UnsupportedContent]
```

## DocumentCodec

```swift
protocol DocumentCodec : Sendable
```

```swift
var format: DocumentFormat { get }
```

```swift
func inspect(_ data: Data, limits: PackageLimits) throws -> DocumentSummary
```

```swift
func read(_ data: Data, options: ReadOptions) throws -> ReadResult
```

```swift
func scan(_ data: Data, options: ReadOptions, onBlock: (Block) throws -> Void) throws -> ScanResult
```

## DocumentDrawing

```swift
struct DocumentDrawing
```

```swift
init(root: DrawingNode, placement: DrawingPlacement = .init(), sourcePart: String = "", rawXML: String = "", revision: Revision? = nil)
```

```swift
var placement: DrawingPlacement
```

```swift
var rawXML: String
```

```swift
var revision: Revision?
```

```swift
var root: DrawingNode
```

```swift
var sourcePart: String
```

## DocumentError

```swift
enum DocumentError
```

```swift
case corruptedPackage(String)
```

```swift
var description: String { get }
```

```swift
case invalidModel(String)
```

```swift
case invalidOptions(String)
```

```swift
case invalidRelationship(part: String, detail: String)
```

```swift
case invalidXML(part: String, detail: String)
```

```swift
case limitExceeded(String)
```

```swift
case missingPart(String)
```

```swift
case noCodec(DocumentFormat)
```

```swift
case unknownFormat
```

```swift
case unsupportedContainer(String)
```

## DocumentFont

```swift
struct DocumentFont
```

```swift
var alternateName: String?
```

```swift
var charset: String?
```

```swift
var embeddedFaces: [EmbeddedFont]
```

```swift
var family: String?
```

```swift
init(name: String)
```

```swift
var name: String
```

```swift
var panose: String?
```

```swift
var pitch: String?
```

## DocumentFormat

```swift
enum DocumentFormat
```

```swift
static func detect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentFormat
```

```swift
static func detect(contentsOf url: URL, limits: PackageLimits = .init()) throws -> DocumentFormat
```

```swift
case docm
```

```swift
case docx
```

```swift
var fileExtension: String { get }
```

```swift
init?(fileExtension: String)
```

```swift
init?(rawValue: String)
```

```swift
case odt
```

```swift
case pages
```

```swift
var productName: String { get }
```

## DocumentImage

```swift
struct DocumentImage
```

```swift
var alternativeText: String?
```

```swift
var assetPath: String?
```

```swift
var contentType: String?
```

```swift
var crop: ImageCrop?
```

```swift
var drawing: DocumentDrawing?
```

```swift
var externalURL: String?
```

```swift
var fallbackAssetPath: String?
```

```swift
var fallbackExternalURL: String?
```

```swift
var height: Double?
```

```swift
init(assetPath: String? = nil, externalURL: String? = nil, name: String? = nil, alternativeText: String? = nil, width: Double? = nil, height: Double? = nil, isFloating: Bool = false, rawXML: String = "")
```

```swift
var isFloating: Bool
```

```swift
var name: String?
```

```swift
var rawXML: String
```

```swift
var revision: Revision?
```

```swift
var width: Double?
```

## DocumentMetadata

```swift
struct DocumentMetadata
```

```swift
var application: String?
```

```swift
var created: String?
```

```swift
var creator: String?
```

```swift
var custom: [String : String]
```

```swift
var declaredPages: Int?
```

```swift
var declaredWords: Int?
```

```swift
var description: String?
```

```swift
init()
```

```swift
init(from decoder: any Decoder) throws
```

```swift
var keywords: String?
```

```swift
var lastModifiedBy: String?
```

```swift
var modified: String?
```

```swift
var subject: String?
```

```swift
var title: String?
```

## DocumentStyle

```swift
struct DocumentStyle
```

```swift
var basedOn: String?
```

```swift
var columnBandSize: Int?
```

```swift
var id: String
```

```swift
init(id: String, name: String, kind: String, basedOn: String? = nil, isDefault: Bool = false, paragraph: ParagraphFormatting = .init(), text: TextFormatting = .init(), list: ListReference? = nil)
```

```swift
var isDefault: Bool
```

```swift
var kind: String
```

```swift
var list: ListReference?
```

```swift
var name: String
```

```swift
var paragraph: ParagraphFormatting
```

```swift
var rowBandSize: Int?
```

```swift
var tableRules: [TableStyleRule]
```

```swift
var text: TextFormatting
```

## DocumentSummary

```swift
struct DocumentSummary
```

```swift
var expandedBytes: Int { get }
```

```swift
var format: DocumentFormat
```

```swift
init(format: DocumentFormat, metadata: DocumentMetadata, parts: [PackagePart])
```

```swift
init(from decoder: any Decoder) throws
```

```swift
var metadata: DocumentMetadata
```

```swift
var parts: [PackagePart]
```

## DocumentTheme

```swift
struct DocumentTheme
```

```swift
var colors: [String : String]
```

```swift
init()
```

```swift
var majorFonts: [String : String]
```

```swift
var minorFonts: [String : String]
```

## DrawingColor

```swift
struct DrawingColor
```

```swift
init(value: String, isTheme: Bool = false, transforms: [ColorTransform] = [])
```

```swift
var isTheme: Bool
```

```swift
var transforms: [ColorTransform]
```

```swift
var value: String
```

## DrawingConnection

```swift
struct DrawingConnection
```

```swift
init(targetID: String, siteIndex: UInt32)
```

```swift
var siteIndex: UInt32
```

```swift
var targetID: String
```

## DrawingFill

```swift
struct DrawingFill
```

```swift
enum Kind
```

```swift
case gradient
```

```swift
init?(rawValue: String)
```

```swift
case none
```

```swift
case pattern
```

```swift
case picture
```

```swift
case solid
```

```swift
var angle: Double?
```

```swift
var backgroundColor: DrawingColor?
```

```swift
var color: DrawingColor?
```

```swift
var gradientStops: [GradientStop]
```

```swift
var image: DrawingImage?
```

```swift
init(kind: DrawingFill.Kind, color: DrawingColor? = nil)
```

```swift
var kind: DrawingFill.Kind
```

```swift
var pattern: String?
```

```swift
var rawXML: String?
```

## DrawingGeometry

```swift
struct DrawingGeometry
```

```swift
var adjustments: [GeometryGuide]
```

```swift
var guides: [GeometryGuide]
```

```swift
init()
```

```swift
var paths: [GeometryPath]
```

```swift
var preset: String?
```

```swift
var rawXML: String?
```

## DrawingImage

```swift
struct DrawingImage
```

```swift
var assetPath: String?
```

```swift
var contentType: String?
```

```swift
var crop: ImageCrop?
```

```swift
var externalURL: String?
```

```swift
var fallbackAssetPath: String?
```

```swift
var fallbackExternalURL: String?
```

```swift
init(assetPath: String? = nil, externalURL: String? = nil)
```

```swift
var opacity: Double?
```

## DrawingLine

```swift
struct DrawingLine
```

```swift
var cap: String?
```

```swift
var dash: String?
```

```swift
var fill: DrawingFill?
```

```swift
var head: String?
```

```swift
init()
```

```swift
var rawXML: String?
```

```swift
var tail: String?
```

```swift
var width: Double?
```

## DrawingNode

```swift
struct DrawingNode
```

```swift
enum Kind
```

```swift
case canvas
```

```swift
case chart
```

```swift
case connector
```

```swift
case diagram
```

```swift
case group
```

```swift
case image
```

```swift
init?(rawValue: String)
```

```swift
case ink
```

```swift
case shape
```

```swift
case unknown
```

```swift
var alternativeText: String?
```

```swift
var chart: Chart?
```

```swift
var children: [DrawingNode]
```

```swift
var endConnection: DrawingConnection?
```

```swift
var fill: DrawingFill?
```

```swift
var geometry: DrawingGeometry?
```

```swift
var id: String?
```

```swift
var image: DrawingImage?
```

```swift
init(kind: DrawingNode.Kind)
```

```swift
var kind: DrawingNode.Kind
```

```swift
var line: DrawingLine?
```

```swift
var name: String?
```

```swift
var plainText: String { get }
```

```swift
var rawProperties: [String]
```

```swift
var relatedPart: String?
```

```swift
var sourcePart: String?
```

```swift
var startConnection: DrawingConnection?
```

```swift
var text: [Block]
```

```swift
var textProperties: [String : String]
```

```swift
var transform: DrawingTransform
```

## DrawingPlacement

```swift
struct DrawingPlacement
```

```swift
var allowOverlap: Bool
```

```swift
var behindText: Bool
```

```swift
var distances: [String : Double]
```

```swift
var height: Double?
```

```swift
var horizontal: DrawingPosition?
```

```swift
init()
```

```swift
var isFloating: Bool
```

```swift
var layoutInCell: Bool
```

```swift
var rawProperties: [String]
```

```swift
var relativeHeight: Int?
```

```swift
var vertical: DrawingPosition?
```

```swift
var width: Double?
```

```swift
var wrap: String?
```

```swift
var wrapSide: String?
```

## DrawingPosition

```swift
struct DrawingPosition
```

```swift
var alignment: String?
```

```swift
init(relativeTo: String, offset: Double? = nil, alignment: String? = nil, percentage: Double? = nil)
```

```swift
var offset: Double?
```

```swift
var percentage: Double?
```

```swift
var relativeTo: String
```

## DrawingRect

```swift
struct DrawingRect
```

```swift
var height: Double
```

```swift
init(x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0)
```

```swift
var width: Double
```

```swift
var x: Double
```

```swift
var y: Double
```

## DrawingTransform

```swift
struct DrawingTransform
```

```swift
var bounds: DrawingRect
```

```swift
var childBounds: DrawingRect?
```

```swift
var flipHorizontal: Bool
```

```swift
var flipVertical: Bool
```

```swift
init()
```

```swift
var rotation: Double
```

## EmbeddedFont

```swift
struct EmbeddedFont
```

```swift
var assetPath: String
```

```swift
var face: String
```

```swift
init(assetPath: String, key: String? = nil, face: String = "regular", isSubset: Bool = false)
```

```swift
var isSubset: Bool
```

```swift
var key: String?
```

## Equation

```swift
struct Equation
```

```swift
static func == (lhs: Equation, rhs: Equation) -> Bool
```

```swift
enum Dialect
```

```swift
init?(rawValue: String)
```

```swift
case mathML
```

```swift
case omml
```

```swift
var dialect: Equation.Dialect { get }
```

```swift
func encode(to encoder: any Encoder) throws
```

```swift
init(dialect: Equation.Dialect = .omml, root: EquationNode, source: SourceXMLNode, part: String)
```

```swift
init(from decoder: any Decoder) throws
```

```swift
var lexicalText: String { get }
```

```swift
var part: String { get }
```

```swift
var root: EquationNode { get }
```

```swift
var source: SourceXMLNode { get }
```

## EquationNode

```swift
struct EquationNode
```

```swift
enum Kind
```

```swift
case accent
```

```swift
case action
```

```swift
case annotation
```

```swift
case application
```

```swift
case bar
```

```swift
case base
```

```swift
case binding
```

```swift
case borderBox
```

```swift
case boundVariable
```

```swift
case box
```

```swift
case contentConstant
```

```swift
case contentOperator
```

```swift
case contentSymbol
```

```swift
case declaration
```

```swift
case degree
```

```swift
case delimiter
```

```swift
case denominator
```

```swift
case enclosed
```

```swift
case equationArray
```

```swift
case error
```

```swift
case fraction
```

```swift
case function
```

```swift
case functionName
```

```swift
case groupCharacter
```

```swift
case identifier
```

```swift
init?(rawValue: String)
```

```swift
case interval
```

```swift
case lambda
```

```swift
case limit
```

```swift
case list
```

```swift
case lowerLimit
```

```swift
case math
```

```swift
case matrix
```

```swift
case matrixRow
```

```swift
case multiscripts
```

```swift
case nary
```

```swift
case native
```

```swift
case none
```

```swift
case number
```

```swift
case numerator
```

```swift
case operatorToken
```

```swift
case otherwise
```

```swift
case over
```

```swift
case padded
```

```swift
case paragraph
```

```swift
case phantom
```

```swift
case piece
```

```swift
case piecewise
```

```swift
case preSubSuperscript
```

```swift
case prescripts
```

```swift
case properties
```

```swift
case property
```

```swift
case qualifier
```

```swift
case radical
```

```swift
case row
```

```swift
case run
```

```swift
case semantics
```

```swift
case separator
```

```swift
case set
```

```swift
case share
```

```swift
case space
```

```swift
case stringLiteral
```

```swift
case style
```

```swift
case subSuperscript
```

```swift
case subscriptArgument
```

```swift
case subscriptExpression
```

```swift
case superscript
```

```swift
case superscriptArgument
```

```swift
case tableCell
```

```swift
case text
```

```swift
case under
```

```swift
case underOver
```

```swift
case upperLimit
```

```swift
case vector
```

```swift
var appliedOperator: EquationNode? { get }
```

```swift
let attributes: [String : String]
```

```swift
var boundVariables: [EquationNode] { get }
```

```swift
let children: [EquationNode]
```

```swift
init(from decoder: any Decoder) throws
```

```swift
init(kind: EquationNode.Kind, name: String, namespace: String, attributes: [String : String] = [:], text: String? = nil, tokenParts: [String]? = nil, children: [EquationNode] = [])
```

```swift
let kind: EquationNode.Kind
```

```swift
var lexicalText: String { get }
```

```swift
let name: String
```

```swift
let namespace: String
```

```swift
let text: String?
```

```swift
let tokenParts: [String]?
```

## EvaluatedArc

```swift
struct EvaluatedArc
```

```swift
let center: PathPoint
```

```swift
let end: PathPoint
```

```swift
let heightRadius: Double
```

```swift
init(from decoder: any Decoder) throws
```

```swift
let startAngle: Double
```

```swift
let sweepAngle: Double
```

```swift
let widthRadius: Double
```

## EvaluatedGeometryPath

```swift
struct EvaluatedGeometryPath
```

```swift
let commands: [EvaluatedPathCommand]
```

```swift
let extrusionOK: Bool?
```

```swift
let fillMode: String?
```

```swift
let height: Double?
```

```swift
init(from decoder: any Decoder) throws
```

```swift
let stroke: Bool?
```

```swift
let width: Double?
```

## EvaluatedPathCommand

```swift
enum EvaluatedPathCommand
```

```swift
case arc(EvaluatedArc)
```

```swift
case close
```

```swift
case cubic(control1: PathPoint, control2: PathPoint, end: PathPoint)
```

```swift
init(from decoder: any Decoder) throws
```

```swift
case line(PathPoint)
```

```swift
case move(PathPoint)
```

```swift
case quadratic(control: PathPoint, end: PathPoint)
```

## Field

```swift
struct Field
```

```swift
var codeContent: [Inline]
```

```swift
var fragment: FieldFragment?
```

```swift
init(instruction: String, result: [Inline], isLocked: Bool = false)
```

```swift
var instruction: String
```

```swift
var isLocked: Bool
```

```swift
var result: [Inline]
```

## FieldDefinition

```swift
struct FieldDefinition
```

```swift
enum Kind
```

```swift
case complex
```

```swift
init?(rawValue: String)
```

```swift
case simple
```

```swift
var hasSeparator: Bool
```

```swift
var id: String
```

```swift
init(id: String, parentID: String? = nil, kind: FieldDefinition.Kind = .complex, sourcePart: String, instruction: String = "", isLocked: Bool? = nil, isDirty: Bool? = nil, hasSeparator: Bool = false, isComplete: Bool = false, source: SourceXMLNode? = nil)
```

```swift
var instruction: String
```

```swift
var isComplete: Bool
```

```swift
var isDirty: Bool?
```

```swift
var isLocked: Bool?
```

```swift
var kind: FieldDefinition.Kind
```

```swift
var parentID: String?
```

```swift
var source: SourceXMLNode?
```

```swift
var sourcePart: String
```

## FieldFragment

```swift
struct FieldFragment
```

```swift
var containsSeparator: Bool
```

```swift
var definitionID: String
```

```swift
var endsHere: Bool
```

```swift
init(definitionID: String, startsHere: Bool = false, endsHere: Bool = false, containsSeparator: Bool = false)
```

```swift
init(from decoder: any Decoder) throws
```

```swift
var startsHere: Bool
```

## FormattingChange

```swift
struct FormattingChange<Value> where Value : Sendable
```

```swift
init(revision: Revision, previous: Value, source: SourceXMLNode? = nil)
```

```swift
var previous: Value { get set }
```

```swift
var revision: Revision { get set }
```

```swift
var source: SourceXMLNode? { get set }
```

## GeometryEvaluator

```swift
enum GeometryEvaluator
```

```swift
static func evaluate(_ geometry: DrawingGeometry, width: Double, height: Double, adjustments overrides: [String : Double] = [:], maxOperations: Int = 100_000) throws -> CustomGeometryEvaluation
```

## GeometryGuide

```swift
struct GeometryGuide
```

```swift
var formula: String
```

```swift
init(name: String, formula: String)
```

```swift
var name: String
```

## GeometryPath

```swift
struct GeometryPath
```

```swift
var commands: [GeometryPathCommand]
```

```swift
var extrusionOK: Bool?
```

```swift
var fill: String?
```

```swift
var height: Double?
```

```swift
init()
```

```swift
var stroke: Bool?
```

```swift
var width: Double?
```

## GeometryPathCommand

```swift
enum GeometryPathCommand
```

```swift
case arc(widthRadius: String, heightRadius: String, startAngle: String, sweepAngle: String)
```

```swift
case close
```

```swift
case cubic(control1: GeometryPoint, control2: GeometryPoint, end: GeometryPoint)
```

```swift
case line(GeometryPoint)
```

```swift
case move(GeometryPoint)
```

```swift
case quadratic(control: GeometryPoint, end: GeometryPoint)
```

```swift
case unsupported(String)
```

## GeometryPoint

```swift
struct GeometryPoint
```

```swift
init(x: String, y: String)
```

```swift
var x: String
```

```swift
var y: String
```

## GradientStop

```swift
struct GradientStop
```

```swift
var color: DrawingColor
```

```swift
init(position: Double, color: DrawingColor)
```

```swift
var position: Double
```

## Hyperlink

```swift
struct Hyperlink
```

```swift
var anchor: String?
```

```swift
init(target: String? = nil, anchor: String? = nil, tooltip: String? = nil, inlines: [Inline])
```

```swift
var inlines: [Inline]
```

```swift
var target: String?
```

```swift
var tooltip: String?
```

## ImageCrop

```swift
struct ImageCrop
```

```swift
var bottom: Double
```

```swift
init(left: Double = 0, top: Double = 0, right: Double = 0, bottom: Double = 0)
```

```swift
var left: Double
```

```swift
var right: Double
```

```swift
var top: Double
```

## Inline

```swift
indirect enum Inline
```

```swift
case bookmark(Bookmark)
```

```swift
case commentReference(CommentReference)
```

```swift
case contentControl(ContentControl)
```

```swift
case drawing(DocumentDrawing)
```

```swift
case equation(Equation)
```

```swift
case field(Field)
```

```swift
case hyperlink(Hyperlink)
```

```swift
case image(DocumentImage)
```

```swift
case lineBreak(BreakKind)
```

```swift
case noteReference(NoteReference)
```

```swift
var plainText: String { get }
```

```swift
case ruby(RubyText)
```

```swift
var runs: [TextRun] { get }
```

```swift
case tab
```

```swift
case text(TextRun)
```

```swift
case unsupported(UnsupportedContent)
```

## LineSpacingRule

```swift
enum LineSpacingRule
```

```swift
case atLeast
```

```swift
case exact
```

```swift
init?(rawValue: String)
```

```swift
case multiple
```

## ListReference

```swift
struct ListReference
```

```swift
var id: String
```

```swift
init(id: String, level: Int = 0)
```

```swift
var level: Int
```

## NoteReference

```swift
struct NoteReference
```

```swift
var id: String
```

```swift
init(id: String, kind: StoryKind)
```

```swift
var kind: StoryKind
```

## NumberingDefinition

```swift
struct NumberingDefinition
```

```swift
var abstractID: String
```

```swift
var id: String
```

```swift
init(id: String, abstractID: String, levels: [Int : NumberingLevel])
```

```swift
var levels: [Int : NumberingLevel]
```

## NumberingLevel

```swift
struct NumberingLevel
```

```swift
var format: String
```

```swift
var formatting: TextFormatting
```

```swift
init(level: Int, start: Int = 1, format: String = "decimal", text: String = "%1.", paragraph: ParagraphFormatting = .init(), formatting: TextFormatting = .init(), restartAfterLevel: Int? = nil)
```

```swift
var isLegal: Bool
```

```swift
var level: Int
```

```swift
var paragraph: ParagraphFormatting
```

```swift
var picture: DocumentImage?
```

```swift
var pictureAssetPath: String? { get }
```

```swift
var rawProperties: [String]
```

```swift
var restartAfterLevel: Int?
```

```swift
var start: Int
```

```swift
var suffix: String
```

```swift
var text: String
```

## ODTCodec

```swift
struct ODTCodec
```

```swift
let format: DocumentFormat
```

```swift
init()
```

```swift
func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentSummary
```

```swift
func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult
```

```swift
func scan(_ data: Data, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult
```

## PackageLimits

```swift
struct PackageLimits
```

```swift
init(maxEntries: Int = 10_000, maxExpandedBytes: Int = 512 << 20, maxPartBytes: Int = 128 << 20, maxXMLDepth: Int = 128, maxXMLNodes: Int = 2_000_000)
```

```swift
var maxEntries: Int
```

```swift
var maxExpandedBytes: Int
```

```swift
var maxPartBytes: Int
```

```swift
var maxXMLDepth: Int
```

```swift
var maxXMLNodes: Int
```

## PackagePart

```swift
struct PackagePart
```

```swift
var compressedSize: Int
```

```swift
var contentType: String?
```

```swift
var expandedSize: Int
```

```swift
init(from decoder: any Decoder) throws
```

```swift
init(path: String, contentType: String? = nil, compressedSize: Int, expandedSize: Int)
```

```swift
var path: String
```

## PageOrientation

```swift
enum PageOrientation
```

```swift
init?(rawValue: String)
```

```swift
case landscape
```

```swift
case portrait
```

## PagesCodec

```swift
struct PagesCodec
```

```swift
let format: DocumentFormat
```

```swift
init()
```

```swift
func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentSummary
```

```swift
func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult
```

```swift
func scan(_ data: Data, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult
```

## Paragraph

```swift
struct Paragraph
```

```swift
var defaultTextFormatting: TextFormatting
```

```swift
var formatting: ParagraphFormatting
```

```swift
var formattingChange: ParagraphFormattingChange?
```

```swift
init()
```

```swift
var inlines: [Inline]
```

```swift
var list: ListReference?
```

```swift
var paragraphMarkFormatting: TextFormatting?
```

```swift
var paragraphMarkFormattingChange: TextFormattingChange?
```

```swift
var paragraphMarkRevision: Revision? { get set }
```

```swift
var paragraphMarkRevisions: [Revision]
```

```swift
var plainText: String { get }
```

```swift
var runs: [TextRun] { get }
```

```swift
var sectionBreak: Section?
```

```swift
var styleID: String?
```

## ParagraphAlignment

```swift
enum ParagraphAlignment
```

```swift
case center
```

```swift
case distributed
```

```swift
case end
```

```swift
init?(rawValue: String)
```

```swift
case justified
```

```swift
case kashidaHigh
```

```swift
case kashidaLow
```

```swift
case kashidaMedium
```

```swift
case left
```

```swift
case numericTab
```

```swift
case right
```

```swift
case start
```

```swift
case thaiDistributed
```

## ParagraphFormatting

```swift
struct ParagraphFormatting
```

```swift
static func == (lhs: ParagraphFormatting, rhs: ParagraphFormatting) -> Bool
```

```swift
var alignment: ParagraphAlignment? { get set }
```

```swift
var autoSpaceEastAsianLatin: Bool? { get set }
```

```swift
var autoSpaceEastAsianNumbers: Bool? { get set }
```

```swift
var contextualSpacing: Bool? { get set }
```

```swift
var firstLineIndent: Double? { get set }
```

```swift
var indentLeft: Double? { get set }
```

```swift
var indentRight: Double? { get set }
```

```swift
init()
```

```swift
var keepTogether: Bool? { get set }
```

```swift
var keepWithNext: Bool? { get set }
```

```swift
var kinsoku: Bool? { get set }
```

```swift
var lineSpacing: Double? { get set }
```

```swift
var lineSpacingRule: LineSpacingRule? { get set }
```

```swift
mutating func merge(_ other: ParagraphFormatting)
```

```swift
var outlineLevel: Int? { get set }
```

```swift
var pageBreakBefore: Bool? { get set }
```

```swift
var rawProperties: [String] { get set }
```

```swift
var rightToLeft: Bool? { get set }
```

```swift
var snapToGrid: Bool? { get set }
```

```swift
var spacingAfter: Double? { get set }
```

```swift
var spacingBefore: Double? { get set }
```

```swift
var suppressAutoHyphens: Bool? { get set }
```

```swift
var tabs: [TabStop]? { get set }
```

```swift
var textDirection: String? { get set }
```

```swift
var widowControl: Bool? { get set }
```

```swift
var wordWrap: Bool? { get set }
```

## ParagraphFormattingChange

```swift
typealias ParagraphFormattingChange = FormattingChange<ParagraphFormatting>
```

## PartReference

```swift
struct PartReference
```

```swift
var externalTarget: String?
```

```swift
init(from decoder: any Decoder) throws
```

```swift
init(relationshipID: String, path: String? = nil, externalTarget: String? = nil)
```

```swift
var path: String?
```

```swift
var relationshipID: String
```

## PathPoint

```swift
struct PathPoint
```

```swift
init(from decoder: any Decoder) throws
```

```swift
init(x: Double, y: Double)
```

```swift
let x: Double
```

```swift
let y: Double
```

## ReadOptions

```swift
struct ReadOptions
```

```swift
enum RevisionView
```

```swift
case all
```

```swift
case final
```

```swift
init?(rawValue: String)
```

```swift
case original
```

```swift
var includeRelatedStories: Bool
```

```swift
init(limits: PackageLimits = .init(), revisions: ReadOptions.RevisionView = .final, includeRelatedStories: Bool = true)
```

```swift
var limits: PackageLimits
```

```swift
var revisions: ReadOptions.RevisionView
```

## ReadResult

```swift
struct ReadResult
```

```swift
var document: Document
```

```swift
init(document: Document)
```

```swift
var warnings: [ReadWarning] { get }
```

## ReadWarning

```swift
struct ReadWarning
```

```swift
enum Code
```

```swift
case incompleteField
```

```swift
init?(rawValue: String)
```

```swift
case invalidReference
```

```swift
case storiesOmitted
```

```swift
case uninterpretedFormatting
```

```swift
case unsupportedContent
```

```swift
case unsupportedPart
```

```swift
var code: ReadWarning.Code
```

```swift
var count: Int
```

```swift
var element: String
```

```swift
init(code: ReadWarning.Code, part: String, element: String, message: String, count: Int = 1)
```

```swift
init(from decoder: any Decoder) throws
```

```swift
var message: String
```

```swift
var part: String
```

## Revision

```swift
struct Revision
```

```swift
enum Kind
```

```swift
case deletion
```

```swift
case formatting
```

```swift
init?(rawValue: String)
```

```swift
case insertion
```

```swift
case moveFrom
```

```swift
case moveTo
```

```swift
var author: String? { get set }
```

```swift
var date: String? { get set }
```

```swift
var id: String { get set }
```

```swift
init(id: String, kind: Revision.Kind, author: String? = nil, date: String? = nil, sourceAttributes: [String : String] = [:])
```

```swift
var kind: Revision.Kind { get set }
```

```swift
var sourceAttributes: [String : String] { get set }
```

## RubyText

```swift
struct RubyText
```

```swift
var alignment: String?
```

```swift
var annotation: [Inline]
```

```swift
var annotationSize: Double?
```

```swift
var base: [Inline]
```

```swift
var baseSize: Double?
```

```swift
init(base: [Inline], annotation: [Inline])
```

```swift
var language: String?
```

```swift
var position: String?
```

```swift
var rawProperties: [String]
```

## ScanResult

```swift
struct ScanResult
```

```swift
var blocksRead: Int
```

```swift
var document: Document
```

```swift
init(document: Document, blocksRead: Int)
```

```swift
var warnings: [ReadWarning] { get }
```

## Section

```swift
struct Section
```

```swift
var breakKind: String? { get set }
```

```swift
var columnCount: Int { get set }
```

```swift
var columnSeparator: Bool? { get set }
```

```swift
var columnSpacing: Double? { get set }
```

```swift
var columns: [SectionColumn] { get set }
```

```swift
var documentGrid: [String : String] { get set }
```

```swift
var equalColumnWidths: Bool? { get set }
```

```swift
var footers: [String : String] { get set }
```

```swift
var hasDifferentFirstPage: Bool { get set }
```

```swift
var headers: [String : String] { get set }
```

```swift
init()
```

```swift
var margins: [String : Double] { get set }
```

```swift
var orientation: PageOrientation? { get set }
```

```swift
var pageHeight: Double? { get set }
```

```swift
var pageWidth: Double? { get set }
```

```swift
var rawProperties: [String] { get set }
```

```swift
var textDirection: String? { get set }
```

## SectionColumn

```swift
struct SectionColumn
```

```swift
init(width: Double? = nil, spacingAfter: Double? = nil)
```

```swift
var spacingAfter: Double?
```

```swift
var width: Double?
```

## SourceXMLNode

```swift
struct SourceXMLNode
```

```swift
enum Content
```

```swift
case element(SourceXMLNode)
```

```swift
init(from decoder: any Decoder) throws
```

```swift
case text(String)
```

```swift
let attributeNames: [String : String]
```

```swift
let attributes: [String : String]
```

```swift
var children: [SourceXMLNode] { get }
```

```swift
let content: [SourceXMLNode.Content]
```

```swift
func descendants(named name: String, namespace: String? = nil) -> [SourceXMLNode]
```

```swift
init(from decoder: any Decoder) throws
```

```swift
let name: String
```

```swift
let namespace: String
```

```swift
let namespaceBindings: [String : String]
```

```swift
let qualifiedName: String
```

```swift
var text: String { get }
```

## SourceXMLReadResult

```swift
struct SourceXMLReadResult
```

```swift
let part: String
```

```swift
let root: SourceXMLNode
```

```swift
let warnings: [ReadWarning]
```

## Story

```swift
struct Story
```

```swift
var author: String?
```

```swift
var blocks: [Block]
```

```swift
var date: String?
```

```swift
var id: String
```

```swift
init(id: String, kind: StoryKind, sourcePart: String, blocks: [Block], author: String? = nil, date: String? = nil, type: String? = nil)
```

```swift
var kind: StoryKind
```

```swift
var plainText: String { get }
```

```swift
var sourcePart: String
```

```swift
var type: String?
```

## StoryKind

```swift
enum StoryKind
```

```swift
case comment
```

```swift
case endnote
```

```swift
case footer
```

```swift
case footnote
```

```swift
case header
```

```swift
init?(rawValue: String)
```

## SymbolCharacter

```swift
struct SymbolCharacter
```

```swift
var characterCode: UInt32
```

```swift
var fontName: String
```

```swift
init(fontName: String, characterCode: UInt32)
```

## TabStop

```swift
struct TabStop
```

```swift
var alignment: String
```

```swift
init(position: Double, alignment: String = "left", leader: String? = nil)
```

```swift
var leader: String?
```

```swift
var position: Double
```

## Table

```swift
struct Table
```

```swift
var alignment: TableAlignment?
```

```swift
var borders: [TableBorderEdge : TableBorder]
```

```swift
var cellMargins: [TableCellEdge : TableWidth]
```

```swift
var cellSpacing: TableWidth?
```

```swift
var columnChange: TableColumnChange?
```

```swift
var columnWidths: [Double] { get set }
```

```swift
var columns: [TableColumn]
```

```swift
var formatting: TableFormatting { get set }
```

```swift
var formattingChange: TableFormattingChange?
```

```swift
var indentation: TableWidth?
```

```swift
init()
```

```swift
var layout: TableLayout?
```

```swift
var plainText: String { get }
```

```swift
var preferredWidth: TableWidth?
```

```swift
var properties: [String]
```

```swift
var rightToLeft: Bool?
```

```swift
var rowControls: [ContentControlRange]
```

```swift
var rows: [TableRow]
```

```swift
var shading: String?
```

```swift
var styleID: String?
```

## TableAlignment

```swift
enum TableAlignment
```

```swift
case center
```

```swift
case end
```

```swift
init?(rawValue: String)
```

```swift
case left
```

```swift
case right
```

```swift
case start
```

## TableBorder

```swift
struct TableBorder
```

```swift
var color: String?
```

```swift
var frame: Bool?
```

```swift
init(style: String, width: Double? = nil, color: String? = nil)
```

```swift
var rawProperties: [String]
```

```swift
var shadow: Bool?
```

```swift
var sourceWidth: String?
```

```swift
var spacing: Double?
```

```swift
var style: String
```

```swift
var themeColor: String?
```

```swift
var themeShade: String?
```

```swift
var themeTint: String?
```

```swift
var width: Double?
```

## TableBorderEdge

```swift
enum TableBorderEdge
```

```swift
case bottom
```

```swift
case diagonalDown
```

```swift
case diagonalUp
```

```swift
case end
```

```swift
init?(rawValue: String)
```

```swift
case insideHorizontal
```

```swift
case insideVertical
```

```swift
case left
```

```swift
case right
```

```swift
case start
```

```swift
case top
```

## TableCell

```swift
struct TableCell
```

```swift
var blocks: [Block]
```

```swift
var borders: [TableBorderEdge : TableBorder]
```

```swift
var columnSpan: Int
```

```swift
var fitText: Bool?
```

```swift
var formatting: TableCellFormatting { get set }
```

```swift
var formattingChange: TableCellFormattingChange?
```

```swift
init()
```

```swift
var isCovered: Bool
```

```swift
var margins: [TableCellEdge : TableWidth]
```

```swift
var mergeChange: CellMergeChange?
```

```swift
var noWrap: Bool?
```

```swift
var plainText: String { get }
```

```swift
var preferredWidth: TableWidth?
```

```swift
var properties: [String]
```

```swift
var revisions: [Revision]
```

```swift
var rowSpan: Int
```

```swift
var shading: String?
```

```swift
var textDirection: String?
```

```swift
var verticalAlignment: String?
```

```swift
var verticalMerge: VerticalMerge?
```

```swift
var width: Double? { get }
```

```swift
var widthUnit: String? { get }
```

## TableCellEdge

```swift
enum TableCellEdge
```

```swift
case bottom
```

```swift
case end
```

```swift
init?(rawValue: String)
```

```swift
case left
```

```swift
case right
```

```swift
case start
```

```swift
case top
```

## TableCellFormatting

```swift
struct TableCellFormatting
```

```swift
var borders: [TableBorderEdge : TableBorder]
```

```swift
var columnSpan: Int
```

```swift
var fitText: Bool?
```

```swift
init()
```

```swift
var isCovered: Bool
```

```swift
var margins: [TableCellEdge : TableWidth]
```

```swift
var noWrap: Bool?
```

```swift
var preferredWidth: TableWidth?
```

```swift
var rawProperties: [String]
```

```swift
var rowSpan: Int
```

```swift
var shading: String?
```

```swift
var textDirection: String?
```

```swift
var verticalAlignment: String?
```

```swift
var verticalMerge: VerticalMerge?
```

## TableCellFormattingChange

```swift
typealias TableCellFormattingChange = FormattingChange<TableCellFormatting>
```

## TableColumn

```swift
struct TableColumn
```

```swift
init(width: Double? = nil, sourceWidth: String? = nil)
```

```swift
var rawProperties: [String]
```

```swift
var sourceWidth: String?
```

```swift
var width: Double?
```

## TableColumnChange

```swift
typealias TableColumnChange = FormattingChange<[TableColumn]>
```

## TableFormatting

```swift
struct TableFormatting
```

```swift
var alignment: TableAlignment?
```

```swift
var borders: [TableBorderEdge : TableBorder]
```

```swift
var cellMargins: [TableCellEdge : TableWidth]
```

```swift
var cellSpacing: TableWidth?
```

```swift
var indentation: TableWidth?
```

```swift
init()
```

```swift
var layout: TableLayout?
```

```swift
var preferredWidth: TableWidth?
```

```swift
var rawProperties: [String]
```

```swift
var rightToLeft: Bool?
```

```swift
var shading: String?
```

```swift
var styleID: String?
```

## TableFormattingChange

```swift
typealias TableFormattingChange = FormattingChange<TableFormatting>
```

## TableLayout

```swift
enum TableLayout
```

```swift
case automatic
```

```swift
case fixed
```

```swift
init?(rawValue: String)
```

## TableRow

```swift
struct TableRow
```

```swift
var cellControls: [ContentControlRange]
```

```swift
var cells: [TableCell]
```

```swift
var formatting: TableRowFormatting { get set }
```

```swift
var formattingChange: TableRowFormattingChange?
```

```swift
var height: Double?
```

```swift
var heightRule: TableRowHeightRule?
```

```swift
init()
```

```swift
var isHeader: Bool
```

```swift
var leadingWidth: TableWidth?
```

```swift
var omittedLeadingColumns: Int
```

```swift
var omittedTrailingColumns: Int
```

```swift
var preventSplit: Bool?
```

```swift
var properties: [String]
```

```swift
var revisions: [Revision]
```

```swift
var tableOverrides: TableFormatting?
```

```swift
var tableOverridesChange: TableFormattingChange?
```

```swift
var trailingWidth: TableWidth?
```

## TableRowFormatting

```swift
struct TableRowFormatting
```

```swift
var height: Double?
```

```swift
var heightRule: TableRowHeightRule?
```

```swift
init()
```

```swift
var isHeader: Bool
```

```swift
var leadingWidth: TableWidth?
```

```swift
var omittedLeadingColumns: Int
```

```swift
var omittedTrailingColumns: Int
```

```swift
var preventSplit: Bool?
```

```swift
var rawProperties: [String]
```

```swift
var trailingWidth: TableWidth?
```

## TableRowFormattingChange

```swift
typealias TableRowFormattingChange = FormattingChange<TableRowFormatting>
```

## TableRowHeightRule

```swift
enum TableRowHeightRule
```

```swift
case automatic
```

```swift
case exact
```

```swift
init?(rawValue: String)
```

```swift
case minimum
```

## TableStyleRegion

```swift
enum TableStyleRegion
```

```swift
case bottomLeft
```

```swift
case bottomRight
```

```swift
case evenColumnBand
```

```swift
case evenRowBand
```

```swift
case firstColumn
```

```swift
case firstRow
```

```swift
init?(rawValue: String)
```

```swift
case lastColumn
```

```swift
case lastRow
```

```swift
case oddColumnBand
```

```swift
case oddRowBand
```

```swift
case topLeft
```

```swift
case topRight
```

```swift
case wholeTable
```

## TableStyleRule

```swift
struct TableStyleRule
```

```swift
var cell: TableCellFormatting
```

```swift
init(region: TableStyleRegion)
```

```swift
var paragraph: ParagraphFormatting
```

```swift
var region: TableStyleRegion
```

```swift
var row: TableRowFormatting
```

```swift
var source: SourceXMLNode?
```

```swift
var table: TableFormatting
```

```swift
var text: TextFormatting
```

## TableWidth

```swift
struct TableWidth
```

```swift
enum Unit
```

```swift
case automatic
```

```swift
init?(rawValue: String)
```

```swift
case native
```

```swift
case none
```

```swift
case percent
```

```swift
case points
```

```swift
init(value: Double? = nil, unit: TableWidth.Unit = .points, sourceValue: String? = nil, sourceUnit: String? = nil)
```

```swift
var sourceUnit: String?
```

```swift
var sourceValue: String?
```

```swift
var unit: TableWidth.Unit
```

```swift
var value: Double?
```

## TextFormatting

```swift
struct TextFormatting
```

```swift
static func == (lhs: TextFormatting, rhs: TextFormatting) -> Bool
```

```swift
var allCaps: Bool? { get set }
```

```swift
var bold: Bool? { get set }
```

```swift
var boldComplexScript: Bool? { get set }
```

```swift
var characterSpacing: Double? { get set }
```

```swift
var color: String? { get set }
```

```swift
var emphasis: String? { get set }
```

```swift
var fontHint: String? { get set }
```

```swift
var fontName: String? { get set }
```

```swift
var fontNameComplexScript: String? { get set }
```

```swift
var fontNameEastAsia: String? { get set }
```

```swift
var fontSize: Double? { get set }
```

```swift
var fontSizeComplexScript: Double? { get set }
```

```swift
var fontTheme: String? { get set }
```

```swift
var fontThemeComplexScript: String? { get set }
```

```swift
var fontThemeEastAsia: String? { get set }
```

```swift
var hidden: Bool? { get set }
```

```swift
var highlight: String? { get set }
```

```swift
init()
```

```swift
var italic: Bool? { get set }
```

```swift
var italicComplexScript: Bool? { get set }
```

```swift
var kerning: Double? { get set }
```

```swift
var language: String? { get set }
```

```swift
var languageComplexScript: String? { get set }
```

```swift
var languageEastAsia: String? { get set }
```

```swift
mutating func merge(_ other: TextFormatting, toggling: Bool = false)
```

```swift
var position: Double? { get set }
```

```swift
var rawProperties: [String] { get set }
```

```swift
var rightToLeft: Bool? { get set }
```

```swift
var smallCaps: Bool? { get set }
```

```swift
var strike: Bool? { get set }
```

```swift
var textScale: Double? { get set }
```

```swift
var themeColor: String? { get set }
```

```swift
var themeShade: String? { get set }
```

```swift
var themeTint: String? { get set }
```

```swift
var underline: String? { get set }
```

```swift
var verticalAlignment: TextVerticalAlignment? { get set }
```

## TextFormattingChange

```swift
typealias TextFormattingChange = FormattingChange<TextFormatting>
```

## TextRun

```swift
struct TextRun
```

```swift
var formatting: TextFormatting
```

```swift
var formattingChange: TextFormattingChange?
```

```swift
init(_ text: String, formatting: TextFormatting = .init(), styleID: String? = nil, revision: Revision? = nil)
```

```swift
var revision: Revision?
```

```swift
var styleID: String?
```

```swift
var symbol: SymbolCharacter?
```

```swift
var text: String
```

## TextVerticalAlignment

```swift
enum TextVerticalAlignment
```

```swift
case baseline
```

```swift
init?(rawValue: String)
```

```swift
case `subscript`
```

```swift
case superscript
```

## UnsupportedContent

```swift
struct UnsupportedContent
```

```swift
init(name: String, sourcePart: String, rawXML: String, text: String = "")
```

```swift
var name: String
```

```swift
var rawXML: String
```

```swift
var sourcePart: String
```

```swift
var text: String
```

## VerticalMerge

```swift
enum VerticalMerge
```

```swift
case continuation
```

```swift
init?(rawValue: String)
```

```swift
case restart
```
