#!/usr/bin/env bash
# Initializes the local devcontainer Postgres database with the OMOP CDM v5.4 schema
# and imports the OMOP vocabulary CSV files.
#
# Assumes a clean state (no `cdm` schema yet). Rerunning against an already-initialized
# database fails hard rather than skipping - drop the `cdm` schema first if you need to redo it.
#
# NOTE ON ORDER: the OMOP `concept` <-> `vocabulary`/`domain`/`concept_class` tables have
# circular foreign keys (e.g. vocabulary.vocabulary_concept_id -> concept.concept_id, while
# concept.vocabulary_id -> vocabulary.vocabulary_id). Constraints must therefore be applied
# AFTER all vocabulary data is loaded: ddl -> import CSVs -> primary_keys -> indices -> constraints.
set -euo pipefail

DDL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../omop-ddl" && pwd)"
VOCAB_DIR="/vocab-data"
CDM_SCHEMA="public"

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${POSTGRES_USER:-postgres}"
export PGPASSWORD="${POSTGRES_PASSWORD:-postgres}"
export PGDATABASE="${POSTGRES_DB:-postgres}"

run_sql() { sed "s/@cdmDatabaseSchema/${CDM_SCHEMA}/g" "$DDL_DIR/$1" | psql -v ON_ERROR_STOP=1 -q; }

for i in $(seq 30); do pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" >/dev/null 2>&1 && break; sleep 2; done

PERSON_TABLE_EXISTS="$(psql -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema = '${CDM_SCHEMA}' AND table_name = 'person'")"
if [[ "$PERSON_TABLE_EXISTS" == "1" ]]; then
    echo "[init_omop_db] Table '${CDM_SCHEMA}.person' already exists - skipping initialization."
    exit 0
fi

run_sql OMOPCDM_postgresql_5.4_ddl.sql

# table:file pairs, in dependency order for readability (not required for correctness -
# constraints are applied after all data is loaded).
declare -a TABLE_FILES=(
    "vocabulary:VOCABULARY.csv" "domain:DOMAIN.csv" "concept_class:CONCEPT_CLASS.csv"
    "relationship:RELATIONSHIP.csv" "concept:CONCEPT.csv" "concept_relationship:CONCEPT_RELATIONSHIP.csv"
    "concept_synonym:CONCEPT_SYNONYM.csv" "concept_ancestor:CONCEPT_ANCESTOR.csv" "drug_strength:DRUG_STRENGTH.csv"
)
for entry in "${TABLE_FILES[@]}"; do
    psql -v ON_ERROR_STOP=1 -q -c "\\copy ${CDM_SCHEMA}.${entry%%:*} FROM '${VOCAB_DIR}/${entry##*:}' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, QUOTE E'\b')"
done

run_sql OMOPCDM_postgresql_5.4_primary_keys.sql
run_sql OMOPCDM_postgresql_5.4_indices.sql
run_sql OMOPCDM_postgresql_5.4_constraints.sql

echo "[init_omop_db] Done."


