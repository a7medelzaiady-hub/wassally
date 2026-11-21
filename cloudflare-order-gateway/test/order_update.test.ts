import { describe, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  jwtVerify: async () => ({
    payload: {
      sub: "edit_user",
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

const uid = "edit_user";
const orderId = uid + "_edit_order_1234567890";
const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
} as never;

type Fields = Record<string, unknown>;
const str = (v: string) => ({ stringValue: v });
const num = (v: number) => ({ doubleValue: v });

function orderFields(overrides: Fields = {}): Fields {
  return {
    userId: str(uid),
    storeId: str("store_test"),
    status: str("new"),
    courierId: str(""),
    deliveryFee: num(20),
    subtotal: num(50),
    serviceFee: num(5),
    total: num(75),
    customerName: str("Ahmed"),
    notes: str(""),
    ...overrides,
  };
}

interface Sim {
  commits: Array<{ writes: Array<{ update: { name: string; fields: Fields }; currentDocument?: { updateTime?: string; exists?: boolean } }> }>;
  restore: () => void;
}

function simulateFirebase(opts: {
  order?: Fields | null;
  feed?: boolean;
  commitStatus?: number;
} = {}): Sim {
  const order = opts.order === undefined ? orderFields() : opts.order;
  const commits: Sim["commits"] = [];
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
          fields: { name: str("Test product"), price: num(25), available: { booleanValue: true } },
        },
      }) + "\n", { status: 200 });
    if (url.endsWith("/documents:commit")) {
      commits.push(JSON.parse(String(init?.body)));
      if (opts.commitStatus && opts.commitStatus !== 200) return new Response("conflict", { status: opts.commitStatus });
      return Response.json({ writeResults: [{}, {}, {}] });
    }
    if (url.includes("fcm.googleapis.com/")) return Response.json({ name: "fake-message" });
    if (url.includes("firestore.googleapis.com/")) {
      const path = url.split("/documents/")[1];
      if (path === "orders/" + orderId && order)
        return Response.json({ name: prefix + path, fields: order, updateTime: "2026-11-21T10:00:00.000000Z" });
      if (path === "orders/" + orderId + "/private/contact")
        return Response.json({
          name: prefix + path,
          fields: { phone: str("01099999999"), address: str("Old address") },
          updateTime: "2026-11-21T10:00:01.000000Z",
        });
      if (path === "courier_available_orders/" + orderId && opts.feed)
        return Response.json({ name: prefix + path, fields: { storeId: str("store_test") }, updateTime: "2026-11-21T10:00:02.000000Z" });
      if (path === "stores/store_test")
        return Response.json({ name: prefix + path, fields: { name: str("Test store"), active: { booleanValue: true } } });
      return new Response("not found", { status: 404 });
    }
    throw Error("Unexpected upstream request: " + url);
  });
  return { commits, restore: () => spy.mockRestore() };
}

const body = (overrides: Record<string, unknown> = {}) => ({
  customerName: "Ahmed Test",
  notes: "no onions",
  expectedTotal: 100, // 3 × 25 = 75 + 20 توصيل + 5 رسوم خدمة (الحد الأدنى)
  items: [{ productId: "product_test", expectedPrice: 25, qty: 3, options: [], optionsTotal: 0 }],
  contact: { userName: "Ahmed Test", phone: "01012345678", address: "New test street address" },
  ...overrides,
});
const patch = (payload: unknown) => new Request("https://worker.test/v1/orders/" + orderId, {
  method: "PATCH",
  headers: { Authorization: "Bearer mocked", "Content-Type": "application/json" },
  body: JSON.stringify(payload),
});

describe("PATCH /v1/orders/{id} (customer edit) against simulated Firebase", () => {
  it("saves catalog-priced totals and keeps the stored delivery fee", async () => {
    const sim = simulateFirebase();
    try {
      const res = await worker.fetch(patch(body()), env);
      expect(res.status).toBe(200);
      expect(await res.json()).toMatchObject({ subtotal: 75, deliveryFee: 20, total: 100 });
      expect(sim.commits).toHaveLength(1);
      const writes = sim.commits[0].writes;
      expect(writes).toHaveLength(2); // الطلب + بيانات التواصل الخاصة (status=new: مفيش feed)
      expect(writes[0].update.name).toBe(prefix + "orders/" + orderId);
      expect(writes[0].currentDocument?.updateTime).toBe("2026-11-21T10:00:00.000000Z");
      expect(JSON.stringify(writes[0])).not.toContain("01012345678");
      expect(JSON.stringify(writes[1])).toContain("01012345678");
    } finally { sim.restore(); }
  });

  it("ignores forged deliveryFee/status/userId/total sent in the body", async () => {
    const sim = simulateFirebase();
    try {
      const forged = body({
        deliveryFee: 0, expectedDeliveryFee: 0, status: "delivered", userId: "someone_else",
        subtotal: 1, serviceFee: 0, discount: 999, total: 1,
      });
      const res = await worker.fetch(patch(forged), env);
      expect(res.status).toBe(200);
      const fields = sim.commits[0].writes[0].update.fields;
      expect(fields.status).toEqual({ stringValue: "new" });
      expect(fields.userId).toEqual({ stringValue: uid });
      expect(fields.deliveryFee).toEqual({ integerValue: "20" });
      expect(fields.total).toEqual({ integerValue: "100" });
      expect(fields.discount).toBeUndefined();
    } finally { sim.restore(); }
  });

  it("rejects a forged expectedTotal with 409 and writes nothing", async () => {
    const sim = simulateFirebase();
    try {
      const res = await worker.fetch(patch(body({ expectedTotal: 1 })), env);
      expect(res.status).toBe(409);
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("rejects a forged item price with 409 catalog_mismatch and writes nothing", async () => {
    const sim = simulateFirebase();
    try {
      const forged = body({
        expectedTotal: 1,
        items: [{ productId: "product_test", expectedPrice: 1, qty: 3, options: [], optionsTotal: 0 }],
      });
      const res = await worker.fetch(patch(forged), env);
      expect(res.status).toBe(409);
      expect(await res.json()).toMatchObject({ code: "catalog_mismatch" });
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("refuses to edit someone else's order (403) and writes nothing", async () => {
    const sim = simulateFirebase({ order: orderFields({ userId: str("another_user") }) });
    try {
      const res = await worker.fetch(patch(body()), env);
      expect(res.status).toBe(403);
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("returns 404 for a missing order", async () => {
    const sim = simulateFirebase({ order: null });
    try {
      const res = await worker.fetch(patch(body()), env);
      expect(res.status).toBe(404);
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("refuses edits once the order moved past new/preparing or has a courier", async () => {
    for (const order of [
      orderFields({ status: str("on_the_way") }),
      orderFields({ status: str("delivered") }),
      orderFields({ status: str("cancelled") }),
      orderFields({ courierId: str("courier_1") }),
    ]) {
      const sim = simulateFirebase({ order });
      try {
        const res = await worker.fetch(patch(body()), env);
        expect(res.status).toBe(409);
        expect(sim.commits).toHaveLength(0);
      } finally { sim.restore(); }
    }
  });

  it("preparing order without its courier feed document fails closed", async () => {
    const sim = simulateFirebase({ order: orderFields({ status: str("preparing") }), feed: false });
    try {
      const res = await worker.fetch(patch(body()), env);
      expect(res.status).toBe(409);
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("preparing order updates the courier feed in the same commit", async () => {
    const sim = simulateFirebase({ order: orderFields({ status: str("preparing") }), feed: true });
    try {
      const res = await worker.fetch(patch(body()), env);
      expect(res.status).toBe(200);
      const writes = sim.commits[0].writes;
      expect(writes).toHaveLength(3);
      expect(writes[2].update.name).toBe(prefix + "courier_available_orders/" + orderId);
      expect(JSON.stringify(writes[2])).not.toContain("01012345678");
    } finally { sim.restore(); }
  });

  it("a concurrent status change (Firestore precondition 409) is reported, not swallowed", async () => {
    const sim = simulateFirebase({ commitStatus: 409 });
    try {
      const res = await worker.fetch(patch(body()), env);
      expect(res.status).toBe(409);
    } finally { sim.restore(); }
  });
});

describe("create: 20-second spacing between orders", () => {
  it("rejects a second order within 20 seconds with 429 and writes nothing", async () => {
    const commits: unknown[] = [];
    const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
      const url = String(resource);
      if (url.includes("oauth2.googleapis.com/token"))
        return Response.json({ access_token: "fake-access-token", expires_in: 3600 });
      if (url.includes("accounts:lookup"))
        return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
      if (url.endsWith("/documents:commit")) { commits.push(JSON.parse(String(init?.body))); return Response.json({ writeResults: [] }); }
      if (url.endsWith("/documents:batchGet"))
        return new Response(JSON.stringify({ found: {
          name: prefix + "stores/store_test/products/product_test",
          fields: { name: str("Test product"), price: num(25), available: { booleanValue: true } },
        } }) + "\n", { status: 200 });
      if (url.includes("firestore.googleapis.com/")) {
        const path = url.split("/documents/")[1];
        if (path === "orderLimits/" + uid)
          return Response.json({ name: prefix + path, fields: { lastAt: { timestampValue: new Date().toISOString() } }, updateTime: "2026-11-21T10:00:00.000000Z" });
        if (path === "stores/store_test")
          return Response.json({ name: prefix + path, fields: { name: str("Test store"), active: { booleanValue: true } } });
        return new Response("not found", { status: 404 });
      }
      throw Error("Unexpected upstream request: " + url);
    });
    try {
      const res = await worker.fetch(new Request("https://worker.test/v1/orders", {
        method: "POST",
        headers: { Authorization: "Bearer mocked", "Content-Type": "application/json" },
        body: JSON.stringify({
          orderId: uid + "_spacing_1234567890", storeId: "store_test", customerName: "Ahmed Test",
          expectedDeliveryFee: 20, expectedTotal: 75,
          items: [{ productId: "product_test", expectedPrice: 25, qty: 2, options: [], optionsTotal: 0 }],
          contact: { userName: "Ahmed Test", phone: "01012345678", address: "Test street address" },
        }),
      }), env);
      expect(res.status).toBe(429);
      expect(commits).toHaveLength(0);
    } finally { spy.mockRestore(); }
  });
});
