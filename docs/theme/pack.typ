// pack.typ — the pandoc typst template for every PDF in this pack.
//
// One theme for the whole pack, on purpose. A folder of documents that each look
// slightly different reads as a folder of files rather than as a pack.
//
// Fonts are restricted to the four that typst bundles - Libertinus Serif,
// New Computer Modern, New Computer Modern Math, DejaVu Sans Mono - and the build
// passes --ignore-system-fonts. That is what makes a PDF built on a laptop
// byte-identical to one built in CI: a theme that reaches for a system font
// produces a different artifact on every machine, and then the digest printed by
// the build describes when it ran rather than what it built.
//
// Rendered by: scripts/build-docs.py (make docs)

$if(highlighting-definitions)$
$highlighting-definitions$

$endif$
// ---------------------------------------------------------------- palette ----
#let ink = rgb("#101418")
#let muted = rgb("#5a6572")
#let hair = rgb("#d6dae0")
#let wash = rgb("#f5f7f9")
#let accent = rgb("#1b3a57")
#let flag = rgb("#8a4b08")

#let statusband(status) = {
  if status == none or status == "" { return none }
  box(
    fill: if lower(status) == "release-ready" { rgb("#e8f1e8") } else { rgb("#fdf2e4") },
    stroke: 0.5pt + if lower(status) == "release-ready" { rgb("#4a7a4a") } else { flag },
    inset: (x: 6pt, y: 3pt),
    radius: 2pt,
    text(7.5pt, weight: "semibold", tracking: 0.4pt,
      fill: if lower(status) == "release-ready" { rgb("#2f5d2f") } else { flag },
      upper(status)),
  )
}

// ------------------------------------------------------------------ page -----
#set document(
  title: "$title$",
$if(author)$
  author: ($for(author)$"$author$"$sep$, $endfor$),
$endif$
)

#set page(
  paper: "a4",
  margin: (top: 26mm, bottom: 24mm, left: 24mm, right: 24mm),
  header: context {
    // No running header on the cover: it competes with the title.
    if counter(page).get().first() > 1 {
      set text(8pt, fill: muted)
      grid(
        columns: (1fr, auto),
        align: (left, right),
        emph[$title$],
        [$if(docid)$$docid$$endif$],
      )
      v(-6pt)
      line(length: 100%, stroke: 0.4pt + hair)
    }
  },
  footer: context {
    set text(8pt, fill: muted)
    line(length: 100%, stroke: 0.4pt + hair)
    v(-2pt)
    grid(
      columns: (1fr, auto, 1fr),
      align: (left, center, right),
      [$if(packversion)$$packversion$$endif$],
      counter(page).display("1 of 1", both: true),
      [$if(status)$#text(fill: flag, weight: "semibold")[$status$]$endif$],
    )
  },
)

#set text(font: ("Libertinus Serif",), size: 10.5pt, fill: ink, lang: "en")
#set par(justify: true, leading: 0.68em, spacing: 1.1em, first-line-indent: 0pt)
#show link: it => text(fill: accent, underline(offset: 1.5pt, stroke: 0.4pt + hair, it))
#set underline(evade: true)

// -------------------------------------------------------------- headings -----
#set heading(numbering: "1.1")
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  block(above: 0pt, below: 14pt)[
    #set text(17pt, weight: "bold", fill: accent)
    #block(below: 5pt)[
      #if it.numbering != none [
        #text(fill: muted)[#counter(heading).display(it.numbering)]
        #h(8pt)
      ]
      #it.body
    ]
    #line(length: 100%, stroke: 0.8pt + accent)
  ]
}
#show heading.where(level: 2): it => block(above: 18pt, below: 8pt)[
  #set text(12.5pt, weight: "bold", fill: ink)
  #it
]
#show heading.where(level: 3): it => block(above: 14pt, below: 6pt)[
  #set text(10.8pt, weight: "semibold", fill: ink)
  #it
]
#show heading.where(level: 4): it => block(above: 13pt, below: 6pt)[
  #set text(10.5pt, weight: "semibold", style: "italic", fill: muted)
  #it
]

// ------------------------------------------------------------------ code -----
#show raw.where(block: false): it => box(
  fill: wash, stroke: 0.4pt + hair, inset: (x: 3pt, y: 1pt), outset: (y: 2.5pt), radius: 2pt,
  text(font: ("DejaVu Sans Mono",), size: 8.8pt, it),
)
#show raw.where(block: true): it => block(
  width: 100%, fill: wash, stroke: (left: 2pt + accent, rest: 0.4pt + hair),
  inset: (x: 9pt, y: 8pt), radius: (right: 2pt), breakable: true,
  text(font: ("DejaVu Sans Mono",), size: 8.5pt, it),
)

// ----------------------------------------------------------------- table -----
#set table(
  inset: 6pt,
  stroke: (x, y) => (
    top: if y == 0 { 0.8pt + accent } else if y == 1 { 0.5pt + accent } else { 0.35pt + hair },
    bottom: 0.35pt + hair,
  ),
  fill: (x, y) => if y == 0 { wash } else { none },
)
#show table.cell.where(y: 0): set text(weight: "semibold", size: 9.3pt)
// A show-set rule, not `it => align(left + top, it)`. Both produce left-and-top
// cells, but the element form is undone by the figure rule further down, which
// strips align elements inside figures. A style survives it.
#show table.cell: set align(left + top)
#show table: set text(size: 9.3pt)
// Justification inside a narrow cell produces rivers and a ragged centre. Prose
// in a decision table is the common case here, so cells are set ragged-right.
#show table: set par(justify: false, leading: 0.6em)
#show figure.where(kind: table): set figure.caption(position: top)
// Pandoc wraps every table in a figure whether or not it has a caption, and a
// figure takes a number even when nothing displays it. Left alone, the first
// captioned table in a document is announced as "Table 3". Only number the ones
// that are actually labelled.
#show figure.where(caption: none): set figure(numbering: none)
#show figure.caption: it => text(size: 8.8pt, fill: muted, it)
// Getting a captioned table to sit at the left margin takes both halves of this
// rule, and the reason is worth writing down because the symptom is invisible
// until a table has a long caption.
//
// Pandoc emits `#figure(align(center)[#table(..)], caption: [..])`. A figure is as
// wide as its widest part, so a one-line caption leaves the table nothing to be
// centred within and the table looks correctly placed; a caption that wraps makes
// the figure full width and the same table slides to the middle of the page. So:
//   * `set align(left)` places the figure's own content and its caption, and
//   * `show align: a => a.body` removes pandoc's centring wrapper inside it.
// Neither alone is enough. Note also that `align.where(alignment: center)` matches
// nothing in typst 0.15 — a `where` selector on that field silently never fires,
// which is why the rule is unscoped and confined to figures instead.
#show figure: it => {
  set align(left)
  show align: a => a.body
  it
}

// ------------------------------------------------------------- callouts ------
// A blockquote is the pack's one callout. Markdown has no callout syntax and
// inventing one would break every other renderer the source has to survive.
#show quote.where(block: true): it => block(
  width: 100%, fill: rgb("#fbfcfd"), stroke: (left: 2.5pt + flag, rest: 0.35pt + hair),
  inset: (x: 10pt, y: 9pt), radius: (right: 2pt), breakable: true, it.body,
)
#show terms: set par(justify: false)
#set terms(hanging-indent: 1.2em, separator: [ #h(0.4em) ])
#set list(indent: 0.6em, spacing: 0.72em, marker: ([•], [–], [·]))
#set enum(indent: 0.6em, spacing: 0.72em)
// Centred by explicit endpoints rather than by `align(center, line(..))`: a line
// carries no width for the aligner to work with, so the wrapped version silently
// renders flush left.
#let horizontalRule = block(above: 14pt, below: 14pt, width: 100%,
  line(start: (34%, 0%), end: (66%, 0%), stroke: 0.5pt + hair))
// Defined as a function because pandoc emits `#divider()`, not `#divider`.
#let divider() = horizontalRule

$if(smart)$
$else$
#set smartquote(enabled: false)
$endif$
$for(header-includes)$
$header-includes$
$endfor$

// ----------------------------------------------------------------- cover -----
#block(above: 0pt, below: 0pt)[
  #set text(8.5pt, fill: muted, tracking: 0.6pt)
  #upper[Databricks Agentic Engineering Rails]
  #h(1fr)
  $if(docid)$#upper[$docid$]$endif$
]
#v(2pt)
#line(length: 100%, stroke: 0.8pt + accent)
#v(30pt)

#block[
  #set par(justify: false, leading: 0.5em)
  #text(24pt, weight: "bold", fill: accent)[$title$]
$if(subtitle)$
  #v(8pt)
  #text(13pt, fill: muted, style: "italic")[$subtitle$]
$endif$
]

#v(18pt)
#grid(
  columns: (auto, 1fr),
  gutter: 8pt,
  align: (left, left),
$if(status)$
  text(8.5pt, fill: muted)[Status], statusband("$status$"),
$endif$
$if(packversion)$
  text(8.5pt, fill: muted)[Pack version], text(9pt)[$packversion$],
$endif$
$if(date)$
  text(8.5pt, fill: muted)[Built], text(9pt)[$date$],
$endif$
$if(commit)$
  text(8.5pt, fill: muted)[Revision], text(8.5pt, font: ("DejaVu Sans Mono",))[$commit$],
$endif$
)

$if(status)$
#v(14pt)
#block(
  width: 100%, fill: rgb("#fdf6ec"), stroke: 0.4pt + flag, inset: 9pt, radius: 2pt,
)[
  #set text(8.5pt)
  *Read the status.* This document carries the status shown above. A #smallcaps[preview]
  is honestly incomplete, and each document says which of its claims were exercised
  and which were only read. Nothing in this pack is official Databricks
  documentation; see `DISCLAIMER.md`.
]
$endif$

$if(abstract)$
#v(14pt)
#block(width: 100%, inset: (left: 0pt))[
  #text(9pt, weight: "semibold", fill: muted)[$if(abstract-title)$$abstract-title$$else$Summary$endif$]
  #v(3pt)
  #set text(9.6pt)
  $abstract$
]
$endif$

$if(toc)$
#v(20pt)
#block[
  #text(11pt, weight: "bold", fill: accent)[Contents]
  #v(4pt)
  #line(length: 100%, stroke: 0.5pt + hair)
  #v(6pt)
  #set text(9.5pt)
  #show outline.entry.where(level: 1): it => {
    v(5pt, weak: true)
    strong(it)
  }
  #outline(title: none, depth: $if(toc-depth)$$toc-depth$$else$3$endif$, indent: 1.2em)
]
$endif$

$for(include-before)$
$include-before$
$endfor$

$body$

$for(include-after)$
$include-after$
$endfor$
