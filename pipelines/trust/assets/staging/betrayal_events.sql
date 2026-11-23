/* @bruin
name: staging.betrayal_events
type: duckdb.sql
owner: jihyeonkim610
tags: ["transamerica-job", "staging"]
description: |
  One row per "who did what to whom" in past runs.
  betrayer = the one who acted, victim = the one it was done to.
  known = whether the victim could know about it (secret tips only count as known if the informant was exposed in that run).
  weight > 0 hurts trust, weight < 0 builds trust.
    secret_tip            3   the informant texted the police
    exposed_as_informant  5   the crew found out who the informant was
    left_behind           2   escaped in the same moment a crewmate got arrested
    greedy_share_demand   1   asked for 35% or more of the loot in a run
    escaped_together     -2   both got away in the same run
materialization:
  type: table
depends:
  - raw.decision_log
  - staging.crew_status
columns:
  - name: run_id
    type: varchar
    description: ID of the run the event happened in
    checks:
      - name: not_null
  - name: scene
    type: integer
    description: Scene the event happened in
  - name: betrayer
    type: varchar
    description: Who acted (for escaped_together, the crewmate who got away too)
    checks:
      - name: accepted_values
        value: ["Ruby", "Sky", "Sunny", "Mint"]
  - name: victim
    type: varchar
    description: Who it was done to, i.e. whose trust it changes
    checks:
      - name: accepted_values
        value: ["Ruby", "Sky", "Sunny", "Mint"]
  - name: event_type
    type: varchar
    description: Kind of event
    checks:
      - name: accepted_values
        value: ["secret_tip", "exposed_as_informant", "left_behind", "greedy_share_demand", "escaped_together"]
  - name: known
    type: boolean
    description: Whether the victim could know about it
    checks:
      - name: not_null
  - name: weight
    type: double
    description: Trust impact; above 0 hurts trust, below 0 builds it
    checks:
      - name: min
        value: -2
      - name: max
        value: 5
  - name: detail
    type: varchar
    description: Human-readable detail, e.g. the text of a secret tip
custom_checks:
  - name: nobody betrays themselves
    query: SELECT count(*) FROM staging.betrayal_events WHERE betrayer = victim
    value: 0
@bruin */

WITH crew AS (
  SELECT DISTINCT run_id, speaker AS name FROM raw.decision_log WHERE kind = 'decision'
),
changes AS (
  SELECT * FROM staging.crew_status WHERE status <> prev_status
),
exposed_runs AS (
  SELECT DISTINCT run_id, name FROM staging.crew_status WHERE status = 'exposed'
),
final AS (
  SELECT run_id, name, arg_max(status, step) AS final_status, max(scene) AS scene
  FROM staging.crew_status
  GROUP BY run_id, name
),
tips AS (
  SELECT d.run_id, d.scene, d.speaker AS betrayer, c.name AS victim, 'secret_tip' AS event_type,
         (e.name IS NOT NULL) AS known, 3.0::DOUBLE AS weight, d.secret_tip AS detail
  FROM raw.decision_log d
  JOIN crew c ON c.run_id = d.run_id AND c.name <> d.speaker
  LEFT JOIN exposed_runs e ON e.run_id = d.run_id AND e.name = d.speaker
  WHERE d.kind = 'decision' AND d.secret_tip IS NOT NULL
),
exposed AS (
  SELECT ch.run_id, ch.scene, ch.name, c.name, 'exposed_as_informant', TRUE, 5.0::DOUBLE,
         ch.name || '''s cover was blown: working with the police'
  FROM changes ch
  JOIN crew c ON c.run_id = ch.run_id AND c.name <> ch.name
  WHERE ch.status = 'exposed'
),
left_behind AS (
  SELECT a.run_id, a.scene, a.name, b.name, 'left_behind', TRUE, 2.0::DOUBLE,
         a.name || ' escaped while ' || b.name || ' was arrested'
  FROM changes a
  JOIN changes b ON a.run_id = b.run_id AND a.step = b.step AND a.name <> b.name
  WHERE a.status = 'escaped' AND b.status = 'captured'
),
greed AS (
  SELECT d.run_id, max(d.scene), d.speaker, c.name, 'greedy_share_demand', TRUE, 1.0::DOUBLE,
         d.speaker || ' asked for up to ' || max(d.share_wanted) || '% of the loot'
  FROM raw.decision_log d
  JOIN crew c ON c.run_id = d.run_id AND c.name <> d.speaker
  WHERE d.kind = 'decision'
  GROUP BY d.run_id, d.speaker, c.name
  HAVING max(d.share_wanted) >= 35
),
together AS (
  SELECT a.run_id, greatest(a.scene, b.scene), b.name, a.name, 'escaped_together', TRUE, -2.0::DOUBLE,
         a.name || ' and ' || b.name || ' both got away'
  FROM final a
  JOIN final b ON a.run_id = b.run_id AND a.name <> b.name
  WHERE a.final_status = 'escaped' AND b.final_status = 'escaped'
)
SELECT * FROM tips
UNION ALL SELECT * FROM exposed
UNION ALL SELECT * FROM left_behind
UNION ALL SELECT * FROM greed
UNION ALL SELECT * FROM together
