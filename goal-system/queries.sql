-- DuckDB over the goal-system logs (jsonl reads are native)
-- usage: just query          then e.g.:  SELECT * FROM pending;

CREATE OR REPLACE VIEW indications AS SELECT * FROM read_json_auto('indications.jsonl', format='newline_delimited');
CREATE OR REPLACE VIEW approvals   AS SELECT * FROM read_json_auto('approvals.jsonl',   format='newline_delimited');
CREATE OR REPLACE VIEW runs        AS SELECT * FROM read_json_auto('runs.jsonl',        format='newline_delimited');
CREATE OR REPLACE VIEW gap_events  AS SELECT * FROM read_json_auto('gaps.jsonl',        format='newline_delimited');
CREATE OR REPLACE VIEW ledger      AS SELECT * FROM read_json_auto('ledger.jsonl',      format='newline_delimited');

-- latest verdict per indication (append-only ⇒ last event wins)
CREATE OR REPLACE VIEW verdict AS
  SELECT indication, arg_max(verdict, at) AS verdict, max(at) AS at
  FROM approvals GROUP BY indication;

-- the three states
CREATE OR REPLACE VIEW pending AS
  SELECT i.id, i.kind, i.node, i.at
  FROM indications i LEFT JOIN verdict v ON i.id = v.indication
  WHERE v.verdict IS NULL;

-- latest run per solution
CREATE OR REPLACE VIEW latest_runs AS
  SELECT * FROM runs QUALIFY row_number() OVER
    (PARTITION BY solution_id ORDER BY finished_at DESC) = 1;

-- pass rate per solution
CREATE OR REPLACE VIEW solution_health AS
  SELECT solution_id,
         count(*) AS n_runs,
         sum(CASE WHEN status = 'passed' THEN 1 ELSE 0 END) AS n_passed,
         max(finished_at) AS last_run
  FROM runs GROUP BY solution_id ORDER BY solution_id;

-- the honesty queries (need .seeds/):
-- failing goals with no open seed  → unaddressed problems
-- open seeds pointing at green goals → possibly unnecessary work
-- closed seeds whose goal is still red → claimed done, not verified
