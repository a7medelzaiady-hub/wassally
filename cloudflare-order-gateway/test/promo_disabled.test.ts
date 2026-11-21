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

const uid = "limit_user";
const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
} as never;
const orderInput = (id: string) => ({
  orderId: uid + "_" + id,
  storeId: "store_test",
  customerName: "Ahmed Test",
  expectedDeliveryFee: 20,
  expectedTotal: 75, // 50 أصناف + 20 توصيل + 5 رسوم خدمة (الحد الأدنى)
  items: [{ productId: "product_test", expectedPrice: 25, qty: 2, options: [], optionsTotal: 0 }],
  contact: { userName: "Ahmed Test", phone: "01012345678", address: "Test street address" },
});

type Fields = Record<string, unknown>;
function simulateFirebase() {
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
      return new Response("not found", { status: 404 });
    }
    throw Error("Unexpected upstream request: " + url);
  });
  return { commits, restore: () => spy.mockRestore() };
}
const post = (id: string, extra: Record<string, unknown> = {}) => new Request("https://worker.test/v1/orders", {
  method: "POST",
  headers: { Authorization: "Bearer mocked", "Content-Type": "application/json" },
  body: JSON.stringify({ ...orderInput(id), ...extra }),
});

describe("coupons are disabled in the Worker", () => {
  it("rejects an order that carries a promoCode and writes nothing", async () => {
    const sim = simulateFirebase();
    try {
      const res = await worker.fetch(post("order_with_promo_1234567890", { promoCode: "SAVE10" }), env);
      expect(res.status).toBe(409);
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("still accepts the same order without a promoCode", async () => {
    const sim = simulateFirebase();
    try {
      const res = await worker.fetch(post("order_no_promo_1234567890"), env);
      expect(res.status).toBe(200);
      expect(sim.commits).toHaveLength(1);
    } finally { sim.restore(); }
  });
});
