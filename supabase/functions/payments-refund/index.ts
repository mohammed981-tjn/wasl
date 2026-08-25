// ═══════════════════════════════════════════════════════════════════════════
// وصل | الاسترداد
// ═══════════════════════════════════════════════════════════════════════════
//
// الاسترداد يخرج مالًا لا يعود، فحراسته مضاعفة:
//   ١) **من ينادي**: محاسبٌ أو مالك — يُسأل عنه المُصدِّق ثم تُسأل أدواره.
//   ٢) **كم**: سقفُه في القاعدة (`enforce_refund_ceiling`) لا في هذه الدالّة.
//
// والترتيب مقصود: يُسجَّل الطلب في القاعدة **أوّلًا** فيمرّ على السقف، ثم
// يُنفَّذ عند المزوّد. فلو نُفِّذ أوّلًا لَخرج مالٌ يرفضه القيد بعد خروجه.

const MOYASAR_API = "https://api.moyasar.com/v1";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MOYASAR_SECRET = Deno.env.get("MOYASAR_SECRET_KEY") ?? "";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function db(path: string, init: RequestInit = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      ...(init.headers ?? {}),
    },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${path}: ${res.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

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
    return json({ error: "بوّابة الدفع غير مضبوطة بعد (MOYASAR_SECRET_KEY)" }, 503);
  }

  const uid = await callerId(req.headers.get("Authorization"));
  if (!uid) return json({ error: "جلسة غير صالحة" }, 401);

  const roles = await db(
    `user_roles?user_id=eq.${uid}&role=in.(super_admin,accountant)&select=role`,
  );
  if (!Array.isArray(roles) || roles.length === 0) {
    return json({ error: "الاسترداد للمحاسب أو المالك" }, 403);
  }

  let paymentId: string, amount: number, reason: string;
  try {
    const body = await req.json();
    paymentId = String(body?.payment_id ?? "");
    amount = Number(body?.amount ?? 0);
    reason = String(body?.reason ?? "").trim();
    if (!paymentId || !(amount > 0) || !reason) {
      return json({ error: "بيانات الاسترداد ناقصة" }, 400);
    }
  } catch {
    return json({ error: "طلبٌ غير مفهوم" }, 400);
  }

  const rows = await db(
    `payments?id=eq.${paymentId}&select=id,order_id,status,amount,provider_ref,raw_response`,
  );
  const payment = Array.isArray(rows) ? rows[0] : null;
  if (!payment) return json({ error: "الدفعة غير موجودة" }, 404);
  if (payment.status !== "captured") {
    return json({ error: "لا استرداد من دفعةٍ لم تُقبض" }, 400);
  }

  // أوّلًا في القاعدة: السقف يقرّر قبل أن يخرج شيء.
  let refund: any;
  try {
    const created = await db("refunds", {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({
        payment_id: payment.id,
        order_id: payment.order_id,
        amount,
        reason,
        status: "pending",
        requested_by: uid,
      }),
    });
    refund = Array.isArray(created) ? created[0] : created;
  } catch (e) {
    return json({ error: String(e).includes("يتجاوز") ? String(e) : "رُفض الاسترداد" }, 400);
  }

  // معرّف الدفعة عند المزوّد لا معرّف الفاتورة: الاسترداد يقع على دفعة.
  const providerPaymentId = payment.raw_response?.id ?? payment.provider_ref;

  const auth = "Basic " + btoa(`${MOYASAR_SECRET}:`);
  const res = await fetch(`${MOYASAR_API}/payments/${providerPaymentId}/refund`, {
    method: "POST",
    headers: { Authorization: auth, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ amount: String(Math.round(amount * 100)) }),
  });
  const raw = await res.json().catch(() => ({}));

  // الفشل يُكتب على الحركة ولا يُحذف: «طُلب استردادٌ ورفضه المزوّد» واقعةٌ
  // تُراجَع، وحذفُها يجعلها تختفي من الدفاتر.
  await db(`refunds?id=eq.${refund.id}`, {
    method: "PATCH",
    body: JSON.stringify(
      res.ok
        ? { status: "completed", provider_ref: String(raw?.id ?? ""), completed_at: new Date().toISOString() }
        : { status: "failed" },
    ),
  });

  return res.ok
    ? json({ ok: true, refund_id: refund.id })
    : json({ error: raw?.message ?? "رفض المزوّد الاسترداد" }, 502);
});
