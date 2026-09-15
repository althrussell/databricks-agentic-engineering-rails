---
title: "Theme Specimen"
subtitle: "Every styled element on one page, so a theme change can be seen rather than guessed at"
docid: theme-specimen
---

This page exists to be looked at. It is not documentation, and it is not shipped
in the release; `make docs` builds it so that the PDF pipeline has something to
prove itself against before any real document exists, and so that a change to
`pack.typ` can be reviewed by comparing two renderings instead of by reading
typst source and hoping.

Body text is set in Libertinus Serif at 10.5pt, justified, on a 24mm margin. The
only fonts used anywhere in this pack are the four that typst bundles, and the
build passes `--ignore-system-fonts`. That is a reproducibility decision, not an
aesthetic one: a theme that reaches for a system font renders differently on
every machine, and then the checksum in `release/release-manifest.json` records
which laptop built the file rather than which source produced it.

# Specimen

## Headings and hierarchy

The section above is a level-one heading: it starts a page, carries a number, and
sits above a rule. That is deliberate — in a document people navigate by
skimming, a section that begins mid-page is a section that gets missed.

### A level-three heading

Level three is where most technical writing actually lives. It is set smaller and
tighter than level two, with no rule, so a reader can tell depth apart at a
glance without reading the numbers.

#### A level-four heading

Level four is italic and muted, because a document that needs five levels of
hierarchy usually needs restructuring instead.

## Inline elements

Body text supports `inline code`, **bold**, *italic*, ***both***, and links such
as [the Databricks developer hub](https://developers.databricks.com/). Inline code
is boxed rather than merely recoloured, so a bare identifier like `ug status`
stays legible when the page is printed in greyscale — which is how a reference
card is usually read.

A long inline path such as `~/.claude/settings.json` should not break the line
badly, and a long URL in running text should wrap rather than push into the
margin: <https://docs.databricks.com/aws/en/ai-gateway/coding-agent-integration-model-services>.

## Code blocks

```bash
# Launch the reference harness through the gateway.
ug claude --refresh

# What to include in a bug report: the full commit-qualified version.
ug --version   # e.g. 0.1.0+14.g93986a8
```

```python
def attribution_headers(team: str, purpose: str) -> dict[str, str]:
    """Tags travel on the request and land in the usage table's request_tags."""
    return {
        "Databricks-Ai-Gateway-Request-Tags": json.dumps(
            {"team": team, "purpose": purpose}
        )
    }
```

```sql
-- Per-team spend for the last 7 days.
SELECT request_tags:team AS team,
       count(*)          AS requests,
       sum(total_tokens)  AS tokens
FROM   system.ai_gateway.usage
WHERE  event_time >= current_timestamp() - INTERVAL 7 DAYS
GROUP  BY ALL
ORDER  BY tokens DESC
```

A code block with a very long line should scroll off nowhere and clip nothing;
typst wraps it, which is uglier than a horizontal scrollbar and more useful than
a truncation:

```text
databricks --profile PROFILE api get /api/2.0/serving-endpoints --json '{"name":"an-endpoint-with-a-deliberately-long-name-to-force-a-wrap"}'
```

## Tables

| Harness | Model routing | MCP | Status in this pack |
|---|---|---|---|
| Claude Code | `ug claude` | yes | Reference: verified end to end |
| Codex CLI | `ug codex` | yes | Placeholder — route absent on the verification workspace |
| Cursor | not supported | yes | Placeholder — MCP only, by design of the launcher |
| Gemini CLI | `ug gemini` | yes | Placeholder |
| OpenCode | `ug opencode` | yes | Placeholder |

A table with wider prose in its cells has to stay readable, because most of the
useful tables in this pack are decision tables rather than data:

| Question | Choose a Skill | Choose an MCP server |
|---|---|---|
| What is being added? | Knowledge: how this team does a thing | Capability: an action the agent could not otherwise take |
| Where does the cost land? | Context, once loaded | Context per tool definition, plus a live dependency |
| Who governs it? | Code review on the repository | Unity Catalog permissions and gateway traffic controls |

## Callouts

> **A budget is not an invoice cap.** Block thresholds are enforced
> approximately, from a near-real-time cost estimate, and requests already in
> flight are not interrupted. Size a budget as protection against a runaway loop,
> not as a guarantee about the bill.

> A blockquote is the pack's only callout, because Markdown has no callout syntax
> and inventing one would break every other renderer this source has to survive —
> GitHub's preview, an editor, a plain `cat`.

## Lists

Ordered, for anything a reader will follow in sequence:

1. Run `scripts/doctor.sh` and read the table it prints.
2. Launch the harness through the gateway.
3. Make one scoped change.
4. Attach the evidence record to the pull request.

Unordered, for things with no order:

- Model services and MCP services are both Unity Catalog securables.
- Rate limits on model services cover requests and tokens; on MCP services,
  requests only.
  - A nested item, to check indentation and the second-level marker.
    - And a third level, which should be rare enough to look slightly wrong.
- Exceeding a limit returns HTTP 429, so a client needs backoff.

Definition lists, used for glossary entries:

Gateway route
: The workspace path an agent family is pointed at. Availability is per
  workspace and has to be probed rather than assumed.

Tool budget
: The number of tool definitions a harness loads into context before the model
  starts choosing badly. A budget, because the resource is finite.

## Rules and figures

---

The rule above separates without shouting: it is deliberately narrow and light,
because a full-width rule between two sections competes with the section rule
that already means something.

Captions are set small and muted, above the table, because a caption read after
the data has arrived too late to help:

| Control | Applies to model services | Applies to MCP services |
|---|---|---|
| Requests per minute | yes | yes |
| Tokens per minute | yes | no |
| Budget thresholds | yes | yes |

: Traffic controls by service type. Token-based limits do not apply to MCP
services, which is the asymmetry most likely to surprise an admin sizing limits
for the first time.

Table width is decided by pandoc, not by the theme: a source table whose widest
line exceeds pandoc's column budget gets percentage column widths and fills the
measure, and a narrow one keeps its natural width. Both appear on this page. Only
the left edge is guaranteed, which is why no document in this pack refers to a
table as "the table on the right".

## Long paragraph, for line breaking

The point of a specimen page is that the failure modes of a theme are visual and
therefore invisible in source review. Overlong measure, a heading that collides
with a rule, a code block that clips on the right margin, a table that overflows
the text block, a footer that overlaps the last line of body text on a full page,
justified text that opens rivers when a paragraph contains several long
unbreakable identifiers such as `system.ai_gateway.external_model_spend` and
`Databricks-Ai-Gateway-Request-Tags` in quick succession — none of these appear
in a diff. They appear here, on one page, where a reviewer can see them in the
time it takes to scroll.
