# OpenCode — placeholder

**Status: not implemented,** and the most likely of the four to be promoted next.

| Question | Answer today |
| :--- | :--- |
| Generated configuration here? | No. There is no renderer for `opencode` in `harness/scripts/render.py`. |
| Can the three tiers be expressed? | Probably. It is open source, so the answer is readable rather than inferable. See `NOTES.md`. |
| Gateway route? | `/ai-gateway/mlflow/v1`, shared with open-source models (claim `gw-coding-agent-routes`). Probe your own workspace (claim `probe-gw-route-coverage`). |
| Launcher? | `ug` launches it (claim `ug-agents-and-cursor`). |
| Blocker to promotion | Only that nobody has done it. There is no known structural obstacle. |

## Why this one is the recommended next promotion

Three reasons, in order of weight.

1. **The route is shared, not bespoke.** `/ai-gateway/mlflow/v1` is the route for
   open-source models generally, so proving it for OpenCode proves the path for every
   model a team serves themselves. The reference harness only exercises the Anthropic
   route, which leaves the larger half of the gateway untested by this pack.
2. **The source is readable.** Every open question in the other three placeholders is a
   question about undocumented precedence and hook behaviour, answerable only by
   experiment. Here they are answerable by reading, and then confirmable by experiment.
   Cheaper, and the answers are citable.
3. **It tests whether `harness/shared/` is actually neutral.** The shared policy claims
   to be a source of truth that any harness can render. One renderer does not
   demonstrate that; it demonstrates that a file and its only consumer agree. The
   second renderer is where the vocabulary in `harness/shared/README.md` either holds
   up or gets fixed — and finding out that it does not hold is worth more than another
   passing check.

## What to do today

If your team runs self-hosted models, this is the harness to try, and `NOTES.md` is
where to start. Expect to contribute the renderer back rather than to find one here.

## What promotion requires

`harness/PROMOTION.md`. All five conditions apply with no special case; this is the
straightforward one.
