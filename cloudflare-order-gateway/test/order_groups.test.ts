import { describe, expect, it, vi } from "vitest";

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

import worker, { courierAvailableFeedData, sanitizeCourierFeed } from "../src/index";
import {
  ORDER_GROUP_MAX_ORDERS,
  ORDER_GROUP_TTL_MS,
  OrderGroupError,
  isOrderGroupId,
  orderGroupCode,
  parseOrderGroupId,
  planOrderGroup,
} from "../src/order_groups";

const GROUP = "grp_AbCdEfGhIjKlMnOpQr12";
const now = new Date("2026-11-22T20:00:00Z");

function code(fn: () => unknown): string {
  try {
    fn();
  } catch (error) {
    if (error instanceof OrderGroupError) return `${error.status}:${error.code}`;
    throw error;
  }
  return "ok";
}

describe("order group rules (pure)", () => {
  it("accepts only the grp_ + 20 alphanumerics format; empty = not grouped", () => {
    expect(isOrderGroupId(GROUP)).toBe(true);
    expect(parseOrderGroupId(undefined)).toBe("");
    expect(parseOrderGroupId(null)).toBe("");
    expect(parseOrderGroupId("")).toBe("");
    for (const bad of ["grp_short", "grp_AbCdEfGhIjKlMnOpQr1!", "user1_grp", "GRP_AbCdEfGhIjKlMnOpQr12", 123, {}]) {
      expect(code(() => parseOrderGroupId(bad))).toBe("400:invalid_group");
    }
  });

  it("shows couriers a 6-character code only (no customer data)", () => {
    expect(orderGroupCode(GROUP)).toBe("OPQR12");
  });

  it("first order creates the group bound to the customer, with an expiry", () => {
    const plan = planOrderGroup(null, { uid: "u1", orderId: "u1_order_a", storeId: "s1", now });
    expect(plan.isNew).toBe(true);
    expect(plan.fields).toMatchObject({ userId: "u1", orderIds: ["u1_order_a"], storeIds: ["s1"], count: 1 });
    expect((plan.fields.expiresAt as Date).getTime()).toBe(now.getTime() + ORDER_GROUP_TTL_MS);
  });

  it("next order from another store joins the same group", () => {
    const first = planOrderGroup(null, { uid: "u1", orderId: "u1_order_a", storeId: "s1", now }).fields;
    const plan = planOrderGroup(first, { uid: "u1", orderId: "u1_order_b", storeId: "s2", now });
    expect(plan.isNew).toBe(false);
    expect(plan.fields).toMatchObject({ orderIds: ["u1_order_a", "u1_order_b"], storeIds: ["s1", "s2"], count: 2 });
  });

  it("rejects another customer's group, an expired group, a full group and a repeated store", () => {
    const group = planOrderGroup(null, { uid: "u1", orderId: "u1_order_a", storeId: "s1", now }).fields;
    expect(code(() => planOrderGroup(group, { uid: "intruder", orderId: "intruder_x", storeId: "s2", now })))
      .toBe("403:group_forbidden");
    const later = new Date(now.getTime() + ORDER_GROUP_TTL_MS + 1);
    expect(code(() => planOrderGroup(group, { uid: "u1", orderId: "u1_order_b", storeId: "s2", now: later })))
      .toBe("409:group_expired");
    expect(code(() => planOrderGroup(group, { uid: "u1", orderId: "u1_order_b", storeId: "s1", now })))
      .toBe("409:group_store_repeat");
    const full = {
      ...group,
      orderIds: Array.from({ length: ORDER_GROUP_MAX_ORDERS }, (_, i) => `u1_o${i}`),
      storeIds: Array.from({ length: ORDER_GROUP_MAX_ORDERS }, (_, i) => `s${i}`),
      count: ORDER_GROUP_MAX_ORDERS,
    };
    expect(code(() => planOrderGroup(full, { uid: "u1", orderId: "u1_new", storeId: "s99", now })))
      .toBe("409:group_full");
    expect(code(() => planOrderGroup({ ...group, expiresAt: "tomorrow" }, { uid: "u1", orderId: "u1_b", storeId: "s2", now })))
      .toBe("409:group_expired");
  });
});

describe("courier feed carries the group code only", () => {
  it("copies groupCode but never groupId or customer fields", () => {
    const feed = courierAvailableFeedData({
      storeId: "s1", storeName: "Store", items: [], subtotal: 10, deliveryFee: 20, total: 35,
      createdAt: now, groupId: GROUP, groupCode: "OPQR12", userId: "u1", customerName: "Ali",
    });
    expect(feed.groupCode).toBe("OPQR12");
    expect(feed.groupId).toBeUndefined();
    expect(feed.userId).toBeUndefined();
    expect(feed.customerName).toBeUndefined();
    expect(sanitizeCourierFeed({ groupId: GROUP, phone: "010" })).toEqual({});
    expect(courierAvailableFeedData({ storeId: "s1", items: [] }).groupCode).toBeUndefined();
  });
});

// ─────────── createOrder مع التجميع ───────────
const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
} as never;
const GROUP_UPDATE_TIME = "2026-11-22T19:00:00.000000Z";

const orderInput = (uid: string, id: string, extra: Record<string, unknown> = {}) => ({
  orderId: uid + "_" + id,
  storeId: "store_test",
  customerName: "Ahmed Test",
  expectedDeliveryFee: 20,
  expectedTotal: 75,
  items: [{ productId: "product_test", expectedPrice: 25, qty: 2, options: [], optionsTotal: 0 }],
  contact: { userName: "Ahmed Test", phone: "01012345678", address: "Test street address" },
  ...extra,
});

type Fields = Record<string, unknown>;
function simulate(groupFields: Fields | null, existingOrders: Record<string, Fields> = {}) {
  const commits: Array<{ writes: Array<{ update: { name: string; fields: Fields }; currentDocument?: unknown }> }> = [];
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token")) return Response.json({ access_token: "t", expires_in: 3600 });
    if (url.includes("accounts:lookup")) {
      const id = JSON.parse(String(init?.body)).localId[0];
      return Response.json({ users: [{ localId: id, validSince: "1", disabled: false }] });
    }
    if (url.endsWith("/documents:batchGet"))
      return new Response(JSON.stringify({
        found: {
          name: prefix + "stores/store_test/products/product_test",
          fields: { name: { stringValue: "Test product" }, price: { doubleValue: 25 }, available: { booleanValue: true } },
        },
      }) + "\n", { status: 200 });
    if (url.endsWith("/documents:commit")) {
      commits.push(JSON.parse(String(init?.body)));
      return Response.json({ writeResults: [] });
    }
    if (url.includes("fcm.googleapis.com/")) return Response.json({ name: "m" });
    if (url.includes("firestore.googleapis.com/")) {
      const path = decodeURIComponent(url.split("/documents/")[1]);
      if (path === "stores/store_test")
        return Response.json({ name: prefix + path, fields: { name: { stringValue: "Test store" }, active: { booleanValue: true } } });
      if (path === `order_groups/${GROUP}` && groupFields)
        return Response.json({ name: prefix + path, fields: groupFields, updateTime: GROUP_UPDATE_TIME });
      if (existingOrders[path]) return Response.json({ name: prefix + path, fields: existingOrders[path] });
      return new Response("not found", { status: 404 });
    }
    throw Error("Unexpected upstream request: " + url);
  });
  return { commits, restore: () => spy.mockRestore() };
}
const post = (uid: string, body: unknown) => new Request("https://worker.test/v1/orders", {
  method: "POST",
  headers: { Authorization: "Bearer " + uid, "Content-Type": "application/json" },
  body: JSON.stringify(body),
});
const groupFor = (owner: string, over: Fields = {}): Fields => ({
  userId: { stringValue: owner },
  orderIds: { arrayValue: { values: [{ stringValue: owner + "_first_order_123456" }] } },
  storeIds: { arrayValue: { values: [{ stringValue: "other_store" }] } },
  count: { integerValue: "1" },
  expiresAt: { timestampValue: new Date(Date.now() + 60 * 60 * 1000).toISOString() },
  ...over,
});

describe("createOrder with an optional group", () => {
  it("without groupId the order is unchanged (no group write, no group fields)", async () => {
    const sim = simulate(null);
    try {
      const res = await worker.fetch(post("u1", orderInput("u1", "plain_order_1234567890")), env);
      expect(res.status).toBe(200);
      const writes = sim.commits[0].writes;
      expect(writes).toHaveLength(3);
      expect(writes[0].update.fields.groupId).toBeUndefined();
      expect(writes[0].update.fields.groupCode).toBeUndefined();
    } finally { sim.restore(); }
  });

  it("first grouped order creates the group (exists:false) in the same commit", async () => {
    const sim = simulate(null);
    try {
      const res = await worker.fetch(post("u1", orderInput("u1", "grouped_order_1234567890", { groupId: GROUP })), env);
      expect(res.status).toBe(200);
      expect(await res.json()).toMatchObject({ groupCode: "OPQR12" });
      const writes = sim.commits[0].writes;
      expect(writes).toHaveLength(4);
      expect(writes[0].update.fields.groupId).toEqual({ stringValue: GROUP });
      expect(writes[0].update.fields.groupCode).toEqual({ stringValue: "OPQR12" });
      expect(writes[3].update.name).toBe(prefix + `order_groups/${GROUP}`);
      expect(writes[3].currentDocument).toEqual({ exists: false });
      expect(writes[3].update.fields.userId).toEqual({ stringValue: "u1" });
    } finally { sim.restore(); }
  });

  it("second order joins the customer's own group with an updateTime precondition", async () => {
    const sim = simulate(groupFor("u1"));
    try {
      const res = await worker.fetch(post("u1", orderInput("u1", "second_order_1234567890", { groupId: GROUP })), env);
      expect(res.status).toBe(200);
      const groupWrite = sim.commits[0].writes[3];
      expect(groupWrite.currentDocument).toEqual({ updateTime: GROUP_UPDATE_TIME });
      expect(groupWrite.update.fields.count).toEqual({ integerValue: "2" });
    } finally { sim.restore(); }
  });

  it("refuses to attach an order to another customer's group and writes nothing", async () => {
    const sim = simulate(groupFor("victim"));
    try {
      const res = await worker.fetch(post("intruder", orderInput("intruder", "steal_order_1234567890", { groupId: GROUP })), env);
      expect(res.status).toBe(403);
      expect(await res.json()).toMatchObject({ code: "group_forbidden" });
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("refuses an expired group, a repeated store and a malformed groupId", async () => {
    let sim = simulate(groupFor("u1", { expiresAt: { timestampValue: "2020-01-01T00:00:00Z" } }));
    try {
      const res = await worker.fetch(post("u1", orderInput("u1", "late_order_1234567890", { groupId: GROUP })), env);
      expect(res.status).toBe(409);
      expect(await res.json()).toMatchObject({ code: "group_expired" });
    } finally { sim.restore(); }
    sim = simulate(groupFor("u1", { storeIds: { arrayValue: { values: [{ stringValue: "store_test" }] } } }));
    try {
      const res = await worker.fetch(post("u1", orderInput("u1", "same_store_1234567890", { groupId: GROUP })), env);
      expect(res.status).toBe(409);
      expect(await res.json()).toMatchObject({ code: "group_store_repeat" });
    } finally { sim.restore(); }
    sim = simulate(null);
    try {
      const res = await worker.fetch(post("u1", orderInput("u1", "bad_group_1234567890", { groupId: "grp_../../admins" })), env);
      expect(res.status).toBe(400);
      expect(await res.json()).toMatchObject({ code: "invalid_group" });
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });

  it("replaying the same order id does not add it to the group twice", async () => {
    const orderId = "u1_replay_order_1234567890";
    const sim = simulate(groupFor("u1"), {
      [`orders/${orderId}`]: { userId: { stringValue: "u1" }, storeId: { stringValue: "store_test" } },
    });
    try {
      const res = await worker.fetch(post("u1", orderInput("u1", "replay_order_1234567890", { groupId: GROUP })), env);
      expect(res.status).toBe(200);
      expect(await res.json()).toMatchObject({ reused: true });
      expect(sim.commits).toHaveLength(0);
    } finally { sim.restore(); }
  });
});
