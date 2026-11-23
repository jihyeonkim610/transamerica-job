/* @bruin
name: raw.decision_log
type: duckdb.sql
description: |
  Every row of every saved run log in data/runs/*.csv, one row per logged step.
  data/runs/_header.csv (column names only) keeps this working before the first real run is saved.
  If the same run was saved twice, only one copy is kept.
materialization:
  type: table
columns:
  - name: run_id
    type: varchar
    checks:
      - name: not_null
  - name: step
    type: integer
    checks:
      - name: not_null
@bruin */

WITH src AS (
  SELECT *
  FROM read_csv('data/runs/*.csv', header = true, all_varchar = true, union_by_name = true, filename = true)
)
SELECT
  run_id,
  TRY_CAST(scene AS INTEGER)          AS scene,
  TRY_CAST(step AS INTEGER)           AS step,
  TRY_CAST("time" AS TIMESTAMPTZ)     AS logged_at,
  kind,
  speaker,
  role,
  location_before,
  move_to,
  escape_exit,
  escape_route,
  TRY_CAST(share_wanted AS INTEGER)   AS share_wanted,
  said,
  action,
  reason,
  NULLIF(secret_tip_to_police, '')    AS secret_tip,
  TRY_CAST(dice AS INTEGER)           AS dice,
  status_after,
  TRY_CAST(heat AS INTEGER)           AS heat,
  TRY_CAST(loot AS BIGINT)            AS loot,
  roadblocks,
  note,
  filename                            AS source_file
FROM src
WHERE coalesce(run_id, '') <> '' AND TRY_CAST(step AS INTEGER) IS NOT NULL
QUALIFY row_number() OVER (PARTITION BY run_id, TRY_CAST(step AS INTEGER) ORDER BY filename) = 1
