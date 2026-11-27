import { describe, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  jwtVerify: async () => ({
    payload: {
      sub: "limit_user",
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: "google.com" },
    },
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
import { districtFromAddress } from "../src/address_district";

const uid = "limit_user";
const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
} as never;
const orderInput = (id: string, area?: string) => ({
  ...(area !== undefined ? { area } : {}),
  orderId: uid + "_" + id,
  storeId: "store_test",
  customerName: "Ahmed Test",
  expectedDeliveryFee: 20,
  expectedTotal: 75, // 50 أصناف + 20 توصيل + 5 رسوم خدمة (الحد الأدنى)
  items: [{ productId: "product_test", expectedPrice: 25, qty: 2, options: [], optionsTotal: 0 }],
  contact: { userName: "Ahmed Test", phone: "01012345678", address: "Test street address" },
});

type Fields = Record<string, unknown>;
function simulateFirebase(limitFields: Fields | null, areasFields: Fields | null = null) {
  const commits: Array<{ writes: Array<{ update: { name: string; fields: Fields }; currentDocument?: unknown }> }> = [];
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token"))
      return Response.json({ access_token: "fake-access-token", expires_in: 3600 });
    if (url.includes("accounts:lookup"))
      return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
    if (url.endsWith("/documents:batchGet"))
      return new Response(JSON.stringify({
        found: {
          name: prefix + "stores/store_test/products/product_test",
          fields: { name: { stringValue: "Test product" }, price: { doubleValue: 25 }, available: { booleanValue: true } },
        },
      }) + "\n", { status: 200 });
    if (url.endsWith("/documents:commit")) {
      commits.push(JSON.parse(String(init?.body)));
      return Response.json({ writeResults: [{}, {}, {}] });
    }
    if (url.includes("fcm.googleapis.com/")) return Response.json({ name: "fake-message" });
    if (url.includes("firestore.googleapis.com/")) {
      const path = url.split("/documents/")[1];
      if (path === "stores/store_test")
        return Response.json({ name: prefix + path, fields: { name: { stringValue: "Test store" }, active: { booleanValue: true } } });
      if (path === "orderLimits/" + uid && limitFields)
        return Response.json({ name: prefix + path, fields: limitFields, updateTime: "2026-11-19T10:00:00.000000Z" });
      if (path === "app_info/delivery_areas" && areasFields)
        return Response.json({ name: prefix + path, fields: areasFields });
      return new Response("not found", { status: 404 });
    }
    throw Error("Unexpected upstream request: " + url);
  });
  return { commits, restore: () => spy.mockRestore() };
}
const post = (id: string, area?: string) => new Request("https://worker.test/v1/orders", {
  method: "POST",
  headers: { Authorization: "Bearer mocked", "Content-Type": "application/json" },
  body: JSON.stringify(orderInput(id, area)),
});


function writtenOrder(commits: Array<{ writes: Array<{ update: { name: string; fields: Fields } }> }>) {
  const w = commits[0].writes.find((x) => x.update?.name?.endsWith("/orders/" + uid + "_" + lastId));
  return w?.update.fields as Record<string, { stringValue?: string }> | undefined;
}
let lastId = "";

describe("districtFromAddress", () => {
  it("keeps only the district from the start of the address", () => {
    expect(districtFromAddress("حي السلام شارع 5 عمارة 12 الدور التالت")).toBe("حي السلام");
    expect(districtFromAddress("المعادي، شارع 9، عمارة 4")).toBe("المعادي");
    expect(districtFromAddress("مدينة نصر - عباس العقاد")).toBe("مدينة نصر");
    expect(districtFromAddress("الزقازيق ش الجلاء بجوار المسجد")).toBe("الزقازيق");
    expect(districtFromAddress("١٢ شارع التحرير")).toBe("");
    expect(districtFromAddress("   ")).toBe("");
    expect(districtFromAddress("كفر الشيخ مركز دسوق قرية محلة أبو علي القنطرة")).toBe("كفر الشيخ مركز دسوق");
    expect(districtFromAddress("ا".repeat(80)).length).toBe(40);
  });
});

describe("order area without a delivery-areas list", () => {
  it("stores the sanitized district from the app in the public order", async () => {
    const sim = simulateFirebase(null, null);
    lastId = "order_district_1234567890";
    try {
      const res = await worker.fetch(post(lastId, "حي السلام شارع 5 عمارة 12"), env);
      expect(res.status).toBe(200);
      expect(writtenOrder(sim.commits)?.area?.stringValue).toBe("حي السلام");
    } finally { sim.restore(); }
  });

  it("writes no area when the address has no district part", async () => {
    const sim = simulateFirebase(null, null);
    lastId = "order_nodistrict_1234567890";
    try {
      const res = await worker.fetch(post(lastId, "12 ش التحرير"), env);
      expect(res.status).toBe(200);
      expect(writtenOrder(sim.commits)?.area).toBeUndefined();
    } finally { sim.restore(); }
  });

  it("still requires a listed area when the admin configured delivery areas", async () => {
    const areas = { areas: { arrayValue: { values: [{ mapValue: { fields: {
      name: { stringValue: "وسط البلد" }, fee: { integerValue: "20" },
    } } }] } } };
    const rejected = simulateFirebase(null, areas);
    try {
      const bad = await worker.fetch(post("order_unlisted_1234567890", "حي السلام"), env);
      expect(bad.status).toBe(400);
      expect(rejected.commits).toHaveLength(0);
    } finally { rejected.restore(); }

    const sim = simulateFirebase(null, areas);
    lastId = "order_listed_1234567890";
    try {
      const ok = await worker.fetch(post(lastId, "وسط البلد"), env);
      expect(ok.status).toBe(200);
      expect(writtenOrder(sim.commits)?.area?.stringValue).toBe("وسط البلد");
    } finally { sim.restore(); }
  });
});
