#!/usr/bin/env bash
# Runs once after the devcontainer is created (see postCreateCommand in devcontainer.json).
#
# Steps:
#   1. Install the ariadne package in editable mode.
#   2. Download the spaCy model used for term normalization.
#   3. Initialize the local Postgres OMOP CDM schema and load vocabulary data.
#   4. Download the term corpus used for verbatim (exact) mapping.
#   5. Build the verbatim mapping index (data/verbatim_condition_index.pkl).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

pip install -e .

python -m spacy download en_core_web_sm

bash .devcontainer/db-init/scripts/init_omop_db.sh

export VOCAB_CONNECTION_STRING="postgresql+psycopg://postgres:postgres@localhost:5432/postgres"
export VOCAB_SCHEMA="public"

python -m ariadne.verbatim_mapping.term_downloader

python -c "
from ariadne.utils.config import Config
from ariadne.verbatim_mapping.vocab_verbatim_term_mapper import VocabVerbatimTermMapper

VocabVerbatimTermMapper(settings=Config().verbatim_mapping)
"

echo "[post_create] Done."
