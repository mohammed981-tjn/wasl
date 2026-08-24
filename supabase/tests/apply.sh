#!/usr/bin/env bash
# تطبيق كل المهاجرات على قاعدة نظيفة، والتوقّف عند أول خطأ.
set -uo pipefail
PSQL="psql -h /tmp -p 5433 -U postgres -v ON_ERROR_STOP=1 -q"
cd "$(dirname "$0")/../.."

$PSQL -d postgres -c "drop database if exists wasl;" -c "create database wasl;" >/dev/null 2>&1
$PSQL -d wasl -f supabase/tests/00_supabase_shim.sql >/dev/null || { echo "✗ shim"; exit 1; }
echo "✓ shim"

for f in supabase/migrations/*.sql; do
  out=$($PSQL -d wasl -f "$f" 2>&1)
  if [ $? -ne 0 ]; then
    echo "✗ $(basename "$f")"
    echo "$out" | grep -E "ERROR|FATAL" | head -5
    exit 1
  fi
  echo "✓ $(basename "$f")"
done
echo "── كل المهاجرات طُبِّقت بنجاح"
