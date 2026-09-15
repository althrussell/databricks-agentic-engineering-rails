# Promoting a placeholder harness

Four directories here contain a `STATUS.md` and a `NOTES.md` and no configuration.
This file is the definition of what changes that, so that "coming soon" resolves into
either a supported harness or a written reason it is not one — instead of sitting in
the support matrix indefinitely, looking like the row above it.

The bar is deliberately awkward. A harness that is described as supported will be
adopted by someone who does not read this directory, and they will assume the same
things hold that hold for the reference harness.

## The five conditions

All five, in order. Each is checkable by someone other than the person who did the
work, which is the property that matters.

### 1. A renderer, and no hand-written configuration

`harness/scripts/render.py` gains a function for the harness and its name moves out of
`PLACEHOLDERS` into `IMPLEMENTED`. Every file in the directory is generated from
`harness/shared/` and recorded in `.generated.sha256`, except files declared
`unmanaged` in that manifest.

Not negotiable, and this is the condition most likely to be quietly skipped: it is far
easier to write a working config by hand and add a generator afterwards. The result
looks identical on the first day and diverges by the third, because the hand-written
file is the one people edit. `harness/scripts/verify.sh` fails the build on that, and
it distinguishes "the policy moved and nobody regenerated" from "someone edited the
output", which are the same diff and opposite problems.

### 2. Every capability accounted for

Each capability in `harness/shared/permissions.yml` is either rendered into a rule, or
recorded as a **mechanism substitution** in the harness's `RENDER-NOTES.md`, or the
renderer refuses to produce output at all.

Silence is what is being prohibited. A capability that the harness cannot express, and
that nobody wrote down, becomes a tier that exists in the shared policy and not on
disk — and the shared policy is what the documentation describes. The reference render
needed two substitutions; both are in its `RENDER-NOTES.md` with the reasoning. Two
honest substitutions are a better outcome than none claimed.

### 3. The three tiers demonstrated, including a refusal

`harness/shared/guards/cases.tsv` holds 46 cases across six guard rules — 27 that must
be denied and 19 that must be allowed. The guard is harness-neutral, so
`make harness-deny-proof` already passes them without any harness installed. That is
not sufficient. The demonstration required here is the tier refusing **inside a live
session** of the harness under promotion, with the journal line that shows which rule
fired.

The allow cases matter as much as the deny cases. A configuration that refuses
everything passes every deny test and is useless, and a harness people work around is
worse than one they never adopted.

### 4. The gateway route probed on a real workspace

Not read from documentation. Route availability is per workspace: on the workspace this
pack was verified against, the Anthropic route returned 200 while the Codex route
returned 404 and the Gemini route returned 400 (claim `probe-gw-route-coverage`).

A real model call through the route, with request tags attached, **and the same call
with an invalid token, which must be refused.** The second call is the one that makes
the first mean something: a 200 on its own proves a route exists, not that the
credential is what opened it.

### 5. Evidence, committed

A run of `harness/scripts/verify-in-sandbox.sh` extended to the new harness, writing
`harness/evidence/verify-in-sandbox-<harness>.md`. Assertions with verdicts, not
prose. The workspace host reduced to a shape, no token or account name anywhere in it,
and a closing section saying what the run did **not** prove.

That last section is the point of the file. The reference harness's evidence names
three things it could not establish, including the fact that a session's own model
traffic reaching the gateway is not among what was proved. An evidence file with
nothing in that section is a file nobody looked hard at.

## Then, and only then

- Move the harness from `PLACEHOLDERS` to `IMPLEMENTED` in `harness/scripts/render.py`.
- Delete its `STATUS.md`, and keep `NOTES.md` — the open questions it answered are
  worth more once they have answers than while they are still questions.
- Write the harness's own `README.md`, hand-written and declared `unmanaged`, following
  `harness/claude-code/README.md`: what is enforced, by which of the four mechanisms,
  and **when each one fails**.
- Update the support matrix in `docs/02-harness-standard.md`, with the support level
  that the evidence actually supports rather than the one that was hoped for.
- Add the claims established along the way to `claims-ledger.json`, each with its
  source, its evidence and a re-verification interval. Findings about a vendor's
  behaviour expire; that is what the interval is for.

## Partial promotion is a legitimate outcome

Two of the four placeholders may never meet condition 4 as written. `ug cursor`
supports MCP only and not model routing; no gateway route is documented for Copilot
CLI at all. If the evidence shows that tool access is governable and model spend is
metered somewhere else, the correct result is a documented support level of "tools
governed, model spend not" — with the split stated plainly, in both the matrix and the
harness's own files.

What is not acceptable is one word, "supported", covering both, because a reader who
takes governance as a single property will assume a cost dashboard exists that does
not. Governing which tools an agent may reach and governing what its model calls cost
are separate problems with separate mechanisms, and this pack should never let them
share a checkmark.
