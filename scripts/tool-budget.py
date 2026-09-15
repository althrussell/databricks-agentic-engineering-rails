#!/usr/bin/env python3
"""Report what the MCP configuration costs in context, against the stated ceilings.

Usage:  scripts/tool-budget.py [--live] [--profile NAME] [--json] [--quiet]
Exit:   0  every measured figure is within its ceiling
        1  a ceiling is exceeded
        2  this script cannot do its job

Why a budget needs a script and not a review
--------------------------------------------
Every registered MCP tool costs context in every session whether or not it is called,
and the cost is invisible: nobody notices the twelfth tool, and by then the first
message of every session carries several thousand tokens of schema nobody chose.
`harness/shared/mcp.yml` states four ceilings. This measures against them.

The part that makes the number honest
-------------------------------------
Two of the four figures can be measured from committed files. The third cannot:
**the tool schemas are advertised by the server at connect time**, so their real size
is unknown until something connects. That matters because tool schemas are usually the
largest component, so an estimate that quietly leaves them out and compares the
remainder to a ceiling reports a pass it has not earned.

So the offline estimate is reported as a **lower bound**, labelled as one, and a pass
against the token ceiling says "lower bound within ceiling" rather than "within
ceiling". `--live` connects to the governed MCP route, asks the server for its tool
list, and measures the bytes it actually sends - which turns the lower bound into a
measurement. Prefer it before quoting a number to anyone.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MCP_YML = os.path.join(ROOT, "harness", "shared", "mcp.yml")
GENERATED_MCP = os.path.join(ROOT, "harness", "claude-code", "mcp.json")

# Files loaded into the front of every session, if present. Kept as a list rather than
# a glob because "which files does the harness always read" is a policy question with a
# specific answer, and a glob would silently start counting a file someone added for a
# different purpose.
ALWAYS_LOADED = [
    "CLAUDE.md",
    ".claude/CLAUDE.md",
    "AGENTS.md",
]
SKILL_GLOB = ("skills", "SKILL.md")


def die(msg: str) -> None:
    sys.stderr.write("\n  %s\n\n" % msg)
    raise SystemExit(2)


def load_yaml(path: str):
    try:
        import yaml
    except ImportError:
        die("PyYAML is not installed, and this script reads harness/shared/mcp.yml.\n"
            "  Install it (pip install pyyaml) or run `make deps` for the full list.")
    try:
        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh)
    except OSError as exc:
        die("could not read %s: %s" % (path, exc))


def measured_servers_and_tools(mcp: dict) -> tuple[int, list[str], list[str]]:
    """Count from the policy, then cross-check against what was generated.

    Counting the generated file alone would measure the render; counting the policy
    alone would measure the intent. They should agree, and a disagreement means the
    render is stale - which is a different problem, reported as one.
    """
    servers = mcp.get("servers", []) or []
    tools: list[str] = []
    for s in servers:
        tools.extend(s.get("tools_allowed", []) or [])

    notes = []
    if os.path.exists(GENERATED_MCP):
        try:
            with open(GENERATED_MCP, encoding="utf-8") as fh:
                generated = json.load(fh)
            n = len(generated.get("mcpServers", {}))
            if n != len(servers):
                notes.append(
                    "harness/shared/mcp.yml declares %d server(s) and the generated "
                    "harness/claude-code/mcp.json has %d. Run `make harness-generate`; "
                    "until then these figures describe the policy and not what a "
                    "session would load." % (len(servers), n))
        except (OSError, ValueError) as exc:
            notes.append("could not read %s (%s), so the policy figures below are "
                         "unchecked against the generated file" % (GENERATED_MCP, exc))
    else:
        notes.append("no generated harness/claude-code/mcp.json, so the figures below "
                     "are the policy's intent and not a measurement of what loads")
    return len(servers), tools, notes


def instruction_files() -> list[tuple[str, int]]:
    out = []
    for rel in ALWAYS_LOADED:
        p = os.path.join(ROOT, rel)
        if os.path.isfile(p):
            out.append((rel, os.path.getsize(p)))
    skills_dir = os.path.join(ROOT, SKILL_GLOB[0])
    if os.path.isdir(skills_dir):
        for name in sorted(os.listdir(skills_dir)):
            p = os.path.join(skills_dir, name, SKILL_GLOB[1])
            if os.path.isfile(p):
                out.append((os.path.join(SKILL_GLOB[0], name, SKILL_GLOB[1]),
                            os.path.getsize(p)))
    return out


def live_tool_schema_bytes(profile: str) -> tuple[int, list[str], str]:
    """Ask the governed MCP route for its tool list and measure what it sends.

    Returns (bytes, advertised tool names, note). Raises SystemExit(2) only when the
    caller has asked for a live measurement and the prerequisites for making one are
    absent - because returning zero here would be indistinguishable from a server that
    advertises nothing, and those mean opposite things.
    """
    service = os.environ.get("DAER_MCP_SERVICE", "").strip()
    if not service:
        die("--live needs DAER_MCP_SERVICE set to the Unity Catalog name of the\n"
            "  governed MCP service, as catalog.schema.name. Without it there is no\n"
            "  route to connect to, and reporting 0 bytes would look like a server\n"
            "  that advertises no tools.")

    def cli(args: list[str]) -> str:
        try:
            r = subprocess.run(["databricks"] + args + ["--profile", profile],
                               capture_output=True, text=True, timeout=60)
        except (OSError, subprocess.SubprocessError) as exc:
            die("could not run the databricks CLI: %s" % exc)
        if r.returncode != 0:
            die("databricks %s failed for profile %r. Run: databricks auth login "
                "--profile %s" % (" ".join(args), profile, profile))
        return r.stdout

    host = ""
    m = re.search(r'"DATABRICKS_HOST"\s*:\s*"([^"]+)"', cli(["auth", "env"]))
    if m:
        host = m.group(1).rstrip("/")
    token = ""
    m = re.search(r'"access_token"\s*:\s*"([^"]+)"', cli(["auth", "token"]))
    if m:
        token = m.group(1)
    if not host or not token:
        die("could not resolve a host and token for profile %r" % profile)

    url = "%s/ai-gateway/mcp-services/%s" % (host, service)
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list",
                       "params": {}}).encode()
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": "Bearer %s" % token,
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        die("the governed MCP route answered %s for service %r.\n"
            "  This is a measurement, not a budget failure: nothing was measured.\n"
            "  Check the service exists in Unity Catalog and that you can read it."
            % (exc.code, service))
    except (urllib.error.URLError, OSError) as exc:
        die("could not reach the governed MCP route: %s" % exc)

    text = raw.decode("utf-8", "replace")
    # A streaming transport wraps the payload in SSE frames. The JSON is what costs
    # context, so the frame overhead is stripped before measuring.
    payload = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("data:"):
            line = line[5:].strip()
        if line.startswith("{"):
            try:
                payload = json.loads(line)
                break
            except ValueError:
                continue
    if payload is None:
        try:
            payload = json.loads(text)
        except ValueError:
            die("the route answered, but not with JSON this script could read. "
                "Nothing was measured.")

    tools = payload.get("result", {}).get("tools", [])
    if not isinstance(tools, list):
        die("the route answered with no tools list. Nothing was measured.")
    measured = len(json.dumps(tools, separators=(",", ":")).encode())
    names = [t.get("name", "?") for t in tools if isinstance(t, dict)]
    return measured, names, "measured from a live tools/list on the governed route"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--live", action="store_true",
                    help="connect to the governed MCP route and measure the tool "
                         "schemas it actually advertises")
    ap.add_argument("--profile", default=os.environ.get(
        "DAER_PROFILE", os.environ.get("DATABRICKS_CONFIG_PROFILE", "DEFAULT")))
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--quiet", action="store_true", help="summary only")
    args = ap.parse_args()

    mcp = load_yaml(MCP_YML)
    if not isinstance(mcp, dict) or "budget" not in mcp:
        die("%s has no `budget` section, so there is nothing to measure against."
            % MCP_YML)
    budget = mcp["budget"]

    n_servers, tools, notes = measured_servers_and_tools(mcp)
    instr = instruction_files()
    instr_bytes = sum(b for _, b in instr)

    schema_bytes = 0
    schema_note = ("not measurable offline: tool schemas are advertised by the server "
                   "at connect time. Re-run with --live to measure them.")
    advertised: list[str] | None = None
    if args.live:
        schema_bytes, advertised, schema_note = live_tool_schema_bytes(args.profile)
        # The comparison the live mode exists for, beyond the byte count. An allowlist
        # and the server it points at are edited independently, and they disagree in two
        # directions that cost different things:
        #
        #   advertised but not allowed  - context is spent on a schema in every session
        #                                 for a tool the permission rules will refuse.
        #                                 Pure waste, and invisible.
        #   allowed but not advertised  - the allowlist names a tool the server does not
        #                                 have, so that line of the policy protects
        #                                 nothing and reads as though it does.
        allowed = set(tools)
        adv = set(advertised)
        extra = sorted(adv - allowed)
        absent = sorted(allowed - adv)
        if extra:
            notes.append(
                "the service advertises %d tool(s) the allowlist does not contain (%s). "
                "Their schemas are loaded into every session and the permission rules "
                "will then refuse the calls, so this is context spent on nothing."
                % (len(extra), ", ".join(extra)))
        if absent:
            notes.append(
                "the allowlist names %d tool(s) the service does not advertise (%s). "
                "Those entries constrain nothing. Either the wrong service is "
                "configured, or the allowlist is describing a server it no longer "
                "points at." % (len(absent), ", ".join(absent)))
        if not extra and not absent:
            notes.append("the advertised tools and the allowlist agree exactly.")

    total_bytes = instr_bytes + schema_bytes
    est_tokens = total_bytes // 4

    rows = [
        ("mcp servers", n_servers, budget["max_mcp_servers"], "counted", True),
        ("mcp tools allowed", len(tools), budget["max_mcp_tools"], "counted", True),
        ("instruction bytes", instr_bytes, budget["max_instruction_bytes"],
         "%d file(s)" % len(instr), True),
        ("estimated context tokens", est_tokens,
         budget["max_estimated_context_tokens"],
         "bytes/4; " + ("%d tool(s) advertised, %d bytes of schema"
                        % (len(advertised), schema_bytes) if args.live
                        else "LOWER BOUND, excludes tool schemas"), args.live),
    ]

    failures = [r for r in rows if r[1] > r[2]]

    if args.json:
        print(json.dumps({
            "servers": n_servers,
            "tools": len(tools),
            "instruction_bytes": instr_bytes,
            "tool_schema_bytes": schema_bytes if args.live else None,
            "estimated_context_tokens": est_tokens,
            "estimate_is_lower_bound": not args.live,
            "budget": budget,
            "exceeded": [r[0] for r in failures],
            "notes": notes,
            "advertised_tools": advertised,
        }, indent=2))
        return 1 if failures else 0

    if not args.quiet:
        print("\n  tool budget, against the ceilings in harness/shared/mcp.yml\n")
        print("  %-26s %8s %8s   %s" % ("", "measured", "ceiling", "how"))
        for name, got, ceiling, how, definite in rows:
            mark = "OVER" if got > ceiling else ("ok" if definite else "~")
            print("  %-26s %8s %8s   %-4s %s" % (name, got, ceiling, mark, how))
        print()
        if tools:
            print("  tools: %s\n" % ", ".join(tools))
        for rel, b in instr:
            print("  %8d  %s" % (b, rel))
        if not instr:
            print("  No always-loaded instruction file exists yet (looked for %s and\n"
                  "  skills/*/SKILL.md). The instruction figure above is therefore 0\n"
                  "  because there is nothing to load, not because something was\n"
                  "  measured and found small."
                  % ", ".join(ALWAYS_LOADED))
        print()
        if not args.live:
            print("  %s\n" % schema_note)
        for n in notes:
            print("  note: %s\n" % n)

    if failures:
        for name, got, ceiling, _, _ in failures:
            sys.stderr.write("  OVER    %s: %d against a ceiling of %d\n"
                             % (name, got, ceiling))
        sys.stderr.write("\n  A ceiling is a decision point, not a hard limit. Either\n"
                         "  remove a tool, or raise the ceiling in "
                         "harness/shared/mcp.yml\n  with a recorded reason.\n\n")
        return 1

    if args.live:
        print("  ok      every figure is within its ceiling, tool schemas measured.\n")
    else:
        print("  ok      counted figures are within their ceilings; the token figure\n"
              "          is a lower bound within its ceiling. Run --live to measure it.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
