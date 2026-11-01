-- Esquema del enunciat amb els tipus de l'exercici 3.
-- Ús: psql -v schema=<nom> -f 01_schema.sql
-- PostgreSQL no té TINYINT: season passa a SMALLINT (2 B en lloc d'1 B).
-- Els noms de taula segueixen les queries de l'enunciat (CUSTOMERS, VIEWS).

SET client_min_messages = warning;
DROP SCHEMA IF EXISTS :schema CASCADE;
CREATE SCHEMA :schema;
SET search_path TO :schema;

CREATE TABLE customers (
    cid           INT PRIMARY KEY,
    subscription  CHAR(7),
    city          CHAR(10),
    timeOfSubs    DATE,
    name          CHAR(20),
    goldCustomer  BOOLEAN
);

CREATE TABLE views (
    viewID        INT PRIMARY KEY,
    custID        INT REFERENCES customers(cid),
    seriesID      CHAR(20) NOT NULL,
    season        SMALLINT,
    episode       SMALLINT,
    startingTime  CHAR(5),
    endingTime    CHAR(5)
);
