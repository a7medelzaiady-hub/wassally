import { describe, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  jwtVerify: async () => ({
    payload: {
      sub: "real_format_user",
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

import worker, { parseBatchGetResponse } from "../src/index";

const uid = "real_format_user";
const orderId = uid + "_real_format_order_1234567890";
const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "monitor",
} as never;
const productDoc = {
  name: prefix + "stores/store_test/products/product_test",
  fields: {
    name: { stringValue: "Test product" },
    price: { integerValue: "25" },
    available: { booleanValue: true },
  },
  createTime: "2026-11-20T10:00:00.000000Z",
  updateTime: "2026-11-20T10:00:00.000000Z",
};
// الشكل الحقيقي لرد Firestore REST: JSON array منسّق على أكتر من سطر.
const realBatchGetBody = JSON.stringify([
  { found: productDoc, readTime: "2026-11-21T02:30:00.000000Z" },
], null, 2);

const input = {
  orderId, storeId: "store_test", customerName: "Ahmed",
  expectedDeliveryFee: 20, expectedTotal: 75,
  items: [{ productId: "product_test", expectedPrice: 25, qty: 2, options: [], optionsTotal: 0 }],
  contact: { userName: "Ahmed", phone: "01012345678", address: "Test street address" },
};

describe("Firestore batchGet real response format", () => {
  it("parses the multi-line JSON array, a single object, NDJSON, and missing docs", () => {
    expect(parseBatchGetResponse(realBatchGetBody)[0].found?.name).toBe(productDoc.name);
    const withMissing = JSON.stringify([
      { found: productDoc, readTime: "t" },
      { missing: prefix + "stores/store_test/products/gone", readTime: "t" },
    ], null, 2);
    expect(parseBatchGetResponse(withMissing)).toHaveLength(2);
    expect(parseBatchGetResponse(JSON.stringify({ found: productDoc }))).toHaveLength(1);
    expect(parseBatchGetResponse(JSON.stringify({ found: productDoc }) + "\n" +
      JSON.stringify({ missing: "x" }) + "\n")).toHaveLength(2);
    expect(parseBatchGetResponse("")).toEqual([]);
  });

  it("garbage from upstream is a 503, not an unexpected 500", () => {
    expect(() => parseBatchGetResponse("<html>oops</html>")).toThrowError(/كتالوج/);
  });

  it("POST /v1/orders succeeds (200) when batchGet returns the real array format", async () => {
    const commits: unknown[] = [];
    const upstream = vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
      const url = String(resource);
      if (url.includes("oauth2.googleapis.com/token"))
        return Response.json({ access_token: "fake-access-token", expires_in: 3600 });
      if (url.includes("accounts:lookup"))
        return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
      if (url.endsWith("/documents:batchGet"))
        return new Response(realBatchGetBody, { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/documents:commit")) {
        commits.push(JSON.parse(String(init?.body)));
        return Response.json({ writeResults: [{}, {}, {}] });
      }
      if (url.includes("fcm.googleapis.com/")) return Response.json({ name: "m" });
      if (url.includes("firestore.googleapis.com/")) {
        const path = url.split("/documents/")[1];
        if (path === "stores/store_test")
          return Response.json({ name: prefix + path, fields: {
            name: { stringValue: "Test store" }, active: { booleanValue: true },
          } });
        return new Response("not found", { status: 404 });
      }
      throw Error("Unexpected upstream request");
    });
    try {
      const res = await worker.fetch(new Request("https://worker.test/v1/orders", {
        method: "POST",
        headers: { Authorization: "Bearer t", "Content-Type": "application/json" },
        body: JSON.stringify(input),
      }), env);
      expect(res.status).toBe(200);
      expect(await res.json()).toMatchObject({ orderId, subtotal: 50, deliveryFee: 20, total: 75 });
      expect(commits).toHaveLength(1);
    } finally {
      upstream.mockRestore();
    }
  });
});
