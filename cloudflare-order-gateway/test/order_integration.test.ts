import { describe, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  jwtVerify: async () => ({
    payload: {
      sub: "integration_user",
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

const uid = "integration_user";
const orderId = uid + "_integration_order_1234567890";
const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
} as never;
const doc = (path: string, fields: Record<string, unknown>) => ({
  name: prefix + path,
  fields: Object.fromEntries(Object.entries(fields).map(([key, value]) => [
    key, typeof value === "string" ? { stringValue: value } :
      typeof value === "boolean" ? { booleanValue: value } :
      { doubleValue: value },
  ])),
});
const input = {
  orderId, storeId: "store_test", customerName: "Ahmed Test",
  expectedDeliveryFee: 20, expectedTotal: 75, // + رسوم خدمة 5
  items: [{ productId: "product_test", expectedPrice: 25, qty: 2, options: [], optionsTotal: 0 }],
  contact: { userName: "Ahmed Test", phone: "01012345678", address: "Test street address" },
};

describe("full order creation against simulated Firebase", () => {
  it("atomically saves catalog-priced order and private contact, then reuses the order ID", async () => {
    let saved = false;
    const commits: Array<{ writes: Array<{ update: { name: string; fields: Record<string, unknown> } }> }> = [];
    const upstream = vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
      const url = String(resource);
      if (url.includes("oauth2.googleapis.com/token"))
        return Response.json({ access_token: "fake-access-token", expires_in: 3600 });
      if (url.includes("accounts:lookup"))
        return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
      if (url.endsWith("/documents:batchGet"))
        return new Response(JSON.stringify({ found: doc("stores/store_test/products/product_test", {
          name: "Test product", price: 25, available: true,
        }) }) + "\n", { status: 200 });
      if (url.endsWith("/documents:commit")) {
        const body = JSON.parse(String(init?.body));
        commits.push(body);
        saved = true;
        return Response.json({ writeResults: [{}, {}, {}] });
      }
      if (url.includes("fcm.googleapis.com/"))
        return Response.json({ name: "fake-message" });
      if (url.includes("firestore.googleapis.com/")) {
        const path = url.split("/documents/")[1];
        if (path === "orders/" + orderId && saved)
          return Response.json(doc(path, { userId: uid, storeId: input.storeId }));
        if (path === "stores/store_test")
          return Response.json(doc(path, { name: "Test store", active: true }));
        return new Response("not found", { status: 404 });
      }
      throw Error("Unexpected upstream request: " + url);
    });
    try {
      const request = () => new Request("https://worker.test/v1/orders", {
        method: "POST",
        headers: { Authorization: "Bearer mocked-firebase-token", "Content-Type": "application/json" },
        body: JSON.stringify(input),
      });
      const first = await worker.fetch(request(), env);
      expect(first.status).toBe(200);
      const result = await first.json() as Record<string, unknown>;
      expect(result).toMatchObject({ orderId, subtotal: 50, deliveryFee: 20, total: 75 });
      expect(commits[0].writes[0].update.fields.serviceFee).toEqual({ integerValue: "5" });
      expect(commits).toHaveLength(1);
      expect(commits[0].writes).toHaveLength(3);
      expect(commits[0].writes[0].update.name).toBe(prefix + "orders/" + orderId);
      expect(commits[0].writes[1].update.name).toBe(prefix + "orders/" + orderId + "/private/contact");
      expect(commits[0].writes[2].update.name).toBe(prefix + "orderLimits/" + uid);
      expect(JSON.stringify(commits[0].writes[0])).not.toContain("01012345678");
      expect(JSON.stringify(commits[0].writes[1])).toContain("01012345678");
      const second = await worker.fetch(request(), env);
      expect(second.status).toBe(200);
      expect(await second.json()).toMatchObject({ orderId, reused: true });
      expect(commits).toHaveLength(1);
    } finally {
      upstream.mockRestore();
    }
  });
});


describe("reject tampered client prices without creating an order", () => {
  it("rejects forged product price and total before any Firestore commit", async () => {
    let commitCalls = 0;
    const upstream = vi.spyOn(globalThis, "fetch").mockImplementation(async (resource) => {
      const url = String(resource);
      if (url.includes("oauth2.googleapis.com/token"))
        return Response.json({ access_token: "fake-access-token", expires_in: 3600 });
      if (url.includes("accounts:lookup"))
        return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
      if (url.endsWith("/documents:batchGet"))
        return new Response(JSON.stringify({ found: doc("stores/store_test/products/product_test", {
          name: "Test product", price: 25, available: true,
        }) }) + "\n", { status: 200 });
      if (url.endsWith("/documents:commit")) {
        commitCalls++;
        return Response.json({ writeResults: [] });
      }
      if (url.includes("firestore.googleapis.com/")) {
        const path = url.split("/documents/")[1];
        if (path === "stores/store_test")
          return Response.json(doc(path, { name: "Test store", active: true }));
        return new Response("not found", { status: 404 });
      }
      throw Error("Unexpected upstream request: " + url);
    });
    try {
      const forged = {
        ...input,
        items: [{ ...input.items[0], expectedPrice: 1 }],
        expectedTotal: 27,
      };
      const result = await worker.fetch(new Request("https://worker.test/v1/orders", {
        method: "POST",
        headers: { Authorization: "Bearer mocked-firebase-token", "Content-Type": "application/json" },
        body: JSON.stringify(forged),
      }), env);
      expect(result.status).toBe(409);
      expect(commitCalls).toBe(0);
    } finally {
      upstream.mockRestore();
    }
  });
});
