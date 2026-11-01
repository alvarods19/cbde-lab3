-- Dades exactes de l'enunciat (4 + 11 tuples).
-- Ús: psql -v schema=paper -f 02_data_paper.sql

SET search_path TO :schema;

INSERT INTO customers VALUES
    (1, 'Regular', 'Barcelona', '2024-01-01', 'Oscar R.',  false),
    (2, 'Regular', 'Barcelona', '2024-01-01', 'Marc M.',   false),
    (3, 'Regular', 'Barcelona', '2024-01-01', 'Esther S.', false),
    (4, 'Plus',    'Barcelona', '2024-01-01', 'Anna Q.',   true);

INSERT INTO views VALUES
    ( 1, 1, 'Breaking Bad',   7,  4, 'BoE',   'EoE'),
    ( 2, 1, 'Breaking Bad',   7,  5, 'BoE',   '21:45'),
    ( 3, 2, 'Vikings',        4,  1, 'BoE',   'EoE'),
    ( 4, 2, 'Vikings',        4,  2, 'BoE',   'EoE'),
    ( 5, 2, 'Vikings',        4,  3, 'BoE',   'EoE'),
    ( 6, 4, 'The Good Place', 2, 10, 'BoE',   'EoE'),
    ( 7, 1, 'Breaking Bad',   7,  5, '21:45', 'EoE'),
    ( 8, 3, 'Kaos',           1,  1, 'BoE',   '12:57'),
    ( 9, 1, 'Dirk Gently',    1,  1, 'BoE',   '6:02'),
    (10, 1, 'Breaking Bad',   7,  6, 'BoE',   'EoE'),
    (11, 1, 'Breaking Bad',   7,  7, 'BoE',   'EoE');
