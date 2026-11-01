-- Únic índex secundari: VIEWS(custID). VACUUM perquè el visibility map permeti Index Only Scan.
SET search_path TO :schema;
CREATE INDEX views_custid_idx ON views(custID);
VACUUM ANALYZE views;
