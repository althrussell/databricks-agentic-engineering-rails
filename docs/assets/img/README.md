# Illustrations

Four images, used in `README.md` and on the documentation site. They are
**decorative**. Every one of them illustrates a point that is also stated in
prose, a table or a Mermaid diagram on the same page, and none of them is the
only place a fact appears.

That rule is not politeness about accessibility, though it covers that too. It
is a consequence of how they were made, and the two findings below are why it is
written down rather than assumed.

## Provenance

Generated with OpenAI `gpt-image-2` from written prompts at 1536x1024, then
resized to 1400px on the long edge and re-encoded as JPEG at quality 90 with
`sips`. All four share one style string, so the set reads as a set.

The style is photorealistic 3D editorial rendering rather than flat vector:
physically based materials (matte ceramic, smoked and frosted glass with real
refraction, brushed anodised aluminium, polished lacquer), one large soft studio
key with cool fill and specular rim light, believable contact shadows and
ambient occlusion, and shallow depth of field with the focal element sharp. A
first attempt in flat minimal vector was discarded — at this size and detail
density it read as clip art, which undermines a document arguing for production
standards.

## Palette

The prompts name exact hex values taken from the public Databricks brand
properties, so the set sits alongside Databricks material without imitating it:

| Role | Value |
| :--- | :--- |
| Primary accent — lava red | `#FF3621`, with tints `#FF5F46` and `#FF9E94` |
| Primary dark — navy | `#1B3139` and `#143D4A` |
| Cool navy greys | `#5A6F77`, `#90A5B1`, `#DCE0E2` |
| Ground — oat | `#F9F7F4` shading to `#EEEDE9` |
| Single permitted accent | `#00A972` |

Read from the stylesheets of the public brand site,
<https://brand.databricks.com/>, on 2026-09-16. These are colours, not assets:
no logo, wordmark, typeface or brand asset is used anywhere here, and
`DISCLAIMER.md` states that this pack is not a Databricks product.

The prompts name these values; the renders approximate them. A hinged gate in
`permission-tiers.jpg` reads brass rather than oat under warm key light, and the
ground in `evidence-not-promises.jpg` is a cooler grey than the oat elsewhere in
the set. Both were accepted. Naming hexes moves a render close enough to belong
to a set, and no closer — if you need exact brand colour, composite it yourself
rather than asking for it.

## Two findings worth keeping

**A generative model cannot be trusted with a label.** Every prompt ends with an
explicit instruction to render no text, no words, no letters and no numbers,
because an approximately-correct label is worse than none — it looks
authoritative and says something slightly false. So anything precise — the
permission tiers, the gateway routes, what is proved and what is not — is
written as Markdown or as Mermaid, which GitHub renders natively and which a
screen reader, a diff and a text search can all read. That is the decorative
rule, and it is a constraint of the tool rather than a stylistic preference.

**It cannot be trusted with the absence of a logo either.** The prompt for
`evidence-not-promises.jpg` forbade logos. The first render put a stacked-layer
emblem into the wax seal that read unmistakably as the Databricks logo — on a
seal of authenticity, on an artifact whose disclaimer says it is not a
Databricks product. It was regenerated with the seal's pattern constrained to
concentric rings and radial ticks and an explicitly blank centre. **Look at what
came back, every time, specifically for marks nobody asked for.** A prohibition
in a prompt is a preference, not a guarantee.

Two earlier renders of `permission-tiers.jpg` were discarded as well. The first
read as a frying pan: a long straight navy rail beside a shallow round dish
became a handle, and no amount of correct symbolism survives that. The second cut
a notch through the outer wall to reveal the interior, which contradicted the one
thing that image exists to show. An illustration that disagrees with the text
beside it is worse than no illustration.

Three of the four images needed at least one retry, and the retries were for
correctness rather than taste. Budget for that.

## What each one is for

| File | Illustrates | Where the same point is made in text |
|---|---|---|
| `hero-on-rails.jpg` | Unconstrained work versus work on rails, arriving somewhere | `README.md`, opening section |
| `governed-gateway.jpg` | Many clients, one governed route, one ledger, one refusal | `README.md`, "One route" — and the table and Mermaid diagram under it |
| `permission-tiers.jpg` | Three tiers: automatic, ask, never — the outer wall unbroken | `README.md`, the permission-tier tables |
| `evidence-not-promises.jpg` | A sealed claim among unsealed ones, traced to a command | `README.md`, "Evidence, not adjectives" |

## Alt text

Each image carries alt text describing the composition, because — given the
decorative rule — the composition is all a reader who cannot see it is missing.
Do not put load-bearing information into alt text either: if it matters, it
belongs in the body.

## Replacing these

If you fork this pack for your own organisation, replace them with your own
palette. Keep the decorative rule, keep the habit of looking at what came back,
and keep a note like this one saying how the replacements were made and what was
rejected.
