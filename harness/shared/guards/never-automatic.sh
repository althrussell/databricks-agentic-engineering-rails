#!/bin/sh
# never-automatic.sh - classify one command string against the never-automatic tier.
#
# Usage:  never-automatic.sh "<command string>"
# Exit:   0  no opinion. The command is not in the never-automatic tier; the
#            harness's own permission rules decide what happens next. Prints nothing.
#         3  denied. One line on stdout: "<rule-id><TAB><reason>".
#         2  usage error.
#
# The rule ids it emits are the guard_rule values in harness/shared/permissions.yml.
# harness/scripts/deny-proof.sh checks that the two sets still agree, so renaming a
# rule in one place fails the build rather than silently disabling a tier.
#
# This script is harness-neutral on purpose: it takes text and returns a verdict, so
# every harness's hook adapter is a translation layer rather than a second copy of
# the policy.
#
# How it matches, and why that choice
# -----------------------------------
# A harness permission rule matches the command text the model wrote, after the
# harness splits compound commands and strips a short fixed list of wrappers. It is
# not a boundary around the program. A rule anchored on the first two words stops
# the obvious spelling of a push and misses the same command with a global option in
# front of the subcommand, or with the subcommand quoted.
# Those forms are not exotic; two of them are things a competent engineer types by
# habit.
#
# So this guard normalises the text first - lowercase, quotes removed, absolute
# program paths reduced to their basename, whitespace squeezed - and then asks two
# different kinds of question about it:
#
#   * for subcommands and flags, whether a whole word is present. `merge` as a word
#     is a merge; `mergeable` inside `--json state,mergeable` is a field name, and
#     reading a pull request's merge status must not cost a prompt.
#   * for filesystem paths and endpoints, whether a substring is present, because a
#     credential path is dangerous wherever it appears in the line and whatever
#     program is reading it.
#
# The result still over-matches: a command that merely writes about a force-push in
# a commit message is refused. That trade is deliberate. In this tier a false deny
# costs one prompt and a human typing the command themselves, while a false allow
# costs a rewritten branch, a merged pull request nobody read, or a deploy at 02:00.
# The tiers above this one are where precision matters. Here, refusing too much is
# the correct failure - so long as the ordinary commands of a working day still pass,
# which is what the allow rows in cases.tsv exist to hold us to.
#
# What it is not
# --------------
# It is not a security boundary. A determined agent, or a prompt-injected one, can
# express any of these actions in a form this text match cannot see: base64, a
# script written to a file and then run, a language runtime's own process API. The
# harness's own working-directory scope is what removes the capability; this guard
# removes the accident and writes a record of the attempt. Deploy both, or neither.

set -euf   # -f matters: the tokeniser loops over unquoted $cmd, and a command
           # containing * must not be expanded against the filesystem.

if [ "$#" -ne 1 ]; then
  echo "usage: never-automatic.sh \"<command string>\"" >&2
  exit 2
fi

# ---------------------------------------------------------------- normalisation --
cmd=$(
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -d '"'"'" \
    | sed -e 's#/usr/local/bin/##g' -e 's#/usr/bin/##g' -e 's#/bin/##g' \
          -e 's#/opt/homebrew/bin/##g' -e 's#/opt/local/bin/##g' \
    | tr '\n\t' '  ' \
    | tr -s ' '
)
# Padded copy, so a `case` glob can require spaces either side of a word.
padded=" $cmd "

# has WORD - true when WORD appears as a whole space-delimited token.
has() {
  case "$padded" in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# hasany WORD... - true when any of the words appears as a token.
hasany() {
  for w in "$@"; do
    if has "$w"; then return 0; fi
  done
  return 1
}

# contains TEXT - true when TEXT appears anywhere, token boundaries ignored. Used
# for paths and URLs, where the dangerous thing is the string itself.
contains() {
  case "$cmd" in
    *"$1"*) return 0 ;;
  esac
  return 1
}

deny() {
  printf '%s\t%s\n' "$1" "$2"
  exit 3
}

# --------------------------------------------------------------- MCP tool names --
# The classifier also accepts an MCP tool name in the harness's own spelling,
# mcp__<server>__<tool>, because permissions.yml keeps a message-a-person entry with
# an empty capability list for exactly this case: no tool in the reference
# configuration can message a person, and registering one must not quietly make it
# automatic. The whole name arrives as a single token, so none of the shell rules
# below can match it by accident.
case "$cmd" in
  mcp__*)
    mcp_server=$(printf '%s' "$cmd" | awk -F'__' '{print $2}')
    mcp_tool=$(printf '%s' "$cmd" | awk -F'__' '{print $3}')
    # A messaging verb in the tool's own name, whatever server it came from.
    case "$mcp_tool" in
      *send*|*post*|*message*|*email*|*mail*|*comment*|*reply*|*notify*|*invite*)
        deny message-a-person \
          "This tool sends something to a person. The recipient cannot tell an agent's message from yours, so a human sends it." ;;
    esac
    # A server whose whole purpose is person-to-person messaging. Reads on it belong
    # to the ask tier; anything else here is a send by another name.
    case "$mcp_server" in
      slack|teams|discord|telegram|gmail|outlook|twilio|zoom|sendgrid|mailgun)
        case "$mcp_tool" in
          *read*|*get*|*list*|*search*|*info*|*history*) ;;
          *)
            deny message-a-person \
              "A write against a messaging service. Reading a channel is one thing; writing to it puts words in front of people under a human's name." ;;
        esac
        ;;
    esac
    # Nothing else here classifies MCP names. The ask tier's catch-all is what makes
    # an unrecognised tool prompt, and that is the correct place for it.
    exit 0
    ;;
esac

# ------------------------------------------------------------------ force-push --
# Needs both a push and a force. A plain push belongs to the ask tier and must keep
# prompting rather than being refused outright, so it must not match here.
if has push; then
  forced=no
  for tok in $cmd; do
    case "$tok" in
      --force|--force=*|--force-with-lease|--force-with-lease=*|--force-if-includes)
        forced=yes ;;
      +*) forced=yes ;;   # a leading + in a refspec is a force push with no force
                          # flag anywhere in the line
      -[!-]*)
        # A single-dash token, so a short-flag cluster: -f, -fu, -uf all force.
        # Matched in two steps because a glob cannot ask "starts with one dash and
        # contains an f" in one pattern, and the one-step version either misses -fu
        # or catches --follow-tags.
        case "$tok" in
          *f*) forced=yes ;;
        esac
        ;;
    esac
  done
  if [ "$forced" = yes ]; then
    deny force-push \
      "Force-pushing discards commits other people may already hold. Do this by hand, on a branch you own, after checking who else has it."
  fi
fi

# ------------------------------------------------------------ merge-or-release --
if has gh; then
  if has merge || contains "/merge"; then
    deny merge-or-release \
      "Merging is the moment a change becomes everyone's problem. A human merges, having read the diff. The API path is the same act by another route."
  fi
  if has ready; then
    deny merge-or-release \
      "Marking a pull request ready for review asks named people for their time. That request comes from a person."
  fi
  if has release && hasany create edit upload delete; then
    deny merge-or-release \
      "Cutting or changing a release publishes artifacts under this project's name. Not automatic, at any confidence level."
  fi
fi
if has git && has merge && { contains "origin/main" || contains "origin/master"; }; then
  deny merge-or-release \
    "Merging the shared branch locally is how an unreviewed change reaches a push. Do it deliberately."
fi

# ---------------------------------------------------------------------- deploy --
if has databricks; then
  if has bundle && hasany deploy destroy run; then
    deny deploy \
      "A bundle deployment changes a live target. Deploy from CI on a merged commit, or by hand with the target named out loud."
  fi
  if has apps && hasany deploy start stop delete; then
    deny deploy \
      "Starting, stopping or deploying an app is a change users can see. A human decides when."
  fi
fi
if hasany terraform tofu && hasany apply destroy; then
  deny deploy \
    "Applying infrastructure changes shared state, and the plan is the artifact a human is supposed to read first."
fi
if has kubectl && hasany apply delete; then
  deny deploy "Cluster state is shared state."
fi

# ---------------------------------------------------------- credential-access --
if contains "databrickscfg" || contains ".databricks/token" || contains "token-cache"; then
  deny credential-access \
    "That file is the human's workspace credential. Reading it hands this session their full authority. Mint a short-lived token with \`databricks auth token\` instead."
fi
if has databricks && has auth && has token; then
  deny credential-access \
    "This prints a live OAuth token to stdout, where it lands in the transcript and in every log that captured it. A script that needs a token should fetch it into a variable itself."
fi
if has security && hasany find-generic-password find-internet-password; then
  deny credential-access \
    "Keychain access is credential access, and a changed HOME does not isolate the keychain."
fi
if contains "keychain"; then
  deny credential-access "Keychain access is credential access."
fi
if contains "id_rsa" || contains "id_ed25519" || contains ".ssh/" \
   || contains ".netrc" || contains ".aws/credentials" \
   || contains "application_default_credentials"; then
  deny credential-access \
    "A private key or a cloud credential file. Nothing in an agent session needs to read one."
fi
if contains "managed-settings.json" || contains "managed_config.toml"; then
  deny credential-access \
    "That is the organisation's managed harness policy. It is deliberately outside this session's reach."
fi
if contains ".claude/settings" || contains "ucode-settings" || contains ".codex/config"; then
  deny credential-access \
    "That is the harness's own configuration. An agent that can edit its own permission rules does not have permission rules."
fi

# ----------------------------------------------------------- message-a-person --
if has gh; then
  if hasany comment review; then
    deny message-a-person \
      "A comment or review arrives as a notification with a human's name attached. That name should belong to whoever meant to send it."
  fi
  if has issue && has create; then
    deny message-a-person "Opening an issue puts an item on someone's queue under your name."
  fi
fi
if contains "chat.postmessage" || { contains "slack" && has post; }; then
  deny message-a-person \
    "Messaging an individual is never automatic. The recipient cannot tell an agent's message from yours."
fi
if hasany sendmail mailx || { has osascript && contains "messages"; }; then
  deny message-a-person "Messaging an individual is never automatic."
fi

# ---------------------------------------------------------- destructive-path --
if has rm || has rmdir; then
  # Rooted at / or at the home directory, or climbing out of the working tree.
  if contains " /" || contains " ~" || contains "\$home" || contains "../"; then
    for tok in $cmd; do
      hit=no
      case "$tok" in
        --recursive|--force) hit=yes ;;
        -[!-]*) case "$tok" in *r*|*f*) hit=yes ;; esac ;;
      esac
      if [ "$hit" = yes ]; then
        deny destructive-path \
          "A recursive or forced delete whose path is not confined to the working tree. There is no version of this worth not asking about."
      fi
    done
  fi
fi
if contains "mkfs" || contains "diskutil erase" \
   || { has dd && contains "of=/dev/"; }; then
  deny destructive-path "Destroys a device, or the machine it runs on."
fi
if has find && has -delete && { contains " /" || contains " ~"; }; then
  deny destructive-path "A recursive delete rooted outside the repository."
fi
if hasany chmod chown && contains " /"; then
  for tok in $cmd; do
    hit=no
    case "$tok" in
      --recursive|-R) hit=yes ;;
      -[!-]*) case "$tok" in *r*) hit=yes ;; esac ;;
    esac
    if [ "$hit" = yes ]; then
      deny destructive-path \
        "A recursive permission or ownership change rooted outside the repository."
    fi
  done
fi
if has git && has clean; then
  # -x is the flag that turns tidying into deleting ignored files. -X alone removes
  # only ignored files, which is the same hazard, and both lowercase here.
  for tok in $cmd; do
    case "$tok" in
      -[!-]*)
        case "$tok" in
          *x*)
            deny destructive-path \
              "Cleaning ignored files deletes exactly where .env files, local credentials and unpushed scratch work live." ;;
        esac
        ;;
    esac
  done
fi
if has git && has reset && has --hard && contains "origin"; then
  deny destructive-path \
    "A hard reset to the remote throws away local commits that exist in no other copy. Ask first."
fi

exit 0
