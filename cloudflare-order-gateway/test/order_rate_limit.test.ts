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

import worker, { assertOrderRateLimit } from "../src/index";

const uid = "limit_user";
const prefix = "projects/wasally-test/databases/(default)/documents/";
const baseEnv = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
};
const orderInput = (id: string) => ({
  orderId: uid + "_" + id,
  storeId: "store_test",
  customerName: "Ahmed Test",
  expectedDeliveryFee: 20,
  expectedTotal: 75,
  items: [{ productId: "product_test", expectedPrice: 25, qty: 2, options: [], optionsTotal: 0 }],
  contact: { userName: "Ahmed Test", phone: "01012345678", address: "Test street address" },
});

function simulateFirebase() {
  const firestoreCalls: string[] = [];
  const commits: unknown[] = [];
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token"))
      return Response.json({ access_token: "fake-access-token", expires_in: 3600 });
    if (url.includes("accounts:lookup"))
      return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
    if (url.includes("fcm.googleapis.com/")) return Response.json({ name: "fake-message" });
    if (url.includes("firestore.googleapis.com/")) {
      firestoreCalls.push(url);
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
      const path = url.split("/documents/")[1];
      if (path === "stores/store_test")
        return Response.json({ name: prefix + path, fields: { name: { stringValue: "Test store" }, active: { booleanValue: true } } });
      return new Response("not found", { status: 404 });
    }
    throw Error("Unexpected upstream request: " + url);
  });
  return { firestoreCalls, commits, restore: () => spy.mockRestore() };
}

const post = (id: string) => new Request("https://worker.test/v1/orders", {
  method: "POST",
  headers: { Authorization: "Bearer mocked", "Content-Type": "application/json" },
  body: JSON.stringify(orderInput(id)),
});
const patch = () => new Request("https://worker.test/v1/orders/" + uid + "_order_edit_1234567890", {
  method: "PATCH",
  headers: { Authorization: "Bearer mocked", "Content-Type": "application/json" },
  body: JSON.stringify({ ...orderInput("order_edit_1234567890"), notes: "x" }),
});

describe("per-customer order rate limit (protects the Spark read/write quota)", () => {
  it("rejects create with 429 rate_limited before ANY Firestore call", async () => {
    const sim = simulateFirebase();
    const keys: string[] = [];
    const limiter = { limit: async ({ key }: { key: string }) => { keys.push(key); return { success: false }; } };
    try {
      const res = await worker.fetch(post("order_limited_1234567890"), { ...baseEnv, ORDER_RATE_LIMITER: limiter } as never);
      expect(res.status).toBe(429);
      expect(await res.json()).toMatchObject({ code: "rate_limited" });
      expect(keys).toEqual(["order:" + uid]);
      expect(sim.firestoreCalls).toHaveLength(0);
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("rejects edit (PATCH) with 429 rate_limited before ANY Firestore call", async () => {
    const sim = simulateFirebase();
    const limiter = { limit: async (_: { key: string }) => ({ success: false }) };
    try {
      const res = await worker.fetch(patch(), { ...baseEnv, ORDER_RATE_LIMITER: limiter } as never);
      expect(res.status).toBe(429);
      expect(await res.json()).toMatchObject({ code: "rate_limited" });
      expect(sim.firestoreCalls).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("still accepts a normal order when the limiter allows it", async () => {
    const sim = simulateFirebase();
    const limiter = { limit: async (_: { key: string }) => ({ success: true }) };
    try {
      const res = await worker.fetch(post("order_allowed_1234567890"), { ...baseEnv, ORDER_RATE_LIMITER: limiter } as never);
      expect(res.status).toBe(200);
      expect(sim.commits).toHaveLength(1);
    } finally { sim.restore(); }
  });

  it("fails open when the limiter itself throws or is not configured", async () => {
    for (const limiter of [
      { limit: async (_: { key: string }) => { throw new Error("limiter down"); } },
      undefined,
    ]) {
      const sim = simulateFirebase();
      try {
        const res = await worker.fetch(post("order_open_" + (limiter ? "t" : "u") + "_1234567890"),
          { ...baseEnv, ...(limiter ? { ORDER_RATE_LIMITER: limiter } : {}) } as never);
        expect(res.status).toBe(200);
        expect(sim.commits).toHaveLength(1);
      } finally { sim.restore(); }
    }
  });

  it("assertOrderRateLimit: no limiter resolves; denied limiter throws 429", async () => {
    await expect(assertOrderRateLimit(undefined, uid)).resolves.toBeUndefined();
    await expect(assertOrderRateLimit({ limit: async () => ({ success: false }) }, uid))
      .rejects.toMatchObject({ status: 429, code: "rate_limited" });
  });
});
