# GOALS.md — Goal System Constitution

Instructions for Claude (and reference for humans) governing this repository.
Read this file and `goals.yaml` at the start of any session that touches goals.

## What this is

A provenanced goal graph, GSN-derived: **goals** (claims about desired steady
states), **strategies** (reasoning that decomposes them), **solutions**
(evidence — executable checks or static artifacts). Goals are extracted from a
corpus of timestamped conversation/document files, validated by evidence runs,
and repaired through gap questions. Tasks live elsewhere (seeds); this graph
tracks *truth*, not work.

## Constitution

1. **Record, not infer.** Every `confirmed` node carries `derived_from`: one or
   more spans (verbatim quote + source file + role). Machine proposals enter as
   `status: candidate` (rendered gray) and are promoted only by a human commit.
   Inference may generate *questions* (gaps), never facts.

2. **Gaps, not guesses.** Gaps are the only channel through which inference
   may speak: question-shaped, never work-shaped. They are not structure and
   never live in `goals.yaml`. Two kinds:
   - *Derived* gaps (a goal with no strategy/solution, an orphan, a stale
     strategy) are computed from structure at read time, like status — never
     stored.
   - *Authored* gaps (substantive questions to the human: thresholds,
     obstacles, domain discoveries) are events appended to `gaps.jsonl`
     (`raised` / `resolved`). Resolution is a new fact appended — pointing at
     the corpus span that answered it — never a mutation. Answers arrive as
     new corpus files and are extracted like everything else.

3. **Edges need textual warrant.** A `supported_by` link is recorded only when
   source text states the relation ("so that", "to ensure", "because"). Related-
   looking goals without a textual link get a gap, not an edge.

4. **Determinism gradient.** Every goal and solution carries
   `grade: deterministic | statistical | heuristic | judgment`. Grade must be
   monotone non-decreasing in determinism walking down. Leaves must be
   `deterministic`, or `judgment` with a sampled human review attached.
   Strategies carry the inferential debt between heuristic parents and
   deterministic children — they take human sign-off (`reviewed_by`,
   `reviewed_at`), and go stale when the tree beneath them changes.

5. **Append-only truth.** `runs.jsonl`, `ledger.jsonl`, and `gaps.jsonl` are
   never edited, only appended. Status is NEVER written into `goals.yaml` — it
   is a fold computed from runs at read time; open gaps are likewise a fold
   over gap events. `goals.yaml` is pure structure, expanding as information
   arrives, never retracting; git history is the promotion log.

6. **Goal identity is evidence identity.** Two statements are the same goal iff
   one check would evidence both. Normalize utterances to
   `(mode, subject, predicate)` before comparing. Adjudication verdicts are
   five-way: `same | refines | motivates | contradicts | unrelated` — only
   `same` merges. Near-duplicates are usually refinements; do not collapse
   hierarchy.

7. **Modes select folds.** `maintain` = every run in the trailing `window`
   passed. `achieve` = at least one passing run exists. `avoid` = no violation
   event in the window. Scripts evaluate leaves; temporality lives in the fold
   over run history. (MVP fold: latest run + TTL; window folds come later.)

8. **Tasks are not evidence.** Seeds (`.seeds/`) track work; closing a task is
   a claim. A task's closure triggers an evidence re-run; only the fold turns a
   goal green. Seeds reference goals (`extensions.goal_id`); goals never
   reference seeds.

## Claude session protocol

- When the human discusses goals, propose **candidate YAML blocks** matching
  the schema below, with `derived_from` quoting their exact words and naming
  the corpus file this chat will become. Never write `status: confirmed`.
- Surface gap questions when structure is missing; quote the anchoring spans.
  Raising an authored gap = appending a `raised` event to `gaps.jsonl`;
  resolving one = appending a `resolved` event citing the answering span.
- When a check fails, triage as `flaky | regression | domain_discovery` and,
  for domain discovery, propose candidate domain-facts/obstacles + a gap
  question — never conclusions.
- Never edit `runs.jsonl`, `ledger.jsonl`, `gaps.jsonl`, or emitted status —
  append only. Never promote candidates; the human's commit is the
  confirmation event.

## Schema (v0 — prose-defined; LinkML extracted later from what survives)

```yaml
subjects:                # registry — dedup happens here
  - {id, name, aliases: []}

goals:
  - id: g-<slug>
    text: <curated label, human-signed>
    mode: maintain | achieve | avoid
    subject: <subject id>
    grade: deterministic | statistical | heuristic | judgment
    status: candidate | confirmed
    derived_from:
      - {quote, source, role: states|restates|amends|motivates|contradicts}
    supported_by: [<strategy or solution ids>]

strategies:
  - id: s-<slug>
    text: <the reasoning step>
    status: candidate | confirmed
    reviewed_by: <name>        # sign-off carries the inferential debt
    reviewed_at: <date>
    supported_by: [<goal ids>]

solutions:
  - id: sn-<slug>
    kind: check | static
    recipe: just <target>      # for checks: exit code + artifacts
    ttl: <e.g. 24h>            # staleness horizon
    window: <e.g. 7d>          # for maintain folds (later)
    grade: deterministic | ...
    uri/sha256:                # for static evidence

```

Gap events (`gaps.jsonl`, one JSON object per line — NOT part of goals.yaml):

```yaml
{gap_id, event: raised | resolved,
 kind: missing_strategy|missing_solution|missing_parent|obstacle,
 anchor: <node id>, question, at, span?: <quote+source, on resolved>}
```

## Files

```
GOALS.md        this constitution
goals.yaml      structure — human-promoted only (no gaps, no status)
runs.jsonl      append-only evidence runs {solution_id, started_at,
                finished_at, status, subject_sha, graph_sha, cases?, artifacts?}
gaps.jsonl      append-only gap events (raised/resolved); open = fold
ledger.jsonl    corpus processing log {doc_sha, path, extractor, prompt_sha,
                state, at}
corpus/         the pile — save chats here, timestamped
scripts/goalc.py   tree / lint / check / gaps
queries.sql     DuckDB examples over goals + runs (+ .seeds if present)
justfile        verbs and evidence recipes (run via uv)
pyproject.toml  deps (pyyaml) — `uv run` resolves the env, no manual pip
```
