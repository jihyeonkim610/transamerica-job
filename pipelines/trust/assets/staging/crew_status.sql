/* @bruin
name: staging.crew_status
type: duckdb.sql
description: |
  Each crew member's status (active, hiding, escaped, captured, exposed) after every narrator step,
  next to the status they had just before. Read from the "status_after" column, e.g. "Ruby=active Sky=escaped".
materialization:
  type: table
depends:
  - raw.decision_log
@bruin */

WITH pairs AS (
  SELECT run_id, scene, step, kind, unnest(string_split(trim(status_after), ' ')) AS pair
  FROM raw.decision_log
  WHERE kind IN ('narration', 'ending') AND coalesce(status_after, '') <> ''
)
SELECT
  run_id,
  scene,
  step,
  kind,
  split_part(pair, '=', 1) AS name,
  split_part(pair, '=', 2) AS status,
  lag(split_part(pair, '=', 2), 1, 'active')
    OVER (PARTITION BY run_id, split_part(pair, '=', 1) ORDER BY step) AS prev_status
FROM pairs
WHERE pair LIKE '%=%'
