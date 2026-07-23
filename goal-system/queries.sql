-- run via `just query` (materializes goals.yaml → .goals.json first)

CREATE OR REPLACE VIEW goals     AS SELECT unnest(goals, recursive := true)     FROM read_json('.goals.json');
CREATE OR REPLACE VIEW solutions AS SELECT unnest(solutions, recursive := true) FROM read_json('.goals.json');
CREATE OR REPLACE VIEW runs      AS SELECT * FROM read_json_auto('runs.jsonl', format='newline_delimited');

-- latest run per solution (append-only ⇒ max finished_at wins)
CREATE OR REPLACE VIEW latest_runs AS
  SELECT * FROM runs QUALIFY row_number() OVER
    (PARTITION BY solution_id ORDER BY finished_at DESC) = 1;

-- staleness report: why is each leaf outdated?
SELECT s.id, r.status, r.finished_at,
       CASE WHEN r.solution_id IS NULL THEN 'never-run'
            WHEN now() - r.finished_at::timestamptz > interval '24 hours' THEN 'time-stale'
            ELSE 'fresh' END AS freshness
FROM solutions s LEFT JOIN latest_runs r ON r.solution_id = s.id;

-- the honesty queries (need .seeds/):
-- CREATE VIEW seeds AS SELECT * FROM read_json_auto('.seeds/issues.jsonl', format='newline_delimited');
-- failing goals with no open seed  → unaddressed problems
-- open seeds pointing at green goals → possibly unnecessary work
-- closed seeds whose goal is still red → claimed done, not verified
