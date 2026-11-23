/* @bruin
name: staging.crew_status
type: duckdb.sql
owner: jihyeonkim610
tags: ["transamerica-job", "staging"]
description: |
  Each crew member's status (active, hiding, escaped, captured, exposed) after every narrator step,
  next to the status they had just before. Read from the "status_after" column, e.g. "Ruby=active Sky=escaped".
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
  - name: step
    type: integer
    description: The narrator step this status was recorded at
    primary_key: true
    checks:
      - name: not_null
  - name: scene
    type: integer
    description: Scene number
  - name: kind
    type: varchar
    description: narration (end of a scene) or ending (end of the story)
    checks:
      - name: accepted_values
        value: ["narration", "ending"]
  - name: name
    type: varchar
    description: Crew member
    primary_key: true
    checks:
      - name: accepted_values
        value: ["Ruby", "Sky", "Sunny", "Mint"]
  - name: status
    type: varchar
    description: Status after this step
    checks:
      - name: accepted_values
        value: ["active", "hiding", "escaped", "captured", "exposed"]
  - name: prev_status
    type: varchar
    description: Status just before this step ("active" at the start of a run)
    checks:
      - name: accepted_values
        value: ["active", "hiding", "escaped", "captured", "exposed"]
custom_checks:
  - name: every status belongs to a loaded run
    query: SELECT count(*) FROM staging.crew_status WHERE run_id NOT IN (SELECT run_id FROM raw.decision_log)
    value: 0
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
