# 0003 — pandoc + typst, bundled fonts, stable rebuilds

**Status:** accepted
**Date:** 2026-09-15

## Context

The pack ships PDFs, and three of them — the digest, the field guide and the
reference card — are meant to be forwarded on their own to people who will never
see this repository. That imposes requirements a casual Markdown-to-PDF pipeline
does not meet: a cover carrying version, build date and revision so a recipient
can date the copy in their hand; real heading structure and bookmarks; selectable
text; and output that can be checked rather than trusted.

The checkable part is the constraint that shaped the choice. If the same source
revision produces different bytes on every build, then a published checksum
proves nothing, and "the PDF attached to the release is the one built from this
commit" becomes an assertion instead of a verification.

## Decision

**pandoc 3.11 driving typst 0.15.1**, with the template at `docs/theme/pack.typ`.
Versions are recorded in `template-version.yml`, and `make docs` warns when the
local toolchain differs from what the release was built with.

**Fonts are restricted to the four typst bundles** — Libertinus Serif, New
Computer Modern, New Computer Modern Math, DejaVu Sans Mono — and the build passes
`--ignore-system-fonts`. This is the single decision that makes reproducibility
achievable: a theme that reaches for a system font produces a different PDF on
every machine, and the failure is silent because the renderer substitutes
something plausible. Their licences are recorded in `NOTICE`, verified against
upstream, because the subsets are embedded in a distributed artifact.

**Dates come from `SOURCE_DATE_EPOCH`, derived from the commit timestamp**, not
from the wall clock. A document rebuilt six months later has not changed and must
not claim to have.

**The build fails on overflow.** `scripts/build-docs.py` measures every glyph's
distance past the right text edge with `pdftotext -bbox` and fails past 4pt. The
tolerance is not zero because justified text with hyphenation lets a hyphen hang
into the margin — the worst case observed in this pack is 1.95pt — and it is not
larger because real overflow is not subtle. The worst overhang per document is
printed in the build summary, so a reader can see how close it came rather than
only whether it passed.

**`build-docs.py --check-reproducible` states which of two standards was met.** Byte-identical is
the strong one and is what this toolchain currently achieves. If a future
renderer version cannot, the build falls back to a declared equivalence check —
identical extracted text and per-word bounding boxes, hence identical page count,
line breaking and glyph positions — and says so in as many words, rather than
quietly relaxing the requirement.

**The combined pack PDF is one pandoc invocation over every source**, not
finished PDFs stitched together, so it carries a single continuous table of
contents and one bookmark tree.

## Consequences

- The theme cannot use a brand typeface. Every document in the pack is set in
  Libertinus Serif with DejaVu Sans Mono for code, and that is not negotiable
  without giving up reproducibility.
- Anyone changing `pack.typ` must look at the rendered PDF. The theme's defects
  found during this build were all invisible to exit codes: a rule rendering
  flush left because a `line` carries no width for an aligner to work with, the
  first captioned table announcing itself as "Table 3" because pandoc wraps every
  table in a figure, and a captioned table drifting to the page centre because a
  figure is as wide as its widest part. Build the combined PDF and look at it; the
  overflow check catches width, not taste.
- `pdftotext` and `pdfinfo` (poppler) become build dependencies of the *checks*,
  not of the documents. `make docs` still produces PDFs without them; the
  overflow check reports that it could not run.
- The overflow check reads text bounding boxes, so it catches an unwrapped code
  line or an over-wide table — both carry glyphs — and not a rule or an image
  that overhangs with nothing in it. That limit is stated here rather than left
  for the check to imply a guarantee it cannot make.

## Rejected alternatives

**LaTeX via pandoc.** The obvious default, and it would meet the typographic
requirements. Rejected on the size and reproducibility of the dependency: a
TeX distribution is gigabytes, its font handling reaches into the system by
default, and pinning it well enough for byte-identical output across machines is
substantially more work than pinning a single 30MB binary.

**A headless browser printing HTML.** Rejected because the renderer is a moving
target with no meaningful version pin, PDF metadata and object ordering vary
between patch releases, and bookmark structure depends on browser-specific
behaviour.

**Accept non-reproducible output and publish checksums anyway.** Rejected because
a checksum nobody can independently reproduce documents what was uploaded, not
what was built, and the pack's argument is that a verification you cannot repeat
is a claim.

**Stitch the combined PDF with `pdfunite`.** Rejected because it concatenates
pages and leaves a flat, discontinuous outline. The combined PDF is the one a
reader is most likely to navigate rather than read straight through, so its table
of contents is the point of it.

## Revisit when

typst's PDF output stops being byte-reproducible under a pinned version — at
which point `build-docs.py --check-reproducible` will say so on its own — or a document needs a
script the bundled fonts do not cover, which would force either a fifth font with
its licence recorded or a different renderer.
