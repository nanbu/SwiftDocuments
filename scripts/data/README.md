# Pinned geometry reference data

`presetShapeDefinitions.xml` is pinned from the Apache POI project (Apache
License 2.0, `APACHE-LICENSE.txt`). It contains 187 OOXML preset shape path
definitions. `generate-preset-geometries.py` converts only guide/path data to
the bundled JSON; rendering does not parse this reference XML or fetch a URL.
Source: [Apache POI preset shape definitions](https://github.com/apache/poi/blob/trunk/poi/src/main/resources/org/apache/poi/sl/draw/geom/presetShapeDefinitions.xml).
The raw reference is unchanged. Eight circular-arrow equations contain an
extra fourth operand equal to zero after `+-`; the generator removes that
trailing zero, retaining the intended `x + y - z` expression. The evaluator
continues to reject unknown operations, over-arity, cycles and division by zero.
Several reference formulas reuse temporary names. Generation converts those
declaration-order assignments to unique temporary names and rewrites dependent
formulas/path references. Source documents and their own guide names are not
rewritten. The public evaluator still rejects duplicate source guide declarations.
