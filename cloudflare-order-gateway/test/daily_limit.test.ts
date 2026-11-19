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

import worker, {
  cairoDayKey,
  ordersCountedToday,
  resolveMaxOrdersPerDay,
} from "../src/index";

describe("daily order limit helpers", () => {
  it("uses Cairo calendar day, not UTC", () => {
    // 22:30 UTC on Nov 19 is already Nov 20 in Cairo (UTC+2 in winter).
    expect(cairoDayKey(new Date("2026-11-19T22:30:00Z"))).toBe("2026-11-20");
    expect(cairoDayKey(new Date("2026-11-19T21:30:00Z"))).toBe("2026-11-19");
    // Summer time (UTC+3): 21:30 UTC is already the next day.
    expect(cairoDayKey(new Date("2026-07-10T21:30:00Z"))).toBe("2026-07-11");
  });

  it("counts only today's orders", () => {
    expect(ordersCountedToday({ day: "2026-11-19", dailyCount: 4 }, "2026-11-19")).toBe(4);
    expect(ordersCountedToday({ day: "2026-11-18", dailyCount: 9 }, "2026-11-19")).toBe(0);
    expect(ordersCountedToday({}, "2026-11-19")).toBe(0);
    expect(ordersCountedToday({ day: "2026-11-19", dailyCount: "x" }, "2026-11-19")).toBe(0);
    expect(ordersCountedToday({ day: "2026-11-19", dailyCount: -3 }, "2026-11-19")).toBe(0);
  });

  it("resolves the limit: valid doc value, then env, then default 50", () => {
    expect(resolveMaxOrdersPerDay(5, "20")).toBe(5);
    expect(resolveMaxOrdersPerDay(undefined, "20")).toBe(20);
    expect(resolveMaxOrdersPerDay(undefined, undefined)).toBe(50);
    expect(resolveMaxOrdersPerDay("5", "20")).toBe(20); // doc value must be a number
    expect(resolveMaxOrdersPerDay(0, "20")).toBe(20);
    expect(resolveMaxOrdersPerDay(1000, undefined)).toBe(50);
    expect(resolveMaxOrdersPerDay(2.5, "abc")).toBe(50);
  });
});

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
const oldEnough = { timestampValue: "2026-01-01T00:00:00Z" }; // far in the past: passes the 20s spacing rule

describe("daily order limit in createOrder", () => {
  it("rejects the 51st order of today with code daily_limit and writes nothing", async () => {
    const today = cairoDayKey(new Date());
    const sim = simulateFirebase({
      lastAt: oldEnough, day: { stringValue: today }, dailyCount: { integerValue: "50" },
    });
    try {
      const res = await worker.fetch(post("order_over_limit_1234567890"), env);
      expect(res.status).toBe(429);
      expect(await res.json()).toMatchObject({ code: "daily_limit" });
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("accepts the 50th order and records dailyCount 50 on the same orderLimits write", async () => {
    const today = cairoDayKey(new Date());
    const sim = simulateFirebase({
      lastAt: oldEnough, day: { stringValue: today }, dailyCount: { integerValue: "49" },
    });
    try {
      const res = await worker.fetch(post("order_tenth_1234567890"), env);
      expect(res.status).toBe(200);
      expect(sim.commits).toHaveLength(1);
      const limitWrite = sim.commits[0].writes[2];
      expect(limitWrite.update.name).toBe(prefix + "orderLimits/" + uid);
      expect(limitWrite.update.fields).toMatchObject({
        day: { stringValue: today }, dailyCount: { integerValue: "50" },
      });
      // Atomic with the order: guarded by the updateTime we read.
      expect(limitWrite.currentDocument).toEqual({ updateTime: "2026-11-19T10:00:00.000000Z" });
    } finally { sim.restore(); }
  });

  it("resets the counter on a new day", async () => {
    const sim = simulateFirebase({
      lastAt: oldEnough, day: { stringValue: "2020-01-01" }, dailyCount: { integerValue: "50" },
    });
    try {
      const res = await worker.fetch(post("order_new_day_1234567890"), env);
      expect(res.status).toBe(200);
      expect(sim.commits[0].writes[2].update.fields).toMatchObject({ dailyCount: { integerValue: "1" } });
    } finally { sim.restore(); }
  });

  it("starts at 1 for a customer with no orderLimits document", async () => {
    const sim = simulateFirebase(null);
    try {
      const res = await worker.fetch(post("order_first_ever_1234567890"), env);
      expect(res.status).toBe(200);
      expect(sim.commits[0].writes[2].update.fields).toMatchObject({ dailyCount: { integerValue: "1" } });
      expect(sim.commits[0].writes[2].currentDocument).toEqual({ exists: false });
    } finally { sim.restore(); }
  });

  it("honours maxOrdersPerDay from app_info/delivery_areas", async () => {
    const today = cairoDayKey(new Date());
    const sim = simulateFirebase(
      { lastAt: oldEnough, day: { stringValue: today }, dailyCount: { integerValue: "3" } },
      { maxOrdersPerDay: { integerValue: "3" } },
    );
    try {
      const res = await worker.fetch(post("order_doc_limit_1234567890"), env);
      expect(res.status).toBe(429);
      expect(await res.json()).toMatchObject({ code: "daily_limit" });
    } finally { sim.restore(); }
  });
});
