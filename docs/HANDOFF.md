# Traspaso: Lab "Scrutinizing Column-Oriented Databases" (UPC) — Ejercicio 4

Este fichero resume lo que ya está hecho de la práctica y lo que falta: el **ejercicio 4** y su
validación experimental. Léelo entero antes de empezar.

## 1. Contexto

- Práctica en pareja de bases de datos orientadas a columnas (UPC). Se entrega un `.docx`.
- En este directorio hay:
  - El **enunciado** de la práctica (PDF).
  - Nuestro **documento de entrega actual** (`.docx`), con los ejercicios 1, 2 y 3 hechos.
- **Idioma del texto de entrega: catalán.** Los comentarios del pseudocódigo también están en catalán.
- **No modifiques el `.docx` original.** Produce el texto en Markdown (o en una copia del `.docx`)
  para que lo peguemos nosotros.

### Entorno

- Ubuntu 24.04.
- **PostgreSQL y DBeaver instalados.** Pregunta usuario, contraseña y puerto de PostgreSQL antes de
  conectarte. Crea una base de datos propia para la práctica (por ejemplo `columnar_lab`) y no toques
  otras.
- **MonetDB no está instalado.** Es opcional (ver sección 6).

## 2. Esquema y datos del enunciado

```
Customer(cid, subscription, city, timeOfSubscription, name, goldCustomer)   -- 4 filas
View(viewID, custID, seriesID, season, episode, startingTime, endingTime)   -- 11 filas
View.custID es FK a Customer.cid
```

Los datos concretos están en el enunciado y en el `.docx`. Columna `View.custID` en orden de filas:
`1,1,2,2,2,4,1,3,1,1,1`.

El sistema columnar del enunciado usa **RLE con ending-row index**. Cada columna tiene tres estructuras:
`col.dictionary` (hash), `col.runs` (ERI) y `col.eValues`. Operaciones disponibles:
`Lookup(dictionary, value)`, `InverseLookUp(dictionary, encoded_value)`,
`Iterate(runs, eValues, encoded_value) -> ranges` y `Reconstruct(ranges, [columns]) -> table`.

## 3. Lo que ya está hecho

### Ejercicio 1 — Estructuras (hecho y revisado)

- Posiciones **en base 0** (como en las diapositivas): el ERI es la posición donde acaba cada run.
- **Código 0 reservado para NULL.** Los códigos del diccionario son la posición de la entrada por
  orden de aparición, empezando en 1. Ejemplo: `custID.dictionary` = {1→1, 2→2, 4→3, 3→4}.
- Ejemplo: `custID.runs = [1,4,5,6,7,10]` y `custID.eValues = [1,2,3,1,4,1]`.
- Valores distintos (D) y runs (R) por columna:

| Tabla | Columna | D | R |
|---|---|---|---|
| Customer | cid | 4 | 4 |
| Customer | subscription | 2 | 2 |
| Customer | city | 1 | 1 |
| Customer | timeOfSubs | 1 | 1 |
| Customer | name | 4 | 4 |
| Customer | goldCustomer | 2 | 2 |
| View | viewID | 11 | 11 |
| View | custID | 4 | 6 |
| View | seriesID | 5 | 7 |
| View | season | 4 | 6 |
| View | episode | 8 | 10 |
| View | startingTime | 2 | 3 |
| View | endingTime | 4 | 6 |

### Ejercicio 2 — Planes de ejecución (versión final)

Criterio del profesor: usar al máximo las operaciones dadas y el mínimo código extra.

```
-- Q1: SELECT DISTINCT seriesID FROM View WHERE custID = 1
E = Lookup(custID.dictionary, 1);
if E == NULL return {};
R = Iterate(custID.runs, custID.eValues, E);     -- ([{0,1},{6,6},{8,10}], View)
T = Reconstruct(R, [seriesID]);                  -- solo 6 tuplas y 1 columna
return HashSet(T.seriesID);                      -- código extra: DISTINCT

-- Q2: SELECT * FROM Customer
n = contarTuples(cid.runs);                      -- último ERI + 1 = 4
R = ([{0, n-1}], Customer);                      -- sin Iterate: no hay filtro
return Reconstruct(R, [cid, subscription, city, timeOfSubs, name, goldCustomer]);

-- Q3: SELECT COUNT(*) FROM View WHERE custID = 1
E = Lookup(custID.dictionary, 1);
if E == NULL return 0;
R = Iterate(custID.runs, custID.eValues, E);
return count(R);                                 -- suma de longitudes de rango = 6; SIN Reconstruct

-- Q4: SELECT custID, COUNT(seriesID) FROM View GROUP BY custID
-- Supuesto: seriesID es NOT NULL, así que COUNT(seriesID) = COUNT(*)
Result = {};
for each (v in custID.dictionary) {
    E = Lookup(custID.dictionary, v);
    R = Iterate(custID.runs, custID.eValues, E);
    Result.add(v, count(R));
}
return Result;                                   -- (1,6), (2,3), (3,1), (4,1)
```

Ideas clave: materialización tardía; Q3 y Q4 trabajan **sobre datos comprimidos sin reconstruir**;
Q2 es el peor caso para un sistema columnar (reconstruye todas las columnas de todas las filas).

### Ejercicio 3 — Espacio en disco (hecho)

Asunciones:
- **Por filas:** tipos de tamaño fijo, sin compresión ni cabeceras. Tamaño de columna = N·s.
  `cid`, `viewID`, `custID` INT 4 B; `timeOfSubs` DATE 4 B; `goldCustomer` BOOLEAN 1 B;
  `season` TINYINT 1 B; `episode` SMALLINT 2 B; `subscription` CHAR(7); `city` CHAR(10);
  `name`, `seriesID` CHAR(20); `startingTime`, `endingTime` CHAR(5).
- **Por columnas:** diccionario = D·s (el código es la posición y no ocupa espacio); ERI de 4 B por
  run; eValue de 1 B por run. Tamaño de columna = D·s + 5·R.

Resultados (bytes, por filas → por columnas):

| Customer | Filas | Columnas | | View | Filas | Columnas |
|---|---|---|---|---|---|---|
| cid | 16 | 36 | | viewID | 44 | 99 |
| subscription | 28 | 24 | | custID | 44 | 46 |
| city | 40 | 15 | | seriesID | 220 | 135 |
| timeOfSubs | 16 | 9 | | season | 11 | 34 |
| name | 80 | 100 | | episode | 22 | 66 |
| goldCustomer | 4 | 12 | | startingTime | 55 | 25 |
| **Total** | **184** | **196** | | endingTime | 55 | 50 |
| | | | | **Total** | **451** | **455** |

Conclusión: el columnar gana con valores largos y repetidos o con runs largas, y pierde con valores
únicos o muy cortos. Con tablas tan pequeñas pesa más el sobrecoste fijo. El objetivo principal de la
compresión es reducir E/S. **Estos números se pueden reutilizar en el ejercicio 4** para estimar bytes
leídos por cada query.

## 4. Lo que falta: ejercicio 4

Enunciado:

> For each of the queries, discuss if a relational row-oriented database would yield better or worse
> performance (i.e., overall cost). Refer to your execution plan to discuss, with as much detail as
> possible, what would be different in both systems.

Nota del profesor: **hacer la discusión y validarla con PostgreSQL o MonetDB, justificándola con
alguna muestra** (salidas de `EXPLAIN`, buffers leídos, tiempos).

### Puntos de partida por query (a desarrollar y contrastar con los experimentos)

Coste = principalmente E/S (bloques/bytes leídos) + CPU (descompresión y reconstrucción de tuplas).

- **Q1 (filtro + DISTINCT).** Por filas: full scan de `View` leyendo las 7 columnas de todas las
  tuplas (o index scan sobre `custID` + acceso a las tuplas), y después HashAggregate/Sort para el
  DISTINCT. Por columnas: lee solo `custID` comprimida y `seriesID` para las posiciones
  filtradas. **Gana el columnar**, sobre todo cuando la tabla es ancha. Con un índice muy selectivo,
  el sistema por filas puede acercarse.
- **Q2 (`SELECT *`).** Por filas: seq scan, con las tuplas ya contiguas, que es el caso óptimo.
  Por columnas: lee las 6 columnas, decodifica y recompone las tuplas por posición (`Reconstruct`
  de todo). **Gana el sistema por filas.**
- **Q3 (`COUNT` con filtro).** Por filas: full scan de todas las tuplas (o index-only scan si hay
  índice en `custID`). Por columnas: solo `custID.runs/eValues`, sumando longitudes de rango, sin
  descomprimir ni reconstruir; el coste depende del número de runs, no de filas. **Gana claramente
  el columnar.**
- **Q4 (`GROUP BY` + `COUNT`).** Por filas: full scan + HashAggregate. Por columnas: solo `custID`,
  agregando runs en lugar de filas. **Gana el columnar.**
- Aproximación con los números del ejercicio 3: Q3/Q4 leen `custID` (46 B) frente a toda `View`
  (451 B + cabeceras); Q1 lee `custID` + `seriesID` (≤ 181 B) frente a 451 B; Q2 lee 196 B + coste
  de reconstrucción frente a 184 B secuenciales. Con 4 y 11 filas todo cabe en una página, así que
  la diferencia real solo se ve con muchos datos.

### Validación con PostgreSQL (obligatoria según el profesor)

1. Crear la BD `columnar_lab` y el esquema con los tipos del ejercicio 3. PostgreSQL no tiene
   TINYINT: usar SMALLINT y comentarlo.
2. Cargar los datos del enunciado y, además, generar datos aleatorios con `generate_series`. El
   enunciado opcional habla de unos miles de filas; para que se vean diferencias, probar también con
   una tabla `View` grande (por ejemplo, ~1M de filas, ~10k clientes, pocas decenas de series).
   Distribuciones realistas: pocos valores distintos en `seriesID`, `season`, `startingTime`, etc.
3. `ANALYZE` y, para cada query, `EXPLAIN (ANALYZE, BUFFERS)`:
   - sin índices secundarios;
   - con un índice en `View(custID)` (en Q3 debería aparecer un Index Only Scan).
4. Recoger por query: nodos del plan, filas, `shared hit/read` (buffers = páginas de 8 KB) y tiempo.
   Opcional: `pg_relation_size` / `pg_total_relation_size` para relacionarlo con el ejercicio 3.
5. Interpretación: PostgreSQL siempre lee tuplas completas (páginas enteras) aunque la query solo
   use una columna. Esa es la diferencia clave con nuestros planes columnar.

Guarda los scripts en ficheros (`01_schema.sql`, `02_data.sql`, `03_queries.sql`…) y las salidas
en `results/`.

## 5. Entregables de esta sesión

1. Scripts SQL reproducibles y las salidas de `EXPLAIN` guardadas.
2. **Texto del ejercicio 4 en catalán**, por query: plan por filas frente a nuestro plan columnar,
   qué se lee en cada caso, qué sistema gana y por qué, y la evidencia experimental (fragmento de
   plan y cifras de buffers/tiempo). Tono y extensión similares al ejercicio 3: compacto, sin
   perder los puntos importantes.
3. Una tabla resumen: query → ganador → motivo → evidencia.

## 6. Opcional: MonetDB

La actividad opcional del enunciado pide repetir la práctica en MonetDB (columnar real), cargar unos
miles de filas aleatorias, pedir el plan y compararlo con PostgreSQL. Solo si hay tiempo y queremos:

- Instalación en Ubuntu 24.04: repositorio oficial de MonetDB (paquetes `monetdb5-sql` y
  `monetdb-client`) o imagen Docker oficial. Verifica los pasos en la documentación oficial.
- Planes: `PLAN <query>` (plan relacional), `EXPLAIN <query>` (programa MAL) y `TRACE <query>`
  (tiempos por instrucción).
- Comparación interesante: en MAL las operaciones trabajan sobre BATs (una columna cada una). Las
  selecciones (`algebra.select`/`thetaselect`) se parecen a nuestro `Iterate` y las proyecciones
  (`algebra.projection`) a nuestro `Reconstruct`. MonetDB no usa RLE como en el enunciado; compara
  con prudencia.

## 7. Cómo trabajar

- Antes de ejecutar nada, propón un plan y espera confirmación.
- Pide las credenciales de PostgreSQL; no las guardes en ficheros versionados.
- No modifiques el `.docx` original.
- Al final, revisa que el texto del ejercicio 4 sea coherente con los planes del ejercicio 2 y los
  números del ejercicio 3.
