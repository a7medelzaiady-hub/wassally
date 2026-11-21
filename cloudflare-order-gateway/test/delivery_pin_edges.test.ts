import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  // الـtoken في الاختبار = uid (عشان نجرب عميل ومندوب ومستخدم غريب).
  jwtVerify: async (token: string) => ({
    payload: { sub: token, auth_time: Math.floor(Date.now() / 1000), firebase: { sign_in_provider: "google.com" } },
  }),
  importPKCS8: async () => ({}),
  SignJWT: class {
    setProtectedHeader() { return this; }
    setIssuer() { return this; }
    setAudience() { return this; }
    setIssuedAt() { return this; }
    setExpirationTime() { return this; }
    async sign() { return "fake-service-jwt"; }
  },
}));

import worker from "../src/index";
import { deriveDeliveryPin, equalPin } from "../src/delivery_pin";

const SECRET = "test-delivery-secret";
const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
  DELIVERY_PIN_SECRET: SECRET,
} as never;

function enc(v: unknown): unknown {
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return { doubleValue: v };
  return { nullValue: null };
}
const fields = (m: Record<string, unknown>) => Object.fromEntries(Object.entries(m).map(([k, v]) => [k, enc(v)]));

const onTheWay = (over: Record<string, unknown> = {}) => ({
  userId: "cust_1", courierId: "courier_1", status: "on_the_way", ready: true,
  courierArrivedAt: new Date("2026-11-20T10:00:00Z"), deliveryMode: "store",
  deliveryFee: 20, total: 70, ...over,
});

type Docs = Record<string, Record<string, unknown> | undefined>;
let commits: any[] = [];
function firebase(docs: Docs) {
  commits = [];
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token")) return Response.json({ access_token: "t", expires_in: 3600 });
    if (url.includes("accounts:lookup")) {
      const uid = JSON.parse(String(init?.body)).localId[0];
      return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
    }
    if (url.endsWith("/documents:commit")) {
      commits.push(JSON.parse(String(init?.body)));
      return Response.json({ writeResults: [] });
    }
    if (url.includes("firestore.googleapis.com/")) {
      const path = decodeURIComponent(url.split("/documents/")[1]);
      const d = docs[path];
      if (d) return Response.json({ name: prefix + path, fields: fields(d), updateTime: "2026-11-20T10:00:00.000000Z" });
      return new Response("not found", { status: 404 });
    }
    throw Error("Unexpected request: " + url);
  });
}
afterEach(() => vi.restoreAllMocks());

const getPin = (uid: string, id = "o1") => worker.fetch(new Request(`https://w.test/v1/orders/${id}/delivery-pin`, {
  method: "GET", headers: { Authorization: "Bearer " + uid },
}), env);
const deliver = (uid: string, pin: unknown, id = "o1") => worker.fetch(new Request(`https://w.test/v1/orders/${id}/deliver`, {
  method: "POST", headers: { Authorization: "Bearer " + uid, "Content-Type": "application/json" },
  body: JSON.stringify({ pin }),
}), env);
const wrongOf = (pin: string) => String((Number(pin) + 1) % 10000).padStart(4, "0");


const ok = { "couriers/courier_1": { active: true } };

describe("POST /v1/orders/:id/deliver — حالات الطلب غير المسموح بتسليمها", () => {
  const cases: Array<[string, Record<string, unknown>, string]> = [
    ["طلب غير معيّن لأي مندوب", { courierId: "" }, "الطلب غير معيّن لحسابك."],
    ["طلب معيّن لمندوب آخر", { courierId: "courier_2" }, "الطلب غير معيّن لحسابك."],
    ["الطلب لسه جديد", { status: "new" }, "لازم يكون الطلب «في الطريق»."],
    ["الطلب بيتجهز", { status: "preparing" }, "لازم يكون الطلب «في الطريق»."],
    ["الطلب ملغي", { status: "cancelled" }, "لازم يكون الطلب «في الطريق»."],
    ["الطلب اتسلّم قبل كده", { status: "delivered" }, "لازم يكون الطلب «في الطريق»."],
    ["المحل لم يؤكد الجاهزية", { ready: false }, "المحل لم يؤكد جاهزية الطلب بعد."],
    ["المندوب لم يسجل الوصول", { courierArrivedAt: null }, "سجّل وصولك إلى عنوان العميل أولًا."],
    ["بلاغ توصيل مفتوح", { activeDeliveryIssueId: "i1" }, "يوجد بلاغ توصيل مفتوح لهذا الطلب."],
    ["نوع المندوب غير محدد", { deliveryMode: "" }, "نوع المندوب غير محدد على الطلب."],
    ["العميل أكد بالفعل", { customerConfirmedAt: new Date("2026-11-20T10:05:00Z") }, "تم تأكيد تسليم هذا الطلب بالفعل."],
  ];

  for (const [label, over, message] of cases) {
    it(`${label}: 409 not_deliverable برسالة واضحة، حتى مع الرمز الصحيح، بدون أي كتابة`, async () => {
      firebase({ "orders/o1": onTheWay(over), ...ok });
      const res = await deliver("courier_1", await deriveDeliveryPin("o1", SECRET));
      expect(res.status).toBe(409);
      expect(await res.json()).toEqual({ error: message, code: "not_deliverable" });
      expect(commits).toHaveLength(0);
    });
  }

  it("المندوب الداخلي (store) والخارجي (external) كلاهما يعدّي الفحص مع رمز صحيح", async () => {
    for (const mode of ["store", "external"]) {
      firebase({ "orders/o1": onTheWay({ deliveryMode: mode }), ...ok });
      const res = await deliver("courier_1", await deriveDeliveryPin("o1", SECRET));
      expect(res.status).toBe(200);
      expect(commits).toHaveLength(1);
      vi.restoreAllMocks();
    }
  });

  it("طلب غير موجود: 404 بدون كتابة", async () => {
    firebase({ ...ok });
    const res = await deliver("courier_1", "1234");
    expect(res.status).toBe(404);
    expect(commits).toHaveLength(0);
  });

  it("الرمز الغلط على طلب جاهز: رسالة عربية مفهومة وكود pin_wrong", async () => {
    firebase({ "orders/o1": onTheWay(), ...ok });
    const res = await deliver("courier_1", wrongOf(await deriveDeliveryPin("o1", SECRET)));
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string; code: string };
    expect(body.code).toBe("pin_wrong");
    expect(body.error).toMatch(/[؀-ۿ]/);
  });

  it("بدون DELIVERY_PIN_SECRET: 503 pin_disabled وبدون أي قراءة أو كتابة", async () => {
    const spy = firebase({ "orders/o1": onTheWay(), ...ok });
    const res = await worker.fetch(new Request("https://w.test/v1/orders/o1/deliver", {
      method: "POST",
      headers: { Authorization: "Bearer courier_1", "Content-Type": "application/json" },
      body: JSON.stringify({ pin: "1234" }),
    }), { ...(env as object), DELIVERY_PIN_SECRET: undefined } as never);
    expect(res.status).toBe(503);
    expect(await res.json()).toMatchObject({ code: "pin_disabled" });
    expect(commits).toHaveLength(0);
    expect(spy).toBeDefined();
  });
});
