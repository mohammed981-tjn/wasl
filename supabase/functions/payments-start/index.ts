// ═══════════════════════════════════════════════════════════════════════════
// وصل | فتح جلسة دفع عند المزوّد
// ═══════════════════════════════════════════════════════════════════════════
//
// **لماذا هذه الدالّة موجودة أصلًا**: مفتاحُ سرّ المزوّد لا يجوز أن يسكن حزمةً
// تُثبَّت على هاتف — من يفكّ الحزمة يأخذه. فالحزمة تطلب «افتح لي دفعًا لطلب
// كذا»، والخادمُ وحده يعرف المفتاح ويعرف المبلغ.
//
// **والمبلغ لا يأتي من العميل.** يُقرأ من `open_payment_session` في القاعدة.
// ولو أُخذ من الطلب الوارد لَدفع كلُّ عميلٍ ما يشاء لطلبه.

const MOYASAR_API = "https://api.moyasar.com/v1";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MOYASAR_SECRET = Deno.env.get("MOYASAR_SECRET_KEY") ?? "";
// إلى أين يعود العميل بعد صفحة الدفع. رابطٌ عامّ لا صفحةٌ سرّية: النتيجة
// تُعتمد من الإشعار الخلفيّ لا من عودة المتصفّح.
const CALLBACK_URL = Deno.env.get("PAYMENT_CALLBACK_URL") ?? "";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function rpc(fn: string, args: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(args),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${fn}: ${res.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

/// من هو المنادي؟ **يُسأل المُصدِّق لا الرمز**: قراءة الادّعاء من الرمز بلا
/// تحقّقٍ تقبل رمزًا ملفَّقًا.
async function callerId(authHeader: string | null): Promise<string | null> {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SERVICE_KEY, Authorization: authHeader },
  });
  if (!res.ok) return null;
  const user = await res.json();
  return typeof user?.id === "string" ? user.id : null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST فقط" }, 405);

  if (!MOYASAR_SECRET) {
    // يُقال صراحةً ولا يُتظاهر بالنجاح: «الدفع غير مضبوط» رسالةٌ تُصلَح،
    // و«فشل غير معروف» رسالةٌ تُبحث ساعةً.
    return json({ error: "بوّابة الدفع غير مضبوطة بعد (MOYASAR_SECRET_KEY)" }, 503);
  }

  const uid = await callerId(req.headers.get("Authorization"));
  if (!uid) return json({ error: "جلسة غير صالحة" }, 401);

  let orderId: string;
  try {
    const body = await req.json();
    orderId = String(body?.order_id ?? "");
    if (!orderId) return json({ error: "لا رقم طلب" }, 400);
  } catch {
    return json({ error: "طلبٌ غير مفهوم" }, 400);
  }

  const session = await rpc("open_payment_session", {
    p_order: orderId,
    p_customer: uid,
  });
  if (!session?.ok) {
    return json({ error: session?.reason ?? "تعذّر فتح الدفع" }, 400);
  }

  // الهللات: المبلغ عند المزوّد عددٌ صحيح. و`Math.round` لا `parseInt`،
  // فـ`230.10 * 100` تعطي `23009.999...` في الفاصلة العائمة.
  const halalas = Math.round(Number(session.amount) * 100);

  const form = new URLSearchParams({
    amount: String(halalas),
    currency: String(session.currency ?? "SAR"),
    description: `${session.laundry_name} — طلب #${session.order_number}`,
    "metadata[order_id]": orderId,
    "metadata[order_number]": String(session.order_number),
  });
  if (CALLBACK_URL) form.set("callback_url", CALLBACK_URL);

  const auth = "Basic " + btoa(`${MOYASAR_SECRET}:`);
  const res = await fetch(`${MOYASAR_API}/invoices`, {
    method: "POST",
    headers: { Authorization: auth, "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });

  const raw = await res.json().catch(() => ({}));
  if (!res.ok) {
    return json({ error: raw?.message ?? "رفض المزوّد فتح الدفع" }, 502);
  }

  // تُسجَّل الدفعة `pending` فورًا. ولماذا قبل أن يدفع أحد: المحاولةُ كيانٌ لا
  // نتيجة — ومن يسجّل الناجحة وحدها لا يعرف كم عميلًا حاول ولم يستطع.
  await rpc("apply_payment_result", {
    p_provider_ref: String(raw.id),
    p_status: "pending",
    p_amount: session.amount,
    p_order: orderId,
    p_method: "card",
    p_raw: raw,
  });

  return json({ ok: true, url: raw.url, ref: raw.id });
});
