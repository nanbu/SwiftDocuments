# ReadDocument example

Compile and run against a local Word document from the repository root:

```sh
swift run --package-path Examples/ReadDocument ReadDocument sample.docx
swift run --package-path Examples/ReadDocument ReadDocument --scan sample.docx
```

The example uses the public umbrella product. It reads revisions, source symbols,
drawings, equations, chart caches, ruby, lazy images and original XML. It prints
warnings and does not perform font substitution, layout, rendering or external
resource fetching. The input is never modified.
