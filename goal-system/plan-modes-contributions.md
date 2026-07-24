# Plan v2: schema for goals, relations, candidates, indications — and the prompt

Status: **proposal only** — nothing implemented, nothing committed.
Revised 2026-07-23 after review; v1's mermaid procedure chart is gone (too
mechanical, not natural enough) and avoid-mode machinery is simplified.
Bibliography stays in `references.bib` — the ideas survive; the flowchart
doesn't.

Two deliverables, in order of importance:

1. **The prompt** — the session protocol that governs discovery conversations
   (this is where the real failure happened: not knowing a conversation
   wasn't over).
2. **The schema** — goals with honest modes, goal↔goal relations, and a
   separate home for candidates and indications.

---

## 1. The prompt (GOALS.md session protocol, rewritten)

The current protocol tells Claude what to *emit* (candidate YAML, gap
questions). It says nothing about how to *converse*, so the model defaults to
its training: produce artifacts as soon as production is possible. The
revised protocol governs the conversation itself:

**Discovery mode is a state, and it is open until the human closes it.**

- While open: no files are written. Proposals, labels, and connections live
  in the chat. Receiving answers is not closure — answers usually open
  threads.
- The model's job while open: ask questions that walk toward *fundamental
  goals* — the ones whose "why?" comes back **"it just is."** That answer
  shape is the key indicator. Fundamental goals define value; they are what
  a business communicates with and what satisfaction is measured against —
  they matter more than any individual task-goal extracted along the way.
- Question repertoire (from the survey, used naturally — not as a flowchart):
  why is that important? (keeney1992value) · what would happen if you
  couldn't? (reynolds1988laddering) · what would it mean if that were true?
  (beck1979cognitive) · tell me about the last time this happened
  (critical incident) · here's my label — is that your meaning?
  (reflect-confirm, MI) · which two of these are alike? (kelly1955psychology)
- The model may *propose* closure ("this thread reads saturated — close,
  park, or keep digging?") but only the human closes (akao1991hoshin,
  catchball). Root recognition works the same way: the model may notice
  "it just is" talk, only the human confirms a fundamental goal.
- Imperfection is expected and acceptable. The transcript is the safety net:
  everything lands in corpus, so anything missed can be re-mined.

## 2. The schema

### 2a. Modes, kept simple

- `maintain`: every run in the trailing window passed.
- `avoid`: **anti-maintain** — every run in the trailing window found no
  violation. Same fold, opposite polarity of what a run means. No extra
  TTL rules, no sampling-density lint: how often to look is a property of
  the individual goal, decided when its solution is written, not a
  system-level metric.
- `achieve`: at least one passing run exists. Sticky.
- No `window` declared → today's MVP fold (latest run + TTL). No flag day.

Implementation is read-side only in `goalc.py` (keep full run history per
solution, dispatch fold on mode). Schema untouched — `mode` and `window`
already exist.

### 2b. Goals relate to goals: helps / hurts / breaks

Two ways a relation enters, both cheap:

1. **Through discussion** — the connection is spoken: "I want my data backed
   up *because* it's important that my family can access it." The helps
   edge is implicit in the utterance; the span is its warrant (rule 3
   unchanged).
2. **By sweep** — candidates arrive unconnected, and that's fine. When a new
   goal enters, walk the existing goals one by one and ask: does this
   connect? Conflict? Nothing? Small graphs make this a small job; no
   machinery beyond "compare the new one against the list."

Edge schema (expand-only, on goals):

```yaml
relates:
  - to: g-other
    effect: helps | hurts | breaks
    status: candidate | confirmed
    derived_from: [{quote, source, role}]   # warrant, or the indication(s) below
```

Relations never propagate fold status — a goal is not red because a green
goal hurts it. What conflicts *do* produce: visibility. A `tensions` view
listing hurts/breaks pairs where the hurting goal is currently green.

### 2c. Candidates and indications — the new focus

**Indications** are the missing primitive: transcript-derived signals that
something is probably true, before anyone confirms it. Weaker than facts,
stronger than nothing, append-only like everything else observed.

```
indications.jsonl   (append-only)
{id, at, kind, span: {quote, source}, ...}

kind: relates      {goal, to, effect: helps|hurts|breaks}
kind: fundamental  {goal}          # an "it just is" moment in the transcript
kind: same|refines|motivates|contradicts {goal, other}   # rule-6 verdicts as data
```

Indications accumulate. Three transcripts each hinting that g-x helps g-y is
three indications; the edge itself still enters as a candidate and is
confirmed only by the human. Indications ARE the provenance trail for
candidacy — they answer "why did this candidate exist at all?"

**Candidates** move out of `goals.yaml` into their own file:

```
candidates.yaml     machine-writable, freely rewritable, disposable
goals.yaml          human-promoted structure only — every node confirmed
```

Promotion = the human moves a block from candidates.yaml to goals.yaml and
commits (unchanged ritual, cleaner homes). A discarded candidate just gets
deleted from candidates.yaml — its indications survive in the log, so the
record of "this was considered and why" costs nothing to keep. (This gives
the useful part of IBIS — rejected positions remain knowledge — without
adopting IBIS.)

Fundamental goals get marked in structure once confirmed:

```yaml
goals:
  - id: g-x
    fundamental: true    # confirmed root — "it just is"; defines value
```

### 2d. Provenance to evidence, unbroken

The chain the schema must keep walkable end to end:

```
utterance (corpus) → indication → candidate → confirmed goal
                                             → relates edge
confirmed goal → solution → runs → fold → status
```

Prerequisite that makes the whole chain trustworthy: the **warrant lint** —
every quote in `derived_from` (and every indication span) must literally
occur in its named source file. Deterministic, cheap, closes the one channel
where an extractor can forge provenance. New self-hosting leaf under
`g-provenance`.

## Sequencing

1. Warrant lint (self-contained; strengthens an existing confirmed goal)
2. Prompt rewrite in GOALS.md (no code)
3. candidates.yaml split + indications.jsonl (schema homes; migrate current
   candidate blocks out of goals.yaml)
4. Mode folds, simple version (read-side goalc change + selftest fixture)
5. `relates` edges + tensions view

Each step is its own commit with its own corpus provenance, when approved.

## Open questions (carried, not resolved)

- Saturation: is "no new indications in recent turns" a good enough signal
  for the model to *propose* closure? (Closure itself stays human.)
- Do parked threads need a home, or is the corpus + open indications enough
  for the next session to pick them up?
- Subject induction remains the weakest link — triads discriminate given
  elements; nothing yet generates elements.
