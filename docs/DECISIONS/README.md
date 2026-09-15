# Decision records

A decision record explains a choice a reader would otherwise have to
reverse-engineer from the code — and, more usefully, explains what was rejected
and why. The rejected option is the part that stops the same argument being had
again in six months.

## Format

Each record is `NNNN-short-slug.md` and carries these sections, in this order:

| Section | What belongs in it |
|---|---|
| Status | `accepted`, `superseded by NNNN`, or `provisional — <what would settle it>` |
| Date | When it was decided, not when the file was tidied |
| Context | The constraint that forced a choice. No preamble. |
| Decision | One paragraph, in the present tense, stating what is done. |
| Consequences | What this costs, including what a reader loses. |
| Rejected alternatives | Each option considered, and the specific reason it lost. |
| Revisit when | The observable condition that should reopen this. |

A record is never edited to change its decision. It is superseded by a later
record that names it, so the history of the reasoning survives.

## Who owns these

**An agent may draft a decision record; a human owns the decision.** A drafted
record stays `provisional` until a human accepts it, and `provisional` records
are listed in `release-readiness.yml` rather than presented as settled. This is
not ceremony: an agent that can both make an architectural choice and write the
justification for it will produce a coherent-sounding record for a choice nobody
would have made deliberately.

## Records

| # | Decision | Status |
|---|---|---|
| [0001](0001-reference-harness-first.md) | One harness implemented, four honestly labelled | accepted |
| [0002](0002-execution-boundary.md) | Where agent commands actually run | provisional |
| [0003](0003-pdf-toolchain.md) | pandoc + typst, four fonts, byte-identical output | accepted |
| [0004](0004-posix-sh-for-diagnostics.md) | The doctor and the link checker carry no interpreter | accepted |
| [0005](0005-forge-agnostic-gate.md) | The gate is a script, not a workflow file | accepted |
