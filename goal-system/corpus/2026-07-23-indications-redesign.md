# 2026-07-23 — indications replace candidates (chat excerpt)

Context: after the plan-v2 review (avoid = anti-maintain, no confabulated
metrics, mermaid dropped, focus on schema + prompt), Conrad redesigned the
candidate layer:

> we want to make sure the prompt guide for goalc captures that indications
> do a lot - indicate whether a goal is objective or fundemental, whether a
> user is defining a goal, strategy (way to combine goals), evidence
> mechanisms, the help/hurt/break relations, and the achiece/maintain/avoid -
> the indications replace candidates completely i think ? but every
> indication should be either approved or not approved from a user (3
> statused total, approved, not, and no action yet). We then have 2 goal
> files we can build, the one that shows the total goal system if all is
> approved (removing indications that were specifically rejected) and the
> goal system we would derive if we only track what is explicitely approved.
> ... we want a total rewrite

Decisions (catchball, four questions answered):

- Approvals live in their own append-only `approvals.jsonl`, human-authored
  only, via `goalc approve/reject`; latest event per indication wins.
- Indications are atomic claims — one approvable statement each (existence,
  mode, grade, fundamentality, each edge separately); batch approval verb
  for ergonomics.
- Migration by backfill: the existing graph converts to indications citing
  existing corpus spans; previously-confirmed nodes get backfilled approval
  events (the past commits were the approvals); candidates enter pending.
- Evidence checks run against the optimistic view — seeing evidence pass or
  fail before approving is the information approval needs.

Effect: goals.yaml is retired. Structure itself becomes a fold — the same
move status and gaps already made. Two compiled views: optimistic (all but
rejected) and strict (approved only).
