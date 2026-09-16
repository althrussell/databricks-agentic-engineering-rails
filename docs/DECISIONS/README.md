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
record stays `provisional` until a human accepts it, and the Status line says so
in the record's own first section rather than being presented as settled. This is
not ceremony: an agent that can both make an architectural choice and write the
justification for it will produce a coherent-sounding record for a choice nobody
would have made deliberately.

## Records

| # | Decision | Status |
|---|---|---|
| [0001](0001-generate-every-harness.md) | Five harnesses generated, each labelled by what it can enforce | accepted |
| [0003](0003-pdf-toolchain.md) | pandoc + typst, bundled fonts, stable rebuilds | accepted |
| [0004](0004-posix-sh-for-diagnostics.md) | The doctor and the link checker carry no interpreter | accepted |
| [0005](0005-the-gate-is-a-command.md) | The gate is a command, not a workflow file | accepted |
