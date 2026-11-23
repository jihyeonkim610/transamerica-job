/* @bruin
name: export.trust_json
type: duckdb.sql
description: |
  Writes trust.json next to index.html. Before each run the page reads it and gives every agent
  its own memories: how much it trusts each crewmate and why, and how its past runs ended.
depends:
  - mart.trust
  - mart.agent_history
  - mart.run_summary
@bruin */

COPY (
  SELECT
    CAST(now() AS VARCHAR)                                                   AS generated_at,
    (SELECT count(*) FROM mart.run_summary)                                  AS runs,
    (SELECT list(t ORDER BY t.truster, t.trustee) FROM mart.trust t)         AS trust,
    (SELECT list(h ORDER BY h.name) FROM mart.agent_history h)               AS history,
    (SELECT list(r ORDER BY r.started_at DESC)
       FROM (SELECT run_id, CAST(started_at AS VARCHAR) AS started_at, scenes, ending_title, final_statuses, loot, finished
             FROM mart.run_summary ORDER BY started_at DESC LIMIT 5) r)      AS recent_runs
) TO 'trust.json' (FORMAT json);
