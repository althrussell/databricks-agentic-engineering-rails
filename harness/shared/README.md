# `harness/shared/` — one policy, many harnesses

Everything in this directory is harness-neutral. Nothing here is loaded by a coding
agent directly. `harness/scripts/generate.sh` renders it into each harness's own
configuration format, and `harness/scripts/verify.sh` fails if a rendered file has
drifted from this source.

The reason for the indirection is narrow and worth stating: five harnesses
configured by hand become five policies within a quarter, and the drift is
invisible because each file looks reasonable on its own. A policy that exists once
and is rendered five times can only drift in one direction — and `verify.sh` sees
that direction.

## What each file is

| File | Holds | Rendered into |
| :--- | :--- | :--- |
| `permissions.yml` | The three permission tiers, as capability entries in a neutral vocabulary | the harness's own permission model |
| `mcp.yml` | Which MCP servers a project registers, and the tool budget ceiling | the harness's MCP registration file |
| `gateway.yml` | How each harness family reaches Unity AI Gateway: route, environment variables, headers | the harness's launch script |
| `boundary.yml` | The execution boundary: filesystem, network and credential policy | the harness's sandbox settings, where it has one |
| `guards/never-automatic.sh` | The **only** executable here. Classifies one command string against the never-automatic tier | called by a generated per-harness hook adapter |
| `guards/cases.tsv` | The verdict table the guard is tested against | `harness/scripts/deny-proof.sh` |

## The neutral vocabulary

`permissions.yml` names capabilities, not harness syntax. A capability is one of:

| Form | Means | Claude Code renders it as |
| :--- | :--- | :--- |
| `tool(Read)` | a built-in tool, by the harness's own name for it | `Read` |
| `shell(git status)` | a shell command whose leading words are exactly this | `Bash(git status *)` |
| `net.fetch(docs.databricks.com)` | an HTTP fetch to one host | `WebFetch(domain:docs.databricks.com)` |
| `mcp(databricks.execute_sql)` | one tool on one MCP server | `mcp__databricks__execute_sql` |
| `mcp(databricks.*)` | every tool on one server | `mcp__databricks__*` |

The vocabulary is deliberately small. It covers what a permission tier needs to say
and nothing else, because a configuration language rich enough to express anything
is a second program to maintain. When a harness cannot express one of these forms,
the generator must fail loudly rather than silently drop the rule — a permission
rule that vanished during rendering is the worst possible defect in this directory.

## Adding a harness

1. Add a renderer function to `harness/scripts/render.py`. It receives the parsed
   policy and returns a mapping of relative path to file content.
2. Run `make harness-generate`. The new files appear under `harness/<name>/`.
3. Run `make harness-verify`. It must pass with no hand-editing.
4. Work through `harness/PROMOTION.md`. Until every line of it holds, the harness
   stays a placeholder no matter how complete its generated config looks.

Step 4 is the one that takes the time, and it is the only one that makes the
matrix in `docs/02-harness-standard.md` honest.
