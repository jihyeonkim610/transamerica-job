/* @bruin
name: mart.place_stats
type: duckdb.sql
description: |
  What the crew has learned about each place from past runs: how often someone headed there,
  how often that ended in an escape or an arrest, and how often it was the planned way out.
  The Driver gets this table as street knowledge, so escape routes shift toward what has worked.
materialization:
  type: table
depends:
  - raw.decision_log
  - staging.crew_status
  - reference.places
columns:
  - name: place_name
    type: varchar
    checks:
      - name: not_null
      - name: unique
  - name: escape_rate
    type: double
    checks:
      - name: min
        value: 0
      - name: max
        value: 1
  - name: arrest_rate
    type: double
    checks:
      - name: min
        value: 0
      - name: max
        value: 1
@bruin */

WITH decisions AS (
  SELECT run_id, scene, speaker, move_to, escape_exit
  FROM raw.decision_log
  WHERE kind = 'decision'
),
outcomes AS (   -- where a crew member was heading in the scene they escaped or were arrested
  SELECT d.move_to AS place_name, c.status
  FROM staging.crew_status c
  JOIN decisions d ON d.run_id = c.run_id AND d.scene = c.scene AND d.speaker = c.name
  WHERE c.status <> c.prev_status AND c.status IN ('escaped', 'captured')
),
visits AS (
  SELECT move_to AS place_name, count(*) AS visits, count(DISTINCT run_id) AS runs_visited
  FROM decisions GROUP BY 1
),
planned AS (
  SELECT escape_exit AS place_name, count(*) AS times_planned_as_exit
  FROM decisions WHERE coalesce(escape_exit, '') <> '' GROUP BY 1
),
results AS (
  SELECT place_name,
         count(*) FILTER (WHERE status = 'escaped')  AS escapes,
         count(*) FILTER (WHERE status = 'captured') AS arrests
  FROM outcomes GROUP BY 1
)
SELECT
  p.place_key,
  p.place_name,
  p.area,
  p.is_exit,
  coalesce(v.visits, 0)                                         AS visits,
  coalesce(v.runs_visited, 0)                                   AS runs_visited,
  coalesce(r.escapes, 0)                                        AS escapes,
  coalesce(r.arrests, 0)                                        AS arrests,
  coalesce(pl.times_planned_as_exit, 0)                         AS times_planned_as_exit,
  CASE WHEN coalesce(v.visits, 0) = 0 THEN NULL
       ELSE round(coalesce(r.escapes, 0) / v.visits, 2) END     AS escape_rate,
  CASE WHEN coalesce(v.visits, 0) = 0 THEN NULL
       ELSE round(coalesce(r.arrests, 0) / v.visits, 2) END     AS arrest_rate
FROM reference.places p
LEFT JOIN visits  v  USING (place_name)
LEFT JOIN results r  USING (place_name)
LEFT JOIN planned pl USING (place_name)
ORDER BY p.is_exit DESC, p.place_name
