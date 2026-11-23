import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  // الـtoken في الاختبار = uid.
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
import { deriveDeliveryPin } from "../src/delivery_pin";
import { newQuickOrder, resolveQuickSettings } from "../src/quick_orders";

const SECRET = "test-delivery-secret";
const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
  DELIVERY_PIN_SECRET: SECRET,
  CLOUDINARY_CLOUD_NAME: "demo",
  CLOUDINARY_API_KEY: "k",
  CLOUDINARY_API_SECRET: "s",
  UPLOAD_RATE_LIMITER: { limit: async () => ({ success: true }) },
} as never;

function enc(v: unknown): unknown {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  return { mapValue: { fields: fields(v as Record<string, unknown>) } };
}
const fields = (m: Record<string, unknown>): Record<string, unknown> =>
  Object.fromEntries(Object.entries(m).map(([k, v]) => [k, enc(v)]));

const ID = "cust1_abcdefghijklmnop";
const UPDATE_TIME = "2026-11-22T10:00:00.000000Z";
type Docs = Record<string, Record<string, unknown> | undefined>;
let commits: any[] = [];
let commitStatus = 200;
let pushes: any[] = [];

function firebase(docs: Docs) {
  commits = [];
  pushes = [];
  commitStatus = 200;
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token")) return Response.json({ access_token: "t", expires_in: 3600 });
    if (url.includes("accounts:lookup")) {
      const uid = JSON.parse(String(init?.body)).localId[0];
      return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
    }
    if (url.includes("fcm.googleapis.com")) {
      pushes.push(JSON.parse(String(init?.body)));
      return Response.json({ name: "m" });
    }
    if (url.endsWith("/documents:commit")) {
      commits.push(JSON.parse(String(init?.body)));
      return commitStatus === 200
        ? Response.json({ writeResults: [] })
        : new Response("FAILED_PRECONDITION", { status: commitStatus });
    }
    if (url.includes("firestore.googleapis.com/")) {
      const path = decodeURIComponent(url.split("/documents/")[1]);
      const d = docs[path];
      if (d) return Response.json({ name: prefix + path, fields: fields(d), updateTime: UPDATE_TIME });
      return new Response("not found", { status: 404 });
    }
    throw Error("Unexpected request: " + url);
  });
}
afterEach(() => vi.restoreAllMocks());

const call = (uid: string, path: string, body?: unknown, method = "POST") =>
  worker.fetch(new Request(`https://w.test${path}`, {
    method,
    headers: { Authorization: "Bearer " + uid, "Content-Type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), env);

const createBody = {
  orderId: ID,
  customerName: "Ali Hassan",
  area: "وسط البلد",
  stores: [{ name: "بقالة الخير", items: "رز، 2 زيت" }, { name: "", items: "كيلو لحمة" }],
  contact: { userName: "Ali Hassan", phone: "01012345678", address: "شارع التحرير 10" },
};

const openOrder = () => newQuickOrder({
  uid: "cust1",
  customerFirstName: "Ali",
  area: "",
  notes: "",
  stores: [{ name: "", items: "عيش" }],
  settings: resolveQuickSettings({ enabled: true }),
});

describe("POST /v1/quick (create)", () => {
  it("is refused only when the admin switched the service off (emergency)", async () => {
    firebase({ "app_info/quick_settings": { enabled: false } });
    const res = await call("cust1", "/v1/quick", createBody);
    expect(res.status).toBe(503);
    expect(((await res.json()) as { code: string }).code).toBe("quick_disabled");
    expect(commits.length).toBe(0);
  });

  it("creates the order, private contact and limit atomically, then pings quick couriers", async () => {
    firebase({ "app_info/quick_settings": { enabled: true, prepaidThresholdPiastres: 20000 } });
    const res = await call("cust1", "/v1/quick", createBody);
    expect(res.status).toBe(200);
    expect(commits.length).toBe(1);
    const writes = commits[0].writes;
    expect(writes.length).toBe(3);
    expect(writes[0].update.name).toBe(prefix + `quick_orders/${ID}`);
    expect(writes[0].currentDocument).toEqual({ exists: false });
    const order = writes[0].update.fields;
    expect(order.status).toEqual({ stringValue: "open" });
    expect(order.customerFirstName).toEqual({ stringValue: "Ali" });
    // الخصوصية: مفيش رقم ولا عنوان في المستند العام.
    expect(JSON.stringify(order)).not.toContain("01012345678");
    expect(writes[1].update.name).toBe(prefix + `quick_orders/${ID}/private/contact`);
    expect(writes[2].update.name).toBe(prefix + "quickLimits/cust1");
    expect(pushes[0].message.topic).toBe("quick_couriers");
    expect(pushes[0].message.data).toEqual({ type: "quick_order" });
    expect(JSON.stringify(pushes[0])).not.toContain("01012345678");
  });

  it("computes approxTotalPiastres on the server and ignores a total sent by the app", async () => {
    firebase({ "app_info/quick_settings": { enabled: true } });
    const res = await call("cust1", "/v1/quick", {
      ...createBody,
      approxTotalPiastres: 1,
      stores: [
        { name: "الخير", items: "عيش", pricedItems: [{ name: "زيت لتر", qty: 2, unitPricePiastres: 7500 }] },
        { name: "", items: "كيلو لحمة", pricedItems: null },
      ],
    });
    expect(res.status).toBe(200);
    const fields = commits[0].writes[0].update.fields;
    expect(fields.approxTotalPiastres).toEqual({ integerValue: "15000" });
    expect(fields.estimatedPurchasesPiastres).toEqual({ nullValue: null });
  });

  it("rejects an invalid priced item without writing", async () => {
    firebase({ "app_info/quick_settings": { enabled: true } });
    const res = await call("cust1", "/v1/quick", {
      ...createBody,
      stores: [{ name: "", items: "", pricedItems: [{ name: "زيت", qty: 100, unitPricePiastres: 7500 }] }],
    });
    expect(res.status).toBe(400);
    expect(((await res.json()) as { code: string }).code).toBe("invalid_priced_items");
    expect(commits.length).toBe(0);
  });

  it("replaying the same id returns the existing order without writing", async () => {
    firebase({ [`quick_orders/${ID}`]: openOrder() });
    const res = await call("cust1", "/v1/quick", createBody);
    expect(((await res.json()) as { reused: boolean }).reused).toBe(true);
    expect(commits.length).toBe(0);
  });

  it("rejects ids that do not belong to the caller and enforces the daily limit", async () => {
    firebase({ "app_info/quick_settings": { enabled: true } });
    expect((await call("cust2", "/v1/quick", createBody)).status).toBe(400);
    vi.restoreAllMocks();
    firebase({
      "app_info/quick_settings": { enabled: true, maxPerDay: 1 },
      "quickLimits/cust1": {
        day: new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Cairo", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date()),
        dailyCount: 1,
      },
    });
    expect((await call("cust1", "/v1/quick", createBody)).status).toBe(429);
  });
});

describe("POST /v1/quick/:id/:action", () => {
  it("accept writes with an updateTime precondition (no double assignment)", async () => {
    firebase({
      [`quick_orders/${ID}`]: openOrder(),
      "couriers/cour1": { name: "Mido", active: true, quickEnabled: true },
      "users/cust1": { fcmTokens: ["customer-device", "customer-device"] },
    });
    const res = await call("cour1", `/v1/quick/${ID}/accept`, {});
    expect(res.status).toBe(200);
    const write = commits[0].writes[0];
    expect(write.currentDocument).toEqual({ updateTime: UPDATE_TIME });
    expect(write.updateMask.fieldPaths).toContain("courierId");
    expect(((await res.json()) as { order: { status: string } }).order.status).toBe("accepted");
    expect(pushes).toHaveLength(1);
    expect(pushes[0].message.token).toBe("customer-device");
    expect(pushes[0].message.data).toEqual({ type: "quick_customer_update", orderId: ID });
  });

  it("a concurrent accept that loses the race gets 409 conflict", async () => {
    firebase({
      [`quick_orders/${ID}`]: openOrder(),
      "couriers/cour2": { name: "Sayed", active: true, quickEnabled: true },
    });
    commitStatus = 400;
    const res = await call("cour2", `/v1/quick/${ID}/accept`, {});
    expect(res.status).toBe(409);
    expect(((await res.json()) as { code: string }).code).toBe("conflict");
  });

  it("couriers without quickEnabled, and strangers, cannot accept", async () => {
    firebase({
      [`quick_orders/${ID}`]: openOrder(),
      "couriers/cour3": { name: "Normal", active: true },
    });
    expect((await call("cour3", `/v1/quick/${ID}/accept`, {})).status).toBe(403);
    expect((await call("stranger", `/v1/quick/${ID}/accept`, {})).status).toBe(403);
    expect(commits.length).toBe(0);
  });

  it("customer approves the final statement with its revision; the write is conditional", async () => {
    firebase({
      [`quick_orders/${ID}`]: {
        ...openOrder(), status: "summary_pending", courierId: "cour1", summaryRevision: 2,
        totals: { purchases: 15000, serviceFee: 500, delivery: 3000, prepaid: 0, due: 18500 },
      },
    });
    expect((await call("cust1", `/v1/quick/${ID}/approve-summary`, { expectedSummaryRevision: 1 })).status).toBe(409);
    expect(commits.length).toBe(0);
    const res = await call("cust1", `/v1/quick/${ID}/approve-summary`, { expectedSummaryRevision: 2 });
    expect(res.status).toBe(200);
    expect(commits[0].writes[0].currentDocument).toEqual({ updateTime: UPDATE_TIME });
    expect(commits[0].writes[0].update.fields.status).toEqual({ stringValue: "summary_approved" });
  });

  it("unknown actions are 404", async () => {
    firebase({ [`quick_orders/${ID}`]: openOrder() });
    expect((await call("cust1", `/v1/quick/${ID}/hack`, {})).status).toBe(404);
  });
});

describe("quick delivery PIN", () => {
  const locked = (over: Record<string, unknown> = {}) => ({
    ...openOrder(),
    status: "summary_approved",
    courierId: "cour1",
    summaryRevision: 1,
    summaryApprovedAt: new Date("2026-11-22T11:00:00Z"),
    totals: { purchases: 15000, serviceFee: 500, delivery: 3000, prepaid: 0, due: 18500 },
    ...over,
  });

  it("no PIN and no delivery while the final statement awaits the customer's approval", async () => {
    const pending = locked({ status: "summary_pending", summaryApprovedAt: null });
    firebase({ [`quick_orders/${ID}`]: pending, "couriers/cour1": { name: "Mido", active: true } });
    expect((await call("cust1", `/v1/quick/${ID}/delivery-pin`, undefined, "GET")).status).toBe(409);
    const pin = await deriveDeliveryPin("quick:" + ID, SECRET);
    const res = await call("cour1", `/v1/quick/${ID}/deliver`, { pin });
    expect(res.status).toBe(409);
    expect(((await res.json()) as { code: string }).code).toBe("not_deliverable");
    expect(commits.length).toBe(0);
  });

  it("only the customer gets the PIN, after approving the statement", async () => {
    firebase({ [`quick_orders/${ID}`]: locked() });
    const res = await call("cust1", `/v1/quick/${ID}/delivery-pin`, undefined, "GET");
    expect(res.status).toBe(200);
    expect(((await res.json()) as { pin: string }).pin).toBe(await deriveDeliveryPin("quick:" + ID, SECRET));
    expect((await call("cour1", `/v1/quick/${ID}/delivery-pin`, undefined, "GET")).status).toBe(403);
    vi.restoreAllMocks();
    firebase({ [`quick_orders/${ID}`]: openOrder() });
    expect((await call("cust1", `/v1/quick/${ID}/delivery-pin`, undefined, "GET")).status).toBe(409);
  });

  it("wrong PIN counts an attempt; right PIN delivers and records the fee owed by the courier", async () => {
    const pin = await deriveDeliveryPin("quick:" + ID, SECRET);
    const wrong = String((Number(pin) + 1) % 10000).padStart(4, "0");
    firebase({ [`quick_orders/${ID}`]: locked(), "couriers/cour1": { name: "Mido", active: true } });
    const bad = await call("cour1", `/v1/quick/${ID}/deliver`, { pin: wrong });
    expect(bad.status).toBe(400);
    expect(commits[0].writes[0].update.name).toBe(prefix + `deliveryPinAttempts/quick_${ID}`);
    vi.restoreAllMocks();
    firebase({ [`quick_orders/${ID}`]: locked(), "couriers/cour1": { name: "Mido", active: true } });
    const good = await call("cour1", `/v1/quick/${ID}/deliver`, { pin });
    expect(good.status).toBe(200);
    const f = commits[0].writes[0].update.fields;
    expect(f.status).toEqual({ stringValue: "delivered" });
    expect(f.courierOwedPiastres).toEqual({ integerValue: "500" });
    expect(commits[0].writes[0].currentDocument).toEqual({ updateTime: UPDATE_TIME });
  });

  it("another courier cannot deliver", async () => {
    const pin = await deriveDeliveryPin("quick:" + ID, SECRET);
    firebase({ [`quick_orders/${ID}`]: locked(), "couriers/cour2": { name: "Sayed", active: true } });
    expect((await call("cour2", `/v1/quick/${ID}/deliver`, { pin })).status).toBe(409);
    expect(commits.length).toBe(0);
  });
});

describe("receipt upload folder", () => {
  it("only the assigned courier of a purchasing order may upload to quick_receipts", async () => {
    firebase({ [`quick_orders/${ID}`]: { ...openOrder(), status: "purchasing", courierId: "cour1" } });
    const form = new FormData();
    form.append("folder", "quick_receipts");
    form.append("orderId", ID);
    form.append("file", new File([new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0])], "r.jpg", { type: "image/jpeg" }));
    const encoded = new Response(form);
    const bytes = new Uint8Array(await encoded.arrayBuffer());
    const res = await worker.fetch(new Request("https://w.test/v1/uploads", {
      method: "POST",
      headers: {
        Authorization: "Bearer cour2",
        "Content-Type": encoded.headers.get("content-type") ?? "",
        "Content-Length": String(bytes.length),
      },
      body: bytes,
    }), env);
    expect(res.status).toBe(403);
  });
});
