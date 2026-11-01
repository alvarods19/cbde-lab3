-- Resultat de Q1-Q4 (per comprovar-los amb l'exercici 2 a l'schema paper).
SET search_path TO :schema;
\echo '--- Q1'
SELECT DISTINCT seriesID FROM views WHERE custID = 1 ORDER BY 1;
\echo '--- Q2'
SELECT * FROM customers ORDER BY cid LIMIT 10;
\echo '--- Q3'
SELECT COUNT(*) FROM views WHERE custID = 1;
\echo '--- Q4'
SELECT custID, COUNT(seriesID) FROM views GROUP BY custID ORDER BY custID LIMIT 10;
