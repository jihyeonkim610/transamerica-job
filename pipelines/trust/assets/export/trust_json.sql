/* @bruin
name: export.trust_json
type: duckdb.sql
owner: jihyeonkim610
tags: ["transamerica-job", "export", "agent-memory"]
description: |
  Writes trust.json next to index.html. Before each run the page reads it and gives every agent
  its own memories: how much it trusts each crewmate and why, and how its past runs ended.
depends:
  - mart.trust
  - mart.agent_history
  - mart.run_summary
  - mart.place_stats
  - mart.police_hotspots
custom_checks:
  - name: every trust row has a score before export
    query: SELECT count(*) FROM mart.trust WHERE trust_score IS NULL
    value: 0
  - name: every exit is known before export
    query: SELECT count(*) FROM mart.place_stats WHERE is_exit IS NULL
    value: 0
@bruin */

COPY (
  SELECT
    CAST(now() AS VARCHAR)                                                   AS generated_at,
    (SELECT count(*) FROM mart.run_summary)                                  AS runs,
    (SELECT list(t ORDER BY t.truster, t.trustee) FROM mart.trust t)         AS trust,
    (SELECT list(h ORDER BY h.name) FROM mart.agent_history h)               AS history,
    (SELECT list(r ORDER BY r.started_at DESC)
       FROM (SELECT run_id, CAST(started_at AS VARCHAR) AS started_at, scenes, ending_title, final_statuses, loot, finished
             FROM mart.run_summary ORDER BY started_at DESC LIMIT 5) r)      AS recent_runs,
    (SELECT list(p ORDER BY p.is_exit DESC, p.place_name)
       FROM mart.place_stats p WHERE p.visits > 0)                           AS places,
    (SELECT list(h ORDER BY h.scenes_with_police DESC)
       FROM mart.police_hotspots h)                                          AS hotspots
) TO 'trust.json' (FORMAT json);
