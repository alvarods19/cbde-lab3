# Exercici 4 — Rendiment: orientat a files vs. orientat a columnes

**Cost considerat.** El cost d'una query és bàsicament E/S (pàgines o bytes llegits) més CPU (descomprimir i reconstruir tuples). La diferència clau és que una BD per files (PostgreSQL) sempre llegeix pàgines amb **tuples senceres**, encara que la query només faci servir una columna. En canvi, el nostre sistema columnar només llegeix les estructures (`dictionary`, `runs`, `eValues`) de les columnes que necessita, i sovint treballa sobre les dades comprimides.

**Validació.** Hem implementat l'esquema a PostgreSQL 18 amb els tipus de l'exercici 3 (`season` com a SMALLINT, perquè no hi ha TINYINT). L'hem provat amb tres jocs de dades:
- `paper`: les 4 + 11 tuples de l'enunciat;
- `small`: 1.000 clients i 10.000 vistes;
- `large`: 10.000 clients, 1.000.000 de vistes i 30 sèries, amb VIEWS ordenada per `custID`.

Per a cada query hem executat `EXPLAIN (ANALYZE, BUFFERS)` sense índexs secundaris i amb un sol índex a `views(custID)`. Els *buffers* són pàgines de 8 KB llegides i el temps és la mediana de 5 execucions amb la cache calenta. Per estimar el cost del columnar hem calculat la D i la R reals de cada columna i hi hem aplicat la fórmula de l'exercici 3 (`D·s + 5·R`, amb eValues de 2 B quan D > 255). Amb les dades `paper`, aquest càlcul reprodueix exactament les D, R i mides de l'exercici 3.

**Les dades de l'enunciat no permeten distingir res.** Amb `paper`, totes les queries llegeixen **1 pàgina** i triguen menys de 0,02 ms, tant amb índex com sense. Les taules caben en una pàgina, així que la diferència de bytes de l'exercici 3 (46 B de `custID` contra 451 B de VIEWS) no es nota. Per això la comparació es fa amb `large`, on VIEWS ocupa 9.346 pàgines (73 MB). Cada tupla ocupa uns 76 B en disc (unes 107 per pàgina), mentre que `custID` només n'ocupa 4: la ràtio de lectura efectiva d'una query que només necessita `custID` és d'un 5 %.

### Query 1 — `SELECT DISTINCT seriesID FROM views WHERE custID = 1`

- **Columnar** (pla de l'ex. 2): `Lookup` a `custID.dictionary`, `Iterate` sobre `custID.runs/eValues` (10.000 runs × 6 B ≈ 60 KB), i després `Reconstruct` només de `seriesID` i només de les 103 posicions que retorna `Iterate`. El `DISTINCT` es fa amb un HashSet sobre 103 valors. No es toca cap altra columna.
- **Files sense índex:** `Seq Scan on views` llegeix les 7 columnes de les 1.000.000 tuples per quedar-se'n amb 103 (`Rows Removed by Filter: 999897`), i després fa `Sort + Unique`. Són **9.346 pàgines i 24,3 ms**.
- **Files amb índex:** `Index Scan using views_custid_idx` + `HashAggregate` llegeix **4 pàgines** (0,035 ms). El predicat és molt selectiu (0,01 %) i les tuples del client 1 estan juntes, així que l'índex B-tree hi va directament.
- **Guanya el columnar** davant d'un recorregut complet de la taula (60 KB més unes poques pàgines de `seriesID`, contra 73 MB). Amb un índex molt selectiu, el sistema per files s'hi acosta i fins i tot el supera: el nostre `Iterate` recorre totes les runs de `custID`, mentre que el B-tree va directament a la clau. La diferència es manté si la query és menys selectiva o si l'índex no existeix.

### Query 2 — `SELECT * FROM customers`

- **Columnar:** es llegeixen les 6 columnes senceres (≈ 490 KB estimats amb la fórmula de l'exercici 3) i `Reconstruct` ha de recompondre 10.000 tuples a partir de 6 estructures diferents, és a dir, 60.000 valors descodificats amb `InverseLookUp` i aparellats per posició.
- **Files:** `Seq Scan on customers` llegeix **104 pàgines (832 KB) en 0,5 ms**. Les tuples ja estan guardades contigües i en el format que s'han de retornar: no hi ha cap descodificació ni reconstrucció. L'índex no hi aporta res (el pla és idèntic).
- **Guanya el sistema per files.** Quan es demanen totes les columnes de totes les files, el columnar estalvia poca E/S o cap: a l'exercici 3 ocupava més (196 B contra 184 B), i a `large` els ≈ 490 KB estimats contra 832 KB només es deuen al fet que PostgreSQL guarda capçaleres de tupla. A més, el columnar ha de llegir 6 estructures per separat i paga la reconstrucció. És el pitjor cas per a un sistema columnar.

### Query 3 — `SELECT COUNT(*) FROM views WHERE custID = 1`

- **Columnar:** `Lookup` + `Iterate` sobre `custID.runs/eValues` (≈ 60 KB), i `count(R)` suma les longituds dels rangs. **No hi ha `Reconstruct`** ni es descomprimeix res: el cost depèn del nombre de runs (10.000), no del de files (1.000.000).
- **Files sense índex:** `Aggregate` ← `Seq Scan on views`, el mateix recorregut que a Q1: **9.346 pàgines i 24,3 ms** per comptar 103 files.
- **Files amb índex:** `Index Only Scan using views_custid_idx` amb `Heap Fetches: 0` llegeix **4 pàgines** (0,012 ms). L'índex funciona com una "columna" `custID` ordenada i no cal anar a la taula. Aquest és l'equivalent més proper, dins d'un SGBD per files, a treballar només sobre la columna.
- **Guanya clarament el columnar** davant del recorregut complet (unes 1.200 vegades menys bytes). Per acostar-s'hi, el sistema per files necessita una estructura addicional (l'índex, 870 pàgines més), que s'ha de mantenir i que només serveix per a aquest predicat.

### Query 4 — `SELECT custID, COUNT(seriesID) FROM views GROUP BY custID`

- **Columnar:** un bucle sobre `custID.dictionary` amb `Iterate` + `count` per a cada valor. Només es llegeix `custID` (≈ 100 KB entre diccionari, runs i eValues) i s'agreguen **runs en lloc de files**. Com que `seriesID` és NOT NULL, no cal llegir aquesta columna.
- **Files (amb índex o sense):** `HashAggregate` ← `Seq Scan on views`. Es llegeixen **9.346 pàgines** i s'han de processar un per un 1.000.000 de tuples per obtenir 10.000 grups: **108,6 ms**. Amb l'índex el pla no canvia, perquè cal tota la taula i l'optimitzador continua triant el recorregut seqüencial.
- **Guanya el columnar**, i aquí l'índex no redueix la diferència: unes 700 vegades menys bytes i 10.000 iteracions sobre dades comprimides, contra 1.000.000 de tuples senceres.

### Resum

| Query | Guanya | Motiu | Evidència (`large`, PostgreSQL) |
|---|---|---|---|
| Q1 | Columnar | Només llegeix `custID` comprimida i `seriesID` de 103 posicions (materialització tardana) | Seq Scan: 9.346 pàg., 24,3 ms. Amb índex: 4 pàg., 0,035 ms (molt selectiu) |
| Q2 | Files | Tuples ja contigües; el columnar llegeix totes les columnes i ha de reconstruir 10.000 tuples | Seq Scan: 104 pàg., 0,5 ms; l'índex no hi influeix |
| Q3 | Columnar (clarament) | `Iterate` + `count` sobre les runs, sense `Reconstruct` ni descompressió | Seq Scan: 9.346 pàg., 24,3 ms. Index Only Scan: 4 pàg., 0,012 ms |
| Q4 | Columnar | Agrega 10.000 runs d'una sola columna en lloc d'1 M de tuples senceres | Seq Scan + HashAggregate: 9.346 pàg., 108,6 ms, amb índex o sense |

**Conclusió.** Quan la query fa servir poques columnes (Q1, Q3, Q4), el columnar llegeix una fracció petita dels bytes i treballa sobre dades comprimides, mentre que PostgreSQL recorre totes les pàgines de la taula. Un índex escollit per a un predicat concret i molt selectiu (Q1, Q3) pot acostar el sistema per files al columnar o fins i tot superar-lo. Però no ajuda quan cal recórrer tota la taula (Q4) i té un cost d'espai i de manteniment, cosa que coincideix amb l'afirmació de l'enunciat que el *tuning* no iguala un sistema columnar. Només quan es demanen totes les columnes (Q2) guanya el sistema per files. Amb les 4 i 11 files de l'enunciat no es veu cap diferència: tot cap en una pàgina.

*Nota sobre les dades sintètiques:* `seriesID`, `season` i `episode` s'han generat a l'atzar dins de cada client, de manera que gairebé no formen runs (R ≈ N). Això fa que l'estimació columnar d'aquestes columnes sigui pessimista, però no afecta les conclusions: Q3 i Q4 només fan servir `custID`, i Q1 només llegeix 103 posicions de `seriesID`.
