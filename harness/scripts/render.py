#!/usr/bin/env python3
"""render.py - turn harness/shared/ into one harness's own configuration.

Run through `make harness-generate`, which calls harness/scripts/generate.sh, which
calls this. The direct invocation is `python3 harness/scripts/render.py [--harness
claude-code] [--dry-run]`.

The contract, because everything else in this file is a consequence of it:

    harness/shared/ is the policy. A generated file is a rendering of it and is
    never edited. harness/scripts/verify.sh fails the build when one has been.

Three rules this renderer follows
---------------------------------

1.  **Fail loudly rather than drop.** A permission rule that vanished during
    rendering is the worst defect this directory can have, because the
    configuration still looks careful and the tier is gone. Every capability form
    the target harness cannot express raises, and the only escape is an explicit
    entry in SUBSTITUTIONS that names the mechanism used instead - and is checked
    against the file actually produced.

2.  **Record what the harness cannot do from this scope.** Some keys are ignored
    when they arrive in a repository's own settings file. Writing them there
    anyway produces a configuration that reads as enforced and is not, which is
    the single most dangerous kind of mistake available here. Those keys are
    listed in PROJECT_SCOPE_INEFFECTIVE, refused in settings.json, and emitted
    into the launch script's `--settings` payload instead.

3.  **Never invent a key.** Every setting written here was read in the harness's
    own documentation during this build. Where behaviour is genuinely unknown, the
    generated RENDER-NOTES.md says so under "not yet proved" rather than the
    renderer guessing and the reader inheriting the guess.

Why a generator at all, for one harness
---------------------------------------
Because the second harness is where hand-written configuration fails, and by then
the first one is load-bearing and nobody wants to touch it. The generator exists
before it is needed so that the reference harness is a rendering like every later
one, rather than the special case everything else has to imitate.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass, field

try:
    import yaml
except ImportError:  # pragma: no cover - the message is the whole behaviour
    sys.exit(
        "missing dependency: pyyaml. Run `make deps`, or "
        "`pip install pyyaml`, then re-run `make harness-generate`."
    )

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHARED = os.path.join(ROOT, "harness", "shared")
TEMPLATES = os.path.join(ROOT, "harness", "scripts", "templates")

# The same three sentences in every generated file, wrapped rather than run to 300
# columns, because the first thing anyone does with a generated file is read the top of
# it and a line that needs scrolling reads as machine output nobody proofread.
BANNER_LINES = (
    "GENERATED FILE - do not edit.",
    "",
    "Rendered from harness/shared/ by harness/scripts/render.py. Change the policy",
    "there and run `make harness-generate`. `make harness-verify` fails the build if",
    "this file was edited by hand, and says which of the two mistakes it was.",
)
BANNER_SH = "\n# ".join(BANNER_LINES).replace("# \n", "#\n")

# Harnesses this renderer can produce. The other four are placeholders on purpose:
# see harness/PROMOTION.md for what moving one across this line requires.
IMPLEMENTED = ("claude-code",)
PLACEHOLDERS = ("codex", "cursor", "copilot-cli", "opencode")


class PolicyError(Exception):
    """The shared policy is internally inconsistent. Nothing is rendered."""


class Unrenderable(Exception):
    """This harness cannot express this capability, and no substitution is recorded."""


# ---------------------------------------------------------------------------
# The neutral vocabulary
# ---------------------------------------------------------------------------

CAPABILITY = re.compile(r"^(tool|shell|net\.fetch|mcp)\((.+)\)$")


def parse_capability(text: str) -> tuple[str, str]:
    """Split `shell(git status)` into ("shell", "git status")."""
    match = CAPABILITY.match(text)
    if not match:
        raise PolicyError(
            "capability %r is not one of tool(...), shell(...), net.fetch(...) or "
            "mcp(...). The vocabulary is listed in harness/shared/README.md and is "
            "deliberately small; add a form there and here together, or express the "
            "rule with one that exists." % text
        )
    return match.group(1), match.group(2)


@dataclass(frozen=True)
class Substitution:
    """A capability this harness cannot express as a rule, and what stands in.

    `requires` is the part that keeps this honest. Each entry is a dotted path into
    the settings document this renderer produced and the value that must be there.
    If the substituted mechanism is missing or set to something else, rendering
    fails. Without that check a substitution is a comment explaining why a
    permission tier is absent.
    """

    why: str
    requires: dict = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Claude Code
# ---------------------------------------------------------------------------

CC_SUBSTITUTIONS = {
    # Two catch-alls, and the same underlying reason: in this harness an `ask` rule
    # outranks a more specific `allow` rule. A matching ask rule prompts even when a
    # narrower allow rule also matches the same call. So rendering either catch-all
    # as a rule would not add a backstop under the allow list - it would sit on top
    # of it and prompt for `git status`, and the first thing anyone would do is
    # delete the whole tier.
    "tool(Bash)": Substitution(
        why=(
            "Rendered as a rule this becomes a bare `Bash` ask entry, which outranks "
            "every narrower allow rule in the auto-allow tier and prompts for `git "
            "status`. It is also skipped for commands that run inside the sandbox, so "
            "it would be simultaneously too broad and too narrow. The asking default "
            "mode does the job the tier wants - anything not explicitly allowed "
            "prompts - and autoAllowBashIfSandboxed keeps that true for sandboxed "
            "commands, which otherwise run without a prompt."
        ),
        requires={
            "permissions.defaultMode": "default",
            "sandbox.autoAllowBashIfSandboxed": False,
        },
    ),
    "mcp(*)": Substitution(
        why=(
            "`mcp__*` is accepted only as a deny or ask rule, and as an ask rule it "
            "outranks the named tool allows above it, so every approved read would "
            "prompt. The asking default mode covers the same ground: a tool that is "
            "not named in the allow list is not allowed, and prompts."
        ),
        requires={"permissions.defaultMode": "default"},
    ),
}

# Keys that are read from a repository's own settings file and then ignored. Each one
# is refused in settings.json and delivered another way, named here so the refusal is
# a policy rather than an omission.
CC_PROJECT_SCOPE_INEFFECTIVE = {
    "sandbox.network.strictAllowlist": (
        "Takes effect only from user, managed or `--settings` scope. Set in a "
        "project file it silently does nothing, and the allowlist prompts for an "
        "unlisted host instead of denying it. Delivered by launch.sh through "
        "`--settings`."
    ),
    "sandbox.filesystem.disabled": (
        "Cannot be set from a project file at all, which is correct - a checked-out "
        "repository must not be able to switch filesystem isolation off. Listed here "
        "so nobody adds it later expecting it to work."
    ),
    "permissions.defaultMode=auto": (
        "The looser modes do not take effect from project or local settings. A repo "
        "that wants one has to say so in its documentation and let a human choose it, "
        "which is the right shape for that decision anyway."
    ),
    "permissions.defaultMode=bypassPermissions": (
        "Same as auto, and for a stronger reason: a repository that could turn the "
        "permission system off for whoever cloned it is a supply-chain vector."
    ),
    "sandbox.credentials mask entries": (
        "A `mask` entry authorises the sandbox proxy to send a real credential to a "
        "named host, so it is honoured only from settings the human or their "
        "administrator controls. Every credential entry this renderer writes is "
        "`deny`, which any scope may add."
    ),
}


def cc_render_rule(form: str, arg: str) -> str:
    """One capability, in Claude Code's permission-rule syntax.

    The `shell` form renders as a prefix rule. Worth being precise about what that
    does and does not catch, because the deny tier depends on it: `Bash(git push
    --force:*)` matches the command whose text begins with those words, and misses
    the same action spelled with a global option before the subcommand, with the
    subcommand quoted, or with the flag moved after the refspec. That is not a
    defect to be fixed with a cleverer pattern - it is why the never-automatic tier
    is also enforced by harness/shared/guards/never-automatic.sh, which normalises
    the text first. The rules stop the canonical spelling and leave a record in the
    settings file; the guard stops the rest and leaves a record in the journal.
    """
    if form == "tool":
        return arg
    if form == "shell":
        return "Bash(%s:*)" % arg
    if form == "net.fetch":
        return "WebFetch(domain:%s)" % arg
    if form == "mcp":
        server, dot, tool = arg.partition(".")
        if not dot or not server or not tool:
            raise Unrenderable(
                "mcp(%s) has no server.tool shape. Claude Code accepts a wildcard "
                "only after a literal mcp__<server>__ prefix, so a server-wide or "
                "global form has to be either written out or substituted." % arg
            )
        return "mcp__%s__%s" % (server, tool)
    raise Unrenderable("no Claude Code rendering for capability form %r" % form)


TIER_TO_KEY = {"auto-allow": "allow", "ask": "ask", "never-automatic": "deny"}


def cc_permissions(permissions: dict) -> tuple[dict, list[tuple[str, str, Substitution]]]:
    """Render the three tiers, and report which capabilities were substituted."""
    declared = {tier["id"] for tier in permissions["tiers"]}
    if set(TIER_TO_KEY) != declared:
        raise PolicyError(
            "permissions.yml declares tiers %s; this renderer knows %s. A new tier "
            "needs a decision about which permission list it becomes, not a default."
            % (sorted(declared), sorted(TIER_TO_KEY))
        )

    buckets: dict[str, list[str]] = {"allow": [], "ask": [], "deny": []}
    substituted: list[tuple[str, str, Substitution]] = []

    for cap in permissions["capabilities"]:
        tier = cap["tier"]
        if tier not in TIER_TO_KEY:
            raise PolicyError(
                "capability %r sits in tier %r, which permissions.yml does not declare."
                % (cap["id"], tier)
            )
        key = TIER_TO_KEY[tier]
        for text in cap.get("capabilities") or []:
            if text in CC_SUBSTITUTIONS:
                substituted.append((cap["id"], text, CC_SUBSTITUTIONS[text]))
                continue
            rule = cc_render_rule(*parse_capability(text))
            if rule not in buckets[key]:
                buckets[key].append(rule)

    # A rule in two tiers is a policy bug, not a rendering one, and the harness would
    # resolve it silently in the stricter direction. Say so instead.
    seen: dict[str, str] = {}
    for key, rules in buckets.items():
        for rule in rules:
            if rule in seen:
                raise PolicyError(
                    "rule %s is produced in both the %s and %s tiers. One capability "
                    "renders to one rule; two tiers claiming it means the policy has "
                    "not decided." % (rule, seen[rule], key)
                )
            seen[rule] = key

    mode = permissions["default_mode"]
    if mode != "manual":
        raise PolicyError(
            "default_mode is %r. This renderer maps only the asking mode, because the "
            "two catch-all capabilities are substituted by it (see CC_SUBSTITUTIONS) "
            "and any other value would remove the backstop without removing the "
            "substitution." % mode
        )

    # The canonical spelling of the asking mode is "default", labelled Manual in the
    # interface. "manual" is accepted as an alias by recent versions only, so the
    # canonical value goes in the file and the neutral policy keeps the readable word.
    document = {"defaultMode": "default"}
    for key in ("allow", "ask", "deny"):
        document[key] = buckets[key]
    return document, substituted


def cc_sandbox(boundary: dict) -> dict:
    """Render boundary.yml into Claude Code's sandbox block.

    Only the keys this scope can actually deliver. `strictAllowlist` is the notable
    absence and is in CC_PROJECT_SCOPE_INEFFECTIVE with the reason.
    """
    fs = boundary["filesystem"]
    net = boundary["network"]

    if net["policy"] != "allowlist":
        raise PolicyError(
            "boundary.yml network.policy is %r. An allowlist is the only policy this "
            "renderer can express; a denylist would have to be written as one."
            % net["policy"]
        )

    # The workspace host is a variable in the policy and must stay one in every
    # committed file. Claude Code's settings.json performs no variable expansion, so
    # a "${...}" entry here would be taken literally and match nothing. It is dropped
    # with intent and added by launch.sh at run time, where the value exists.
    literal_domains = [d for d in net["allowed_domains"] if "${" not in d]
    variable_domains = [d for d in net["allowed_domains"] if "${" in d]
    if not variable_domains:
        raise PolicyError(
            "boundary.yml lists no variable domain. The workspace host is supposed to "
            "be one; a literal host in a committed allowlist is both a leak and a file "
            "every fork has to edit."
        )

    return {
        "enabled": True,
        # The most important line in the block. A missing sandbox otherwise warns and
        # then runs unsandboxed, so the boundary appears in the file, the reader
        # believes it is on, and it is not.
        "failIfUnavailable": bool(boundary["availability"]["fail_if_unavailable"]),
        # Removes the retry-outside-the-sandbox escape hatch.
        "allowUnsandboxedCommands": False,
        # Without this, a command the sandbox can run is approved automatically and
        # the ask tier's backstop never fires. It is the other half of the tool(Bash)
        # substitution.
        "autoAllowBashIfSandboxed": False,
        "filesystem": {"denyRead": list(fs["deny_read"])},
        "credentials": {
            # Two mechanisms over the same paths, deliberately. denyRead is the
            # filesystem layer; a credentials `deny` entry is the same read block
            # grouped where a reviewer looks for credentials, and its environment
            # half survives even if filesystem isolation is switched off elsewhere.
            "files": [{"path": p, "mode": "deny"} for p in fs["deny_read"]],
            "envVars": [{"name": v, "mode": "deny"} for v in fs["strip_env"]],
        },
        "network": {"allowedDomains": literal_domains},
    }


def cc_hooks(guard_rel: str) -> dict:
    """Two matchers, one adapter.

    The adapter is what turns the never-automatic tier from a list of patterns into
    something that leaves a record. `Bash` catches shell calls; `mcp__.*` catches
    every MCP tool, which matters because a messaging server registered later would
    otherwise arrive with no classifier in front of it.
    """
    command = "${CLAUDE_PROJECT_DIR}/%s" % guard_rel
    entry = {"hooks": [{"type": "command", "command": command}]}
    return {
        "PreToolUse": [
            dict(matcher="Bash", **entry),
            dict(matcher="mcp__.*", **entry),
        ]
    }


def dotted(document: dict, path: str):
    """Look up "a.b.c" in nested dicts. Returns KeyError's absence as a sentinel."""
    node = document
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return _MISSING
        node = node[part]
    return node


_MISSING = object()


def cc_check_substitutions(settings: dict, substituted) -> None:
    """Every substituted capability must point at a mechanism that is really there."""
    for cap_id, text, sub in substituted:
        for path, expected in sub.requires.items():
            found = dotted(settings, path)
            if found is _MISSING:
                raise PolicyError(
                    "capability %s (%s) is not rendered as a rule because %s stands in "
                    "for it, and %s is absent from the settings this renderer "
                    "produced. The tier would be silently gone."
                    % (text, cap_id, path, path)
                )
            if found != expected:
                raise PolicyError(
                    "capability %s (%s) is substituted by %s = %r, but the rendered "
                    "settings say %r. A substitution that does not hold is a missing "
                    "permission tier with a comment next to it."
                    % (text, cap_id, path, expected, found)
                )


def cc_check_ineffective(settings: dict) -> None:
    """Refuse to write a key this scope would ignore."""
    for entry in CC_PROJECT_SCOPE_INEFFECTIVE:
        path, _, value = entry.partition("=")
        path = path.strip()
        if " " in path:  # a prose entry, documented rather than checkable
            continue
        found = dotted(settings, path)
        if found is _MISSING:
            continue
        if value and str(found) != value.strip():
            continue
        raise PolicyError(
            "settings.json would contain %s, which this scope ignores: %s"
            % (entry, CC_PROJECT_SCOPE_INEFFECTIVE[entry])
        )


def cc_mcp(mcp: dict, gateway: dict, harness_dir: str) -> tuple[dict, list[str]]:
    """Render the MCP registration, and return the tools it expects to be governed."""
    servers = {}
    tools: list[str] = []
    for server in mcp["servers"]:
        route = server["route"]
        if route not in mcp["routes"]:
            raise PolicyError(
                "server %r names route %r, which mcp.yml does not define."
                % (server["name"], route)
            )
        if not mcp["routes"][route]["governed_by_gateway"] and "why" not in server:
            raise PolicyError(
                "server %r uses the ungoverned route %r with no recorded reason. "
                "That combination is the one this pack exists to make visible."
                % (server["name"], route)
            )
        if route != "governed":
            raise PolicyError(
                "server %r uses route %r. Only the governed route is rendered, "
                "because a generated config that quietly bypasses the gateway is "
                "worse than none." % (server["name"], route)
            )

        template = mcp["routes"][route]["template"]
        # Both placeholders stay placeholders. `.mcp.json` does expand ${VAR} in the
        # url, unlike settings.json, so the workspace host is supplied by launch.sh at
        # run time and the service name by whoever deploys the environment.
        url = template.replace("{workspace}", "${DAER_WORKSPACE_HOST}").replace(
            "{uc_full_name}", server["uc_full_name"]
        )
        servers[server["name"]] = {
            "type": server["transport"],
            "url": url,
            # A short-lived token minted per connection, plus the gateway request tag,
            # so MCP traffic is attributable the same way model traffic is. See the
            # helper's own header for why this is not a literal Authorization value.
            "headersHelper": "${CLAUDE_PROJECT_DIR}/%s/hooks/mcp-auth-header.sh"
            % harness_dir,
        }
        tools.extend("%s.%s" % (server["name"], t) for t in server["tools_allowed"])

    budget = mcp["budget"]
    if len(servers) > budget["max_mcp_servers"]:
        raise PolicyError(
            "%d MCP servers registered, ceiling is %d (mcp.yml budget)."
            % (len(servers), budget["max_mcp_servers"])
        )
    if len(tools) > budget["max_mcp_tools"]:
        raise PolicyError(
            "%d MCP tools allowed, ceiling is %d (mcp.yml budget)."
            % (len(tools), budget["max_mcp_tools"])
        )
    return {"mcpServers": servers}, tools


def cross_check_mcp_tools(permissions: dict, expected_tools: list[str]) -> None:
    """The two files must agree on which MCP tools exist.

    mcp.yml decides what is registered and pays the context cost; permissions.yml
    decides what may be called. A tool in one and not the other is either a standing
    grant to something unregistered or a registered tool with no tier, and both read
    as deliberate in the file where they appear.
    """
    named = set()
    for cap in permissions["capabilities"]:
        for text in cap.get("capabilities") or []:
            form, arg = parse_capability(text)
            if form == "mcp" and arg != "*":
                named.add(arg)
    registered = set(expected_tools)

    unregistered = sorted(named - registered)
    ungoverned = sorted(registered - named)
    problems = []
    if unregistered:
        problems.append(
            "permissions.yml names MCP tools that mcp.yml does not register: %s. The "
            "rule would sit in the settings file granting access to a tool the "
            "session never loads." % ", ".join(unregistered)
        )
    if ungoverned:
        problems.append(
            "mcp.yml registers MCP tools that no permission tier names: %s. They cost "
            "context in every session and fall to the ask catch-all, which is a "
            "decision nobody wrote down." % ", ".join(ungoverned)
        )
    if problems:
        raise PolicyError(" ".join(problems))


# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------

PLACEHOLDER_RE = re.compile(r"@@[A-Z0-9_]+@@")


def fill(harness: str, name: str, values: dict) -> str:
    """Read a template and substitute every @@PLACEHOLDER@@.

    Both directions are checked: a value with no placeholder is a stale key, and a
    placeholder with no value is a typo that would otherwise ship a script with
    `@@GUARD_REL@@` in it and fail at run time on someone else's machine.
    """
    path = os.path.join(TEMPLATES, harness, name)
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    present = set(PLACEHOLDER_RE.findall(text))
    offered = {"@@%s@@" % key for key in values}
    missing = sorted(present - offered)
    if missing:
        raise PolicyError(
            "template %s/%s uses %s, which the renderer does not supply."
            % (harness, name, ", ".join(missing))
        )
    unused = sorted(offered - present)
    if unused:
        raise PolicyError(
            "the renderer supplies %s to template %s/%s, which does not use them. A "
            "value nobody reads is either a rename that was half finished or a "
            "placeholder that was deleted from the template."
            % (", ".join(unused), harness, name)
        )

    for key, value in values.items():
        text = text.replace("@@%s@@" % key, value)
    left = PLACEHOLDER_RE.findall(text)
    if left:
        raise PolicyError(
            "template %s/%s still contains %s after substitution."
            % (harness, name, ", ".join(sorted(set(left))))
        )
    return text


# ---------------------------------------------------------------------------
# Rendering one harness
# ---------------------------------------------------------------------------

@dataclass
class Rendered:
    files: dict  # relpath within the harness directory -> (mode, text)
    unmanaged: tuple  # relpaths that are hand-written and not checked
    notes: str


def load(name: str):
    with open(os.path.join(SHARED, name), encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def render_claude_code() -> Rendered:
    permissions = load("permissions.yml")
    mcp = load("mcp.yml")
    gateway = load("gateway.yml")
    boundary = load("boundary.yml")

    harness_dir = "harness/claude-code"
    guard_rel = "harness/shared/guards/never-automatic.sh"
    if not os.path.exists(os.path.join(ROOT, guard_rel)):
        raise PolicyError(
            "the never-automatic classifier is missing at %s. The generated hook "
            "would deny every command, which is safe and useless." % guard_rel
        )

    family = gateway["families"]["claude-code"]
    defaults = gateway["defaults"]
    tags = family["request_tags"]

    perms, substituted = cc_permissions(permissions)
    sandbox = cc_sandbox(boundary)
    settings = {
        "permissions": perms,
        "sandbox": sandbox,
        "hooks": cc_hooks("%s/hooks/pretooluse-guard.sh" % harness_dir),
    }
    cc_check_substitutions(settings, substituted)
    cc_check_ineffective(settings)

    mcp_document, expected_tools = cc_mcp(mcp, gateway, harness_dir)
    cross_check_mcp_tools(permissions, expected_tools)

    literal_domains = [d for d in boundary["network"]["allowed_domains"] if "${" not in d]
    extra = "".join(',"%s"' % d for d in literal_domains)

    launch = fill(
        "claude-code",
        "launch.sh.in",
        {
            "GENERATED_BANNER": BANNER_SH,
            "DEFAULT_PROFILE": defaults["profile"],
            "GATEWAY_ROUTE": family["route"],
            "GATEWAY_PROBE_PATH": family["probe_path"],
            "PROJECT_TAG": defaults["project_tag"],
            "FAIL_IF_UNAVAILABLE": json.dumps(sandbox["failIfUnavailable"]),
            # The key a project file cannot deliver, delivered here.
            "STRICT_ALLOWLIST": "true",
            "RUNTIME_EXTRA_DOMAINS": extra,
        },
    )
    helper = fill(
        "claude-code",
        "mcp-auth-header.sh.in",
        {
            "GENERATED_BANNER": BANNER_SH,
            "DEFAULT_PROFILE": defaults["profile"],
            "PROJECT_TAG": defaults["project_tag"],
            "TAGS_HEADER": tags["header"],
        },
    )
    hook = fill(
        "claude-code",
        "pretooluse-guard.sh.in",
        {
            "GENERATED_BANNER": BANNER_SH,
            "GUARD_REL": guard_rel,
            "JOURNAL_REL": defaults["journal_path"],
        },
    )

    # Every tag key gateway.yml declares has to appear in the scripts that set the
    # header, or the usage table gets a column the policy promised and nobody filled.
    for key in tags["keys"]:
        for name, text in (("launch.sh", launch), ("mcp-auth-header.sh", helper)):
            # Backslashes removed first: one of these scripts embeds the tag object
            # inside a JSON string, so its keys are spelled \"team\" in the source.
            if '"%s"' % key not in text.replace("\\", ""):
                raise PolicyError(
                    "gateway.yml declares request tag %r, which the rendered %s does "
                    "not set. Untagged spend has no owner." % (key, name)
                )

    files = {
        "settings.json": (0o644, json_text(settings)),
        "mcp.json": (0o644, json_text(mcp_document)),
        "launch.sh": (0o755, launch),
        "hooks/mcp-auth-header.sh": (0o755, helper),
        "hooks/pretooluse-guard.sh": (0o755, hook),
    }
    notes = cc_render_notes(settings, substituted, mcp_document, expected_tools, mcp)
    files["RENDER-NOTES.md"] = (0o644, notes)
    return Rendered(files=files, unmanaged=("README.md",), notes=notes)


def json_text(document: dict) -> str:
    """Two spaces, sorted nowhere, trailing newline.

    Key order follows the renderer, not the alphabet, because these files are read by
    people and `permissions` before `sandbox` before `hooks` is the order they are
    reasoned about in.
    """
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def cc_render_notes(settings, substituted, mcp_document, tools, mcp) -> str:
    """The file that makes the generated directory reviewable.

    A generated configuration a reviewer cannot check is worse than a hand-written
    one, because it comes with the authority of having been produced by a program.
    This file is where every judgement call the renderer made is written down in the
    output, next to the output.
    """
    lines = [
        "<!--",
        *BANNER_LINES,
        "-->",
        "",
        "# Claude Code, as rendered from `harness/shared/`",
        "",
        "This directory is output. `harness/shared/` is the policy, and every file",
        "here except `README.md` is reproduced by `make harness-generate`.",
        "`make harness-verify` fails if one has been edited by hand.",
        "",
        "## Where each file goes",
        "",
        "| File | Installs as | Notes |",
        "| :--- | :--- | :--- |",
        "| `settings.json` | `<project>/.claude/settings.json` | Project scope. Two of its",
        "sibling keys deliberately are not here; see the table below. |",
        "| `mcp.json` | `<project>/.mcp.json` | Expands `${VAR}`, which `settings.json`",
        "does not. |",
        "| `launch.sh` | run in place | Resolves the workspace, probes the gateway route,",
        "injects what project scope cannot deliver. |",
        "| `hooks/pretooluse-guard.sh` | run in place | Adapter around the shared",
        "classifier. |",
        "| `hooks/mcp-auth-header.sh` | run in place | `headersHelper` for the governed",
        "MCP route. |",
        "",
        "The paths in `settings.json` are relative to the repository root through",
        "`${CLAUDE_PROJECT_DIR}`, so a team that copies `harness/` wholesale into their",
        "own project gets working hooks with no edit. A team that copies only",
        "`harness/claude-code/` gets a hook that denies everything and says why, which",
        "is the intended failure.",
        "",
        "## The permission tiers as rendered",
        "",
    ]
    perms = settings["permissions"]
    lines.append("Default mode `%s`: anything not named below prompts." % perms["defaultMode"])
    lines.append("")
    for key, heading in (
        ("allow", "Allowed with no prompt"),
        ("ask", "Prompts"),
        ("deny", "Refused by rule, and again by the guard"),
    ):
        lines.append("**%s** (%d)" % (heading, len(perms[key])))
        lines.append("")
        for rule in perms[key]:
            lines.append("- `%s`" % rule)
        lines.append("")

    lines += [
        "### What the deny rules do not catch",
        "",
        "A `Bash(...)` rule matches the text of the command as written. The deny rules",
        "above stop the canonical spelling of each never-automatic action and miss the",
        "same action written with a global option before the subcommand, with the",
        "subcommand quoted, or with the flag moved to the end. That is why the tier is",
        "also enforced by `harness/shared/guards/never-automatic.sh`, which normalises",
        "the text first and is held to `harness/shared/guards/cases.tsv` by",
        "`make harness-deny-proof`. The rules are the fast path; the guard is the one",
        "that has been tested against the awkward spellings.",
        "",
        "## Capabilities not rendered as rules",
        "",
        "The neutral policy names these; this harness expresses them another way. The",
        "renderer refuses to build unless the substituted mechanism is actually present",
        "in the file it produced.",
        "",
    ]
    for cap_id, text, sub in substituted:
        lines.append("### `%s` (%s)" % (text, cap_id))
        lines.append("")
        lines.append(sub.why)
        lines.append("")
        for path, expected in sub.requires.items():
            lines.append("- Substituted by `%s` = `%s`" % (path, json.dumps(expected)))
        lines.append("")

    lines += [
        "## Keys this scope would ignore",
        "",
        "Written into a repository's own settings file, each of these reads as enforced",
        "and does nothing. The renderer refuses to emit them here.",
        "",
        "| Key | Why not, and where it goes instead |",
        "| :--- | :--- |",
    ]
    for key, why in CC_PROJECT_SCOPE_INEFFECTIVE.items():
        lines.append("| `%s` | %s |" % (key, why))

    server_names = ", ".join(sorted(mcp_document["mcpServers"]))
    budget = mcp["budget"]
    lines += [
        "",
        "## MCP",
        "",
        "Servers: %s. Tools allowed: %d against a ceiling of %d; servers %d against %d."
        % (server_names, len(tools), budget["max_mcp_tools"],
           len(mcp_document["mcpServers"]), budget["max_mcp_servers"]),
        "",
        "The registration carries no tool allowlist of its own. Which tools may be",
        "called is decided by the permission rules above, and the renderer fails if the",
        "two files disagree about which tools exist. `scripts/tool-budget.py --live`",
        "measures the context cost against the ceilings, by asking the governed route",
        "what its tools actually cost - and reports where the allowlist and the",
        "server's advertised tools disagree, which is context spent on nothing in one",
        "direction and a policy line that constrains nothing in the other.",
        "",
        "## Proved, and worth knowing",
        "",
        "From `harness/evidence/verify-in-sandbox.md`, which is what",
        "`make harness-verify-sandbox` writes when it runs against a real workspace.",
        "",
        "- **`headersHelper` runs outside the Bash sandbox**, as a direct child of the",
        "  harness process. It was observed reading `~/.databrickscfg`, minting a token",
        "  and reaching a host on no allowlist. So the `credentials.files` deny entry",
        "  above does not break MCP authentication - that was the open question - but the",
        "  helper is a command named in `.mcp.json` that runs with the developer\'s full",
        "  authority and outside every boundary configured here. Treat it as trusted",
        "  code: `.mcp.json` belongs in the set of files whose edits are not automatic.",
        "- **These rules load only in a trusted project.** Until the trust dialog is",
        "  accepted, every `permissions.allow` entry is dropped and the harness says so",
        "  on one easily missed line. Deny rules and hooks keep working, so the failure",
        "  is toward refusing, but a clone where nobody accepted the dialog queries every",
        "  routine command and looks broken.",
        "",
        "## Not yet proved",
        "",
        "Stated here rather than left for a reader to discover:",
        "",
        "- Whether a *session* reaches the model through the governed route. The route",
        "  itself is proved by a real call over HTTP; where a session sends its traffic",
        "  is a different question, and a session started with a deliberately invalid",
        "  gateway token has been seen to answer normally by falling back to an ambient",
        "  login. The environment variables `launch.sh` sets are a default, not a",
        "  control. Enforce the route with managed settings, and confirm it from the",
        "  gateway side using the request tags.",
        "- Whether the four placeholder harnesses can express these tiers at all. Until",
        "  one is rendered and run, `harness/PROMOTION.md` is a checklist and not a",
        "  claim.",
        "",
    ]
    return "\n".join(lines) + "\n"


RENDERERS = {"claude-code": render_claude_code}


def render(harness: str) -> Rendered:
    if harness in RENDERERS:
        return RENDERERS[harness]()
    if harness in PLACEHOLDERS:
        raise Unrenderable(
            "%s is a placeholder, not an implementation. There is no renderer for it, "
            "on purpose: a generated config for a harness nobody has run would make "
            "the support matrix in docs/02-harness-standard.md dishonest. "
            "harness/PROMOTION.md lists what promoting it requires." % harness
        )
    raise Unrenderable(
        "unknown harness %r. Implemented: %s. Placeholders: %s."
        % (harness, ", ".join(IMPLEMENTED), ", ".join(PLACEHOLDERS))
    )


# ---------------------------------------------------------------------------
# The drift manifest
# ---------------------------------------------------------------------------

MANIFEST = ".generated.sha256"
MANIFEST_SCHEMA = 1


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: str) -> str:
    with open(path, "rb") as handle:
        return sha256_bytes(handle.read())


def inputs_digest(harness: str) -> str:
    """One hash over everything the renderer read.

    Scoped to harness/shared/, this file, and this harness's own templates. A wider
    scope would report drift on every other harness's template change, and a reader
    who has learned that the drift message is usually spurious stops reading it.
    """
    roots = [
        os.path.join(ROOT, "harness", "shared"),
        os.path.join(TEMPLATES, harness),
    ]
    entries = [(os.path.relpath(os.path.abspath(__file__), ROOT), os.path.abspath(__file__))]
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if d != "__pycache__")
            for name in sorted(filenames):
                if name.endswith(".pyc") or name == ".DS_Store":
                    continue
                full = os.path.join(dirpath, name)
                entries.append((os.path.relpath(full, ROOT), full))

    lines = sorted("%s  %s\n" % (sha256_file(full), rel) for rel, full in entries)
    return sha256_bytes("".join(lines).encode("utf-8"))


def manifest_text(harness: str, rendered: Rendered) -> str:
    lines = [
        "# %s/%s" % (harness_dir_for(harness), MANIFEST),
        "# Written by harness/scripts/render.py. Read by harness/scripts/verify.sh,",
        "# which is POSIX sh and parses this file with no YAML and no JSON.",
        "#",
        "# Tab-separated. One record per line:",
        "#   schema     <n>",
        "#   inputs     <sha256 over every file the renderer read>",
        "#   file       <mode> <sha256> <path relative to this directory>",
        "#   unmanaged  <path>   hand-written; its content is deliberately not checked",
        "#",
        "# A changed `inputs` means the policy moved and this directory needs",
        "# regenerating. A changed `file` hash with `inputs` intact means someone edited",
        "# the output. verify.sh reports those two cases differently, because they are",
        "# different mistakes.",
        "schema\t%d" % MANIFEST_SCHEMA,
        "inputs\t%s" % inputs_digest(harness),
    ]
    for rel in sorted(rendered.files):
        mode, text = rendered.files[rel]
        if any(ch.isspace() for ch in rel):
            raise PolicyError(
                "generated path %r contains whitespace; the manifest format and its "
                "POSIX sh reader both assume none." % rel
            )
        lines.append("file\t%o\t%s\t%s" % (mode, sha256_bytes(text.encode("utf-8")), rel))
    for rel in sorted(rendered.unmanaged):
        lines.append("unmanaged\t%s" % rel)
    return "\n".join(lines) + "\n"


def harness_dir_for(harness: str) -> str:
    return os.path.join("harness", harness)


def write(harness: str, rendered: Rendered, dry_run: bool) -> list[str]:
    out = os.path.join(ROOT, harness_dir_for(harness))
    written = []
    payload = dict(rendered.files)
    payload[MANIFEST] = (0o644, manifest_text(harness, rendered))

    for rel in sorted(payload):
        mode, text = payload[rel]
        path = os.path.join(out, rel)
        written.append(os.path.join(harness_dir_for(harness), rel))
        if dry_run:
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(path, mode)
    return written


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Render harness/shared/ into each implemented harness's own "
        "configuration. Placeholder harnesses are refused rather than faked."
    )
    parser.add_argument(
        "--harness",
        action="append",
        default=None,
        help="render only this harness; repeatable. Default: every implemented one.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="render and check everything, write nothing, list the files.",
    )
    args = parser.parse_args(argv)

    targets = args.harness or list(IMPLEMENTED)
    print()
    for harness in targets:
        try:
            rendered = render(harness)
        except (PolicyError, Unrenderable) as exc:
            print("  render failed for %s\n" % harness)
            print("  %s\n" % exc)
            return 1
        written = write(harness, rendered, args.dry_run)
        verb = "would write" if args.dry_run else "wrote"
        for rel in written:
            print("  %-11s %s" % (verb, rel))
    print()
    if args.dry_run:
        print("  dry run: nothing written.\n")
    else:
        print("  run `make harness-verify` to confirm nothing here is hand-edited.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
