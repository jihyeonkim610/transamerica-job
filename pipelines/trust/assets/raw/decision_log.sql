/* @bruin
name: raw.decision_log
type: duckdb.sql
owner: jihyeonkim610
tags: ["transamerica-job", "raw"]
description: |
  Every row of every saved run log in data/runs/*.csv, one row per logged step.
  data/runs/_header.csv (column names only) keeps this working before the first real run is saved.
  If the same run was saved twice, only one copy is kept.
materialization:
  type: table
columns:
  - name: run_id
    type: varchar
    description: ID of the run (start time, e.g. 20261123212622)
    primary_key: true
    checks:
      - name: not_null
  - name: step
    type: integer
    description: Order of the row inside its run, starting at 1
    primary_key: true
    checks:
      - name: not_null
      - name: positive
  - name: scene
    type: integer
    description: Scene number, 0 for the run start, then 1 to 10
    checks:
      - name: min
        value: 0
      - name: max
        value: 10
  - name: kind
    type: varchar
    description: What the row records
    checks:
      - name: accepted_values
        value: ["run_start", "event", "decision", "narration", "ending", "cutscene", "memory", "run_stopped", "error"]
  - name: speaker
    type: varchar
    description: Who acted (a crew member, Narrator, World, System or Cutscene)
  - name: move_to
    type: varchar
    description: Place the crew member decided to go to
  - name: escape_exit
    type: varchar
    description: The way out the crew member planned
  - name: share_wanted
    type: integer
    description: Percent of the loot the crew member asked for
    checks:
      - name: min
        value: 0
      - name: max
        value: 100
  - name: secret_tip
    type: varchar
    description: The informant's secret text to the police in this decision, if any
  - name: dice
    type: integer
    description: The d20 roll the narrator used for this decision
    checks:
      - name: min
        value: 1
      - name: max
        value: 20
  - name: status_after
    type: varchar
    description: Everyone's status after a narrator step, e.g. "Ruby=active Sky=escaped"
  - name: heat
    type: integer
    description: Police heat from 0 to 100 at that moment
    checks:
      - name: min
        value: 0
      - name: max
        value: 100
  - name: loot
    type: bigint
    description: Money taken so far in dollars
    checks:
      - name: non_negative
  - name: roadblocks
    type: varchar
    description: Place keys with a police roadblock at that moment, separated by spaces
custom_checks:
  - name: one row per run step
    description: The same (run_id, step) never appears twice, even if a run was saved twice.
    query: SELECT count(*) FROM (SELECT run_id, step FROM raw.decision_log GROUP BY 1, 2 HAVING count(*) > 1)
    value: 0
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
