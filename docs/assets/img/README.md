# Illustrations

Four images, used in `README.md` and on the documentation site. They are
**decorative**. Every one of them illustrates a point that is also stated in
prose, a table or a Mermaid diagram on the same page, and none of them is the
only place a fact appears.

That rule is not politeness about accessibility, though it covers that too. It
is a consequence of how they were made.

## Provenance

Generated with OpenAI `gpt-image-2` from written prompts, then resized to
1200px on the long edge and re-encoded as JPEG at quality 88 with `sips`. The
prompts share one style string so the set reads as a set, and every prompt ends
with an explicit instruction to render no text, no words, no letters and no
numbers.

That last instruction is the reason for the decorative rule. A generative image
model cannot be relied on to render a label correctly, and a diagram whose
labels are approximately right is worse than no diagram — it looks
authoritative and says something slightly false. So anything precise —
permission tiers, gateway routes, what is proved and what is not — is written
as Markdown or as Mermaid, which GitHub renders natively and which a screen
reader, a diff and a text search can all read.

| File | Illustrates | Where the same point is made in text |
|---|---|---|
| `hero-on-rails.jpg` | Unconstrained work versus work on rails, arriving somewhere | `README.md`, opening section |
| `governed-gateway.jpg` | Many clients, one governed route, one ledger, one refusal | `README.md`, "One route" — and the table under it |
| `permission-tiers.jpg` | Three tiers: automatic, ask, never — the outer band unbroken | `README.md`, the permission-tier table |
| `evidence-not-promises.jpg` | A sealed claim among unsealed ones, traced to a command | `README.md`, "Evidence, not adjectives" |

## Alt text

Each image carries alt text describing what a reader who cannot see it would
otherwise miss — which, given the rule above, is the composition and not the
content. Do not put load-bearing information into alt text either: if it
matters, it belongs in the body.

## Replacing these

If you fork this pack for your own organisation, replace them. They carry no
Databricks branding and are not trying to; they are placeholders with a
consistent palette. Keep the decorative rule when you do, and keep a note like
this one saying how the replacements were made.
