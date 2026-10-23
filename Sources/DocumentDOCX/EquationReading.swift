import Foundation
import DocumentCore

private let mathNamespaces: Set<String> = [
    "http://schemas.openxmlformats.org/officeDocument/2006/math",
    "http://purl.oclc.org/ooxml/officeDocument/math"
]

func isMathNamespace(_ namespace: String) -> Bool { mathNamespaces.contains(namespace) }

func isEquation(_ node: MarkupNode) -> Bool {
    mathNamespaces.contains(node.namespace) && ["oMath", "oMathPara"].contains(node.name)
}

extension StoryReader {
    func equation(_ source: MarkupNode) throws -> Equation {
        let kinds: [String: EquationNode.Kind] = [
            "oMath": .math, "oMathPara": .paragraph, "r": .run, "t": .text,
            "f": .fraction, "num": .numerator, "den": .denominator, "rad": .radical, "deg": .degree, "e": .base,
            "sSup": .superscript, "sSub": .subscriptExpression, "sSubSup": .subSuperscript,
            "sPre": .preSubSuperscript, "sub": .subscriptArgument, "sup": .superscriptArgument,
            "nary": .nary, "d": .delimiter, "m": .matrix, "mr": .matrixRow, "eqArr": .equationArray,
            "func": .function, "fName": .functionName, "acc": .accent, "bar": .bar, "groupChr": .groupCharacter,
            "limLow": .lowerLimit, "limUpp": .upperLimit, "lim": .limit, "box": .box,
            "borderBox": .borderBox, "phant": .phantom
        ]
        let required: [String: [String]] = [
            "f": ["num", "den"], "rad": ["deg", "e"], "sSup": ["e", "sup"], "sSub": ["e", "sub"],
            "sSubSup": ["e", "sub", "sup"], "sPre": ["sub", "sup", "e"], "nary": ["sub", "sup", "e"],
            "func": ["fName", "e"], "limLow": ["e", "lim"], "limUpp": ["e", "lim"],
            "acc": ["e"], "bar": ["e"], "groupChr": ["e"], "box": ["e"], "borderBox": ["e"], "phant": ["e"]
        ]
        let propertyContainers: Set<String> = [
            "oMathParaPr", "rPr", "ctrlPr", "fPr", "radPr", "sSupPr", "sSubPr", "sSubSupPr", "sPrePr",
            "naryPr", "dPr", "mPr", "eqArrPr", "funcPr", "accPr", "barPr", "groupChrPr", "limLowPr", "limUppPr",
            "boxPr", "borderBoxPr", "phantPr", "mcs", "mc", "mcPr"
        ]
        let propertyNames: Set<String> = [
            "jc", "type", "chr", "degHide", "grow", "limLoc", "subHide", "supHide", "begChr", "endChr", "sepChr",
            "shp", "baseJc", "count", "mcJc", "cGp", "cGpRule", "cSp", "rSp", "rSpRule", "plcHide", "pos", "vertJc",
            "sty", "scr", "nor", "lit", "brk", "aln", "diff", "noBreak", "opEmu", "hideBot", "hideTop", "hideLeft",
            "hideRight", "strikeBLTR", "strikeH", "strikeTLBR", "strikeV", "show", "transp", "zeroAsc", "zeroDesc", "zeroWid"
        ]
        func project(_ node: MarkupNode, property: Bool = false) throws -> EquationNode {
            try Task.checkCancellation()
            let isMath = mathNamespaces.contains(node.namespace)
            let isProperties = isMath && propertyContainers.contains(node.name)
            let kind = isMath ? kinds[node.name] ?? (isProperties ? .properties : property && propertyNames.contains(node.name) ? .property : .native) : .native
            if isMath, let arguments = required[node.name] {
                for argument in arguments {
                    guard node.children.filter({ mathNamespaces.contains($0.namespace) && $0.name == argument }).count == 1 else {
                        throw DocumentError.invalidXML(part: part, detail: "missing / duplicate equation argument \(node.name)/\(argument)")
                    }
                }
            }
            if kind == .native {
                warnings.add(.unsupportedContent, part: part, element: "{\(node.namespace)}\(node.name)", message: "Uninterpreted equation node retained in the source subtree.")
            }
            return EquationNode(kind: kind, name: node.name, namespace: node.namespace, attributes: node.attributes,
                                text: kind == .text ? node.text : nil,
                                children: try node.children.map { try project($0, property: isProperties) })
        }
        // Only the small equation subtree receives a complete source snapshot.
        // Original part bytes/prefixes remain available through the document's source APIs.
        return try Equation(root: project(source), source: SourceXMLNode(source), part: part)
    }
}
