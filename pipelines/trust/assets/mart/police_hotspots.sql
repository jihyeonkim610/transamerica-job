/* @bruin
name: mart.police_hotspots
type: duckdb.sql
description: |
  Where the police set up roadblocks in past runs, as a share of all scenes played.
  Read from the "roadblocks" column of each scene's world-event row (place keys separated by spaces).
materialization:
  type: table
depends:
  - raw.decision_log
  - reference.places
columns:
  - name: place_key
    type: varchar
    checks:
      - name: not_null
      - name: unique
  - name: share_of_scenes
    type: double
    checks:
      - name: min
        value: 0
      - name: max
        value: 1
@bruin */

WITH scenes AS (
  SELECT run_id, scene, roadblocks
  FROM raw.decision_log
  WHERE kind = 'event'
),
blocks AS (
  SELECT run_id, scene, unnest(string_split(trim(roadblocks), ' ')) AS place_key
  FROM scenes
  WHERE coalesce(trim(roadblocks), '') <> ''
),
total AS (
  SELECT count(*) AS scenes FROM scenes
)
SELECT
  b.place_key,
  coalesce(p.place_name, b.place_key)               AS place_name,
  count(*)                                          AS scenes_with_police,
  count(DISTINCT b.run_id)                          AS runs_with_police,
  round(count(*) / greatest(max(t.scenes), 1), 2)   AS share_of_scenes
FROM blocks b
CROSS JOIN total t
LEFT JOIN reference.places p USING (place_key)
WHERE b.place_key <> ''
GROUP BY b.place_key, p.place_name
ORDER BY scenes_with_police DESC
