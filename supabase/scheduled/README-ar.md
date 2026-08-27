# جدولةٌ تُنفَّذ على المشروع الحيّ وحده

**لماذا خارج `migrations/`**: `supabase/tests/apply.sh` يطبّق كلَّ ملفّ في
`migrations/` على قاعدةٍ محلّيّة، و`pg_cron` غيرُ موجودٍ فيها. فمهاجرةٌ تفترضه
تُفشل تطبيقَ المهاجرات كلَّها — ويصير كلُّ اختبارٍ في المشروع لا يعمل من أجل
سطرِ جدولة.

فتُحفظ هنا، وتُطبَّق يدويًّا مرّةً واحدة على المشروع الحيّ.

## الحالة

| الملفّ | مُطبَّق؟ |
|---|---|
| `close_stale_complaints.sql` | ✅ نعم — `cron.job` باسم `close-stale-complaints`, كلَّ ساعة عند الدقيقة ٧ |

## التحقّق

```sql
select jobname, schedule, active from cron.job;
select jobname, status, return_message, start_time
from cron.job_run_details order by start_time desc limit 10;
```
