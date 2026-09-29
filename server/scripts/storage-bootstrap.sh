#!/bin/sh
set -eu
# Covers existing data volumes too; init-scripts alone only run on fresh databases.
psql -X -v ON_ERROR_STOP=1 -h db -U postgres -d postgres <<'SQL'
\getenv storage_password PGPASSWORD
alter user supabase_storage_admin with password :'storage_password';
SQL
