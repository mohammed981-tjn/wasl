#!/usr/bin/env bash
# مشغّل اختبارات قاعدة البيانات.
#
# لماذا قاعدة محلية لا مشروع Supabase: الاختبار يجب أن يبدأ من قاعدة نظيفة كل
# مرة ويُلقي بما كتبه (rollback). تشغيله على مشروع حيّ يعني إمّا تلويث بيانات
# حقيقية أو خوفًا من تشغيله — وكلاهما يقتل الاختبار.
#
#   supabase/tests/run.sh
#
# يتطلّب: postgresql-16 + postgresql-16-postgis-3 وقاعدة تعمل على المنفذ 5433.
set -uo pipefail
cd "$(dirname "$0")/../.."

PORT=${PGTESTPORT:-5433}
PSQL="psql -h /tmp -p $PORT -U postgres"

$PSQL -d postgres -c 'select 1' >/dev/null 2>&1 || {
  echo "✗ لا قاعدة تعمل على المنفذ $PORT — شغّلها أولًا:"
  echo "  su postgres -c '/usr/lib/postgresql/16/bin/pg_ctl -D <datadir> -o \"-k /tmp -p $PORT\" start'"
  exit 1
}

./supabase/tests/apply.sh || exit 1
echo

# **حارسٌ ضدّ فجوةٍ صامتة**: ملفُّ اختبارٍ باسمٍ لا يطابق النمط لا يُشغَّل
# أبدًا — فيبدو المشروع مختبَرًا وهو ليس كذلك. حدث هذا فعلًا مع
# `07b_reports_test.sql`.
declare -i _all=0 _matched=0
for f in supabase/tests/*_test.sql; do _all+=1; done
for f in supabase/tests/[0-9][0-9]_*_test.sql; do _matched+=1; done
if [ "$_all" -ne "$_matched" ]; then
  echo "✗ ملفّات اختبارٍ لا تطابق النمط ولن تُشغَّل:"
  for f in supabase/tests/*_test.sql; do
    case "$(basename "$f")" in
      [0-9][0-9]_*_test.sql) ;;
      *) echo "   $(basename "$f")" ;;
    esac
  done
  exit 1
fi

fail=0
for t in supabase/tests/[0-9][0-9]_*_test.sql; do
  echo "── $(basename "$t")"
  out=$($PSQL -d wasl -f "$t" 2>&1)
  echo "$out" | grep -E "✓|✗" | sed 's/^psql:[^ ]* //;s/^NOTICE:  /   /'
  if echo "$out" | grep -qE "✗|^psql:.*ERROR"; then fail=1; fi
done

echo
if [ $fail -ne 0 ]; then echo "✗ فشل اختبار أو أكثر"; exit 1; fi
echo "✓ كل الاختبارات نجحت"
