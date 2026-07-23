# 2026-07-22 — gaps are events, not structure (chat excerpt)

Context: after the first real-world check (site reachability) landed, Conrad
questioned where gaps live:

> The goals and the evidence collector work and make sense - this is
> fantastic. Gaps seems a bit off to me though - Gaps maybe do not belong in
> the goals file - I think this is why: I feel like the goals file should
> expand, but not retract, when we acquire new information. Gaps can come and
> go - and so they are kind of more like tasks in that regard - and we
> specifically do not want task tracking as a part of this system. What do
> you think? Do we even want gaps ?

Claude's assessment: gaps stay (they are the only channel inference may speak
through — question-shaped, not work-shaped), but their storage was wrong:
mutating `resolved_by: null` in place inside goals.yaml is a status write into
the structure file, the same sin rule 5 forbids for run status. Structural
gaps (missing solution/strategy/parent) are derivable and should be computed
at read time, like status. Substantive authored questions become an
append-only event log, `gaps.jsonl` (raised/resolved events); resolution is a
new fact appended, never a mutation.

Conrad's decision:

> Yes I think that is fine - it helps with understanding the semantics of the
> system. It may be wrong - but it will be easier to merge these back together
> rather than split a larger compilation apart imo. Go ahead and commit -
> update the goal system to reflect how this must function

Effect: goals.yaml becomes pure structure (subjects, goals, strategies,
solutions); gaps.jsonl joins runs.jsonl and ledger.jsonl as append-only truth.
