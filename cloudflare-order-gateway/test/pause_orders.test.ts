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
  expectedTotal: 70,
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
const post = (id: string) => new Request("https://worker.test/v1/orders", {
  method: "POST",
  headers: { Authorization: "Bearer mocked", "Content-Type": "application/json" },
  body: JSON.stringify(orderInput(id)),
});

describe("emergency pause switch (app_info/delivery_areas.ordersPaused)", () => {
  it("rejects new orders with 503 orders_paused and writes nothing", async () => {
    const sim = simulateFirebase(null, { ordersPaused: { booleanValue: true } });
    try {
      const res = await worker.fetch(post("order_paused_1234567890"), env);
      expect(res.status).toBe(503);
      expect(await res.json()).toMatchObject({ code: "orders_paused" });
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("accepts orders when ordersPaused is false or missing", async () => {
    for (const areas of [{ ordersPaused: { booleanValue: false } }, null]) {
      const sim = simulateFirebase(null, areas);
      try {
        const res = await worker.fetch(post("order_open_" + (areas ? "f" : "n") + "_1234567890"), env);
        expect(res.status).toBe(200);
        expect(sim.commits).toHaveLength(1);
      } finally { sim.restore(); }
    }
  });
});
