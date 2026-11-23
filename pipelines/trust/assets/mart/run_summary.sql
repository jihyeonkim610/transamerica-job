/* @bruin
name: mart.run_summary
type: duckdb.sql
description: One row per saved run, with how it ended.
materialization:
  type: table
depends:
  - raw.decision_log
@bruin */

SELECT
  run_id,
  min(logged_at)                                                                AS started_at,
  max(scene)                                                                    AS scenes,
  max(action) FILTER (WHERE kind = 'ending')                                    AS ending_title,
  arg_max(status_after, step) FILTER (WHERE coalesce(status_after, '') <> '')   AS final_statuses,
  max(loot)                                                                     AS loot,
  bool_or(kind = 'ending')                                                      AS finished,
  bool_or(kind = 'run_start' AND note LIKE 'Demo run%')                         AS is_demo
FROM raw.decision_log
GROUP BY run_id
ORDER BY started_at
