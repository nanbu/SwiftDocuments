#!/usr/bin/env python3
"""Generate format-neutral preset geometry data from a pinned OOXML reference; no runtime XML parse."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'scripts/data/presetShapeDefinitions.xml'
TARGET = ROOT / 'Sources/DocumentDOCX/Resources/preset-geometries.json'
def local(n): return n.tag.split('}')[-1]
def child(n, name): return next((x for x in n if local(x) == name), None)
def guides(n, name):
    values = child(n, name)
    result = []
    for x in [] if values is None else values:
        formula = x.get('fmla')
        fields = formula.split()
        # Eight circular-arrow equations in the pinned POI reference carry an extra trailing zero.
        # Keep the source untouched; normalize only these documented over-arity identities.
        if local(n) in ('circularArrow','leftCircularArrow','leftRightCircularArrow') and len(fields) == 5 and fields[0] == '+-' and fields[-1] == '0':
            formula = ' '.join(fields[:-1])
        result.append({'name': x.get('name'), 'formula': formula})
    return result
def generate():
    result = {}
    for shape in E.parse(SOURCE).getroot():
        adjustments = guides(shape,'avLst')
        source_guides = guides(shape,'gdLst')
        # The reference reuses temporary variable names. Convert declaration-order assignments
        # to unique names so the public evaluator can remain strict about duplicate source guides.
        bindings = {g['name']:g['name'] for g in adjustments}
        occurrences = {g['name']:1 for g in adjustments}
        normalized_guides = []
        for guide in source_guides:
            fields = guide['formula'].split()
            formula = ' '.join([fields[0]] + [bindings.get(v,v) for v in fields[1:]])
            name = guide['name']; count = occurrences.get(name,0)+1; occurrences[name] = count
            normalized = name if count == 1 else name+'__'+str(count)
            bindings[name] = normalized
            normalized_guides.append({'name':normalized,'formula':formula})
        paths = []
        source = child(shape, 'pathLst')
        for path in [] if source is None else source:
            commands = []
            for command in path:
                name = local(command)
                args = [command.get(k, '0') for k in ('wR','hR','stAng','swAng')] if name == 'arcTo' else [v for p in command for v in (p.get('x','0'),p.get('y','0'))]
                commands.append({'name': name, 'arguments': [bindings.get(a,a) for a in args]})
            paths.append({'width': float(path.get('w')) if path.get('w') else None, 'height': float(path.get('h')) if path.get('h') else None,
                          'fill': path.get('fill'), 'stroke': path.get('stroke') not in ('0','false'),
                          'extrusionOK': None if path.get('extrusionOk') is None else path.get('extrusionOk') not in ('0','false'), 'commands': commands})
        result[local(shape)] = {'adjustments': adjustments, 'guides': normalized_guides, 'paths': paths}
    assert len(result) == 187 and all(x['paths'] for x in result.values()), 'incomplete preset reference'
    return json.dumps(result, sort_keys=True, separators=(',',':'))+'\n'
if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--check',action='store_true'); args=parser.parse_args()
    content=generate()
    if args.check:
        if not TARGET.exists() or TARGET.read_text() != content: raise SystemExit('Generated preset geometries are stale')
        print('187 preset geometries match pinned reference')
    else: TARGET.write_text(content)
