-- Dades aleatòries amb generate_series.
-- Ús: psql -v schema=large -v n_cust=10000 -v n_views=1000000 -f 03_data_synth.sql
-- VIEWS s'insereix ordenada per custID (com una projecció ordenada d'un sistema columnar):
-- dona runs llargues a custID i alta correlació per a l'índex de PostgreSQL.

SET search_path TO :schema;
SELECT setseed(0.42) \g /dev/null

INSERT INTO customers
SELECT c,
       CASE WHEN random() < 0.2 THEN 'Plus' ELSE 'Regular' END,
       (ARRAY['Barcelona','Madrid','Valencia','Sevilla','Bilbao',
              'Girona','Tarragona','Lleida','Zaragoza','Malaga'])[1 + floor(random() * 10)::int],
       DATE '2024-01-01' + floor(random() * 365)::int,
       'Customer ' || c,
       random() < 0.1
FROM generate_series(1, :n_cust) AS c;

INSERT INTO views
SELECT row_number() OVER (ORDER BY custID, r) AS viewID,
       custID, seriesID, season, episode, startingTime, endingTime
FROM (
    SELECT CASE WHEN g <= 5 THEN 1                       -- el client 1 sempre té vistes
                ELSE 1 + floor(random() * :n_cust)::int END AS custID,
           random() AS r,
           'Series ' || lpad((1 + floor(random() * 30)::int)::text, 2, '0') AS seriesID,
           1 + floor(random() * 8)::int  AS season,
           1 + floor(random() * 12)::int AS episode,
           CASE WHEN random() < 0.85 THEN 'BoE'
                ELSE lpad(floor(random() * 24)::text, 2, '0') || ':' || lpad(floor(random() * 60)::text, 2, '0') END AS startingTime,
           CASE WHEN random() < 0.85 THEN 'EoE'
                ELSE lpad(floor(random() * 24)::text, 2, '0') || ':' || lpad(floor(random() * 60)::text, 2, '0') END AS endingTime
    FROM generate_series(1, :n_views) AS g
) s
ORDER BY custID, r;
