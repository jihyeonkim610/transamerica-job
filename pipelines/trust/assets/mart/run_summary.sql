/* @bruin
name: mart.run_summary
type: duckdb.sql
owner: jihyeonkim610
tags: ["transamerica-job", "mart"]
description: One row per saved run, with how it ended.
materialization:
  type: table
depends:
  - raw.decision_log
columns:
  - name: run_id
    type: varchar
    description: ID of the run
    primary_key: true
    checks:
      - name: not_null
      - name: unique
  - name: started_at
    type: timestamptz
    description: When the run started
  - name: scenes
    type: integer
    description: Number of scenes played
    checks:
      - name: min
        value: 0
      - name: max
        value: 10
  - name: ending_title
    type: varchar
    description: Title the narrator gave the ending (empty if the run was stopped)
  - name: final_statuses
    type: varchar
    description: Everyone's status at the end, e.g. "Ruby=escaped Sky=captured"
  - name: loot
    type: bigint
    description: Money taken in dollars
    checks:
      - name: non_negative
  - name: finished
    type: boolean
    description: Whether the run reached an ending
  - name: is_demo
    type: boolean
    description: True for demo runs without AI
custom_checks:
  - name: finished runs have an ending title
    query: SELECT count(*) FROM mart.run_summary WHERE finished AND coalesce(ending_title, '') = ''
    value: 0
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
