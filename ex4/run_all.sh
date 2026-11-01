#!/usr/bin/env bash
# Exercici 4: carrega les dades i executa Q1-Q4 amb EXPLAIN (ANALYZE, BUFFERS)
# a tres escales (paper, small, large), sense índex i amb un índex a VIEWS(custID).
# Credencials: PGPASSWORD per entorn o al fitxer local.env (ignorat per git), mai al script.
set -euo pipefail
cd "$(dirname "$0")"
[[ -f local.env ]] && { set -a; . ./local.env; set +a; }   # contrasenya local, ignorada per git

export PGHOST=${PGHOST:-localhost} PGPORT=${PGPORT:-5435} PGUSER=${PGUSER:-lab3} PGDATABASE=${PGDATABASE:-columnar_lab}
PSQL="psql -X -q -v ON_ERROR_STOP=1"
OUT=results
RUNS=6   # 1 d'escalfament + 5 mesures
mkdir -p "$OUT"

declare -A Q=(
    [Q1]="SELECT DISTINCT seriesID FROM views WHERE custID = 1"
    [Q2]="SELECT * FROM customers"
    [Q3]="SELECT COUNT(*) FROM views WHERE custID = 1"
    [Q4]="SELECT custID, COUNT(seriesID) FROM views GROUP BY custID"
)

load() {  # schema [n_cust n_views]
    $PSQL -v schema="$1" -f sql/01_schema.sql
    if [[ $1 == paper ]]; then
        $PSQL -v schema="$1" -f sql/02_data_paper.sql
    else
        $PSQL -v schema="$1" -v n_cust="$2" -v n_views="$3" -f sql/03_data_synth.sql
    fi
    $PSQL -c "VACUUM ANALYZE $1.customers" -c "VACUUM ANALYZE $1.views"
}

explain() {  # schema variant query_id
    local schema=$1 variant=$2 q=$3 plan times
    local sql="SET search_path TO $schema; SET max_parallel_workers_per_gather = 0;"
    for _ in $(seq $RUNS); do sql+=" EXPLAIN (ANALYZE, BUFFERS) ${Q[$q]};"; done
    plan=$($PSQL -At -c "$sql")
    # Pla de l'última execució
    { echo "=== $schema | $variant | $q: ${Q[$q]}"; echo "$plan" | awk '/^[A-Z].*cost=/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}'; echo; } \
        >> "$OUT/plans_${schema}.txt"
    # Mediana de les 5 últimes execucions
    times=$(echo "$plan" | sed -n 's/^Execution Time: \([0-9.]*\) ms/\1/p' | tail -n +2 | sort -g)
    local median=$(echo "$times" | sed -n '3p')
    local last=$(echo "$plan" | awk '/^[A-Z].*cost=/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}')
    local node=$(echo "$last" | head -1 | sed 's/  (cost.*//')
    local scan=$(echo "$last" | grep -oE '(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan|Bitmap Index Scan)' | sort -u | paste -sd+)
    local hit=$(echo "$last" | grep -m1 'Buffers:' | grep -oE 'hit=[0-9]+' | cut -d= -f2)
    local read=$(echo "$last" | grep -m1 'Buffers:' | grep -oE 'read=[0-9]+' | cut -d= -f2)
    local rows=$(echo "$last" | head -1 | grep -oE 'actual time=[^)]*rows=[0-9.]+' | grep -oE 'rows=[0-9.]+' | cut -d= -f2)
    echo "$schema,$variant,$q,$node,$scan,${rows:-0},$(( ${hit:-0} + ${read:-0} )),$median" >> "$OUT/summary.csv"
}

rm -f "$OUT"/plans_*.txt "$OUT"/sizes_*.txt
echo "schema,variant,query,root_node,scans,rows,buffers_8KB,median_ms" > "$OUT/summary.csv"

load paper
load small 1000 10000
load large 10000 1000000

for s in paper small large; do
    for q in Q1 Q2 Q3 Q4; do explain "$s" no_index "$q"; done
    $PSQL -v schema="$s" -f sql/04_index.sql
    for q in Q1 Q2 Q3 Q4; do explain "$s" index_custid "$q"; done
    $PSQL -v schema="$s" -f sql/06_sizes.sql > "$OUT/sizes_${s}.txt"
done
$PSQL -v schema=paper -f sql/05_results.sql > "$OUT/results_paper.txt"

column -s, -t "$OUT/summary.csv"
