# Skills versus MCP

The decision people get wrong most often, and it is expensive in a way that does not show
up until sessions start feeling slow and stupid for no visible reason.

## The one-line rule

**A skill is instructions. An MCP server is a capability.**

If what you are adding is knowledge — how this team does code review, the shape of our
commit messages, which tables matter and what the columns mean — that is a skill. It is
text. It costs tokens when it is loaded and nothing when it is not.

If what you are adding is an action the harness cannot otherwise take — query this
warehouse, read this catalog, call this internal service — that is MCP. It costs tokens
in **every single session**, whether or not it is used, because the tool schemas are sent
up front.

## The cost nobody notices

Every registered MCP tool pays context rent in every session. Nobody notices the twelfth
tool. By then the first message of every session carries several thousand tokens of
schema that no one chose, the model has twelve plausible-looking options for every
request, and quality drops in a way that is very hard to attribute.

`harness/shared/mcp.yml` states four ceilings and `scripts/tool-budget.py` measures
against them:

```sh
python3 scripts/tool-budget.py            # from committed files
python3 scripts/tool-budget.py --live     # connect and measure what is really sent
```

The offline figure is reported as a **lower bound**, labelled as one, because the tool
schemas are advertised by the server at connect time and are usually the largest
component. An estimate that quietly omitted them and compared the remainder to a ceiling
would report a pass it had not earned. `--live` turns the bound into a measurement.

It also compares the allowlist against what the server actually advertises, in both
directions:

- **Advertised but not allowed** — context spent in every session on a schema whose
  calls the permission rules will refuse. Pure waste, and invisible.
- **Allowed but not advertised** — a line of policy that constrains nothing while
  reading as though it does.

## How to decide, in practice

Ask what happens if the thing is *wrong*.

A wrong skill produces bad advice, which a person notices in the output and fixes by
editing a file. A wrong MCP registration produces a capability nobody audited, in every
session, with a schema the model will try to use. The failure modes are not symmetric,
so the bar is not the same height.

Then ask whether the harness could already do it with a shell command. A great many MCP
servers wrap something that `git`, `curl` or the project's own `make` targets already do,
and a shell command costs nothing until it is called, is covered by the permission tiers
you already wrote, and appears in the guard journal. **Prefer a `make` target over an
MCP tool whenever one will do** — a `make check` is one call where a hand-rolled
equivalent is ten.

| You want to add | Use | Because |
| :--- | :--- | :--- |
| Team conventions, review standards, domain vocabulary | Skill | Text, loaded when relevant |
| A repeatable multi-step procedure | Skill | Instructions, not a new capability |
| Read from Unity Catalog | MCP, governed route | A real capability, and it should be metered |
| Query a warehouse | MCP, governed route | Same |
| Anything the CLI already does | Shell command in the auto-allow tier | Free until called, already governed |
| A wrapper around `git` | Shell command | Almost never worth the context |

## Governing MCP

Register through the gateway, not directly:

```
{workspace}/ai-gateway/mcp-services/{catalog.schema.name}    governed
{workspace}/api/2.0/mcp/...                                  UC-governed, gateway-invisible
```

Both respect Unity Catalog permissions. Only the first appears in
`system.ai_gateway.usage` and is subject to rate limits. `docs/03-gateway-auth.md` has
the detail; this pack's generated configuration uses the governed route only.

Which tools a session may call is a Unity Catalog grant on the MCP service, not a harness
setting. The harness allowlist is a second, weaker fence — it stops an accident, and it
is edited by whoever can edit the repository. **Grant narrowly at the catalog, then
allowlist.** In that order.

## Skills, briefly

Skills are the cheap half of this document, which is why there is less to say. Keep them
small and specific, name them for the situation they apply to rather than the topic they
cover, and let them be loaded on relevance rather than always. A skill that is always
loaded is an instruction file, and an instruction file that has grown past a page or two
gets skimmed by the model exactly the way it gets skimmed by people.

`scripts/tool-budget.py` counts always-loaded instruction bytes against a ceiling too,
for the same reason it counts tool schemas.
