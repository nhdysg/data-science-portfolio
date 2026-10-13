-- Split every performer credit into individual names and tag K-pop credits.
-- "TOMORROW X TOGETHER" is renamed first so the " X " separator does not split it.
CREATE OR REPLACE TABLE credit_tokens AS
WITH performers AS (
    SELECT credit, min(chart_week) AS first_week
    FROM entries
    GROUP BY credit
)
SELECT
    p.credit,
    p.first_week,
    trim(tok) AS token
FROM performers p,
     unnest(string_split_regex(
         replace(p.credit, 'TOMORROW X TOGETHER', 'TXT'),
         '\s+(?:&|Featuring|featuring|With|X|x|And)\s+|,\s+|:\s+'
     )) AS t(tok);

CREATE OR REPLACE TABLE performer_tags AS
WITH matched AS (
    SELECT
        c.credit,
        c.token,
        k.act_family,
        k.segment
    FROM credit_tokens c
    LEFT JOIN artists k
           ON k.credit_name = c.token
          AND c.first_week >= k.valid_from
)
SELECT
    credit,
    count(act_family) > 0                                         AS kpop,
    -- the soundtrack outranks a Korean act, which outranks KATSEYE
    CASE WHEN bool_or(segment = 'kdh')     THEN 'KPop Demon Hunters'
         WHEN bool_or(segment = 'korean')  THEN 'Korean act'
         WHEN bool_or(segment = 'us_made') THEN 'KATSEYE'
    END                                                           AS segment,
    min(act_family)                                               AS act_family,
    -- a credited name outside the K-pop list means a cross-market collaboration
    count(act_family) > 0 AND count(*) FILTER (WHERE act_family IS NULL) > 0 AS western_collab
FROM matched
GROUP BY credit;
