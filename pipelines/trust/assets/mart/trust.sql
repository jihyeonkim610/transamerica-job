/* @bruin
name: mart.trust
type: duckdb.sql
description: |
  The trust table: one row for every pair of crew members (truster -> trustee).
  trust_score starts at 70 and moves with the weight of every KNOWN event (6 points per weight point), kept between 0 and 100.
  secret_tips counts the informant's texts to the police even when nobody found out; only the informant is told about those.
materialization:
  type: table
depends:
  - raw.decision_log
  - staging.betrayal_events
columns:
  - name: trust_score
    type: integer
    checks:
      - name: not_null
@bruin */

WITH crew_runs AS (
  SELECT DISTINCT run_id, speaker AS name FROM raw.decision_log WHERE kind = 'decision'
),
crew AS (
  SELECT DISTINCT name FROM crew_runs
),
pairs AS (
  SELECT a.name AS truster, b.name AS trustee FROM crew a CROSS JOIN crew b WHERE a.name <> b.name
),
shared AS (
  SELECT a.name AS truster, b.name AS trustee, count(DISTINCT a.run_id) AS runs_together
  FROM crew_runs a JOIN crew_runs b ON a.run_id = b.run_id AND a.name <> b.name
  GROUP BY 1, 2
)
SELECT
  p.truster,
  p.trustee,
  coalesce(s.runs_together, 0)                                                     AS runs_together,
  count(e.event_type) FILTER (WHERE e.known AND e.weight > 0)                      AS known_betrayals,
  count(e.event_type) FILTER (WHERE e.event_type = 'secret_tip')                   AS secret_tips,
  count(DISTINCT e.run_id) FILTER (WHERE e.event_type = 'exposed_as_informant')    AS times_exposed,
  count(e.event_type) FILTER (WHERE e.event_type = 'left_behind')                  AS times_left_behind,
  count(e.event_type) FILTER (WHERE e.event_type = 'greedy_share_demand')          AS greedy_runs,
  count(e.event_type) FILTER (WHERE e.event_type = 'escaped_together')             AS escaped_together,
  CAST(greatest(0, least(100, 70 - 6 * coalesce(sum(e.weight) FILTER (WHERE e.known), 0))) AS INTEGER) AS trust_score
FROM pairs p
LEFT JOIN shared s USING (truster, trustee)
LEFT JOIN staging.betrayal_events e ON e.victim = p.truster AND e.betrayer = p.trustee
GROUP BY p.truster, p.trustee, s.runs_together
ORDER BY p.truster, p.trustee
