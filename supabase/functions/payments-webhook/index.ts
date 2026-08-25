// ═══════════════════════════════════════════════════════════════════════════
// وصل | استقبال إشعار المزوّد
// ═══════════════════════════════════════════════════════════════════════════
//
// هذه الدالّة **بلا تحقّق من رمز الدخول** (`verify_jwt = false`) — لأن الذي
// يناديها بوّابةُ الدفع لا مستخدم. وبديلُ الحراسة رمزٌ سرّيّ متبادَل يُرسله
// المزوّد في متن الإشعار ويُقارَن هنا.
//
// **ولا شيء يُصدَّق قبل مقارنته**: نداءٌ بلا رمزٍ صحيح لا يُطبَّق — ويُسجَّل،
// لأن «وصل إشعارٌ بتوقيعٍ خاطئ» معلومةٌ أمنية لا يجوز أن تمرّ صامتة.
//
// **والجواب دائمًا ٢٠٠ لما فُهم.** البوّابة تعيد الإرسال حتى تتلقّى إقرارًا،
// فالردُّ بخطأٍ على إشعارٍ مكرَّرٍ يجعلها تعيده أبدًا.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("MOYASAR_WEBHOOK_SECRET") ?? "";

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

/// مقارنةٌ ثابتة الزمن: مقارنةُ السلاسل العادية تخرج عند أوّل حرفٍ مختلف،
/// وفرقُ الزمن بين محاولةٍ وأخرى يكشف الرمز حرفًا حرفًا.
function secretMatches(given: string): boolean {
  if (!WEBHOOK_SECRET || given.length !== WEBHOOK_SECRET.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) {
    diff |= given.charCodeAt(i) ^ WEBHOOK_SECRET.charCodeAt(i);
  }
  return diff === 0;
}

/// حالة المزوّد ⇒ حالتنا. وما لا يُعرف لا يُخمَّن: يُسجَّل ولا يُطبَّق.
function mapStatus(type: string, status: string): string | null {
  if (type === "payment_paid" || status === "paid") return "captured";
  if (type === "payment_authorized" || status === "authorized") return "authorized";
  if (type === "payment_failed" || status === "failed") return "failed";
  if (status === "voided" || status === "canceled") return "cancelled";
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST فقط" }, 405);

  let body: Record<string, any>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "متنٌ غير مفهوم" }, 400);
  }

  const eventId = String(body?.id ?? "");
  const eventType = String(body?.type ?? "");
  const data = body?.data ?? {};
  // الفاتورة هي ما فُتح به الدفع، فهي المرجع. وإن جاء إشعارُ دفعةٍ بلا فاتورة
  // فمرجعُها معرّفُها هي.
  const ref = String(data?.invoice_id ?? data?.id ?? "");

  if (!eventId) return json({ error: "لا معرّف حدث" }, 400);

  if (!secretMatches(String(body?.secret_token ?? ""))) {
    await rpc("record_webhook_event", {
      p_provider: "moyasar",
      p_event_id: eventId,
      p_event_type: eventType,
      p_provider_ref: ref || null,
      p_payload: body,
      p_accepted: false,
      p_reject_reason: "رمز الإشعار غير صحيح",
    }).catch(() => {});
    return json({ error: "غير مصرَّح" }, 401);
  }

  const recorded = await rpc("record_webhook_event", {
    p_provider: "moyasar",
    p_event_id: eventId,
    p_event_type: eventType,
    p_provider_ref: ref || null,
    p_payload: body,
    p_accepted: true,
  });

  // رأيناه من قبل: نجاحٌ بلا معالجة كي تكفّ البوّابة عن الإعادة.
  if (recorded?.duplicate) return json({ ok: true, duplicate: true });

  const status = mapStatus(eventType, String(data?.status ?? ""));
  if (!status) return json({ ok: true, ignored: eventType });

  const source = data?.source ?? {};
  const result = await rpc("apply_payment_result", {
    p_provider_ref: ref,
    p_status: status,
    p_amount: Number(data?.amount ?? 0) / 100,
    p_order: data?.metadata?.order_id ?? null,
    p_method: source?.type === "applepay" ? "apple_pay" : "card",
    p_card_brand: source?.company ?? source?.type ?? null,
    p_card_last4: source?.number ? String(source.number).slice(-4) : null,
    p_failure_code: data?.source?.message ? "gateway" : null,
    p_failure_message: data?.source?.message ?? null,
    p_raw: data,
  });

  // حتى الرفض يُجاب بنجاح: أُخذ الإشعار وسُجّل، وإعادته لن تغيّر شيئًا.
  return json({ ok: true, applied: result });
});
