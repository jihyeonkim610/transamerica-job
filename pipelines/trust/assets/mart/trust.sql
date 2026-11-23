/* @bruin
name: mart.trust
type: duckdb.sql
owner: jihyeonkim610
tags: ["transamerica-job", "mart", "agent-memory"]
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
  - name: truster
    type: varchar
    description: The crew member whose trust this row describes
    primary_key: true
    checks:
      - name: not_null
      - name: accepted_values
        value: ["Ruby", "Sky", "Sunny", "Mint"]
  - name: trustee
    type: varchar
    description: The crew member being trusted (or not)
    primary_key: true
    checks:
      - name: not_null
      - name: accepted_values
        value: ["Ruby", "Sky", "Sunny", "Mint"]
  - name: runs_together
    type: integer
    description: How many saved runs both played in
    checks:
      - name: non_negative
  - name: known_betrayals
    type: integer
    description: Events the truster knows about that hurt trust
    checks:
      - name: non_negative
  - name: secret_tips
    type: integer
    description: The trustee's texts to the police in runs with the truster, found out or not
    checks:
      - name: non_negative
  - name: times_exposed
    type: integer
    description: Runs where the trustee was exposed as the police informant
    checks:
      - name: non_negative
  - name: times_left_behind
    type: integer
    description: Times the trustee escaped while the truster was being arrested
    checks:
      - name: non_negative
  - name: greedy_runs
    type: integer
    description: Runs where the trustee asked for 35% or more of the loot
    checks:
      - name: non_negative
  - name: escaped_together
    type: integer
    description: Runs where both got away
    checks:
      - name: non_negative
  - name: trust_score
    type: integer
    description: Trust from 0 (none) to 100 (complete); 70 means no history yet
    checks:
      - name: not_null
      - name: min
        value: 0
      - name: max
        value: 100
custom_checks:
  - name: one row per pair
    description: Every truster -> trustee pair appears exactly once.
    query: |
      SELECT count(*) FROM (
        SELECT truster, trustee FROM mart.trust GROUP BY 1, 2 HAVING count(*) > 1
      )
    value: 0
  - name: nobody rates themselves
    query: SELECT count(*) FROM mart.trust WHERE truster = trustee
    value: 0
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
