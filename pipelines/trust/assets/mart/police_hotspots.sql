/* @bruin
name: mart.police_hotspots
type: duckdb.sql
owner: jihyeonkim610
tags: ["transamerica-job", "mart", "agent-learning"]
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
    description: Key of the place that had a roadblock
    primary_key: true
    checks:
      - name: not_null
      - name: unique
  - name: place_name
    type: varchar
    description: Name of the place
    checks:
      - name: not_null
  - name: scenes_with_police
    type: integer
    description: Scenes in which a roadblock stood there
    checks:
      - name: positive
  - name: runs_with_police
    type: integer
    description: Runs in which a roadblock stood there at some point
    checks:
      - name: positive
  - name: share_of_scenes
    type: double
    description: scenes_with_police / all scenes played
    checks:
      - name: min
        value: 0
      - name: max
        value: 1
custom_checks:
  - name: roadblocks only at known places
    query: SELECT count(*) FROM mart.police_hotspots WHERE place_key NOT IN (SELECT place_key FROM reference.places)
    value: 0
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
