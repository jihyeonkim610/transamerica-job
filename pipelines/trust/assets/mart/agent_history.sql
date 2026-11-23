/* @bruin
name: mart.agent_history
type: duckdb.sql
description: How each crew member's past runs ended, plus their habits (texts to police, share demands).
materialization:
  type: table
depends:
  - raw.decision_log
  - staging.crew_status
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
