# Writing notes

How these lessons should be built. Derived from Tutorial 04, which got it wrong.

## Tutorial vs. learning material

A tutorial transfers a **result** — friction is a defect, the author owns the outcome.
Learning material transfers **capability** — friction is the mechanism, the reader owns it.

They're inverted with respect to difficulty, not points on a scale. Every lesson here is
both: the rocket has to fly, and the math has to change you. Decide which one each
*section* is before writing it.

Failure modes are asymmetric. A too-hard tutorial fails loudly — you get stuck and complain.
Too-easy learning material fails silently: it reads well, feels like understanding, and
produces no ability. Fluency is not comprehension, and you can't detect this by rereading.

## Classify sections before writing prose

Per section: **type**, **what the reader can do after it**, and for tasks, **which moves it needs**.

- **Worked example** — teaches a *move*.
- **Task** — asks the reader to *select and compose* moves already demonstrated.
- **Explanation** — why this matters, what it means.
- **Reference** — lookup. Inert until the reader has a question.

**Rule:** every move a task needs must be discharged by a prior worked example.

**The tell:** if writing the task requires putting the hint in the prompt, it's a worked
example. Choosing which tool applies *is* the skill — name it and you've done the only
interesting step, leaving arithmetic dressed as an exercise.

**Budget:** a page supports two or three real tasks. More than that and they soften into
ritual, because you can't afford genuine difficulty six times. Worked examples should
outnumber tasks several to one.

## Sequence by motivation, not logic

Logical dependency and motivational dependency give different orders. Check the second one.

**Test:** if you can't state — in the reader's words, at the moment they arrive — the question
a section answers, it's misplaced, not badly written. The previous section is responsible for
planting that question.

Reference goes late, or to a sidebar. Tools *available* ≠ tools *read first*; front-loading
reference makes the reader memorize on faith.

Work without a why spends the reader's interest, which is the scarce resource. That's the
real cost of getting this wrong — not being wrong, but being expensive.

## Voice

Standalone, always. Someone who wasn't in the conversation is the only reader.

- No conversation artifacts: "since you asked", "you said", "the exercise you wanted".
- No changelog. The reader doesn't know there was a previous draft.
- Generic-you ("your rocket") is fine. Specific-you — a reader with a known history and
  known gaps — is not.
- Don't narrate the pedagogy. The structure should work without describing itself.
- Reference needs no justification for existing. Attaching one tells the reader you assume
  they've forgotten it.

## Baseline

Algebra. Trig, calculus and vector math are supplied as tools, then used. Any identity a
derivation leans on is stated explicitly, by name, before it's needed. Prefer the tool with
the smaller prerequisite set — the dot product over trig identities — even when the other is
the textbook route.

Every derived quantity comes with how to get it out of kOS. State the dimensionality.
