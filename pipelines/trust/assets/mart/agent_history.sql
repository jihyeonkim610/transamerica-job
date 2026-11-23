/* @bruin
name: mart.agent_history
type: duckdb.sql
owner: jihyeonkim610
tags: ["transamerica-job", "mart", "agent-memory"]
description: How each crew member's past runs ended, plus their habits (texts to police, share demands).
materialization:
  type: table
depends:
  - raw.decision_log
  - staging.crew_status
columns:
  - name: name
    type: varchar
    description: Crew member
    primary_key: true
    checks:
      - name: not_null
      - name: unique
      - name: accepted_values
        value: ["Ruby", "Sky", "Sunny", "Mint"]
  - name: runs
    type: integer
    description: Saved runs this crew member played in
    checks:
      - name: positive
  - name: escaped
    type: integer
    description: Runs that ended with them escaped
    checks:
      - name: non_negative
  - name: captured
    type: integer
    description: Runs that ended with them arrested
    checks:
      - name: non_negative
  - name: exposed
    type: integer
    description: Runs that ended with their cover blown (informant only)
    checks:
      - name: non_negative
  - name: still_in_city
    type: integer
    description: Runs that ended with them still active or hiding
    checks:
      - name: non_negative
  - name: tips_sent
    type: integer
    description: Secret texts to the police over all runs
    checks:
      - name: non_negative
  - name: avg_share_wanted
    type: integer
    description: Average loot share asked for, in percent
  - name: max_share_wanted
    type: integer
    description: Largest loot share asked for, in percent
custom_checks:
  - name: endings never exceed runs played
    query: SELECT count(*) FROM mart.agent_history WHERE escaped + captured + exposed + still_in_city > runs
    value: 0
  - name: only the informant texts the police
    query: SELECT count(*) FROM mart.agent_history WHERE name <> 'Mint' AND tips_sent > 0
    value: 0
@bruin */

WITH final AS (
  SELECT run_id, name, arg_max(status, step) AS final_status
  FROM staging.crew_status
  GROUP BY run_id, name
),
decisions AS (
  SELECT
    speaker                                        AS name,
    count(DISTINCT run_id)                         AS runs,
    count(*) FILTER (WHERE secret_tip IS NOT NULL) AS tips_sent,
    CAST(round(avg(share_wanted)) AS INTEGER)      AS avg_share_wanted,
    max(share_wanted)                              AS max_share_wanted
  FROM raw.decision_log
  WHERE kind = 'decision'
  GROUP BY speaker
)
SELECT
  d.name,
  d.runs,
  count(f.run_id) FILTER (WHERE f.final_status = 'escaped')               AS escaped,
  count(f.run_id) FILTER (WHERE f.final_status = 'captured')              AS captured,
  count(f.run_id) FILTER (WHERE f.final_status = 'exposed')               AS exposed,
  count(f.run_id) FILTER (WHERE f.final_status IN ('active', 'hiding'))   AS still_in_city,
  d.tips_sent,
  d.avg_share_wanted,
  d.max_share_wanted
FROM decisions d
LEFT JOIN final f ON f.name = d.name
GROUP BY d.name, d.runs, d.tips_sent, d.avg_share_wanted, d.max_share_wanted
ORDER BY d.name
