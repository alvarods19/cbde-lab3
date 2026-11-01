# Ejercicio 4: validación con PostgreSQL

Experimentos que apoyan la discusión del ejercicio 4: comparar el coste de Q1–Q4 en una BD orientada a filas (PostgreSQL) con nuestros planes columnares del ejercicio 2. El texto para la entrega está en [ex4_ca.md](ex4_ca.md), en catalán.

## 1. La instancia de PostgreSQL

Para no tocar las BD que ya había en el ordenador (el 5432 es la instancia del sistema y el 5433 estaba ocupado), la práctica usa **una instancia de PostgreSQL 18 propia**:

| | |
|---|---|
| Host | `localhost` (solo TCP, sin socket Unix) |
| Puerto | `5435` |
| Base de datos | `columnar_lab` |
| Usuario | `lab3` (superusuario de esta instancia) |
| Contraseña | en `ex4/local.env` (no se sube a git; si falta, pedidla) |
| Datos | `lab3/pgdata/` (no se sube a git; log en `pgdata/server.log`) |

La instancia **no arranca sola** al reiniciar el ordenador:

```bash
ex4/pg.sh start     # arrancar
ex4/pg.sh status    # ¿está en marcha?
ex4/pg.sh stop      # parar
```

Si `pgdata/` no existe (por ejemplo, en otro ordenador), se puede recrear así:

```bash
echo -n '<contraseña>' > /tmp/pw
/usr/lib/postgresql/18/bin/initdb -D pgdata -U lab3 --pwfile=/tmp/pw --auth=scram-sha-256 -E UTF8 --locale=C.UTF-8
rm /tmp/pw
printf "port = 5435\nlisten_addresses = 'localhost'\nunix_socket_directories = ''\n" >> pgdata/postgresql.conf
ex4/pg.sh start
psql -h localhost -p 5435 -U lab3 -d postgres -c "CREATE DATABASE columnar_lab"
```

Después, `ex4/run_all.sh` carga los datos.

## 2. Conectarse

**DBeaver:** *New Database Connection* → PostgreSQL → Host `localhost`, Port `5435`, Database `columnar_lab`, Username `lab3` y la contraseña. Si la conexión falla, comprobad que la instancia está en marcha (`ex4/pg.sh status`).

**psql:**

```bash
set -a; . ex4/local.env; set +a
psql -h localhost -p 5435 -U lab3 -d columnar_lab
```

## 3. Los datos

Dentro de `columnar_lab` hay un schema por escala, y cada uno tiene las tablas `customers` y `views`. Los nombres siguen las queries del enunciado (`FROM VIEWS`, `FROM CUSTOMERS`).

| Schema | customers | views | Para qué |
|---|---|---|---|
| `paper` | 4 | 11 | Los datos exactos del enunciado. Sirve para comprobar los resultados del ej. 2 y las D/R del ej. 3 |
| `small` | 1.000 | 10.000 | Los "unos miles de filas" del enunciado opcional |
| `large` | 10.000 | 1.000.000 | La escala donde se ven las diferencias (VIEWS ocupa 9.346 páginas, 73 MB) |

- **Tipos:** son los del ejercicio 3. `season` es SMALLINT porque PostgreSQL no tiene TINYINT.
- **Datos sintéticos** (`small` y `large`): generados con semilla fija, así que siempre salen iguales.
  - `views` se inserta **ordenada por `custID`**, como una proyección ordenada de un sistema columnar: las runs de `custID` son largas y el índice tiene correlación máxima.
  - Hay 30 series. `startingTime` y `endingTime` valen `BoE`/`EoE` en el 85 % de las filas.
  - El cliente 1 siempre tiene vistas.

## 4. Los scripts

```
ex4/
  run_all.sh            orquesta todo (carga + experimentos + resultados)
  pg.sh                 start/stop/status de la instancia
  local.env             contraseña (ignorado por git)
  sql/01_schema.sql     DROP + CREATE del schema y las dos tablas (con PK y FK)
  sql/02_data_paper.sql INSERT de los datos del enunciado
  sql/03_data_synth.sql datos aleatorios con generate_series (parámetros n_cust, n_views)
  sql/04_index.sql      crea el único índice secundario, views(custID), y hace VACUUM ANALYZE
  sql/05_results.sql    resultado de Q1–Q4 (para comprobarlos con el ej. 2)
  sql/06_sizes.sql      páginas en PostgreSQL + D y R reales por columna + bytes estimados (fórmula del ej. 3)
  results/              salidas (se regeneran en cada ejecución)
  ex4_ca.md             texto del ejercicio 4 para la entrega (catalán)
```

**Qué hace `run_all.sh`** (unos 15 s, y siempre deja el mismo estado):

1. Para cada schema (`paper`, `small`, `large`): lo borra y lo recrea (01), carga los datos (02 o 03) y hace `VACUUM ANALYZE`.
2. Para cada schema, ejecuta Q1–Q4 con `EXPLAIN (ANALYZE, BUFFERS)`, primero **sin índice** y después **con el índice en `views(custID)`** (04). Lo hace con `max_parallel_workers_per_gather = 0` para tener planes limpios. Cada query se ejecuta 6 veces: la primera calienta la caché y de las otras 5 se toma la mediana del tiempo.
3. Ejecuta 06 en cada schema y 05 en `paper`.

```bash
cd ex4 && ./run_all.sh     # coge la contraseña de local.env
```

**Ficheros de `results/`:**

| Fichero | Contenido |
|---|---|
| `summary.csv` | Una fila por schema × variante × query: nodo raíz, tipo de scan, filas, páginas de 8 KB leídas y mediana en ms |
| `plans_<schema>.txt` | El plan completo de cada ejecución (lo que se cita en el texto) |
| `sizes_<schema>.txt` | Páginas de tablas e índices; D, R, bytes por filas y bytes columnares estimados por columna |
| `results_paper.txt` | Resultado de Q1–Q4 con los datos del enunciado |

Al terminar, **todos los schemas tienen el índice creado**.

## 5. Probar a mano en DBeaver

1. **Abrir un editor:** clic derecho sobre `columnar_lab` → *SQL Editor → Open SQL script* (`Ctrl+]`). Escoged el schema en el selector de la barra del editor, o empezad el script con:
   ```sql
   SET search_path TO large;
   SET max_parallel_workers_per_gather = 0;
   ```
   Para ejecutar: `Ctrl+Enter` ejecuta la sentencia donde está el cursor y `Alt+X` todo el script.

2. **Las queries:**
   ```sql
   SELECT DISTINCT seriesID FROM views WHERE custID = 1;           -- Q1
   SELECT * FROM customers;                                         -- Q2
   SELECT COUNT(*) FROM views WHERE custID = 1;                     -- Q3
   SELECT custID, COUNT(seriesID) FROM views GROUP BY custID;       -- Q4
   ```

3. **El plan:** poned `EXPLAIN (ANALYZE, BUFFERS)` delante de la query. En la salida, mirad:
   - el nodo (`Seq Scan`, `Index Scan`, `Index Only Scan`, `HashAggregate`…);
   - `Buffers: shared hit=…`: páginas de 8 KB leídas (si sale `read=`, se suma);
   - `Rows Removed by Filter`: tuplas leídas y descartadas;
   - `Execution Time`.

   El botón *Explain execution plan* (`Ctrl+Shift+E`) dibuja el plan en árbol. Para ver tiempos y buffers hay que marcar *ANALYSE* y *BUFFERS* en sus opciones. Para copiar al informe, es más cómoda la salida en texto.

4. **Sin índice / con índice:**
   ```sql
   DROP INDEX large.views_custid_idx;
   EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*) FROM views WHERE custID = 1;   -- Seq Scan, ~9.346 páginas

   CREATE INDEX views_custid_idx ON large.views(custID);
   VACUUM ANALYZE large.views;   -- si no, el Index Only Scan tiene que ir a la tabla (Heap Fetches > 0)
   EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*) FROM views WHERE custID = 1;   -- Index Only Scan, ~4 páginas
   ```
   `VACUUM` necesita que *Auto-Commit* esté activado; viene activado por defecto.

5. **Tamaños:**
   ```sql
   SELECT relname, relpages AS paginas, pg_size_pretty(pg_relation_size(oid)) AS mida
   FROM pg_class WHERE relnamespace = 'large'::regnamespace AND relkind IN ('r','i');
   ```
   Las D/R por columna están en `results/sizes_large.txt`. `06_sizes.sql` usa variables de psql (`:schema`): para ejecutarlo en DBeaver hay que sustituir `:schema` y `:'schema'` por el nombre del schema.

**Avisos:**
- La tabla `views` aparece en la carpeta *Tables*, no en *Views*; no tiene nada que ver con las vistas SQL.
- Los primeros tiempos pueden salir más altos mientras la caché se llena. Las páginas leídas no dependen de la caché.
- Si tocáis algo y queréis volver al estado inicial, ejecutad `./run_all.sh`.

## 6. Resultados principales (`large`)

| Query | Sin índice | Con índice | Gana |
|---|---|---|---|
| Q1 | Seq Scan, 9.346 páginas, 24 ms | Index Scan, 4 páginas, 0,03 ms | Columnar (con un índice muy selectivo, las filas se acercan o lo superan) |
| Q2 | Seq Scan, 104 páginas, 0,5 ms | igual | Filas |
| Q3 | Seq Scan, 9.346 páginas, 24 ms | Index Only Scan, 4 páginas, 0,01 ms | Columnar |
| Q4 | Seq Scan + HashAggregate, 9.346 páginas, ~109 ms | igual (el índice no se usa) | Columnar |

Con `paper` todas las queries leen 1 página: con 4 y 11 filas no se ve ninguna diferencia. La discusión completa está en [ex4_ca.md](ex4_ca.md).

## 7. Cómo trabajamos

- **No se modifica el `.docx` original** (`docs/Exercise-Column-Oriented.docx`). El texto se prepara en Markdown y lo pegamos nosotros.
- **El texto de entrega va en catalán**; la documentación interna, como este fichero, en castellano.
- **Credenciales:** nunca en ficheros versionados. La contraseña está en `ex4/local.env`, que está en `.gitignore`, igual que `pgdata/`.
- **Reproducibilidad:** todo lo que se cita en el texto tiene que salir de `run_all.sh`. Si se cambia un script, se vuelve a ejecutar y se revisa que las cifras de `ex4_ca.md` sigan coincidiendo con `results/`.
- **Coherencia:** el texto del ejercicio 4 tiene que cuadrar con los planes del ejercicio 2 (Lookup / Iterate / Reconstruct) y con los números del ejercicio 3. `results_paper.txt` y `sizes_paper.txt` sirven de comprobación.
- **Con Claude:** antes de ejecutar nada nuevo, Claude propone un plan y espera confirmación. El alcance es deliberadamente acotado: escaneo completo frente a un único índice simple, sin un análisis exhaustivo de tuning.
- **Pendiente / opcional:** repetir las queries en MonetDB (por Docker) y comparar los planes. De momento está aparcado.
