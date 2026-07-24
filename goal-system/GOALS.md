# GOALS.md — Goal System Constitution (v1: indications)

Instructions for Claude (and reference for humans) governing this repository.
Read this file at the start of any session that touches goals.

## What this is

A provenanced goal graph where **structure itself is a fold**. The machine
observes conversations and appends **indications** — atomic, provenanced
claims about goals. The human appends **approvals**. The goal graph is never
written directly by anyone: it is compiled from the two logs, in two views:

- **optimistic** — every indication except those explicitly rejected
  ("the system if all of this turned out true")
- **strict** — only what is explicitly approved
  ("the system we are willing to stand behind")

Evidence runs validate leaves; gaps carry open questions; the corpus of
timestamped conversation files is where everything ultimately comes from.
Tasks live elsewhere; this graph tracks *truth*, not work.

## Indications

An indication is one atomic, approvable claim, derived from a span of source
text. Indications do a lot — one kind per thing they can indicate:

| kind | claims | payload |
|---|---|---|
| `goal` | a goal exists | `node`, `text`, `subject` |
| `strategy` | a way to combine goals exists | `node`, `text` |
| `solution` | an evidence mechanism exists | `node`, `recipe`/`uri`, `ttl`, `window?` |
| `subject` | a subject exists | `node`, `name`, `aliases` |
| `mode` | a goal is achieve / maintain / avoid | `node`, `mode` |
| `grade` | determinism grade | `node`, `grade` |
| `fundamental` | the goal is fundamental — "it just is" | `node` |
| `supports` | parent is argued/evidenced by child | `node`, `child` |
| `relates` | goal→goal contribution | `node`, `to`, `effect: helps\|hurts\|breaks` |

Every indication carries `span` (or `spans`): `{quote, source, role}`. A goal
without a `fundamental` indication is a means objective — something held
because it helps something else. Fundamental goals define value; they are
what a business communicates with and what satisfaction — the customer's,
ours — is measured against.

Each indication has exactly one of three states, computed from
`approvals.jsonl`: **approved**, **rejected**, or **pending** (no action
yet). Approval events are appended, never edited; the latest event per
indication wins, so any verdict can be superseded by appending another.

## Constitution

1. **Record, not infer.** The machine writes only `indications.jsonl`; the
   human writes only `approvals.jsonl`. Neither writes the graph — it is
   compiled. Every indication carries a span; inference may generate
   *questions* (gaps) and *indications*, never approved structure.

2. **Gaps, not guesses.** Unchanged: derived gaps (a goal with no support)
   are computed at read time; authored questions are events in `gaps.jsonl`
   (`raised`/`resolved`). Resolution is a new fact appended, never a
   mutation.

3. **Warrant is literal.** Every span's `quote` must occur verbatim
   (whitespace-normalized) in its named `source` file — enforced by lint.
   This closes the channel where an extractor could forge provenance.
   `relates` edges need warrant like everything else: "because", "so that",
   "but", "at the cost of".

4. **Determinism gradient.** Grades `deterministic | statistical | heuristic
   | judgment`, monotone non-decreasing in determinism walking down the
   strict view. Leaves must be `deterministic`, or `judgment` with sampled
   human review.

5. **Append-only truth.** `indications.jsonl`, `approvals.jsonl`,
   `runs.jsonl`, `gaps.jsonl`, `ledger.jsonl`: appended, never edited. All
   graph state — structure, status, open gaps — is a fold at read time. The
   compiled views under `views/` are build artifacts, never sources.

6. **Goal identity is evidence identity.** Two statements are the same goal
   iff one check would evidence both. Adjudication verdicts —
   `same | refines | motivates | contradicts` — enter as indications too.
   Only `same` merges; near-duplicates are usually refinements.
   Corollary: **subject identity is measurement identity** — a subject is
   the thing whose state a check reads (`subject_sha`). If we cannot say
   what `subject_sha` would hash, we have a topic, not a subject.

7. **Modes select folds.** `maintain` = every run in the trailing `window`
   passed. `avoid` = anti-maintain: identical fold, opposite reading — a
   failing run means a violation was observed. `achieve` = at least one
   passing run exists, sticky. No `window` declared → latest run + TTL.
   How often to look is a property of each goal's solution, not a system
   metric. Relations (`relates`) never propagate fold status — a goal is
   not red because a green goal hurts it; tensions are surfaced, not folded.

8. **Tasks are not evidence.** Seeds track work; closing a task is a claim.
   Only the fold turns a goal green.

## Claude session protocol — discovery mode

Discovery is a **state, and it is open until the human closes it.** This
protocol exists because the model's training pulls toward producing
artifacts the moment production is possible; here, that is the failure mode.

- While discovery is open: **no files are written.** Proposed indications
  live in the chat as readable claims ("indication: g-x helps g-y, from
  'because...'"). Receiving answers is not closure — answers open threads.
  `answered ⇒ closed` is an illegal transition.
- The conversation's aim: walk toward **fundamental goals**. The indicator
  is the answer shape "**it just is**" — when why-questions stop producing
  "because it helps X". The model may notice this; only the human confirms
  fundamentality (as an approval, like everything else).
- Question repertoire, used naturally, not as a script: *why is that
  important?* · *what would happen if you couldn't?* · *what would it mean
  if that were true?* · *tell me about the last time this happened* · *my
  label for this is ____ — is that your meaning?* (confirm every label
  before it becomes an indication's text) · *which two of these are alike,
  and how does the third differ?* (when subjects are unclear).
  Sources in `references.bib`.
- Watch for and voice indications of every kind as they occur: goal
  definitions, strategies, evidence mechanisms, modes, fundamentality, and
  especially relation talk — "but", "except", "at the cost of" indicate
  hurts/breaks; "because", "so that" indicate helps/supports.
- The model may **propose** closure ("this thread reads saturated — close,
  park, or keep digging?"); only the human closes (catchball). On "sort
  it": append the accumulated indications to `indications.jsonl`, then
  stop — approval is the human's move, at their pace.
- When a check fails, triage as `flaky | regression | domain_discovery`;
  for domain discovery, propose indications + a gap question, never
  conclusions.
- Never append to `approvals.jsonl` (except as explicitly directed
  backfill). Never edit any log. Imperfection is expected; the transcript
  is the safety net — everything lands in corpus and can be re-mined.

## Schema (v1)

```
indications.jsonl   (machine-appended)
{id: i-NNNN, at, kind, node, span|spans: {quote, source, role},
 ...kind-specific payload (see table above)}

approvals.jsonl     (human-appended, via `goalc approve|reject`)
{indication: i-NNNN, verdict: approved|rejected, at, by}

runs.jsonl          {solution_id, started_at, finished_at, status,
                     subject_sha, graph_sha, cases?, artifacts?}
gaps.jsonl          {gap_id, event: raised|resolved, kind, anchor,
                     question, at, span?}
ledger.jsonl        {doc_sha, path, extractor, prompt_sha, state, at}
```

## Files

```
GOALS.md            this constitution
indications.jsonl   machine-observed claims — append-only
approvals.jsonl     human verdicts — append-only
runs.jsonl          evidence runs — append-only
gaps.jsonl          question events — append-only
ledger.jsonl        corpus processing log — append-only
corpus/             the pile — save chats here, timestamped
views/              compiled goal files (goalc build) — artifacts, gitignored
scripts/goalc.py    tree / lint / check / gaps / pending / approve / reject / build
references.bib      goal-discovery bibliography
queries.sql         DuckDB over the logs
justfile            verbs and evidence recipes (run via uv)
pyproject.toml      deps — `uv run` resolves the env
```

## Verbs

```
just tree [FILTER]      optimistic view (pending rendered gray); FILTER =
                        subject or node id
just tree-strict        approved-only view
just pending            indications awaiting a verdict
just approve I...       append approval events
just reject I...        append rejection events
just check [SOLUTION]   run due evidence over the optimistic view
just build              write views/goals.{optimistic,approved}.yaml
just lint | gaps | ingest FILE
```
