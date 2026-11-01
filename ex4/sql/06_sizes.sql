-- Mida real a PostgreSQL i estimació del sistema columnar amb la fórmula de l'exercici 3.
-- Columnar: D·s (diccionari) + R·4 (runs, ERI) + R·e (eValues), amb e = bytes per codificar D+1 valors
-- (1 B si D < 256, com a l'exercici 3; 2 B si no). Les runs es compten en l'ordre físic (viewID / cid).
SET search_path TO :schema;

\echo '--- Mida a PostgreSQL (pàgines de 8 KB)'
SELECT c.relname, c.reltuples::bigint AS tuples, c.relpages AS pages,
       pg_size_pretty(pg_relation_size(c.oid)) AS size,
       round(c.reltuples / NULLIF(c.relpages, 0)) AS tuples_per_page
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = :'schema' AND c.relkind IN ('r', 'i')
ORDER BY c.relname;

\echo '--- D i R per columna i estimació columnar (bytes)'
WITH v AS (
    SELECT viewID,
           (viewID       IS DISTINCT FROM lag(viewID)       OVER w)::int AS r_viewid,
           (custID       IS DISTINCT FROM lag(custID)       OVER w)::int AS r_custid,
           (seriesID     IS DISTINCT FROM lag(seriesID)     OVER w)::int AS r_seriesid,
           (season       IS DISTINCT FROM lag(season)       OVER w)::int AS r_season,
           (episode      IS DISTINCT FROM lag(episode)      OVER w)::int AS r_episode,
           (startingTime IS DISTINCT FROM lag(startingTime) OVER w)::int AS r_start,
           (endingTime   IS DISTINCT FROM lag(endingTime)   OVER w)::int AS r_end
    FROM views WINDOW w AS (ORDER BY viewID)
), c AS (
    SELECT (cid          IS DISTINCT FROM lag(cid)          OVER w)::int AS r_cid,
           (subscription IS DISTINCT FROM lag(subscription) OVER w)::int AS r_sub,
           (city         IS DISTINCT FROM lag(city)         OVER w)::int AS r_city,
           (timeOfSubs   IS DISTINCT FROM lag(timeOfSubs)   OVER w)::int AS r_time,
           (name         IS DISTINCT FROM lag(name)         OVER w)::int AS r_name,
           (goldCustomer IS DISTINCT FROM lag(goldCustomer) OVER w)::int AS r_gold
    FROM customers WINDOW w AS (ORDER BY cid)
), stats(tab, col, s, n, d, r) AS (
    SELECT 'views', 'viewID',       4, (SELECT count(*) FROM views), (SELECT count(DISTINCT viewID)       FROM views), (SELECT sum(r_viewid)   FROM v) UNION ALL
    SELECT 'views', 'custID',       4, (SELECT count(*) FROM views), (SELECT count(DISTINCT custID)       FROM views), (SELECT sum(r_custid)   FROM v) UNION ALL
    SELECT 'views', 'seriesID',    20, (SELECT count(*) FROM views), (SELECT count(DISTINCT seriesID)     FROM views), (SELECT sum(r_seriesid) FROM v) UNION ALL
    SELECT 'views', 'season',       1, (SELECT count(*) FROM views), (SELECT count(DISTINCT season)       FROM views), (SELECT sum(r_season)   FROM v) UNION ALL
    SELECT 'views', 'episode',      2, (SELECT count(*) FROM views), (SELECT count(DISTINCT episode)      FROM views), (SELECT sum(r_episode)  FROM v) UNION ALL
    SELECT 'views', 'startingTime', 5, (SELECT count(*) FROM views), (SELECT count(DISTINCT startingTime) FROM views), (SELECT sum(r_start)    FROM v) UNION ALL
    SELECT 'views', 'endingTime',   5, (SELECT count(*) FROM views), (SELECT count(DISTINCT endingTime)   FROM views), (SELECT sum(r_end)      FROM v) UNION ALL
    SELECT 'customers', 'cid',          4, (SELECT count(*) FROM customers), (SELECT count(DISTINCT cid)          FROM customers), (SELECT sum(r_cid)  FROM c) UNION ALL
    SELECT 'customers', 'subscription', 7, (SELECT count(*) FROM customers), (SELECT count(DISTINCT subscription) FROM customers), (SELECT sum(r_sub)  FROM c) UNION ALL
    SELECT 'customers', 'city',        10, (SELECT count(*) FROM customers), (SELECT count(DISTINCT city)         FROM customers), (SELECT sum(r_city) FROM c) UNION ALL
    SELECT 'customers', 'timeOfSubs',   4, (SELECT count(*) FROM customers), (SELECT count(DISTINCT timeOfSubs)   FROM customers), (SELECT sum(r_time) FROM c) UNION ALL
    SELECT 'customers', 'name',        20, (SELECT count(*) FROM customers), (SELECT count(DISTINCT name)         FROM customers), (SELECT sum(r_name) FROM c) UNION ALL
    SELECT 'customers', 'goldCustomer', 1, (SELECT count(*) FROM customers), (SELECT count(DISTINCT goldCustomer) FROM customers), (SELECT sum(r_gold) FROM c)
)
SELECT tab, col, n, d, r,
       n * s                                              AS row_bytes,
       d * s + r * 4 + r * CASE WHEN d < 256 THEN 1 ELSE 2 END AS col_bytes
FROM stats
ORDER BY tab DESC, col;
